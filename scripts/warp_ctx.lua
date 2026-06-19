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

        -- platform sizes + their surfaces. electrified_ground (set by the
        -- electrified-ground tech) flips all three dimension surfaces to
        -- always_day + a global electric network.
        platform = {
            warp    = {size = dw.platform_size.warp[1]},
            factory = {size = 0, surface = nil},
            mining  = {size = {x = 0, y = 0}, surface = nil},
            power   = {size = 0, water = false, surface = nil},
            electrified_ground = false,
        },

        -- warp state machine
        warp = {
            number = 0,
            current = {},
            previous = nil,
            status = defines.warp.awaiting,
            time = game.tick,
            preferred_destination = nil,

            -- P2 docking bay (ADR-0006). Set when a warp fires with nobody
            -- online: the platform parks on its own on-demand dock surface,
            -- frozen via MTS pause, until a member resumes.
            docked = false,
            dock_surface_name = nil,   -- the ephemeral safe dock surface
            dock_surface_index = nil,
            pending_destination = nil, -- the real planet to Arrive on at resume
            resume_chosen = false,     -- a member chose to resume (arms the thaw)
        },

        -- timers are in seconds, not ticks
        timer = {
            active = false,
            base = 15 * 60, -- 15 min auto-warp floor (warp-generator-1; grows with the generator techs)
            warp = nil,         -- countdown to the next warp
            manual_warp = nil,  -- player-vote warp countdown
            dock = nil,         -- P2: resume countdown (thaw -> forced warp out)
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
            -- Buckets keyed by per-team ROLE token (NOT surface name), resolved
            -- via dw.surface_role: 'surface' = the warp surface, 'gate' = the
            -- warp-gate cluster, factory/mining/power = the three dimension
            -- surfaces. Upstream keyed these by bare surface name (produstia/
            -- smeltus/electria), which collapses under per-team unique names.
            chest_loader_pairs = {gate = {}, surface = {}, factory = {}, mining = {}, power = {}},
        },

        -- accumulated pollution multiplier (grows to spawn biters)
        pollution = 1,

        -- warp gate entity + mobile inventory persistence. gate/gatepole are the
        -- static cluster on the warp surface; mobile_gate is the player-carried
        -- gate; mobile_type is its current item name (grows with gate research).
        warpgate = {
            chest_number = 2,
            type = "warp-gate",
            mobile_chests = {},
            mobile_loaders = {},
            gate = nil,
            gatepole = nil,
            mobile_gate = nil,
            mobile_type = nil,
        },

        -- harvester platforms (left/right)
        harvesters = {
            loaders = 2,
            loader_tier = "harvest-linked-belt",
            pipes_type = "dw-pipe",
            left  = {gate = nil, area = nil, size = 0, loaders = {}},
            right = {gate = nil, area = nil, size = 0, loaders = {}},
        },

        -- space-age agricultural cranes (Gleba): tower lists plus the seed/fruit
        -- chests + shared pole created on the mining platform by the
        -- dimension-crane research (populated lazily on first Gleba warp).
        agricultural = {
            yumako_towers = {},
            jellynut_towers = {},
            yumako_input = nil,
            yumako_output = nil,
            jellynut_input = nil,
            jellynut_output = nil,
            pole = nil,
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

-- Forward-compat for saves created BEFORE the P4 aux port. Factorio only fires
-- on_configuration_changed on a VERSION change, so a same-version code reload of
-- a long-running save would otherwise skip every migration. We therefore reshape
-- each ctx lazily, here at the single chokepoint every consumer goes through.
-- Idempotent + cheap: the guard short-circuits the instant the new shape exists,
-- so it is a one-time fixup per team and a no-op forever after.
--
-- The one shape change that would CRASH the new code on an old ctx: P4 renamed
-- the chest_loader_pairs buckets from planet names (produstia/smeltus/electria)
-- to role tokens (factory/mining/power). The logistics layer indexes
-- ctx.stairs.chest_loader_pairs[role], so a missing 'factory' bucket nil-indexes.
-- The old aux code was flat (never wrote ctx.stairs), so these buckets are empty
-- on every pre-P4 save -- the rename just needs the new keys to exist. Everything
-- else P4 added (electrified_ground, warpgate handles, agricultural chests) is a
-- nil-default the code already reads safely, so it needs no migration.
local function ensure_p4_shape(ctx)
    local clp = ctx.stairs and ctx.stairs.chest_loader_pairs
    if clp and clp.factory == nil then
        clp.factory = clp.produstia or {}
        clp.mining  = clp.smeltus  or {}
        clp.power   = clp.electria or {}
        clp.gate    = clp.gate    or {}
        clp.surface = clp.surface or {}
        clp.produstia, clp.smeltus, clp.electria = nil, nil, nil
    end
end

-- Returns the bundle for force_name, creating it on first call. This is the
-- single entry point every consumer uses instead of touching storage.teams
-- directly, so the create-on-demand invariant lives in one place.
function dw.warp_ctx(force_name)
    if not storage.teams then storage.teams = {} end
    local ctx = storage.teams[force_name]
    if not ctx then
        ctx = new_ctx()
        storage.teams[force_name] = ctx
    else
        ensure_p4_shape(ctx)
    end
    return ctx
end

-- True if a context already exists for force_name (without creating one).
function dw.has_warp_ctx(force_name)
    return storage.teams ~= nil and storage.teams[force_name] ~= nil
end

-- Resolve a player's EFFECTIVE team force name, spectator-aware. A member
-- spectating another team is on the 'spectator' force, so player.force.name is
-- NOT their team; mts-v1 get_effective_force returns the real team. Used by the
-- dock prompt + member-gather so a spectating member still resumes/travels with
-- their own team. Falls back to the live force name if the query is unavailable.
function dw.effective_force(player)
    if not (player and player.valid) then return nil end
    local fn = player.force.name
    if fn:find("^team%-") then return fn end
    local ok, real = pcall(remote.call, 'mts-v1', 'get_effective_force', player.index)
    if ok and real then return real end
    return fn
end

-- Resolve which ROLE a surface plays in a team's setup: 'factory'/'mining'/
-- 'power' for the three permanent dimension surfaces, else 'surface' (the warp
-- surface, the dock, or anything else). This REPLACES upstream's
-- dw.safe_surfaces[surface.name] keying, which collapses under per-team unique
-- surface names (mdw-team-1-factory is not "produstia"). The 'gate' bucket is a
-- literal owned by the warp-gate code, not produced here. Compares live surface
-- handles, so it self-heals when the warp surface is replaced on each warp.
function dw.surface_role(ctx, surface)
    if not (ctx and surface and surface.valid) then return "surface" end
    local idx = surface.index
    local p = ctx.platform
    if p.factory.surface and p.factory.surface.valid and p.factory.surface.index == idx then return "factory" end
    if p.mining.surface  and p.mining.surface.valid  and p.mining.surface.index  == idx then return "mining" end
    if p.power.surface   and p.power.surface.valid   and p.power.surface.index   == idx then return "power" end
    return "surface"
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
