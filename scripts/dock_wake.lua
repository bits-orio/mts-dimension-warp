-- Slow "thaw from stasis" for a dock resuming its warp.
------------------------------------------------------------
-- On resume the dock thaws from the cold "frozen" look to the default night-sky
-- starfield. The VISIBLE driver is the daytime: it is darkened explicitly each tick
-- from a cold evening (FROZEN_DAYTIME) to the black default night (NIGHT_DAYTIME),
-- evenly, reaching the night value exactly when the forced warp fires
-- (start_tick + WAKE_TICKS == the warp tick). The cold indigo wash fades out
-- alongside as platform-local detail. No warming / brightening.
--
-- Driving the daytime each tick (rather than relying on freeze_daytime to hold and
-- only fading a faint wash) is deliberate: the wash alone is too subtle to read as
-- an animation; the whole-sky daytime change is what's actually visible.
--
-- DEBUG: dw.diag logs the start (with whether the cold wash actually exists) and a
-- once-per-second progress line (t, the daytime we set + read back, the wash alpha,
-- whether the wash render is still valid) so an in-game resume can be diagnosed from
-- factorio-current.log.
--
-- State lives in storage.dock_wakes (keyed by force name) until the warp retires the
-- dock or a re-freeze / warp-out cancels it. on_load needs no special handling.

dw = dw or {}

-- Reach the night value at DOCK_WAKE_SECONDS, then HOLD it: the driver clamps t to 1
-- and keeps re-pinning NIGHT_DAYTIME, so the dock SETTLES into the full black night
-- sky for the rest of the resume window instead of warping the instant it arrives.
local DOCK_WAKE_SECONDS = 6
local WAKE_TICKS  = DOCK_WAKE_SECONDS * 60
local DRIVER_NTH  = 3          -- update every 3 ticks (~20 Hz)
-- darkness is LINEAR in daytime only across the dusk(0.25)->evening(0.45) band, then
-- flat at 1.0. So sweep WITHIN that band -- 0.35 (darkness 0.5) to evening 0.45
-- (darkness 1.0) -- for an even, smooth darkening with no flat tail.
local FROZEN_DAYTIME = 0.35    -- cold "frozen" evening: dim + legible (the docked look)
local NIGHT_DAYTIME  = 0.45    -- evening = full darkness (with min_brightness 0, a pure-black sky)
local COLD        = {r = 0.10, g = 0.07, b = 0.22}   -- cold indigo wash (matches apply_dock_stasis)
local COLD_ALPHA  = 0.22                              -- its starting alpha (matches apply_dock_stasis)

local function clamp01(t) if t < 0 then return 0 elseif t > 1 then return 1 end return t end
local function obj(id) local o = id and rendering.get_object_by_id(id) return (o and o.valid) and o or nil end
local function set_alpha(id, c, a) local o = obj(id) if o then o.color = {r = c.r, g = c.g, b = c.b, a = a} end end
local function destroy(id) local o = obj(id) if o then o.destroy() end end

-- Begin the thaw for a freshly-resumed dock: take over the cold wash (created by
-- apply_dock_stasis, id on ctx.warp.dock_tint_id) so the driver can fade it, and
-- play a soft cue.
function dw.start_dock_wake(force_name, ctx, surface, start_tick)
    if not (surface and surface.valid) then
        dw.diag("dock_wake START force=%s ABORT: no surface", tostring(force_name))
        return
    end
    dw.cancel_dock_wake(force_name)        -- never stack two thaws on one team
    storage.dock_wakes = storage.dock_wakes or {}
    local cold_id = ctx.warp.dock_tint_id
    storage.dock_wakes[force_name] = {
        surface_name = surface.name,
        start_tick   = start_tick,
        cold_id      = cold_id,
    }
    ctx.warp.dock_tint_id = nil            -- the thaw owns the wash now
    surface.play_sound{path = "dw-teleport"}
    dw.diag("dock_wake START force=%s surface=%s cold_valid=%s", force_name, surface.name, tostring(obj(cold_id) ~= nil))
end

-- Stop + clean up a team's thaw (interrupted resume, or warp-out). Safe to call
-- when none is active.
function dw.cancel_dock_wake(force_name)
    local w = storage.dock_wakes and storage.dock_wakes[force_name]
    if not w then return end
    destroy(w.cold_id)
    storage.dock_wakes[force_name] = nil
    dw.diag("dock_wake CANCEL force=%s", tostring(force_name))
end

local function drive_wakes()
    local wakes = storage.dock_wakes
    if not wakes then return end
    for force_name, w in pairs(wakes) do
        local surface = game.surfaces[w.surface_name]
        if not (surface and surface.valid) then
            destroy(w.cold_id); wakes[force_name] = nil
            dw.diag("dock_wake END force=%s (surface gone)", force_name)
        else
            local elapsed = game.tick - w.start_tick
            local t = clamp01(elapsed / WAKE_TICKS)
            local daytime = FROZEN_DAYTIME + (NIGHT_DAYTIME - FROZEN_DAYTIME) * t
            surface.daytime = daytime
            surface.freeze_daytime = true
            -- The wash fades to alpha 0 (reaching it as the sky hits full dark, since
            -- NIGHT_DAYTIME = evening) and RESTS there -- it is NOT destroyed mid-thaw.
            -- Destroying it (cold_valid true->false) on the dark sky is the pop the
            -- user verified; cleanup happens at cancel (warp-out / re-freeze), where
            -- the warp cut masks it.
            if w.cold_id then set_alpha(w.cold_id, COLD, COLD_ALPHA * (1 - t)) end
        end
    end
end

dw.register_event("on_nth_tick_" .. DRIVER_NTH, drive_wakes)
