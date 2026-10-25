local unlocker,
---@class mint
mint,
addon = ...

---@class Actor
local Actor = mint.Actor

addon.shaman = {}
addon.shaman.settings = {
	["Elemental"] = {},
	["Enhancement"] = {},
	["Restoration"] = {},
}
addon.shaman.data = {
	vars = {},
	["Elemental"] = {
		vars = {
			fusion = {},
		},
		sequences = {},
	},
	["Enhancement"] = {
		vars = {},
		sequences = {},
	},
	["Restoration"] = {
		vars = {},
		sequences = {},
	},
}
addon.shaman.elemental		= Actor.New({ spec = 1, class = "shaman"})
addon.shaman.enhancement  	= Actor.New({ spec = 2, class = "shaman"})
addon.shaman.restoration 	= Actor.New({ spec = 3, class = "shaman"})