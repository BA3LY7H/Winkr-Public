local unlocker,
---@class mint
mint,
addon = ...

----------------------------
--- Constants/Locals
----------------------------
local Interface = mint.Interface

addon.deathknight.settings["Unholy"].toggles = {

}

local settings = mint.Settings
local settings_page = addon.deathknight.unholy:GetUI()

local defaults = {
    -- Cooldowns
	auto_aotd = true,
    auto_dt = true,
    auto_putrefy = true,
	abom_toggle = false,
	cd_ttd = 18,
    -- Stops
    blind_toggle = true,
    stun_toggle = true,
    grip_stop = true,
    -- Defensives
	ams_toggle = true,
	lichborne_toggle = true,
	ibf_toggle = true,
	advance_toggle = true,
	death_strike = true,
	ds_pct = 35,
}

settings_page:AddDefaults(defaults)

addon.deathknight.settings["Unholy"] = {
	page = {
		layoutConfig = { padding = { top = 15 } },
		database = settings.profile.deathknight.unholy,
		rows = {
			{
				header = {
					type = 'header',
					label = '|TInterface\\Icons\\spell_deathknight_unholypresence:18:18|t Unholy Death Knight'
				}
			},
			{
				margins = {
                    margin = { top = 10 },
                    order = 0,
                },
				stop_label = {
					type = 'label',
					label = '|TInterface\\Icons\\Ability_maldraxxus_deathknight:18:18|t Cooldowns',
					size = 13,
					order = 1,
				}
			},
			{
				auto_aotd = {
					key = 'auto_aotd',
					type = 'checkbox',
					label = 'Army of the Dead',
					tooltip = 'Automatically use Army of the Dead on bosses.',
					column = 3,
					order = 1
				},
				auto_dt = {
					key = 'auto_dt',
					type = 'checkbox',
					label = 'Dark Transformation',
					tooltip = 'Automatically use Dark Transformation.',
					column = 3,
					order = 2
				},
				auto_putrefy = {
					key = 'auto_putrefy',
					type = 'checkbox',
					label = 'Putrefy',
					tooltip = 'Automatically use Putrefy.',
					column = 4,
					order = 3
				},
			},
            {
                abom_toggle = {
					key = 'abom_toggle',
					type = 'checkbox',
					label = 'Abomination Limb',
					tooltip = 'Automatically use Abomination Limb.',
					column = 3,
					order = 1
				},
				cd_ttd = {
					key = 'cd_ttd',
					type = 'slider',
					label = 'CD Time To Die',
					precision = 0,
					min = 5,
					max = 45,
					column = 6,
					order = 2
				},
            },
			{
				margins = {
                    margin = { top = 10 },
                    order = 0,
                },
				stop_label = {
					type = 'label',
					label = '|TInterface\\Icons\\Spell_deathknight_mindfreeze:18:18|t Stops',
					size = 13,
					order = 1,
				}
			},
			{
				blind_toggle = {
					key = 'blind_toggle',
					type = 'checkbox',
					label = 'Blinding Sleet',
					tooltip = 'Automatically use Blinding Sleet.',
					column = 3,
					order = 1
				},
				stun_toggle = {
					key = 'stun_toggle',
					type = 'checkbox',
					label = 'Asphyxiate',
					tooltip = 'Automatically use Asphyxiate.',
					column = 3,
					order = 2
				},
				grip_stop = {
					key = 'grip_stop',
					type = 'checkbox',
					label = 'Death Grip',
					tooltip = 'Use Death Grip to stop casts.',
					column = 5,
					order = 3
				},
			},
			{
				margins = {
                    margin = { top = 10 },
                    order = 0,
                },
				stop_label = {
					type = 'label',
					label = '|TInterface\\Icons\\Spell_deathknight_iceboundfortitude:18:18|t Defensives',
					size = 13,
					order = 1,
				}
			},
			{
				ams_toggle = {
					key = 'ams_toggle',
					type = 'checkbox',
					label = 'Anti-Magic Shell',
					tooltip = 'Automatically use AMS.',
					column = 3,
					order = 1
				},
				death_strike = {
					key = 'death_strike',
					type = 'checkbox',
					label = 'Death Strike',
					tooltip = 'Automatically use Death Strike.',
					column = 3,
					order = 2
				},
				ds_pct = {
					key = 'ds_pct',
					type = 'slider',
					label = 'Death Strike HP',
					precision = 0,
					min = 5,
					max = 100,
					column = 6,
					order = 3
				},
			},
			{
				advance_toggle = {
					key = 'advance_toggle',
					type = 'checkbox',
					label = 'Death\'s Advance',
					tooltip = 'Automatically use Death\'s Advance.',
					column = 3,
					order = 1
				},
				lichborne_toggle = {
					key = 'lichborne_toggle',
					type = 'checkbox',
					label = 'Lichborne',
					tooltip = 'Automatically use Lichborne.',
					column = 3,
					order = 2
				},
				ibf_toggle = {
					key = 'ibf_toggle',
					type = 'checkbox',
					label = 'Icebound Fortitude',
					tooltip = 'Automatically use Icebound Fortitude.',
					column = 5,
					order = 3
				},
			},
		},
	}
}

settings_page:AddLayout(addon.deathknight.settings["Unholy"].page)
