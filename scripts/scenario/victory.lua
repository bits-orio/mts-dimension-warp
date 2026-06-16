--- Per-team, NON-TERMINAL victory (ADR-0007).
------------------------------------------------------------
-- Completing the `stabilize-dimensions` research is the win, attributed to the
-- researching force exactly as upstream DW did. Here it is fully per-team and
-- non-terminal: a finishing team simply stops warping and roams free, while
-- every other team keeps racing. We deliberately do NOT call
-- game.set_game_state{game_finished=true} (that ends EVERY team's game) and we
-- drop the global set_win_ending_info (it has no per-team variant). The finish
-- is announced to everyone as a ranked race result instead.
--
-- ctx resolution is guarded: only TEAM forces (force.name matches ^team-) get a
-- warp ctx, so a research event from a non-team force never creates a bogus ctx.

--- Announce a team's finish. Prefixed with the team's MTS rich-text label when
--- the mts-v1 interface is present, so the broadcast reads as "<Team> finished".
--- Falls back to a plain message if MTS isn't available.
local function announce_victory(force_name)
    local label
    if remote.interfaces["mts-v1"] then
        label = remote.call("mts-v1", "get_team_label", force_name)
    end
    if label then
        game.print({"dw-messages.stabilize-dimensions-victory-team", label})
    else
        game.print({"dw-messages.stabilize-dimensions-victory"})
    end
end

local function on_research_finished(event)
    if event.research.name ~= "stabilize-dimensions" then return end

    local force = event.research.force
    -- Only TEAM forces have a warp ctx. A research finishing on the
    -- spectator/player/landing-pen force has no team to win, so ignore it
    -- rather than lazily creating a bogus ctx via dw.warp_ctx.
    if not force.name:find("^team%-") then return end

    local ctx = dw.warp_ctx(force.name)
    ctx.victory = true

    -- Deactivate this team's warp timers (and only this team's): -1 parks the
    -- countdowns so warp_timer never triggers another warp for them.
    ctx.timer.base = -1
    ctx.timer.warp = -1

    -- Unlock the planet selector for this team -- the warp is now theirs to
    -- steer manually.
    ctx.gui.planet_selector_enabled = true

    announce_victory(force.name)
end

dw.register_event(defines.events.on_research_finished, on_research_finished)
