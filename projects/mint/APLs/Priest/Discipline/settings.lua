local unlocker,
---@class mint
mint,
addon = ...

local Interface = mint.Interface

addon.priest.settings["Discipline"] = {
    OOCCasts = false,
}

----------------------------
--- Constants/Locals
----------------------------

----------------------------
--- Interface Page
----------------------------

Interface:AddQuickButton("Ability_priest_atonement", "OOCAtonement", "OOC Casts", function()
    addon.priest.settings["Discipline"].OOCCasts = not addon.priest.settings["Discipline"].OOCCasts

    if addon.priest.settings["Discipline"].OOCCasts then
        mint:Log("Will now maintain atonement and PW:S on friends outside of combat.")
    else
        mint:Log("Will no longer maintain atonement and PW:S on friends outside of combat.")
    end
end)



local settings = mint.Settings
local disc_page = addon.priest.discipline:GetUI()

local defaults = {
	ooc_renew_mana = 80,
	healthstone_pct = 40,
	healthpot_pct = 35
}

disc_page:AddDefaults(defaults)

addon.priest.settings["Discipline"] = {
	page = {
		layoutConfig = { padding = { top = 15 } },
		database = settings.profile.priest.discipline,
		rows = {
			{
				header = {
					type = 'header',
					label = 'Discipline Priest'
				}
			},
			{
                margins = {
                    margin = { top = 20 },
                    order = 0,
                },
				ooc_renew_mana = {
					key = 'ooc_renew_mana',
					type = 'slider',
					label = 'OOC Renew Mana %',
					precision = 1,
					min = 5,
					max = 100,
					column = 8,
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
		},
	}
}

disc_page:AddLayout(addon.priest.settings["Discipline"].page)