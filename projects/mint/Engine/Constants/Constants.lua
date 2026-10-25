local unlocker,
---@class mint
mint = ...

---@class Constants
---@field ActionBarButtonNames string[]
---@field MapActionBarToBinding table<string, string>
---@field KeybindTargetDescriptions table<string, string>
---@field QuickbarIconsByClass table
---@field ClassDispelMap table
---@field DispelList List
local Constants = {}
Constants.__index = Constants

----------------------------
--- UI Stylesheet
----------------------------

local classRGB = {
    ["DEATHKNIGHT"]  = { 0.77, 0.12, 0.23 },
    ["DEMONHUNTER"]  = { 0.64, 0.19, 0.79 },
    ["DRUID"]        = { 1.00, 0.49, 0.04 },
    ["EVOKER"]       = { 0.20, 0.58, 0.50 },
    ["HUNTER"]       = { 0.67, 0.83, 0.45 },
    ["MAGE"]         = { 0.25, 0.78, 0.92 },
    ["MONK"]         = { 0.00, 1.00, 0.60 },
    ["PALADIN"]      = { 0.96, 0.55, 0.73 },
    ["PRIEST"]       = { 1.00, 1.00, 1.00 },
    ["ROGUE"]        = { 1.00, 0.96, 0.41 },
    ["SHAMAN"]       = { 0.00, 0.44, 0.87 },
    ["WARLOCK"]      = { 0.53, 0.53, 0.93 },
    ["WARRIOR"]      = { 0.78, 0.61, 0.43 },
}

local myClass = select(2, UnitClass("player"))
local myColor = classRGB[myClass]

Constants.Stylesheet = {
	font        = {
		family    = "MintFontNormal",
		size      = 10,
		titleSize = 14,
		effect    = 'NONE',
		strata    = 'OVERLAY',
		color     = {
			normal   = { r = 1, g = 0.82, b = 0, a = 1 },
			disabled = { r = 1, g = 1, b = 1, a = 1 },
			header   = { r = 1, g = 0.9, b = 0, a = 1 },
			element  = { r = 1, g = 1, b = 1, a = 1 },
			label    = { r = 1, g = 1, b = 1, a = 1 },
		}
	},

	backdrop    = {
		texture               = [[Interface\Buttons\WHITE8X8]],
		panel                 = {
			r = 0.054,
			g = 0.054,
			b = 0.054,
			a = 0.8
			-- r = 0.054901960784313725,
			-- g = 0.050980392156862744,
			-- b = 0.06666666666666667,
			-- a = 0.9
		},
		slider                = { r = 0.15, g = 0.15, b = 0.15, a = 1 },
		sliderDrag     		  = { r = myColor[1], g = myColor[2], b = myColor[3], a = 1 },

		-- This is unknown atm
		highlight             = { r = 1, g = 0, b = 0, a = 0.5 },
		-- Button and checkbox background
		button                = { r = 0.054, g = 0.054, b = 0.054, a = 0.85 },

		dropdown              = { r = 0.1, g = 0.1, b = 0.1, a = 0.85 },

		-- Selected button
		buttonSelected        = {
			r = 1,
			g = 0.82,
			b = 0,
			a = 0.4
		},
		-- Disabled button, but this isn't used and buttonSelected is used instead
		buttonDisabled        = { r = 1, g = 0, b = 0, a = 1 },

		border                = { r = 0.00, g = 0.00, b = 0.00, a = 1 },
		borderDisabled        = { r = 0.00, g = 0.00, b = 0.00, a = 1 }, -- not used
		borderSelected        = { r = 1, g = 0.82, b = 0, a = 1 }, -- used for selected AND disabled

		-- Used for Checkboxes
		checkedBorderSelected = { r = 1, g = 0.82, b = 0, a = 1 },

		-- Dropdowns
		ddHover               = { r = 0.15, g = 0.15, b = 0.15, a = 0.85 },
		ddBorderHover         = { r = 0.1, g = 0.1, b = 0.1, a = 1 },

	},

	progressBar = {
		color = { r = 1, g = 0.9, b = 0, a = 0.5 },
	},

	-- This is the highlight when you hover over buttons
	-- literally just always use alpha 0 this is cooked
	highlight   = {
		color = { r = 1, g = 0.82, b = 0, a = 0 },
		blank = { r = 0, g = 0, b = 0, a = 0 }
	},

	tables      = {
		hover = { r = 0.15, g = 0.15, b = 0.15, a = 0.85 },
		select = { r = 0.15, g = 0.15, b = 0.15, a = 0.85 },
	},

	dialog      = {
		width  = 400,
		height = 100,
		button = {
			width  = 100,
			height = 20,
			margin = 5
		}
	},

	tooltip     = {
		padding = 10
	}
};

----------------------------
--- Constants/Locals
----------------------------

local Spell     = mint.Spell.New

Constants.ActionBarButtonNames = {
    "ActionButton",
    "MultiBarBottomLeftButton",
    "MultiBarBottomRightButton",
    "MultiBarLeftButton",
    "MultiBarRightButton",
    "MultiBar5Button",
    "MultiBar6Button",
    "MultiBar7Button"
}

Constants.MapActionBarToBinding = {
    ActionButton1 = "ACTIONBUTTON1",
    ActionButton2 = "ACTIONBUTTON2",
    ActionButton3 = "ACTIONBUTTON3",
    ActionButton4 = "ACTIONBUTTON4",
    ActionButton5 = "ACTIONBUTTON5",
    ActionButton6 = "ACTIONBUTTON6",
    ActionButton7 = "ACTIONBUTTON7",
    ActionButton8 = "ACTIONBUTTON8",
    ActionButton9 = "ACTIONBUTTON9",
    ActionButton10 = "ACTIONBUTTON10",
    ActionButton11 = "ACTIONBUTTON11",
    ActionButton12 = "ACTIONBUTTON12",
    MultiBarBottomLeftButton1 = "MULTIACTIONBAR1BUTTON1",
    MultiBarBottomLeftButton2 = "MULTIACTIONBAR1BUTTON2",
    MultiBarBottomLeftButton3 = "MULTIACTIONBAR1BUTTON3",
    MultiBarBottomLeftButton4 = "MULTIACTIONBAR1BUTTON4",
    MultiBarBottomLeftButton5 = "MULTIACTIONBAR1BUTTON5",
    MultiBarBottomLeftButton6 = "MULTIACTIONBAR1BUTTON6",
    MultiBarBottomLeftButton7 = "MULTIACTIONBAR1BUTTON7",
    MultiBarBottomLeftButton8 = "MULTIACTIONBAR1BUTTON8",
    MultiBarBottomLeftButton9 = "MULTIACTIONBAR1BUTTON9",
    MultiBarBottomLeftButton10 = "MULTIACTIONBAR1BUTTON10",
    MultiBarBottomLeftButton11 = "MULTIACTIONBAR1BUTTON11",
    MultiBarBottomLeftButton12 = "MULTIACTIONBAR1BUTTON12",
    MultiBarBottomRightButton1 = "MULTIACTIONBAR2BUTTON1",
    MultiBarBottomRightButton2 = "MULTIACTIONBAR2BUTTON2",
    MultiBarBottomRightButton3 = "MULTIACTIONBAR2BUTTON3",
    MultiBarBottomRightButton4 = "MULTIACTIONBAR2BUTTON4",
    MultiBarBottomRightButton5 = "MULTIACTIONBAR2BUTTON5",
    MultiBarBottomRightButton6 = "MULTIACTIONBAR2BUTTON6",
    MultiBarBottomRightButton7 = "MULTIACTIONBAR2BUTTON7",
    MultiBarBottomRightButton8 = "MULTIACTIONBAR2BUTTON8",
    MultiBarBottomRightButton9 = "MULTIACTIONBAR2BUTTON9",
    MultiBarBottomRightButton10 = "MULTIACTIONBAR2BUTTON10",
    MultiBarBottomRightButton11 = "MULTIACTIONBAR2BUTTON11",
    MultiBarBottomRightButton12 = "MULTIACTIONBAR2BUTTON12",
    MultiBarLeftButton1 = "MULTIACTIONBAR4BUTTON1",
    MultiBarLeftButton2 = "MULTIACTIONBAR4BUTTON2",
    MultiBarLeftButton3 = "MULTIACTIONBAR4BUTTON3",
    MultiBarLeftButton4 = "MULTIACTIONBAR4BUTTON4",
    MultiBarLeftButton5 = "MULTIACTIONBAR4BUTTON5",
    MultiBarLeftButton6 = "MULTIACTIONBAR4BUTTON6",
    MultiBarLeftButton7 = "MULTIACTIONBAR4BUTTON7",
    MultiBarLeftButton8 = "MULTIACTIONBAR4BUTTON8",
    MultiBarLeftButton9 = "MULTIACTIONBAR4BUTTON9",
    MultiBarLeftButton10 = "MULTIACTIONBAR4BUTTON10",
    MultiBarLeftButton11 = "MULTIACTIONBAR4BUTTON11",
    MultiBarLeftButton12 = "MULTIACTIONBAR4BUTTON12",
    MultiBarRightButton1 = "MULTIACTIONBAR3BUTTON1",
    MultiBarRightButton2 = "MULTIACTIONBAR3BUTTON2",
    MultiBarRightButton3 = "MULTIACTIONBAR3BUTTON3",
    MultiBarRightButton4 = "MULTIACTIONBAR3BUTTON4",
    MultiBarRightButton5 = "MULTIACTIONBAR3BUTTON5",
    MultiBarRightButton6 = "MULTIACTIONBAR3BUTTON6",
    MultiBarRightButton7 = "MULTIACTIONBAR3BUTTON7",
    MultiBarRightButton8 = "MULTIACTIONBAR3BUTTON8",
    MultiBarRightButton9 = "MULTIACTIONBAR3BUTTON9",
    MultiBarRightButton10 = "MULTIACTIONBAR3BUTTON10",
    MultiBarRightButton11 = "MULTIACTIONBAR3BUTTON11",
    MultiBarRightButton12 = "MULTIACTIONBAR3BUTTON12"
}

-- Keybind names for keybind tooltip?
Constants.KeybindTargetDescriptions = {
    ["Cursor"] = "Will be cast at your cursor position.",
    ["Mouseover"] = "Will be cast on your mouseover target.",
    ["Target"] = "Will be cast on your current target.",
    ["Focus"] = "Will be cast on your focus target.",
    ["Self"] = "Will be cast on yourself.",
}

-- Icons: CD, Kick, Defensives
Constants.QuickbarIconsByClass = {
    -- Warrior
    [1] = {
        "Ability_warrior_bladestorm", -- Cooldowns
        "Inv_gauntlets_04", -- Kick
        "Ability_warrior_shieldwall", -- Defensives
		false, -- Dispel (Friends)
		false, -- Purge (Enemies)
    },
    -- Paladin
    [2] = {
        "Spell_holy_avenginewrath", -- Cooldowns
        "Spell_holy_rebuke", -- Kick
        "Spell_holy_divineprotection", -- Defensives
		"Spell_holy_renew", -- Dispel (Friends)
		false, -- Purge (Enemies)
    },
    -- Hunter
    [3] = {
        "Ability_druid_ferociousbite", -- Cooldowns
        "Inv_ammo_arrow_03", -- Kick
        "Spell_nature_spiritarmor", -- Defensives
		false, -- Dispel (Friends)
		"Spell_nature_drowsy", -- Purge (Enemies)
    },
    -- Rogue
    [4] = {
        "Spell_shadow_shadowworddominate", -- Cooldowns
        "ability_kick", -- Kick
        "Ability_rogue_feint", -- Defensives
		false, -- Dispel (Friends)
		"Inv_throwingknife_04", -- Purge (Enemies)
    },
    -- Priest
    [5] = {
        "Ability_priest_darkarchangel", -- Cooldowns
        "Spell_shadow_psychicscream", -- Kick
        "Spell_holy_testoffaith", -- Defensives
		"Spell_nature_nullifydisease", -- Dispel (Friends)
		"Spell_holy_dispelmagic", -- Purge (Enemies)
    },
    -- Death Knight
    [6] = {
        "Ability_maldraxxus_deathknight", -- Cooldowns
        "Spell_deathknight_mindfreeze", -- Kick
        "Spell_deathknight_iceboundfortitude", -- Defensives
		false, -- Dispel (Friends)
		false, -- Purge (Enemies)
    },
    -- Shaman
    [7] = {
        "Spell_fire_elementaldevastation", -- Cooldowns
        "Spell_nature_cyclone", -- Kick
        "Ability_shaman_astralshift", -- Defensives
		"Ability_shaman_cleansespirit", -- Dispel (Friends)
		"Spell_nature_purge", -- Purge (Enemies)
    },
    -- Mage
    [8] = {
        "Ability_mage_timewarp", -- Cooldowns
        "Spell_frost_iceshock", -- Kick
        "Spell_fire_bluefire", -- Defensives
		"Spell_nature_removecurse", -- Dispel (Friends)
		"Spell_arcane_arcane02", -- Purge (Enemies)
    },
    -- Warlock
    [9] = {
        "Spell_shadow_summoninfernal", -- Cooldowns
        "Spell_shadow_mindrot", -- Kick
        "Spell_shadow_demonictactics", -- Defensives
		false, -- Dispel (Friends)
		false, -- Purge (Enemies)
    },
    -- Monk
    [10] = {
        "Ability_monk_summontigerstatue", -- Cooldowns
        "Ability_monk_spearhand", -- Kick
        "Ability_monk_touchofkarma", -- Defensives
		"Ability_rogue_imrovedrecuperate", -- Dispel (Friends)
		false, -- Purge (Enemies)
    },
    -- Druid
    [11] = {
        "Spell_druid_incarnation", -- Cooldowns
        IsPlayerSpell(78675) and "Ability_vehicle_sonicshockwave" or "Inv_bone_skull_04", -- Kick
        "Spell_nature_stoneclawtotem", -- Defensives
		"Spell_holy_removecurse", -- Dispel (Friends)
		"Ability_hunter_beastsoothe", -- Purge (Enemies)
    },
    -- Demon Hunter
    [12] = {
        "Ability_demonhunter_metamorphasisdps", -- Cooldowns
        "Ability_demonhunter_consumemagic", -- Kick
        "Ability_demonhunter_blur", -- Defensives
		false, -- Dispel (Friends)
		false, -- Purge (Enemies)
    },
    -- Evoker
    [13] = {
        "Ability_evoker_furyoftheaspects", -- Cooldowns
        "Ability_evoker_quell", -- Kick
        "Inv_artifact_dragonscales", -- Defensives
		"Ability_evoker_fontofmagic_green", -- Dispel (Friends)
		false, -- Purge (Enemies)
    },
}

Constants.ClassIconMap = {
	["deathknight"] = "|TInterface\\Icons\\Spell_deathknight_classicon:30:30:0:0:64:64:4:60:4:60|t",
	["demonhunter"] = "|TInterface\\Icons\\Classicon_demonhunter:30:30:0:0:64:64:4:60:4:60|t",
	["druid"] 		= "|TInterface\\Icons\\Classicon_druid:30:30:0:0:64:64:4:60:4:60|t",
	["evoker"] 		= "|TInterface\\Icons\\Classicon_evoker:30:30:0:0:64:64:4:60:4:60|t",
	["hunter"] 		= "|TInterface\\Icons\\Classicon_hunter:30:30:0:0:64:64:4:60:4:60|t",
	["mage"] 		= "|TInterface\\Icons\\Classicon_mage:30:30:0:0:64:64:4:60:4:60|t",
	["monk"] 		= "|TInterface\\Icons\\Classicon_monk:30:30:0:0:64:64:4:60:4:60|t",
	["paladin"] 	= "|TInterface\\Icons\\Classicon_paladin:30:30:0:0:64:64:4:60:4:60|t",
	["priest"] 		= "|TInterface\\Icons\\Classicon_priest:30:30:0:0:64:64:4:60:4:60|t",
	["rogue"] 		= "|TInterface\\Icons\\Classicon_rogue:30:30:0:0:64:64:4:60:4:60|t",
	["shaman"] 		= "|TInterface\\Icons\\Classicon_shaman:30:30:0:0:64:64:4:60:4:60|t",
	["warlock"] 	= "|TInterface\\Icons\\Classicon_warlock:30:30:0:0:64:64:4:60:4:60|t",
	["warrior"] 	= "|TInterface\\Icons\\Classicon_warrior:30:30:0:0:64:64:4:60:4:60|t"
}

---@type table<number, string>
Constants.SpecIconMap = {
	-- Death Knight
	[250] = "spell_deathknight_bloodpresence",
	[251] = "spell_deathknight_frostpresence",
	[252] = "spell_deathknight_unholypresence",

	-- Demon Hunter
	[577] = "ability_demonhunter_specdps",
	[581] = "ability_demonhunter_spectank",

	-- Druid
	[102] = "spell_nature_starfall",
	[103] = "ability_druid_catform",
	[104] = "ability_racial_bearform",
	[105] = "spell_nature_healingtouch",

	-- Evoker
	[1467] = "classicon_evoker_devastation",
	[1468] = "classicon_evoker_preservation",
	[1473] = "classicon_evoker_augmentation",

	-- Hunter
	[253] = "ability_hunter_bestialdiscipline",
	[254] = "ability_hunter_focusedaim",
	[255] = "ability_hunter_camouflage",

	-- Mage
	[62] = "spell_holy_magicalsentry",
	[63] = "spell_fire_firebolt02",
	[64] = "spell_frost_frostbolt02",

	-- Monk
	[268] = "spell_monk_brewmaster_spec",
	[269] = "spell_monk_windwalker_spec",
	[270] = "spell_monk_mistweaver_spec",

	-- Paladin
	[65] = "spell_holy_holybolt",
	[66] = "spell_holy_devotionaura",
	[70] = "spell_holy_auraoflight",

	-- Priest
	[256] = "spell_holy_powerwordshield",
	[257] = "spell_holy_guardianspirit",
	[258] = "spell_shadow_shadowwordpain",

	-- Rogue
	[259] = "ability_rogue_deadlybrew",
	[260] = "ability_rogue_waylay",
	[261] = "ability_stealth",

	-- Shaman
	[262] = "spell_nature_lightning",
	[263] = "spell_shaman_improvedstormstrike",
	[264] = "spell_nature_magicimmunity",

	-- Warlock
	[265] = "spell_shadow_deathcoil",
	[266] = "spell_shadow_metamorphosis",
	[267] = "spell_shadow_rainoffire",

	-- Warrior
	[71] = "ability_warrior_savageblow",
	[72] = "ability_warrior_innerrage",
	[73] = "ability_warrior_defensivestance",
}

-- Class name map
Constants.ClassNameByID = {
    [1] = "Warrior",
    [2] = "Paladin",
    [3] = "Hunter",
    [4] = "Rogue",
    [5] = "Priest",
    [7] = "Shaman",
    [8] = "Mage",
    [9] = "Warlock",
	[10] = "Monk",
    [11] = "Druid",
	[12] = "Demon Hunter",
	[13] = "Evoker"
}

---Spec ID to name mapping
---@type table<number, string>
Constants.SpecNameByID = {
    -- Death Knight
    [250] = "Blood",
    [251] = "Frost",
    [252] = "Unholy",
    -- Demon Hunter
    [577] = "Havoc",
    [581] = "Vengeance",
    -- Druid
    [102] = "Balance",
    [103] = "Feral",
    [104] = "Guardian",
    [105] = "Restoration",
    -- Evoker
    [1467] = "Devastation",
    [1468] = "Preservation",
    [1473] = "Augmentation",
    -- Hunter
    [253] = "BeastMastery",
    [254] = "Marksmanship",
    [255] = "Survival",
    -- Mage
    [62] = "Arcane",
    [63] = "Fire",
    [64] = "Frost",
    -- Monk
    [268] = "Brewmaster",
    [269] = "Windwalker",
    [270] = "Mistweaver",
    -- Paladin
    [65] = "Holy",
    [66] = "Protection",
    [70] = "Retribution",
    -- Priest
    [256] = "Discipline",
    [257] = "Holy",
    [258] = "Shadow",
    -- Rogue
    [259] = "Assassination",
    [260] = "Outlaw",
    [261] = "Subtlety",
    -- Shaman
    [262] = "Elemental",
    [263] = "Enhancement",
    [264] = "Restoration",
    -- Warlock
    [265] = "Affliction",
    [266] = "Demonology",
    [267] = "Destruction",
    -- Warrior
    [71] = "Arms",
    [72] = "Fury",
    [73] = "Protection",
}

-- Class and Spec index to SpecID mapping (fallback when GetSpecializationInfo fails)
Constants.SpecIDByClassSpec = {
    ["Warrior"] = {[1] = 71, [2] = 72, [3] = 73},           	-- Arms, Fury, Protection
    ["Paladin"] = {[1] = 65, [2] = 66, [3] = 70},           	-- Holy, Protection, Retribution
    ["Hunter"] = {[1] = 253, [2] = 254, [3] = 255},         	-- Beast Mastery, Marksmanship, Survival
    ["Rogue"] = {[1] = 259, [2] = 260, [3] = 261},          	-- Assassination, Outlaw, Subtlety
    ["Priest"] = {[1] = 256, [2] = 257, [3] = 258},         	-- Discipline, Holy, Shadow
    ["Death Knight"] = {[1] = 250, [2] = 251, [3] = 252},   	-- Blood, Frost, Unholy
    ["Shaman"] = {[1] = 262, [2] = 263, [3] = 264},         	-- Elemental, Enhancement, Restoration
    ["Mage"] = {[1] = 62, [2] = 63, [3] = 64},              	-- Arcane, Fire, Frost
    ["Warlock"] = {[1] = 265, [2] = 266, [3] = 267},        	-- Affliction, Demonology, Destruction
    ["Monk"] = {[1] = 268, [2] = 270, [3] = 269},           	-- Brewmaster, Mistweaver, Windwalker
    ["Druid"] = {[1] = 102, [2] = 103, [3] = 104, [4] = 105}, 	-- Balance, Feral, Guardian, Restoration
    ["Demon Hunter"] = {[1] = 577, [2] = 581},              	-- Havoc, Vengeance
    ["Evoker"] = {[1] = 1467, [2] = 1468, [3] = 1473}       	-- Devastation, Preservation, Augmentation
}

-- TWW S2 Dungeon Icons
Constants.DungeonKeyToIcon = {
	["cinderbrew_meadery"] 	= "|TInterface\\Icons\\Inv_achievement_dungeon_cinderbrewmeadery:30:30:0:0:64:64:4:60:4:60|t",
	["darkflame"] 			= "|TInterface\\Icons\\Inv_achievement_dungeon_darkflamecleft:30:30:0:0:64:64:4:60:4:60|t",
	["the_rookery"] 		= "|TInterface\\Icons\\Inv_achievement_dungeon_rookery:30:30:0:0:64:64:4:60:4:60|t",
	["priory"] 				= "|TInterface\\Icons\\Inv_achievement_dungeon_prioryofthesacredflame:30:30:0:0:64:64:4:60:4:60|t",
	["motherlode"] 			= "|TInterface\\Icons\\Achievement_dungeon_kezan:30:30:0:0:64:64:4:60:4:60|t",
	["operation_floodgate"] = "|TInterface\\Icons\\Inv_achievement_dungeon_waterworks:30:30:0:0:64:64:4:60:4:60|t",
	["theater_of_pain"] 	= "|TInterface\\Icons\\Achievement_dungeon_theatreofpain:30:30:0:0:64:64:4:60:4:60|t",
	["mechagon"] 			= "|TInterface\\Icons\\Achievement_boss_mechagon:30:30:0:0:64:64:4:60:4:60|t",
}

-- TWW S2 Dungeon Display Names
Constants.DungeonKeyToName = {
	["skyreach"] = "Skyreach",
	["pit-of-saron"] = "Pit of Saron",
	["seat-of-the-triumvirate"] = "Seat of the Triumvirate",
	["algethar-academy"] = "Algeth'ar Academy",
	["windrunner-spire"] = "Windrunner Spire",
	["magisters-terrace"] = "Magister's Terrace",
	["nexus-point-xenas"] = "Nexus-Point Xenas",
	["maisara-caverns"] = "Maisara Caverns",

	["cinderbrew_meadery"] 	= "Cinderbrew Meadery",
	["darkflame"] 			= "Darkflame Cleft",
	["the_rookery"] 		= "The Rookery",
	["priory"] 				= "Priory of the Sacred Flame",
	["motherlode"] 			= "The Motherlode",
	["operation_floodgate"] = "Operation: Floodgate",
	["theater_of_pain"] 	= "Theater of Pain",
	["mechagon"] 			= "Operation: Mechagon: Workshop",
	["undermine"] 			= "Liberation of Undermine",
}

Constants.IgnoreSpells = {
	[453] = true, 	 -- Mind Soothe
	[61305] = true,  -- Polymorph (Cat)
    [61025] = true,  -- Polymorph (Snake)
    [61721] = true,  -- Polymorph (Rabbit)
    [61780] = true,  -- Polymorph (Turkey)
    [28271] = true,  -- Polymorph (Turtle)
    [28272] = true,  -- Polymorph (Pig)
	[118] = true,    -- Polymorph Sheep
	[277792] = true, -- Polymorph (Bee)
    [161354] = true, -- Polymorph (Monkey)
    [277787] = true, -- Polymorph (Direhorn)
    [161355] = true, -- Polymorph (Penguin)
    [161353] = true, -- Polymorph (Polar Bear)
    [120140] = true, -- Polymorph (Porcupine)
    [161372] = true, -- Polymorph (Peacock)
    [391622] = true, -- Polymorph (Duck)
	[115078] = true, -- Paralysis
	[217832] = true, -- Imprison
	[211015] = true, -- Hex (Cockroach)
    [210873] = true, -- Hex (Compy)
    [211010] = true, -- Hex (Snake)
    [211004] = true, -- Hex (Spider)
    [277784] = true, -- Hex (Wicker Mongrel)
    [277778] = true, -- Hex (Zandalari Tendonripper)
    [309328] = true, -- Hex (Living Honey)
    [269352] = true, -- Hex (Skeletal Raptor)
}




Constants.TWWS2 = {
	kicks = {
	},
	spellsteal_ids = {
	},
	spellsteal_spells = mint.List:New({
	}),
	buff_map = {
	},
	debuff_map = {
		-- Skyreach
		[153757] = { class = "bleed", name = "Fan of Blades", dungeon = "skyreach", condition = function(...) return true end, spell = Spell(153757) },
		[1254475] = { class = "bleed", name = "Blade Rush", dungeon = "skyreach", condition = function(...) return true end, spell = Spell(1254475) },
		[1254670] = { class = "magic", name = "Rushing Winds", dungeon = "skyreach", condition = function(...) return true end, spell = Spell(1254670) },
		[1254678] = { class = "enrage", name = "Wrathful Wind", dungeon = "skyreach", condition = function(...) return true end, spell = Spell(1254678) },
		[1273356] = { class = "magic", name = "Solar Barrier", dungeon = "skyreach", condition = function(...) return true end, spell = Spell(1273356) },

		-- Pit of Saron
		[157736] = { class = "magic", name = "Immolate", dungeon = "pit-of-saron", condition = function(...) return true end, spell = Spell(157736) },
		[1258434] = { class = "curse", name = "Curse of Torment", dungeon = "pit-of-saron", condition = function(...) return true end, spell = Spell(1258434) },
		[1258437] = { class = "magic", name = "Permeating Cold", dungeon = "pit-of-saron", condition = function(...) return true end, spell = Spell(1258437) },
		[1258448] = { class = "magic", name = "Necromantic Infusion", dungeon = "pit-of-saron", condition = function(...) return true end, spell = Spell(1258448) },
		[1258459] = { class = "disease", name = "Rotting Strikes", dungeon = "pit-of-saron", condition = function(...) return true end, spell = Spell(1258459) },
		[1258826] = { class = "magic", name = "Torrent of Misery", dungeon = "pit-of-saron", condition = function(...) return true end, spell = Spell(1258826) },
		[1259132] = { class = "enrage", name = "Plague Frenzy", dungeon = "pit-of-saron", condition = function(...) return true end, spell = Spell(1259132) },
		[1261921] = { class = "magic", name = "Cryoshards", dungeon = "pit-of-saron", condition = function(...) return true end, spell = Spell(1261921) },
		[1262930] = { class = "disease", name = "Rotting Strikes", dungeon = "pit-of-saron", condition = function(...) return true end, spell = Spell(1262930) },
		[1264186] = { class = "curse", name = "Shadowbind", dungeon = "pit-of-saron", condition = function(...) return true end, spell = Spell(1264186) },

		-- Seat of the Triumvirate
		[240559] = { class = "bleed", name = "Grievous Wound", dungeon = "seat-of-the-triumvirate", condition = function(...) return true end, spell = Spell(240559) },
		[244751] = { class = "magic", name = "Howling Dark", dungeon = "seat-of-the-triumvirate", condition = function(...) return true end, spell = Spell(244751) },
		[245742] = { class = "bleed", name = "Shadow Pounce", dungeon = "seat-of-the-triumvirate", condition = function(...) return true end, spell = Spell(245742) },
		[245748] = { class = "magic", name = "Corrupting Touch", dungeon = "seat-of-the-triumvirate", condition = function(...) return true end, spell = Spell(245748) },
		[1262519] = { class = "bleed", name = "Backstab", dungeon = "seat-of-the-triumvirate", condition = function(...) return true end, spell = Spell(1262519) },
		[1262526] = { class = "magic", name = "Abyssal Enhancement", dungeon = "seat-of-the-triumvirate", condition = function(...) return true end, spell = Spell(1262526) },
		[1264036] = { class = "enrage", name = "Battle Rage", dungeon = "seat-of-the-triumvirate", condition = function(...) return true end, spell = Spell(1264036) },
		[1280330] = { class = "magic", name = "Rift Essence", dungeon = "seat-of-the-triumvirate", condition = function(...) return true end, spell = Spell(1280330) },

		-- Algeth'ar Academy
		[374350] = { class = "magic", name = "Energy Bomb", dungeon = "algethar-academy", condition = function(...) return true end, spell = Spell(374350) },
		[376997] = { class = "bleed", name = "Savage Peck", dungeon = "algethar-academy", condition = function(...) return true end, spell = Spell(376997) },
		[377344] = { class = "bleed", name = "Peck", dungeon = "algethar-academy", condition = function(...) return true end, spell = Spell(377344) },
		[377389] = { class = "enrage", name = "Raging Screech", dungeon = "algethar-academy", condition = function(...) return true end, spell = Spell(377389) },
		[388392] = { class = "magic", name = "Monotonous Lecture", dungeon = "algethar-academy", condition = function(...) return true end, spell = Spell(388392) },
		[389033] = { class = "poison", name = "Lasher Toxin", dungeon = "algethar-academy", condition = function(...) return true end, spell = Spell(389033) },
		[390938] = { class = "enrage", name = "Agitation", dungeon = "algethar-academy", condition = function(...) return true end, spell = Spell(390938) },
		[391977] = { class = "magic", name = "Oversurge", dungeon = "algethar-academy", condition = function(...) return true end, spell = Spell(391977) },
		[396716] = { class = "bleed", name = "Splinterbark", dungeon = "algethar-academy", condition = function(...) return true end, spell = Spell(396716) },
		[1282244] = { class = "bleed", name = "Vile Bite", dungeon = "algethar-academy", condition = function(...) return true end, spell = Spell(1282244) },

		-- Windrunner Spire
		[468659] = { class = "bleed", name = "Throw Axe", dungeon = "windrunner-spire", condition = function(...) return true end, spell = Spell(468659) },
		[472054] = { class = "bleed", name = "Reckless Leap", dungeon = "windrunner-spire", condition = function(...) return true end, spell = Spell(472054) },
		[473795] = { class = "poison", name = "Poison Blades", dungeon = "windrunner-spire", condition = function(...) return true end, spell = Spell(473795) },
		[1215803] = { class = "curse", name = "Curse of Darkness", dungeon = "windrunner-spire", condition = function(...) return true end, spell = Spell(1215803) },
		[1216298] = { class = "magic", name = "Soul Torment", dungeon = "windrunner-spire", condition = function(...) return true end, spell = Spell(1216298) },
		[1216459] = { class = "enrage", name = "Ephemeral Bloodlust", dungeon = "windrunner-spire", condition = function(...) return true end, spell = Spell(1216459) },
		[1216825] = { class = "poison", name = "Poison Spray", dungeon = "windrunner-spire", condition = function(...) return true end, spell = Spell(1216825) },
		[1216860] = { class = "magic", name = "Bolstering Flames", dungeon = "windrunner-spire", condition = function(...) return true end, spell = Spell(1216860) },
		[1216985] = { class = "bleed", name = "Puncturing Bite", dungeon = "windrunner-spire", condition = function(...) return true end, spell = Spell(1216985) },
		[1253739] = { class = "bleed", name = "Shred Flesh", dungeon = "windrunner-spire", condition = function(...) return true end, spell = Spell(1253739) },
		[1253834] = { class = "curse", name = "Curse of Darkness", dungeon = "windrunner-spire", condition = function(...) return true end, spell = Spell(1253834) },

		-- Magister's Terrace
		[468966] = { class = "magic", name = "Polymorph", dungeon = "magisters-terrace", condition = function(...) return true end, spell = Spell(468966) },
		[1214038] = { class = "magic", name = "Ethereal Shackles", dungeon = "magisters-terrace", condition = function(...) return true end, spell = Spell(1214038) },
		[1214714] = { class = "magic", name = "Void Torrent", dungeon = "magisters-terrace", condition = function(...) return true end, spell = Spell(1214714) },
		[1215897] = { class = "magic", name = "Devouring Entropy", dungeon = "magisters-terrace", condition = function(...) return true end, spell = Spell(1215897) },
		[1245068] = { class = "magic", name = "Consuming Void", dungeon = "magisters-terrace", condition = function(...) return true end, spell = Spell(1245068) },
		[1248689] = { class = "magic", name = "Hastening Ward", dungeon = "magisters-terrace", condition = function(...) return true end, spell = Spell(1248689) },
		[1252909] = { class = "magic", name = "Arcane Blade", dungeon = "magisters-terrace", condition = function(...) return true end, spell = Spell(1252909) },
		[1254306] = { class = "magic", name = "Power Word: Shield", dungeon = "magisters-terrace", condition = function(...) return true end, spell = Spell(1254306) },
		[1255187] = { class = "magic", name = "Holy Fire", dungeon = "magisters-terrace", condition = function(...) return true end, spell = Spell(1255187) },
		[1264693] = { class = "magic", name = "Void Surge", dungeon = "magisters-terrace", condition = function(...) return true end, spell = Spell(1264693) },
		[1265561] = { class = "magic", name = "Arcane Blade", dungeon = "magisters-terrace", condition = function(...) return true end, spell = Spell(1265561) },
		[1282055] = { class = "magic", name = "Ethereal Shackles", dungeon = "magisters-terrace", condition = function(...) return true end, spell = Spell(1282055) },
		[1284627] = { class = "magic", name = "Umbral Splinters", dungeon = "magisters-terrace", condition = function(...) return true end, spell = Spell(1284627) },

		-- Nexus-Point Xenas
		[1216502] = { class = "bleed", name = "Crimson Glaive", dungeon = "nexus-point-xenas", condition = function(...) return true end, spell = Spell(1216502) },
		[1217882] = { class = "curse", name = "Bad Omens", dungeon = "nexus-point-xenas", condition = function(...) return true end, spell = Spell(1217882) },
		[1238439] = { class = "bleed", name = "Razor Dive", dungeon = "nexus-point-xenas", condition = function(...) return true end, spell = Spell(1238439) },
		[1249815] = { class = "magic", name = "Transference", dungeon = "nexus-point-xenas", condition = function(...) return true end, spell = Spell(1249815) },
		[1263783] = { class = "magic", name = "Holy Echo", dungeon = "nexus-point-xenas", condition = function(...) return true end, spell = Spell(1263783) },
		[1277557] = { class = "magic", name = "Burning Radiance", dungeon = "nexus-point-xenas", condition = function(...) return true end, spell = Spell(1277557) },
		[1281636] = { class = "curse", name = "Creeping Void", dungeon = "nexus-point-xenas", condition = function(...) return true end, spell = Spell(1281636) },

		-- Maisara Caverns
		[1246666] = { class = "disease", name = "Infected Pinions", dungeon = "maisara-caverns", condition = function(...) return true end, spell = Spell(1246666) },
		[1254175] = { class = "magic", name = "Cries of the Fallen", dungeon = "maisara-caverns", condition = function(...) return true end, spell = Spell(1254175) },
		[1255765] = { class = "enrage", name = "Blood Frenzy", dungeon = "maisara-caverns", condition = function(...) return true end, spell = Spell(1255765) },
		[1256008] = { class = "magic", name = "Hex", dungeon = "maisara-caverns", condition = function(...) return true end, spell = Spell(1256008) },
		[1259255] = { class = "magic", name = "Spirit Rend", dungeon = "maisara-caverns", condition = function(...) return true end, spell = Spell(1259255) },
		[1259731] = { class = "magic", name = "Cries of the Fallen", dungeon = "maisara-caverns", condition = function(...) return true end, spell = Spell(1259731) },
		[1260709] = { class = "magic", name = "Vilebranch Sting", dungeon = "maisara-caverns", condition = function(...) return true end, spell = Spell(1260709) },
		[1262411] = { class = "magic", name = "Ritual Firebrand", dungeon = "maisara-caverns", condition = function(...) return true end, spell = Spell(1262411) },
		[1266381] = { class = "bleed", name = "Hooked Snare", dungeon = "maisara-caverns", condition = function(...) return true end, spell = Spell(1266381) },
		[1266488] = { class = "bleed", name = "Open Wound", dungeon = "maisara-caverns", condition = function(...) return true end, spell = Spell(1266488) },
		[1270079] = { class = "magic", name = "Grim Ward", dungeon = "maisara-caverns", condition = function(...) return true end, spell = Spell(1270079) },
		[1271623] = { class = "magic", name = "Frost Nova", dungeon = "maisara-caverns", condition = function(...) return true end, spell = Spell(1271623) },

	}
}

Constants.DispelList = mint.List:New({
	-- Devouring Ring (Affix)
	{ id = 440313, class = "any", condition = function(unit, player, spell)
		if player:FindDebuff(spell):Active() and not unit:IsUnit(player) then
			return false
		end
		return true
	end, spell = Spell(440313) },

	-- Bleed spells
	{ id = 153757, class = "bleed", condition = function(...) return true end, spell = Spell(153757) },
	{ id = 240559, class = "bleed", condition = function(...) return true end, spell = Spell(240559) },
	{ id = 245742, class = "bleed", condition = function(...) return true end, spell = Spell(245742) },
	{ id = 376997, class = "bleed", condition = function(...) return true end, spell = Spell(376997) },
	{ id = 377344, class = "bleed", condition = function(...) return true end, spell = Spell(377344) },
	{ id = 396716, class = "bleed", condition = function(...) return true end, spell = Spell(396716) },
	{ id = 468659, class = "bleed", condition = function(...) return true end, spell = Spell(468659) },
	{ id = 472054, class = "bleed", condition = function(...) return true end, spell = Spell(472054) },
	{ id = 1216502, class = "bleed", condition = function(...) return true end, spell = Spell(1216502) },
	{ id = 1216985, class = "bleed", condition = function(...) return true end, spell = Spell(1216985) },
	{ id = 1238439, class = "bleed", condition = function(...) return true end, spell = Spell(1238439) },
	{ id = 1253739, class = "bleed", condition = function(...) return true end, spell = Spell(1253739) },
	{ id = 1254475, class = "bleed", condition = function(...) return true end, spell = Spell(1254475) },
	{ id = 1262519, class = "bleed", condition = function(...) return true end, spell = Spell(1262519) },
	{ id = 1266381, class = "bleed", condition = function(...) return true end, spell = Spell(1266381) },
	{ id = 1266488, class = "bleed", condition = function(...) return true end, spell = Spell(1266488) },
	{ id = 1282244, class = "bleed", condition = function(...) return true end, spell = Spell(1282244) },

	-- Magic spells
	{ id = 157736, class = "magic", condition = function(...) return true end, spell = Spell(157736) },
	{ id = 244751, class = "magic", condition = function(...) return true end, spell = Spell(244751) },
	{ id = 245748, class = "magic", condition = function(...) return true end, spell = Spell(245748) },
	{ id = 374350, class = "magic", condition = function(...) return true end, spell = Spell(374350) },
	{ id = 388392, class = "magic", condition = function(...) return true end, spell = Spell(388392) },
	{ id = 391977, class = "magic", condition = function(...) return true end, spell = Spell(391977) },
	{ id = 468966, class = "magic", condition = function(...) return true end, spell = Spell(468966) },
	{ id = 1214038, class = "magic", condition = function(...) return true end, spell = Spell(1214038) },
	{ id = 1214714, class = "magic", condition = function(...) return true end, spell = Spell(1214714) },
	{ id = 1215897, class = "magic", condition = function(...) return true end, spell = Spell(1215897) },
	{ id = 1216298, class = "magic", condition = function(...) return true end, spell = Spell(1216298) },
	{ id = 1216860, class = "magic", condition = function(...) return true end, spell = Spell(1216860) },
	{ id = 1245068, class = "magic", condition = function(...) return true end, spell = Spell(1245068) },
	{ id = 1248689, class = "magic", condition = function(...) return true end, spell = Spell(1248689) },
	{ id = 1249815, class = "magic", condition = function(...) return true end, spell = Spell(1249815) },
	{ id = 1252909, class = "magic", condition = function(...) return true end, spell = Spell(1252909) },
	{ id = 1254175, class = "magic", condition = function(...) return true end, spell = Spell(1254175) },
	{ id = 1254306, class = "magic", condition = function(...) return true end, spell = Spell(1254306) },
	{ id = 1254670, class = "magic", condition = function(...) return true end, spell = Spell(1254670) },
	{ id = 1255187, class = "magic", condition = function(...) return true end, spell = Spell(1255187) },
	{ id = 1256008, class = "magic", condition = function(...) return true end, spell = Spell(1256008) },
	{ id = 1258437, class = "magic", condition = function(...) return true end, spell = Spell(1258437) },
	{ id = 1258448, class = "magic", condition = function(...) return true end, spell = Spell(1258448) },
	{ id = 1258826, class = "magic", condition = function(...) return true end, spell = Spell(1258826) },
	{ id = 1259255, class = "magic", condition = function(...) return true end, spell = Spell(1259255) },
	{ id = 1259731, class = "magic", condition = function(...) return true end, spell = Spell(1259731) },
	{ id = 1260709, class = "magic", condition = function(...) return true end, spell = Spell(1260709) },
	{ id = 1261921, class = "magic", condition = function(...) return true end, spell = Spell(1261921) },
	{ id = 1262411, class = "magic", condition = function(...) return true end, spell = Spell(1262411) },
	{ id = 1262526, class = "magic", condition = function(...) return true end, spell = Spell(1262526) },
	{ id = 1263783, class = "magic", condition = function(...) return true end, spell = Spell(1263783) },
	{ id = 1264693, class = "magic", condition = function(...) return true end, spell = Spell(1264693) },
	{ id = 1265561, class = "magic", condition = function(...) return true end, spell = Spell(1265561) },
	{ id = 1270079, class = "magic", condition = function(...) return true end, spell = Spell(1270079) },
	{ id = 1271623, class = "magic", condition = function(...) return true end, spell = Spell(1271623) },
	{ id = 1273356, class = "magic", condition = function(...) return true end, spell = Spell(1273356) },
	{ id = 1277557, class = "magic", condition = function(...) return true end, spell = Spell(1277557) },
	{ id = 1280330, class = "magic", condition = function(...) return true end, spell = Spell(1280330) },
	{ id = 1282055, class = "magic", condition = function(...) return true end, spell = Spell(1282055) },
	{ id = 1284627, class = "magic", condition = function(...) return true end, spell = Spell(1284627) },

	-- Enrage spells
	{ id = 377389, class = "enrage", condition = function(...) return true end, spell = Spell(377389) },
	{ id = 390938, class = "enrage", condition = function(...) return true end, spell = Spell(390938) },
	{ id = 1216459, class = "enrage", condition = function(...) return true end, spell = Spell(1216459) },
	{ id = 1254678, class = "enrage", condition = function(...) return true end, spell = Spell(1254678) },
	{ id = 1255765, class = "enrage", condition = function(...) return true end, spell = Spell(1255765) },
	{ id = 1259132, class = "enrage", condition = function(...) return true end, spell = Spell(1259132) },
	{ id = 1264036, class = "enrage", condition = function(...) return true end, spell = Spell(1264036) },

	-- Poison spells
	{ id = 389033, class = "poison", condition = function(...) return true end, spell = Spell(389033) },
	{ id = 473795, class = "poison", condition = function(...) return true end, spell = Spell(473795) },
	{ id = 1216825, class = "poison", condition = function(...) return true end, spell = Spell(1216825) },

	-- Curse spells
	{ id = 1215803, class = "curse", condition = function(...) return true end, spell = Spell(1215803) },
	{ id = 1217882, class = "curse", condition = function(...) return true end, spell = Spell(1217882) },
	{ id = 1253834, class = "curse", condition = function(...) return true end, spell = Spell(1253834) },
	{ id = 1258434, class = "curse", condition = function(...) return true end, spell = Spell(1258434) },
	{ id = 1264186, class = "curse", condition = function(...) return true end, spell = Spell(1264186) },
	{ id = 1281636, class = "curse", condition = function(...) return true end, spell = Spell(1281636) },

	-- Disease spells
	{ id = 1246666, class = "disease", condition = function(...) return true end, spell = Spell(1246666) },
	{ id = 1258459, class = "disease", condition = function(...) return true end, spell = Spell(1258459) },
	{ id = 1262930, class = "disease", condition = function(...) return true end, spell = Spell(1262930) },

})


Constants.move_spells = mint.List:New({
	mint.Spell.New(79206),
	mint.Spell.New(358267) -- Hover
})

-- print("DISPELS:", Constants.DispelList:count())

Constants.ClassDispelMap = {
	["DEATHKNIGHT"] = false,
	["DEMONHUNTER"] = false,
	["DRUID"] = {
		-- Balance
		[102] = {
			Spell(2782, { beneficial = true, ignore_moving = true, ignore_facing = true }), -- Remove Corruption
		},
		-- Feral
		[103] = {
			Spell(2782, { beneficial = true, ignore_moving = true, ignore_facing = true }), -- Remove Corruption
		},
		-- Guardian
		[104] = {
			Spell(2782, { beneficial = true, ignore_moving = true, ignore_facing = true }), -- Remove Corruption
		},
		-- Restoration
		[105] = {
			Spell(88423, { beneficial = true, ignore_moving = true, ignore_facing = true }), -- Nature's Cure
			Spell(2782, { beneficial = true, ignore_moving = true, ignore_facing = true }), -- Remove Corruption
		}
	},
	["EVOKER"] = {
		-- Devestation
		[1467] = {
			Spell(374251, { beneficial = true, ignore_moving = true, ignore_facing = true }), -- Cauterizing Flame
			Spell(365585, { beneficial = true, ignore_moving = true, ignore_facing = true }), -- Expunge
		},
		-- Preservation
		[1468] = {
			Spell(374251, { beneficial = true, ignore_moving = true, ignore_facing = true }), -- Cauterizing Flame
			Spell(360823, { beneficial = true, ignore_moving = true, ignore_facing = true }), -- Naturalize
		},
		-- Augmentation
		[1473] = {
			Spell(374251, { beneficial = true, ignore_moving = true, ignore_facing = true }), -- Cauterizing Flame
			Spell(365585, { beneficial = true, ignore_moving = true, ignore_facing = true }), -- Expunge
		}
	},
	["HUNTER"] = {
		-- Beast Mastery
		[253] = false,
		-- Marksmanship
		[254] = false,
		-- Survival
		[255] = false
	},
	["MAGE"] = {
		-- Arcane
		[62] = {
			Spell(475, { beneficial = true, ignore_moving = true, ignore_facing = true }), -- Remove Curse
		},
		-- Fire
		[63] = {
			Spell(475, { beneficial = true, ignore_moving = true, ignore_facing = true }), -- Remove Curse
		},
		-- Frost
		[64] = {
			Spell(475, { beneficial = true, ignore_moving = true, ignore_facing = true }), -- Remove Curse
		}
	},
	["MONK"] = {
		-- Brewmaster
		[268] = {
			Spell(115450, { beneficial = true, ignore_moving = true, ignore_facing = true }), -- Detox
		},
		-- Windwalker
		[269] = {
			Spell(115450, { beneficial = true, ignore_moving = true, ignore_facing = true }), -- Detox
		},
		-- Mistweaver
		[270] = {
			Spell(115450, { beneficial = true, ignore_moving = true, ignore_facing = true }), -- Detox
		}
	},
	["PALADIN"] = {
		-- Holy
		[65] = {
			Spell(4987, { beneficial = true, ignore_moving = true, ignore_facing = true }), -- Cleanse
		},
		-- Protection
		[66] = {
			Spell(213644, { beneficial = true, ignore_moving = true, ignore_facing = true }), -- Cleanse Toxins
		},
		-- Retribution
		[70] = {
			Spell(213644, { beneficial = true, ignore_moving = true, ignore_facing = true }), -- Cleanse Toxins
		}
	},
	["PRIEST"] = {
		-- Discipline
		[256] = {
			Spell(527, { beneficial = true, ignore_moving = true, ignore_facing = true }), -- Purify
		},
		-- Holy
		[257] = {
			Spell(527, { beneficial = true, ignore_moving = true, ignore_facing = true }), -- Purify
		},
		-- Shadow
		[258] = {
			Spell(213634, { beneficial = true, ignore_moving = true, ignore_facing = true }), -- Purify Disease
		}
	},
	["ROGUE"] = false,
	["SHAMAN"] = {
		-- Elemental
		[262] = {
			Spell(51886, { beneficial = true, ignore_moving = true, ignore_facing = true }), -- Cleanse Spirit
			Spell(383013, { beneficial = true, ignore_moving = true, ignore_facing = true }), -- Poison Cleansing Totem
		},
		-- Enhancement
		[263] = {
			Spell(51886, { beneficial = true, ignore_moving = true, ignore_facing = true }), -- Cleanse Spirit
			Spell(383013, { beneficial = true, ignore_moving = true, ignore_facing = true }), -- Poison Cleansing Totem
		},
		-- Restoration
		[264] = {
			Spell(77130, { beneficial = true, ignore_moving = true, ignore_facing = true }), -- Purify Spirit
			Spell(383013, { beneficial = true, ignore_moving = true, ignore_facing = true }), -- Poison Cleansing Totem
			-- Spell(51886), -- Cleanse Spirit
		}
	},
	["WARLOCK"] = false,
	["WARRIOR"] = false
}

Constants.ClassKickMap = {
	["DEATHKNIGHT"] = {
		-- Blood
		[250] = Spell(47528),
		-- Frost
		[251] = Spell(47528),
		-- Unholy
		[252] = Spell(47528),
	},
	["DEMONHUNTER"] = {
		-- Havoc
		[577] = Spell(183752),
		-- Vengeance
		[581] = Spell(183752),
	},
	["DRUID"] = {
		-- Balance
		[102] = Spell(78675),
		-- Feral
		[103] = Spell(106839),
		-- Guardian
		[104] = Spell(106839),
		-- Restoration
		[105] = Spell(106839),
	},
	["EVOKER"] = {
		-- Devestation
		[1467] = Spell(351338),
		-- Preservation
		[1468] = Spell(351338),
		-- Augmentation
		[1473] = Spell(351338),
	},
	["HUNTER"] = {
		-- Beast Mastery
		[253] = Spell(147362),
		-- Marksmanship
		[254] = Spell(147362),
		-- Survival
		[255] = Spell(187707),
	},
	["MAGE"] = {
		-- Arcane
		[62] = Spell(2139),
		-- Fire
		[63] = Spell(2139),
		-- Frost
		[64] = Spell(2139),
	},
	["MONK"] = {
		-- Brewmaster
		[268] = Spell(116705),
		-- Mistweaver
		[270] = Spell(116705),
		-- Windwalker
		[269] = Spell(116705),
	},
	["PALADIN"] = {
		-- Holy
		[65] = Spell(96231),
		-- Protection
		[66] = Spell(96231),
		-- Retribution
		[70] = Spell(96231),
	},
	["PRIEST"] = {
		-- Discipline
		[256] = false,
		-- Holy
		[257] = false,
		-- Shadow
		[258] = Spell(15487),
	},
	["ROGUE"] = {
		-- Assassination
		[259] = Spell(1766),
		-- Outlaw
		[260] = Spell(1766),
		-- Subtlety
		[261] = Spell(1766),
	},
	["SHAMAN"] = {
		-- Elemental
		[262] = Spell(57994),
		-- Enhancement
		[263] = Spell(57994),
		-- Restoration
		[264] = Spell(57994),
	},
	["WARLOCK"] = {
		-- Affliction
		[265] = Spell(19647),
		-- Demonology
		[266] = Spell(19647),
		-- Destruction
		[267] = Spell(19647),
	},
	["WARRIOR"] = {
		-- Arms
		[71] = Spell(6552),
		-- Fury
		[72] = Spell(6552),
		-- Protection
		[73] = Spell(6552),
	}
}

Constants.ClassStopMap = {
	["DEATHKNIGHT"] = {
		-- Blood
		[250] = {
			{
				type = "kick",
				cost = 0,
				spell = Spell(47528), -- Mind Freeze
			},
			{
				type = "stun",
				cost = 1,
				spell = Spell(108194), -- Asphyxiate
			},
		},
		-- Frost
		[251] = {
			{
				type = "kick",
				cost = 0,
				spell = Spell(47528), -- Mind Freeze
			},
			{
				type = "stun",
				cost = 1,
				spell = Spell(108194), -- Asphyxiate
			},
		},
		-- Unholy
		[252] = {
			{
				type = "kick",
				cost = 0,
				spell = Spell(47528), -- Mind Freeze
			},
			{
				type = "stun",
				cost = 1,
				spell = Spell(108194), -- Asphyxiate
			},
		},
	},
	["DEMONHUNTER"] = {
		-- Havoc
		[577] = {
			{
				type = "kick",
				cost = 0,
				spell = Spell(183752), -- Disrupt
			},
			-- {
			-- 	type = "stun",
			-- 	cost = 1,
			-- 	spell = Spell(179057), -- Chaos Nova
			-- },
		},
		-- Vengeance
		[581] = {
			{
				type = "kick",
				cost = 0,
				spell = Spell(183752), -- Disrupt
			},
			-- {
			-- 	type = "stun",
			-- 	cost = 1,
			-- 	spell = Spell(179057), -- Chaos Nova
			-- },
		}
	},
	["DRUID"] = {
		-- Balance
		[102] = {
			{
				type = "kick",
				cost = 0,
				spell = Spell(78675), -- Solar Beam
			},
			-- {
			-- 	type = "stun",
			-- 	cost = 1,
			-- 	spell = Spell(5211), -- Mighty Bash
			-- },
		},
		-- Feral
		[103] = {
			{
				type = "kick",
				cost = 0,
				spell = Spell(106839), -- Skull Bash
			},
			-- {
			-- 	type = "stun",
			-- 	cost = 1,
			-- 	spell = Spell(5211), -- Mighty Bash
			-- },
		},
		-- Guardian
		[104] = {
			{
				type = "kick",
				cost = 0,
				spell = Spell(106839), -- Skull Bash
			},
			-- {
			-- 	type = "stun",
			-- 	cost = 1,
			-- 	spell = Spell(5211), -- Mighty Bash
			-- },
		},
		-- Restoration
		[105] = {
			{
				type = "kick",
				cost = 0,
				spell = Spell(106839), -- Skull Bash
			},
			-- {
			-- 	type = "stun",
			-- 	cost = 1,
			-- 	spell = Spell(5211), -- Mighty Bash
			-- },
		}
	},
	["EVOKER"] = {
		-- Devestation
		[1467] = {
			{
				type = "kick",
				cost = 0,
				spell = Spell(351338), -- Quell
			},
		},
		-- Preservation
		[1468] = {
			{
				type = "kick",
				cost = 0,
				spell = Spell(351338), -- Quell
			},
		},
		-- Augmentation
		[1473] = {
			{
				type = "kick",
				cost = 0,
				spell = Spell(351338), -- Quell
			},
		},
	},
	["HUNTER"] = {
		-- Beast Mastery
		[253] = {
			{
				type = "kick",
				cost = 0,
				spell = Spell(147362), -- Counter Shot
			},
			-- {
			-- 	type = "stun",
			-- 	cost = 1,
			-- 	spell = Spell(109248), -- Binding Shot
			-- },
		},
		-- Marksmanship
		[254] = {
			{
				type = "kick",
				cost = 0,
				spell = Spell(147362), -- Counter Shot
			},
		},
		-- Survival
		[255] = {
			{
				type = "kick",
				cost = 0,
				spell = Spell(187707), -- Muzzle
			},
		}
	},
	["MAGE"] = {
		-- Arcane
		[62] = {
			{
				type = "kick",
				cost = 0,
				spell = Spell(2139), -- Counterspell
			},
		},
		-- Fire
		[63] = {
			{
				type = "kick",
				cost = 0,
				spell = Spell(2139), -- Counterspell
			},
		},
		-- Frost
		[64] = {
			{
				type = "kick",
				cost = 0,
				spell = Spell(2139), -- Counterspell
			},
		}
	},
	["MONK"] = {
		-- Brewmaster
		[268] = {
			{
				type = "kick",
				cost = 0,
				spell = Spell(116705), -- Spear Hand Strike
			},
		},
		-- Mistweaver
		[270] = {
			{
				type = "kick",
				cost = 0,
				spell = Spell(116705), -- Spear Hand Strike
			},
		},
		-- Windwalker
		[269] = {
			{
				type = "kick",
				cost = 0,
				spell = Spell(116705), -- Spear Hand Strike
			},
		}
	},
	["PALADIN"] = {
		-- Holy
		[65] = {
			{
				type = "kick",
				cost = 0,
				spell = Spell(96231), -- Rebuke
			},
			{
				type = "stun",
				cost = 1,
				spell = Spell(853), -- Hammer of Justice
			},
			-- {
			-- 	type = "disorient",
			-- 	cost = 3,
			-- 	spell = Spell(115750), -- Blinding Light
			-- },
		},
		-- Protection
		[66] = {
			{
				type = "kick",
				cost = 0,
				spell = Spell(96231), -- Rebuke
			},
			{
				type = "kick",
				cost = 0,
				spell = Spell(31935), -- Avenger's Shield
			},
			{
				type = "stun",
				cost = 1,
				spell = Spell(853), -- Hammer of Justice
			},
		},
		-- Retribution
		[70] = {
			{
				type = "kick",
				cost = 0,
				spell = Spell(96231), -- Rebuke
			},
			{
				type = "stun",
				cost = 1,
				spell = Spell(853), -- Hammer of Justice
			},
		}
	},
	["PRIEST"] = {
		-- Discipline
		[256] = false,
		-- Holy
		[257] = false,
		-- Shadow
		[258] = {
			{
				type = "kick",
				cost = 0,
				spell = Spell(15487), -- Silence
			},
		}
	},
	["ROGUE"] = {
		-- Assassination
		[259] = {
			{
				type = "kick",
				cost = 0,
				spell = Spell(1766), -- Kick
			},
			{
				type = "stop",
				cost = 1,
				spell = Spell(2094), -- Blind
			},
		},
		-- Outlaw
		[260] = {
			{
				type = "kick",
				cost = 0,
				spell = Spell(1766), -- Kick
			},
			{
				type = "stop",
				cost = 1,
				spell = Spell(2094), -- Blind
			},
		},
		-- Subtlety
		[261] = {
			{
				type = "kick",
				cost = 0,
				spell = Spell(1766), -- Kick
			},
			{
				type = "stop",
				cost = 1,
				spell = Spell(2094), -- Blind
			},
		}
	},
	["SHAMAN"] = {
		-- Elemental
		[262] = {
			{
				type = "kick",
				cost = 0,
				spell = Spell(57994), -- Wind Shear
			},
		},
		-- Enhancement
		[263] = {
			{
				type = "kick",
				cost = 0,
				spell = Spell(57994), -- Wind Shear
			},
		},
		-- Restoration
		[264] = {
			{
				type = "kick",
				cost = 0,
				spell = Spell(57994), -- Wind Shear
			},
		}
	},
	["WARLOCK"] = {
		-- Affliction
		[265] = {
			{
				type = "kick",
				cost = 0,
				spell = Spell(19647), -- Spell Lock
			},
		},
		-- Demonology
		[266] = {
			{
				type = "kick",
				cost = 0,
				spell = Spell(19647), -- Spell Lock
			},
		},
		-- Destruction
		[267] = {
			{
				type = "kick",
				cost = 0,
				spell = Spell(19647), -- Spell Lock
			},
		}
	},
	["WARRIOR"] = {
		-- Arms
		[71] = {
			{
				type = "kick",
				cost = 0,
				spell = Spell(6552), -- Pummel
			},
		},
		-- Fury
		[72] = {
			{
				type = "kick",
				cost = 0,
				spell = Spell(6552), -- Pummel
			},
		},
		-- Protection
		[73] = {
			{
				type = "kick",
				cost = 0,
				spell = Spell(6552), -- Pummel
			},
		},
	}
}

Constants.ClassDefensiveMap = {
    ["DEATHKNIGHT"] = false,
	["DEMONHUNTER"] = false,
	["DRUID"] = {
		-- Balance
		[102] = {
			Spell(2782), -- Remove Corruption
		},
		-- Feral
		[103] = {
			Spell(2782), -- Remove Corruption
		},
		-- Guardian
		[104] = {
			Spell(2782), -- Remove Corruption
		},
		-- Restoration
		[105] = {
			Spell(88423), -- Nature's Cure
			Spell(2782), -- Remove Corruption
		}
	},
	["EVOKER"] = {
		-- Devestation
		[1467] = {
			Spell(374251), -- Cauterizing Flame
			Spell(365585), -- Expunge
		},
		-- Preservation
		[1468] = {
			Spell(374251), -- Cauterizing Flame
			Spell(360823), -- Naturalize
		},
		-- Augmentation
		[1473] = {
			Spell(374251), -- Cauterizing Flame
			Spell(365585), -- Expunge
		}
	},
	["HUNTER"] = {
		-- Beast Mastery
		[253] = false,
		-- Marksmanship
		[254] = false,
		-- Survival
		[255] = false
	},
	["MAGE"] = {
        Spell(235313), -- Blazing Barrier
        Spell(414658), -- Ice Cold
        Spell(55342), -- Mirror Image
        Spell(110959), -- Greater Invisibility
        Spell(342245), -- Alter Time
	},
	["MONK"] = {
		-- Brewmaster
		[268] = {
			Spell(115450), -- Detox
		},
		-- Windwalker
		[269] = {
			Spell(115450), -- Detox
		},
		-- Mistweaver
		[270] = {
			Spell(115450), -- Detox
		}
	},
	["PALADIN"] = {
		-- Holy
		[65] = {
			Spell(4987), -- Cleanse
		},
		-- Protection
		[66] = {
			Spell(213644), -- Cleanse Toxins
		},
		-- Retribution
		[70] = {
			Spell(213644), -- Cleanse Toxins
		}
	},
	["PRIEST"] = {
		-- Discipline
		[256] = {
			Spell(527), -- Purify
		},
		-- Holy
		[257] = {
			Spell(527), -- Purify
		},
		-- Shadow
		[258] = {
			Spell(213634), -- Purify Disease
		}
	},
	["ROGUE"] = false,
	["SHAMAN"] = {
		-- Elemental
		[262] = {
			Spell(51886), -- Cleanse Spirit
			Spell(383013), -- Poison Cleansing Totem
		},
		-- Enhancement
		[263] = {
			Spell(51886), -- Cleanse Spirit
			Spell(383013), -- Poison Cleansing Totem
		},
		-- Restoration
		[264] = {
			Spell(77130), -- Purify Spirit
			Spell(383013), -- Poison Cleansing Totem
			-- Spell(51886), -- Cleanse Spirit
		}
	},
	["WARLOCK"] = false,
	["WARRIOR"] = false
}

Constants.Targets = {
	["priority"] = {
		-- Darkheart Thicket
		[99358] = { name = "Rotheart Dryad" },
		[100532] = { name = "Bloodtainted Burster" },
		-- Uldaman: Legacy of Tyr
		[186696] = { name = "Quaking Totem" },
		[184131] = { name = "Earthen Guardian" },
		-- Amirdrassil, the Dream's Hope
		[207796] = { name = "Burning Colossus" },
		[211904] = { name = "Tainted Treant" },
		[214441] = { name = "Scorched Treant" },
		-- Sepulcher of the First Ones
		[184140] = { name = "Xy Acolyte" },
		[182778] = { name = "Collapsing Quasar" },
		[183671] = { name = "Monstrous Soul" },
		[182045] = { name = "Necrotic Ritualist" },
		-- Earthcrawl Mines
		[216621] = { name = "Nerubian Webspinner" },
		-- Ruby Life Pools
		[197697] = { name = "Flamegullet" },
		[187897] = { name = "Defier Draghar" },
		[197535] = { name = "High Channeler Ryvati" },
		[197698] = { name = "Thunderhead" },
		-- The Underrot
		[135169] = { name = "Spirit Drain Totem" },
		[137103] = { name = "Blood Visage" },
		[133685] = { name = "Befouled Spirit" },
		[130909] = { name = "Fetid Maggot" },
		[138187] = { name = "Grotesque Horror" },
		-- Dawn of the Infinite
		[206140] = { name = "Coalesced Time" },
		[205158] = { name = "Spurlok, Timesworn Sentinel" },
		[206230] = { name = "Infinite Diversionist" },
		[205337] = { name = "Infinite Timebender" },
		[205212] = { name = "Infinite Keeper" },
		[208698] = { name = "Infinite Riftmage" },
		-- Tazavesh, the Veiled Market
		[178392] = { name = "Gatewarden Zo'mazz" },
		[179821] = { name = "Commander Zo'far" },
		[178171] = { name = "Stormforged Guardian" },
		[180433] = { name = "Wandering Pulsar" },
		[179842] = { name = "Commerce Enforcer" },
		[178165] = { name = "Coastwalker Goliath" },
		[179334] = { name = "Portalmancer Zo'dahh" },
		[180495] = { name = "Enraged Direhorn" },
		[179733] = { name = "Invigorating Fish Stick" },
		[179269] = { name = "Oasis Security" },
		[175576] = { name = "Containment Cell" },
		-- Vault of the Incarnates
		[198214] = { name = "Broodguardian Ziruss" },
		[191230] = { name = "Dragonspawn Flamebender" },
		[199549] = { name = "Flamesworn Herald" },
		[199547] = { name = "Frostforged Zealot" },
		[188026] = { name = "Frost Tomb" },
		[189234] = { name = "Frostbreath Arachnid" },
		-- Khaz Algar
		[220976] = { name = "Hollows Guard" },
		[220978] = { name = "Skeins Guard" },
		[220986] = { name = "Hollows Sentry" },
		[220988] = { name = "Skeins Sentry" },
		[215756] = { name = "Ascended Webwarden" },
		[220974] = { name = "Bazaar Guard" },
		[211816] = { name = "Bazaar Sentry" },
		[215755] = { name = "Ascended Overseer" },
		-- Shadowmoon Burial Grounds
		[75899] = { name = "Possessed Soul" },
		[75652] = { name = "Void Spawn" },
		[75979] = { name = "Exhumed Spirit" },
		[76518] = { name = "Ritual of Bones" },
		-- The Azure Vault
		[199368] = { name = "Hardened Crystal" },
		[191164] = { name = "Arcane Tender" },
		[196115] = { name = "Arcane Tender" },
		[187154] = { name = "Unstable Curator" },
		-- The Dawnbreaker
		[211261] = { name = "Ascendant Vis'coxria" },
		[214762] = { name = "Nightfall Commander" },
		[211263] = { name = "Deathscreamer Iken'tak" },
		[213885] = { name = "Nightfall Dark Architect" },
		[211262] = { name = "Ixkreten the Unbreakable" },
		-- Algeth'ar Academy
		[196044] = { name = "Unruly Textbook" },
		[197406] = { name = "Aggravated Skitterfly" },
		-- Castle Nathria
		[165483] = { name = "Court Hierarch" },
		[165762] = { name = "Soul Infuser" },
		[168156] = { name = "Remornia" },
		[175992] = { name = "Dutiful Attendant" },
		[166971] = { name = "Castellan Niklaus" },
		-- Spires of Ascension
		[168425] = { name = "Forsworn Annihilator" },
		[163524] = { name = "Kyrian Dark-Praetor" },
		[168658] = { name = "Forsworn Devastator" },
		-- Siege of Boralus
		[128969] = { name = "Ashvane Commander" },
		[129369] = { name = "Irontide Raider" },
		[136549] = { name = "Ashvane Cannoneer" },
		-- The Dread Pit
		[227632] = { name = "Venombite" },
		[227514] = { name = "Velo" },
		-- Priory of the Sacred Flame
		[217658] = { name = "Sir Braunpyke" },
		[211289] = { name = "Taener Duelmal" },
		[211290] = { name = "Elaena Emberlanz" },
		[211291] = { name = "Sergeant Shaynemail" },
		[212826] = { name = "Guard Captain Suleyman" },
		[212831] = { name = "Forge Master Damian" },
		[239833] = { name = "Elaena Emberlanz" },
		[239834] = { name = "Taener Duelmal" },
		[239836] = { name = "Sergeant Shaynemail" },
		[212827] = { name = "High Priest Aemya" },
		-- Sanctum of Domination
		[177889] = { name = "Mawforged Souljudge" },
		[180070] = { name = "Mawsworn Scryer" },
		[180474] = { name = "Soul Reaver" },
		[176974] = { name = "Soul Reaver" },
		[180864] = { name = "High Torturer" },
		[180323] = { name = "Fatespawn Monstrosity" },
		[179847] = { name = "Shadowsteel Horror" },
		[175861] = { name = "Glacial Spike" },
		-- The Nokhud Offensive
		[194897] = { name = "Stormsurge Totem" },
		[193373] = { name = "Nokhud Thunderfist" },
		[195696] = { name = "Primalist Thunderbeast" },
		[192791] = { name = "Nokhud Warspear" },
		[195877] = { name = "Risen Mystic" },
		-- Ara-Kara, City of Echoes
		[217531] = { name = "Ixin" },
		[217533] = { name = "Atik" },
		[218961] = { name = "Starved Crawler" },
		[218324] = { name = "Nakt" },
		[216340] = { name = "Sentry Stagshell" },
		[216364] = { name = "Blood Overseer" },
		-- The Necrotic Wake
		[165872] = { name = "Flesh Crafter" },
		[164702] = { name = "Carrion Worm" },
		[165824] = { name = "Nar'zudah" },
		[165197] = { name = "Skeletal Monstrosity" },
		-- Brackenhide Hollow
		[190426] = { name = "Decay Totem" },
		[186226] = { name = "Fetid Rotsinger" },
		[190381] = { name = "Rotburst Totem" },
		[185529] = { name = "Bracken Warscourge" },
		[195135] = { name = "Bracken Warscourge" },
		-- Black Rook Hold
		[98538] = { name = "Lady Velandras Ravencrest" },
		[98521] = { name = "Lord Etheldrin Ravencrest" },
		[101008] = { name = "Stinging Swarm" },
		-- Operation: Mechagon
		[150146] = { name = "Scrapbone Shaman" },
		[154758] = { name = "Toxic Monstrosity" },
		[150292] = { name = "Mechagon Cavalry" },
		[151325] = { name = "Alarm-o-Bot" },
		[144298] = { name = "Defense Bot Mk III" },
		[190174] = { name = "Hypnosis Bat" },
		[154744] = { name = "Toxic Monstrosity" },
		[150168] = { name = "Toxic Monstrosity" },
		[152033] = { name = "Inconspicuous Plant" },
		-- Sanguine Depths
		[162040] = { name = "Grand Overseer" },
		[171799] = { name = "Depths Warden" },
		[162099] = { name = "General Kaal" },
		[168882] = { name = "Fleeting Manifestation" },
		[166589] = { name = "Animated Weapon" },
		[165556] = { name = "Fleeting Manifestation" },
		[162133] = { name = "General Kaal" },
		-- The Vortex Pinnacle
		[52019] = { name = "Skyfall Nova" },
		[45930] = { name = "Minister of Air" },
		-- De Other Side
		[170483] = { name = "Atal'ai Deathwalker's Spirit" },
		[164873] = { name = "Runestag Elderhorn" },
		[167964] = { name = "4.RF-4.RF" },
		[171343] = { name = "Bladebeak Matriarch" },
		[168934] = { name = "Enraged Spirit" },
		-- Plaguefall
		[168310] = { name = "Plagueroc" },
		[164737] = { name = "Brood Ambusher" },
		[168747] = { name = "Venomfang" },
		[168153] = { name = "Plagueroc" },
		-- Aberrus, the Shadowed Crucible
		[202969] = { name = "Empty Recollection" },
		[203812] = { name = "Voice From Beyond" },
		[199703] = { name = "Magma Mystic" },
		[201288] = { name = "Sundered Champion" },
		-- Theater of Pain
		[170234] = { name = "Oppressive Banner" },
		[234443] = { name = "Jundies" },
		[169893] = { name = "Nefarious Darkspeaker" },
		[164506] = { name = "Ancient Captain" },
		[170850] = { name = "Raging Bloodhorn" },
		-- Liberation of Undermine
		[234557] = { name = "Support Rig" },
		[229619] = { name = "Blazing Fueldemon" },
		[238068] = { name = "Geargrinder Rager" },
		[233623] = { name = "Pyrotechnics" },
		-- Atal'Dazar
		[122970] = { name = "Shadowblade Stalker" },
		[122984] = { name = "Dazar'ai Colossus" },
		[129553] = { name = "Dinomancer Kish'o" },
		-- Waycrest Manor
		[135329] = { name = "Matron Bryndle" },
		[135365] = { name = "Matron Alma" },
		[131677] = { name = "Heartsbane Runeweaver" },
		[131812] = { name = "Heartsbane Soulcharmer" },
		-- Neltharion's Lair
		[92538] = { name = "Tarspitter Grub" },
		[97720] = { name = "Blightshard Skitter" },
		[94224] = { name = "Petrifying Totem" },
		[92610] = { name = "Understone Drummer" },
		[101075] = { name = "Wormspeaker Devout" },
		[98081] = { name = "Bellowing Idol" },
		-- Freehold
		[129559] = { name = "Cutwater Duelist" },
		[129529] = { name = "Blacktooth Scrapper" },
		[127106] = { name = "Irontide Officer" },
		-- Operation: Floodgate
		[230740] = { name = "Shreddinator 3000" },
		[230748] = { name = "Darkfuse Bloodwarper" },
		-- The Rookery
		[212793] = { name = "Void Ascendant" },
		[209801] = { name = "Quartermaster Koratite" },
		-- Black Rook Hold - Artifact Challenge
		[118489] = { name = "Corrupted Risen Soldier" },
		-- The Everbloom
		[85194] = { name = "Entanglement" },
		[84499] = { name = "Entanglement" },
		[84957] = { name = "Putrid Pyromancer" },
		[84767] = { name = "Twisted Abomination" },
		-- Halls of Atonement
		[165913] = { name = "Ghastly Parishioner" },
		[173729] = { name = "Manifestation of Pride" },
		[167876] = { name = "Inquisitor Sigar" },
		[164562] = { name = "Depraved Houndmaster" },
		-- Grim Batol
		[224609] = { name = "Twilight Destroyer" },
		[40357] = { name = "Invoked Shadowflame Spirit" },
		[224249] = { name = "Twilight Lavabender" },
		-- The Sinkhole
		[220742] = { name = "Guardian Tentacle" },
		-- Temple of the Jade Serpent
		[56792] = { name = "Figment of Doubt" },
		[59555] = { name = "Haunting Sha" },
		-- Return to Karazhan
		[114544] = { name = "Skeletal Usher" },
		[115765] = { name = "Abstract Nullifier" },
		[114626] = { name = "Forlorn Spirit" },
		[115388] = { name = "King" },
		-- Court of Stars
		[104251] = { name = "Duskwatch Sentry" },
		[104278] = { name = "Felbound Enforcer" },
		-- Nerub-ar Palace
		[223822] = { name = "Queen's Guard Re'zah" },
		[221945] = { name = "Forgotten Harbinger" },
		[218884] = { name = "Shattershell Scarab" },
		-- Mists of Tirna Scithe
		[166301] = { name = "Mistveil Stalker" },
		[164926] = { name = "Drust Boughbreaker" },
		[168988] = { name = "Overgrowth" },
		[167116] = { name = "Spinemaw Reaver" },
		-- Neltharus
		[193291] = { name = "Apex Blazewing" },
		[192788] = { name = "Qalashi Thaumaturge" },
		[189227] = { name = "Qalashi Hunter" },
		-- City of Threads
		[220401] = { name = "Pale Priest" },
		[216328] = { name = "Unstable Test Subject" },
		[220196] = { name = "Herald of Ansurek" },
		-- Torghast, Tower of the Damned
		[155831] = { name = "Mawsworn Soulbinder" },
		[152898] = { name = "Deadsoul Chorus" },
		[152905] = { name = "Tower Sentinel" },
		[176573] = { name = "Mawsworn Woebringer" },
		[151127] = { name = "Lord of Torment" },
		[155908] = { name = "Deathspeaker" },
		-- The MOTHERLODE!!
		[136139] = { name = "Mechanized Peacekeeper" },
		[130485] = { name = "Mechanized Peacekeeper" },
		-- Faronaar
		[115640] = { name = "Fuming Imp" },
		-- 9.0 Bastion Arena - Path of Ascension
		[175550] = { name = "Volatile Faerie" },
		-- Halls of Infusion
		[190368] = { name = "Flamecaller Aymi" },
		[190342] = { name = "Containment Apparatus" },
		-- Halls of Valor
		[101326] = { name = "Honored Ancestor" },
		[95834] = { name = "Valarjar Mystic" },
		-- Grimrail Depot
		[82597] = { name = "Grom'kar Captain" },
		[88163] = { name = "Grom'kar Cinderseer" },
		-- Throne of the Tides
		[212673] = { name = "Naz'jar Ravager" },
		-- The Stonevault
		[221979] = { name = "Void Bound Howler" },
		-- Darkflame Cleft
		[212412] = { name = "Sootsnout" },
		-- Cinderbrew Meadery
		[214697] = { name = "Chef Chewie" },
	},
	["high_hp"] = {
		-- Aberrus, the Shadowed Crucible
		[205622] = { name = "Krono Sandtongue" },
		[205623] = { name = "Drazos Blackwing" },
		[200840] = { name = "Flamebound Huntsman" },
		[200836] = { name = "Obsidian Guard" },
		[205618] = { name = "Thorak Greenscale" },
		[205619] = { name = "Sarek Cinderbreath" },
		[205620] = { name = "Malgosa Spellbinder" },
		-- Darkflame Cleft
		[211121] = { name = "Rank Overseer" },
		[212411] = { name = "Torchsnarl" },
		[220616] = { name = "Corridor Sleeper" },
		[208450] = { name = "Wandering Candle" },
		[210539] = { name = "Corridor Creeper" },
		-- Darkheart Thicket
		[99359] = { name = "Rotheart Keeper" },
		[95779] = { name = "Festerhide Grizzly" },
		[100531] = { name = "Bloodtainted Fury" },
		-- Freehold
		[129602] = { name = "Irontide Enforcer" },
		[130400] = { name = "Irontide Crusher" },
		[130404] = { name = "Vermin Trapper" },
		-- Dawn of the Infinite
		[208438] = { name = "Infinite Saboteur" },
		[199749] = { name = "Timestream Anomaly" },
		[207177] = { name = "Infinite Watchkeeper" },
		[208208] = { name = "Alliance Destroyer" },
		[203861] = { name = "Horde Destroyer" },
		[205152] = { name = "Lerai, Timesworn Maiden" },
		[208440] = { name = "Infinite Slayer" },
		[205804] = { name = "Risen Dragon" },
		[205435] = { name = "Epoch Ripper" },
		[201222] = { name = "Valow, Timesworn Keeper" },
		[206214] = { name = "Infinite Infiltrator" },
		-- The Rookery
		[212786] = { name = "Voidrider" },
		[212739] = { name = "Radiating Voidstone" },
		[214421] = { name = "Coalescing Void Diffuser" },
		-- The Necrotic Wake
		[164578] = { name = "Stitchflesh's Creation" },
		[165137] = { name = "Zolramus Gatekeeper" },
		[163620] = { name = "Rotspew" },
		[163621] = { name = "Goregrind" },
		[172981] = { name = "Kyrian Stitchwerk" },
		[165919] = { name = "Skeletal Marauder" },
		-- Waycrest Manor
		[131587] = { name = "Bewitched Captain" },
		[131858] = { name = "Thornguard" },
		[131586] = { name = "Banquet Steward" },
		-- Vault of the Incarnates
		[199233] = { name = "Flamescale Captain" },
		[190688] = { name = "Blazing Fiend" },
		[197595] = { name = "Earthwrought Smasher" },
		[190690] = { name = "Thundering Ravager" },
		[200943] = { name = "Electrified Colossal Stormfiend" },
		[191225] = { name = "Tarasek Earthreaver" },
		[190588] = { name = "Tectonic Crusher" },
		[196856] = { name = "Primal Stormsentry" },
		[193760] = { name = "Surging Ruiner" },
		[192767] = { name = "Primal Icebulk" },
		[198311] = { name = "Flamewrought Eradicator" },
		[198263] = { name = "Stalwart Broodwarden" },
		[197145] = { name = "Colossal Stormfiend" },
		[197146] = { name = "Qalashi Emissary" },
		[198308] = { name = "Frostwrought Dominator" },
		[188673] = { name = "Smoldering Colossus" },
		[198702] = { name = "Unstable Frost" },
		[198709] = { name = "Unstable Earth" },
		[198326] = { name = "Stormwrought Despoiler" },
		-- The MOTHERLODE!!
		[130435] = { name = "Addled Thug" },
		[136643] = { name = "Azerite Extractor" },
		[133430] = { name = "Venture Co. Mastermind" },
		[133463] = { name = "Venture Co. War Machine" },
		[134012] = { name = "Taskmaster Askari" },
		-- Iron Docks
		[83761] = { name = "Ogron Laborer" },
		[83578] = { name = "Ogron Laborer" },
		[83389] = { name = "Ironwing Flamespitter" },
		[81603] = { name = "Champion Druna" },
		[83026] = { name = "Siegemaster Olugar" },
		[87252] = { name = "Unruly Ogron" },
		[80805] = { name = "Makogg Emberblade" },
		[84520] = { name = "Pitwarden Gwarnok" },
		-- Temple of the Jade Serpent
		[200387] = { name = "Shambling Infester" },
		[65317] = { name = "Xiang" },
		[59873] = { name = "Corrupt Living Water" },
		[59553] = { name = "The Songbird Queen" },
		[59547] = { name = "Jiang" },
		-- City of Threads
		[221103] = { name = "Hulking Warshell" },
		[220730] = { name = "Royal Venomshell" },
		[224731] = { name = "Web Marauder" },
		[220197] = { name = "Royal Swarmguard" },
		[219983] = { name = "Eye of the Queen" },
		-- Uldaman: Legacy of Tyr
		[184020] = { name = "Hulking Berserker" },
		[184300] = { name = "Ebonstone Golem" },
		[184331] = { name = "Infinite Timereaver" },
		[184107] = { name = "Runic Protector" },
		-- Castle Nathria
		[165479] = { name = "Court Enforcer" },
		[174843] = { name = "Stoneborn Maitre D'" },
		[169924] = { name = "Veteran Stoneguard" },
		[165805] = { name = "Shade of Kael'thas" },
		-- Algeth'ar Academy
		[192333] = { name = "Alpha Eagle" },
		[197219] = { name = "Vile Lasher" },
		[196671] = { name = "Arcane Ravager" },
		-- Tazavesh, the Veiled Market
		[178139] = { name = "Murkbrine Shellcrusher" },
		[180429] = { name = "Adorned Starseer" },
		[180091] = { name = "Ancient Core Hound" },
		[177808] = { name = "Armored Overseer" },
		-- The Stonevault
		[210109] = { name = "Earth Infused Golem" },
		[213954] = { name = "Rock Smasher" },
		[213343] = { name = "Forge Loader" },
		[212765] = { name = "Void Bound Despoiler" },
		-- Ruby Life Pools
		[190034] = { name = "Blazebound Destroyer" },
		[188244] = { name = "Primal Juggernaut" },
		-- Ara-Kara, City of Echoes
		[228015] = { name = "Hulking Bloodguard" },
		[217039] = { name = "Nerubian Hauler" },
		[216338] = { name = "Hulking Bloodguard" },
		-- Theater of Pain
		[167532] = { name = "Heavin the Breaker" },
		[167538] = { name = "Dokigg the Brutalizer" },
		[163086] = { name = "Rancid Gasbag" },
		[167536] = { name = "Harugia the Bloodthirsty" },
		[164451] = { name = "Dessia the Decapitator" },
		[162763] = { name = "Soulforged Bonereaver" },
		[162744] = { name = "Nekthara the Mangler" },
		[167998] = { name = "Portal Guardian" },
		[167533] = { name = "Advent Nevermore" },
		[167534] = { name = "Rek the Hardened" },
		-- Return to Karazhan
		[114584] = { name = "Phantom Crew" },
		[115486] = { name = "Erudite Slayer" },
		[115757] = { name = "Wrathguard Flamebringer" },
		[115395] = { name = "Queen" },
		[114624] = { name = "Arcane Warden" },
		[114633] = { name = "Spectral Valet" },
		[114334] = { name = "Damaged Golem" },
		[115020] = { name = "Arcanid" },
		-- Sanctum of Domination
		[177891] = { name = "Mawforged Summoner" },
		[176523] = { name = "Painsmith Raznal" },
		-- Atal'Dazar
		[127757] = { name = "Reanimated Honor Guard" },
		[122971] = { name = "Dazar'ai Juggernaut" },
		[129552] = { name = "Monzumi" },
		-- Sanguine Depths
		[162038] = { name = "Regal Mistdancer" },
		[162047] = { name = "Insatiable Brute" },
		[162057] = { name = "Chamber Sentinel" },
		[168594] = { name = "Chamber Sentinel" },
		-- Halls of Valor
		[97068] = { name = "Storm Drake" },
		[96574] = { name = "Stormforged Sentinel" },
		[101637] = { name = "Valarjar Aspirant" },
		[99891] = { name = "Storm Drake" },
		-- The Nokhud Offensive
		[195928] = { name = "Soulharvester Duuren" },
		[195929] = { name = "Soulharvester Tumen" },
		[195930] = { name = "Soulharvester Mandakh" },
		[195265] = { name = "Stormcaller Arynga" },
		[194315] = { name = "Stormcaller Solongo" },
		[194316] = { name = "Stormcaller Zarii" },
		[194317] = { name = "Stormcaller Boroo" },
		[199595] = { name = "Nokhud Defender" },
		[199717] = { name = "Nokhud Defender" },
		[195927] = { name = "Soulharvester Galtmaa" },
		-- Grim Batol
		[39392] = { name = "Faceless Corruptor" },
		[224221] = { name = "Twilight Overseer" },
		[40166] = { name = "Molten Giant" },
		-- The Azure Vault
		[187240] = { name = "Drakonid Breaker" },
		[196117] = { name = "Crystal Thrasher" },
		[191739] = { name = "Scalebane Lieutenant" },
		-- Spires of Ascension
		[168318] = { name = "Forsworn Goliath" },
		[163520] = { name = "Forsworn Squad-Leader" },
		-- Mists of Tirna Scithe
		[166276] = { name = "Mistveil Guardian" },
		[173655] = { name = "Mistveil Matriarch" },
		[173714] = { name = "Mistveil Nightblossom" },
		[173720] = { name = "Mistveil Gorgegullet" },
		-- The Vortex Pinnacle
		[45917] = { name = "Cloud Prince" },
		[45919] = { name = "Young Storm Dragon" },
		[45928] = { name = "Executor of the Caliph" },
		[45915] = { name = "Armored Mistral" },
		-- Cinderbrew Meadery
		[210269] = { name = "Hired Muscle" },
		[223423] = { name = "Careless Hopgoblin" },
		[220946] = { name = "Venture Co. Honey Harvester" },
		-- Halls of Infusion
		[190403] = { name = "Glacial Proto-Dragon" },
		[190370] = { name = "Squallbringer Cyraz" },
		-- Brackenhide Hollow
		[186229] = { name = "Wilted Oak" },
		[187033] = { name = "Stinkbreath" },
		[186208] = { name = "Rotbow Stalker" },
		-- The Everbloom
		[81984] = { name = "Gnarlroot" },
		[83894] = { name = "Dulhu" },
		[86372] = { name = "Melded Berserker" },
		[84400] = { name = "Gnarled Ancient" },
		-- Sepulcher of the First Ones
		[185032] = { name = "Taskmaster Xy'pro" },
		[183033] = { name = "Grim Reflection" },
		[183495] = { name = "Twisted Worldeater" },
		-- Operation: Mechagon
		[150253] = { name = "Weaponized Crawler" },
		[144293] = { name = "Waste Processing Unit" },
		[151476] = { name = "Blastatron X-80" },
		[150160] = { name = "Scrapbone Bully" },
		[144296] = { name = "Spider Tank" },
		-- Plaguefall
		[164707] = { name = "Congealed Slime" },
		[165010] = { name = "Congealed Slime" },
		[163882] = { name = "Decaying Flesh Giant" },
		[168396] = { name = "Plaguebelcher" },
		-- Throne of the Tides
		[40925] = { name = "Tainted Sentry" },
		[40936] = { name = "Faceless Watcher" },
		[40577] = { name = "Naz'jar Sentinel" },
		[214140] = { name = "Naz'jar Sentinel" },
		-- Operation: Floodgate
		[231197] = { name = "Bubbles" },
		[229251] = { name = "Venture Co. Architect" },
		[231325] = { name = "Darkfuse Jumpstarter" },
		-- Black Rook Hold
		[98810] = { name = "Wrathguard Bladelord" },
		[98368] = { name = "Ghostly Protector" },
		[98243] = { name = "Soul-Torn Champion" },
		[98706] = { name = "Commander Shemdah'sohn" },
		[100485] = { name = "Soul-torn Vanguard" },
		-- Priory of the Sacred Flame
		[206704] = { name = "Ardent Paladin" },
		[206696] = { name = "Arathi Knight" },
		-- The Dawnbreaker
		[214761] = { name = "Nightfall Ritualist" },
		[211341] = { name = "Manifested Shadow" },
		[213932] = { name = "Sureki Militant" },
		-- Nerub-ar Palace
		[227300] = { name = "Bile-Soaked Spawn" },
		-- De Other Side
		[170480] = { name = "Atal'ai Deathwalker" },
		[171184] = { name = "Mythresh, Sky's Talons" },
		-- Halls of Atonement
		[165410] = { name = "High Adjudicator Aleez" },
		[167607] = { name = "Stoneborn Slasher" },
		[164557] = { name = "Shard of Halkias" },
		-- Torghast, Tower of the Damned
		[156245] = { name = "Grand Automaton" },
		[156244] = { name = "Winged Automaton" },
		-- Amirdrassil, the Dream's Hope
		[214012] = { name = "Dark Colossus" },
		-- Neltharion's Lair
		[102404] = { name = "Stoneclaw Grubmaster" },
		[113537] = { name = "Emberhusk Dominator" },
		[102287] = { name = "Emberhusk Dominator" },
		[91000] = { name = "Vileshard Hulk" },
		-- Siege of Boralus
		[135245] = { name = "Bilge Rat Demolisher" },
		[129374] = { name = "Scrimshaw Enforcer" },
		-- Neltharus
		[189466] = { name = "Irontorch Commander" },
		[189235] = { name = "Overseer Lahar" },
		-- Earthcrawl Mines
		[227573] = { name = "Anub'vir" },
		-- Court of Stars
		[104270] = { name = "Guardian Construct" },
		-- The Underrot
		[131436] = { name = "Chosen Blood Matron" },
		-- Grimrail Depot
		[80938] = { name = "Grom'kar Hulk" },
		[81212] = { name = "Grimrail Overseer" },
	}
}

Constants.Defaults = {
	dispels = {
		deathknight = {},
		demonhunter = {},
		druid = {},
		evoker = {},
		hunter = {},
		mage = {},
		monk = {},
		paladin = {},
		priest = {},
		rogue = {},
		shaman = {},
		warlock = {},
		warrior = {},
	}
}

return Constants