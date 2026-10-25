local unlocker,
---@class mint
mint,
addon = ...

local Interface = mint.Interface

addon.paladin.settings["Holy"] = {
    LoHDelay = false,
}

----------------------------
--- Constants/Locals
----------------------------

----------------------------
--- Interface Page
----------------------------

Interface:AddQuickButton("Spell_holy_layonhands", "LayOnHands", "LOH Delay", function()
    addon.paladin.settings["Holy"].LoHDelay = not addon.paladin.settings["Holy"].LoHDelay

    if addon.paladin.settings["Holy"].LoHDelay then
        mint:Log("Lay on Hands will now be delayed 0.5~ seconds before use.")
    else
        mint:Log("Lay on Hands will now be used instantly.")
    end
end)



local settings = mint.Settings
local holy_page = addon.paladin.holy:GetUI()

local defaults = {
	loh_toggle = false,
	loh_pct = 20,
	auto_hoj = true,
	bos_toggle = false,
	bos_pct = 35,
	summer_heal_spam = true,
	summer_on_cd = false,
	auto_lod = false,
	holy_shock_dps = false,
	hold_hs_charge = false,
	healthstone_pct = 40,
	healthpot_pct = 35,
	healing_buffer = 10,
	judge_mana = 80,
	beacon_buffer = 10
}

holy_page:AddDefaults(defaults)

addon.paladin.settings["Holy"] = {
	page = {
		layoutConfig = { padding = { top = 15 } },
		database = settings.profile.paladin.holy,
		rows = {
			{
				header = {
					type = 'header',
					label = 'Holy Paladin'
				}
			},
			{
                margins = {
                    margin = { top = 10 },
                    order = 0,
                },
				loh_toggle = {
					key = 'loh_toggle',
					type = 'checkbox',
					label = 'Lay on Hands',
					tooltip = 'Enable Lay on Hands usage.',
					column = 3,
					order = 1
				},
				loh_pct = {
					key = 'loh_pct',
					type = 'slider',
					label = 'Lay on Hands HP',
					precision = 1,
					min = 5,
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
				bos_toggle = {
					key = 'bos_toggle',
					type = 'checkbox',
					label = 'Blessing of Sacrifice',
					tooltip = 'Enable Blessing of Sacrifice usage.',
					column = 3,
					order = 1
				},
				bos_pct = {
					key = 'bos_pct',
					type = 'slider',
					label = 'Blessing of Sacrifice HP',
					precision = 1,
					min = 5,
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
				auto_hoj = {
					key = 'auto_hoj',
					type = 'checkbox',
					label = 'Hammer of Justice',
					tooltip = 'Enable Hammer of Justice usage for interrupts.',
					column = 6,
					order = 1
				},
			},
			{
				margins = {
					margin = { top = 10 },
					order = 0,
				},
				summer_on_cd = {
					key = 'summer_on_cd',
					type = 'checkbox',
					label = 'Blessing of Summer on CD',
					tooltip = "Don't hold Blessing of Summer for Avenging Wrath.",
					column = 6,
					order = 1
				},
			},
			{
				margins = {
					margin = { top = 10 },
					order = 0,
				},
				summer_heal_spam = {
					key = 'summer_heal_spam',
					type = 'checkbox',
					label = 'Summer Heal Spam',
					tooltip = 'Enable heal spam during Blessing of Summer to maximize damage (at the cost of mana and HP).',
					column = 6,
					order = 1
				},
			},
			{
				margins = {
					margin = { top = 10 },
					order = 0,
				},
				auto_lod = {
					key = 'auto_lod',
					type = 'checkbox',
					label = 'Use LoD in Raid',
					tooltip = 'Enable Light of Dawn usage in raid.',
					column = 6,
					order = 1
				},
			},
			{
				margins = {
					margin = { top = 10 },
					order = 0,
				},
				hold_hs_charge = {
					key = 'hold_hs_charge',
					type = 'checkbox',
					label = 'Hold Holy Shock Charge in Raid',
					tooltip = 'Prefer to use holy shock for healing over damage.',
					column = 6,
					order = 1
				},
			},
			{
				margins = {
					margin = { top = 10 },
					order = 0,
				},
				holy_shock_dps = {
					key = 'holy_shock_dps',
					type = 'checkbox',
					label = 'Use Holy Shock for DPS in raid',
					tooltip = 'Use Holy Shock for DPS in raid',
					column = 6,
					order = 1
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
			{
				margins = {
					margin = { top = 10 },
					order = 0,
				},
				healing_buffer = {
					key = 'healing_buffer',
					type = 'slider',
					label = 'Healing Buffer',
					precision = 0,
					min = 0,
					max = 30,
					column = 9,
					order = 2
				},
			},
			{
				margins = {
					margin = { top = 10 },
					order = 0,
				},
				judge_mana = {
					key = 'judge_mana',
					type = 'slider',
					label = 'Judgment Mana (Raid)',
					precision = 0,
					min = 0,
					max = 100,
					column = 9,
					order = 2
				}
			},
			{
				margins = {
					margin = { top = 10 },
					order = 0,
				},
				beacon_buffer = {
					key = 'beacon_buffer',
					type = 'slider',
					label = '[Raid] Beacon of Virtue Buffer',
					precision = 0,
					min = 0,
					max = 30,
					column = 9,
					order = 2
				},
			},
		},
	}
}

holy_page:AddLayout(addon.paladin.settings["Holy"].page)