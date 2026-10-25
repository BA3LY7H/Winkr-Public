local unlocker,
---@class mint
mint,
addon = ...

local Interface = mint.Interface

addon.paladin.settings["Protection"] = {
    DivineToll = false,
}

----------------------------
--- Constants/Locals
----------------------------

----------------------------
--- Interface Page
----------------------------

Interface:AddQuickButton("Inv_ability_paladin_divinetoll", "DivineToll", "Toll", function()
    addon.paladin.settings["Protection"].DivineToll = not addon.paladin.settings["Protection"].DivineToll

    if addon.paladin.settings["Protection"].DivineToll then
        mint:Log("Divine Toll is now enabled.")
    else
        mint:Log("Divine Toll is now disabled.")
    end
end)

Interface:AddQuickButton("Paladin_retribution", "OOC", "OOC Routine", function()
    addon.paladin.settings["Protection"].OOCRoutine = not addon.paladin.settings["Protection"].OOCRoutine

    if addon.paladin.settings["Protection"].OOCRoutine then
        mint:Log("OOC Routine is now enabled.")
    else
        mint:Log("OOC Routine is now disabled.")
    end
end)

local settings = mint.Settings
local ui_page = addon.paladin.protection:GetUI()

local defaults = {
	loh_toggle = false,
	loh_pct = 20,
	auto_hoj = true,
	offensive_potions = false,
	healthstone_pct = 40,
	healthpot_pct = 35,

	potion_threshold = 30,
	stone_threshold = 60,
	loh_threshold = 18,
	sl_wog_threshold = 50,
	wog_threshold = 30

}

ui_page:AddDefaults(defaults)

addon.paladin.settings["Protection"] = {
	page = {
		layoutConfig = { padding = { top = 15 } },
		database = settings.profile.paladin.protection,
		rows = {
			{
				header = {
					type = 'header',
					label = 'Protection Paladin'
				}
			},
			{
                margins = {
                    margin = { top = 20 },
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
				offensive_potions = {
					key = 'offensive_potions',
					type = 'checkbox',
					label = 'Offensive Potions',
					tooltip = 'Enable offensive potions.',
					column = 6,
					order = 1
				},
			},
			{
                margins = {
                    margin = { top = 25 },
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
				loh_threshold = {
					key = 'loh_threshold',
					type = 'slider',
					label = 'Lay on Hands HP',
					precision = 0,
					min = 0,
					max = 100,
					column = 9,
					order = 2
				},
			},
			{
				margins = {
					margin = { top = 25 },
					order = 0,
				},
				stone_threshold = {
					key = 'stone_threshold',
					type = 'slider',
					label = 'Healthstone HP',
					precision = 0,
					min = 0,
					max = 100,
					column = 9,
					order = 1
				},
			},
			{
				margins = {
					margin = { top = 20 },
					order = 0,
				},
				potion_threshold = {
					key = 'potion_threshold',
					type = 'slider',
					label = 'Health Potion HP',
					precision = 0,
					min = 0,
					max = 100,
					column = 9,
					order = 1
				},
			},
			{
				margins = {
					margin = { top = 20 },
					order = 0,
				},
				sl_wog_threshold = {
					key = 'sl_wog_threshold',
					type = 'slider',
					label = 'SL + WoG HP',
					precision = 0,
					min = 0,
					max = 100,
					column = 9,
					order = 1
				},
			},
			{
				margins = {
					margin = { top = 20 },
					order = 0,
				},
				wog_threshold = {
					key = 'wog_threshold',
					type = 'slider',
					label = 'Natty WoG HP',
					precision = 0,
					min = 0,
					max = 100,
					column = 9,
					order = 1
				},
			},
		},
	}
}

ui_page:AddLayout(addon.paladin.settings["Protection"].page)