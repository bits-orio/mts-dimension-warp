-- scripts/selftest.lua
--
-- In-engine self-test harness for the two dock bugs:
--   1. Pollution chunk-gen on docked surfaces  (pollute must skip docked teams)
--   2. Dock-surface orphan leak                (retire must not silently drop a
--      surface it fails to delete; existing orphans must be cleanable)
--
-- Runs in MDW's own Lua state (full access to dw.* / storage / remote), exposed
-- via the "mdw-selftest" remote interface so it can be driven over RCON:
--
--   /sc rcon.print(remote.call("mdw-selftest", "run"))
--
-- Every test is SYNCHRONOUS: it asserts on return values and pollution deltas,
-- not on async surface deletion completing, so a single command yields a
-- deterministic PASS/FAIL report. Test surfaces use tick-unique names so repeat
-- runs never collide with a still-deleting surface from a prior run.

dw = dw or {}

local TEST_PLANET = "neo-nauvis"

local function mg()
    local p = game.planets[TEST_PLANET]
    return p and p.prototype.map_gen_settings or game.surfaces.nauvis.map_gen_settings
end

local function make_surface(tag)
    local name = "mdw-selftest-" .. tag .. "-" .. game.tick
    local s = game.create_surface(name, mg())
    s.request_to_generate_chunks({0, 0}, 2)
    s.force_generate_chunk_requests()
    return s
end

-- Dock-named test surface (matches the orphan-cleanup name pattern).
local function make_surface_dock(team_num)
    local name = "mdw-team-" .. team_num .. "-dock-w" .. game.tick
    local s = game.create_surface(name, mg())
    s.request_to_generate_chunks({0, 0}, 2)
    s.force_generate_chunk_requests()
    return s
end

-- A minimal warp ctx good enough for pollute(): it only touches timer/victory,
-- platform.{factory,mining,power}.surface (nil-safe), pollution, warp.current.
local function fake_ctx(surface, docked)
    return {
        timer    = { active = true },
        victory  = false,
        pollution = 1000,
        platform = { factory = {}, mining = {}, power = {} },
        warp     = { docked = docked, current = { surface = surface, name = surface.name } },
    }
end

local function first_team_force()
    for name in pairs(game.forces) do
        if name:find("^team%-%d+$") then return name end
    end
    return "team-1"
end

-- ── Tests ─────────────────────────────────────────────────────────────
-- Each returns (ok:boolean, detail:string).

-- BUG 1: a docked team's pollute() must inject NO new pollution AND clear any
-- existing cloud (so a bloated save self-heals). Seed pollution, expect 0 after.
local function t_pollute_skips_docked()
    local s = make_surface("polldock")
    s.pollute({0, 0}, 5000)                 -- pre-existing dock cloud to be cleared
    local ctx = fake_ctx(s, true)
    dw.pollute("team-selftest", ctx)
    local after = s.get_total_pollution()
    game.delete_surface(s)
    return (after == 0),
        string.format("docked pollute -> total=%.0f (expect 0: no inject + cleared)", after)
end

-- CRASH GUARD: pollute() must not crash for an active team that has no valid
-- current surface (mid-setup, or a surface recycled by a disband+slot reuse).
local function t_pollute_no_surface_no_crash()
    local ctx = {
        timer = { active = true }, victory = false, pollution = 1000,
        platform = { factory = {}, mining = {}, power = {} },
        warp = { docked = false, current = {} },   -- current.surface == nil
    }
    local ok, err = pcall(dw.pollute, "team-selftest", ctx)
    return ok, ok and "no crash with nil current surface" or ("CRASHED: " .. tostring(err))
end

-- REGRESSION: a live (non-docked) team's pollute() must still add pollution.
local function t_pollute_runs_when_active()
    local s = make_surface("pollact")
    local ctx = fake_ctx(s, false)
    local before = s.get_total_pollution()
    dw.pollute("team-selftest", ctx)
    local after = s.get_total_pollution()
    game.delete_surface(s)
    return (after > before),
        string.format("active pollute before=%.0f after=%.0f (expect after>before)", before, after)
end

-- BUG 2a: retiring a previous surface MTS no longer owns must still remove it
-- (fallback delete), not silently leak it. We assert the returned status.
local function t_retire_fallback_on_unowned()
    local s = make_surface("orphan")
    local force = first_team_force()   -- a real team that does NOT own `s`
    local ctx = {
        warp = {
            status   = defines.warp.warping,
            previous = { surface = s, name = s.name, index = s.index },
            current  = { surface = s, name = s.name },
        },
    }
    local status = dw.update_surfaces_properties(force, ctx)
    -- surface delete is async; the status proves the fallback path executed
    return (status == "deleted_fallback"),
        string.format("unowned previous -> status=%s (expect deleted_fallback)", tostring(status))
end

-- BUG 2b: cleanup deletes an orphan dock surface but preserves a referenced one.
local function t_cleanup_orphan_keeps_referenced()
    local orphan = make_surface_dock("98")   -- unreferenced
    local keep   = make_surface_dock("99")   -- referenced via the live override
    local pattern = "^mdw%-team%-9[89]%-dock%-w"   -- isolate to just these two
    local live = { [keep.name] = true }
    local n, names = dw.cleanup_orphan_dock_surfaces(live, pattern)
    local keep_alive = game.surfaces[keep.name] ~= nil and game.surfaces[keep.name].valid
    if game.surfaces[keep.name] then game.delete_surface(keep.name) end
    local ok = (n == 1 and names[1] == orphan.name and keep_alive)
    return ok, string.format("deleted=%d names=[%s] keep_alive=%s (expect 1, orphan only, true)",
        n, table.concat(names, ","), tostring(keep_alive))
end

-- BUG 3: disbanding a team must delete its mts-v1 surfaces (docks / warp worlds),
-- which live only in MTS's surface_owner_overrides map -- not just the legacy
-- 'team-N-' prefixed / variant-map surfaces. We drive a real disband_team through
-- the mts-v1 API on a synthetic team and assert the surface's ownership was swept
-- (owner -> nil). The actual surface delete is async; ownership clearing is the
-- synchronous proof that cleanup_force_surfaces processed the override entry (and
-- it always calls game.delete_surface alongside). End-to-end deletion is covered
-- by the integration check on a real team.
local function t_disband_sweeps_surface()
    local fn = "team-77"
    if not game.forces[fn] then game.create_force(fn) end
    local nm = "mdw-team-77-dock-w" .. game.tick
    remote.call("mts-v1", "create_team_surface", fn, { name = nm, planet = TEST_PLANET, map_gen_settings = mg() })
    local existed      = game.surfaces[nm] ~= nil
    local owner_before = remote.call("mts-v1", "get_surface_owner", nm)
    remote.call("mts-v1", "disband_team", fn)
    local owner_after  = remote.call("mts-v1", "get_surface_owner", nm)
    local ok = (existed and owner_before == fn and owner_after == nil)
    return ok, string.format("created=%s owner_before=%s owner_after=%s (expect true, %s, nil)",
        tostring(existed), tostring(owner_before), tostring(owner_after), fn)
end

-- ── Runner ────────────────────────────────────────────────────────────

local TESTS = {
    { "pollute_skips_docked",        t_pollute_skips_docked },
    { "pollute_no_surface_no_crash", t_pollute_no_surface_no_crash },
    { "pollute_runs_when_active",    t_pollute_runs_when_active },
    { "retire_fallback_on_unowned",  t_retire_fallback_on_unowned },
    { "cleanup_orphan_keeps_kept",   t_cleanup_orphan_keeps_referenced },
    { "disband_sweeps_surface",      t_disband_sweeps_surface },
}

function dw.run_selftest()
    local lines = { "=== MDW selftest ===" }
    local passed = 0
    for _, t in ipairs(TESTS) do
        local name, fn = t[1], t[2]
        local pok, tok, detail = pcall(fn)
        local pass = pok and tok and true or false
        local msg
        if not pok then msg = "ERROR: " .. tostring(tok) else msg = tostring(detail) end
        if pass then passed = passed + 1 end
        lines[#lines + 1] = string.format("[%s] %-30s %s", pass and "PASS" or "FAIL", name, msg)
    end
    lines[#lines + 1] = string.format("=== %d/%d passed ===", passed, #TESTS)
    return table.concat(lines, "\n")
end

if not (remote.interfaces["mdw-selftest"]) then
    remote.add_interface("mdw-selftest", {
        run = function() return dw.run_selftest() end,
        -- Integration helper: run the real orphan sweep over storage.teams.
        cleanup_real = function()
            local n, names = dw.cleanup_orphan_dock_surfaces()
            return { n = n, names = names }
        end,
    })
end
