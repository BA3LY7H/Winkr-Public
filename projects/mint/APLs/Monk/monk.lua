local unlocker,
---@class mint
mint,
addon = ...

mint.DebugMode = true

addon.monk = {}
addon.monk.settings = {
	["Brewmaster"] = {},
	["Mistweaver"] = {},
	["Windwalker"] = {},
}
addon.monk.data = {
	vars = {},
	sequences = {},
	in_flight = {}
}

addon.monk.brewmaster  	= mint.Actor.New({ spec = 1, class = "monk"})
addon.monk.mistweaver 	= mint.Actor.New({ spec = 2, class = "monk"})
addon.monk.windwalker 	= mint.Actor.New({ spec = 3, class = "monk"})