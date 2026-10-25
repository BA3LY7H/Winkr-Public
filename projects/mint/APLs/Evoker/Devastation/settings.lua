local unlocker, mint, addon = ...
local settings = mint.Settings
local settings_page = addon.evoker.devastation:GetUI()

local defaults = {
	engage_only = true,
}

settings_page:AddDefaults(defaults)

addon.evoker.settings["devastation"] = {
	page = {
		layoutConfig = { padding = { top = 15 } },
		database = settings.profile.evoker.devastation,
		rows = {
			{
				header = {
					type = 'header',
					label = '|TInterface\\Icons\\ability_evoker_shatteringstar:18:18|t Devastation Evoker'
				}
			},
			{
                margins = {
                    margin = { top = 20 },
                    order = 0,
                },
				engage_only = {
					key = 'engage_only',
					type = 'checkbox',
					label = 'Only Attack Engaged',
					tooltip = 'If enabled, the rotation will only attack targets that are already in combat with you or your party.',
					column = 3,
					order = 1
				},
			},
		},
	}
}

settings_page:AddLayout(addon.evoker.settings["devastation"].page)
