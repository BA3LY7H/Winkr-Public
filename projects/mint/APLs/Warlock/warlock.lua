local unlocker, mint, addon = ...

local Actor = mint.Actor

addon.warlock = {}
addon.warlock.settings = {
	generic = {}
}

addon.warlock.data = {
	vars = {},
	generic = {},
}

local gen 	= Actor.New({ spec = false, class = "warlock"})

addon.warlock.generic = gen
mint.console.log("Warlock Actor sync'd.")
