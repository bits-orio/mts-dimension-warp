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
    -- ctx.warp.current.planet is the STRING planet name (always set). The
    -- surface's LuaPlanet (ctx.warp.current.surface.planet) is NIL for our nauvis
    -- warp surfaces -- create_team_surface only associate_surface's NON-nauvis
    -- planets -- so derive the current planet from the name, not surface.planet.
    local current_planet_name = ctx.warp.current.planet
    local current_planet = current_planet_name and game.planets[current_planet_name]
    local current_require_heat = current_planet and current_planet.valid
        and current_planet.prototype.entities_require_heating or false
    dw.diag("get_allowed_planet force=%s current_planet=%s require_heat=%s",
        force_name, tostring(current_planet_name), tostring(current_require_heat))
    for _, planet in pairs(game.planets) do
        -- remove nauvis, dimension surfaces from the list
        if not utils.ignore_planet(planet.name) then
            if force.is_space_location_unlocked(planet.name) then
                if current_require_heat and planet.name == current_planet_name then
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
    -- Test override (set by the /mdw-warp admin command): force a one-shot exact
    -- destination, bypassing the unlocked-planet filter + randomness. Consumed
    -- here so it never leaks into a subsequent real auto-warp.
    if ctx.warp.test_destination then
        local forced = ctx.warp.test_destination
        ctx.warp.test_destination = nil
        dw.diag("select_destination[%s]: TEST override -> %s", force_name, tostring(forced))
        return forced
    end
    local total_dest, destinations = get_allowed_planet(force_name, ctx)
    -- No unlocked planets: warp to nauvis rather than indexing destinations with
    -- math.random(0), whose empty interval errors. A team with nothing unlocked
    -- simply falls back to nauvis.
    if total_dest == 0 then
        dw.diag("select_destination[%s]: no unlocked destinations -> nauvis", force_name)
        return "nauvis"
    end
    if ctx.warp.preferred_destination then
        if ctx.warp.preferred_destination == "nauvis" then
            dw.diag("select_destination[%s]: preferred=nauvis -> nauvis (allowed=%d)", force_name, total_dest)
            return "nauvis"
        end
        for _, dest in pairs(destinations) do
            if dest == ctx.warp.preferred_destination then
                local chosen = math.random() < 0.7 and dest or destinations[math.random(total_dest)]
                dw.diag("select_destination[%s]: preferred=%s -> %s (allowed=%d)",
                    force_name, ctx.warp.preferred_destination, chosen, total_dest)
                return chosen
            end
        end
    end
    local chosen = destinations[math.random(total_dest)]
    dw.diag("select_destination[%s]: random -> %s (allowed=%d)", force_name, tostring(chosen), total_dest)
    return chosen
end

local function prepare_warp_to_next_surface(force_name, ctx, target)
    dw.diag("prepare_warp[%s]: ENTER status=%s target=%s from=%s",
        force_name, tostring(ctx.warp.status), tostring(target), dw.diag_surface(ctx.warp.current.surface))
    if ctx.warp.status ~= defines.warp.awaiting then return end
    ctx.warp.status = defines.warp.preparing

    -- generate_surface advances ctx to the new surface (or rolls back on a failed
    -- MTS create). Only clone the platform + retire the old surface if it succeeded;
    -- on failure, drop back to awaiting so the team simply retries next expiry.
    if not dw.generate_surface(force_name, ctx, target) then
        dw.diag("prepare_warp[%s]: generate_surface=false -> rollback to awaiting", force_name)
        ctx.warp.status = defines.warp.awaiting
        return
    end
    dw.diag("prepare_warp[%s]: generate_surface=true -> %s", force_name, dw.diag_surface(ctx.warp.current.surface))

    dw.diag("prepare_warp[%s]: status preparing -> warping", force_name)
    ctx.warp.status = defines.warp.warping
    dw.teleport_platform(force_name, ctx)

    -- Retire the previous surface now that the platform has been cloned onto the
    -- new one. CORE drives this directly (event-driven) rather than relying on a
    -- callback from the excluded aux teleport_platform -- see surface-generation.lua.
    dw.update_surfaces_properties(force_name, ctx)
    dw.diag("prepare_warp[%s]: DONE now on %s (warp_number=%d)",
        force_name, tostring(ctx.warp.current.name), ctx.warp.number)
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
    if remote.call('mts-v1', 'is_team_paused', force_name) then
        -- Only note the skip at the moment it actually matters: the warp clock has
        -- expired and we WOULD have warped this tick were the team not paused.
        -- Stays out of the idle path (a paused, mid-countdown team logs nothing).
        if ctx.timer.active and ((not ctx.victory and ctx.timer.warp and ctx.timer.warp <= 0)
            or (ctx.timer.manual_warp and ctx.timer.manual_warp <= 0)) then
            dw.diag("warp_timer[%s]: SKIP warp -- team paused (warp=%s manual=%s votes=%d/%d)",
                force_name, tostring(ctx.timer.warp), tostring(ctx.timer.manual_warp),
                ctx.votes.count, ctx.votes.min_vote)
        end
        return
    end

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
            local manual = ctx.timer.manual_warp <= 0
            dw.diag("warp_timer[%s]: TRIGGER warp_number=%d warp=%d manual_warp=%d manual=%s votes=%d/%d",
                force_name, ctx.warp.number, ctx.timer.warp, ctx.timer.manual_warp,
                tostring(manual), ctx.votes.count, ctx.votes.min_vote)

            local target = select_destination(force_name, ctx)
            if target == "nauvis" and ctx.warp.current.planet == "nauvis" then
                dw.diag("warp_timer[%s]: STAY on nauvis (target=nauvis, already on nauvis)", force_name)
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

                -- reset evolution based on warp number (per-team surface)
                dw.set_warp_evolution_factor(force_name, ctx)
                ctx.pollution = 1
                dw.gui.update_manual_warp_button()

                -- once everything's done, force recreate the tiles in platforms (because some explosions may break some.)
                dw.update_warp_platform_size(force_name, ctx)
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

-- Per-team research gate (restores DW's warp-generator progression). DW gated
-- ALL warping behind researching warp-generator-1 (it armed storage.timer.active)
-- and grew the auto-warp interval with warp-generator-2..6. MTS team forces
-- research independently, so resolve event.research.force -> that team's ctx and
-- mutate ONLY ctx.timer.* -- never the flat globals. Until a team researches
-- warp-generator-1 it stays "dark": no warp button, no auto-warp countdown (the
-- warp loop is wrapped in `if ctx.timer.active`), exactly DW's "build the
-- generator first" onboarding.
local function warp_generator_research(event)
    local tech = event.research
    local force = tech.force
    -- Only team forces have a warp ctx; ignore player/spectator/enemy/neutral.
    if not force.name:find("^team%-") then return end
    if not dw.has_warp_ctx(force.name) then return end
    local ctx = dw.warp_ctx(force.name)

    if tech.name == "warp-generator-1" then
        -- THE GATE: this team's warp timer comes online. force.print (NOT
        -- game.print) so one team's progress isn't broadcast to every team.
        ctx.timer.active = true
        ctx.timer.manual_warp = calculate_manual_warp_time(ctx)
        force.print({"dw-messages.warp-generator-1"})
        dw.diag("warp-generator-1 researched: force=%s -> warp timer ARMED", force.name)
    end
    -- warp-generator-1 ALSO matches this %d+ block (level 1), so the interval is
    -- seeded on gen-1 too -- byte-faithful to DW. Do NOT early-return above.
    if string.match(tech.name, "warp%-generator%-%d+") then
        if tech.level < 6 then
            ctx.timer.base = (20 + (tech.level - 1) * 10) * 60
        else
            ctx.timer.base = ctx.timer.base + 30 * 60
        end
        -- Load-bearing seed: if warp-generator-1 is researched BEFORE
        -- on_team_clock_started fires (a staged-start team), this is the only
        -- thing making ctx.timer.warp non-nil when active flips true, so
        -- warp_timer's `ctx.timer.warp >= 0` never compares nil. regate_existing_
        -- teams backfills the same way. Do not remove.
        if not ctx.timer.warp then
            ctx.timer.warp = ctx.timer.base
        end
        dw.gui.update_manual_warp_button()
        dw.diag("warp-generator-%d researched: force=%s -> timer.base=%ds",
            tech.level, force.name, ctx.timer.base)
    end
    if tech.name == "warp-preferred-planet" then
        ctx.gui.planet_selector_enabled = true
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
