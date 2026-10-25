local unlocker, mint, addon = ...

local Actor = mint.Actor

addon.hunter = {}
addon.hunter.settings = {
	beastmastery = {},
	marksmanship = {},
	survival = {}
}

local bmData = {}

addon.hunter.data = {
	vars = {},
	beastmastery = bmData,
	bm = bmData,
	marksmanship = {},
	survival = {}
}

local bm 	= Actor.New({ spec = 1, class = "hunter"})
local mm 	= Actor.New({ spec = 2, class = "hunter"})
local surv 	= Actor.New({ spec = 3, class = "hunter"})

addon.hunter.beastmastery 	= bm
addon.hunter.beastMastery 	= bm
addon.hunter.bm 			= bm

addon.hunter.marksmanship 	= mm
addon.hunter.mm 			= mm

addon.hunter.survival		= surv
addon.hunter.surv			= surv