--- All surface platform related function
------------------------------------------------------------

-- v1 CORE port: per-team. Reads ctx.warp.current.surface / ctx.platform.warp.size
-- (the flat globals are never set by the per-team path -> nil -> crash). The
-- entity-clear filter keeps the TEAM's force (was hard-coded "player") so it
-- does not destroy the team's own base sitting on the platform.
local function update_warp_platform_size(force_name, ctx)
    local surface = ctx.warp.current.surface
    if not (surface and surface.valid) then return end
    local size = ctx.platform.warp.size
    dw.diag("update_warp_platform_size force=%s surface=%s size=%s",
        force_name, dw.diag_surface(surface), size)
    -- Ensure the platform chunks exist before tiling. At warp #0 adoption the
    -- surface is freshly created and ungenerated; without forcing generation
    -- first, the later terrain chunk-gen would overwrite the warp-platform floor.
    surface.request_to_generate_chunks({0, 0}, size / 32 + 1)
    surface.force_generate_chunk_requests()
    local new_platform_area = math2d.bounding_box.create_from_centre({0, 0}, size - 1)
    local tiles = {}

    utils.add_tiles(tiles, "warp-platform", new_platform_area.left_top, new_platform_area.right_bottom)

    local filter_area = math2d.bounding_box.create_from_centre({0, 0}, size)
    local stuff_to_remove = surface.find_entities_filtered {
        area = filter_area,
        force = {force_name, "enemy"},
        invert = true,
    }
    for _, stuff in pairs(stuff_to_remove) do
        stuff.destroy()
    end
    surface.set_tiles(tiles)
    if size >= 12 then
        utils.put_warning_tiles(surface, dw.hazard_tiles.surface)
    end
end
dw.update_warp_platform_size = update_warp_platform_size

-- v1 CORE port: PER-TEAM platform clone. Threaded (force_name, ctx) from the
-- warp.lua call site (dw.teleport_platform(force_name, ctx)). Every flat
-- storage.warp.* / storage.platform.* read is now ctx.warp.* / ctx.platform.*
-- so the clone moves THIS team's base from its previous surface to its current
-- one. The clone_area calls themselves are byte-faithful to upstream -- only the
-- source/destination surfaces (ctx.previous -> ctx.current) and the status guard
-- changed. The vehicle/train/player/K2-shelter handling is untouched, just
-- sourced from the ctx surfaces.
local function teleport_platform(force_name, ctx)
    if ctx.warp.status ~= defines.warp.warping then return end

    local platform_area = math2d.bounding_box.create_from_centre({0, 0}, ctx.platform.warp.size, ctx.platform.warp.size)
    local platform_area_delta = math2d.bounding_box.create_from_centre({0, 0}, ctx.platform.warp.size + 2, ctx.platform.warp.size + 2)

    local source = ctx.warp.previous.surface
    local destination = ctx.warp.current.surface

    dw.diag("teleport_platform force=%s src=%s dest=%s size=%s",
        force_name, dw.diag_surface(source), dw.diag_surface(destination), ctx.platform.warp.size)

    --- if destination is nauvis, evict any players inside the platform area before cloning
    if ctx.warp.current.planet == "nauvis" then
        local nauvis_surface = game.planets.nauvis.surface
        if nauvis_surface then
            local players_in_area = nauvis_surface.find_entities_filtered{area = platform_area, type = "character"}
            for _, character in pairs(players_in_area) do
                if character.valid and character.player then
                    dw.safe_teleport(character.player, nauvis_surface, platform_area_delta.left_top, true)
                end
            end
        end
    end

    --- clone the tiles first, so we prepare the area, remove all unwanted stuff
    source.clone_area({
        source_area = platform_area,
        destination_area = platform_area,
        destination_surface = destination,
        clone_tiles = true,
        clone_entities = false,
        clone_decoratives = false,
        clear_destination_entities = true,
        clear_destination_decoratives = true,
        expand_map = true,
        create_build_effect_smoke = false,
    })

    --- check for cars & stuff. Use area_delta so we catch stuff on the border
    local vehicles = source.find_entities_filtered{
        type = {"car", "spider-vehicle"},
        area = platform_area_delta,
    }
    for _, vehicle in pairs(vehicles) do
        local position = vehicle.position
        dw.safe_teleport(vehicle, destination, position, true)
    end

    --- check for train related stuff, as we don't want to teleport them there
    --- but let the clone do its job to properly create them. So we need to remove
    --- the playfrom passengers and drivers
    local trains_and_wagons = source.find_entities_filtered{
        type = {"locomotive", "cargo-wagon", "fluid-wagon", "artillery-wagon"},
        area = platform_area_delta,
    }

    local trains_with_drivers = {}
    local locomotive_data = {}
    for _, train in pairs(trains_and_wagons) do
        local driver = train.get_driver()
        train.set_driver(nil)
        if driver and driver.is_player() then driver = driver.character end
        if driver and driver.valid then
            table.insert(trains_with_drivers, {
                train_position = train.position,
                driver_position = driver.position,
                train_name = train.name,
                driver_name = driver.name,
            })
        end

        if train.type == "locomotive" then
            local locomotive = train.train --[[@as LuaTrain]]
            local train_data = {
                schedule = locomotive.schedule,
                manual_mode = locomotive.manual_mode,
                name = train.name,
                position = train.position

            }
            table.insert(locomotive_data, train_data)
        end
    end

    --- check for players, and teleport them to the new surface
    for _, player in pairs(game.connected_players) do
        if player.physical_surface.name == source.name then
            if math2d.bounding_box.contains_point(platform_area_delta, player.physical_position) or player.controller_type == defines.controllers.ghost then
                if player.controller_type == defines.controllers.ghost then
                    dw.safe_teleport(player, destination, {0, 0}, true)
                else
                    dw.safe_teleport(player, destination, player.physical_position, true)
                end
            else
                -- Off-platform players are left behind on the source world and
                -- die -- UNLESS we are leaving nauvis (the safe home base). Read
                -- the planet from ctx (a STRING, always set) and NOT source.planet:
                -- a nauvis warp surface (mdw-nauvis-wN) has surface.planet == nil
                -- (create_team_surface only associates non-nauvis planets), so
                -- source.planet.name would crash here exactly as get_allowed_planet did.
                if ctx.warp.previous.planet ~= "nauvis" then
                    player.character.die()
                end
            end
        end
    end

    --- Offline members travel by the SAME position rule. A disconnected player's
    --- character is a STANDALONE entity (LuaPlayer.character is nil while
    --- disconnected), so we find the character ENTITY on the source surface and
    --- resolve its owning player via LuaEntity.player (valid for a disconnected
    --- character). An on-platform offline character is MOVED to the destination
    --- (the entity itself travels, so inventory + position are preserved AND it
    --- isn't duplicated by the entity-clone pass below). An off-platform one is
    --- left behind and dies -- the member respawns empty-handed on the platform
    --- when they reconnect. Connected members were already moved above; characters
    --- with no player (orphan bodies) are left to the entity clone as before.
    for _, char in pairs(source.find_entities_filtered{type = "character"}) do
        local p = char.player
        if p and not p.connected then
            if math2d.bounding_box.contains_point(platform_area_delta, char.position) then
                dw.safe_teleport(char, destination, char.position, true)   -- move the body
            elseif ctx.warp.previous.planet ~= "nauvis" then
                char.die()
            end
        end
    end

    --- Check for some other stuff we cannot just clone (due to mod scripts)
    --- Krastorio2 Shelter, as it creates stuff when built.
    local shelter_data = {}
    if script.active_mods['Krastorio2'] or script.active_mods['Krastorio2-spaced-out'] then
        local krastorio_shelter = source.find_entities_filtered{
            name = (prototypes.entity["kr-shelter-plus-container"] and {"kr-shelter-container", "kr-shelter-plus-container"} or {"kr-shelter-container"}),
            area = platform_area_delta,
        }
        if krastorio_shelter[1] then -- player can only put 1 per surface, so there's at most 1
            local shelter = krastorio_shelter[1]
            shelter_data.name = shelter.name
            shelter_data.position = shelter.position
            shelter_data.inventory = {}
            local inventory = shelter.get_inventory(defines.inventory.chest)
            if inventory then
                for i = 1, #inventory do
                    local stack = inventory[i]
                    if stack.valid_for_read then
                        table.insert(shelter_data.inventory, {
                            name = stack.name,
                            count = stack.count,
                            type = stack.type,
                            quality = stack.quality,
                            spoil_tick = stack.spoil_tick,
                            spoil_percent = stack.spoil_percent,
                            health = stack.health,
                        })
                    end
                end
            end
            shelter.destroy{raise_destroy=true}
        end
    end

    --- clone the left entities (includes biters... ?)
    source.clone_area{
        source_area = platform_area,
        destination_area = platform_area,
        destination_surface = destination,
        clone_tiles = false,
        clone_entities = true,
        clone_decoratives = false,
        clear_destination_entities = false,
        clear_destination_decoratives = false,
        expand_map = false,
        create_build_effect_smoke = false
    }

    dw.diag("teleport_platform force=%s platform cloned src=%s -> dest=%s",
        force_name, dw.diag_surface(source), dw.diag_surface(destination))

    for _, train_driver in pairs(trains_with_drivers) do
        local train = destination.find_entity(train_driver.train_name, train_driver.train_position)
        local driver = destination.find_entity(train_driver.driver_name, train_driver.driver_position)
        if train and driver then
            train.set_driver(driver)
        end
    end

    for _, train_data in pairs(locomotive_data) do
        local locomotive = destination.find_entity(train_data.name, train_data.position)
        if locomotive then
            local train = locomotive.train ---@as LuaTrain
            if train then
                train.schedule = train_data.schedule
                train.manual_mode = train_data.manual_mode
            end
        end
    end

    --- Krastorio2 Shelter - put it back and restore its inventory
    if shelter_data.name then
        local shelter = destination.create_entity{
            name = shelter_data.name,
            position = shelter_data.position,
            force = game.forces.player,
            raise_built = true
        }
        if shelter then
            local inventory = shelter.get_inventory(defines.inventory.chest)
            if inventory then
                for _, stack in pairs(shelter_data.inventory) do
                    inventory.insert(stack)
                end
            end
        end
    end

    -- Retire the previous surface for THIS team (idempotent with warp.lua's own
    -- post-clone call: the first invocation flips ctx.warp.status to awaiting, so
    -- the other is a guarded no-op -- exactly one retire happens).
    dw.update_surfaces_properties(force_name, ctx)
end
dw.teleport_platform = teleport_platform

-- Re-find the warp-SIDE chest/loader handles (the 'surface' role bucket) after a
-- platform clone invalidates their unit_numbers. The dimension-SIDE handles live
-- on a surface that is never cloned, so they persist and must NOT be re-found.
local function relink_loader_chest(ctx, surface, positions_list)
    for _, positions in pairs(positions_list) do
        local chest_index = 'surface_' .. positions.chests[1][1] .. '_' .. positions.chests[1][2]
        local loader_index = 'surface_' .. positions.loaders[1][1] .. '_' .. positions.loaders[1][2]

        --- if we didn't store any pair with that index, it means the chest/loader pair is not yet deployed
        if not ctx.stairs.chest_pairs[chest_index] then goto continue end

        local chest = surface.find_entities_filtered{position = positions.chests[1], name = {"dw-chest", "dw-logistic-input", "dw-logistic-output"}}
        local loader = surface.find_entities_filtered{position = positions.loaders[1], name = {ctx.stairs.loader_tier}}

        if chest[1] and loader[1] then
            -- Re-find the warp-side chest unconditionally (the item-flow-critical
            -- handle); only the loader-bucket update needs the existence guard
            -- (the bucket entry is created alongside the chest_pair, so it is
            -- normally present -- the guard just avoids a nil-index in the rare
            -- case it isn't).
            ctx.stairs.chest_pairs[chest_index].A = chest[1]
            local lp = ctx.stairs.chest_loader_pairs.surface[loader_index]
            if lp then
                lp.loader = loader[1]
                lp.chest = chest[1]
            end
        end
        ::continue::
    end
end

local function relink_pipes(ctx, surface, positions_list)
    for _, positions in pairs(positions_list) do
        local index = 'surface_' .. positions.pipes[1][1] .. '_' .. positions.pipes[1][2]

        --- if we didn't store any pair with that index, it means the pipe pair is not yet deployed
        if not ctx.stairs.pipe_pairs[index] then goto continue end

        local pipe = surface.find_entities_filtered{position = positions.pipes[1], name = {ctx.stairs.pipes_type}}

        if pipe[1] and ctx.stairs.pipe_pairs[index].B and ctx.stairs.pipe_pairs[index].B.valid then
            ctx.stairs.pipe_pairs[index].A = pipe[1]
            pipe[1].fluidbox.add_linked_connection(0, ctx.stairs.pipe_pairs[index].B, 0)
        end
        ::continue::
    end
end

--- force update some entities that may be broken due to clone (new unit_numbers)
--- and the fact surfaces are not linked to planet as soon as they are created.
--- Called per-team from the warp loop after each Arrive. Re-finds ONLY the warp-
--- side handles; dimension-side handles are on un-cloned surfaces and persist.
dw.platform_force_update_entities = function(force_name, ctx)
    local surface = ctx.warp.current.surface
    if not (surface and surface.valid) then return end
    local platform = math2d.bounding_box.create_from_centre({0, 0}, ctx.platform.warp.size, ctx.platform.warp.size)

    --- delete corpses
    local corpses = surface.find_entities_filtered({area = platform, type="corpse"})
    for _, corpse in pairs(corpses) do
        corpse.destroy()
    end

    -- update lightning attractors
    local lightning_attractors = surface.find_entities_filtered{
        type = "lightning-attractor",
        area = platform,
    }

    for _, rod in pairs(lightning_attractors) do
        rod.clone{position=rod.position, create_build_effect_smoke=false}
        rod.destroy()
    end

    --- update teleporters (radio station + warpgate)
    local radio_tower = surface.find_entity(dw.entities.surface_radio_station.name, dw.entities.surface_radio_station.position)
    if radio_tower and ctx.teleporter['factory-to-warp'] and ctx.teleporter['factory-to-warp'].from then
        utils.link_gates(ctx, 'factory-to-warp', 'warp-to-factory', ctx.teleporter['factory-to-warp'].from, radio_tower)
        utils.link_cables(ctx.teleporter['factory-to-warp'].from, radio_tower, defines.wire_connectors.logic)
    end

    --- update electricity link
    local surface_radio_pole = surface.find_entity(dw.entities.surface_radio_pole.name, dw.entities.surface_radio_pole.position)
    if ctx.platform.factory.surface and ctx.platform.factory.surface.valid then
        local factory_power_pole = ctx.platform.factory.surface.find_entity(dw.entities.pole_factory_surface.name, dw.entities.pole_factory_surface.position)
        if surface_radio_pole and factory_power_pole then
            utils.link_cables(surface_radio_pole, factory_power_pole, defines.wire_connectors.power)
        end
    end

    --- relink loaders/chests between surfaces
    relink_loader_chest(ctx, surface, dw.stairs.surface_factory)
    relink_pipes(ctx, surface, dw.stairs.surface_factory)

    --- recreate and relink mobile gate
    if ctx.warpgate.gate then
        local warp_gate = surface.find_entity(dw.warp_gate.name, dw.warp_gate.position)
        if warp_gate then
            ctx.warpgate.gate = warp_gate
            ctx.warpgate.mobile_gate = nil
            dw.gate.create_mobile_gate(force_name, ctx)
            dw.gate.link_warp_gate(force_name, ctx, nil, nil, nil, true)
        end
        -- relink power pole
        local pole = surface.find_entity("dw-hidden-gate-pole", dw.warp_gate.position)
        if pole and surface_radio_pole then
            utils.link_cables(surface_radio_pole, pole, defines.wire_connectors.power)
        end
        ctx.warpgate.gatepole = pole
    end
end


-- Per-team platform-growth gate (restores DW's warp-platform-size progression).
-- DW grew the platform when warp-platform-size-N was researched. MTS team forces
-- research independently, so resolve event.research.force -> that team's ctx and
-- grow ONLY that team's platform.
local function on_technology_research_finished(event)
    local tech = event.research
    local force = tech.force
    -- Only team forces have a warp ctx; ignore player/spectator/enemy/neutral.
    if not force.name:find("^team%-") then return end
    if not dw.has_warp_ctx(force.name) then return end
    local ctx = dw.warp_ctx(force.name)

    if string.match(tech.name, "warp%-platform%-size%-%d+") then
        -- Tier table dw.platform_size.warp = {8,22,36,...}; level N -> index N+1.
        ctx.platform.warp.size = dw.platform_size.warp[tech.level + 1]
        update_warp_platform_size(force.name, ctx)
        dw.diag("warp-platform-size-%d researched: force=%s -> platform size=%d",
            tech.level, force.name, ctx.platform.warp.size)
    end

    -- platform-radar (re-enabled in P4/S7 now the aux platforms are per-team):
    -- wake the surface radio station and drop a hidden radar on each dimension
    -- platform the team owns. Guarded per surface so a team that hasn't unlocked
    -- a given platform is simply skipped.
    if string.match(tech.name, "platform%-radar") then
        local radio_tower = ctx.warp.current.surface
            and ctx.warp.current.surface.find_entity(dw.entities.surface_radio_station.name, dw.entities.surface_radio_station.position)
        if radio_tower then
            radio_tower.active = true
        end
        for _, role in ipairs({"factory", "mining", "power"}) do
            local s = ctx.platform[role].surface
            if s and s.valid then
                local radar = s.create_entity{name = "dw-hidden-radar", force = force, position = {0, 0}}
                radar.destructible = false
            end
        end
    end
end


dw.register_event(defines.events.on_research_finished, on_technology_research_finished)
