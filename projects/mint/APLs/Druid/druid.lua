local unlocker,
---@class mint
mint,
addon = ...

mint.DebugMode = true

addon.druid = {}

addon.druid.settings = {
    ["Restoration"] = {},
    ["Feral"] = {},
    ["Balance"] = {},
    ["Guardian"] = {}
}

addon.druid.resto 		= mint.Actor.New({ spec = 4, class = "druid"})
addon.druid.guardian 	= mint.Actor.New({ spec = 3, class = "druid"})
addon.druid.feral 		= mint.Actor.New({ spec = 2, class = "druid"})
addon.druid.balance 	= mint.Actor.New({ spec = 1, class = "druid"})