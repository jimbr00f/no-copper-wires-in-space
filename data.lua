local common = require 'common'
local base_sprite = {
    icon = "__core__/graphics/icons/tooltips/tooltip-category-equipment-grid-electricity.png",
    icon_size = 40,
    scale = 1,
    tint = {r = 0, g = 0, b = 0, a = 1}
}

data:extend({
    {
        name = common.ids.toggle_grid_enforcer,
        associated_control_input = common.ids.toggle_grid_enforcer,
        type = "shortcut",
        action = "lua",
        toggleable = true,
        icons = {base_sprite},
        small_icons = {base_sprite}
    },
    {
        name = common.ids.toggle_grid_enforcer,
        type = "custom-input",
        key_sequence = "",
        action = "lua"
    }
})

if settings.startup["grid-enforcer-enable-planner"].value == false then
    return
end

data:extend({
    {
        name = "invoke-grid-enforcer",
        associated_control_input = "invoke-grid-enforcer",
        type = "shortcut",
        action = "spawn-item",
        item_to_spawn = "invoke-grid-enforcer",
        style = "default",
        icons = {{
            icon = "__noangledcables__/graphics/invoke-grid-enforcer.png",
            icon_size = 32,
            tint = {29, 28, 29}
        }},
        small_icons = {{
            icon = "__noangledcables__/graphics/invoke-grid-enforcer-x24.png",
            icon_size = 24,
            tint = {29, 28, 29}
        }}
    },
    {
        name = "invoke-grid-enforcer",
        type = "custom-input",
        key_sequence = "",
        action = "spawn-item",
        item_to_spawn = "invoke-grid-enforcer"
    },
    {
        name = "invoke-grid-enforcer",
        type = "selection-tool",
        icons = {{
            icon = "__noangledcables__/graphics/invoke-grid-enforcer.png",
            icon_size = 32,
            tint = {0.98, 0.66, 0.22}
        }},
        stack_size = 1,
        hidden = true,
        flags = {"not-stackable", "only-in-cursor", "spawnable"},
        select = {
            border_color = {0.98, 0.66, 0.22},-------------------
            cursor_box_type = "electricity",
            mode = {"buildable-type", "same-force"},
            entity_type_filters = {"electric-pole"}
        },
        alt_select = {
            border_color = {34, 181, 255, 128},
            cursor_box_type = "electricity",
            mode = {"buildable-type", "same-force"},
            entity_type_filters = {"electric-pole"}
        }
    }
})