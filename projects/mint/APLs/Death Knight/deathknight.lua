local unlocker,
---@class mint
mint,
addon = ...

mint.DebugMode = true

addon.deathknight = {}
addon.deathknight.settings = {
	["Blood"] = {},
	["Frost"] = {},
	["Unholy"] = {},
}
addon.deathknight.data = {
	vars = {},
	sequences = {},
	["Blood"] = {
		vars = {}
	},
	["Frost"] = {
		vars = {},
	},
	["Unholy"] = {
		vars = {}
	},
}
addon.deathknight.blood  = mint.Actor.New({ spec = 1, class = "deathknight"})
addon.deathknight.frost  = mint.Actor.New({ spec = 2, class = "deathknight"})
addon.deathknight.unholy = mint.Actor.New({ spec = 3, class = "deathknight"})