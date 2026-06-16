-- scripts/warp_ctx.lua
--
-- Per-team warp context: the storage.teams[force_name] keystone.
--
-- MTS Dimension Warp is a fork of single-team Dimension Warp. Upstream kept all
-- warp state in flat globals (storage.warp, storage.timer, storage.platform, ...);
-- here every one of those is per-team and lives inside a single bundle keyed by
-- the team's force name. warp_ctx(force_name) is the lazy accessor that returns
-- (creating on first call) that bundle.
--
-- A reverse surface_index -> force_name map (storage.surface_index_to_force)
-- lets surface-scoped engine events (on_surface_deleted, pollution, generation)
-- route to the owning team's context in O(1). Without it, those events cannot be
-- attributed to a team. MTS owns the surfaces; this map only records which team
-- each surface currently belongs to.
--
-- FOUNDATION ONLY: this module defines the shape, the accessor, and teardown.
-- The singleton consumers in warp.lua, gui.lua, etc. are NOT rewritten yet --
-- that mechanical pass lands in a later phase.

dw = dw or {}

local warp_ctx_lib = {}

------------------------------------------------------------
--- Default bundle shape
------------------------------------------------------------
-- Builds a fresh per-team bundle. Field meanings and defaults mirror the flat
-- globals the upstream mod used in control.lua's set_globals(), so consumers can
-- be ported field-for-field later. Every value is freshly constructed per call
-- (no shared sub-tables between teams) to avoid cross-team pollution.
local function new_ctx()
    return {
        -- player_name -> bool: collected the cheat bag on this team's base
        cheat_bag = {},

        -- team finished stabilize-dimensions research and stopped warping
        victory = false,

        -- GUI state (item watchdogs + planet selector)
        gui = {
            item_watch = {},
            watchdogs = {[1] = true, [2] = true, [3] = true},
            count_watchdogs = 3,
            count_watched_item = 0,
            item_list = {},
            planet_selector_enabled = false,
            planet_selector_list = {},
        },

        -- platform sizes + their surfaces
        platform = {
            warp    = {size = dw.platform_size.warp[1]},
            factory = {size = 0, surface = nil},
            mining  = {size = {x = 0, y = 0}, surface = nil},
            power   = {size = 0, water = false, surface = nil},
        },

        -- warp state machine
        warp = {
            number = 0,
            current = {},
            previous = nil,
            status = defines.warp.awaiting,
            time = game.tick,
            preferred_destination = nil,
        },

        -- timers are in seconds, not ticks
        timer = {
            active = false,
            base = 20 * 60, -- 20 min auto-warp
            warp = nil,         -- countdown to the next warp
            manual_warp = nil,  -- player-vote warp countdown
        },

        -- warp voting
        votes = {
            count = 0,
            players = {},
            min_vote = 1,
            players_count = 0,
        },

        -- 13 fixed teleporter routes between this team's surfaces
        teleporter = {
            ['warp-to-factory']            = {active = false},
            ['factory-to-warp']            = {active = false},
            ['mining-to-factory']          = {active = false},
            ['factory-to-mining']          = {active = false},
            ['power-to-mining']            = {active = false},
            ['mining-to-power']            = {active = false},
            ['nauvis-gate']                = {active = false},
            ['warp-gate-to-surface']       = {active = false},
            ['harvester-left-to-surface']  = {active = false},
            ['harvester-right-to-surface'] = {active = false},
            ['surface-to-warp-gate']       = {active = false},
            ['surface-to-harvester-left']  = {active = false},
            ['surface-to-harvester-right'] = {active = false},
        },

        -- anti-spam: player_index -> last teleport tick
        players_last_teleport = {},

        -- chest/loader/pipe interconnects between surfaces
        stairs = {
            chest_number = 2,
            chest_type = {input = "dw-chest", output = "dw-chest"},
            loader_tier = "dw-stair-loader",
            pipes_type = "dw-pipe",
            chest_pairs = {},
            pipe_pairs = {},
            chest_loader_pairs = {gate = {}, surface = {}, produstia = {}, smeltus = {}, electria = {}},
        },

        -- accumulated pollution multiplier (grows to spawn biters)
        pollution = 1,

        -- warp gate entity + mobile inventory persistence
        warpgate = {
            chest_number = 2,
            type = "warp-gate",
            mobile_chests = {},
            mobile_loaders = {},
        },

        -- harvester platforms (left/right)
        harvesters = {
            loaders = 2,
            loader_tier = "harvest-linked-belt",
            pipes_type = "dw-pipe",
            left  = {gate = nil, area = nil, size = 0, loaders = {}},
            right = {gate = nil, area = nil, size = 0, loaders = {}},
        },

        -- space-age agricultural entities (Gleba); populated lazily on first Gleba warp
        agricultural = {
            yumako_towers = {},
            jellynut_towers = {},
        },

        -- lab intro / nauvis bootstrap flags
        intro_built_entities = {},
        nauvis_lab_exploded = false,
        nauvis_cleared = false,
        all_players_left_nauvis = false,
        lab_intro_finished = false,
        nauvis_resources = nil,

        -- per-planet first-arrival triggers
        fulgora_first_warp = false,
        gleba_first_warp = false,
        vulcanus_first_warp = false,
        aquilo_first_warp = false,
        aquilo_resources = nil,
    }
end

------------------------------------------------------------
--- Lazy accessor
------------------------------------------------------------
-- Returns the bundle for force_name, creating it on first call. This is the
-- single entry point every consumer uses instead of touching storage.teams
-- directly, so the create-on-demand invariant lives in one place.
function dw.warp_ctx(force_name)
    if not storage.teams then storage.teams = {} end
    local ctx = storage.teams[force_name]
    if not ctx then
        ctx = new_ctx()
        storage.teams[force_name] = ctx
    end
    return ctx
end

-- True if a context already exists for force_name (without creating one).
function dw.has_warp_ctx(force_name)
    return storage.teams ~= nil and storage.teams[force_name] ~= nil
end

------------------------------------------------------------
--- Surface index <-> force reverse map
------------------------------------------------------------
-- storage.surface_index_to_force : surface_index -> force_name
-- Records which team currently owns each surface so surface-scoped engine
-- events can be routed to the right context in O(1).

-- Associate a surface index with a team. Called on surface birth/adoption.
function dw.set_surface_owner(surface_index, force_name)
    if not storage.surface_index_to_force then storage.surface_index_to_force = {} end
    storage.surface_index_to_force[surface_index] = force_name
end

-- Forget a single surface index (e.g. one surface deleted). No-op if unknown.
function dw.clear_surface_owner(surface_index)
    if not storage.surface_index_to_force then return end
    storage.surface_index_to_force[surface_index] = nil
end

-- Resolve a surface index to its owning force name, or nil if unowned.
function dw.surface_owner(surface_index)
    if not storage.surface_index_to_force then return nil end
    return storage.surface_index_to_force[surface_index]
end

-- Drop every surface-index mapping that points at force_name. Used at teardown,
-- where we know the force but not which indices it held.
function dw.clear_surfaces_for_force(force_name)
    if not storage.surface_index_to_force then return end
    for index, owner in pairs(storage.surface_index_to_force) do
        if owner == force_name then
            storage.surface_index_to_force[index] = nil
        end
    end
end

------------------------------------------------------------
--- Creation / teardown
------------------------------------------------------------
-- Initialize a team's context (idempotent -- safe to call again on rebirth into
-- a recycled force name). Returns the bundle so callers can bootstrap from it.
function dw.create_warp_ctx(force_name)
    return dw.warp_ctx(force_name)
end

-- Tear a team down: drop its bundle and forget all its surface-index mappings.
-- MTS deletes the actual surfaces; this only releases the per-team state so a
-- recycled force name starts clean.
function dw.destroy_warp_ctx(force_name)
    if storage.teams then storage.teams[force_name] = nil end
    dw.clear_surfaces_for_force(force_name)
end

-- Ensure the top-level storage shape exists. Called from on_init /
-- on_configuration_changed. Fresh save -- no migration, just the new shape.
function dw.init_warp_ctx_storage()
    storage.teams = storage.teams or {}
    storage.surface_index_to_force = storage.surface_index_to_force or {}
end

-- Migration (on_configuration_changed): the warp-generator-1 research gate was
-- restored after an earlier version armed ctx.timer.active immediately at MTS
-- clock-start. Recompute each existing team's gate from its ACTUAL research
-- state, so an upgraded in-flight save obeys the new rule: a team is armed iff
-- it has researched warp-generator-1. Idempotent (recomputes from research, not
-- from the prior flag), so it is safe to run on any config change. A fresh save
-- has no teams, so this is a no-op there.
function dw.regate_existing_teams()
    if not storage.teams then return end
    for force_name, ctx in pairs(storage.teams) do
        local force = game.forces[force_name]
        local gen1 = force and force.valid and force.technologies["warp-generator-1"]
        if gen1 and gen1.researched then
            ctx.timer.active = true
            -- Backfill the countdown when arming so the live warp loop
            -- (warp.lua `if ctx.timer.warp >= 0`) and the GUI never compare nil.
            -- A staged-start (skip_clock) team can still have warp==nil here --
            -- on_team_clock_started hasn't fired -- so mirror the gen-1 research
            -- handler's self-heal rather than trust clock-start ordering.
            ctx.timer.warp = ctx.timer.warp or ctx.timer.base
            ctx.timer.manual_warp = ctx.timer.manual_warp or ctx.timer.base
        else
            ctx.timer.active = false
        end
    end
end

return warp_ctx_lib
