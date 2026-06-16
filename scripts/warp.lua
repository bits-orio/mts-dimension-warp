--- warp between surface and timers are managed in this file
------------------------------------------------------------
-- v1 CORE port: the warp loop is now PER-TEAM. Every storage.warp/timer/votes
-- read+write is threaded through ctx (the storage.teams[force_name] bundle from
-- scripts/warp_ctx.lua), and the loop is driven by dw.register_team_tick so it
-- runs once per team each period. game.forces.player becomes game.forces[force_name].
--
-- EXPECTED stale (slices 4-7): the aux helpers this loop still calls
-- (dw.set_warp_evolution_factor, dw.gui.*, dw.platforms.*, dw.update_warp_platform_size,
-- storage.warpgate.*) keep reading the flat globals for now. That divergence is
-- intentional and must NOT be "fixed" here.
dw.warp = dw.warp or {}

local function calculate_manual_warp_time(ctx)
    local base_time = 10 --seconds
    local max_time = settings.global['dw-manual-warp-max-time'].value * 60
    local warp_zone = math.floor(ctx.warp.number * settings.global['dw-manual-warp-zone-multiplier'].value)

    return math.min(max_time, math.floor(base_time + warp_zone ^ 1.35))
end

local function get_allowed_planet(force_name, ctx)
    local force = game.forces[force_name]
    local allowed_planets = {}
    local total = 0
    local current = ctx.warp.current.surface
    local current_require_heat = current.planet.prototype.entities_require_heating
    for _, planet in pairs(game.planets) do
        -- remove nauvis, dimension surfaces from the list
        if not utils.ignore_planet(planet.name) then
            if force.is_space_location_unlocked(planet.name) then
                if current_require_heat and planet.name == current.planet.name then
                    goto continue
                end
                table.insert(allowed_planets, planet.name)
                total = total + 1

                ::continue::
            end
        end
    end
    return total, allowed_planets
end


local function select_destination(force_name, ctx)
    local total_dest, destinations = get_allowed_planet(force_name, ctx)
    if ctx.warp.preferred_destination then
        if ctx.warp.preferred_destination == "nauvis" then
            return "nauvis"
        end
        for _, dest in pairs(destinations) do
            if dest == ctx.warp.preferred_destination then
                return math.random() < 0.7 and dest or destinations[math.random(total_dest)]
            end
        end
    end
    return destinations[math.random(total_dest)]
end

local function prepare_warp_to_next_surface(force_name, ctx, target)
    if ctx.warp.status ~= defines.warp.awaiting then return end
    ctx.warp.status = defines.warp.preparing

    -- generate_surface advances ctx to the new surface (or rolls back on a failed
    -- MTS create). Only clone the platform + retire the old surface if it succeeded;
    -- on failure, drop back to awaiting so the team simply retries next expiry.
    if not dw.generate_surface(force_name, ctx, target) then
        ctx.warp.status = defines.warp.awaiting
        return
    end

    ctx.warp.status = defines.warp.warping
    dw.teleport_platform(force_name, ctx)

    -- Retire the previous surface now that the platform has been cloned onto the
    -- new one. CORE drives this directly (event-driven) rather than relying on a
    -- callback from the excluded aux teleport_platform -- see surface-generation.lua.
    dw.update_surfaces_properties(force_name, ctx)
end

local function reset_timer_vote(ctx)
    -- reset all timers / globals
    ctx.timer.warp = ctx.timer.base
    ctx.timer.manual_warp = calculate_manual_warp_time(ctx)
    ctx.warp.time = game.tick

    -- reset warp votes
    ctx.votes.count = 0
    ctx.votes.players = {}

end

local function warp_timer(force_name, ctx)
    -- Skip a team MTS has paused: no warp clock, no ticking, no warp.
    if remote.call('mts-v1', 'is_team_paused', force_name) then return end

    if not ctx.nauvis_lab_exploded then return end

    if ctx.timer.active then
        if ctx.timer.warp >= 0 then
            ctx.timer.warp = ctx.timer.warp - 1
        end

        if ctx.votes.count >= ctx.votes.min_vote then
            ctx.timer.manual_warp = ctx.timer.manual_warp - 1
        else
            ctx.timer.manual_warp = math.max(10, ctx.timer.manual_warp - 1)
        end

        if (ctx.timer.warp < 60 and ctx.timer.warp > 0) or ctx.timer.manual_warp < 10 then
            if game.tick % (3 * 60) == 0 then
                game.play_sound{path = "dw-alarm"}
            end
        end

        if (not ctx.victory and ctx.timer.warp <= 0) or ctx.timer.manual_warp <= 0 then

            local target = select_destination(force_name, ctx)
            if target == "nauvis" and ctx.warp.current.planet == "nauvis" then
                game.print({"dw-messages.stay-on-nauvis"})
                reset_timer_vote(ctx)
                dw.gui.update_manual_warp_button()
            else
                -- return warp gate
                if storage.warpgate.mobile_gate then
                    storage.warpgate.mobile_gate.destroy{raise_destroy=true}
                end
                -- harvesters recall
                dw.platforms.recall_harvester("left")
                dw.platforms.recall_harvester("right")

                -- generate new surface and teleport
                prepare_warp_to_next_surface(force_name, ctx, target)
                -- play sound
                game.play_sound{path = "dw-warpdrive"}
                if ctx.warp.message then game.print({ctx.warp.message}) end
                ctx.warp.message = nil

                reset_timer_vote(ctx)

                -- reset evolution based on warp number
                dw.set_warp_evolution_factor()
                ctx.pollution = 1
                dw.gui.update_manual_warp_button()

                -- once everything's done, force recreate the tiles in platforms (because some explosions may break some.)
                dw.update_warp_platform_size()
                if storage.platform.factory.surface then dw.platforms.init_update_factory_platform() end
                if storage.harvesters.left.gate then dw.platforms.place_harvester_tiles("left") end
                if storage.harvesters.right.gate then dw.platforms.place_harvester_tiles("right") end
                if storage.platform.mining.surface then dw.platforms.init_update_mining_platform() end
                if storage.platform.power.surface then dw.platforms.init_update_power_platform() end
            end
        end
    end

    --- each seconds, we update the GUI
    dw.gui.update()
end
dw.warp.warp_timer = warp_timer


local function update_warp_vote_threshold()
    local new_vote_threshold = math.max(1, math.ceil(storage.votes.players_count * settings.global['dw-min-warp-voter'].value))
    --- reset warp votes if the threshold changed
    if storage.votes.min_vote ~= new_vote_threshold then
        storage.votes.min_vote = new_vote_threshold
        storage.votes.count = 0
        storage.votes.players = {}
        dw.gui.update_manual_warp_button()
    end
end

-- Flat-global manual-warp time, for the still-stale research handler below.
-- EXPECTED stale (slices 4-7): warp_generator_research reads the flat globals
-- (dead but seeded). Kept byte-faithful to upstream so it can't crash; the
-- per-team timer is actually armed by mts_lifecycle on_team_clock_started.
local function calculate_manual_warp_time_flat()
    local base_time = 10 --seconds
    local max_time = settings.global['dw-manual-warp-max-time'].value * 60
    local warp_zone = math.floor(storage.warp.number * settings.global['dw-manual-warp-zone-multiplier'].value)

    return math.min(max_time, math.floor(base_time + warp_zone ^ 1.35))
end

local function warp_generator_research(event)
    local tech = event.research
    if tech.name == "warp-generator-1" then
        storage.timer.active = true
        storage.timer.manual_warp = calculate_manual_warp_time_flat()
        game.print({"dw-messages.warp-generator-1"})
    end
    if string.match(tech.name, "warp%-generator%-%d+") then
        if tech.level < 6 then
            storage.timer.base =  (20 + (tech.level - 1)  * 10) * 60
        else
            storage.timer.base = storage.timer.base + 30 * 60
        end
        if not storage.timer.warp then
            storage.timer.warp = storage.timer.base
        end
        dw.gui.update_manual_warp_button()
    end
    if tech.name == "warp-preferred-planet" then
        storage.gui.planet_selector_enabled = true
    end
end


local function update_warp_vote_join(event)
    storage.votes.players_count = storage.votes.players_count + 1
    update_warp_vote_threshold()
end


local function update_warp_vote_leave(event)
    storage.votes.players_count = storage.votes.players_count - 1
    update_warp_vote_threshold()
end


-- Per-team warp loop: register_team_tick fans this out once per team each
-- second, calling warp_timer(force_name, ctx). Replaces the upstream global
-- on_nth_tick_60 singleton.
dw.register_team_tick(60, warp_timer)
dw.register_event(defines.events.on_research_finished, warp_generator_research)
dw.register_event(defines.events.on_player_joined_game, update_warp_vote_join)
dw.register_event(defines.events.on_player_left_game, update_warp_vote_leave)
dw.register_event(defines.events.on_player_kicked, update_warp_vote_leave)
