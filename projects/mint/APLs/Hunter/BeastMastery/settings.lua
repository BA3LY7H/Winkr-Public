local unlocker, mint, addon = ...

local Interface = mint.Interface

----------------------------
--- Constants/Locals
----------------------------

----------------------------
--- Interface Page
----------------------------

-- Interface:AddQuickButton("Inv_ability_paladin_divinetoll", "DivineToll", "Toll", function()
--     addon.paladin.settings["Protection"].DivineToll = not addon.paladin.settings["Protection"].DivineToll

--     if addon.paladin.settings["Protection"].DivineToll then
--         mint:Log("Divine Toll is now enabled.")
--     else
--         mint:Log("Divine Toll is now disabled.")
--     end
-- end)

local spells = addon.hunter.data.bm.spells
local items = addon.hunter.data.bm.items
local settings = mint.Settings
local ui_page = addon.hunter.bm:GetUI()

local defaults = {
	-- $ General
	openerNotifs = true,
	petIndicator = false,

	-- $ Defensives
	-- Healthstone
	stoneToggle = true,
	stonePct = 60,
	-- Healing Potion
	potionToggle = true,
	potionPct = 30,
	-- Exhilaration
	exhilToggle = true,
	exhilPct = 70,
	-- Fortitude of the Bear
	fotbToggle = true,
	fotbPct = 70,
	-- Survival of the Fittest
	sotfToggle = false,
	sotfPct = 50,

	-- Pet Management
	mendToggle = false,
	mendThreshold = 75,
}

local tankStr = "|TInterface\\LFGFrame\\UI-LFG-ICON-PORTRAITROLES:16:16:0:0:64:64:0:19:22:41|t"
local healStr = "|TInterface\\LFGFrame\\UI-LFG-ICON-PORTRAITROLES:16:16:0:0:64:64:20:39:1:20|t"
local dpsStr = "|TInterface\\LFGFrame\\UI-LFG-ICON-PORTRAITROLES:16:16:0:0:64:64:20:39:22:41|t"
local leaverStr = "|A:groupfinder-icon-leaver:16:16|a"

ui_page:AddDefaults(defaults)

local stdMargin = { top = 20, bottom = 10 }

addon.hunter.settings.beastmastery = {
	page = {
		layoutConfig = { padding = { top = 15 } },
		database = settings.profile.hunter.beastmastery,
		rows = {
			{
				header = {
					type = 'header',
					label = 'Beast Mastery'
				}
			},
			{
				margins = {
                    margin = { top = 15 },
                    order = 0,
                },
			},
			{
				subheader = {
					type = 'subheader',
					label = '|TInterface\\Icons\\ability_hunter_bestialdiscipline:16|t General Settings'
				}
			},
			{
				margins = {
					margin = { top = 10, bottom = 12 },
					order = 0,
				},
				petIndicator = {
					key = 'petIndicator',
					type = 'checkbox',
					label = 'Pet Indicators',
					tooltip = 'Enable indicators under your pet.',
					column = 5,
					order = 1
				},
				openerNotifs = {
					key = 'openerNotifs',
					type = 'checkbox',
					label = 'Opener Notifications',
					tooltip = 'Enable opener state notifications.',
					column = 6,
					order = 2
				},
			},
			{
				subheader = {
					type = 'subheader',
					label = spells.survival_of_the_fittest.iconString() .. ' Defensives'
				}
			},
			{
				margins = {
					margin = stdMargin,
					order = 0,
				},
				stoneToggle = {
					key = 'stoneToggle',
					type = 'checkbox',
					label = items.healthstone.iconString() .. ' Healthstone',
					tooltip = 'Enable Healthstone usage.',
					column = 5,
					order = 1
				},
				stonePct = {
					key = 'stonePct',
					type = 'slider',
					label = items.healthstone.iconString() .. ' Healthstone HP',
					precision = 0,
					min = 0,
					max = 100,
					column = 7,
					order = 2
				},
			},
			{
				margins = {
					margin = stdMargin,
					order = 0,
				},
				potionToggle = {
					key = 'potionToggle',
					type = 'checkbox',
					label = items.healing_potion.iconString() .. ' Health Potion',
					tooltip = 'Enable Healing Potion usage.',
					column = 5,
					order = 1
				},
				potionPct = {
					key = 'potionPct',
					type = 'slider',
					label = items.healing_potion.iconString() .. ' Healing Potion Threshold',
					precision = 0,
					min = 0,
					max = 100,
					column = 7,
					order = 2
				},
			},
			{
				margins = {
					margin = stdMargin,
					order = 0,
				},
				exhilToggle = {
					key = 'exhilToggle',
					type = 'checkbox',
					label = spells.exhilaration.iconString() .. ' Exhilaration',
					tooltip = 'Enable Exhilaration usage.\nAt half of this value, it will be used at\na much higher priority.',
					column = 5,
					order = 1
				},
				exhilPct = {
					key = 'exhilPct',
					type = 'slider',
					label = spells.exhilaration.iconString() .. ' Exhilaration Threshold',
					precision = 0,
					min = 0,
					max = 100,
					column = 7,
					order = 2
				},
			},
			{
				margins = {
					margin = stdMargin,
					order = 0,
				},
				fotbToggle = {
					key = 'fotbToggle',
					type = 'checkbox',
					label = spells.fortitude_of_the_bear.iconString() .. ' Fort. of the Bear',
					tooltip = 'Enable FoTB usage.',
					column = 5,
					order = 1
				},
				fotbPct = {
					key = 'fotbPct',
					type = 'slider',
					label = spells.fortitude_of_the_bear.iconString() .. ' Fortitude of the Bear Threshold',
					precision = 0,
					min = 0,
					max = 100,
					column = 7,
					order = 2
				},
			},
			{
				margins = {
					margin = stdMargin,
					order = 0,
				},
				sotfToggle = {
					key = 'sotfToggle',
					type = 'checkbox',
					label = spells.survival_of_the_fittest.iconString() .. ' Survival of the Fittest',
					tooltip = 'Enable Survival of the Fittest usage.',
					column = 5,
					order = 1
				},
				sotfPct = {
					key = 'sotfPct',
					type = 'slider',
					label = spells.survival_of_the_fittest.iconString() .. ' Survival of the Fittest Threshold',
					precision = 0,
					min = 0,
					max = 100,
					column = 7,
					order = 2
				},
			},
			{
				subheader = {
					type = 'subheader',
					label = spells.mend_pet.iconString() .. ' Pet Management'
				}
			},
			{
				margins = {
					margin = stdMargin,
					order = 0,
				},
				mendToggle = {
					key = 'mendToggle',
					type = 'checkbox',
					label = 'Mend Pet',
					tooltip = 'Enable Mend Pet usage.',
					column = 5,
					order = 1
				},
				mendThreshold = {
					key = 'mendThreshold',
					type = 'slider',
					label = 'Mend Pet %',
					precision = 0,
					min = 0,
					max = 100,
					column = 7,
					order = 2
				},
			},
			-- {
			-- 	subheader = {
			-- 		type = 'subheader',
			-- 		label = spells.exhilaration.iconString() .. ' Exhilaration'
			-- 	}
			-- },
			-- {
			-- 	subheader = {
			-- 		type = 'subheader',
			-- 		label = spells.fortitude_of_the_bear.iconString() .. ' Fortitude of the Bear'
			-- 	}
			-- },
			-- {
			-- 	margins = {
			-- 		margin = { top = 25, bottom = 10 },
			-- 		order = 0,
			-- 	},
			-- 	fortThreshold = {
			-- 		key = 'fortThreshold',
			-- 		type = 'slider',
			-- 		label = 'FoTB Threshold',
			-- 		precision = 0,
			-- 		min = 0,
			-- 		max = 100,
			-- 		column = 7,
			-- 		order = 1
			-- 	},
			-- 	fortDanger = {
			-- 		key = 'fortDanger',
			-- 		type = 'slider',
			-- 		label = leaverStr .. ' Emergency FoTB Threshold',
			-- 		precision = 0,
			-- 		min = 0,
			-- 		max = 100,
			-- 		column = 7,
			-- 		order = 2
			-- 	},
			-- },
		},
	}
}

ui_page:AddLayout(addon.hunter.settings.beastmastery.page)