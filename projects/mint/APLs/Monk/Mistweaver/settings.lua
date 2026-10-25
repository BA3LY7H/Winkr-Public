local unlocker,
---@class mint
mint,
addon = ...

local Interface = mint.Interface
local Settings      = mint.Settings
local profile       = Settings.profile.monk.mistweaver

addon.monk.settings["Mistweaver"] = {
    use_tod = false,
	use_cocoon = false,
}

----------------------------
--- Constants/Locals
----------------------------

----------------------------
--- Interface Page
----------------------------

Interface:AddQuickButton("ability_monk_chicocoon", "ChiCocoon", "Cocoon", function()
    addon.monk.settings["Mistweaver"].use_cocoon = not addon.monk.settings["Mistweaver"].use_cocoon
end)

Interface:AddQuickButton("ability_monk_touchofdeath", "TouchOfDeath", "ToD", function()
	addon.monk.settings["Mistweaver"].use_tod = not addon.monk.settings["Mistweaver"].use_tod
end)



local settings = mint.Settings
local mw_page = addon.monk.mistweaver:GetUI()

local defaults = {
	life_cocoon_delay = false,
	auto_cjl = false,
	auto_leg_sweep = false,
	celestial_conduit = false,
	danger_pct = 30,
	aoe_heal_pct = 80,
	healthstone_pct = 40,
	healthpot_pct = 35
}

mw_page:AddDefaults(defaults)

addon.monk.settings["Mistweaver"] = {
	page = {
		layoutConfig = { padding = { top = 15 } },
		database = settings.profile.monk.mistweaver,
		rows = {
			{
				header = {
					type = 'header',
					label = 'Mistweaver Monk'
				}
			},
			{
                margins = {
                    margin = { top = 10 },
                    order = 0,
                },
				life_cocoon_delay = {
					key = 'life_cocoon_delay',
					type = 'checkbox',
					label = 'Life Cocoon Delay',
					tooltip = 'Enable Life Cocoon Delay.',
					column = 3,
					order = 2
				},
				celestial_conduit = {
					key = 'celestial_conduit',
					type = 'checkbox',
					label = 'Use Celestial Conduit',
					tooltip = 'Enable Celestial Conduit.',
					column = 3,
					order = 2
				},
			},
			{
				margins = {
					margin = { top = 10 },
					order = 0,
				},
				auto_leg_sweep = {
					key = 'auto_leg_sweep',
					type = 'checkbox',
					label = 'Leg Sweep',
					tooltip = 'Enable Automatic Leg Sweep Usage.',
					column = 3,
					order = 3
				},
				auto_cjl = {
					key = 'auto_cjl',
					type = 'checkbox',
					label = 'Crackling Jade Lightning',
					tooltip = 'Enable Automatic CJL Usage.',
					column = 3,
					order = 4
				},
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
			{
				margins = {
					margin = { top = 10 },
					order = 0,
				},
				healthstone_pct = {
					key = 'healthstone_pct',
					type = 'slider',
					label = 'Healthstone HP',
					precision = 1,
					min = 0,
					max = 100,
					column = 9,
					order = 2
				},
			},
			{
				margins = {
					margin = { top = 10 },
					order = 0,
				},
				healthpot_pct = {
					key = 'healthpot_pct',
					type = 'slider',
					label = 'Health Potion HP',
					precision = 1,
					min = 0,
					max = 100,
					column = 9,
					order = 2
				},
			},
		},
	}
}

mw_page:AddLayout(addon.monk.settings["Mistweaver"].page)