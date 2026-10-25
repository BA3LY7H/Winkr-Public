local unlocker, mint, addon = ...

local Settings = mint.Settings
local settings_page = addon.evoker.preservation:GetUI()

local defaults = {
    -- Healing Thresholds
    echo_threshold = 95,
    reversion_threshold = 98,
    verdant_embrace_threshold = 75,
    emerald_blossom_threshold = 85,
    dream_breath_threshold = 85,
    rewind_threshold = 40,
    living_flame_threshold = 90,

    
    -- Automatic Cooldowns
    auto_rewind = true,
    auto_blessing = true,
}

settings_page:AddDefaults(defaults)

addon.evoker.settings["preservation"] = {
	page = {
		layoutConfig = { padding = { top = 15 } },
		database = Settings.profile.evoker.preservation,
		rows = {
			{
				header = {
					type = 'header',
					label = '|TInterface\\Icons\\spell_evoker_preservation:18:18|t Preservation Evoker'
				}
			},
			{
				echo_threshold = {
					key = 'echo_threshold',
					type = 'slider',
					label = 'Echo HP %',
					min = 50,
					max = 100,
					column = 12,
					order = 1
				},
			},

			{
				reversion_threshold = {
					key = 'reversion_threshold',
					type = 'slider',
					label = 'Reversion HP %',
					min = 50,
					max = 100,
					column = 12,
					order = 3
				},
			},
			{
				verdant_embrace_threshold = {
					key = 'verdant_embrace_threshold',
					type = 'slider',
					label = 'Verdant Embrace HP %',
					min = 20,
					max = 100,
					column = 12,
					order = 5
				},
			},

			{
				emerald_blossom_threshold = {
					key = 'emerald_blossom_threshold',
					type = 'slider',
					label = 'Emerald Blossom HP %',
					min = 20,
					max = 100,
					column = 12,
					order = 7
				},
			},
			{
				dream_breath_threshold = {
					key = 'dream_breath_threshold',
					type = 'slider',
					label = 'Dream Breath HP %',
					min = 10,
					max = 100,
					column = 12,
					order = 9
				},
			},
			{
				living_flame_threshold = {
					key = 'living_flame_threshold',
					type = 'slider',
					label = 'Living Flame HP %',
					min = 10,
					max = 100,
					column = 12,
					order = 11
				},
			},
			{
				rewind_threshold = {
					key = 'rewind_threshold',
					type = 'slider',
					label = 'Rewind HP %',
					min = 5,
					max = 80,
					column = 12,
					order = 13
				},
			},
		},
	}
}

settings_page:AddLayout(addon.evoker.settings["preservation"].page)
