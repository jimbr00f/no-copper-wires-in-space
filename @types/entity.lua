---@class PoleCleanupRequest
---@field entity LuaEntity
---@field is_selection boolean
---@field alt_mode boolean
---@field search_direction defines.direction?

---@class CleanupParams : PoleCleanupRequest
---@field entity LuaEntity
---@field connector LuaWireConnector
---@field origin MapPosition
---@field length number
---@field width number

---@enum quality_level
quality_level = {
    normal = 1 --[[@as quality_level.normal]],
    uncommon = 2 --[[@as quality_level.uncommon`]],
    epic = 3 --[[@as quality_level.epic`]],
    legendary = 5 --[[@as quality_level.legendary`]],
}

---@alias PoleQualityWireLengthMap table<quality_level, number>
---@alias PoleWireLengthMap table<string, PoleQualityWireLengthMap>
---@alias PoleWidthMap table<string, number>
---@alias PoleCleanupRequestQueue table<uint64, PoleCleanupRequest>

---@class SearchParams
---@field axis string
---@field key integer
---@field multiplier number

---@enum box_corner
box_corner = {
    lt = 'left_top' --[[@as box_corner.lt]],
    rb = 'right_bottom' --[[@as box_corner.rb`]],
}

---@alias SearchQueue table<defines.direction, SearchParams>