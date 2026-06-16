-- scripts/mts_lifecycle.lua
--
-- Wires MTS Dimension Warp to the MTS team lifecycle via the mts-v1 remote
-- interface:
--   on_team_created        -> create the team's warp context (the bundle in
--                             storage.teams[force_name]).
--   on_team_surface_created -> adopt the team's FIRST surface as warp #0 and lay
--                             the dimension-space platform onto it (ADR-0004).
--   on_team_clock_started  -> arm the team's warp timer (no warp happens yet --
--                             the warp loop itself is a later slice).
--   on_team_released       -> tear the team's warp context down.
--
-- Subscription pattern (multiplayer-safe -- see the MTS event-subscription
-- reference): the event ids come from script.generate_event_name() inside MTS,
-- so they must be fetched with remote.call("mts-v1","get_event_id",name). That
-- call is illegal in the control.lua main chunk and in on_load, so:
--   * setup()    : on_init / on_configuration_changed only -- remote.call the
--                  ids and CACHE them in storage, then register the handlers.
--   * register() : on_init / on_load / on_configuration_changed -- re-attach the
--                  handlers from the cached ids (NO remote.call).
-- Registering from cached ids in all three hooks keeps the handler set identical
-- on every peer the instant on_load finishes, so a client joining mid-game is
-- not rejected. (A deferred one-shot on_nth_tick would make the handler sets
-- diverge between a long-running server and a fresh client -- the bug this
-- pattern exists to avoid.)

dw = dw or {}

local mts_lifecycle = {}

------------------------------------------------------------
--- Adoption helpers (warp #0 bootstrap)
------------------------------------------------------------
-- Lay the dimension-space platform tiles onto the adopted home surface.
--
-- v1 CORE port: this only paints the floor. The warp GATE, harvesters, stairs
-- and the rest of the platform furniture are aux subsystems (scripts/platforms/*,
-- scripts/entities/*) and are NOT placed here.
--
-- The platform SIZE is read from ctx.platform.warp.size as a fixed value.
-- DIVERGENCE from upstream: the size-growing tech (update_warp_platform_size)
-- lives in excluded aux code, so the platform never grows in v1 -- it stays at
-- the default first-tier size the context was seeded with.
--
-- Tile shape mirrors the upstream dimension-space fill in
-- scripts/surface-generation.lua (nested floor..ceil loop -> set_tiles).
local function lay_warp_platform_tiles(ctx, surface)
    local size = ctx.platform.warp.size
    local area = math2d.bounding_box.create_from_centre({0, 0}, size, size)

    local tiles = {}
    for x = math.floor(area.left_top.x), math.ceil(area.right_bottom.x) - 1 do
        for y = math.floor(area.left_top.y), math.ceil(area.right_bottom.y) - 1 do
            table.insert(tiles, {name = "dimension-space", position = {x, y}})
        end
    end
    surface.set_tiles(tiles)
end

------------------------------------------------------------
--- Handlers
------------------------------------------------------------
-- MTS payloads (verified against MTS remote_api.lua raise_* functions):
--   on_team_created         : { force_name, player_index }
--   on_team_surface_created : { surface_name, force_name }
--   on_team_clock_started   : { force_name, start_tick }
--   on_team_released        : { force_name }

local function on_team_created(event)
    local force_name = event.force_name
    if not force_name then return end
    -- Initialize the per-team bundle. Warp #0 adoption and the timer arm on the
    -- on_team_surface_created / on_team_clock_started events below.
    dw.create_warp_ctx(force_name)
end

-- Adopt a team's FIRST surface as warp #0. MTS owns surface birth (ADR-0004);
-- this event fires for EVERY surface the team gains, including MDW's own later
-- warp surfaces -- so the guard is: only adopt when the team's warp.current is
-- still empty. Once warp #0 is set, later surface-created events are ignored.
local function on_team_surface_created(event)
    local force_name, surface_name = event.force_name, event.surface_name
    if not force_name or not surface_name then return end
    if not dw.has_warp_ctx(force_name) then return end -- not an MDW-tracked team

    local ctx = dw.warp_ctx(force_name)
    if ctx.warp.current.surface then return end -- already adopted warp #0

    local surface = game.surfaces[surface_name]
    if not surface or not surface.valid then return end

    -- warp.current shape mirrors generate_surface(): {name, planet, surface,
    -- surface_index}. planet is a STRING name (surface.planet is the LuaPlanet).
    ctx.warp.current = {
        name          = surface.name,
        -- Always a non-nil string: consumers (gui space-location label, seed)
        -- concatenate it. A non-planet home surface defaults to nauvis.
        planet        = surface.planet and surface.planet.name or "nauvis",
        surface       = surface,
        surface_index = surface.index,
    }
    ctx.warp.number = 0

    -- Skip the disabled single-team lab intro: the team starts ON its dimension
    -- home, not on a nauvis lab that has to explode first.
    ctx.nauvis_lab_exploded = true

    -- Route this surface's engine events back to the owning team in O(1).
    dw.set_surface_owner(surface.index, force_name)

    -- Paint the platform floor (no gate -- that is aux).
    lay_warp_platform_tiles(ctx, surface)
end

-- Mirror of warp.lua's calculate_manual_warp_time(), reading from the per-team
-- context instead of the flat globals. Kept in lockstep with the upstream
-- formula (base 10s + scaled warp-zone term, capped at the configured max).
local function calculate_manual_warp_time(ctx)
    local base_time = 10 -- seconds
    local max_time = settings.global['dw-manual-warp-max-time'].value * 60
    local warp_zone = math.floor(ctx.warp.number * settings.global['dw-manual-warp-zone-multiplier'].value)
    return math.min(max_time, math.floor(base_time + warp_zone ^ 1.35))
end

-- Arm the team's warp timer when MTS starts its clock. No warp is performed yet
-- (the warp loop is a later slice); this only seeds the countdown state so the
-- loop has something to tick down once it lands.
local function on_team_clock_started(event)
    local force_name = event.force_name
    if not force_name then return end
    if not dw.has_warp_ctx(force_name) then return end

    local ctx = dw.warp_ctx(force_name)
    ctx.timer.active = true
    ctx.timer.warp = ctx.timer.base
    ctx.timer.manual_warp = calculate_manual_warp_time(ctx)
end

local function on_team_released(event)
    local force_name = event.force_name
    if not force_name then return end
    -- Drop the bundle and forget the team's surface-index mappings. MTS has
    -- already deleted the surfaces themselves.
    dw.destroy_warp_ctx(force_name)
end

------------------------------------------------------------
--- Registration (no remote.call -- safe in on_init/on_load/on_config)
------------------------------------------------------------
-- Re-attach the handlers from the event ids cached in storage. Idempotent and
-- deterministic, so every peer ends up with the same handler set.
function mts_lifecycle.register()
    local ids = storage.mts_event_ids
    if not ids then return end
    if ids.on_team_created then
        script.on_event(ids.on_team_created, on_team_created)
    end
    if ids.on_team_surface_created then
        script.on_event(ids.on_team_surface_created, on_team_surface_created)
    end
    if ids.on_team_clock_started then
        script.on_event(ids.on_team_clock_started, on_team_clock_started)
    end
    if ids.on_team_released then
        script.on_event(ids.on_team_released, on_team_released)
    end
end

------------------------------------------------------------
--- Setup (remote.call -- on_init/on_configuration_changed only)
------------------------------------------------------------
-- Fetch and cache the mts-v1 event ids, then register. The ids can shift only
-- when the mod set changes, which is exactly when on_configuration_changed
-- fires -- so re-fetching here keeps them current.
function mts_lifecycle.setup()
    local iface = remote.interfaces["mts-v1"]
    if iface and iface.get_event_id then
        storage.mts_event_ids = {
            on_team_created         = remote.call("mts-v1", "get_event_id", "on_team_created"),
            on_team_surface_created = remote.call("mts-v1", "get_event_id", "on_team_surface_created"),
            on_team_clock_started   = remote.call("mts-v1", "get_event_id", "on_team_clock_started"),
            on_team_released        = remote.call("mts-v1", "get_event_id", "on_team_released"),
        }
    end
    mts_lifecycle.register()
end

return mts_lifecycle
