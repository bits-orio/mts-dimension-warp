dw.platforms = dw.platforms or {}

-- PORTED to per-team ctx (P4/S6). The harvesters are deployable mining grids that
-- a team builds on its WARP surface; they lay hidden ore + machinery on the team's
-- MINING dimension platform and link belts/pipes back to the base. Tenants of the
-- mining surface (depend on S2). All flat storage.harvesters / storage.platform.
-- mining / storage.warp.current state moves to ctx; entities belong to the team
-- force. Entity handlers resolve the team from the surface owner, research from
-- event.research.force. dw.harvesters[side] (geometry constants) stays flat.

local function lay_hidden_ore(ctx, area)
    for i = area.left_top.x, area.right_bottom.x, 1 do
        for j = area.left_top.y, area.right_bottom.y, 1 do
            local position = {i, j}
            ctx.platform.mining.surface.create_entity{
                name = "dw-hidden-ore",
                position = position,
                amount = 1,
            }
        end
    end
end

local function create_update_pipes_loaders(force_name, ctx, side)
    local force = game.forces[force_name]
    local harvester_const = dw.harvesters[side]
    local harvester = ctx.harvesters[side]
    local inner_surface = harvester.deployed and ctx.warp.current.surface or ctx.platform.mining.surface

    local inner_x = harvester_const.center[1] + ((side == "left") and (harvester.size / 2 - 0.5) or (-harvester.size / 2 + 0.5))
    local outer_x = inner_x + ((side == "left") and 2 or -2)

    -- loaders between harvester and mining platform
    for i = 1, ctx.harvesters.loaders, 1 do
        local inner_position = {x = inner_x, y = dw.harvesters.loader_y[i]}
        local outer_position = {x = outer_x, y = dw.harvesters.loader_y[i]}

        if harvester.deployed then
            inner_position = math2d.position.subtract(inner_position, harvester_const.center)
            inner_position = math2d.position.add(inner_position, harvester.mobile.position)
        end

        if harvester.loaders[i] and utils.is_valid(harvester.loaders[i][1]) and utils.is_valid(harvester.loaders[i][2]) then
            local inner_loader = harvester.loaders[i][1]
            local outer_loader = harvester.loaders[i][2]
            -- check for position
            if outer_loader.position.x ~= outer_position.x then
                local to_remove = outer_loader.surface.find_entities_filtered {position = outer_position, type = {"character"}, invert = true}
                for _, entity in pairs(to_remove) do entity.destroy() end

                local new_outer = outer_loader.clone{
                    position = outer_position,
                    surface = outer_loader.surface,
                    force = force
                }
                outer_loader.destroy()
                outer_loader = new_outer
            end
            if inner_loader.position.x ~= inner_position.x then
                local to_remove = inner_loader.surface.find_entities_filtered {position = inner_position, type = {"character"}, invert = true}
                for _, entity in pairs(to_remove) do entity.destroy() end

                local new_inner = inner_loader.clone{
                    position = inner_position,
                    surface = inner_loader.surface,
                    force = force
                }
                inner_loader.destroy()
                inner_loader = new_inner
            end

            -- check for tier
            if outer_loader.name ~= ctx.harvesters.loader_tier then
                local new_outer = ctx.platform.mining.surface.create_entity{
                    name = ctx.harvesters.loader_tier,
                    position = outer_position,
                    direction = outer_loader.direction,
                    force = force,
                    fast_replace = true,
                    spill = false,
                }
                outer_loader = new_outer
            end

            if inner_loader.name ~= ctx.harvesters.loader_tier then
                local new_inner = inner_surface.create_entity{
                    name = ctx.harvesters.loader_tier,
                    position = inner_position,
                    direction = inner_loader.direction,
                    force = force,
                    fast_replace = true,
                    spill = false,
                }
                inner_loader = new_inner
            end

            -- force all links, in case anything changed
            inner_loader.destructible = false
            outer_loader.destructible = false
            harvester.loaders[i][1] = inner_loader
            harvester.loaders[i][2] = outer_loader
            inner_loader.connect_linked_belts(outer_loader)

        else
            local to_remove = inner_surface.find_entities_filtered {position = inner_position, type = {"character"}, invert = true}
            for _, entity in pairs(to_remove) do entity.destroy() end
            local to_remove = ctx.platform.mining.surface.find_entities_filtered {position = outer_position, type = {"character"}, invert = true}
            for _, entity in pairs(to_remove) do entity.destroy() end


            local inner_loader = inner_surface.create_entity{
                name = ctx.harvesters.loader_tier,
                position = inner_position,
                direction = defines.loader_facing[(side == "left") and "right" or "left"].input,
                force = force
            }

            local outer_loader = ctx.platform.mining.surface.create_entity{
                name = ctx.harvesters.loader_tier,
                position = outer_position,
                direction = defines.loader_facing[(side == "left") and "left" or "right"].output,
                force = force
            }

            inner_loader.destructible = false
            outer_loader.destructible = false
            harvester.loaders[i] = {inner_loader, outer_loader}
            inner_loader.linked_belt_type = "input"
            outer_loader.linked_belt_type = "output"
            inner_loader.connect_linked_belts(outer_loader)
        end
    end

    -- pipes

    local inner_position = {x = inner_x, y = dw.harvesters.pipe_y}
    local outer_position = {x = outer_x, y = dw.harvesters.pipe_y}

    if harvester.deployed then
        inner_position = math2d.position.subtract(inner_position, harvester_const.center)
        inner_position = math2d.position.add(inner_position, harvester.mobile.position)
    end

    if harvester.pipe and utils.is_valid(harvester.pipe[1]) and utils.is_valid(harvester.pipe[2]) then
        local inner_pipe = harvester.pipe[1]
        local outer_pipe = harvester.pipe[2]
        if outer_pipe.position.x ~= outer_position.x then
            local to_remove = outer_pipe.surface.find_entities_filtered {position = outer_position, type = {"character"}, invert = true}
            for _, entity in pairs(to_remove) do entity.destroy() end

            local new_outer = outer_pipe.clone{
                position = outer_position,
                surface = outer_pipe.surface,
                force = force
            }
            outer_pipe.destroy()
            outer_pipe = new_outer
        end
        if inner_pipe.position.x ~= inner_position.x then
            local to_remove = inner_pipe.surface.find_entities_filtered {position = inner_position, type = {"character"}, invert = true}
            for _, entity in pairs(to_remove) do entity.destroy() end

            local new_inner = inner_pipe.clone{
                position = inner_position,
                surface = inner_pipe.surface,
                force = force
            }
            inner_pipe.destroy()
            inner_pipe = new_inner
        end

        inner_pipe.destructible = false
        outer_pipe.destructible = false
        inner_pipe.fluidbox.add_linked_connection(0, outer_pipe, 0)
        harvester.pipe = {inner_pipe, outer_pipe}

    else
        local to_remove = inner_surface.find_entities_filtered {position = inner_position, type = {"character"}, invert = true}
        for _, entity in pairs(to_remove) do entity.destroy() end
        local to_remove = ctx.platform.mining.surface.find_entities_filtered {position = outer_position, type = {"character"}, invert = true}
        for _, entity in pairs(to_remove) do entity.destroy() end

        local inner_pipe = inner_surface.create_entity {
            name = ctx.harvesters.pipes_type,
            position = inner_position,
            direction = ((side == "left") and defines.direction.west or defines.direction.east),
            force = force,
        }
        local outer_pipe = inner_surface.create_entity {
            name = ctx.harvesters.pipes_type,
            position = outer_position,
            direction = ((side == "left") and defines.direction.east or defines.direction.west),
            force = force,
        }
        inner_pipe.destructible = false
        outer_pipe.destructible = false
        inner_pipe.fluidbox.add_linked_connection(0, outer_pipe, 0)
        harvester.pipe = {inner_pipe, outer_pipe}
    end
end
dw.platforms.create_update_pipes_loaders = create_update_pipes_loaders

local function place_harvester_tiles(force_name, ctx, side)
    local harvester_const = dw.harvesters[side]
    local harvester = ctx.harvesters[side]

    local harvester_area = math2d.bounding_box.create_from_centre(harvester_const.center, harvester.size - 1)
    local warn_area = math2d.bounding_box.create_from_centre(harvester_const.center, harvester.size + 1)
    local side_area = math2d.bounding_box.create_from_centre(harvester_const.center, harvester.size + 1 + harvester.border * 2)
    local path_area = {
        {harvester_const.center[1] - harvester.border, harvester_const.center[2] - harvester.border},
        {side == "left" and (-ctx.platform.mining.size.x / 2) or (ctx.platform.mining.size.x / 2), harvester_const.center[2] + harvester.border - 1}
    }

    local tiles = {}
    utils.add_tiles(tiles, "mining-platform", path_area[1], path_area[2])
    utils.add_tiles(tiles, "mining-platform", side_area.left_top, side_area.right_bottom)
    utils.add_tiles(tiles, "dimension-harvester-hazard", warn_area.left_top, warn_area.right_bottom)
    utils.add_tiles(tiles, "harvester-platform", harvester_area.left_top, harvester_area.right_bottom)
    ctx.platform.mining.surface.set_tiles(tiles)
end
dw.platforms.place_harvester_tiles = place_harvester_tiles

local function create_harvester_zone(force_name, ctx, side)
    local force = game.forces[force_name]
    local harvester_const = dw.harvesters[side]
    local harvester = ctx.harvesters[side]
    local harvester_area = math2d.bounding_box.create_from_centre(harvester_const.center, harvester.size - 1)

    place_harvester_tiles(force_name, ctx, side)
    lay_hidden_ore(ctx, harvester_area)

    if utils.is_nil_or_invalid(harvester.gate) then
        local harvester_gate = ctx.platform.mining.surface.create_entity{
            name = harvester_const.name,
            position = harvester_const.center,
            force = force,
        }
        harvester_gate.destructible = false
        harvester.gate = harvester_gate
    end
    if utils.is_nil_or_invalid(harvester.pole) then
        local pole = ctx.platform.mining.surface.create_entity{
            name = harvester_const.pole,
            position = harvester_const.center,
            force = force,
        }
        pole.destructible = false
        harvester.pole = pole
    end

    -- as we update the size, if it's deployed we need to update the overlay and area
    if harvester.deployed then
        harvester.rectangle.destroy()
        local draw_area = math2d.bounding_box.create_from_centre(harvester.mobile.position, harvester.size)
        harvester.rectangle = rendering.draw_rectangle{
            color = util.color('#69351010'),
            left_top = draw_area.left_top,
            right_bottom = draw_area.right_bottom,
            surface = ctx.warp.current.surface,
            only_in_alt_mode = true,
            draw_on_ground = true,
            filled = true
        }
        harvester.area = math2d.bounding_box.create_from_centre(harvester.mobile.position, harvester.size - 1)
    end

    create_update_pipes_loaders(force_name, ctx, side)
end
dw.platforms.create_harvester_zone = create_harvester_zone

--- Link the pipe and loaders deployed in surface to the one in Smeltus
local function link_harvester_pipe_chest(force_name, ctx, side)
    local harvester_const = dw.harvesters[side]
    local harvester = ctx.harvesters[side]
    local surface = harvester.deployed and ctx.warp.current.surface or ctx.platform.mining.surface
    local inner_x = harvester_const.center[1] + ((side == "left") and (harvester.size / 2 - 0.5) or (-harvester.size / 2 + 0.5))

    -- loader link
    for i = 1, ctx.harvesters.loaders, 1 do
        local inner_position = {inner_x, dw.harvesters.loader_y[i]}
        if harvester.deployed then
            inner_position = math2d.position.subtract(inner_position, harvester_const.center)
            inner_position = math2d.position.add(inner_position, harvester.mobile.position)
        end

        if harvester.loaders[i] then
            local loader = surface.find_entity(ctx.harvesters.loader_tier, inner_position)
            if loader then
                loader.connect_linked_belts(harvester.loaders[i][2])
                harvester.loaders[i][1] = loader
                loader.destructible = false
            end
        end
    end

    -- pipe link
    local inner_position = {inner_x, dw.harvesters.pipe_y}
    if harvester.deployed then
        inner_position = math2d.position.subtract(inner_position, harvester_const.center)
        inner_position = math2d.position.add(inner_position, harvester.mobile.position)
    end

    if harvester.pipe then
        local pipe = surface.find_entity(ctx.harvesters.pipes_type, inner_position)
        if pipe then
            pipe.fluidbox.add_linked_connection(0, harvester.pipe[2], 0)
            harvester.pipe[1] = pipe
            pipe.destructible = false
        end
    end

end

local function recall_harvester(force_name, ctx, side)
    if not ctx.harvesters[side].deployed then return end
    local surface = ctx.warp.current.surface
    local deployed_area = ctx.harvesters[side].area
    local deployed_center = ctx.harvesters[side].mobile.position

    -- remove entities we don't want to teleport back
    ctx.harvesters[side].rectangle.destroy()
    ctx.harvesters[side].mobile_pole.destroy()

    -- find all entities we want to teleport back to harvester zone
    local harvester_entities = surface.find_entities_filtered {
        type = {"locomotive", "cargo-wagon", "fluid-wagon", "artillery-wagon",
                "spider-leg", "player", "character", "resource"},
        area = deployed_area,
        invert = true,
    }

    -- don't clone harvester gate and any vehicles with players inside
    for index = #harvester_entities, 1, -1 do
        local h_entity = harvester_entities[index]
        if h_entity.name == dw.harvesters[side].mobile_name then
            table.remove(harvester_entities, index)
        end
        if h_entity.type == "car" or h_entity.type == "spider-vehicle" then
            if h_entity.get_driver() or h_entity.get_passenger() then
                table.remove(harvester_entities, index)
            end
        end
    end

    local destination_offset = math2d.position.subtract(dw.harvesters[side].center, deployed_center)
    ctx.platform.mining.surface.clone_entities{
        entities = harvester_entities,
        destination_surface = ctx.platform.mining.surface,
        destination_offset = destination_offset
    }

    -- remove the entities
    for _, h_entity in pairs(harvester_entities) do
        h_entity.destroy{raise_destroy = true}
    end

    ctx.harvesters[side].mobile.destroy()
    ctx.harvesters[side].deployed = false
    link_harvester_pipe_chest(force_name, ctx, side)
end
dw.platforms.recall_harvester = recall_harvester

local function harvester_placed(event)
    local harvester_grid = event.entity
    if utils.is_nil_or_invalid(harvester_grid) then return end
    if not string.match(harvester_grid.name, "harvester%-%a+%-grid%-%d") then return end

    -- Resolve the owning team from the surface; the grid may only be placed on
    -- that team's WARP surface (role 'surface'). A nil ctx is rejected.
    local owner = dw.surface_owner(harvester_grid.surface.index)
    local ctx = owner and dw.warp_ctx(owner) or nil
    if not utils.entity_built_surface_check(event, ctx, "surface", "dw-messages.cannot-build-harvester") then return end
    local force_name = owner
    local force = game.forces[force_name]

    local position = event.entity.position
    local surface = ctx.warp.current.surface
    local side = string.match(harvester_grid.name, "harvester%-(%a+)%-grid%-%d")

    -- Deploying clones machinery from the MINING dimension platform; without it
    -- there's nothing to deploy. Return the item instead of nil-derefing it later
    -- (spill BEFORE destroying the grid so the item handle is still valid).
    if not (ctx.platform.mining.surface and ctx.platform.mining.surface.valid) then
        utils.spill_or_return_item(event)
        harvester_grid.destroy()
        return
    end

    -- check area before anything else
    local check_area = math2d.bounding_box.create_from_centre(position, ctx.harvesters[side].size)
    if utils.check_deployable_collision(ctx, check_area, defines.deployable_collision_source[side .. "_harvester"]) then
        utils.spill_or_return_item(event)
        utils.create_flying_text{
            position = harvester_grid.position,
            surface = harvester_grid.surface,
            text = {"dw-messages.harvester-deployable-collision"},
            color = util.color(defines.hexcolor.orangered.. 'd9')
        }
        harvester_grid.destroy()
        return
    end

    harvester_grid.destroy()

    if ctx.harvesters[side].deployed then return end

    -- if we are here, all lights are green to deploy a harvester
    local harvester = surface.create_entity{
        name = dw.harvesters[side].mobile_name,
        position = position,
        force = force,
    }
    harvester.destructible = false

    local draw_area = math2d.bounding_box.create_from_centre(position, ctx.harvesters[side].size)
    local render = rendering.draw_rectangle{
        color = util.color('#69351010'),
        left_top = draw_area.left_top,
        right_bottom = draw_area.right_bottom,
        surface = surface,
        only_in_alt_mode = true,
        draw_on_ground = true,
        filled = true
    }

    local deployed_area = math2d.bounding_box.create_from_centre(position, ctx.harvesters[side].size - 1)
    local harvester_area = math2d.bounding_box.create_from_centre(dw.harvesters[side].center, ctx.harvesters[side].size - 1)
    local harvester_entities = ctx.platform.mining.surface.find_entities_filtered {
        type = {"locomotive", "cargo-wagon", "fluid-wagon", "artillery-wagon", "spider-leg", "player", "character", "resource"},
        area = harvester_area,
        invert = true,
    }

    -- don't clone harvester gate and pole and any vehicles with players inside
    for index = #harvester_entities, 1, -1 do
        local h_entity = harvester_entities[index]
        if h_entity.name == dw.harvesters[side].pole or h_entity.name == dw.harvesters[side].name then
            table.remove(harvester_entities, index)
        end
        if h_entity.type == "car" or h_entity.type == "spider-vehicle" then
            if h_entity.get_driver() or h_entity.get_passenger() then
                table.remove(harvester_entities, index)
            end
        end
    end

    local destination_offset = math2d.position.subtract(position, dw.harvesters[side].center)
    ctx.platform.mining.surface.clone_entities{
        entities = harvester_entities,
        destination_surface = surface,
        destination_offset = destination_offset
    }

    for _, h_entity in pairs(harvester_entities) do
        h_entity.destroy{raise_destroy = true}
    end

    local pole = surface.create_entity{
        name = dw.harvesters[side].pole,
        position = position,
        force = force,
    }
    pole.destructible = false


    ctx.harvesters[side].rectangle = render
    ctx.harvesters[side].area = deployed_area
    ctx.harvesters[side].mobile = harvester
    ctx.harvesters[side].mobile_pole = pole
    ctx.harvesters[side].mobile_pole.destructible = false
    ctx.harvesters[side].deployed = true
    utils.link_cables(ctx.harvesters[side].mobile_pole, ctx.harvesters[side].pole, defines.wire_connectors.power)
    utils.link_cables(ctx.harvesters[side].mobile, ctx.harvesters[side].gate, defines.wire_connectors.logic)
    utils.link_gates(ctx, "harvester-" .. side .. "-to-surface", "surface-to-harvester-" .. side, ctx.harvesters[side].gate, ctx.harvesters[side].mobile)
    link_harvester_pipe_chest(force_name, ctx, side)
end

local function replace_mined_item(ctx, side, event)
    if event.name == defines.events.script_raised_destroy then return end
    local mobile_gate = 'harvester-' .. side .. '-mobile-gate'
    local buffer = event.buffer
    for i = 1, #buffer, 1 do
        if buffer[i] and buffer[i].valid_for_read then
            if buffer[i].name == mobile_gate then
                local new_gate = {name = ctx.harvesters[side].mobile_name,count = buffer[i].count}
                buffer[i].clear()
                buffer.insert(new_gate)
            end
        end
    end

    if settings.global['dw-harvester-only-one'].value and event.player_index then
        local quantity = 0
        local player = game.players[event.player_index]
        local inventory = player.get_main_inventory()
        for i = 1, #inventory, 1 do
            if inventory[i] and inventory[i].valid_for_read then
                if inventory[i].name == mobile_gate or inventory[i].name == ctx.harvesters[side].mobile_name then
                    quantity = quantity + 1
                    if quantity > 0 then
                        inventory[i].clear()
                    end
                end
            end
        end
    end
end

local function harvester_mined(event)
    local entity = event.entity
    if utils.is_nil_or_invalid(entity) then return end
    local name = entity.name

    -- only proceed for harvester gate/mobile-gate entities, then resolve the team
    if not (string.match(name, "harvester%-%a+%-mobile%-gate") or string.match(name, "harvester%-%a+%-gate")) then return end
    local owner = dw.surface_owner(entity.surface.index)
    if not owner then return end
    local force_name = owner
    local ctx = dw.warp_ctx(owner)

    if string.match(name, "harvester%-%a+%-mobile%-gate") then
        local side = string.match(name, "harvester%-(%a+)%-mobile%-gate")
        recall_harvester(force_name, ctx, side)
        replace_mined_item(ctx, side, event)
    end

    if string.match(name, "harvester%-%a+%-gate") then
        local side = string.match(name, "harvester%-(%a+)%-gate")
        local new_gate = entity.surface.find_entity(name, entity.position)
        new_gate.destructible = false
        ctx.harvesters[side].gate = new_gate
        recall_harvester(force_name, ctx, side)
        replace_mined_item(ctx, side, event)
    end

end

local function replace_harvester_inventory(force_name, ctx, side)
    local force = game.forces[force_name]
    for _, player in pairs(force.players) do
        local inventory = player.get_main_inventory()
        if inventory and not inventory.is_empty() then
            for i = 1, #inventory, 1 do
                if inventory[i].valid_for_read then
                    if string.match(inventory[i].name, "harvester%-" .. side .. "%-grid%-%d") then
                        local new_harvester = {name = ctx.harvesters[side].mobile_name, count = inventory[i].count}
                        inventory[i].clear()
                        inventory.insert(new_harvester)
                    end
                end
            end
        end
    end
end

local function on_technology_research_finished(event)
    local force = event.research.force
    if not force.name:find("^team%-") then return end
    if not dw.has_warp_ctx(force.name) then return end
    local force_name = force.name
    local ctx = dw.warp_ctx(force_name)
    local tech = event.research

    if string.match(tech.name, "dimension%-harvester%-%a+%-%d+") then
        local side = string.match(tech.name, "dimension%-harvester%-(%a+)%-%d+")
        if side then
            -- The harvester lays its zone on the team's MINING dimension platform.
            -- Bail (log) if that surface isn't live -- the tech being researched
            -- proves nothing about the surface handle (out-of-order grant, MTS
            -- create failure). Without this, create_harvester_zone nil-derefs.
            if not (ctx.platform.mining.surface and ctx.platform.mining.surface.valid) then
                dw.diag("on_research[harvester] force=%s side=%s: no mining surface -- skip", force_name, side)
                return
            end
            recall_harvester(force_name, ctx, side)
            ctx.harvesters[side].size = dw.platform_size.harvester[tech.level]
            ctx.harvesters[side].border = tech.level + 2
            ctx.harvesters[side].mobile_name = "harvester-" .. side .. "-grid-" .. tech.level
            create_harvester_zone(force_name, ctx, side)
            replace_harvester_inventory(force_name, ctx, side)
        end
    end
    if string.match(tech.name, "dw%-number%-stairs%-.*") then
        ctx.harvesters.loaders = ctx.harvesters.loaders + 1
        if ctx.harvesters.left.gate then create_update_pipes_loaders(force_name, ctx, "left") end
        if ctx.harvesters.right.gate then create_update_pipes_loaders(force_name, ctx, "right") end

    end
    if string.match(tech.name, "dw%-.*%-loader%-stairs") then
        local tier = string.match(tech.name, "dw%-(.*)%-loader%-stairs")
        if tier then
            ctx.harvesters.loader_tier = "harvest-" .. tier .. "-linked-belt"
            if ctx.harvesters.left.gate then create_update_pipes_loaders(force_name, ctx, "left") end
            if ctx.harvesters.right.gate then create_update_pipes_loaders(force_name, ctx, "right") end
        end
    end
end

local function invert_belt_from_belt(ctx, belt)
    for _, linked_pair in pairs(ctx.harvesters['left'].loaders) do
        if linked_pair[1] == belt or linked_pair[2] == belt then
            local belt_type = linked_pair[1].linked_belt_type
            linked_pair[1].connect_linked_belts(nil)
            linked_pair[1].linked_belt_type = linked_pair[2].linked_belt_type
            linked_pair[2].linked_belt_type = belt_type
            linked_pair[1].connect_linked_belts(linked_pair[2])
            return
        end
    end

    for _, linked_pair in pairs(ctx.harvesters['right'].loaders) do
        if linked_pair[1] == belt or linked_pair[2] == belt then
            local belt_type = linked_pair[1].linked_belt_type
            linked_pair[1].connect_linked_belts(nil)
            linked_pair[1].linked_belt_type = linked_pair[2].linked_belt_type
            linked_pair[2].linked_belt_type = belt_type
            linked_pair[1].connect_linked_belts(linked_pair[2])
            return
        end
    end
end

local function rotate_linked_belt(event)
    local entity = event.entity
    if utils.is_nil_or_invalid(entity) then return end

    if string.match(entity.name, "harvest.*linked%-belt") then
        local owner = dw.surface_owner(entity.surface.index)
        if not owner then return end
        local ctx = dw.warp_ctx(owner)
        entity.direction = event.previous_direction
        invert_belt_from_belt(ctx, entity)
    end
end

local function flipped_linked_belt(event)
    local entity = event.entity
    if utils.is_nil_or_invalid(entity) then return end

    if string.match(entity.name, "harvest.*linked%-belt") then
        local owner = dw.surface_owner(entity.surface.index)
        if not owner then return end
        local ctx = dw.warp_ctx(owner)
        if event.horizontal then
            entity.direction = util.oppositedirection(entity.direction)
        end
        invert_belt_from_belt(ctx, entity)
    end
end

dw.register_event(defines.events.on_research_finished, on_technology_research_finished)

dw.register_event(defines.events.on_built_entity, harvester_placed)
dw.register_event(defines.events.on_robot_built_entity, harvester_placed)
dw.register_event(defines.events.script_raised_revive, harvester_placed) -- need to catch this events, if a mod create the ghost

dw.register_event(defines.events.on_player_mined_entity, harvester_mined)
dw.register_event(defines.events.on_robot_mined_entity, harvester_mined)
dw.register_event(defines.events.script_raised_destroy, harvester_mined) -- need to catch this events, if a mod delete the item

dw.register_event(defines.events.on_player_flipped_entity, flipped_linked_belt)
dw.register_event(defines.events.on_player_rotated_entity, rotate_linked_belt)
