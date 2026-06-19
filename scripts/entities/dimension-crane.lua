if not script.active_mods['space-age'] then return end

-- PORTED to per-team ctx (P4/S7). Yumako/jellynut cranes the team builds on its
-- WARP surface, feeding fruit/seed chests on the team's MINING dimension platform.
-- All flat storage.agricultural / storage.platform.mining state moves to ctx;
-- entities belong to the team force. move_crane_items runs per-team via a team
-- tick; crane_built resolves the team from the surface owner, research from
-- event.research.force.

local function transfer_seeds(from_inventory, to_inventory, name, quantity)
    for i = 1, #from_inventory do
        if quantity <= 0 then return end
        local stack = from_inventory[i]

        if stack.valid_for_read then
            if stack.name == name   then
                local inserted_stack = {
                    name = stack.name,
                    count = math.min(stack.count, quantity),
                    quality = table.deepcopy(stack.quality)
                }

                local inserted = to_inventory.insert(inserted_stack)
                if inserted > 0 then
                    stack.count = stack.count - inserted
                    quantity = quantity - inserted
                end
            end
        end
    end
end

local function transfer_seeds_fruits(towers, seed_chest, fruit_chest, seed_name)
    if not (seed_chest and seed_chest.valid and fruit_chest and fruit_chest.valid) then return end
    for index = #towers, 1, -1 do
        local tower = towers[index]
        if not tower.valid then
            table.remove(towers, index)
            goto continue
        end

        local tower_seed_inventory = tower.get_inventory(defines.inventory.agricultural_tower_input)
        local tower_fruit_inventory = tower.get_inventory(defines.inventory.agricultural_tower_output)
        local fruit_chest_inventory = fruit_chest.get_inventory(defines.inventory.chest)
        local seed_chest_inventory = seed_chest.get_inventory(defines.inventory.chest)

        utils.transfert_chest_content(tower_fruit_inventory, fruit_chest_inventory)
        if tower_seed_inventory.get_item_count(seed_name) < 1 then
            transfer_seeds(seed_chest_inventory, tower_seed_inventory, seed_name, 5)
        end

        ::continue::
    end
end

local function crane_built(event)
    local crane = event.entity
    if not crane.valid then return end
    if not string.match(crane.name, "dimension%-crane%-%a+") then return end

    -- Resolve the owning team from the surface; cranes may only be placed on that
    -- team's WARP surface (role 'surface'). A nil ctx is rejected.
    local owner = dw.surface_owner(crane.surface.index)
    local ctx = owner and dw.warp_ctx(owner) or nil
    if not utils.entity_built_surface_check(event, ctx, "surface", "dw-messages.cannot-build-crane") then return end
    local force_name = owner

    if crane.name == "dimension-crane-yumako" then table.insert(ctx.agricultural.yumako_towers, crane) end
    if crane.name == "dimension-crane-jellynut" then table.insert(ctx.agricultural.jellynut_towers, crane) end

    local crane_pole = crane.surface.create_entity {
        name = "dw-hidden-gate-pole",
        position = crane.position,
        force = game.forces[force_name],
    }
    crane_pole.destructible = false
    if ctx.agricultural.pole and ctx.agricultural.pole.valid then
        utils.link_cables(crane_pole, ctx.agricultural.pole, defines.wire_connectors.power)
    end
end

---@param event (EventData.on_player_mined_entity|EventData.on_robot_mined_entity|EventData.on_entity_died)
local function crane_destroyed(event)
    local crane = event.entity
    if not crane.valid then return end
    if not string.match(crane.name, "dimension%-crane%-%a+") then return end

    -- remove the hidden pole when we remove the crane
    local pole = crane.surface.find_entity("dw-hidden-gate-pole", crane.position)
    if pole then pole.destroy() end
end

local function move_crane_items(force_name, ctx)
    transfer_seeds_fruits(ctx.agricultural.jellynut_towers, ctx.agricultural.jellynut_input, ctx.agricultural.jellynut_output, "jellynut-seed")
    transfer_seeds_fruits(ctx.agricultural.yumako_towers, ctx.agricultural.yumako_input, ctx.agricultural.yumako_output, "yumako-seed")
end

local function on_technology_research_finished(event)
    local force = event.research.force
    if not force.name:find("^team%-") then return end
    if not dw.has_warp_ctx(force.name) then return end
    local force_name = force.name
    local ctx = dw.warp_ctx(force_name)
    local tech = event.research

    if tech.name == "dimension-crane" then
        if not (ctx.platform.mining.surface and ctx.platform.mining.surface.valid) then return end
        local fforce = game.forces[force_name]
        local mining = ctx.platform.mining.surface
        local yumako_input = mining.create_entity {
            name = "dw-crane-yumako-seed-input",
            position = {-0.5, -0.5},
            force = fforce,
        }
        local yumako_output = mining.create_entity {
            name = "dw-crane-yumako-output",
            position = {-0.5, 0.5},
            force = fforce,
        }
        local jellynut_input = mining.create_entity {
            name = "dw-crane-jellynut-seed-input",
            position = {0.5, -0.5},
            force = fforce,
        }
        local jellynut_output = mining.create_entity {
            name = "dw-crane-jellynut-output",
            position = {0.5, 0.5},
            force = fforce,
        }
        local fruit_pole = mining.create_entity {
            name = "dw-hidden-gate-pole",
            position = {0.5, 0.5},
            force = fforce,
        }
        yumako_input.destructible = false
        yumako_output.destructible = false
        jellynut_input.destructible = false
        jellynut_output.destructible = false
        fruit_pole.destructible = false

        ctx.agricultural.yumako_input = yumako_input
        ctx.agricultural.yumako_output = yumako_output
        ctx.agricultural.jellynut_input = jellynut_input
        ctx.agricultural.jellynut_output = jellynut_output

        ctx.agricultural.pole = fruit_pole

        ctx.agricultural.yumako_towers = {}
        ctx.agricultural.jellynut_towers = {}
    end
end

dw.register_event(defines.events.on_research_finished, on_technology_research_finished)
dw.register_team_tick(60, move_crane_items)

dw.register_event(defines.events.on_built_entity, crane_built)
dw.register_event(defines.events.on_robot_built_entity, crane_built)
dw.register_event(defines.events.script_raised_revive, crane_built)

dw.register_event(defines.events.on_player_mined_entity, crane_destroyed)
dw.register_event(defines.events.on_robot_mined_entity, crane_destroyed)
dw.register_event(defines.events.on_entity_died, crane_destroyed)
dw.register_event(defines.events.script_raised_destroy, crane_destroyed)
