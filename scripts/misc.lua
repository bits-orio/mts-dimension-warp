--- Misc helpers: starter cheat bag + watchdog item counting.
------------------------------------------------------------
-- v1 CORE port: both features are now PER-TEAM. A player's team is their force
-- (player.force.name); their warp context is dw.warp_ctx(force_name). The cheat
-- bag is recorded per team in ctx.cheat_bag, and item counting iterates only the
-- surfaces that team owns (via the dw.surface_owner reverse map) and writes into
-- that team's ctx.gui.item_list.
--
-- Non-team players (spectator / landing-pen / player force) have NO team ctx and
-- are skipped: we never create a bogus ctx for a non-team force. Guard every
-- access with force.name:find('^team%-') or dw.has_warp_ctx before warp_ctx.
--
-- EXPECTED stale (until gui.lua is ported): count_stored_items writes the fresh
-- counts into ctx.gui.item_list, but the GUI refresh it calls
-- (dw.gui.update_watchdogs_gui) still reads the flat storage.gui globals. That
-- divergence is intentional here -- the same pattern warp.lua's loop uses for its
-- dw.gui.* calls -- and must NOT be "fixed" in this slice.

-- True only for real team forces (team-<n>). Spectator/landing-pen/player forces
-- never own a warp ctx, so resolving one for them would create a bogus bundle.
local function is_team_force(force_name)
    return force_name:find('^team%-') ~= nil
end

---Grant the helper items in the beginning of the game, so it's easier for player
---@param event EventData.on_player_changed_position
local function check_cheat_bag(event)
    if not settings.global['dw-helper-starter-item'].value then return end

    local player = game.players[event.player_index]

    -- The cheat bag belongs to the player's TEAM. A player not on a team force
    -- (spectator / landing pen) gets no bag and no ctx is created for them.
    if not is_team_force(player.force.name) then return end
    local ctx = dw.warp_ctx(player.force.name)

    if player.surface.name ~= 'nauvis' and not ctx.cheat_bag[player.name] then
        local character = player.character
        if not character then return end

        -- clear armor then replace with a new one
        local armor_inventory = character.get_inventory(defines.inventory.character_armor)
        if not armor_inventory then return end

        -- if something is already in the armor, move it to main inventory, not to break it
        if armor_inventory[1] then
            character.get_main_inventory().insert(armor_inventory[1])
        end
        armor_inventory.clear()

        -- insert the items now
        player.insert{name="power-armor", count = 1}
        player.insert{name="construction-robot", count = 50}
        player.force.create_ghost_on_entity_death = true
        local grid = armor_inventory[1].grid

        if grid then
            if script.active_mods['Krastorio2'] or script.active_mods['Krastorio2-spaced-out'] then
                player.insert{name="kr-fuel", count = 200}
                grid.put({name = "kr-portable-generator-equipment"})
                grid.put({name = "kr-superior-solar-panel-equipment"})
                grid.put({name = "kr-superior-solar-panel-equipment"})
                grid.put({name = "kr-superior-solar-panel-equipment"})
            else
                grid.put({name = "fission-reactor-equipment"})
                grid.put({name = "personal-roboport-mk2-equipment"})
            end
            grid.put({name = "personal-roboport-mk2-equipment"})
            grid.put({name = "battery-mk2-equipment"})
            grid.put({name = "battery-mk2-equipment"})
            grid.put({name = "energy-shield-equipment"})

            -- charge everything
            for _, equipment in ipairs(grid.equipment) do
                if equipment.max_shield > 0 then
                    equipment.shield = equipment.max_shield
                elseif equipment.max_energy > 0 then
                    equipment.energy = equipment.max_energy
                end
            end
        end
        ctx.cheat_bag[player.name] = true
    end
end

---Count items from all chests (non logistic) in a given surface into the team's
---watch list. Filters by the team's force so only that team's chests are counted.
---@param ctx table the team's warp context (storage.teams[force_name] bundle)
---@param force LuaForce the team's force, used to filter chests
---@param surface LuaSurface
---@param area ?BoundingBox
local function count_chest_items(ctx, force, surface, area)
    if not (surface and surface.valid) then return end
    local chests
    if area then
        chests = surface.find_entities_filtered{area=area, type={"container", "logistic-container", "cargo-landing-pad"}, force=force}
    else
        chests = surface.find_entities_filtered{type={"container", "logistic-container", "cargo-landing-pad"}, force=force}
    end
    for _, chest in pairs(chests) do
        for _, item_qty in pairs(ctx.gui.item_list) do
            item_qty.qty = item_qty.qty + chest.get_item_count(item_qty.item)
        end
    end
end

---Count all the items a team watches to update its watch GUI.
---Runs once per team via register_team_tick; iterates the surfaces that team owns
---through the dw.surface_owner reverse map. The team's own warp (current) surface
---is restricted to the platform area so wild chests off the platform are ignored;
---every other team surface (factory/mining/power dimensions) is counted in full.
---@param force_name string the team's force name
---@param ctx table the team's warp context
local function count_stored_items(force_name, ctx)
    if not ctx.nauvis_lab_exploded then return end

    -- init the list (seed prev from the team's previous counts)
    local item_list = {}
    for _, item in pairs(ctx.gui.item_watch) do
        local index = item.name .. '-' .. item.quality
        if not item_list[index] then
            item_list[index] = {
                item = item,
                qty = 0,
                prev = (ctx.gui.item_list[index] and ctx.gui.item_list[index].qty or 0)
            }
        end
    end
    ctx.gui.item_list = item_list

    local force = game.forces[force_name]
    if not force then return end

    -- Only the platform region of the warp (current) surface counts; the rest of
    -- that surface is the wild planet and must not be tallied.
    local warp_surface = ctx.warp.current.surface
    local warp_area = math2d.bounding_box.create_from_centre({0, 0}, ctx.platform.warp.size, ctx.platform.warp.size)

    -- Walk the reverse map for surfaces this team owns and count each one. The
    -- warp surface uses the platform area; the dimension platforms count in full.
    for surface_index, owner in pairs(storage.surface_index_to_force or {}) do
        if owner == force_name then
            local surface = game.get_surface(surface_index)
            if surface and surface.valid then
                if warp_surface and surface.index == warp_surface.index then
                    count_chest_items(ctx, force, surface, warp_area)
                else
                    count_chest_items(ctx, force, surface)
                end
            end
        end
    end

    -- update GUI
    dw.gui.update_watchdogs_gui()
end

dw.register_event(defines.events.on_player_changed_position, check_cheat_bag)
dw.register_team_tick(300, count_stored_items)
