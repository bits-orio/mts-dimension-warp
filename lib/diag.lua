-- lib/diag.lua
-- Lightweight diagnostic logging for tracing the warp flow and key lifecycle
-- events. Writes to factorio-current.log via the engine's log(). Every line is
-- tick-stamped and prefixed "[mdw]" so it's easy to grep.
--
-- Flip DIAG to false to silence everything (or later wire it to a runtime mod
-- setting). Kept verbose on purpose while the per-team warp loop is stabilising.

dw = dw or {}

local DIAG = true

--- Log a diagnostic line. Accepts a plain string, or a string.format pattern
--- plus args:  dw.diag("warp %s -> %s", a, b)
function dw.diag(fmt, ...)
    if not DIAG then return end
    local msg = (select("#", ...) > 0) and string.format(fmt, ...) or tostring(fmt)
    log("[mdw] @" .. ((game and game.tick) or 0) .. " | " .. msg)
end

--- Helper: a compact "<name>#<index>" for a surface, or "nil".
function dw.diag_surface(surface)
    if not (surface and surface.valid) then return "nil" end
    return surface.name .. "#" .. surface.index
end
