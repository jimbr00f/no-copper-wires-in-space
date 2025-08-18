local common = require 'common'
data:extend({
    {
		type = "bool-setting",
		name = common.ids.enable_planner,
		order = "g-e-e-p",
		setting_type = "startup",
		default_value = false,
	},
	{
		type = "bool-setting",
		name = common.ids.no_clean_on_remove,
		order = "g-e-n-c-o-r",
		setting_type = "runtime-global",
		default_value = false
	},
	{
		type = "bool-setting",
		name = common.ids.no_wires_in_space,
		order = "g-e-n-w",
		setting_type = "runtime-global",
		default_value = false
	}
})