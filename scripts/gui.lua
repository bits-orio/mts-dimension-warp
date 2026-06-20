--- Everything related to DW GUI is here.
------------------------------------------------------------
-- v1 CORE port: the warp frame is now PER-TEAM. Every read of warp/timer/votes
-- state (and the planet selector) is threaded through ctx -- the
-- storage.teams[force_name] bundle from scripts/warp_ctx.lua -- so each player
-- sees their OWN team's warp state. A player's team is their force; their ctx is
-- dw.warp_ctx(force.name), resolved ONLY for forces whose name matches ^team%-
-- (see ctx_for_player). Players on the spectator / landing-pen / player force get
-- no ctx, so their warp frame is hidden and blank -- we never fabricate a bogus
-- context for a non-team force.
--
-- EXPECTED stale (out of slice 5 scope): the item-watcher container frame and its
-- helpers (get_container_frame, get_or_create_item_selector, update_watchdog,
-- item_watch_changed, update_watchdogs_gui) still read the flat storage.gui seeds.
-- That is an aux subsystem (fed by misc.lua, also flat) and must NOT be ported here.
dw.gui = dw.gui or {}

-- Resolve the warp context for the player's OWN team, or nil if the player is not
-- on a team force. Guarded so we never lazily create a bogus ctx for the
-- spectator / landing-pen / player force: only ^team%- forces get a context.
local function ctx_for_player(player)
    local force_name = player.force.name
    if not force_name:find('^team%-') then return nil end
    return dw.warp_ctx(force_name)
end

-- Like ctx_for_player but SPECTATOR-AWARE: resolves the player's REAL team (via
-- dw.effective_force / mts-v1), so a member spectating another team still maps to
-- their own team's ctx. Used by the dock prompt path so a returning member who
-- spectates can still see the prompt and resume.
local function effective_team_ctx(player)
    local fn = dw.effective_force(player)
    if fn and dw.has_warp_ctx(fn) then return dw.warp_ctx(fn) end
    return nil
end

local function get_player_gui_settings(player)
    local player_settings = settings.get_player_settings(player)
    return {
        highlight_change = player_settings['dw-gui-highlight-qty-change'].value --[[@as boolean]],
        default_color = player_settings['dw-gui-default-color'].value --[[@as string]],
        increase_color = player_settings['dw-gui-increase-qty-color'].value --[[@as string]],
        decrease_color = player_settings['dw-gui-decrease-qty-color'].value --[[@as string]],
        delimiter = player_settings['dw-gui-thousand-delimiter'].value --[[@as string]],
        info_planet = player_settings['dw-gui-info-planet'].value --[[@as boolean]],
        info_dimension = player_settings['dw-gui-info-dimension'].value --[[@as boolean]],
        info_planet_clock = player_settings['dw-gui-info-planet-clock'].value --[[@as boolean]],
        info_evolution = player_settings['dw-gui-info-evolution'].value --[[@as boolean]],
        info_warp_timer = player_settings['dw-gui-info-warp-timer'].value --[[@as boolean]],
        info_manual_timer = player_settings['dw-gui-info-manual-warp-timer'].value --[[@as boolean]],
        planet_selector = player_settings['dw-gui-planet-selector'].value --[[@as boolean]],
    }
end

local function set_warp_toggle_buttons(player)
    local buttonflow = mod_gui.get_button_flow(player)
    local warp_toggle = buttonflow.warp_toggle or buttonflow.add({type = "sprite-button", name = "warp_toggle", sprite = "warp-toggle-icon"})
    local container_toggle = buttonflow.container_toggle or buttonflow.add({type = "sprite-button", name = "container_toggle", sprite = "warp-toggle-container-icon"})
    warp_toggle.visible = true
    warp_toggle.tooltip = {"dw-messages.gui-button-tooltip"}
    container_toggle.visible = true
    container_toggle.tooltip = {"dw-messages.gui-watchitem-tooltip"}
end
dw.gui.set_warp_toggle_buttons = set_warp_toggle_buttons

local function get_warp_frame(player)
    local frameflow = mod_gui.get_frame_flow(player)
    local dw_frame = frameflow.dw_frame or frameflow.add({type = "flow", name = "dw_frame", direction = "vertical"})
    local warp_frame = dw_frame.warp_frame or dw_frame.add({type = "flow", name = "warp_frame", direction = "vertical"})
    warp_frame.visible = warp_frame.visible or false
    warp_frame.style.padding = {5, 0, 0, 5}

    -- A player not on a team force has no warp state: hide the whole warp frame
    -- and stop -- never build/refresh per-team widgets without a context.
    local ctx = ctx_for_player(player)
    if not ctx then
        warp_frame.visible = false
        return warp_frame
    end

    local surfaceflow = warp_frame.surface or warp_frame.add{type = "label", name = "surface", caption = {"dw-gui.planet", "nauvis", "Nauvis", "normal"}}
    local dimensionflow = warp_frame.dimension or warp_frame.add{type = "label", name = "dimension", caption = {"dw-gui.dimension", "1"}}
    local surface_time = warp_frame.surface_time or warp_frame.add{type = "label", name = "surface_time", caption = {"dw-gui.planet_clock", "0"}}
    local surface_evolution = warp_frame.surface_evolution or warp_frame.add{type = "label", name = "surface_evolution", caption = {"dw-gui.planet_evolution", "0"}}
    local warpflow = warp_frame.warp_timer or warp_frame.add{type = "label", name = "warp_timer", caption = {"dw-gui.autowarp_timer", "0"}}
    local manualwarpflow = warp_frame.warp_timer_manual or warp_frame.add{type = "label", name = "warp_timer_manual", caption = {"dw-gui.manualwarp_timer", "0"}}
    local destination_flow = warp_frame.destination_flow or warp_frame.add{type = "flow", name = "destination_flow", direction = "horizontal"}
    local warp_button = warp_frame.warp_button or warp_frame.add{type="button", name="warp_button", caption={"dw-gui.warp-button"}, style = "confirm_button"}

    -- preferred destination selector buttons
    local preferred_dest_label = destination_flow.label or destination_flow.add{type="label", name="label", caption={"dw-gui.preferred-destination"}}
    local destination_list = {
        none = destination_flow['preferred-none'] or destination_flow.add{type="sprite-button", name="preferred-none", sprite="virtual-signal.signal-deny", auto_toggle=true, toggled=true},
    }
    destination_list.none.style.width = 25
    destination_list.none.style.height = 25
    destination_list.none.style.padding = 0
    destination_list.none.style.margin = 0
    ctx.gui.planet_selector_list["preferred-none"] = true

    for _, planet in pairs(game.planets) do
        if not utils.ignore_planet(planet.name) and player.force.is_space_location_unlocked(planet.name) then
            destination_list["preferred-" .. planet.name] = destination_flow["preferred-" .. planet.name] or destination_flow.add{type="sprite-button", name="preferred-" .. planet.name, sprite="space-location." .. planet.name, tooltip = {"space-location-name." .. planet.name}, auto_toggle=true}
            destination_list["preferred-" .. planet.name].style.width = 25
            destination_list["preferred-" .. planet.name].style.height = 25
            destination_list["preferred-" .. planet.name].style.padding = 0
            destination_list["preferred-" .. planet.name].style.margin = 0
            ctx.gui.planet_selector_list["preferred-" .. planet.name] = true
        end
    end

    -- nauvis_lab_exploded is set per-team by mts_lifecycle warp #0 adoption (the
    -- flat storage.nauvis_lab_exploded is NEVER set -- lab_intro is disabled -- so
    -- gating on it would keep the whole info GUI hidden forever).
    local player_gui_settings = get_player_gui_settings(player)
    surfaceflow.visible = player_gui_settings.info_planet and (ctx.nauvis_lab_exploded or false)
    dimensionflow.visible = player_gui_settings.info_dimension and (ctx.nauvis_lab_exploded or false)
    surface_time.visible = player_gui_settings.info_planet_clock and (ctx.nauvis_lab_exploded or false)
    surface_evolution.visible = player_gui_settings.info_evolution and (ctx.nauvis_lab_exploded or false)
    warpflow.visible = player_gui_settings.info_warp_timer and ctx.timer.active and not ctx.victory
    manualwarpflow.visible = player_gui_settings.info_manual_timer and ctx.timer.active
    destination_flow.visible = player_gui_settings.planet_selector and ctx.gui.planet_selector_enabled
    warp_button.visible = ctx.timer.active

    return warp_frame
end
dw.gui.get_warp_frame = get_warp_frame

-- ctx is the player's team warp context; the watched item for this slot lives in
-- ctx.gui.item_watch (per-team), matching the producer in misc.lua.
local function get_or_create_item_selector(player, ctx, frame, name)
    local flow = frame[name] or frame.add({type = "flow", name = name, direction = "horizontal"})

    local item_button = flow.item or flow.add{type="choose-elem-button", name="item", elem_type="item-with-quality"}
    item_button.elem_value = ctx.gui.item_watch[name]

    local item_count = flow.count or flow.add{type="label", name="count", caption = "0"}

    item_button.style.width = 25
    item_button.style.height = 25
    item_button.style.padding = 0
    item_button.style.margin = 0
    item_button.visible = true
    item_count.visible = true
    item_count.style.height = 25
    item_count.style.width = 80
    item_count.style.right_padding = 5
    item_count.style.vertical_align = "center"
    item_count.style.horizontal_align = "right"
    item_count.style.font_color = util.color(get_player_gui_settings(player).default_color)
    item_count.style.hovered_font_color  = util.color("#C4E9FF")

    return flow
end

local function get_container_frame(player)
    local frameflow = mod_gui.get_frame_flow(player)
    local dw_frame = frameflow.dw_frame or frameflow.add({type = "flow", name = "dw_frame", direction = "vertical"})
    local container_frame = dw_frame.container_frame or dw_frame.add({type = "frame", name = "container_frame", direction = "vertical", visible = false, style="dw_frame"})
    container_frame.visible = container_frame.visible or false
    container_frame.style.margin = {5, 0, 0, 5}

    -- A player not on a team force watches no items: hide the frame and stop, so we
    -- never build per-team watchdog rows without a context.
    local ctx = ctx_for_player(player)
    if not ctx then
        container_frame.visible = false
        return container_frame
    end

    if not container_frame.header_label then container_frame.add{type = "label", name = "header_label", caption = {"dw-gui.item-watch"}} end
    if not container_frame.header_line then container_frame.add{type = "line", name = "header_line"} end

    local item_table = container_frame.item_table or container_frame.add({type = "table", name = "item_table", column_count = 3})
    if not container_frame.footer_line then container_frame.add{type = "line", name = "footer_line"} end

    -- Watchdogs + watched items are this team's (ctx.gui), populated by misc.lua.
    for watchdog, _ in pairs(ctx.gui.watchdogs) do
        local item = ctx.gui.item_watch['watch-item-' .. watchdog]

        -- if we have an item watched, but not existing (mod change) remove the watchdog
        if item and not prototypes.item[item.name] then
            dw.gui.update_watchdog(ctx, 'watch-item-' .. watchdog, nil)
            container_frame.item_table['watch-item-' .. watchdog].destroy()
        else
            get_or_create_item_selector(player, ctx, item_table, 'watch-item-' .. watchdog)
        end
    end

    return container_frame
end
dw.gui.get_container_frame = get_container_frame

-- Single global handler: iterate connected players and refresh each one's vote
-- button against their OWN team's ctx.votes/timer. Non-team players have no warp
-- frame (get_warp_frame returns it hidden, without a warp_button), so skip them.
local function update_manual_warp_button()
    for _, player in pairs(game.connected_players) do
        local ctx = ctx_for_player(player)
        if not ctx then goto continue end

        local frame = get_warp_frame(player)
        local button = frame.warp_button
        button.visible = ctx.timer.active

        -- Docked (#3a): the base is parked in space and frozen. The only way out
        -- is the dock-resume prompt, so the regular warp vote button is shown but
        -- disabled with a "Docked -- resume" caption until the resume completes
        -- (which clears ctx.warp.docked and restores the normal captions below).
        if ctx.warp.docked then
            button.caption = {"dw-gui.warp-button-docked"}
            button.enabled = false
            goto continue
        end

        if ctx.votes.count >= ctx.votes.min_vote then
            button.caption = {"dw-gui.warp-button-warping"}
            button.enabled = false
        else
            if ctx.votes.count > 0 then
                if ctx.votes.players[player.index] then
                    button.caption = {"dw-gui.warp-button-wait", ctx.votes.count, ctx.votes.min_vote}
                    button.enabled = false
                else
                    button.caption = {"dw-gui.warp-button-warp", ctx.votes.count, ctx.votes.min_vote}
                    button.enabled = true
                end
            else
                button.caption = {"dw-gui.warp-button"}
                button.enabled = true
            end
        end

        ::continue::
    end
end
dw.gui.update_manual_warp_button = update_manual_warp_button

-- Sync the preferred-destination toggle for every player ON THE SAME TEAM whose
-- ctx.warp.preferred_destination just changed. Other teams' selectors are
-- independent and must not be touched.
local function update_preferred_destination(force_name, previous_destination, current_destination)
    for _, player in pairs(game.connected_players) do
        if player.force.name ~= force_name then goto continue end

        local frame = get_warp_frame(player)
        local previous_button = frame.destination_flow["preferred-" .. previous_destination]
        if previous_button then
            previous_button.toggled = false
        end
        local current_button = frame.destination_flow["preferred-" .. current_destination]
        if current_button then
            current_button.toggled = true
        end

        ::continue::
    end
end

local function warp_frame_click(event)
    local player = game.players[event.player_index]
    local button = event.element
    if button.name == "warp_toggle" then
        local frame = get_warp_frame(player)
        frame.visible = not frame.visible
    end

    -- Vote / preferred-destination both mutate the CLICKING player's team ctx.
    -- A non-team player can't have these buttons (their warp frame is hidden), so
    -- guarding here is belt-and-suspenders against a stray click event.
    if button.name == "warp_button" then
        local ctx = ctx_for_player(player)
        -- Vote guard (#3b): a docked team can only leave via dock-resume, so a
        -- stray warp-vote click (e.g. a queued click landing as the dock opens)
        -- must not register a vote. The button itself is disabled while docked;
        -- this guards the event path too.
        if ctx and not ctx.warp.docked then
            ctx.votes.count = ctx.votes.count + 1
            ctx.votes.players[event.player_index] = true
            update_manual_warp_button()
        end
    end

    if button.name == "dw_dock_resume" then
        local ctx = effective_team_ctx(player)
        if ctx and ctx.warp.docked and not ctx.warp.resume_chosen then
            ctx.warp.resume_chosen = true
            dw.diag("dock resume chosen via GUI: player=%s team=%s", player.name, dw.effective_force(player))
        end
    end

    if button.name == "container_toggle" then
        local frame = get_container_frame(player)
        frame.visible = not frame.visible
    end

    if button.name:match('^preferred%-') then
        local ctx = ctx_for_player(player)
        if ctx then
            local planet_name = button.name:sub(11)
            local previous = ctx.warp.preferred_destination or "none"
            if button.toggled then
                ctx.warp.preferred_destination = planet_name
            else
                ctx.warp.preferred_destination = nil
            end
            update_preferred_destination(player.force.name, previous, ctx.warp.preferred_destination or "none")
        end
    end
end

--- Update the item watcher list, and the watchdogs if needed. Operates on the
--- given team's context (ctx.gui), so each team's watch list is independent.
---@param ctx table the team's warp context (storage.teams[force_name] bundle)
---@param name string the watchdog item index
---@param item PrototypeWithQuality|nil the item to watch or nil to remove the watch
---@return boolean true if a watchdog has been removed, false otherwise
local function update_watchdog(ctx, name, item)
    local remove_watchdog = false
    -- add the item to the watchlist, or remove it if required
    if item then
        -- add the item to the watchlist, only increase the counter if the watcher didn't have any item yet
        if not ctx.gui.item_watch[name] then
            ctx.gui.count_watched_item = ctx.gui.count_watched_item + 1
        end
        ctx.gui.item_watch[name] = item

        -- add a watchdog for an item
        if ctx.gui.count_watched_item == ctx.gui.count_watchdogs then
            ctx.gui.count_watchdogs = ctx.gui.count_watchdogs + 1
            ctx.gui.watchdogs[game.tick] = true
        end

    else
        -- remove the watched item based on the watchdog name
        if ctx.gui.item_watch[name] then
            ctx.gui.item_watch[name] = nil
            ctx.gui.count_watched_item = ctx.gui.count_watched_item - 1

            -- if we have more than 3 watchdogs, and more than 1 empty, remove the one we unset
            if ctx.gui.count_watchdogs > 3 and (ctx.gui.count_watchdogs - ctx.gui.count_watched_item) > 1  then
                local watchdog = tonumber(name:match('watch%-item%-(%d+)'))
                if watchdog then
                    ctx.gui.watchdogs[watchdog] = nil
                    ctx.gui.count_watchdogs = ctx.gui.count_watchdogs - 1
                    remove_watchdog = true
                end
            end
        end
    end

    return remove_watchdog
end
dw.gui.update_watchdog = update_watchdog

---Event fired when player change an item in the item watcher. The watch list is
---per-team, so the change applies to the CLICKING player's team and is mirrored to
---every connected teammate's container frame only.
---@param event EventData.on_gui_elem_changed
local function item_watch_changed(event)
    local elem = event.element
    local name = elem.parent.name
    local item = elem.elem_value --[[@as PrototypeWithQuality]]

    if not name or not name:match('watch%-item%-%d+') then return end

    -- The watcher row only exists on a team player's container frame, so a non-team
    -- force can't reach here -- guard anyway so a stray event can't fabricate a ctx.
    local clicker = game.players[event.player_index]
    local ctx = ctx_for_player(clicker)
    if not ctx then return end

    local remove_watchdog = update_watchdog(ctx, name, item)

    -- update UI for every connected teammate (same team -> same watch list)
    for _, player in pairs(game.connected_players) do
        if player.force.name ~= clicker.force.name then goto continue end

        local frame = get_container_frame(player)
        frame.item_table[name].item.elem_value = item
        frame.item_table[name].count.caption = "0"

        if not item and remove_watchdog then
            frame.item_table[name].destroy()
        end

        ::continue::
    end
end

--- Update the watchdogs labels to display the actual item quantity. Single global
--- handler: each connected player's labels reflect their OWN team's ctx.gui counts
--- (item_watch + item_list, written by misc.lua). Non-team players are skipped.
local function update_watchdogs_gui()
    for _, player in pairs(game.connected_players) do
        local ctx = ctx_for_player(player)
        if not ctx then goto continue end

        local player_gui_settings = get_player_gui_settings(player)

        for watchdog, item in pairs(ctx.gui.item_watch) do
            local item_quantity = ctx.gui.item_list[item.name .. '-' .. item.quality]
            -- Skip until misc.lua has populated this item's running totals (it is a
            -- {qty, prev} table; absent until counted).
            if type(item_quantity) ~= "table" then goto continue_watchdog end

            local frameflow = mod_gui.get_frame_flow(player)
            -- A container frame can exist WITHOUT its item_table: get_container_frame
            -- returns early (before adding item_table) for a player who had no team
            -- ctx, e.g. mid death/respawn. (Re)build defensively, then bail on this
            -- watchdog if the cell still isn't there rather than indexing a nil.
            local frame = frameflow.dw_frame and frameflow.dw_frame.container_frame
            if not (frame and frame.item_table and frame.item_table[watchdog]
                    and frame.item_table[watchdog].count) then
                frame = get_container_frame(player)
            end
            local count = frame and frame.item_table and frame.item_table[watchdog]
                and frame.item_table[watchdog].count
            if not count then goto continue_watchdog end

            local item_variation = item_quantity.qty - item_quantity.prev
            count.tooltip = nil
            if player_gui_settings.highlight_change then
                local color = util.color(player_gui_settings.default_color)
                if item_variation > 0 then
                    color = util.color(player_gui_settings.increase_color)
                elseif item_variation < 0 then
                    color = util.color(player_gui_settings.decrease_color)
                end
                count.style.font_color = color
                count.tooltip = (item_variation ~= 0 and {"dw-gui.item-variation", item_variation} or nil)
            end

            -- starting 1million, we don't display the exact value anymore.
            if item_quantity.qty >= 1000000 then
                count.caption = util.format_number(item_quantity.qty, true)
            else
                count.caption = utils.format_thousands(item_quantity.qty, player_gui_settings.delimiter)
            end
            ::continue_watchdog::
        end

        ::continue::
    end
end
dw.gui.update_watchdogs_gui = update_watchdogs_gui

---Call by all init method to create the user GUI.
---@param player LuaPlayer
local function prepare_warp_gui(player)
    set_warp_toggle_buttons(player)
    get_warp_frame(player)
    get_container_frame(player)
end

local function on_init(event)
    for _, player in pairs(game.players) do
        prepare_warp_gui(player)
    end
end

local function on_player_created(event)
    local player = game.players[event.player_index]
    prepare_warp_gui(player)
end

------------------------------------------------------------
--- P2 docking bay resume prompt (ADR-0006)
------------------------------------------------------------
-- A centered prompt shown to an online member of a DOCKED team. Clicking
-- "Resume warp" sets ctx.warp.resume_chosen, which dock_timer (warp.lua) acts on
-- to thaw power and warp the parked base out. Shown/hidden each second from
-- update() and immediately on join.
local DOCK_PROMPT = "dw_dock_prompt"

local function hide_dock_prompt(player)
    local f = player.gui.screen[DOCK_PROMPT]
    if f then f.destroy() end
end
dw.gui.hide_dock_prompt = hide_dock_prompt

local function show_dock_prompt(player, ctx)
    local screen = player.gui.screen
    local frame = screen[DOCK_PROMPT]
    if not frame then
        frame = screen.add{type = "frame", name = DOCK_PROMPT, direction = "vertical"}
        frame.auto_center = true
        -- Draggable titlebar (title + a draggable filler), matching the project's
        -- other movable windows.
        local titlebar = frame.add{type = "flow", name = "titlebar", direction = "horizontal"}
        titlebar.add{type = "label", style = "frame_title", caption = {"dw-gui.dock-title"}}
        local drag = titlebar.add{type = "empty-widget", name = "drag", style = "draggable_space_header"}
        drag.style.horizontally_stretchable = true
        drag.style.height = 24
        drag.drag_target = frame
        local body = frame.add{type = "label", name = "body", caption = {"dw-gui.dock-body"}}
        body.style.single_line = false
        body.style.maximal_width = 380
        body.style.bottom_padding = 8
        frame.add{type = "button", name = "dw_dock_resume", caption = {"dw-gui.dock-resume"}, style = "confirm_button"}
        frame.add{type = "label", name = "status", caption = ""}
    end
    -- Reflect resume state: once chosen, disable the button and show the countdown.
    if ctx.warp.resume_chosen then
        frame.dw_dock_resume.enabled = false
        local left = ctx.timer.dock
        frame.status.caption = left and {"dw-gui.dock-status-countdown", math.max(0, math.floor(left))}
            or {"dw-gui.dock-status-restoring"}
    else
        frame.dw_dock_resume.enabled = true
        frame.status.caption = ""
    end
end
dw.gui.show_dock_prompt = show_dock_prompt

-- Dedicated dock-prompt driver: runs every second REGARDLESS of warp/pause state.
-- The main panel update() is driven by warp_timer, which early-returns for
-- docked/paused teams, so it CANNOT keep the resume countdown current (a solo
-- game would freeze the prompt in its pre-click state). This iterates connected
-- players and resolves each one's REAL team (spectator-aware), so it also reaches
-- a docked team's member who is spectating another team. Show/hide lives here, not
-- in update().
local function dock_prompt_driver()
    for _, player in pairs(game.connected_players) do
        local ctx = effective_team_ctx(player)
        if ctx and ctx.warp.docked then
            show_dock_prompt(player, ctx)
        else
            hide_dock_prompt(player)
        end
    end
end
dw.register_event("on_nth_tick_60", dock_prompt_driver)

--- Update all the GUI information (except items). Single global handler: iterate
--- connected players and refresh each one's warp frame against their OWN team's
--- ctx. Non-team players have no ctx (and a hidden warp frame), so skip them.
local function update()
    for _, player in pairs(game.connected_players) do
        local ctx = ctx_for_player(player)
        if not ctx then goto continue end

        -- Skip until the team's warp #0 surface is adopted. A team is created (force
        -- set, ctx made with the empty warp.current = {} default) a tick or more
        -- before on_team_surface_created fills in current.planet/surface -- and a
        -- player can already resolve to that ctx in that window, so the labels below
        -- would concatenate a nil planet (gui.lua:553 crash).
        if not (ctx.warp.current.planet and ctx.warp.current.surface and ctx.warp.current.surface.valid) then
            goto continue
        end

        local frame = get_warp_frame(player)

        local player_gui_settings = get_player_gui_settings(player)

        frame.surface.visible = player_gui_settings.info_planet and (ctx.nauvis_lab_exploded or false)
        frame.dimension.visible = player_gui_settings.info_dimension and (ctx.nauvis_lab_exploded or false)
        frame.surface_time.visible = player_gui_settings.info_planet_clock and (ctx.nauvis_lab_exploded or false)
        frame.surface_evolution.visible = player_gui_settings.info_evolution and (ctx.nauvis_lab_exploded or false)
        frame.destination_flow.visible = player_gui_settings.planet_selector and ctx.gui.planet_selector_enabled

        frame.surface.caption = {"dw-gui.planet", ctx.warp.current.planet, {"space-location-name." .. ctx.warp.current.planet}, ctx.warp.randomizer or "normal"}
        -- Display the dimension as number + 1 to match original DW: DW's on_init
        -- ran one generate_surface (bumping its stored number 0 -> 1) before the
        -- panel showed, so its home platform read "Dimension 1". MDW adopts warp
        -- #0 and KEEPS the stored number at 0 (it feeds the deterministic fairness
        -- seed -- mutating it would re-roll every team's warp sequence). So the +1
        -- is display-only: home = "Dimension 1", first warp = "Dimension 2", ...
        frame.dimension.caption = {"dw-gui.dimension", ctx.warp.number + 1}
        frame.surface_evolution.caption = {"dw-gui.planet_evolution", string.format("%.2f", game.forces.enemy.get_evolution_factor(ctx.warp.current.surface) * 100)}
        frame.surface_time.caption = {"dw-gui.planet_clock", utils.format_time(game.tick/60 - ctx.warp.time/60)}

        if ctx.timer.active then
            if ctx.timer.warp >= 0 then
                frame.warp_timer.visible = player_gui_settings.info_warp_timer
                local timer = utils.format_time(ctx.timer.warp)
                if ctx.timer.warp <= 60 then timer = "[font=default-bold][color=#faf17a]" .. timer .. "[/color][/font]" end
                frame.warp_timer.caption = {"dw-gui.autowarp_timer", timer}
            else
                frame.warp_timer.visible = false
            end
            frame.warp_timer_manual.visible = player_gui_settings.info_manual_timer
            local timer = utils.format_time(ctx.timer.manual_warp)
            if ctx.timer.manual_warp < 10 then timer = "[font=default-bold][color=#faf17a]" .. timer .. "[/color][/font]" end
            frame.warp_timer_manual.caption = {"dw-gui.manualwarp_timer", timer}
        end

        -- (Dock resume prompt is driven separately by dock_prompt_driver, which
        -- runs unconditionally + spectator-aware -- update() is warp_timer-gated.)
        ::continue::
    end
end
dw.gui.update = update

-- Show the dock prompt the instant a member returns to a docked team (update()
-- also covers it within a second, but this avoids the visible delay).
local function on_player_joined(event)
    local player = game.players[event.player_index]
    if not (player and player.valid) then return end
    local ctx = effective_team_ctx(player)
    if ctx and ctx.warp.docked then
        show_dock_prompt(player, ctx)
    end
end

dw.register_event('on_init', on_init)
dw.register_event('on_configuration_changed', on_init)
dw.register_event(defines.events.on_player_created, on_player_created)
dw.register_event(defines.events.on_player_joined_game, on_player_joined)
dw.register_event(defines.events.on_gui_click, warp_frame_click)
dw.register_event(defines.events.on_gui_elem_changed, item_watch_changed)