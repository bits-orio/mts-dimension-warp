--- Manage the pollution and enemies behavior (per-team)
------------------------------------------------------------
-- Each team has its own surfaces and its own warp state machine
-- (storage.teams[force_name], see scripts/warp_ctx.lua). Pollution accrual and
-- forced attacks therefore run once per team against that team's ctx, driven by
-- dw.register_team_tick rather than a single global on_nth_tick handler.

--- Remove pollution from a team's platform surfaces and add it to that team's
--- accumulated value, then pollute the warp surface (to trigger bases & cie)
--- based on warptorio original formula, as it was already really good.
local function pollute(force_name, ctx)
	if not ctx.timer.active or ctx.victory then return end
	local pollution = 0

	-- get platform pollution and clear it there
	pollution = pollution + (ctx.platform.factory.surface and ctx.platform.factory.surface.get_total_pollution() or 0)
	pollution = pollution + (ctx.platform.mining.surface and ctx.platform.mining.surface.get_total_pollution() or 0)
	pollution = pollution + (ctx.platform.power.surface and ctx.platform.power.surface.get_total_pollution() or 0)

	if ctx.platform.factory.surface then ctx.platform.factory.surface.clear_pollution() end
	if ctx.platform.mining.surface then ctx.platform.mining.surface.clear_pollution() end
	if ctx.platform.power.surface then ctx.platform.power.surface.clear_pollution() end

	--- leave a max, but if we pollute every 3 sec, it's still around 5.2h before we reach the max
	ctx.pollution = math.min(1000000, ctx.pollution + (ctx.pollution ^ 0.25) * 0.75)

	pollution = pollution + ctx.pollution * settings.global['dw-helper-pollution-multiplier'].value
	ctx.warp.current.surface.pollute({-1, 0}, pollution, "radio-station")
end

--- Force enemies in a given radius to attack everything on a team's warp surface.
local function force_enemy_attack(force_name, ctx)
	if dw.rampant.active then return end -- rampant already manages this.
	local force_attack_wave = settings.global['dw-helper-enemy-force-attack'].value
	if not ctx.timer.active then return end
	if ctx.warp.number < force_attack_wave then return end
	local time_passed = (game.tick - ctx.warp.time) / 3600
	if time_passed <= 10 then return end --- at least 10min on planet
	ctx.warp.current.surface.set_multi_command{
		command = {
			type = defines.command.attack_area,
			destination = {0, 0},
			radius = math.floor(ctx.platform.warp.size / 2),
			distraction = defines.distraction.by_enemy
		},
		unit_count = 500,
		unit_search_distance = math.min(5000, 3000 * ((time_passed - 10) / 30))
	}
end

--- Calculate and set the new evolution value when warping depending on warp number,
--- scoped to THIS team's warp surface only (called from warp.lua's
--- prepare_warp_to_next_surface, which passes (force_name, ctx)).
local function set_warp_evolution_factor(force_name, ctx)
	-- ctx.warp.number / 5 only makes sure we have an increase before the exponent starts.
	-- warp 100 = 0.25, 150 = 0.414, 200 = 0.656, 243+ = 1
	local biter_evolution = math.min(100, 1.5 ^ (ctx.warp.number / 25) + ctx.warp.number / 5) / 100

	-- warp 100 = 0.23, 150 = 0.358, 200 = 0.505, 250 = 0.689, 300 = 0.94, 310+ = 1
	local pentapod_evolution = math.min(100, 1.8 ^ (ctx.warp.number / 50) + ctx.warp.number / 5) / 100

	if ctx.warp.current.planet ~= "gleba" then
		game.forces.enemy.set_evolution_factor(biter_evolution, ctx.warp.current.surface)
	else
		game.forces.enemy.set_evolution_factor(pentapod_evolution, ctx.warp.current.surface)
	end
end
dw.set_warp_evolution_factor = set_warp_evolution_factor

dw.register_team_tick(180, pollute)
dw.register_team_tick(7200, force_enemy_attack)
