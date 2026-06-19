-- Auto-warp timer label
------------------------------------------------------------
-- An in-world text line, one per team-owned surface, sitting just below the MTS
-- spawn label (team tag + location name at y=-8). It shows the team's live state:
--   * counting down  -> "Auto-warp in MM:SS"   (cool blue-white)
--   * not yet armed   -> "Warp generator not built" (muted grey)
--   * parked in space -> "Docked — resume to warp"  (warm amber, dock theme)
-- Refreshed once per second from the per-team ctx (the same cadence the warp loop
-- decrements ctx.timer.warp). The render ids are tracked on the ctx so they are
-- updated in place rather than recreated each tick, and pruned when a surface is
-- retired (e.g. the old world after a warp auto-destroys its render).

dw = dw or {}

-- Seconds -> "M:SS" (or "MM:SS"). Clamped at 0 so a momentary negative never
-- prints a stray "-1".
local function fmt_mmss(seconds)
    if type(seconds) ~= "number" or seconds < 0 then seconds = 0 end
    local m = math.floor(seconds / 60)
    local s = seconds % 60
    return string.format("%d:%02d", m, s)
end

-- The one line that applies to the whole team this second: localised text + colour.
local function compose_label(ctx)
    if ctx.warp.docked then
        -- Resume in progress: show the live resume countdown (ctx.timer.dock is
        -- armed + ticking to zero only once a member chooses resume) instead of the
        -- static docked line, in a warm "warp imminent" colour.
        if ctx.timer.dock then
            return {"dw-gui.autowarp-resuming", fmt_mmss(ctx.timer.dock)}, {r = 1.0, g = 0.72, b = 0.30}
        end
        return {"dw-gui.autowarp-docked"}, {r = 1.0, g = 0.85, b = 0.55}
    elseif not ctx.timer.active then
        -- Pre-generator: if the eviction backstop is counting down, show it as an
        -- urgent "dimension destabilising" timer so the pressure is visible; else
        -- the team simply hasn't built a warp generator yet.
        if ctx.timer.evict then
            return {"dw-gui.autowarp-unstable", fmt_mmss(ctx.timer.evict)}, {r = 1.0, g = 0.42, b = 0.30}
        end
        return {"dw-gui.autowarp-not-built"}, {r = 0.72, g = 0.72, b = 0.72}
    elseif ctx.votes.count >= ctx.votes.min_vote then
        -- A manual warp has been voted through: the manual countdown (ctx.timer.
        -- manual_warp) is now the operative clock, ticking to 0. Show it in a warm
        -- urgent colour instead of the auto line. reset_timer_vote zeroes the vote
        -- count when the warp fires, so this reverts to the auto line automatically.
        return {"dw-gui.manualwarp-countdown", fmt_mmss(ctx.timer.manual_warp or 0)},
            {r = 1.0, g = 0.66, b = 0.26}
    end
    return {"dw-gui.autowarp-countdown", fmt_mmss(ctx.timer.warp or ctx.timer.base)},
        {r = 0.75, g = 0.9, b = 1.0}
end

-- Collect the surfaces this team currently owns: its live warp/dock floor plus the
-- three permanent dimension floors (any may be absent if not yet unlocked). Keyed
-- by surface index, matching where MTS draws its spawn label.
local function team_surfaces(ctx)
    local out = {}
    local function add(s) if s and s.valid then out[s.index] = s end end
    if ctx.warp.current then add(ctx.warp.current.surface) end
    if ctx.platform then
        add(ctx.platform.factory and ctx.platform.factory.surface)
        add(ctx.platform.mining  and ctx.platform.mining.surface)
        add(ctx.platform.power   and ctx.platform.power.surface)
    end
    return out
end

local function update_warp_timer_labels(force_name, ctx)
    ctx.warp.timer_label_ids = ctx.warp.timer_label_ids or {}
    local text, color = compose_label(ctx)
    local surfaces = team_surfaces(ctx)

    -- Update existing labels in place; create any that are missing.
    for index, surface in pairs(surfaces) do
        local id  = ctx.warp.timer_label_ids[index]
        local obj = id and rendering.get_object_by_id(id)
        if obj and obj.valid then
            obj.text  = text
            obj.color = color
        else
            local new = rendering.draw_text{
                text               = text,
                surface            = surface,
                target             = {x = 0, y = -4.5},   -- just below the spawn label (y=-8)
                color              = color,
                scale              = 2.2,
                alignment          = "center",
                vertical_alignment = "middle",
                use_rich_text      = true,
            }
            ctx.warp.timer_label_ids[index] = new and new.id or nil
        end
    end

    -- Prune ids for surfaces this team no longer owns (post-warp the old world is
    -- gone; its render was auto-destroyed, leaving an invalid id behind).
    for index, id in pairs(ctx.warp.timer_label_ids) do
        if not surfaces[index] then
            local obj = rendering.get_object_by_id(id)
            if obj and obj.valid then obj.destroy() end
            ctx.warp.timer_label_ids[index] = nil
        end
    end
end

dw.register_team_tick(60, update_warp_timer_labels)
