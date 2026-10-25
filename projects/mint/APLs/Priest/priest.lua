local unlocker,
---@class mint
mint,
addon = ...

---@class Actor
local Actor = mint.Actor

addon.priest = {}
addon.priest.settings = {
	["Discipline"] = {},
	["Holy"] = {},
	["Shadow"] = {},
}
addon.priest.data = {
	vars = {},
	sequences = {},
	["Discipline"] = {
		vars = {}
	},
	["Holy"] = {
		vars = {},
	},
	["Shadow"] = {
		vars = {}
	},
}
addon.priest.discipline	= Actor.New({ spec = 1, class = "priest"})
addon.priest.holy  		= Actor.New({ spec = 2, class = "priest"})
addon.priest.shadow 	= Actor.New({ spec = 3, class = "priest"})