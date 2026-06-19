local allowed_shortcuts = {
    ["warp-gate-shortcut"] = true,
    ["harvester-left-shortcut"] = true,
    ["harvester-right-shortcut"] = true
}

---@param event EventData.on_lua_shortcut
local function dw_shortcuts(event)
    local player = game.players[event.player_index]
    local shortcut = event.prototype_name

    if not allowed_shortcuts[shortcut] then return end
    if player.controller_type ~= defines.controllers.character then return end

    -- Resolve the player's team (spectator-aware) so the shortcut hands out THAT
    -- team's current gate/harvester item. No team -> nothing to give.
    local force_name = dw.effective_force(player)
    if not (force_name and dw.has_warp_ctx(force_name)) then return end
    local ctx = dw.warp_ctx(force_name)

    -- if the player already has one, we remove it, otherwise we put it in the hands
    local item_match = ""
    local item_name = nil

    if shortcut == "warp-gate-shortcut" then
        item_match = "mobile%-gate%-%d+"
        item_name = ctx.warpgate.mobile_type
    end

    if shortcut == "harvester-left-shortcut" then
        item_match = "harvester%-left%-grid%-%d+"
        item_name = ctx.harvesters.left.mobile_name
    end

    if shortcut == "harvester-right-shortcut" then
        item_match = "harvester%-right%-grid%-%d+"
        item_name = ctx.harvesters.right.mobile_name
    end

    if player.cursor_stack and player.cursor_stack.valid_for_read and player.cursor_stack.name:match(item_match) then
        player.cursor_stack.clear()
    else
        if not item_name then return end
        player.cursor_stack.set_stack({name = item_name, count = 1})

        -- find the same item in inventory, if it exists remove it from the slot
        -- and set the one in hand to be from there.
        -- this allows clearing inventory if you already have some.
        local inventory = player.get_main_inventory()
        if inventory then
            local item_stack, index = inventory.find_item_stack(item_name)
            if item_stack then
                player.get_main_inventory()[index].clear()
                player.hand_location = {
                    inventory = defines.inventory.character_main,
                    slot = index,
                }
            end
        end
    end
end

dw.register_event(defines.events.on_lua_shortcut, dw_shortcuts)