local unlocker,
---@class mint
mint,
addon = ...

----------------------------
--- Constants/Locals
----------------------------
local Interface = mint.Interface

addon.priest.settings["Shadow"].toggles = {

}

----------------------------
--- Interface Page
----------------------------

local settings = mint.Settings
local settings_page = addon.priest.shadow:GetUI()

local defaults = {
	engage_only = true,
}

settings_page:AddDefaults(defaults)

addon.priest.settings["Shadow"] = {
	page = {
		layoutConfig = { padding = { top = 15 } },
		database = settings.profile.priest.shadow,
		rows = {
			{
				header = {
					type = 'header',
					label = '|TInterface\\Icons\\spell_shadow_shadowwordpain:18:18|t Shadow Priest'
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

settings_page:AddLayout(addon.priest.settings["Shadow"].page)
