--- Surface generation and randomization
------------------------------------------------------------
require "scripts.planets.neo-nauvis"
if script.active_mods['space-age'] then
    require "scripts.planets.fulgora"
    require "scripts.planets.gleba"
    require "scripts.planets.vulcanus"
    require "scripts.planets.aquilo"
end

local function force_map_settings()
    game.map_settings.pollution.enabled = true
    game.map_settings.pollution.diffusion_ratio = 0.105
    game.map_settings.pollution.min_to_diffuse = 15
    game.map_settings.pollution.ageing = 1.0
    game.map_settings.pollution.expected_max_per_chunk = 250
    game.map_settings.pollution.min_to_show_per_chunk = 50
    game.map_settings.pollution.pollution_restored_per_tree_damage = 9
    game.map_settings.pollution.enemy_attack_pollution_consumption_modifier = 1.0

    game.map_settings.enemy_evolution.enabled = true --
    game.map_settings.enemy_evolution.time_factor = 0.000006 -- default 0.000004
    game.map_settings.enemy_evolution.destroy_factor = 0.0002 -- default 0.002
    game.map_settings.enemy_evolution.pollution_factor = 0.0000005 -- default 0.0000009

    game.map_settings.unit_group.min_group_gathering_time = 600
    game.map_settings.unit_group.max_group_gathering_time = 2 * 600
    game.map_settings.unit_group.max_unit_group_size = 200
    game.map_settings.unit_group.max_wait_time_for_late_members = 2 * 360

    game.map_settings.enemy_expansion.enabled = true
    game.map_settings.enemy_expansion.settler_group_min_size = 1
    game.map_settings.enemy_expansion.settler_group_max_size = 1
end

------------------------------------------------------------
--- Deterministic fairness seed (ADR-0005)
------------------------------------------------------------
-- A warp world's seed is a PURE function of (map_seed, planet, warp_number) with
-- no team identity, so any two teams that reach the same planet at the same warp
-- number face the byte-identical world. This replaces stock DW's per-warp
-- randomization (math.random + game.tick), which is unacceptable for MTS's
-- competitive races. math.random / game.tick anywhere on this path is a bug --
-- it breaks both fairness and save reproducibility.

-- The host's chosen map seed. nauvis always exists, and its seed equals the
-- game's chosen map seed (same source MTS uses in surface_utils.seed_for_base).
local function map_seed()
    local nauvis = game.surfaces["nauvis"]
    return (nauvis and nauvis.valid) and nauvis.map_gen_settings.seed or 0
end

-- Sum the byte codes of a string into the mix. Cheap, order-sensitive, and
-- deterministic across peers (no hashing libs, no engine state).
local function fold_string(acc, s)
    for i = 1, #s do
        acc = (acc * 31 + s:byte(i)) % 4294967296 -- mod 2^32 to stay in range
    end
    return acc
end

-- hash(map_seed, planet, warp_number) -> uint32. A small deterministic mixer:
-- fold the map seed, the planet name, and the warp number together. No
-- randomness, no tick -- identical inputs always yield the identical seed.
local function fairness_seed(planet, warp_number)
    local acc = map_seed() % 4294967296
    acc = fold_string(acc, tostring(planet))
    acc = (acc * 31 + warp_number) % 4294967296
    -- final avalanche so adjacent warp numbers don't yield adjacent seeds
    acc = (acc * 2654435761) % 4294967296
    return math.floor(acc)
end

------------------------------------------------------------
--- Per-team surface generation (MTS owns birth/death -- ADR-0004)
------------------------------------------------------------
-- generate_surface(force_name, ctx, target): advance ONE team to its next warp
-- surface. MTS is the sole surface authority: MDW asks MTS to create the next
-- surface and to retire the previous one; MDW only supplies the per-planet
-- map_gen knowledge and the deterministic seed.
--
-- DIVERGENCE from upstream: upstream created/deleted surfaces itself
-- (game.create_surface / game.delete_surface) and randomized per warp. Here
-- create_team_surface / retire_team_surface (mts-v1) own that, and the seed is
-- the deterministic fairness seed above.
--
-- Guard: only run for a real team ctx. The excluded lab-intro scenario still
-- calls the old signature dw.generate_surface('neo-nauvis', true) at on_init;
-- the lab intro is disabled under MTS (the team starts on its adopted dimension
-- home), so that stale call must be a safe no-op rather than a crash.
-- Returns true when the team advanced to a valid new surface, false otherwise
-- (so the caller can skip the platform clone + retire on a failed create).
local function generate_surface(force_name, ctx, target)
    if type(force_name) ~= "string" then return false end
    if type(ctx) ~= "table" or not ctx.warp then return false end
    if not (game.forces[force_name] and game.forces[force_name].valid) then return false end

    force_map_settings()

    local planet = target
    if not planet or not game.planets[planet] then
        planet = "nauvis"
    end

    -- Compute the per-planet map_gen and pin the deterministic fairness seed.
    -- The next warp number is the one we are about to land on.
    --
    -- Space Age supplies per-planet map_gen via the planet prototype. Without it
    -- only nauvis exists, so fall back to the live nauvis surface's settings (the
    -- host-chosen base settings -- the same source map_seed() reads). Deep-copy so
    -- pinning our seed never mutates the shared prototype/surface settings table.
    local next_number = ctx.warp.number + 1
    local planet_proto = game.planets[planet] and game.planets[planet].prototype
    local base_mapgen = (planet_proto and planet_proto.map_gen_settings)
        or game.surfaces.nauvis.map_gen_settings
    local mapgen = table.deepcopy(base_mapgen)
    mapgen.seed = fairness_seed(planet, next_number)

    -- Record the previous surface (so it can be retired after the platform
    -- clone) and advance the warp counter / current placeholder.
    ctx.warp.previous = ctx.warp.current
    ctx.warp.number = next_number
    ctx.warp.current = {
        name          = nil,
        planet        = planet,
        surface       = nil,
        surface_index = nil,
    }

    -- Ask MTS to create this team's EPHEMERAL surface for the base planet. MTS
    -- performs creation (game.create_surface with OUR map_gen_settings, seed
    -- included), ownership registration, planet association, visibility and the
    -- on_team_surface_created event, then returns the created surface name.
    --
    -- The name MUST be NON-VARIANT (not mts-<planet>-N / team-N-<planet>), or
    -- MTS's normalize_variant_seed would clobber our deterministic seed. The
    -- 'mdw-<planet>-w<warp_number>' scheme is unique per (planet, warp) and never
    -- matches a variant pattern, so MTS honors our seed at creation -- NO
    -- post-create re-pin is needed (ADR-0005 fairness holds from birth).
    local surface_name = remote.call("mts-v1", "create_team_surface", force_name, {
        name             = 'mdw-' .. planet .. '-w' .. next_number,
        planet           = planet,
        map_gen_settings = mapgen,
    })

    local surface = surface_name and game.surfaces[surface_name]
    if not (surface and surface.valid) then
        -- Creation failed: roll the warp counter back so we don't strand the
        -- team with a half-advanced, surfaceless context.
        ctx.warp.current = ctx.warp.previous
        ctx.warp.previous = nil
        ctx.warp.number = next_number - 1
        return false
    end

    surface.localised_name = game.planets[planet].prototype.localised_name
    ctx.warp.current.name          = surface.name
    ctx.warp.current.surface       = surface
    ctx.warp.current.surface_index = surface.index

    -- Route this surface's engine events back to the owning team in O(1).
    dw.set_surface_owner(surface.index, force_name)

    dw.rampant.check_surface_processed(ctx.warp.current.surface)
    ctx.warp.current.surface.request_to_generate_chunks({x = 0, y = 0}, ctx.platform.warp.size / 32 + 1)
    ctx.warp.current.surface.force_generate_chunk_requests()
    return true
end
dw.generate_surface = generate_surface

------------------------------------------------------------
--- Previous-surface retirement (replaces game.delete_surface)
------------------------------------------------------------
-- After the platform has been cloned onto the new surface, retire the old one
-- through MTS (the single grounded deletion path -- ADR-0004). Forgets the
-- surface-index mapping too so the reverse map stays accurate.
--
-- DIVERGENCE: upstream's update_surfaces_properties() deleted the previous
-- surface itself (game.delete_surface) and re-associated nauvis to its planet.
-- Under MTS those concerns belong to retire_team_surface. The CORE path
-- (warp.lua prepare_warp_to_next_surface) calls this directly with (force_name,
-- ctx) right after the platform clone.
local function update_surfaces_properties(force_name, ctx)
    -- The excluded aux teleport_platform (scripts/platforms/surface.lua) also
    -- still calls dw.update_surfaces_properties() with NO args at the end of its
    -- clone. That stale call is a safe no-op (guard below) -- the EXPECTED
    -- stale-aux divergence for v1; CORE drives the real retire with real args.
    if type(ctx) ~= "table" or not ctx.warp then return end
    if ctx.warp.status ~= defines.warp.warping then return end

    local previous = ctx.warp.previous
    if previous and previous.surface and previous.surface.valid then
        dw.clear_surface_owner(previous.surface.index)
        remote.call("mts-v1", "retire_team_surface", force_name, previous.name)
    end
    ctx.warp.previous = nil
    ctx.warp.status = defines.warp.awaiting
end
dw.update_surfaces_properties = update_surfaces_properties
