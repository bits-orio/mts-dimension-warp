-- mdw-scenario-test: the dev-only driver behind dev/run-scenarios.sh.
--
-- The joined client claims a team through MTS's landing pen and types the
-- commands (/mdw-resume, /mdw-offlinewarp, /mts-pause, /mts-resume); the
-- runner stops and restarts it for a member leaving and rejoining. This mod
-- builds fixtures on the team's warp platform, fast-forwards the game while
-- nobody is online so the real warp timer expires and the team docks, and
-- checks the base at each stage. Steps arrive as "/mdwt <step>" on the server
-- console. Every check logs
--   MDW_TEST PASS <name>: <detail>    or    MDW_TEST FAIL <name>: <detail>
-- and every step ends with "MDW_TEST STEP <name>", which the runner waits for.
--
-- Handlers are registered unconditionally at parse time, and MTS's events from
-- their ids on every session, so a joining client always matches the server.

local TAG = "MDW_TEST "
local ACC_CHARGE = 3000000                 -- 3 MJ in a 5 MJ accumulator
local FF_SPEED = 64                        -- game.speed while nobody is online
local DOCK_PATTERN = "^mdw%-team%-%d+%-dock%-w%d+$"
local FX = {                               -- on the warp platform (22 x 22 after warp-platform-size-1)
    acc   = { name = "accumulator",          pos = { 8, 8 } },
    solar = { name = "solar-panel",          pos = { -8.5, 8.5 } },
    gen   = { name = "steam-engine",         pos = { -8.5, -6.5 } },
    p1    = { name = "medium-electric-pole", pos = { 8.5, -8.5 } },
    p2    = { name = "medium-electric-pole", pos = { 3.5, -8.5 } },
}

local function say(kind, name, detail)
    log(TAG .. kind .. " " .. name .. (detail ~= nil and (": " .. tostring(detail)) or ""))
end
local function check(name, ok, detail)
    say(ok and "PASS" or "FAIL", name, detail)
    return ok
end
local function step(name, detail) say("STEP", name, detail) end
local function mts(fn, ...) return remote.call("mts-v1", fn, ...) end
local function space_age() return script.active_mods["space-age"] ~= nil end

local STEPS = {}

local function init_storage()
    storage.queue  = storage.queue or {}
    storage.events = storage.events or {}
    storage.mark   = storage.mark or 0
end

local function later(ticks, name, args)
    storage.queue[#storage.queue + 1] = { at = game.tick + ticks, name = name, args = args or {} }
end

local function run(name, args)
    local fn = STEPS[name]
    if not fn then say("FAIL", "unknown-step", name); step(name); return end
    local ok, err = pcall(fn, args or {})
    if not ok then say("FAIL", name, "test step error: " .. tostring(err)); step(name) end
end

-- ─── MTS events ─────────────────────────────────────────────────────────

local function push(kind, e)
    storage.events[#storage.events + 1] = { kind = kind, force = e.force_name, source = e.source, tick = game.tick }
end

local function since(kind)
    local n, sources = 0, {}
    for i = storage.mark + 1, #storage.events do
        local ev = storage.events[i]
        if ev.kind == kind then n = n + 1; sources[#sources + 1] = tostring(ev.source) end
    end
    return n, table.concat(sources, ",")
end

local function mark() storage.mark = #storage.events end

local function expect_events(name, kind, want_n, want_source)
    local n, sources = since(kind)
    check(name, n == want_n and (want_source == nil or sources == want_source),
        "on_team_" .. kind .. " x" .. n .. (n > 0 and (" source=" .. sources) or "") ..
        " (want x" .. want_n .. (want_source and (" " .. want_source) or "") .. ")")
end

local HANDLERS = {
    on_team_created = function(e)
        storage.team, storage.leader = e.force_name, e.player_index
        step("team-created", e.force_name)
        later(30, "setup", { force = e.force_name })
    end,
    on_team_paused  = function(e) push("paused", e);  step("ev-paused", e.force_name .. " source=" .. tostring(e.source)) end,
    on_team_resumed = function(e) push("resumed", e); step("ev-resumed", e.force_name .. " source=" .. tostring(e.source)) end,
}

local function subscribe()
    if not (remote.interfaces["mts-v1"] and remote.interfaces["mts-v1"].get_event_id) then return end
    for name, handler in pairs(HANDLERS) do
        local id = remote.call("mts-v1", "get_event_id", name)
        if id then script.on_event(id, handler) end
    end
end

-- ─── Where the base is ──────────────────────────────────────────────────

local function dock_surface()
    for _, name in ipairs(mts("list_team_surfaces", storage.team)) do
        if name:match(DOCK_PATTERN) then return game.surfaces[name] end
    end
end

--- The fixtures on whichever team surface holds the base right now.
local function find_fixtures()
    local found
    for _, name in ipairs(mts("list_team_surfaces", storage.team)) do
        local s = game.surfaces[name]
        if s and s.valid then
            local p = FX.acc.pos
            local acc = s.find_entities_filtered{ name = FX.acc.name, force = storage.team,
                area = { { p[1] - 0.2, p[2] - 0.2 }, { p[1] + 0.2, p[2] + 0.2 } } }[1]
            if acc then
                found = { surface = s, acc = acc }
                for key, spec in pairs(FX) do
                    local q = spec.pos
                    found[key] = s.find_entities_filtered{ name = spec.name, force = storage.team,
                        area = { { q[1] - 0.2, q[2] - 0.2 }, { q[1] + 0.2, q[2] + 0.2 } } }[1]
                end
                if not name:match(DOCK_PATTERN) then return found end
            end
        end
    end
    return found
end

local function copper(pole)
    return pole and pole.valid and pole.get_wire_connector(defines.wire_connector_id.pole_copper, true)
end

local function wired(f)
    local a, b = copper(f.p1), copper(f.p2)
    return a and b and a.is_connected_to(b) or false
end

local function describe(f)
    if not f then return "no base found on any team surface" end
    return string.format("on %s: accumulator energy=%s, steam engine disabled_by_script=%s, solar_power_multiplier=%s, poles wired=%s",
        f.surface.name, tostring(f.acc and f.acc.valid and f.acc.energy), tostring(f.gen and f.gen.valid and f.gen.disabled_by_script),
        tostring(f.surface.solar_power_multiplier), tostring(wired(f)))
end

local function expect_frozen(prefix, f)
    local paused = mts("is_team_paused", storage.team)
    check(prefix .. "-paused", paused == true, "is_team_paused=" .. tostring(paused))
    if not check(prefix .. "-base-found", f ~= nil and f.gen ~= nil, describe(f)) then return end
    check(prefix .. "-accumulator-zeroed", f.acc.energy == 0, describe(f))
    check(prefix .. "-steam-engine-disabled", f.gen.disabled_by_script == true, describe(f))
    check(prefix .. "-solar-mult-zero", f.surface.solar_power_multiplier == 0, describe(f))
    if space_age() then check(prefix .. "-poles-unplugged", not wired(f), describe(f)) end
end

local function expect_live(prefix, f)
    local paused = mts("is_team_paused", storage.team)
    check(prefix .. "-not-paused", paused == false, "is_team_paused=" .. tostring(paused))
    if not check(prefix .. "-base-found", f ~= nil and f.gen ~= nil, describe(f)) then return end
    check(prefix .. "-accumulator-restored", math.abs(f.acc.energy - ACC_CHARGE) < 1, describe(f))
    check(prefix .. "-steam-engine-enabled", f.gen.disabled_by_script == false, describe(f))
    check(prefix .. "-solar-mult-live", f.surface.solar_power_multiplier > 0, describe(f))
    check(prefix .. "-poles-wired", wired(f), describe(f))
end

-- ─── Setup: arm the warp clock, grow the platform, build the fixtures ───

STEPS["setup"] = function(args)
    local p = game.get_player(storage.leader)
    local tries = (args.tries or 0) + 1
    local surface = p and p.valid and p.physical_surface
    local owner = surface and mts("get_surface_owner", surface.name)
    if owner ~= args.force then
        if tries > 60 then
            check("setup", false, "leader never reached a surface of " .. args.force)
            step("fixtures", "none")
            return
        end
        later(30, "setup", { force = args.force, tries = tries })
        return
    end
    -- As /mdw-arm and /mdw-size 1 do: the warp clock runs (15 min), neo-nauvis
    -- is a destination, and the platform is 22 x 22.
    local force = game.forces[args.force]
    for _, t in ipairs({ "neo-nauvis", "warp-generator-1", "warp-platform-size-1" }) do
        if force.technologies[t] then force.technologies[t].researched = true end
    end
    storage.home = surface
    later(10, "place-fixtures")
end

STEPS["place-fixtures"] = function()
    local s = storage.home
    for _, e in pairs(s.find_entities_filtered{ area = { { -11, -11 }, { 11, 11 } }, type = { "tree", "simple-entity", "cliff", "fish" } }) do
        e.destroy()
    end
    local made, missing = {}, {}
    for key, spec in pairs(FX) do
        local e = s.create_entity{ name = spec.name, position = spec.pos, force = storage.team }
        if e then made[key] = e else missing[#missing + 1] = key end
    end
    if not check("setup-fixtures", #missing == 0, #missing == 0 and ("on " .. s.name) or ("blocked: " .. table.concat(missing, ","))) then
        step("fixtures", "none")
        return
    end
    made.acc.energy = ACC_CHARGE
    local a, b = copper(made.p1), copper(made.p2)
    if not a.is_connected_to(b) then a.connect_to(b, false, defines.wire_origin.player) end
    check("setup-poles-wired", a.is_connected_to(b))
    step("fixtures", string.format("team=%s surface=%s", storage.team, s.name))
end

-- ─── Leaving, docking, resuming ─────────────────────────────────────────

STEPS["mark"] = function() mark(); step("mark") end
STEPS["done"] = function() log(TAG .. "DONE") end

-- The next time the leader leaves, fast-forward until the team docks.
STEPS["ff-on-leave"] = function()
    storage.ff_on_leave = true
    mark()
    step("ff-armed")
end

local function watch(kind, seconds)
    storage.watch = { kind = kind, deadline = game.tick + seconds * 60, started = game.tick }
end

local function docked_checks(prefix)
    local dock = dock_surface()
    check(prefix .. "-dock-surface", dock ~= nil, dock and dock.name or "no dock surface owned")
    local f = find_fixtures()
    check(prefix .. "-base-on-dock", f ~= nil and dock ~= nil and f.surface == dock, describe(f))
    expect_frozen(prefix, f)
end

local WATCHERS = {
    -- The team docked: a dock surface it owns, and it is paused.
    dock = function(w)
        if not (dock_surface() and mts("is_team_paused", storage.team)) then return false end
        game.speed = 1
        local dock = dock_surface()
        say("INFO", "docked-after", string.format("%.0f game seconds of fast-forward", (game.tick - w.started) / 60))
        docked_checks("docked")
        expect_events("docked-paused-by-script", "paused", 1, "script")
        step("docked", dock.name)
        return true
    end,
    -- The base arrived on a new world: the fixtures are on a team surface that
    -- is not a dock, and no dock is left.
    arrival = function()
        local f = find_fixtures()
        if not (f and not f.surface.name:match(DOCK_PATTERN) and not dock_surface()) then return false end
        local tag = storage.arrival_tag or "arrived"
        say("INFO", tag .. "-after", string.format("%.0f game seconds", (game.tick - storage.watch.started) / 60))
        expect_live(tag, f)
        step("arrived", f.surface.name)
        return true
    end,
}

script.on_event(defines.events.on_player_left_game, function(e)
    step("left", tostring(e.player_index))
    if storage.ff_on_leave then
        storage.ff_on_leave = nil
        game.speed = FF_SPEED
        watch("dock", 1800)
        step("ff-started", "game.speed=" .. FF_SPEED)
    end
end)

STEPS["check-docked"] = function()
    docked_checks("docked-online")
    step("check-docked")
end

-- After /mdw-resume: power is back on the dock and the countdown runs.
STEPS["check-thawed-on-dock"] = function()
    local f = find_fixtures()
    local dock = dock_surface()
    check("thawed-still-on-dock", dock ~= nil and f ~= nil and f.surface == dock, describe(f))
    expect_live("thawed-on-dock", f)
    step("check-thawed-on-dock")
end

-- An admin pause holds the dock: still docked, still paused, still frozen.
STEPS["check-held"] = function(args)
    local tag = (args.arg ~= "" and args.arg) or "held"
    local dock = dock_surface()
    check(tag .. "-no-warp-out", dock ~= nil, dock and ("still on " .. dock.name) or "the dock is gone")
    local f = find_fixtures()
    check(tag .. "-base-on-dock", f ~= nil and dock ~= nil and f.surface == dock, describe(f))
    expect_frozen(tag, f)
    step("check-held")
end

STEPS["watch-arrival"] = function(args)
    storage.arrival_tag = (args.arg ~= "" and args.arg) or "arrived"
    watch("arrival", 90)
    step("watch-arrival")
end

-- ─── Scenario 9: a mod update while docked ──────────────────────────────

STEPS["pre-update"] = function()
    local dock = dock_surface()
    storage.s9 = { dock = dock and dock.name }
    check("s9-docked-before-update", dock ~= nil and mts("is_team_paused", storage.team) == true, tostring(storage.s9.dock))
    step("pre-update")
end

local function s9_on_config_changed(changes)
    local mc = changes.mod_changes and changes.mod_changes["multi-team-support"]
    if not (storage.s9 and mc and mc.old_version and mc.new_version) then return end
    mark()
    local paused = mts("is_team_paused", storage.team)
    check("s9-paused-in-config-changed", paused == true, "multi-team-support " .. mc.old_version .. " -> " .. mc.new_version
        .. ", is_team_paused=" .. tostring(paused))
    local f = find_fixtures()
    expect_frozen("s9-after-update", f)
    later(60 * 8, "s9-after")
end

-- Eight seconds later (MDW's dock_timer has run several times): no pause or
-- resume was raised, so MDW never had to re-freeze the dock.
STEPS["s9-after"] = function()
    expect_events("s9-no-refreeze-pause-event", "paused", 0)
    expect_events("s9-no-resume-event", "resumed", 0)
    local dock = dock_surface()
    check("s9-still-docked", dock ~= nil and dock.name == storage.s9.dock, tostring(dock and dock.name))
    expect_frozen("s9-later", find_fixtures())
    storage.s9 = nil
    step("s9-checked")
end

-- ─── Admin, typed commands, the tick ────────────────────────────────────

script.on_event(defines.events.on_player_joined_game, function(e)
    local p = game.get_player(e.player_index)
    p.admin = true
    step("joined", p.name .. " index=" .. p.index .. " admin=" .. tostring(p.admin))
end)

script.on_event(defines.events.on_console_command, function(e)
    local who = e.player_index and game.get_player(e.player_index)
    say("CMD", e.command, (e.parameters or "") .. " by " .. (who and who.name or "server"))
end)

script.on_event(defines.events.on_tick, function(e)
    local q = storage.queue
    if #q > 0 then
        local due, keep = {}, {}
        for _, item in ipairs(q) do
            if item.at <= e.tick then due[#due + 1] = item else keep[#keep + 1] = item end
        end
        if #due > 0 then
            storage.queue = keep
            for _, item in ipairs(due) do run(item.name, item.args) end
        end
    end
    local w = storage.watch
    if w and e.tick % 30 == 0 then
        local ok, done = pcall(WATCHERS[w.kind], w)
        if not ok then
            storage.watch = nil
            game.speed = 1
            say("FAIL", "watch-" .. w.kind, "test watcher error: " .. tostring(done))
            step(w.kind == "dock" and "docked" or "arrived", "error")
        elseif done then
            storage.watch = nil
        elseif e.tick > w.deadline then
            storage.watch = nil
            game.speed = 1
            check("watch-" .. w.kind, false, "timed out; " .. describe(find_fixtures()))
            step(w.kind == "dock" and "docked" or "arrived", "timeout")
        end
    end
end)

commands.add_command("mdwt", "dev test steps (mdw-scenario-test)", function(c)
    local name, rest = (c.parameter or ""):match("^(%S+)%s*(.*)$")
    run(name or "", { arg = rest })
end)

script.on_init(function() init_storage(); subscribe() end)
script.on_load(subscribe)
script.on_configuration_changed(function(changes)
    init_storage()
    subscribe()
    s9_on_config_changed(changes)
end)
