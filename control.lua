local common = require 'common'
require '@types/entity'

local ID_COPPER = defines.wire_connector_id.pole_copper
local DEFAULT_EVENT_FILTER = {
    {
        filter = "type",
        type = "electric-pole"
    }
}

---@type SearchQueue
local DEFAULT_SEARCH_QUEUE = {
    -- which part of area to modify, which subkey, what multiplier
    [defines.direction.north] = {
        axis = box_corner.lt,
        key = 2,
        multiplier = -1
    },
    [defines.direction.east] = {
        axis = box_corner.rb,
        key = 1,
        multiplier = 1
    },
    [defines.direction.south] = {
        axis = box_corner.rb,
        key = 2,
        multiplier = 1
    },
    [defines.direction.west] = {
        axis = box_corner.lt,
        key = 1,
        multiplier = -1
    }
}

-- These are (most) ways a pole can be created or removed
local EVENT_HANDLER_MAPPING = {
    creation = {
        defines.events.on_built_entity,
        defines.events.on_robot_built_entity,
        defines.events.on_space_platform_built_entity,
        defines.events.script_raised_built,
        defines.events.script_raised_revive,
        defines.events.on_entity_cloned
    },
    destruction = {
        defines.events.on_player_mined_entity,
        defines.events.on_robot_mined_entity,
        defines.events.on_space_platform_mined_entity,
        defines.events.on_entity_died,
        defines.events.script_raised_destroy
    },
    input = {
        common.ids.toggle_grid_enforcer,
        defines.events.on_lua_shortcut
    },
    selection = {
        defines.events.on_player_selected_area,
        defines.events.on_player_alt_selected_area
    },
    player_setup = {
        defines.events.on_player_created
    }
}

local function initialize_storage()
    game.print('initializing storage')
    -- Build global state if it doesn't exist (i.e. mod update)
    
    -- Clear cleanup queue
    ---@type PoleCleanupRequestQueue
    storage.cleanup_request_queue = {}
    
    -- Import forces, add any new ones
    ---@type table<string, boolean>
    storage.disabled_forces = storage.disabled_forces or {}
    for force_name, _ in pairs(game.forces) do
        storage.disabled_forces[force_name] = storage.disabled_forces[force_name] or false
    end
    
    -- On load/change we'll store the pole specs for quick reference
    ---@type PoleWireLengthMap
    storage.wire_lengths = storage.wire_lengths or {}
    ---@type PoleWidthMap
    storage.pole_widths = storage.pole_widths or {}
    for name, proto in pairs(prototypes.get_entity_filtered(DEFAULT_EVENT_FILTER)) do
        ---@type PoleQualityWireLengthMap
        storage.wire_lengths[name] = {}
        for _, quality in pairs(prototypes.quality) do
            storage.wire_lengths[name][quality.level] = proto.get_max_wire_distance(quality)
        end
        local selection_box = proto.selection_box
        storage.pole_widths[name] = math.max(
        (math.abs(selection_box.left_top.x) + math.abs(selection_box.right_bottom.x)) / 2,
        (math.abs(selection_box.left_top.y) + math.abs(selection_box.right_bottom.y)) / 2
    ) + 0.05
    end
end

---@param pos1 MapPosition
---@param pos2 MapPosition
---@return number
local function distance(pos1, pos2)
    return ((pos1.x - pos2.x) ^ 2 + (pos1.y - pos2.y) ^ 2) ^ 0.5
end

---@param tbl LuaEntity[]
---@param origin MapPosition
local function distance_sort(tbl, origin)
    table.sort(tbl, function(e1, e2)
        return distance(origin, e1.position) < distance(origin, e2.position)
    end)
end

---@param origin MapPosition
---@param pos MapPosition
---@param widthA number
---@param widthB number
---@return defines.direction?
local function direction_of(origin, pos, widthA, widthB)
    local width = widthA ~= widthB and math.max(widthA or 0.5, widthB or 0.5) or 1
    local h_distance = math.abs(origin.x - pos.x)
    local v_distance = math.abs(origin.y - pos.y)
    if h_distance == 0 and v_distance == 0 then -- Both axes same
        return nil
    elseif h_distance < width and h_distance < v_distance then -- Y axis different, <= prefs n/s connections over e/w
        return origin.y > pos.y and defines.direction.north or defines.direction.south
    elseif v_distance < width and v_distance < h_distance then -- X axis different
        return origin.x > pos.x and defines.direction.west or defines.direction.east
    end
    return nil
end

---@param pole LuaEntity
---@return boolean
local function should_disconnect_for_space(pole)
    local is_setting_enabled = settings.global[common.ids.no_wires_in_space].value
    local is_pole_in_space = pole.surface.platform ~= nil
    return is_setting_enabled and is_pole_in_space
end

---@param pole LuaEntity
---@param is_selection boolean
---@return boolean
local function should_disconnect_for_force(pole, is_selection)
    return is_selection or not storage.disabled_forces[pole.force.name]
end

---@param params CleanupParams
local function disconnect_search_neighbors(params)
    for _, connection in pairs(params.connector.real_connections) do
        local neighbour_connector = connection.target
        local neighbour = neighbour_connector.owner
        local direction = direction_of(params.origin, neighbour.position, params.width, storage.pole_widths[neighbour.name])
        if direction == params.search_direction and neighbour.type == "electric-pole" then
            params.connector.disconnect_from(neighbour_connector)
        end
    end
end


---@param params CleanupParams
---@param search_queue SearchQueue
local function reconnect_closest_neighbors(params, search_queue)
    -- Begin search
    for trace_direction, area_modifier in pairs(search_queue) do
        -- Build our search filter -- area and type filter
        ---@type EntitySearchFilters
        local search_filter = {
            area = {
                left_top = {
                    params.origin.x - params.width,
                    params.origin.y - params.width
                },
                right_bottom = {
                    params.origin.x + params.width,
                    params.origin.y + params.width
                }
            },
            type = "electric-pole",
            force = params.entity.force.name
        }
        -- Edit the filter area to cover our desired direction and length
        local point = search_filter.area[area_modifier.axis]
        point[area_modifier.key] = point[area_modifier.key] + params.length * area_modifier.multiplier
        -- Do our "line" search and sort the result by distance
        local results = params.entity.surface.find_entities_filtered(search_filter)
        distance_sort(results, params.origin)
        -- Move in the target direction until we get a successful connection
        for _, target in pairs(results) do
            if params.entity ~= target then
                if trace_direction == direction_of(params.origin, target.position, params.width, storage.pole_widths[target.name]) then
                    if params.connector.connect_to(target.get_wire_connector(ID_COPPER, true)) then
                        break
                    end
                end
            end
        end
    end
end

---@param pole LuaEntity
---@param alt_mode boolean
---@return number
local function get_pole_width(pole, alt_mode)
    if alt_mode then
        return storage.wire_lengths[pole.name][pole.quality.level --[[@as quality_level]]]
    else
        return storage.pole_widths[pole.name]
    end
end

---@param params CleanupParams
local function cleanup_obsolete_connections(params)
    -- Take our new neighbours and disconnect them from any now-unnecessary connections
    for _, friend_connection in pairs(params.connector.real_connections) do
        local friend_connector = friend_connection.target
        local friend = friend_connector.owner
        if --[[friend.valid and]] friend.type == "electric-pole" then
            local friend_width = get_pole_width(friend, params.alt_mode)
            local friend_pos = friend.position
            -- Kill diagonal connections
            local friend_direction = direction_of(params.origin, friend_pos, params.width, friend_width)
            if not friend_direction then
                params.connector.disconnect_from(friend_connector)
            end
            -- Since we're iterating anyway, let's cache the connectors
            local neighbour_connectors = {}
            local sorted_neighbours = {}
            for _, fof_connection in pairs(friend_connector.real_connections) do
                local fof_connector = fof_connection.target
                local owner = fof_connector.owner
                if --[[owner.valid and]] owner.type == "electric-pole" then
                    sorted_neighbours[#sorted_neighbours+1] = owner
                    neighbour_connectors[owner.unit_number] = fof_connector
                end
            end
            -- Sort so we can iterate in order
            distance_sort(sorted_neighbours, friend_pos)
            -- kill any but the closest in each direction
            local found_friends = {
                [defines.direction.north] = false,
                [defines.direction.east] = false,
                [defines.direction.south] = false,
                [defines.direction.west] = false
            }
            for _, friend_of_friend in pairs(sorted_neighbours) do
                local fof_direction = direction_of(friend_pos, friend_of_friend.position, friend_width, storage.pole_widths[friend_of_friend.name])
                if not fof_direction or found_friends[fof_direction] then
                    friend_connector.disconnect_from(neighbour_connectors[friend_of_friend.unit_number])
                else -- This is our closest connection in the given direction
                    found_friends[fof_direction] = friend_of_friend
                end
            end
        end
    end
end

---@param pole LuaEntity
---@param search_direction defines.direction?
---@param alt_mode boolean?
---@return CleanupParams?
function get_cleanup_params(pole, search_direction, alt_mode)
    local length = storage.wire_lengths[pole.name][pole.quality.level --[[@as quality_level]]]
    local width = storage.pole_widths[pole.name]
    if alt_mode then width = length end
    ---@type CleanupParams
    local params = {
        entity = pole,
        connector = pole.get_wire_connector(ID_COPPER, true),
        search_direction = search_direction,
        alt_mode = alt_mode or false,
        origin = pole.position,
        length = length,
        width = width 
    }
    if not params.connector then return nil end
    return params
end

---@param pole LuaEntity
---@param search_direction? defines.direction
---@param is_selection? boolean
---@param alt_mode? boolean
local function cleanup_pole(pole, search_direction, is_selection, alt_mode)
    if pole.type ~= "electric-pole" then
        return
    end
    
    if not alt_mode then alt_mode = false end
    
    local params = get_cleanup_params(pole, search_direction, alt_mode)
    if not params then
        log(string.format("pole %s has no connector?", pole))
        return
    end
    
    if not should_disconnect_for_force(pole, is_selection or false) then
        return
    end
    
    local disconnect_space = should_disconnect_for_space(pole)
    if disconnect_space or not search_direction then
        params.connector.disconnect_all()
    else
        disconnect_search_neighbors(params)
    end
    if disconnect_space then
        return
    end
    ---@type SearchQueue
    local search_queue = DEFAULT_SEARCH_QUEUE
    if search_direction then search_queue = {[search_direction] = DEFAULT_SEARCH_QUEUE[search_direction]} end
    reconnect_closest_neighbors(params, search_queue)
    cleanup_obsolete_connections(params)
end

local queue_size = 3
script.on_nth_tick(3, function()
    local max_iter = 0
    local key, details = next(storage.cleanup_request_queue)
    -- Empty table. We make this distinction because we want to replace the empty table with {} only when we modify it (instead of every tick)
    if not key or not details then
        return
    end
    repeat
        if details.entity.valid then
            cleanup_pole(details.entity, details.search_direction, details.is_selection, details.alt_mode)
            max_iter = max_iter + 1
        end
        storage.cleanup_request_queue[key] = nil
        key, details = next(storage.cleanup_request_queue)
        -- optimize for gc times
        if not key then
            storage.cleanup_request_queue = {}
            break
        end
    until max_iter > queue_size
end)


---@param event
---| EventData.on_built_entity
---| EventData.on_robot_built_entity
---| EventData.on_space_platform_built_entity
---| EventData.script_raised_built
---| EventData.script_raised_revive
---| EventData.on_entity_cloned
---| EventData.on_player_mined_entity
---| EventData.on_robot_mined_entity
---| EventData.on_space_platform_mined_entity
---| EventData.on_entity_died
---| EventData.script_raised_destroy
local function handle_pole_event(event)
    local is_creation = EVENT_HANDLER_MAPPING.creation[event.name]
    local source_pole = event.entity or event.destination
    -- New pole
    if is_creation then
        cleanup_pole(source_pole)
    elseif not settings.global['grid-enforcer-no-clean-on-remove'].value then
        local connector = source_pole.get_wire_connector(ID_COPPER, false)
        if not connector then
            return
        end
        local widths = storage.pole_widths
        for _, friend_connector in pairs(connector.real_connections) do
            local friend = friend_connector.target.owner
            local friend_direction = direction_of(friend.position, source_pole.position, widths[friend.name], widths[friend.name])
            if friend_direction and friend.type == "electric-pole" then
                storage.cleanup_request_queue[friend.unit_number] = {
                    entity = friend,
                    search_direction = friend_direction,
                    is_selection = false,
                    alt_mode = false
                }
            end
        end
    end
end

---@param event EventData.on_player_selected_area | EventData.on_player_alt_selected_area
local function handle_selection_event(event)
    if event.item ~= common.ids.invoke_grid_enforcer then
        return
    end
    local alt_mode = event.name == defines.events.on_player_alt_selected_area
    for _, ent in pairs(event.entities) do
        storage.cleanup_request_queue[ent.unit_number] = {
            entity = ent,
            is_selection = true,
            alt_mode = alt_mode
        }
    end
end

---@param event EventData
---@return boolean
local function is_input_event(event)
    for _, event_id in pairs(EVENT_HANDLER_MAPPING.input) do
        if event.name == event_id then return true end
    end
    return false
end

local function toggle_shortcut_for_force(event)
    if not is_input_event(event) then
        return
    end
    local event_player = event.player_index and game.players[event.player_index]
    local event_force = event_player and event_player.force
    local enabled = storage.disabled_forces[event_force.name] and true or false
    for _, force_player in pairs(event_force.players) do
        force_player.set_shortcut_toggled("toggle-grid-enforcer", enabled)      
    end
    storage.disabled_forces[event_force.name] = not enabled
end

---@param event_id LuaEventType ID of the event to filter.
---@param event_handler fun(...)
---@param should_filter? boolean
local function register_event(event_id, event_handler, should_filter)
    script.on_event(event_id, event_handler)
    if should_filter then
        script.set_event_filter(event_id, DEFAULT_EVENT_FILTER)
    end
end

local function handle_player_setup(event)
    local player = game.players[event.player_index]
    player.set_shortcut_toggled(common.ids.toggle_grid_enforcer, not storage.disabled_forces[player.force.name])
end

for _, event_id in pairs(EVENT_HANDLER_MAPPING.creation) do
    -- Because we pass event_id.. sometimes
    register_event(event_id, handle_pole_event, true)
end
for _, event_id in pairs(EVENT_HANDLER_MAPPING.destruction) do
    register_event(event_id, handle_pole_event, true)
end
for _, event_id in pairs(EVENT_HANDLER_MAPPING.input) do
    register_event(event_id, toggle_shortcut_for_force)
end
for _, event_id in pairs(EVENT_HANDLER_MAPPING.selection) do
    register_event(event_id, handle_selection_event)
end
for _, event_id in pairs(EVENT_HANDLER_MAPPING.selection) do
    register_event(event_id, handle_selection_event)
end
for _, event_id in pairs(EVENT_HANDLER_MAPPING.player_setup) do
    register_event(event_id, handle_player_setup)
end

script.on_init(initialize_storage)
script.on_configuration_changed(initialize_storage)