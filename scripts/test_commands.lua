-- scripts/test_commands.lua
--
-- Admin-only console commands to SPEEDRUN the per-team warp flow while testing.
-- They bypass the normal resource/research grind so the warp loop can be
-- exercised repeatedly in seconds instead of being played out by hand:
--
--   /mdw-arm            research warp-generator-1 (arm this team's warp timer)
--                       and unlock every destination planet
--   /mdw-warp [planet]  warp NOW. With a planet arg, force that EXACT destination
--                       (even a locked one) -- e.g. `/mdw-warp nauvis` to exercise
--                       the nauvis nil-planet path, then `/mdw-warp vulcanus` to
--                       warp back off nauvis. No arg = a random unlocked planet.
--   /mdw-warpx <n>      warp n times in a row (capped at 10) -- the speedrun
--   /mdw-gen <N>        research warp-generator-1..N (grows the auto-warp interval)
--   /mdw-size <N>       research warp-platform-size-1..N (grows the platform)
--   /mdw-cheat          toggle cheat mode (free building) for the caller
--   /mdw-status         print this team's warp state
--
-- Every command resolves the CALLER's team force -> its warp ctx, so each only
-- affects the admin's own team. All are gated on player.admin. These do not warp
-- through the research gate -- /mdw-warp arms the timer itself -- so they work the
-- instant a team is on its home platform.

dw = dw or {}

-- Resolve the calling admin (and optionally their team ctx). Prints why and
-- returns nil when the caller can't run the command.
local function resolve(command, need_team)
    local player = command.player_index and game.get_player(command.player_index)
    if not (player and player.valid) then return nil end
    if not player.admin then
        player.print("[MDW test] admin only.")
        return nil
    end
    if not need_team then return player end
    local force_name = player.force.name
    if not force_name:find("^team%-") or not dw.has_warp_ctx(force_name) then
        player.print("[MDW test] you are not on a warp-enabled team (force=" .. force_name .. ").")
        return nil
    end
    return player, force_name, dw.warp_ctx(force_name)
end

-- A team is on its platform with a valid current surface (so a warp can clone it).
local function has_surface(ctx)
    return ctx.warp.current and ctx.warp.current.surface and ctx.warp.current.surface.valid
end

-- Give a random warp somewhere to go: research every planet-discovery tech,
-- which is the canonical way a space location becomes unlocked (and lets MTS's
-- planet_map unlock the team's variant). Forced /mdw-warp <planet> does NOT need
-- this -- the test override bypasses the unlocked-planet filter entirely.
local function unlock_all_planets(force)
    for tech_name, tech in pairs(force.technologies) do
        if tech_name:find("^planet%-discovery%-") then
            tech.researched = true
        end
    end
end

-- Run the real warp loop once for this team, optionally forcing an exact target.
-- Returns true iff a warp ACTUALLY happened (ctx.warp.number advanced). warp_timer
-- silently no-ops when the team is paused, when forced nauvis->nauvis (stay), or
-- (random) when nauvis is the only destination and we're already there -- so the
-- caller must not claim success blindly.
local function do_one_warp(force_name, ctx, target)
    local before = ctx.warp.number
    ctx.timer.active = true                                   -- bypass the research gate for testing
    ctx.timer.warp = 0                                        -- expire the auto-warp clock NOW
    ctx.timer.manual_warp = ctx.timer.manual_warp or ctx.timer.base
    if target then ctx.warp.test_destination = target end     -- consumed by select_destination
    dw.warp.warp_timer(force_name, ctx)
    ctx.warp.test_destination = nil                           -- clear if warp_timer never reached select_destination
    return ctx.warp.number > before
end

local function cmd_arm(command)
    local player, force_name, ctx = resolve(command, true)
    if not ctx then return end
    local force = player.force
    for _, t in ipairs({"neo-nauvis", "warp-generator-1"}) do
        local tech = force.technologies[t]
        if tech then tech.researched = true end
    end
    unlock_all_planets(force)
    player.print(string.format("[MDW test] armed: warp-generator-1 researched (timer.active=%s), destinations unlocked.",
        tostring(ctx.timer.active)))
end

local function cmd_warp(command)
    local player, force_name, ctx = resolve(command, true)
    if not ctx then return end
    if not has_surface(ctx) then
        player.print("[MDW test] no current surface -- are you on your team's platform yet?")
        return
    end
    local target = command.parameter and command.parameter:match("%S+")
    if target and target ~= "nauvis" and not game.planets[target] then
        player.print("[MDW test] unknown planet '" .. target .. "'.")
        return
    end
    local from = ctx.warp.current.planet
    if do_one_warp(force_name, ctx, target) then
        player.print(string.format("[MDW test] warp %s -> %s | now dimension %d, planet %s, surface %s.",
            tostring(from), tostring(target or "random"), ctx.warp.number + 1,
            tostring(ctx.warp.current.planet),
            has_surface(ctx) and ctx.warp.current.surface.name or "?"))
    else
        player.print(string.format("[MDW test] NO warp (target=%s) -- team paused, or nauvis->nauvis stay. Still dimension %d, planet %s.",
            tostring(target or "random"), ctx.warp.number + 1, tostring(ctx.warp.current.planet)))
    end
end

local function cmd_warpx(command)
    local player, force_name, ctx = resolve(command, true)
    if not ctx then return end
    if not has_surface(ctx) then
        player.print("[MDW test] no current surface yet.")
        return
    end
    local n = tonumber(command.parameter and command.parameter:match("%d+"))
    if not n or n < 1 then
        player.print("[MDW test] usage: /mdw-warpx <count>")
        return
    end
    n = math.min(n, 10)
    local done = 0
    for _ = 1, n do
        if do_one_warp(force_name, ctx) then done = done + 1 end
    end
    if done == n then
        player.print(string.format("[MDW test] warped %d time(s) -> dimension %d, planet %s.",
            n, ctx.warp.number + 1, tostring(ctx.warp.current.planet)))
    else
        player.print(string.format("[MDW test] warped %d of %d (rest no-op -- stuck on nauvis with no other destination, or paused). Run /mdw-arm to unlock planets. Now dimension %d, planet %s.",
            done, n, ctx.warp.number + 1, tostring(ctx.warp.current.planet)))
    end
end

local function cmd_gen(command)
    local player, force_name, ctx = resolve(command, true)
    if not ctx then return end
    local n = tonumber(command.parameter and command.parameter:match("%d+"))
    if not n or n < 1 or n > 6 then
        player.print("[MDW test] usage: /mdw-gen <1-6>")
        return
    end
    local force = player.force
    if force.technologies["neo-nauvis"] then force.technologies["neo-nauvis"].researched = true end
    for i = 1, n do
        local tech = force.technologies["warp-generator-" .. i]
        if tech then tech.researched = true end
    end
    player.print(string.format("[MDW test] warp-generator-1..%d researched -> auto-warp base %ds (~%.0f min).",
        n, ctx.timer.base, ctx.timer.base / 60))
end

local function cmd_size(command)
    local player, force_name, ctx = resolve(command, true)
    if not ctx then return end
    local n = tonumber(command.parameter and command.parameter:match("%d+"))
    if not n or n < 1 or n > 7 then
        player.print("[MDW test] usage: /mdw-size <1-7>")
        return
    end
    local force = player.force
    for i = 1, n do
        local tech = force.technologies["warp-platform-size-" .. i]
        if tech then tech.researched = true end
    end
    player.print(string.format("[MDW test] warp-platform-size-1..%d researched -> platform size %d.",
        n, ctx.platform.warp.size))
end

local function cmd_cheat(command)
    local player = resolve(command, false)
    if not player then return end
    player.cheat_mode = not player.cheat_mode
    player.print("[MDW test] cheat_mode = " .. tostring(player.cheat_mode))
end

local function cmd_status(command)
    local player, force_name, ctx = resolve(command, true)
    if not ctx then return end
    local cur, prev = ctx.warp.current, ctx.warp.previous
    player.print(string.format("[MDW status] %s | dimension %d (warp #%d) | planet=%s | surface=%s | prev=%s | status=%s",
        force_name, ctx.warp.number + 1, ctx.warp.number, tostring(cur and cur.planet),
        has_surface(ctx) and cur.surface.name or "nil",
        prev and prev.name or "nil", tostring(ctx.warp.status)))
    player.print(string.format("[MDW status] timer active=%s base=%ds warp=%s manual=%s | platform.size=%d | victory=%s",
        tostring(ctx.timer.active), ctx.timer.base, tostring(ctx.timer.warp),
        tostring(ctx.timer.manual_warp), ctx.platform.warp.size, tostring(ctx.victory)))
end

commands.add_command("mdw-arm",    "[MDW test] research warp-generator-1 + unlock planets (arm warping)", cmd_arm)
commands.add_command("mdw-warp",   "[MDW test] warp now [optional exact planet, e.g. nauvis]", cmd_warp)
commands.add_command("mdw-warpx",  "[MDW test] warp <n> times in a row (max 10)", cmd_warpx)
commands.add_command("mdw-gen",    "[MDW test] research warp-generator-1..<N> (grow auto-warp interval)", cmd_gen)
commands.add_command("mdw-size",   "[MDW test] research warp-platform-size-1..<N> (grow platform)", cmd_size)
commands.add_command("mdw-cheat",  "[MDW test] toggle cheat mode", cmd_cheat)
commands.add_command("mdw-status", "[MDW test] print this team's warp state", cmd_status)
