local unlocker,
---@class mint
mint,
addon = ...

mint.DebugMode = true

addon.paladin = {}
addon.paladin.settings = {
	["Protection"] = {},
	["Holy"] = {},
	["Retribution"] = {},
}
addon.paladin.data = {
	vars = {},
	sequences = {},
	["Protection"] = {
		vars = {}
	},
	["Holy"] = {
		vars = {},
	},
	["Retribution"] = {
		vars = {}
	},
}
addon.paladin.holy 		  = mint.Actor.New({ spec = 1, class = "paladin"})
addon.paladin.protection  = mint.Actor.New({ spec = 2, class = "paladin"})
addon.paladin.retribution = mint.Actor.New({ spec = 3, class = "paladin"})