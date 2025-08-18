local exports = {
    
}

exports.mod = 'noangledcables'
exports.prefix = '__' .. exports.mod .. '__'

exports.ids = { 
    toggle_grid_enforcer = 'toggle-grid-enforcer',
    invoke_grid_enforcer = 'invoke-grid-enforcer',
    no_clean_on_remove = 'grid-enforcer-no-clean-on-remove',
    no_wires_in_space = 'grid-enforcer-no-wires-in-space',
    enable_planner = 'grid-enforcer-enable-planner'
}

---@param path string
---@return string
exports.png = function(path)
    return exports.prefix .. '/graphics/' .. path  .. '.png'
end

return exports