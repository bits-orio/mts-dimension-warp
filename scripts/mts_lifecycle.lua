-- scripts/mts_lifecycle.lua
--
-- Wires MTS Dimension Warp to the MTS team lifecycle via the mts-v1 remote
-- interface:
--   on_team_created  -> create the team's warp context (the bundle in
--                       storage.teams[force_name]); the platform/entity bootstrap
--                       and home-surface adoption land in a later phase.
--   on_team_released -> tear the team's warp context down.
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
--- Handlers
------------------------------------------------------------
-- MTS payloads (verified against MTS remote_api.lua raise_* functions):
--   on_team_created  : { force_name, player_index }
--   on_team_released : { force_name }

local function on_team_created(event)
    local force_name = event.force_name
    if not force_name then return end
    -- Initialize the per-team bundle. Platform/entity bootstrap and adoption of
    -- the MTS home surface (warp #0) are wired in a later phase.
    dw.create_warp_ctx(force_name)
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
            on_team_created  = remote.call("mts-v1", "get_event_id", "on_team_created"),
            on_team_released = remote.call("mts-v1", "get_event_id", "on_team_released"),
        }
    end
    mts_lifecycle.register()
end

return mts_lifecycle
