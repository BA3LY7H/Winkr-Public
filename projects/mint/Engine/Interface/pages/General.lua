local unlocker,
---@class mint
mint = ...

----------------------------
--- Constants/Locals
----------------------------
local Constants     = mint.Constants or {}
local settings 		= mint.Settings
---@class Interface
local Interface     = mint.Interface

local general = Interface.Page:NewCustom("General", "general", false)

local defaults = {
	smart_target = true,
	indicator_color = "cyan",
	player_indicator = true,
	indicator_opacity = 80,
	track_players = false,
	tracked_players = {}
}

general:AddDefaults(defaults)

local layout = {
	layoutConfig = { padding = { top = 15 } },
	database = settings.profile.general,
	rows = {
		{
			header = {
				type = 'header',
				label = 'General Settings'
			}
		},
		{
			margins = {
				margin = { top = 10 }
			},
			smart_target = {
				key = 'smart_target',
				type = 'checkbox',
				label = 'Smart Targeting',
				tooltip = 'Automatically select a target when yours dies or does not exist.',
				order = 1
			},
		},
		{
			margins = {
				margin = { top = 15 },
				order = 0,
			},
			player_indicator = {
				key = 'player_indicator',
				type = 'checkbox',
				label = 'Player Indicator',
				tooltip = 'Display an arrow beneath your feet.',
				column = 3,
				order = 1
			},
			indicator_color = {
				key = 'indicator_color',
				label = 'Indicator Color',
				type = 'dropdown',
				options = {
					{ text = '|cff00d8ff Cyan |r',   value = 'cyan' }, -- 00d8ff
					{ text = '|cffffd200 Gold |r',   value = 'gold' }, -- ffd200
					{ text = '|cff00ff12 Lime |r',   value = 'lime' }, -- 00ff12
					{ text = '|cffffffff White |r',  value = 'white' }, -- ffffff
					{ text = '|cffff2114 Red |r',    value = 'red' }, -- ff2114
					{ text = '|cffff8000 Orange |r', value = 'orange' }, -- ff8000
					{ text = '|cfffff809 Yellow |r', value = 'yellow' }, -- fff809
					{ text = '|cffff80ff Pink |r',   value = 'pink' }, -- ff80ff
					{ text = '|cffc845fa Purple |r', value = 'purple' }, -- c845fa
				},
				initialValue = 1,
				column = 5,
				order = 2
			},
			indicator_opacity = {
				key = 'indicator_opacity',
				type = 'slider',
				label = 'Indicator Opacity',
				precision = 1,
				min = 5,
				max = 100,
				column = 4,
				order = 3
			},
		},
		{
			margins = {
				margin = { top = 15 },
				order = 0,
			},
			track_players = {
				key = 'track_players',
				type = 'checkbox',
				label = 'Track Players',
				tooltip = 'Draw a circle around specific players.',
				column = 3,
				order = 1
			},
			tracked_players = {
				key = 'tracked_players',
				label = 'Tracked Players',
				type = 'playerDropdown',
				options = {
					{ }
				},
				multi = true,
				column = 5,
				order = 2
			}
		}
	},
}

general:AddLayout(layout)