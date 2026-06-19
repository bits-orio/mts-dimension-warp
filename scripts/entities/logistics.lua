dw.logistics = dw.logistics or {}

-- PORTED to per-team ctx (P4/S3). Upstream keyed the chest/loader buckets by bare
-- surface NAME via dw.safe_surfaces[surface.name]; under MTS each team's surfaces
-- have unique names (mdw-team-1-factory), so every surface collapsed to "surface"
-- and the indices collided. We key by the per-team ROLE token from
-- dw.surface_role(ctx, surface) instead ('surface'/'factory'/'mining'/'power';
-- the 'gate' bucket is a literal owned by warpgate.lua). All state moves from the
-- flat storage.stairs to ctx.stairs, and entities belong to the team force.

--- surface A should always be first surface in dw.stairs index name.
--- surface B should always be second surface in dw.stairs index name.
--- in the case of the surface mobile gate, A = platform, B = anywhere.
local function create_loader_chest_pair(force_name, ctx, surface_A, surface_B, positions)
    local surface_name_A = dw.surface_role(ctx, surface_A)
    local surface_name_B = dw.surface_role(ctx, surface_B)
    local force = game.forces[force_name]

    local max = math.min(#positions, ctx.stairs.chest_number)
    for i = 1, max, 1 do
        local chest_index = surface_name_A .. '_' .. positions[i].chests[1][1] .. '_' .. positions[i].chests[1][2]
        local loader_index_A = surface_name_A .. '_' .. positions[i].loaders[1][1] .. '_' .. positions[i].loaders[1][2]
        local loader_index_B = surface_name_B .. '_' .. positions[i].loaders[2][1] .. '_' .. positions[i].loaders[2][2]
        local chest_A = nil
        local chest_B = nil
        local loader_A = nil
        local loader_B = nil
        local type = defines.item_direction.push

        if ctx.stairs.chest_pairs[chest_index] then
            chest_A = ctx.stairs.chest_pairs[chest_index].A
            chest_B = ctx.stairs.chest_pairs[chest_index].B
            type = ctx.stairs.chest_pairs[chest_index].type
        end
        if ctx.stairs.chest_loader_pairs[surface_name_A][loader_index_A] then
            loader_A = ctx.stairs.chest_loader_pairs[surface_name_A][loader_index_A].loader
        end
        if ctx.stairs.chest_loader_pairs[surface_name_B][loader_index_B] then
            loader_B = ctx.stairs.chest_loader_pairs[surface_name_B][loader_index_B].loader
        end

        --- if the chest is not valid or doesn't exist, we create it
        if not chest_A or (chest_A and not chest_A.valid) then
            local to_remove = surface_A.find_entities_filtered {position = positions[i].chests[1], type = {"character", "rocket-silo-rocket", "cargo-pod"}, invert = true}
            for _, entity in pairs(to_remove) do entity.destroy() end
            chest_A = surface_A.create_entity {
                name = (type == defines.item_direction.push) and ctx.stairs.chest_type.input or ctx.stairs.chest_type.output,
                position = positions[i].chests[1],
                force = force,
                direction = defines.direction.north
            }
            chest_A.destructible = false
        end

        --- if the chest is not valid or doesn't exist, we create it
        if not chest_B or (chest_B and not chest_B.valid) then
            local to_remove = surface_B.find_entities_filtered {position = positions[i].chests[2], type = {"character", "rocket-silo-rocket", "cargo-pod"}, invert = true}
            for _, entity in pairs(to_remove) do entity.destroy() end
            chest_B = surface_B.create_entity {
                name = (type == defines.item_direction.push) and ctx.stairs.chest_type.output or ctx.stairs.chest_type.input,
                position = positions[i].chests[2],
                force = force,
                direction = defines.direction.north
            }
            chest_B.destructible = false
        end

        --- pair both chest and provide the type of flow.
        ctx.stairs.chest_pairs[chest_index] = {
            A = chest_A,
            B = chest_B,
            type = type,
        }

        --- we create each loaders, and set them the right type
        if not loader_A or (loader_A and not loader_A.valid) then
            local to_remove = surface_A.find_entities_filtered {position = positions[i].loaders[1], type = {"character", "rocket-silo-rocket", "cargo-pod"}, invert = true}
            for _, entity in pairs(to_remove) do entity.destroy() end
            local loader_type = (type == defines.item_direction.push) and "input" or "output"
            loader_A = surface_A.create_entity {
                name = ctx.stairs.loader_tier,
                position = positions[i].loaders[1],
                force = force,
                direction = positions[i].direction[1][loader_type],
                type = loader_type
            }
            loader_A.destructible = false
        end

        if not loader_B or (loader_B and not loader_B.valid) then
            local to_remove = surface_B.find_entities_filtered {position = positions[i].loaders[2], type = {"character", "rocket-silo-rocket", "cargo-pod"}, invert = true}
            for _, entity in pairs(to_remove) do entity.destroy() end
            local loader_type = (type == defines.item_direction.push) and "output" or "input"
            loader_B = surface_B.create_entity {
                name = ctx.stairs.loader_tier,
                position = positions[i].loaders[2],
                force = force,
                direction = positions[i].direction[2][loader_type],
                type = loader_type,
            }
            loader_B.destructible = false
        end

        --- we store each pair (chest/loader) and save the ref to find the linked pair
        --- this is used for post warp check / rotation of loaders to change flow direction
        ctx.stairs.chest_loader_pairs[surface_name_A][loader_index_A] = {
            loader = loader_A,
            chest = chest_A,
            type = (type == defines.item_direction.push) and "input" or "output",
            ref = {surface_name_B, loader_index_B}
        }
        ctx.stairs.chest_loader_pairs[surface_name_B][loader_index_B] = {
            loader = loader_B,
            chest = chest_B,
            type = (type == defines.item_direction.push) and "output" or "input",
            ref = {surface_name_A, loader_index_A}
        }
    end
end
dw.logistics.create_loader_chest_pair = create_loader_chest_pair

--- surface A should always be first surface in dw.stairs index name.
--- surface B should always be second surface in dw.stairs index name.
--- order matters as it's used for the storage
local function create_pipe_pairs(force_name, ctx, surface_A, surface_B, positions)
    local surface_name_A = dw.surface_role(ctx, surface_A)
    local force = game.forces[force_name]

    local max = math.min(#positions, ctx.stairs.chest_number)
    for i = 1, max, 1 do
        local pipe_index = surface_name_A .. '_' .. positions[i].pipes[1][1] .. '_' .. positions[i].pipes[1][2]

        if ctx.stairs.pipe_pairs[pipe_index] and ctx.stairs.pipe_pairs[pipe_index].valid then goto continue end

        --- destroy what's existing in pipe position
        local to_remove = surface_A.find_entities_filtered {position = positions[i].pipes[1], type = {"character", "rocket-silo-rocket", "cargo-pod"}, invert = true}
        for _, entity in pairs(to_remove) do entity.destroy() end
        local pipe_A = surface_A.create_entity {
            name = ctx.stairs.pipes_type,
            position = positions[i].pipes[1],
            force = force,
            direction = (i % 2 == 0) and defines.direction.east or defines.direction.west,
        }
        pipe_A.destructible = false

        local to_remove = surface_B.find_entities_filtered {position = positions[i].pipes[2], type = {"character", "rocket-silo-rocket", "cargo-pod"}, invert = true}
        for _, entity in pairs(to_remove) do entity.destroy() end
        local pipe_B = surface_B.create_entity {
            name = ctx.stairs.pipes_type,
            position = positions[i].pipes[2],
            force = force,
            direction = (i % 2 == 0) and defines.direction.east or defines.direction.west,
        }
        pipe_B.destructible = false

        pipe_A.fluidbox.add_linked_connection(0, pipe_B, 0)
        ctx.stairs.pipe_pairs[pipe_index] = {A = pipe_A, B = pipe_B}
        ::continue::
    end
end
dw.logistics.create_pipe_pairs = create_pipe_pairs

local function upgrade_stairs(force_name, ctx)
    local force = game.forces[force_name]
    for surface_name, loader_pair in pairs(ctx.stairs.chest_loader_pairs) do
        for index, stairs in pairs(loader_pair) do
            local loader = stairs.loader
            if not loader or not loader.valid then goto continue end
            local surface = stairs.loader.surface

            local new_loader = surface.create_entity{
                name = ctx.stairs.loader_tier,
                position = loader.position,
                force = force,
                direction = loader.direction,
                type = loader.loader_type,
                fast_replace = true,
            }
            new_loader.destructible = false
            ctx.stairs.chest_loader_pairs[surface_name][index].loader = new_loader

            ::continue::
        end
    end
end

local function update_chests(force_name, ctx)
    local force = game.forces[force_name]
    for surface_name, loader_pair in pairs(ctx.stairs.chest_loader_pairs) do
        for index, stairs in pairs(loader_pair) do
            local chest = stairs.chest
            if not chest or not chest.valid then goto continue end
            local surface = stairs.chest.surface

            -- find the index of the chest pair
            local chest_index = surface_name .. '_' .. chest.position.x .. '_' .. chest.position.y
            local chest_pair_index = "A"
            local chest_name = ""
            if not ctx.stairs.chest_pairs[chest_index] then
                -- the current pair is not the "A" chest, so check from the pair ref
                local pair_chest = ctx.stairs.chest_loader_pairs[stairs.ref[1]][stairs.ref[2]].chest
                local chest_surface_name = dw.surface_role(ctx, pair_chest.surface)
                if chest_surface_name == "surface" and surface_name == "gate" then chest_surface_name = "gate" end
                chest_index = chest_surface_name .. '_' .. pair_chest.position.x .. '_' .. pair_chest.position.y
                chest_pair_index = "B"

                -- here it means we are the "destination" of the item direction, so we need to inverse the chest type
                local chest_type = ctx.stairs.chest_pairs[chest_index].type
                chest_name = (chest_type == defines.item_direction.push) and ctx.stairs.chest_type.output or ctx.stairs.chest_type.input
            else
                local chest_type = ctx.stairs.chest_pairs[chest_index].type
                chest_name = (chest_type == defines.item_direction.push) and ctx.stairs.chest_type.input or ctx.stairs.chest_type.output
            end

            -- upgrade the chest and store it in the globals
            local new_chest = surface.create_entity{
                name = chest_name,
                position = chest.position,
                force = force,
                direction = chest.direction,
                fast_replace = true,
            }
            new_chest.destructible = false
            ctx.stairs.chest_loader_pairs[surface_name][index].chest = new_chest
            ctx.stairs.chest_pairs[chest_index][chest_pair_index] = new_chest

            ::continue::
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

    if string.match(tech.name, "dw%-.*%-loader%-stairs") then
        local loader = string.match(tech.name, "dw%-(.*)%-stairs")
        if loader then
            ctx.stairs.loader_tier = "dw-stair-" .. loader
            upgrade_stairs(force_name, ctx)
        end
    end

    if string.match(tech.name, "dw%-number%-stairs%-.*") then
        ctx.stairs.chest_number = ctx.stairs.chest_number + 2
        if ctx.platform.factory.surface and ctx.platform.mining.surface then
            create_loader_chest_pair(force_name, ctx, ctx.platform.factory.surface, ctx.platform.mining.surface, dw.stairs.factory_mining)
            create_pipe_pairs(force_name, ctx, ctx.platform.factory.surface, ctx.platform.mining.surface, dw.stairs.factory_mining)
        end
        if ctx.platform.power.surface and ctx.platform.mining.surface then
            create_loader_chest_pair(force_name, ctx, ctx.platform.mining.surface, ctx.platform.power.surface, dw.stairs.mining_power)
            create_pipe_pairs(force_name, ctx, ctx.platform.mining.surface, ctx.platform.power.surface, dw.stairs.mining_power)
        end
        -- surface_factory pairs link the WARP surface to the factory; guard BOTH
        -- (the factory guard alone left ctx.warp.current.surface an unchecked deref).
        if ctx.platform.factory.surface and ctx.platform.factory.surface.valid
            and ctx.warp.current.surface and ctx.warp.current.surface.valid then
            create_loader_chest_pair(force_name, ctx, ctx.warp.current.surface, ctx.platform.factory.surface, dw.stairs.surface_factory)
            create_pipe_pairs(force_name, ctx, ctx.warp.current.surface, ctx.platform.factory.surface, dw.stairs.surface_factory)
        end
    end

    if string.match(tech.name, "dw%-stair%-logistic%-chest") then
        ctx.stairs.chest_type.input = "dw-logistic-input"
        ctx.stairs.chest_type.output = "dw-logistic-output"
        update_chests(force_name, ctx)
    end
end



--- Shuttle items across every chest pair of ONE team. Driven per-team via
--- register_team_tick(5) (upstream was a single global on_nth_tick_5 over the
--- flat chest_pairs).
local function move_chest_items(force_name, ctx)
    for k, chest_pair in pairs(ctx.stairs.chest_pairs) do
        local chest_A = chest_pair.A
        local chest_B = chest_pair.B
        if chest_A and chest_B and chest_A.valid and chest_B.valid then
            local inventory_A = chest_A.get_inventory(defines.inventory.chest)
            local inventory_B = chest_B.get_inventory(defines.inventory.chest)
            if chest_pair.type == defines.item_direction.push then
                utils.transfert_chest_content(inventory_A, inventory_B)
            else
                utils.transfert_chest_content(inventory_B, inventory_A)
            end
        end
    end
end

local function invert_chest_flow(event)
    local entity = event.entity
    if string.match(entity.name, "dw%-stair%-loader") or string.match(entity.name, "dw%-stair%-%a+%-loader") then
        -- Resolve the team that owns the surface the loader sits on. A loader on a
        -- non-team surface (no owner) is not ours -- no-op.
        local owner = dw.surface_owner(entity.surface.index)
        if not owner then return end
        local ctx = dw.warp_ctx(owner)

        local surface_name = dw.surface_role(ctx, entity.surface)
        local index = surface_name .. '_' .. entity.position.x .. '_' .. entity.position.y
        if surface_name == "surface" and not ctx.stairs.chest_loader_pairs[surface_name][index] then
            surface_name = "gate"
            index = surface_name .. '_' .. entity.position.x .. '_' .. entity.position.y
        end

        if ctx.stairs.chest_loader_pairs[surface_name][index] then
            local pair_A = ctx.stairs.chest_loader_pairs[surface_name][index]
            local pair_B = ctx.stairs.chest_loader_pairs[pair_A.ref[1]][pair_A.ref[2]]

            --- invert loaders (we don't need to invert loaderA as the event is triggered by it already)
            if pair_A and pair_A.loader and pair_A.loader.valid then
                pair_A.type = defines.opposite_loader[pair_A.type]
            end
            if pair_B and pair_B.loader and pair_B.loader.valid then
                pair_B.loader.loader_type = defines.opposite_loader[pair_B.loader.loader_type]
                pair_B.type = defines.opposite_loader[pair_B.type]
            end

            --- chest invertion, only do something if we have logistic chests
            if pair_A and pair_A.chest and pair_A.chest.name ~= "dw-chest" then
                local chest_type = (pair_A.type == "input") and ctx.stairs.chest_type.input or ctx.stairs.chest_type.output
                local chest_A = pair_A.chest.surface.create_entity {
                    name = chest_type,
                    position = pair_A.chest.position,
                    force = pair_A.chest.force,
                    fast_replace = true
                }
                chest_A.destructible = false
                pair_A.chest = chest_A

                if pair_B and pair_B.chest then
                    local chest_type = (pair_B.type == "input") and ctx.stairs.chest_type.input or ctx.stairs.chest_type.output
                    local chest_B = pair_B.chest.surface.create_entity {
                        name = chest_type,
                        position = pair_B.chest.position,
                        force = pair_B.chest.force,
                        fast_replace = true
                    }
                    chest_B.destructible = false
                    pair_B.chest = chest_B
                end
            end

            --- find the corresponding chest pair
            local chest_index = surface_name .. '_' .. pair_A.chest.position.x .. '_' .. pair_A.chest.position.y
            if ctx.stairs.chest_pairs[chest_index] then
                ctx.stairs.chest_pairs[chest_index] = {
                    A = pair_A.chest,
                    B = pair_B and pair_B.chest or nil,
                    type = (pair_A.type == "input") and defines.item_direction.push or defines.item_direction.pull,
                }
            else
                local surface_name_B = pair_A.ref[1]
                local chest_index = surface_name_B .. '_' .. pair_B.chest.position.x .. '_' .. pair_B.chest.position.y
                if ctx.stairs.chest_pairs[chest_index] then
                    ctx.stairs.chest_pairs[chest_index] = {
                        A = pair_B.chest,
                        B = pair_A.chest,
                        type = (pair_B.type == "input") and defines.item_direction.push or defines.item_direction.pull,
                    }
                end
            end
        end
    end
end


dw.register_event(defines.events.on_research_finished, on_technology_research_finished)
dw.register_team_tick(5, move_chest_items)
dw.register_event(defines.events.on_player_rotated_entity, invert_chest_flow)
