local ID_COPPER = defines.wire_connector_id.pole_copper

---@class QueueItem
---@field entity LuaEntity
---@field bypass_toggle boolean
---@field alt_mode boolean
---@field direction defines.direction?

storage.enforcer = {}

storage.enforcer.wire_lengths = {
  --pole_name = { pole_quality = pole_connect_distance }
}
storage.enforcer.pole_widths = {
  --pole_name = pole_width
}

storage.enforcer.cleanup_queue = {}

storage.enforcer.disabled_forces = {}

local event_filter = {
  {
    filter = "type",
    type = "electric-pole"
  }--[[,-- Nope :(
  {
    filter = "ghost_type",
    type = "electric-pole",
    mode = "or"
  }]]
}

-- These are (most) ways a pole can be created or removed

local events = {
  creation = {
    on_built_entity = true,
    on_robot_built_entity = true,
    script_raised_built = true,
    script_raised_revive = true,
    on_entity_cloned = true
  },
  destruction = {
    on_player_mined_entity = true,
    on_robot_mined_entity = true,
    on_entity_died = true,
    script_raised_destroy = true
  },
  input = {
    ["toggle-grid-enforcer"] = true,
    on_lua_shortcut = true
  },
  selection = {
    on_player_selected_area = true,
    on_player_alt_selected_area = true
  },
  init = {
    on_init = true,
    on_configuration_changed = true
  }
}


local function distance(pos1, pos2)
  return ((pos1.x - pos2.x) ^ 2 + (pos1.y - pos2.y) ^ 2) ^ 0.5
end

local function distance_sort(tbl, origin)
  return table.sort(tbl, function(e1, e2)
    return distance(origin, e1.position) < distance(origin, e2.position)
  end)
end

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

---@class DirectionalSearchParams
---@field axis defines.direction
---@field key integer
---@field multiplier number
local directions = {
  -- which part of area to modify, which subkey, what multiplier
  [defines.direction.north] = {
    axis = defines.direction.northwest,
    key = 2,
    multiplier = -1
  },
  [defines.direction.east] = {
    axis = defines.direction.southeast,
    key = 1,
    multiplier = 1
  },
  [defines.direction.south] = {
    axis = defines.direction.southeast,
    key = 2,
    multiplier = 1
  },
  [defines.direction.west] = {
    axis = defines.direction.northwest,
    key = 1,
    multiplier = -1
  }
}

---@param pole LuaEntity
---@param search_direction? defines.direction
---@param bypass_toggle? boolean
---@param alt_mode? boolean
local function clean_pole(pole, search_direction, bypass_toggle, alt_mode)
  -- wtf factorio
  if pole.type ~= "electric-pole" then
    return
  end

  local origin = pole.position
  local lengths = storage.enforcer.wire_lengths
  local length = lengths[pole.name][pole.quality.name]
  local widths = storage.enforcer.pole_widths
  local width = alt_mode and length or widths[pole.name]
  local loyalty = pole.force.name
  local connector = pole.get_wire_connector(ID_COPPER, true)
  local is_space = pole.surface_index == game.surfaces["space-platform"].index

  if loyalty and storage.enforcer.disabled_forces[loyalty] and not bypass_toggle then
    return
  end

  if not connector then
    log(string.format("pole %s has no connector?", pole))
    return
  end

  -- #OneDirection
  local search_queue = search_direction and {[search_direction] = directions[search_direction]}
  -- No boyband :(
  search_queue = search_queue or directions
  -- Kill connections in our search direction(s)
  if is_space or not search_direction then
    connector.disconnect_all()
    return
  else
    for _, connection in pairs(connector.real_connections) do
      local neighbour_connector = connection.target
      local neighbour = neighbour_connector.owner
      local direction = direction_of(origin, neighbour.position, width, widths[neighbour.name])
      if direction == search_direction and neighbour.type == "electric-pole" then
        connector.disconnect_from(neighbour_connector)
      end
    end
  end

  -- Begin search
  for trace_direction, area_modifier in pairs(search_queue) do
    -- Build our search filter -- area and type filter
    local search_filter = {
      area = {
        [defines.direction.northwest] = {
          origin.x - width,
          origin.y - width
        },
        [defines.direction.southeast] = {
          origin.x + width,
          origin.y + width
        }
      },
      type = "electric-pole",
      force = loyalty
    }
    -- Edit the filter area to cover our desired direction and length
    local point = search_filter.area[area_modifier.axis]
    point[area_modifier.key] = point[area_modifier.key] + length * area_modifier.multiplier
    -- Do our "line" search and sort the result by distance
    local results = pole.surface.find_entities_filtered(search_filter)
    distance_sort(results, origin)
    -- Move in the target direction until we get a successful connection
    for _, target in pairs(results) do
      if pole ~= target then
        if trace_direction == direction_of(origin, target.position, width, widths[target.name]) then
          if connector.connect_to(target.get_wire_connector(ID_COPPER, true)) then
            break
          end
        end
      end
    end
  end

  -- Take our new neighbours and disconnect them from any now-unnecessary connections
  for _, friend_connection in pairs(connector.real_connections) do
    local friend_connector = friend_connection.target
    local friend = friend_connector.owner
    if --[[friend.valid and]] friend.type == "electric-pole" then
      local friend_width = alt_mode and lengths[friend.name][friend.quality.name] or widths[friend.name]
      local friend_pos = friend.position
      -- Kill diagonal connections
      local friend_direction = direction_of(origin, friend_pos, width, friend_width)
      if not friend_direction then
        connector.disconnect_from(friend_connector)
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
          local fof_direction = direction_of(friend_pos, friend_of_friend.position, friend_width, widths[friend_of_friend.name])
          if not fof_direction or found_friends[fof_direction] then
            friend_connector.disconnect_from(neighbour_connectors[friend_of_friend.unit_number])
          else -- This is our closest connection in the given direction
            found_friends[fof_direction] = friend_of_friend
          end
      end
    end
  end
end

local queue_size = 3
script.on_nth_tick(3, function()
  local max_iter = 0
  local key, details = next(storage.enforcer.cleanup_queue)
  -- Empty table. We make this distinction because we want to replace the empty table with {} only when we modify it (instead of every tick)
  if not key or not details then
    return
  end
  repeat
    if details.entity.valid then
      clean_pole(details.entity, details.direction, details.bypass_toggle, details.alt_mode)
      max_iter = max_iter + 1
    end
    storage.enforcer.cleanup_queue[key] = nil
    key, details = next(storage.enforcer.cleanup_queue)
    -- optimize for gc times
    if not key then
      storage.enforcer.cleanup_queue = {}
      break
    end
  until max_iter > queue_size
end)


---@param event EventData.on_built_entity | EventData.on_robot_built_entity | EventData.script_raised_built | EventData.script_raised_revive | EventData.on_entity_cloned | EventData.on_player_mined_entity | EventData.on_robot_mined_entity | EventData.on_entity_died | EventData.script_raised_destroy
local function handle_pole_event(event)
  local is_creation = events.creation[event.name]
  -- Different events use different names for.. reasons?
  local source_pole = event.entity or event.destination
  -- New pole
  if is_creation then
    clean_pole(source_pole)
  elseif not settings.global["grid-enforcer-no-clean-on-remove"].value then -- Handling reconnection logic on pole removal
    local connector = source_pole.get_wire_connector(ID_COPPER, false)
    if not connector then
      return
    end
    local widths = storage.enforcer.pole_widths
    for _, friend_connector in pairs(connector.real_connections) do
      local friend = friend_connector.target.owner
      local friend_direction = direction_of(friend.position, source_pole.position, widths[friend.name], widths[friend.name])
      if friend_direction and friend.type == "electric-pole" then
        storage.enforcer.cleanup_queue[friend.unit_number] = {
          entity = friend,
          direction = friend_direction
        }
      end
    end
  end
end

---@param event EventData.on_player_selected_area | EventData.on_player_alt_selected_area
local function handle_selection_event(event)
  if event.item ~= "invoke-grid-enforcer" then
    return
  end
  local alt_mode = event.name == defines.events["on_player_alt_selected_area"]
  for _, ent in pairs(event.entities) do
    storage.enforcer.cleanup_queue[ent.unit_number] = {
      entity = ent,
      bypass_toggle = true,
      alt_mode = alt_mode
    }
  end
end

local function toggle_shortcut_for_force(event)
  if not events.input[event.prototype_name or event.input_name or ""] then
    return
  end
  local event_player = event.player_index and game.players[event.player_index]
  local event_force = event_player and event_player.force
  local enabled = storage.enforcer.disabled_forces[event_force.name] and true or false
  for _, force_player in pairs(event_force.players) do
    force_player.set_shortcut_toggled("toggle-grid-enforcer", enabled)      
  end
  storage.enforcer.disabled_forces[event_force.name] = not enabled
end

local function re_init(event)
  log("re_init")
  -- Build global state if it doesn't exist (i.e. mod update)
  storage.enforcer = storage.enforcer or {}
  -- Clear cleanup queue
  storage.enforcer.cleanup_queue = {}
  -- Import forces, add any new ones
  storage.enforcer.disabled_forces = storage.enforcer.disabled_forces or {}
  for force_name in pairs(game.forces) do
    storage.enforcer.disabled_forces[force_name] = storage.enforcer.disabled_forces[force_name] or false
  end
  -- On load/change we'll store the pole specs for quick reference
  storage.enforcer.wire_lengths = {}
  storage.enforcer.pole_widths = {}
  for name, proto in pairs(prototypes.get_entity_filtered(event_filter)) do
    storage.enforcer.wire_lengths[name] = {}
    for quality_name in pairs(prototypes.quality) do
      storage.enforcer.wire_lengths[name][quality_name] = proto.get_max_wire_distance(quality_name)
    end
    local selection_box = proto.selection_box
    storage.enforcer.pole_widths[name] = math.max(
      (math.abs(selection_box.left_top.x) + math.abs(selection_box.right_bottom.x)) / 2,
      (math.abs(selection_box.left_top.y) + math.abs(selection_box.right_bottom.y)) / 2
    ) + 0.05
  end
end

local function register_event(event_name, event_func, should_filter)
  -- Strange but whatever
  local event_id = defines.events[event_name] or event_name
  script.on_event(event_id, event_func)
  if should_filter then
    script.set_event_filter(event_id, event_filter)
  end
end

for event_name in pairs(events.creation) do
  -- Because we pass event_id.. sometimes
  events.creation[defines.events[event_name]] = true
  register_event(event_name, handle_pole_event, true)
end
for event_name in pairs(events.destruction) do
  register_event(event_name, handle_pole_event, true)
end
for event_name in pairs(events.input) do
  register_event(event_name, toggle_shortcut_for_force)
end
for event_name in pairs(events.selection) do
  register_event(event_name, handle_selection_event)
end
for event_name in pairs(events.init) do
  script[event_name](re_init)
end

register_event("on_player_created", function(event)
  local player = game.players[event.player_index]
  player.set_shortcut_toggled("toggle-grid-enforcer", not storage.enforcer.disabled_forces[player.force.name])
end)