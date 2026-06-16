require "lib.lib"
require "lib.rampant"

require "scripts.warp_ctx"
local mts_lifecycle = require "scripts.mts_lifecycle"

------------------------------------------------------------
--- Per-team storage + MTS lifecycle
------------------------------------------------------------
-- Initialize the per-team keystone (storage.teams + surface-index reverse map)
-- and wire MTS team birth/release to per-team context create/teardown.
--
-- FRESH SAVE -- no migration. The legacy flat globals below (set_globals) are
-- left untouched for now: the singleton consumers still read them, and the
-- mechanical port onto warp_ctx(force_name) is a later phase.

-- on_init / on_configuration_changed: ensure storage shape, then setup() which
-- remote.calls + caches the mts-v1 event ids and registers the handlers.
local function init_mts_lifecycle()
    dw.init_warp_ctx_storage()
    mts_lifecycle.setup()
end
dw.register_event('on_init', init_mts_lifecycle)
dw.register_event('on_configuration_changed', init_mts_lifecycle)

-- on_load: NO remote.call / NO storage writes -- just re-attach handlers from
-- the event ids cached in storage during on_init/on_configuration_changed.
dw.register_event('on_load', mts_lifecycle.register)

------------------------------------------------------------
--- Globals
------------------------------------------------------------
local function set_globals()
    --- player cheat bag
    storage.cheat_bag = storage.cheat_bag or {}

    --- Victory
    storage.victory = storage.victory or false

    --- GUI stuffs
    storage.gui = storage.gui or {
        item_watch = {},
        watchdogs = {[1] = true, [2] = true, [3] = true},
        count_watchdogs = 3,
        count_watched_item = 0,
        item_list = {},
        planet_selector_enabled = false,
        planet_selector_list = {}
    }

    --- porm gls (size + surface)
    storage.platform = storage.platform or {
        warp = {size = dw.platform_size.warp[1]},
        factory = {size = 0, surface = nil},
        mining = {size = {x=0, y=0}, surface = nil},
        power = {size = 0, water = false, surface = nil},
    }

    -- warp informations
    storage.warp = storage.warp or {
        number = 0,
        current = {},
        previous = nil,
        status = defines.warp.awaiting,
        time = game.tick,
        preferred_destination = nil,
    }

    -- timer informations
    storage.timer = storage.timer or { -- timers are in seconds, not ticks
        active = false,
        base = 20 * 60, -- 20min
        warp = nil,
        manual_warp = nil,
    }

    -- vote and player count
    storage.votes = storage.votes or {
        count = 0,
        players = {},
        min_vote = 1,
        players_count = 0,
    }

    -- list of teleport locations with status, and both teleporter entity (fom/to)
    storage.teleporter = storage.teleporter or {
        ['warp-to-factory'] =               {active = false},
        ['factory-to-warp'] =               {active = false},
        ['mining-to-factory'] =             {active = false},
        ['factory-to-mining'] =             {active = false},
        ['power-to-mining'] =               {active = false},
        ['mining-to-power'] =               {active = false},
        ['nauvis-gate'] =                   {active = false},
        ['warp-gate-to-surface'] =          {active = false},
        ['harvester-left-to-surface'] =     {active = false},
        ['harvester-right-to-surface'] =    {active = false},
        ['surface-to-warp-gate'] =          {active = false},
        ['surface-to-harvester-left'] =     {active = false},
        ['surface-to-harvester-right'] =    {active = false},
    }
    -- timer check for player teleport
    storage.players_last_teleport = storage.players_last_teleport or {}

    -- stairs (chest/loader/pipes) between surfaces
    storage.stairs = storage.stairs or {
        chest_number = 2,
        chest_type = {input = "dw-chest", output="dw-chest"},
        loader_tier = "dw-stair-loader",
        pipes_type = "dw-pipe",
        chest_pairs = {},
        pipe_pairs = {},
        chest_loader_pairs = {gate={}, surface={}, produstia={}, smeltus={}, electria={}},
    }

    -- base global pollution value
    storage.pollution = storage.pollution or 1

    -- warp gates / harvester gate level
    storage.warpgate = storage.warpgate or {
        chest_number = 2,
        type = "warp-gate",
        mobile_chests = {},
        mobile_loaders = {}
    }
    storage.harvesters = storage.harvesters or {
        loaders = 2,
        loader_tier = "harvest-linked-belt",
        pipes_type = "dw-pipe",
        left = {gate = nil, area = nil, size=0, loaders = {}},
        right = {gate = nil, area = nil, size=0, loaders = {}}
    }
    storage.agricultural = storage.agricultural or {
        yumako_towers = {},
        jellynut_towers = {},
    }
end
dw.register_event('on_init', set_globals)
dw.register_event('on_configuration_changed', set_globals)

------------------------------------------------------------
--- Warnings
------------------------------------------------------------
local function mod_warning()
    if dw.rampant.active then
        game.print({"dw-messages.rampant-settings"})
    end
end
dw.register_event('on_init', mod_warning)
dw.register_event('on_configuration_changed', mod_warning)

------------------------------------------------------------

require "scripts.commands"
require "scripts.shortcuts"
require "scripts.misc"

require "scripts.surface-generation"
require "scripts.teleport"
require "scripts.gui"
require "scripts.platforms.surface"
require "scripts.platforms.dimensions"
require "scripts.platforms.harvesters"

require "scripts.scenario.freeplay"
-- v1: lab_intro DISABLED. The single-team intro built an exploding lab on the
-- SHARED nauvis and pre-created neo-nauvis at on_init, clashing with the MTS
-- per-team spawn. The warp #0 adoption (mts_lifecycle on_team_surface_created)
-- replaces it: each team starts ON its adopted dimension home with
-- ctx.nauvis_lab_exploded already true. Nothing else requires lab_intro -- its
-- functions are only ever wired as its own event handlers -- so dropping the
-- require fully removes it.
-- require "scripts.scenario.lab_intro"
require "scripts.scenario.victory"

require "scripts.warp"
require "scripts.enemies"

require "scripts.entities.warpgate"
require "scripts.entities.rocket_silo"
require "scripts.entities.logistics"
require "scripts.entities.dimension-crane"

require "compatibility.picker-dollies"

-- require "scripts.debug"
