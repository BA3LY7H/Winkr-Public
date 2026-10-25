local unlocker, mint, addon = ...

local Actor = mint.Actor

addon.warrior = {}
addon.warrior.settings = {
	generic = {}
}

addon.warrior.data = {
	vars = {},
	generic = {},
}

local gen 	= Actor.New({ spec = false, class = "warrior"})

addon.warrior.generic = gen
