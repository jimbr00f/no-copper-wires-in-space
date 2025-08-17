data:extend({
    {
		type = "bool-setting",
		name = "grid-enforcer-enable-planner",
		order = "g-e-e-p",
		setting_type = "startup",
		default_value = false,
	},
	{
		type = "bool-setting",
		name = "grid-enforcer-no-clean-on-remove",
		order = "g-e-n-c-o-r",
		setting_type = "runtime-global",
		default_value = false
	},
	{
		type = "bool-setting",
		name = "grid-enforcer-remove-copper-wires-in-space",
		order = "g-e-n-w",
		setting_type = "runtime-global",
		default_value = false
	}
})