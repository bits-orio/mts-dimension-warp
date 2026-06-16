--- Teleport mechanics are all here
------------------------------------------------------------
-- v1 CORE port: teleport is now PER-TEAM. A player's team is their force
-- (player.force.name); their warp context is dw.warp_ctx(force_name). Surfaces
-- are routed back to their owning team through the surface-index reverse map
-- (dw.surface_owner) so a teleporter/route only fires for the team that owns
-- both endpoints.

non_player_controllers = {
    [defines.controllers.god] = true,
    [defines.controllers.editor] = true,
    [defines.controllers.spectator] = true,
    [defines.controllers.remote] = true,
}

-- Resolve the warp context that owns a surface, or nil if the surface isn't a
-- tracked team surface. Uses the O(1) surface-index reverse map.
local function ctx_for_surface(surface)
    if not (surface and surface.valid) then return nil end
    local owner = dw.surface_owner(surface.index)
    if not owner then return nil end
    return dw.warp_ctx(owner), owner
end

--- contain everything related to player teleport between surfaces
local function safe_teleport(player_or_vehicle, surface, position, force_teleport)
    position = {x = position.x or position[1], y = position.y or position[2]}
    local is_player = player_or_vehicle.is_player()
    local controller_type = is_player and player_or_vehicle.controller_type or nil
    local type = is_player and "character" or player_or_vehicle.prototype
    local index = is_player and player_or_vehicle.index or player_or_vehicle.unit_number

    if not surface then return end
    if is_player and non_player_controllers[controller_type] and not force_teleport then return end

    -- prevent teleporting from anywhere to the surface if we are currently in warp.
    -- Route via the destination surface's owning team context.
    local ctx = ctx_for_surface(surface)
    if ctx and ctx.warp.status ~= defines.warp.awaiting
        and ctx.warp.previous and surface.name == ctx.warp.previous.name then
        if is_player then player_or_vehicle.print({"dw-messages.warp-no-teleport"}) end
        return
    end

    position = surface.find_non_colliding_position(type, position, 5, 0.5, false) or position
    player_or_vehicle.teleport(position, surface)

    -- Record anti-spam against the teleporting player's team context (fall back to
    -- the destination's team for vehicles, whose force may not be a tracked team).
    local from_ctx = is_player and dw.has_warp_ctx(player_or_vehicle.force.name)
        and dw.warp_ctx(player_or_vehicle.force.name) or ctx
    if from_ctx then
        from_ctx.players_last_teleport[index] = game.tick
    end
end
dw.safe_teleport = safe_teleport

---
local function check_player_teleport()
    for player_index, player in pairs(game.connected_players) do
        if not player.walking_state.walking and not player.driving then goto continue end

        -- A player's warp context is their team's. Skip players not on a tracked team.
        if not dw.has_warp_ctx(player.force.name) then goto continue end
        local ctx = dw.warp_ctx(player.force.name)

        -- prevent teleport spam
        if (ctx.players_last_teleport[player_index] or 0) > game.tick - 20 then
            goto continue
        end

        -- use the bounding box to determine the size of the check area
        local position = player.physical_position
        local bounding_box = player.character and player.character.bounding_box

        if player.driving then
            local vehicle = (player.controller_type ~= defines.controllers.remote) and player.physical_vehicle or player.vehicle
            if not vehicle then goto continue end
            position = vehicle.position
            bounding_box = vehicle.bounding_box
        end
        if player.character and player.character.is_flying then
            position.y = position.y + player.character.flight_height
        end
        if not bounding_box then goto continue end

        local entity_size = 0.2 + math2d.position.distance(bounding_box.left_top, bounding_box.right_bottom) / 2
        local check_area = {
            {position.x - entity_size, position.y - entity_size},
            {position.x + entity_size, position.y + entity_size}
        }

        local entities = player.surface.find_entities_filtered{area = check_area, subgroup="warpgate"}

        --- is the entities found an active teleporter ?
        for _, found_entity in pairs(entities) do
            for _, teleporter in pairs(ctx.teleporter) do
                if not teleporter.active then goto continue_teleport end
                if not teleporter.from.valid or not teleporter.to.valid then goto continue_teleport end
                if player.surface.name ~= teleporter.from.surface.name then goto continue_teleport end
                if teleporter.from == found_entity then
                    local relative_position = math2d.position.subtract(teleporter.from.position, position)

                    -- make sure we are outside of the teleporter area when teleporting
                    -- so we check current length with increase, compared to the "length" of the target teleporter half-size + entity size
                    local distance = math2d.position.vector_length(relative_position) * 1.3
                    local teleporter_check_distance = entity_size - 0.2 + math2d.position.distance(teleporter.to.bounding_box.left_top, teleporter.to.bounding_box.right_bottom) / 2
                    if distance < teleporter_check_distance then
                        relative_position = math2d.position.multiply_scalar(relative_position, (teleporter_check_distance / distance) + 0.3)
                    else
                        relative_position = math2d.position.multiply_scalar(relative_position, 1.3)
                    end

                    local final_pos = math2d.position.add(teleporter.to.position, relative_position)

                    if player.driving then
                        local vehicle = (player.controller_type ~= defines.controllers.remote) and player.physical_vehicle or player.vehicle
                        if not vehicle then goto continue end
                        local speed = vehicle.speed
                        safe_teleport(player.vehicle, teleporter.to.surface, final_pos)
                        if vehicle.type == "car" then vehicle.speed = speed end
                    else
                        safe_teleport(player, teleporter.to.surface, final_pos)
                    end
                    player.play_sound{path = "dw-teleport"}
                    goto continue
                end
                ::continue_teleport::
            end
        end

        ::continue::
    end
end

--- Make sure that dead player on any old surface is moved to the new surface
local function dead_on_previous_surface(event)
    local player = game.players[event.player_index]
    if not dw.has_warp_ctx(player.force.name) then return end
    local ctx = dw.warp_ctx(player.force.name)
    if ctx.warp.current.name and player.surface.name ~= ctx.warp.current.name then
        player.teleport({0, 0}, ctx.warp.current.name)
    end
end


--- make sure new players are teleported to the new surface
local function teleport_safely_player_on_event(event)
    local player = game.players[event.player_index]

    --- make sure to teleport any new player to the current warp surface
    if dw.has_warp_ctx(player.force.name) then
        local ctx = dw.warp_ctx(player.force.name)
        if ctx.nauvis_lab_exploded and ctx.warp.current.surface then
            if not dw.safe_surfaces[player.surface.name] then
                safe_teleport(player, ctx.warp.current.surface, {0, 0}, true)
            end
        end
    end
end



dw.register_event(defines.events.on_player_died, dead_on_previous_surface)
dw.register_event(defines.events.on_player_created, teleport_safely_player_on_event)
dw.register_event(defines.events.on_player_joined_game, teleport_safely_player_on_event)
dw.register_event('on_nth_tick_6', check_player_teleport)
