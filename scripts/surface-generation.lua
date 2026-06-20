--- Surface generation and randomization
------------------------------------------------------------
require "scripts.planets.neo-nauvis"
if script.active_mods['space-age'] then
    require "scripts.planets.fulgora"
    require "scripts.planets.gleba"
    require "scripts.planets.vulcanus"
    require "scripts.planets.aquilo"
end

-- Apply the docked-in-space "stasis" look to a dock surface: a dim frozen daytime
-- and a faint cold indigo wash over the floor + void (cold, dim, dead-still -- the
-- grilled spec). Dim but legible, so the parked base stays inspectable. Idempotent:
-- it destroys any prior wash first, so re-freezing a dock (after an interrupted
-- resume) never stacks rectangles. Stores the render id on ctx.warp.dock_tint_id so
-- the resume "wake from stasis" beat (dock_timer) can clear it. Tune colour/alpha
-- live in-game.
function dw.apply_dock_stasis(surface, ctx)
    if not (surface and surface.valid) then return end
    if ctx.warp.dock_tint_id then
        local old = rendering.get_object_by_id(ctx.warp.dock_tint_id)
        if old and old.valid then old.destroy() end
        ctx.warp.dock_tint_id = nil
    end
    surface.daytime = 0.35   -- cold "frozen" evening; dock_wake darkens this to the black night on resume
    surface.freeze_daytime = true
    -- Remove the planet's night-light floor (default 0.15) so that when dock_wake
    -- darkens the sky to midnight the dock reads as a pure-black starfield, not a
    -- bluish neo-nauvis night. The dock surface is retired at warp, so this never
    -- leaks to the destination.
    surface.min_brightness = 0
    local r = (ctx.platform.warp.size / 32 + 2) * 32
    local tint = rendering.draw_rectangle{
        color = {r = 0.10, g = 0.07, b = 0.22, a = 0.22},   -- cold indigo/violet
        filled = true, draw_on_ground = true,
        left_top = {-r, -r}, right_bottom = {r, r},
        surface = surface,
    }
    ctx.warp.dock_tint_id = tint and tint.id or nil
    dw.diag("apply_dock_stasis surface=%s daytime=%.3f min_brightness=%.3f tint_id=%s",
        surface.name, surface.daytime, surface.min_brightness, tostring(ctx.warp.dock_tint_id))
end

local function force_map_settings()
    game.map_settings.pollution.enabled = true
    game.map_settings.pollution.diffusion_ratio = 0.105
    game.map_settings.pollution.min_to_diffuse = 15
    game.map_settings.pollution.ageing = 1.0
    game.map_settings.pollution.expected_max_per_chunk = 250
    game.map_settings.pollution.min_to_show_per_chunk = 50
    game.map_settings.pollution.pollution_restored_per_tree_damage = 9
    game.map_settings.pollution.enemy_attack_pollution_consumption_modifier = 1.0

    game.map_settings.enemy_evolution.enabled = true --
    game.map_settings.enemy_evolution.time_factor = 0.000006 -- default 0.000004
    game.map_settings.enemy_evolution.destroy_factor = 0.0002 -- default 0.002
    game.map_settings.enemy_evolution.pollution_factor = 0.0000005 -- default 0.0000009

    game.map_settings.unit_group.min_group_gathering_time = 600
    game.map_settings.unit_group.max_group_gathering_time = 2 * 600
    game.map_settings.unit_group.max_unit_group_size = 200
    game.map_settings.unit_group.max_wait_time_for_late_members = 2 * 360

    game.map_settings.enemy_expansion.enabled = true
    game.map_settings.enemy_expansion.settler_group_min_size = 1
    game.map_settings.enemy_expansion.settler_group_max_size = 1
end

------------------------------------------------------------
--- Deterministic fairness seed (ADR-0005)
------------------------------------------------------------
-- A warp world's seed is a PURE function of (map_seed, planet, warp_number) with
-- no team identity, so any two teams that reach the same planet at the same warp
-- number face the byte-identical world. This replaces stock DW's per-warp
-- randomization (math.random + game.tick), which is unacceptable for MTS's
-- competitive races. math.random / game.tick anywhere on this path is a bug --
-- it breaks both fairness and save reproducibility.

-- The host's chosen map seed. nauvis always exists, and its seed equals the
-- game's chosen map seed (same source MTS uses in surface_utils.seed_for_base).
local function map_seed()
    local nauvis = game.surfaces["nauvis"]
    return (nauvis and nauvis.valid) and nauvis.map_gen_settings.seed or 0
end

-- Sum the byte codes of a string into the mix. Cheap, order-sensitive, and
-- deterministic across peers (no hashing libs, no engine state).
local function fold_string(acc, s)
    for i = 1, #s do
        acc = (acc * 31 + s:byte(i)) % 4294967296 -- mod 2^32 to stay in range
    end
    return acc
end

-- hash(map_seed, planet, warp_number) -> uint32. A small deterministic mixer:
-- fold the map seed, the planet name, and the warp number together. No
-- randomness, no tick -- identical inputs always yield the identical seed.
local function fairness_seed(planet, warp_number)
    local acc = map_seed() % 4294967296
    acc = fold_string(acc, tostring(planet))
    acc = (acc * 31 + warp_number) % 4294967296
    -- final avalanche so adjacent warp numbers don't yield adjacent seeds
    acc = (acc * 2654435761) % 4294967296
    return math.floor(acc)
end

------------------------------------------------------------
--- Per-team surface generation (MTS owns birth/death -- ADR-0004)
------------------------------------------------------------
-- generate_surface(force_name, ctx, target): advance ONE team to its next warp
-- surface. MTS is the sole surface authority: MDW asks MTS to create the next
-- surface and to retire the previous one; MDW only supplies the per-planet
-- map_gen knowledge and the deterministic seed.
--
-- DIVERGENCE from upstream: upstream created/deleted surfaces itself
-- (game.create_surface / game.delete_surface) and randomized per warp. Here
-- create_team_surface / retire_team_surface (mts-v1) own that, and the seed is
-- the deterministic fairness seed above.
--
-- Guard: only run for a real team ctx. The excluded lab-intro scenario still
-- calls the old signature dw.generate_surface('neo-nauvis', true) at on_init;
-- the lab intro is disabled under MTS (the team starts on its adopted dimension
-- home), so that stale call must be a safe no-op rather than a crash.
-- Returns true when the team advanced to a valid new surface, false otherwise
-- (so the caller can skip the platform clone + retire on a failed create).
local function generate_surface(force_name, ctx, target)
    if type(force_name) ~= "string" then return false end
    if type(ctx) ~= "table" or not ctx.warp then return false end
    if not (game.forces[force_name] and game.forces[force_name].valid) then return false end

    force_map_settings()

    local planet = target
    if not planet or not game.planets[planet] then
        planet = "nauvis"
    end

    -- Compute the per-planet map_gen and pin the deterministic fairness seed.
    -- The next warp number is the one we are about to land on.
    --
    -- Space Age supplies per-planet map_gen via the planet prototype. Without it
    -- only nauvis exists, so fall back to the live nauvis surface's settings (the
    -- host-chosen base settings -- the same source map_seed() reads). Deep-copy so
    -- pinning our seed never mutates the shared prototype/surface settings table.
    local next_number = ctx.warp.number + 1
    local planet_proto = game.planets[planet] and game.planets[planet].prototype
    local base_mapgen = (planet_proto and planet_proto.map_gen_settings)
        or game.surfaces.nauvis.map_gen_settings
    local mapgen = table.deepcopy(base_mapgen)
    mapgen.seed = fairness_seed(planet, next_number)

    dw.diag("generate_surface force=%s planet=%s next_number=%d seed=%d",
        force_name, planet, next_number, mapgen.seed)

    -- Create the new surface FIRST, BEFORE advancing ctx.warp.current. This is
    -- critical: create_team_surface synchronously fires on_team_surface_created,
    -- and MDW's adoption handler only skips when ctx.warp.current.surface is set.
    -- If we blanked current before the create, the brand-new warp surface would
    -- be wrongly re-adopted as warp #0 (resetting the warp number AND leaving the
    -- previous/current pair pointed at the same surface -> clone_area collide).
    -- Keeping current pointed at the team's existing surface during the create
    -- makes the adoption correctly skip it.
    --
    -- The name MUST be NON-VARIANT (not mts-<planet>-N / team-N-<planet>) so MTS's
    -- normalize_variant_seed honors our deterministic seed. 'mdw-<planet>-w<N>' is
    -- unique per (planet, warp) and never matches a variant pattern -- NO
    -- post-create re-pin is needed (ADR-0005 fairness holds from birth).
    local surface_name = remote.call("mts-v1", "create_team_surface", force_name, {
        name             = 'mdw-' .. planet .. '-w' .. next_number,
        planet           = planet,
        map_gen_settings = mapgen,
    })
    dw.diag("generate_surface force=%s create_team_surface returned %s",
        force_name, tostring(surface_name))
    local surface = surface_name and game.surfaces[surface_name]
    if not (surface and surface.valid) then
        dw.diag("generate_surface force=%s CREATE FAILED (planet=%s next_number=%d) -- not advancing",
            force_name, planet, next_number)
        return false  -- create failed; nothing advanced, caller drops back to awaiting
    end

    -- Create succeeded: NOW advance. previous = the surface we are leaving,
    -- current = the freshly created one (distinct surfaces -> clone is valid).
    ctx.warp.previous = ctx.warp.current
    ctx.warp.number   = next_number
    ctx.warp.current  = {
        name          = surface.name,
        planet        = planet,
        surface       = surface,
        surface_index = surface.index,
    }

    dw.diag("generate_surface force=%s ADVANCED warp #%d -> previous=%s current=%s",
        force_name, next_number,
        dw.diag_surface(ctx.warp.previous and ctx.warp.previous.surface),
        dw.diag_surface(ctx.warp.current.surface))

    surface.localised_name = game.planets[planet].prototype.localised_name

    -- Route this surface's engine events back to the owning team in O(1).
    dw.set_surface_owner(surface.index, force_name)

    dw.rampant.check_surface_processed(surface)
    surface.request_to_generate_chunks({x = 0, y = 0}, ctx.platform.warp.size / 32 + 1)
    surface.force_generate_chunk_requests()
    return true
end
dw.generate_surface = generate_surface

------------------------------------------------------------
--- On-demand safe DOCK surface (P2 docking bay -- ADR-0006)
------------------------------------------------------------
-- Created when a team's warp fires with NO member online: the platform parks
-- here, frozen via MTS pause, until a member resumes. Created on demand and
-- retired on resume, so only currently-docked teams cost a surface (the user's
-- surface-budget concern). SAFE by construction -- enemies disabled + peaceful
-- mode -- because the docked base is powerless (turrets off) and must not be
-- attackable. Name "mdw-<force>-dock" is NON-VARIANT (dodges clone_mirror) and
-- stable per team (a team docks at most once at a time).
--
-- Advances ctx.warp.current to the dock but does NOT advance ctx.warp.number:
-- the dock DEFERS the warp; the real Arrive (and the number bump) happen when
-- the team resumes and warps out to ctx.warp.pending_destination.
local function generate_dock_surface(force_name, ctx)
    if type(ctx) ~= "table" or not ctx.warp then return false end
    if not (game.forces[force_name] and game.forces[force_name].valid) then return false end

    local base_mapgen = (game.planets["neo-nauvis"] and game.planets["neo-nauvis"].prototype.map_gen_settings)
        or game.surfaces.nauvis.map_gen_settings
    local mapgen = table.deepcopy(base_mapgen)
    mapgen.autoplace_controls = mapgen.autoplace_controls or {}
    mapgen.autoplace_controls["enemy-base"] = { frequency = 0, size = 0, richness = 0 }
    mapgen.peaceful_mode = true
    mapgen.seed = map_seed()   -- deterministic: the dock is identical for all teams

    -- Docked-in-space look: generate the dock as the dimension-space STARFIELD (the
    -- same void our dimension floors float in), not neo-nauvis planet terrain -- so
    -- the parked base reads as floating in space, not parked on dirt.
    mapgen.autoplace_settings = mapgen.autoplace_settings or {}
    mapgen.autoplace_settings.tile = { treat_missing_as_default = false, settings = { ["dimension-space"] = {} } }

    -- Unique per dock cycle: ctx.warp.number is stable while docked (docking does
    -- not bump it) and increments after each resume warp, so successive docks get
    -- distinct names -- a fresh dock can never alias the PREVIOUS dock that is
    -- still being deleted asynchronously (game.delete_surface is deferred).
    local dock_name = "mdw-" .. force_name .. "-dock-w" .. ctx.warp.number
    dw.diag("generate_dock_surface force=%s name=%s", force_name, dock_name)
    local surface_name = remote.call("mts-v1", "create_team_surface", force_name, {
        name             = dock_name,
        planet           = "neo-nauvis",
        map_gen_settings = mapgen,
    })
    local surface = surface_name and game.surfaces[surface_name]
    if not (surface and surface.valid) then
        dw.diag("generate_dock_surface force=%s CREATE FAILED", force_name)
        return false
    end

    ctx.warp.previous = ctx.warp.current   -- the team's old (real) world, retired next
    ctx.warp.current  = {
        name          = surface.name,
        planet        = "neo-nauvis",
        surface       = surface,
        surface_index = surface.index,
    }
    ctx.warp.dock_surface_name  = surface.name
    ctx.warp.dock_surface_index = surface.index

    dw.set_surface_owner(surface.index, force_name)
    surface.request_to_generate_chunks({x = 0, y = 0}, ctx.platform.warp.size / 32 + 1)
    surface.force_generate_chunk_requests()

    -- Cold, dim, dead-still cosmic mood, distinct from the active floors (the
    -- grilled docked-in-space spec). Cleared on resume for the "wake from stasis"
    -- beat (dock_timer), restored if the resume is interrupted (refreeze_dock).
    dw.apply_dock_stasis(surface, ctx)

    dw.diag("generate_dock_surface force=%s DOCKED current=%s (number unchanged=%d)",
        force_name, dw.diag_surface(surface), ctx.warp.number)
    return true
end
dw.generate_dock_surface = generate_dock_surface

------------------------------------------------------------
--- Previous-surface retirement (replaces game.delete_surface)
------------------------------------------------------------
-- After the platform has been cloned onto the new surface, retire the old one
-- through MTS (the single grounded deletion path -- ADR-0004). Forgets the
-- surface-index mapping too so the reverse map stays accurate.
--
-- DIVERGENCE: upstream's update_surfaces_properties() deleted the previous
-- surface itself (game.delete_surface) and re-associated nauvis to its planet.
-- Under MTS those concerns belong to retire_team_surface. The CORE path
-- (warp.lua prepare_warp_to_next_surface) calls this directly with (force_name,
-- ctx) right after the platform clone.
local function update_surfaces_properties(force_name, ctx)
    -- The excluded aux teleport_platform (scripts/platforms/surface.lua) also
    -- still calls dw.update_surfaces_properties() with NO args at the end of its
    -- clone. That stale call is a safe no-op (guard below) -- the EXPECTED
    -- stale-aux divergence for v1; CORE drives the real retire with real args.
    if type(ctx) ~= "table" or not ctx.warp then return "noctx" end
    if ctx.warp.status ~= defines.warp.warping then return "notwarping" end

    local previous = ctx.warp.previous
    local result = "none"
    if previous and previous.surface and previous.surface.valid then
        dw.diag("update_surfaces_properties force=%s retiring previous=%s",
            force_name, dw.diag_surface(previous.surface))
        dw.clear_surface_owner(previous.surface.index)
        local retired = remote.call("mts-v1", "retire_team_surface", force_name, previous.name)
        if retired then
            result = "retired"
        else
            -- MTS no longer owns the surface (e.g. its ownership was wiped by a
            -- historical mod-update bug), so retire_team_surface refuses to delete
            -- it and returns false -- leaving it disowned AND undeleted, i.e. a
            -- permanent orphan still holding the cloned base and a pollution chunk
            -- disk. We KNOW this is our own previous surface, so delete it directly.
            if previous.surface.valid then game.delete_surface(previous.surface) end
            result = "deleted_fallback"
        end
        dw.diag("update_surfaces_properties force=%s retire_team_surface(%s) -> %s (%s)",
            force_name, previous.name, tostring(retired), result)
    else
        dw.diag("update_surfaces_properties force=%s no valid previous surface to retire",
            force_name)
    end
    ctx.warp.previous = nil
    ctx.warp.status = defines.warp.awaiting
    return result
end
dw.update_surfaces_properties = update_surfaces_properties

------------------------------------------------------------
--- Orphaned-dock cleanup (repairs saves leaked by the historical bug)
------------------------------------------------------------
-- A dock surface only ever belongs to ONE team at a time (the team currently
-- parked on it). A dock that is no longer referenced by ANY team's warp ctx is
-- an orphan -- the dock-retire-after-ownership-wipe bug (see
-- update_surfaces_properties above) could leave such a surface disowned AND
-- undeleted, leaking its cloned base and pollution chunk disk forever.
--
-- This deletes every 'mdw-team-N-dock-wM' surface NOT referenced by a live team
-- ctx. It is conservative: it only touches dock surfaces, and only ones absent
-- from the live set (current / previous / dock_surface_name / platform floors of
-- every team in storage.teams). Returns (count, names).
--
-- @param live_override table|nil  test seam: a {surface_name=true} set to use
--                                 instead of computing from storage.teams.
-- @param pattern       string|nil test seam: Lua pattern of surface names to
--                                 consider (default all mdw team dock surfaces).
function dw.cleanup_orphan_dock_surfaces(live_override, pattern)
    pattern = pattern or "^mdw%-team%-%d+%-dock%-w"
    local live = live_override
    if not live then
        live = {}
        local function add(n) if type(n) == "string" then live[n] = true end end
        for _, ctx in pairs(storage.teams or {}) do
            if ctx.warp then
                add(ctx.warp.current and ctx.warp.current.name)
                add(ctx.warp.previous and ctx.warp.previous.name)
                add(ctx.warp.dock_surface_name)
            end
            if ctx.platform then
                for _, role in ipairs({"factory", "mining", "power"}) do
                    local p = ctx.platform[role]
                    if p and p.surface and p.surface.valid then add(p.surface.name) end
                end
            end
        end
    end

    local names = {}
    for _, s in pairs(game.surfaces) do
        if s.valid and s.name:find(pattern) and not live[s.name] then
            names[#names + 1] = s.name
            dw.clear_surface_owner(s.index)
            game.delete_surface(s)
        end
    end
    dw.diag("cleanup_orphan_dock_surfaces: deleted %d orphan dock surface(s)%s",
        #names, #names > 0 and (" -> " .. table.concat(names, ", ")) or "")
    return #names, names
end
