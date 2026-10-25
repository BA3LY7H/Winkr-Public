local unlocker,
---@class mint
mint,
addon = ...

mint.DebugMode = true

addon.mage = {}
addon.mage.settings = {
	["Arcane"] = {},
	["Fire"] = {},
	["Frost"] = {},
}
addon.mage.data = {
	vars = {},
	sequences = {},
	in_flight = {},
	["Arcane"] = {
		vars = {}
	},
	["Fire"] = {
		vars = {},
		sequences = {}
	},
	["Frost"] = {
		vars = {}
	},
}

addon.mage.arcane  	= mint.Actor.New({ spec = 1, class = "mage"})
addon.mage.fire 	= mint.Actor.New({ spec = 2, class = "mage"})
addon.mage.frost 	= mint.Actor.New({ spec = 3, class = "mage"})