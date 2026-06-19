dw.gate = dw.gate or {}
-- PORTED to per-team ctx (P4/S5). The warp gate is a player-carried mobile gate
-- that bridges the team's warp surface to its factory platform, plus a static
-- cluster + inventory-persistence across warps. All flat storage.warpgate /
-- storage.stairs / storage.warp.current state moves to ctx; entities belong to the
-- team force. Event handlers resolve the team from the surface owner (built/mined/
-- died) or event.research.force (research).

--- create entities using the position list, centered around "center"
local function create_entities_relative_to_position(force_name, ctx, surface, entity_info, entity_list)
    local force = game.forces[force_name]
    local name = entity_info.name
    local center = entity_info.center
    local positions = entity_info.positions
    local direction = entity_info.direction
    local loader = entity_info.loader
    local mobile = entity_info.mobile
    local mobile_type = entity_info.mobile_type

    entity_list = entity_list or {}
    local entity_center = center.x and {center.x, center.y} or center
    local max_index = math.min(ctx.warpgate.chest_number, #positions)
    for i = 1, max_index, 1 do
        local final_position = {entity_center[1] + positions[i][1], entity_center[2] + positions[i][2]}

        local to_remove = surface.find_entities_filtered {position = final_position, type = {"character"}, invert = true}
        if to_remove[1] then
            if to_remove[1].name ~= name then
                to_remove[1].destroy()
            else
                entity_list[i] = to_remove[1]
                goto continue
            end
        end

        -- if we deploy the mobile gate, check the equivalent in platform first and decide what to put
        if mobile then
            local static_loader_position = math2d.position.add(dw.warp_gate.loaders[i], ctx.warpgate.gate.position)
            local index = "gate_" .. static_loader_position.x .. '_' .. static_loader_position.y
            local pair = ctx.stairs.chest_loader_pairs.gate[index]

            if mobile_type == "chest" then
                if ctx.stairs.chest_type.input ~= "dw-chest" then
                    name = (pair.type == "input") and ctx.stairs.chest_type.output or ctx.stairs.chest_type.input
                else
                    name = ctx.stairs.chest_type.input
                end
            end
            if mobile_type == "loader" then
                loader = defines.opposite_loader[pair.type]
                direction = defines.loader_facing.bottom[loader]
            end
        end

        local entity = surface.create_entity {
            name = name,
            position = final_position,
            force = force,
            direction = direction and direction or (i % 2 == 0) and defines.direction.east or defines.direction.west,
            type = loader,
            fast_replace = true,
        }
        entity.destructible = false

        -- transfer chest inventory if we saved one
        if mobile and mobile_type == "chest" then
            local index = positions[i][1] .. positions[i][2]
            if ctx.warpgate.mobile_chests[index] then
                local inventory = entity.get_inventory(defines.inventory.chest)
                for stackindex = 1, #ctx.warpgate.mobile_chests[index], 1 do
                    inventory.insert(ctx.warpgate.mobile_chests[index][stackindex])
                end
                ctx.warpgate.mobile_chests[index] = nil
            end
        end

        -- re-set loader filter if it existed
        if mobile and mobile_type == "loader" then
            local index = positions[i][1] .. positions[i][2]
            if ctx.warpgate.mobile_loaders[index] then
                entity.loader_filter_mode = ctx.warpgate.mobile_loaders[index].mode
                for filter_i = 1, #ctx.warpgate.mobile_loaders[index].filters, 1 do
                    entity.set_filter(filter_i, ctx.warpgate.mobile_loaders[index].filters[filter_i])
                end
                ctx.warpgate.mobile_loaders[index] = nil
            end
        end

        entity_list[i] = entity

        ::continue::
    end
    return entity_list
end

local function link_warp_gate(force_name, ctx, mobile_chests, mobile_loaders, mobile_pipes, force_warpgate_link)
    local max_index = math.min(ctx.warpgate.chest_number, #dw.warp_gate.chests)
    -- only use chest as max index, as we have same amount of each
    for i = 1, max_index, 1 do
        -- chests
        local platform_chest_position = math2d.position.add(dw.warp_gate.chests[i], ctx.warpgate.gate.position)
        local chest_index = "gate_" .. platform_chest_position.x .. '_' .. platform_chest_position.y
        ctx.stairs.chest_pairs[chest_index] = ctx.stairs.chest_pairs[chest_index] or {}
        if force_warpgate_link then
            local type = ctx.stairs.chest_pairs[chest_index] and ctx.stairs.chest_pairs[chest_index].type or defines.item_direction.pull
            local chest_type = type == defines.item_direction.pull and ctx.stairs.chest_type.output or ctx.stairs.chest_type.input
            local chest = ctx.warp.current.surface.find_entity(chest_type, platform_chest_position)
            ctx.stairs.chest_pairs[chest_index].A = chest
            ctx.stairs.chest_pairs[chest_index].type = type
        end
        ctx.stairs.chest_pairs[chest_index].B = mobile_chests and mobile_chests[i]

        -- loader/chest
        local platform_loader_position = math2d.position.add(dw.warp_gate.loaders[i], ctx.warpgate.gate.position)
        local loader_index_A = "gate_" .. platform_loader_position.x .. '_' .. platform_loader_position.y
        ctx.stairs.chest_loader_pairs["gate"][loader_index_A] = ctx.stairs.chest_loader_pairs["gate"][loader_index_A] or {}
        if force_warpgate_link then
            local loader_type = ctx.stairs.chest_loader_pairs["gate"][loader_index_A].type or "output"
            local loader = ctx.warp.current.surface.find_entity(ctx.stairs.loader_tier, platform_loader_position)
            ctx.stairs.chest_loader_pairs["gate"][loader_index_A] = {
                loader = loader,
                chest = ctx.stairs.chest_pairs[chest_index].A,
                type = loader_type,
                ref = {"gate", i}
            }
        end

        if mobile_loaders and mobile_loaders[i] then
            local loader_index_B = "gate_" .. mobile_loaders[i].position.x .. '_' .. mobile_loaders[i].position.y
            ctx.stairs.chest_loader_pairs["gate"][loader_index_A].ref = {"gate", loader_index_B}
            ctx.stairs.chest_loader_pairs["gate"][loader_index_B] = {
                loader = mobile_loaders[i],
                chest = mobile_chests[i],
                type = mobile_loaders[i].loader_type,
                ref = {"gate", loader_index_A}
            }
        end

        -- pipes
        local platform_pipe_position = math2d.position.add(dw.warp_gate.pipes[i], ctx.warpgate.gate.position)
        local pipe_index = 'gate_' .. platform_pipe_position.x .. '_' .. platform_pipe_position.y
        ctx.stairs.pipe_pairs[pipe_index] = ctx.stairs.pipe_pairs[pipe_index] or {}
        if force_warpgate_link then
            local pipe = ctx.warp.current.surface.find_entity(ctx.stairs.pipes_type, platform_pipe_position)
            ctx.stairs.pipe_pairs[pipe_index].A = pipe
            ctx.stairs.pipe_pairs[pipe_index].B = nil
        end

        ctx.stairs.pipe_pairs[pipe_index].B = mobile_pipes and mobile_pipes[i]
        if ctx.stairs.pipe_pairs[pipe_index].B and ctx.stairs.pipe_pairs[pipe_index].A then
            ctx.stairs.pipe_pairs[pipe_index].A.fluidbox.add_linked_connection(0, ctx.stairs.pipe_pairs[pipe_index].B, 0)
        end
    end
end
dw.gate.link_warp_gate = link_warp_gate

local function create_warpgate(force_name, ctx)
    local force = game.forces[force_name]
    local surface = ctx.warp.current.surface

    local area = {
        {dw.warp_gate.area[1][1] + dw.warp_gate.position[1], dw.warp_gate.area[1][2] + dw.warp_gate.position[2]},
        {dw.warp_gate.area[2][1] + dw.warp_gate.position[1], dw.warp_gate.area[2][2] + dw.warp_gate.position[2]}
    }
    local to_remove = surface.find_entities_filtered {area = area, name = {"character", "warp-gate", "dw-hidden-gate-pole"}, invert = true}
    for _, entity in pairs(to_remove) do entity.destroy() end

    if not ctx.warpgate.gate or (ctx.warpgate.gate and not ctx.warpgate.gate.valid) then
        local gate = surface.create_entity {
            name = dw.warp_gate.name,
            position = dw.warp_gate.position,
            force = force,
            direction = defines.direction.north,
        }
        gate.destructible = false
        ctx.warpgate.gate = gate
    end

    create_entities_relative_to_position(force_name, ctx,
        surface,
        {
            name = ctx.stairs.chest_type.output,
            center = dw.warp_gate.position,
            positions = dw.warp_gate.chests,
            direction = defines.direction.north,
            loader = nil,
        }
    )

    create_entities_relative_to_position(force_name, ctx,
        surface,
        {
            name = ctx.stairs.loader_tier,
            center = dw.warp_gate.position,
            positions = dw.warp_gate.loaders,
            direction = defines.loader_facing.bottom.output,
            loader = "output",
        }
    )
    create_entities_relative_to_position(force_name, ctx,
        surface,
        {
            name = ctx.stairs.pipes_type,
            center = dw.warp_gate.position,
            positions = dw.warp_gate.pipes,
            direction = nil,
            loader = nil,
        }
    )
    link_warp_gate(force_name, ctx, nil, nil, nil, true)

    if not ctx.warpgate.gatepole or (ctx.warpgate.gatepole and not ctx.warpgate.gatepole.valid) then
        local power_pole = surface.create_entity {
            name = "dw-hidden-gate-pole",
            position = dw.warp_gate.position,
            force = force,
            direction = defines.direction.north,
        }
        power_pole.destructible = false
        ctx.warpgate.gatepole = power_pole
    end

    local radio_tower_pole = surface.find_entity(dw.entities.surface_radio_pole.name, dw.entities.surface_radio_pole.position)
    if radio_tower_pole and ctx.warpgate.gatepole then
        utils.link_cables(ctx.warpgate.gatepole, radio_tower_pole, defines.wire_connectors.power)
    end
end
dw.gate.create_warpgate = create_warpgate

--- create the mobile gate for the user to pick it after each warp / from shortcuts
local function create_mobile_gate(force_name, ctx)
    local force = game.forces[force_name]
    -- remove previous gates
    local existing_mobile_gate = ctx.warp.current.surface.find_entities_filtered{
        area = math2d.bounding_box.create_from_centre({0, 0}, ctx.platform.warp.size),
        name = ctx.warpgate.mobile_type
    }
    for _, gate in pairs(existing_mobile_gate) do
        gate.destroy()
    end

    local position = ctx.warp.current.surface.find_non_colliding_position(
        ctx.warpgate.mobile_type,
        dw.warp_gate.position, 20, 1, true)
    if position then
        local mobile_gate = ctx.warp.current.surface.create_entity{
            name = ctx.warpgate.mobile_type,
            position = position,
            force = force
        }
        utils.link_gates(ctx, "warp-gate-to-surface", "surface-to-warp-gate", ctx.warpgate.gate, mobile_gate)
        ctx.warpgate.mobile_gate = mobile_gate
    end
end
dw.gate.create_mobile_gate = create_mobile_gate

local function gate_research(event)
    local force = event.research.force
    if not force.name:find("^team%-") then return end
    if not dw.has_warp_ctx(force.name) then return end
    local force_name = force.name
    local ctx = dw.warp_ctx(force_name)
    local tech = event.research

    if string.match(tech.name, "dw%-warp%-gate%-%d") then
        ctx.warpgate.mobile_type = "mobile-gate-" .. tech.level
        -- The gate + mobile gate are built on the team's warp surface; its
        -- prereqs (circuit-network, warp-generator-2) don't establish that
        -- surface. Record mobile_type (for the shortcut) but skip the build if
        -- the warp surface isn't live, rather than nil-deref the whole server.
        if not (ctx.warp.current.surface and ctx.warp.current.surface.valid) then
            dw.diag("gate_research force=%s: no warp surface -- skip gate build", force_name)
            return
        end
        if tech.level == 1 then
            create_warpgate(force_name, ctx)
            create_mobile_gate(force_name, ctx)
        else
            -- the gate is deployed
            if ctx.warpgate.mobile_gate and ctx.warpgate.mobile_gate.valid then
                local mobile_gate = ctx.warp.current.surface.create_entity{
                    name = ctx.warpgate.mobile_type,
                    position = ctx.warpgate.mobile_gate.position,
                    force = game.forces[force_name],
                    fast_replace = true,
                    spill = false
                }
                utils.link_gates(ctx, "warp-gate-to-surface", "surface-to-warp-gate", ctx.warpgate.gate, mobile_gate)
                utils.link_cables(ctx.warpgate.gate, mobile_gate, defines.wire_connectors.logic)
                ctx.warpgate.mobile_gate = mobile_gate
            end
            -- replace the gate in inventory if found in one of the team's players.
            for _, player in pairs(force.players) do
                local inventory = player.get_main_inventory()
                if inventory and not inventory.is_empty() then
                    for i = 1, #inventory, 1 do
                        if inventory[i].valid_for_read then
                            if string.match(inventory[i].name, "mobile%-gate%-%d") then
                                local new_gate = {name = ctx.warpgate.mobile_type, count = inventory[i].count}
                                inventory[i].clear()
                                inventory.insert(new_gate)
                            end
                        end
                    end
                end
            end
        end
    end

    if string.match(tech.name, "dw%-number%-stairs%-advanced") then
        ctx.warpgate.chest_number = ctx.warpgate.chest_number + 2
        if ctx.warpgate.gate then
            create_warpgate(force_name, ctx)
        end
    end
end

---Event the catch the destruction of mobile gate. Destruct all chests/loaders
---Save chests content for when a mobile gate is placed again
---@param event (EventData.script_raised_destroy|EventData.on_player_mined_entity|EventData.on_robot_mined_entity|EventData.on_entity_died)
local function mobile_gate_removed_killed(event)
    local gate = event.entity
    if not gate or gate and not gate.valid then return end

    if not string.match(gate.name, "mobile%-gate%-%d") then return end

    -- Resolve the team that owns the surface the gate sits on; not ours -> no-op.
    local owner = dw.surface_owner(gate.surface.index)
    if not owner then return end
    local ctx = dw.warp_ctx(owner)

    local gate_pos = gate.position
    local surface = gate.surface

    local max_index = math.min(ctx.warpgate.chest_number, #dw.warp_gate.chests)
    for i = 1, max_index, 1 do
        local position = dw.warp_gate.chests[i]
        local index = position[1] .. position[2]
        local chest = surface.find_entity(ctx.stairs.chest_type.input, math2d.position.add(gate_pos, position))
        local chest = chest or surface.find_entity(ctx.stairs.chest_type.output, math2d.position.add(gate_pos, position))
        if chest then
            local inventory = chest.get_inventory(defines.inventory.chest)
            if inventory and not inventory.is_empty() then
                ctx.warpgate.mobile_chests[index] = {}
                for i = 1, #inventory, 1 do
                    if inventory[i].valid_for_read then
                        table.insert(ctx.warpgate.mobile_chests[index], {
                            name = inventory[i].name,
                            type = inventory[i].type,
                            count = inventory[i].count,
                            health = inventory[i].health,
                            quality = inventory[i].quality,
                            spoil_tick = inventory[i].spoil_tick,
                            spoil_percent = inventory[i].spoil_percent,
                        })
                    end
                end
            end
            chest.destroy()
        end

        local position = dw.warp_gate.loaders[i]
        local index = position[1] .. position[2]
        local loader = surface.find_entity(ctx.stairs.loader_tier, math2d.position.add(gate_pos, position))
        if loader then
            if loader.loader_filter_mode and loader.loader_filter_mode ~= "none" then
                ctx.warpgate.mobile_loaders[index] = {mode=loader.loader_filter_mode, filters={}}
                for filter_i = 1, loader.filter_slot_count, 1 do
                    ctx.warpgate.mobile_loaders[index].filters[filter_i] = loader.get_filter(filter_i)
                end
            end
            loader.destroy()
        end

        local position = dw.warp_gate.pipes[i]
        local pipe = surface.find_entity(ctx.stairs.pipes_type, math2d.position.add(gate_pos, position))
        if pipe then pipe.destroy() end
    end

    local pole = surface.find_entity("dw-hidden-gate-pole", gate_pos)
    if pole then pole.destroy() end
end


---@param event (EventData.on_built_entity|EventData.on_robot_built_entity)
local function mobile_gate_placed(event)
    local gate = event.entity
    if not gate.valid then return end
    if not string.match(gate.name, "mobile%-gate%-%d") then return end

    -- Resolve the owning team from the surface; the gate may only be placed on
    -- that team's WARP surface (role 'surface'). A nil ctx (unowned surface) is
    -- rejected by entity_built_surface_check.
    local owner = dw.surface_owner(gate.surface.index)
    local ctx = owner and dw.warp_ctx(owner) or nil
    if not utils.entity_built_surface_check(event, ctx, "surface", "dw-messages.cannot-build-mobile-gate") then return end
    local force_name = owner

    if ctx.warpgate.mobile_gate and ctx.warpgate.mobile_gate.valid then
        -- manually destroy it and remove all components, so we are sure to do it before next steps
        ctx.warpgate.mobile_gate.destroy{raise_destroy=true}
    end

    -- if the player uses an outdate version for whatever reason, replace with the right one
    if gate.name ~= ctx.warpgate.mobile_type then
        gate = ctx.warp.current.surface.create_entity{
            name = ctx.warpgate.mobile_type,
            position = gate.position,
            force = game.forces[force_name],
            fast_replace = true,
            spill = false
        }
        -- update entity otherwise it will break other event handlers
        event.entity = gate
    end

    local surface = gate.surface

    ctx.warpgate.mobile_gate = gate

    -- check area for collision with player or enemy structure
    local area_to_check = math2d.bounding_box.create_from_centre({gate.position.x, gate.position.y + 0.5}, 10, 2)

    if utils.check_deployable_collision(ctx, area_to_check, defines.deployable_collision_source.mobile_gate) then
        utils.create_flying_text{
            position = gate.position,
            surface = surface,
            text = {"dw-messages.mobile-gate-other-deployable"},
            color = util.color(defines.hexcolor.orangered.. 'd9')}
        return
    end

    local check_entities = surface.find_entities_filtered{area = area_to_check, force = {force_name, "enemy"}}
    for _, check_e in pairs(check_entities) do
        if check_e.name == "construction-robot" then goto continue end
        if check_e.name == "logistic-robot" then goto continue end
        if check_e.name == "character" then goto continue end

        if check_e.name ~= gate.name then
            utils.create_flying_text{
                position = gate.position,
                surface = surface,
                text = {"dw-messages.mobile-gate-entities-present"},
                color = util.color(defines.hexcolor.orangered.. 'd9')}
            return
        end

        ::continue::
    end

    local mobile_chests = create_entities_relative_to_position(force_name, ctx,
        surface,
        {
            name = nil,
            center = gate.position,
            positions = dw.warp_gate.chests,
            direction = defines.direction.north,
            loader = nil,
            mobile_type = "chest",
            mobile = true,
        }
    )
    local mobile_loaders = create_entities_relative_to_position(force_name, ctx,
        surface,
        {
            name = ctx.stairs.loader_tier,
            center = gate.position,
            positions = dw.warp_gate.loaders,
            direction = nil,
            loader = nil,
            mobile_type = "loader",
            mobile = true,
        }
    )
    local mobile_pipes = create_entities_relative_to_position(force_name, ctx,
        surface,
        {
            name = ctx.stairs.pipes_type,
            center = gate.position,
            positions = dw.warp_gate.pipes,
            direction = nil,
            loader = nil,
            mobile = true,
        }
    )

    local power_pole = surface.create_entity {
        name = "dw-hidden-gate-pole",
        position = gate.position,
        force = game.forces[force_name],
        direction = defines.direction.north,
    }
    power_pole.destructible = false

    if ctx.warpgate.gatepole and power_pole then
        utils.link_cables(power_pole, ctx.warpgate.gatepole, defines.wire_connectors.power)
    end

    utils.link_gates(ctx, "warp-gate-to-surface", "surface-to-warp-gate", ctx.warpgate.gate, gate)
    utils.link_cables(ctx.warpgate.gate, gate, defines.wire_connectors.logic)

    ctx.warpgate.mobile_gate = gate
    link_warp_gate(force_name, ctx, mobile_chests, mobile_loaders, mobile_pipes)
end

dw.register_event(defines.events.on_research_finished, gate_research)

dw.register_event(defines.events.on_built_entity, mobile_gate_placed)
dw.register_event(defines.events.on_robot_built_entity, mobile_gate_placed)
dw.register_event(defines.events.script_raised_revive, mobile_gate_placed) -- trigerred by mods that revive ghost

dw.register_event(defines.events.script_raised_destroy, mobile_gate_removed_killed) -- triggered by destroy()
dw.register_event(defines.events.on_player_mined_entity, mobile_gate_removed_killed)
dw.register_event(defines.events.on_robot_mined_entity, mobile_gate_removed_killed)
dw.register_event(defines.events.on_entity_died, mobile_gate_removed_killed)
