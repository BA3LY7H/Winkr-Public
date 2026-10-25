local unlocker,
---@class mint
mint,
addon = ...

local Interface = mint.Interface
local Settings      = mint.Settings

-- Initialize druid.restoration profile if not present
if not Settings.profile.druid then Settings.profile.druid = {} end
if not Settings.profile.druid.restoration then Settings.profile.druid.restoration = {} end
local profile       = Settings.profile.druid.restoration

addon.druid.settings["Restoration"] = {}

----------------------------
--- Constants/Locals
----------------------------

----------------------------
--- Interface Page
----------------------------

local settings = mint.Settings
local resto_page = addon.druid.resto:GetUI()

local defaults = {
	danger_pct = 30,
	aoe_heal_pct = 80
}

resto_page:AddDefaults(defaults)

addon.druid.settings["Restoration"] = {
	page = {
		layoutConfig = { padding = { top = 15 } },
		database = settings.profile.druid.restoration,
		rows = {
			{
				header = {
					type = 'header',
					label = 'Restoration Druid'
				}
			},
			{
				margins = {
					margin = { top = 10 },
					order = 0,
				},
				danger_pct = {
					key = 'danger_pct',
					type = 'slider',
					label = 'Danger HP',
					precision = 1,
					min = 5,
					max = 100,
					column = 9,
					order = 5
				},
			},
			{
				margins = {
					margin = { top = 10 },
					order = 0,
				},
				aoe_heal_pct = {
					key = 'aoe_heal_pct',
					type = 'slider',
					label = 'AoE HP',
					precision = 1,
					min = 5,
					max = 100,
					column = 9,
					order = 6
				},
			},
		},
	}
}

resto_page:AddLayout(addon.druid.settings["Restoration"].page)