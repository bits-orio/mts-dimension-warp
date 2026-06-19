-- PORTED to per-team ctx (P4/S7). The reset commands take no force argument; they
-- resolve the INVOKING player's team (spectator-aware) and reset only that team's
-- platforms / harvesters. Run from the server console (no player) they no-op.

local function reset_platforms(command)
    if not command.player_index then return end
    local player = game.players[command.player_index]
    if not (player and player.valid) then return end
    local force_name = dw.effective_force(player)
    if not (force_name and dw.has_warp_ctx(force_name)) then return end
    local ctx = dw.warp_ctx(force_name)
    if not ctx.platform.factory.surface then return end
    -- reset_platforms rebuilds the warp<->factory links, so the warp surface must
    -- be live too (it's deref'd below for the radio pole + stairs).
    if not (ctx.warp.current.surface and ctx.warp.current.surface.valid) then return end

    local force = game.forces[force_name]
    local platform_area = math2d.bounding_box.create_from_centre({0, 0}, ctx.platform.warp.size, ctx.platform.warp.size)
    local surface = ctx.warp.current.surface
    local entity_list = {
        "dw-hidden-radio-pole", "dw-hidden-gate-pole", "dw-chest", "dw-logistic-input", "dw-logistic-output", "dw-pipe",
        "dw-stair-loader", "dw-stair-fast-loader", "dw-stair-express-loader"
    }

    if prototypes.entity['dw-stair-turbo-loader'] then table.insert(entity_list, 'dw-stair-turbo-loader') end
    if prototypes.entity['dw-stair-advanced-loader'] then table.insert(entity_list, 'dw-stair-advanced-loader') end
    if prototypes.entity['dw-stair-superior-loader'] then table.insert(entity_list, 'dw-stair-superior-loader') end

    local entities = surface.find_entities_filtered{
        area = platform_area,
        name = entity_list
    }
    for _, entity in pairs(entities) do
        entity.destroy()
    end

    -- recreate surface chests and links with factory
    local factory_pole = ctx.platform.factory.surface.find_entity("dw-hidden-gate-pole", {0, -6})
    local pole = dw.platforms.create_special_entity(ctx.warp.current.surface, dw.entities.surface_radio_pole, false, force)
    if factory_pole and pole then utils.link_cables(factory_pole, pole, defines.wire_connectors.power) end
    dw.logistics.create_loader_chest_pair(force_name, ctx, ctx.warp.current.surface, ctx.platform.factory.surface, dw.stairs.surface_factory)
    dw.logistics.create_pipe_pairs(force_name, ctx, ctx.warp.current.surface, ctx.platform.factory.surface, dw.stairs.surface_factory)

    -- recreate the mobile gate if it exists
    if ctx.warpgate.gate then
        if ctx.warpgate.mobile_gate and ctx.warpgate.mobile_gate.valid then ctx.warpgate.mobile_gate.destroy{raise_destroy=true} end
        dw.gate.create_warpgate(force_name, ctx)
        dw.gate.create_mobile_gate(force_name, ctx)
    end
end

local function reset_harvester_side(force_name, ctx, side, entity_list)
    local surface = ctx.platform.mining.surface
    local harvester_area = math2d.bounding_box.create_from_centre(dw.harvesters[side].center, ctx.harvesters[side].size - 1)

    dw.platforms.recall_harvester(force_name, ctx, side)

    local entities = surface.find_entities_filtered{
        area = harvester_area,
        name = entity_list
    }
    for _,entity in pairs(entities) do
        entity.destroy()
    end

    dw.platforms.create_harvester_zone(force_name, ctx, side)
    dw.platforms.create_update_pipes_loaders(force_name, ctx, side)
end

local function reset_harvesters(command)
    if not command.player_index then return end
    local player = game.players[command.player_index]
    if not (player and player.valid) then return end
    local force_name = dw.effective_force(player)
    if not (force_name and dw.has_warp_ctx(force_name)) then return end
    local ctx = dw.warp_ctx(force_name)
    if not ctx.platform.mining.surface then return end

    local entity_list = {
        "dw-hidden-radio-pole", "dw-hidden-gate-pole", "dw-chest", "dw-logistic-input", "dw-logistic-output", "dw-pipe",
        "dw-stair-loader", "dw-stair-fast-loader", "dw-stair-express-loader",
        "harvest-linked-belt", "harvest-fast-linked-belt", "harvest-express-linked-belt"
    }

    if prototypes.entity['dw-stair-turbo-loader'] then
        table.insert(entity_list, 'dw-stair-turbo-loader')
        table.insert(entity_list, 'harvest-turbo-linked-belt')
    end
    if prototypes.entity['dw-stair-advanced-loader'] then
        table.insert(entity_list, 'dw-stair-advanced-loader')
        table.insert(entity_list, 'harvest-advanced-linked-belt')
    end
    if prototypes.entity['dw-stair-superior-loader'] then
        table.insert(entity_list, 'dw-stair-superior-loader')
        table.insert(entity_list, 'harvest-superior-linked-belt')
    end

    if ctx.harvesters.left.gate then reset_harvester_side(force_name, ctx, "left", entity_list) end
    if ctx.harvesters.right.gate then reset_harvester_side(force_name, ctx, "right", entity_list) end
end


commands.add_command("dw_reset_warp_platform", {"dw-commands.reset-platform"}, reset_platforms)
commands.add_command("dw_reset_harvesters", {"dw-commands.reset-harvesters"}, reset_harvesters)
