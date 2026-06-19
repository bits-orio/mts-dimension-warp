--- All about managing the different zones (factory / mining / power)
--- except the surface (warp) platform itself.
---
--- PORTED to per-team ctx (P4/S2-S3): each dimension surface is a PERMANENT
--- per-team surface, born via mts-v1 create_team_surface, owned by the team, and
--- retired explicitly on team release (mts_lifecycle). Upstream kept a single flat
--- storage.platform slot, so only the first team to research ever owned a platform
--- and every later team corrupted it.
------------------------------------------------------------
dw.platforms = dw.platforms or {}

-- Create a permanent per-team dimension surface on a custom planet. Replaces
-- upstream's game.planets[planet]:create_surface() (which bypasses MTS surface
-- ownership / ADR-0004) with the mts-v1 create_team_surface seam, mirroring the
-- warp-surface birth in surface-generation.lua. The name 'mdw-<force>-<role>' is
-- non-variant, so MTS leaves the seed alone and never clone-mirrors it. The seed
-- is tied to the team's current warp surface for MP-deterministic generation.
-- Returns the surface, or nil on failure (caller must not advance).
local function init_surface(force_name, ctx, role, planet_name)
    local mapgen = table.deepcopy(game.planets[planet_name].prototype.map_gen_settings)
    if ctx.warp.current.surface and ctx.warp.current.surface.valid then
        mapgen.seed = ctx.warp.current.surface.map_gen_settings.seed
    end
    local surface_name = remote.call("mts-v1", "create_team_surface", force_name, {
        name             = 'mdw-' .. force_name .. '-' .. role,
        planet           = planet_name,
        map_gen_settings = mapgen,
    })
    local surface = surface_name and game.surfaces[surface_name]
    if not (surface and surface.valid) then
        dw.diag("init_surface force=%s role=%s CREATE FAILED (planet=%s)", force_name, role, planet_name)
        return nil
    end
    -- Route this surface's engine + teleport events back to the owning team.
    dw.set_surface_owner(surface.index, force_name)

    surface.solar_power_multiplier = 0
    if ctx.platform.electrified_ground then
        surface.daytime = 0
        surface.always_day = true
        surface.create_global_electric_network()
    else
        surface.daytime = 0.5
    end
    surface.freeze_daytime = true
    surface.request_to_generate_chunks({0, 0}, 2)
    surface.force_generate_chunk_requests()
    dw.diag("init_surface force=%s role=%s created %s (index=%d)", force_name, role, surface.name, surface.index)
    return surface
end

-- Create one fixed gate/pole/chest entity on a dimension or warp surface. force
-- defaults to the default player force for legacy (admin) callers; the dimension
-- code passes the TEAM force so the entity belongs to the team (visible, frozen
-- on pause, owned).
local function create_special_entity(surface, entity_info, clear_area, force)
    force = force or game.forces.player
    local name = entity_info.name
    local position = entity_info.position
    if clear_area then
        local area_to_clear = {
            {entity_info.area[1][1] + position[1], entity_info.area[1][2] + position[2]},
            {entity_info.area[2][1] + position[1], entity_info.area[2][2] + position[2]}
        }
        local to_remove = surface.find_entities_filtered {area = area_to_clear, type = {"character", "rocket-silo-rocket", "cargo-pod"}, invert = true}
        for _, entity in pairs(to_remove) do
            entity.destroy()
        end
    end

    local entity = surface.create_entity{
        name = name,
        position = position,
        force = force,
        direction = entity_info.direction or defines.direction.north
    }
    entity.destructible = false
    return entity
end
dw.platforms.create_special_entity = create_special_entity

local function create_warp_factory_teleporters_logistic(force_name, ctx)
    local force = game.forces[force_name]
    -- Both surfaces must exist to link them. Bail (log) rather than hard-crash the
    -- server if the warp surface is somehow missing (e.g. a corrupted/edge ctx).
    if not (ctx.warp.current.surface and ctx.warp.current.surface.valid
            and ctx.platform.factory.surface and ctx.platform.factory.surface.valid) then
        dw.diag("create_warp_factory_teleporters_logistic force=%s: missing warp/factory surface -- skip", force_name)
        return
    end
    local gate_1 = create_special_entity(ctx.platform.factory.surface, dw.entities.gate_factory_surface, true, force)
    local gate_2 = create_special_entity(ctx.warp.current.surface, dw.entities.surface_radio_station, true, force)
    gate_2.active = false
    utils.link_gates(ctx, "factory-to-warp", "warp-to-factory", gate_1, gate_2)
    utils.link_cables(gate_1, gate_2, defines.wire_connectors.logic)

    local pole_1 = create_special_entity(ctx.warp.current.surface, dw.entities.surface_radio_pole, false, force)
    local pole_2 = create_special_entity(ctx.platform.factory.surface, dw.entities.pole_factory_surface, false, force)
    utils.link_cables(pole_1, pole_2, defines.wire_connectors.power)

    dw.logistics.create_loader_chest_pair(force_name, ctx, ctx.warp.current.surface, ctx.platform.factory.surface, dw.stairs.surface_factory)
    dw.logistics.create_pipe_pairs(force_name, ctx, ctx.warp.current.surface, ctx.platform.factory.surface, dw.stairs.surface_factory)
end

local function create_factory_mining_teleporters_logistic(force_name, ctx)
    local force = game.forces[force_name]
    if not (ctx.platform.mining.surface and ctx.platform.mining.surface.valid
            and ctx.platform.factory.surface and ctx.platform.factory.surface.valid) then
        dw.diag("create_factory_mining_teleporters_logistic force=%s: missing mining/factory surface -- skip", force_name)
        return
    end
    local gate_1 = create_special_entity(ctx.platform.mining.surface, dw.entities.gate_mining_factory, true, force)
    local gate_2 = create_special_entity(ctx.platform.factory.surface, dw.entities.gate_factory_mining, true, force)
    utils.link_gates(ctx, "mining-to-factory", "factory-to-mining", gate_1, gate_2)
    utils.link_cables(gate_1, gate_2, defines.wire_connectors.logic)

    local pole_1 = create_special_entity(ctx.platform.factory.surface, dw.entities.pole_factory_mining, false, force)
    local pole_2 = create_special_entity(ctx.platform.mining.surface, dw.entities.pole_mining_factory, false, force)
    utils.link_cables(pole_1, pole_2, defines.wire_connectors.power)

    dw.logistics.create_loader_chest_pair(force_name, ctx, ctx.platform.factory.surface, ctx.platform.mining.surface, dw.stairs.factory_mining)
    dw.logistics.create_pipe_pairs(force_name, ctx, ctx.platform.factory.surface, ctx.platform.mining.surface, dw.stairs.factory_mining)
end

local function create_mining_power_teleporters_logistic(force_name, ctx)
    local force = game.forces[force_name]
    if not (ctx.platform.power.surface and ctx.platform.power.surface.valid
            and ctx.platform.mining.surface and ctx.platform.mining.surface.valid) then
        dw.diag("create_mining_power_teleporters_logistic force=%s: missing power/mining surface -- skip", force_name)
        return
    end
    local gate_1 = create_special_entity(ctx.platform.power.surface, dw.entities.gate_power_mining, true, force)
    local gate_2 = create_special_entity(ctx.platform.mining.surface, dw.entities.gate_mining_power, true, force)
    utils.link_gates(ctx, "power-to-mining", "mining-to-power", gate_1, gate_2)
    utils.link_cables(gate_1, gate_2, defines.wire_connectors.logic)

    local pole_1 = create_special_entity(ctx.platform.mining.surface, dw.entities.pole_mining_power, false, force)
    local pole_2 = create_special_entity(ctx.platform.power.surface, dw.entities.pole_power_mining, false, force)
    utils.link_cables(pole_1, pole_2, defines.wire_connectors.power)

    dw.logistics.create_loader_chest_pair(force_name, ctx, ctx.platform.mining.surface, ctx.platform.power.surface, dw.stairs.mining_power)
    dw.logistics.create_pipe_pairs(force_name, ctx, ctx.platform.mining.surface, ctx.platform.power.surface, dw.stairs.mining_power)
end


local function init_update_power_platform(force_name, ctx)
    if not ctx.platform.power.surface then
        ctx.platform.power.surface = init_surface(force_name, ctx, 'power', 'electria')
        if ctx.platform.power.surface then
            create_mining_power_teleporters_logistic(force_name, ctx)
        end
    end
    if not (ctx.platform.power.surface and ctx.platform.power.surface.valid) then return end

    local tiles = {}
    local size = ctx.platform.power.size

    if ctx.platform.power.water then
        local horizontal_water = math2d.bounding_box.create_from_centre({0,0}, size*2 + 1, size * 2 / 3 + 1)
        utils.add_tiles(tiles, "water", horizontal_water.left_top, horizontal_water.right_bottom)
        local vertical_water = math2d.bounding_box.create_from_centre({0,0}, size * 2 / 3 + 1,  size*2 + 1)
        utils.add_tiles(tiles, "water", vertical_water.left_top, vertical_water.right_bottom)
    end

    local horizontal = math2d.bounding_box.create_from_centre({0,0}, size*2 - 1, size * 2 / 3 - 1)
    local vertical = math2d.bounding_box.create_from_centre({0,0}, size * 2 / 3 - 1,  size*2 - 1)
    utils.add_tiles(tiles, "energy-platform", horizontal.left_top, horizontal.right_bottom)
    utils.add_tiles(tiles, "energy-platform", vertical.left_top, vertical.right_bottom)

    ctx.platform.power.surface.set_tiles(tiles, true, false, false)
    utils.put_warning_tiles(ctx.platform.power.surface, dw.hazard_tiles.power)
end
dw.platforms.init_update_power_platform = init_update_power_platform

local function init_update_mining_platform(force_name, ctx)
    if not ctx.platform.mining.surface then
        ctx.platform.mining.surface = init_surface(force_name, ctx, 'mining', 'smeltus')
        if ctx.platform.mining.surface then
            create_factory_mining_teleporters_logistic(force_name, ctx)
        end
    end
    if not (ctx.platform.mining.surface and ctx.platform.mining.surface.valid) then return end

    local tiles = {}
    local size_x = ctx.platform.mining.size.x
    local size_y = ctx.platform.mining.size.y
    utils.add_tiles(tiles, "mining-platform", {-size_x/2, -size_y/2}, {(size_x-1)/2, (size_y-1)/2})
    ctx.platform.mining.surface.set_tiles(tiles)
    utils.put_warning_tiles(ctx.platform.mining.surface, dw.hazard_tiles.mining)
end
dw.platforms.init_update_mining_platform = init_update_mining_platform

local function init_update_factory_platform(force_name, ctx)
    if not ctx.platform.factory.surface then
        ctx.platform.factory.surface = init_surface(force_name, ctx, 'factory', 'produstia')
        if ctx.platform.factory.surface then
            create_warp_factory_teleporters_logistic(force_name, ctx)
        end
    end
    if not (ctx.platform.factory.surface and ctx.platform.factory.surface.valid) then return end

    local tiles = {}
    local size = ctx.platform.factory.size
    utils.add_tiles(tiles, "factory-platform", {-size/2, -size/2}, {(size-1)/2, (size-1)/2})
    ctx.platform.factory.surface.set_tiles(tiles)
    utils.put_warning_tiles(ctx.platform.factory.surface, dw.hazard_tiles.factory)
end
dw.platforms.init_update_factory_platform = init_update_factory_platform


local function on_technology_research_finished(event)
    local force = event.research.force
    -- Only team forces own dimension platforms. A non-team force (the default
    -- player force, a spectator) or a team without a ctx no-ops safely.
    if not force.name:find("^team%-") then return end
    if not dw.has_warp_ctx(force.name) then return end
    local force_name = force.name
    local ctx = dw.warp_ctx(force_name)
    local tech = event.research

    if string.match(tech.name, "electrified%-ground") then
        ctx.platform.electrified_ground = true
        for _, role in ipairs({"factory", "mining", "power"}) do
            local s = ctx.platform[role].surface
            if s and s.valid then
                s.daytime = 0
                s.always_day = true
                s.create_global_electric_network()
            end
        end
        force.print({"dw-messages.electrified-ground"})
    end

    if string.match(tech.name, "dw%-factory%-beacon%-%d") then
        if ctx.platform.factory.surface and ctx.platform.factory.surface.valid then
            local entity = ctx.platform.factory.surface.create_entity{
                name = "dw-factory-beacon-" .. tech.level,
                position = {0,0},
                force = force_name,
                fast_replace = true
            }
            entity.destructible = false
        end
    end

    if tech.name == "factory-platform" then
        ctx.platform.factory.size = dw.platform_size.factory[1]
        force.print({"dw-messages.factory-unlocked"})
        init_update_factory_platform(force_name, ctx)
    end
    if tech.name == "mining-platform" then
        ctx.platform.mining.size = dw.platform_size.mining[1]
        force.print({"dw-messages.mining-unlocked"})
        init_update_mining_platform(force_name, ctx)
    end
    if tech.name == "power-platform" then
        ctx.platform.power.size = dw.platform_size.power[1]
        force.print({"dw-messages.power-unlocked"})
        init_update_power_platform(force_name, ctx)
    end

    if string.match(tech.name, "factory%-platform%-upgrade%-%d+") then
        ctx.platform.factory.size = dw.platform_size.factory[tech.level + 1]
        init_update_factory_platform(force_name, ctx)
    end
    if string.match(tech.name, "mining%-platform%-upgrade%-%d+") then
        ctx.platform.mining.size = dw.platform_size.mining[tech.level + 1]
        init_update_mining_platform(force_name, ctx)
    end
    if string.match(tech.name, "power%-platform%-upgrade%-%d+") then
        ctx.platform.power.size = dw.platform_size.power[tech.level + 1]
        init_update_power_platform(force_name, ctx)
    end

    if tech.name == "power-platform-water" then
        ctx.platform.power.water = true
        init_update_power_platform(force_name, ctx)
    end
end


dw.register_event(defines.events.on_research_finished, on_technology_research_finished)
