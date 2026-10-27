dw = dw or {}
dw.events = dw.events or {}

special_events = {
    on_init = true,
    on_load = true,
    on_configuration_changed = true,
}

dw.register_event = function(event, callback)
    if not dw.events[event] then
        dw.events[event] = {}
        dw.events[event].callbacks = {}

        -- add helper to trigger all callback at once
        dw.events[event].run = function(event_data)
            for _, cb in pairs(dw.events[event].callbacks) do
                cb(event_data)
            end
        end

        -- check if the event is on_nth_tick_XXX
        local event_nth, frequency = string.match(event, "^(.*)_(%d+)$")
        if event_nth == "on_nth_tick" and frequency then
            script.on_nth_tick(tonumber(frequency), dw.events[event].run)
        else
            if not special_events[event] then
                script.on_event(event, dw.events[event].run)
            end
        end
    end

    for _, cb in pairs(dw.events[event].callbacks) do
        if cb == callback then return end
    end
    table.insert(dw.events[event].callbacks, callback)
end

--- remove a specific callback from event
--- technically, it would be more efficient to use [i]=nil, but
--- we won't have enough event for it to really matter...
dw.remove_event = function(event, callback)
    if not dw.events[event] then return end
    for i=#dw.events[event].callbacks, 1, -1 do
        local cb = dw.events[event].callbacks[i]
        if cb == callback then
            table.remove(dw.events[event].callbacks, i)
        end
    end
end

--- make a specific function to trigger events outside on_event
--- to be able to check if the event is actually registered
dw.fire_event = function(event, event_data)
    if dw.events[event] then
        dw.events[event].run(event_data)
    end
end

--- Per-team tick dispatch (ADDITIVE -- does not touch the singleton path above).
---
--- Upstream Dimension Warp was single-team: every on_nth_tick handler ran once
--- against the flat globals. In MTS Dimension Warp warp state is per-team inside
--- storage.teams[force_name] (see scripts/warp_ctx.lua). A ported per-team handler
--- needs to run once *per team* each period, against that team's ctx.
---
--- register_team_tick(nth, fn) registers a single on_nth_tick_<nth> handler (reusing
--- the proven dw.register_event path -- no new engine API, just the same
--- script.on_nth_tick fan-out) whose body iterates storage.teams and calls
--- fn(force_name, ctx, event_data) for every team that has a context. Teams only
--- appear in storage.teams once dw.warp_ctx() created their bundle, so "has a ctx"
--- is exactly "present in storage.teams" -- no extra existence check needed.
---
--- The existing dw.register_event("on_nth_tick_XXX", ...) path is unchanged: any
--- handler NOT ported to register_team_tick still fires once as a singleton, exactly
--- as before. Only NEW per-team handlers (slice 3+) opt into this facility.
---
--- Each team's call runs under xpcall, so an error in one team's handler does not
--- end the game for every team on the server. The first error logs its traceback,
--- tells that team, and switches that one handler off for that team; the other
--- handlers and the other teams keep running. on_configuration_changed (a mod
--- update, which may carry the fix) switches them back on. The latch key is the
--- handler's registration order, which is the same on every machine because
--- handlers register while control.lua is parsed.
local team_tick_count = 0

local function contain_team_error(force_name, ctx, key, err)
    ctx.failed_handlers = ctx.failed_handlers or {}
    ctx.failed_handlers[key] = game.tick
    log("Error in team handler " .. key .. " for " .. force_name
        .. ", switched off for that team until the next mod update: " .. tostring(err))
    local force = game.forces[force_name]
    if force and force.valid then force.print({"dw-messages.team-script-error"}) end
end

dw.register_team_tick = function(nth, fn)
    team_tick_count = team_tick_count + 1
    local key = "nth" .. nth .. "#" .. team_tick_count
    dw.register_event("on_nth_tick_" .. nth, function(event_data)
        -- storage.teams may not exist before on_init; guard so an early tick is a
        -- no-op rather than an error.
        if not storage.teams then return end
        for force_name, ctx in pairs(storage.teams) do
            if not (ctx.failed_handlers and ctx.failed_handlers[key]) then
                local ok, err = xpcall(fn, debug.traceback, force_name, ctx, event_data)
                if not ok then contain_team_error(force_name, ctx, key, err) end
            end
        end
    end)
end

dw.register_event("on_configuration_changed", function()
    for _, ctx in pairs(storage.teams or {}) do ctx.failed_handlers = nil end
end)

script.on_init(function(event) dw.fire_event("on_init", event) end)
script.on_load(function(event) dw.fire_event("on_load", event) end)
script.on_configuration_changed(function(event) dw.fire_event("on_configuration_changed", event) end)