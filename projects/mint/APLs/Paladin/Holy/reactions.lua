local unlocker,
---@class mint
mint,
addon = ...

--! Tea Locals !--
local RaidEvents   	= mint.RaidEvents
local Reaction      = mint.Reactions
local UnitManager   = mint.UnitManager
local FriendManager = mint.FriendManager
local Item 			= mint.Item.New
local Spell         = mint.Spell.New
local target        = UnitManager:Get("target")
local player        = UnitManager:Get("player")
local none          = UnitManager:Get("none")
local bin 			= mint.bin

--! Addon Locals !--
local holy 			= addon.paladin.holy
local spells 		= addon.paladin.data["Holy"].spells
local items 		= addon.paladin.data["Holy"].items
local auras 		= addon.paladin.data["Holy"].auras
local targets 		= addon.paladin.data["Holy"].targets
local talents 		= addon.paladin.data["Holy"].talents

local thunderclap = Spell(448492)
Reaction:PreCast("paladin", "priory", thunderclap, spells.blessing_of_freedom, 2, function(unit)
    local best_unit = FriendManager:GetLowest(false, function(friend)
        if friend.role == "TANK" then
            return false
        end
        return true
    end)

    return best_unit
end, "Casts Blessing of Freedom on an ally to make them immune to Thunderclap damage.")

Reaction:PreCast("paladin", "priory", thunderclap, spells.blessing_of_sacrifice, 2, function(unit)
    local best_unit = FriendManager:GetLowest(60, function(friend)
        if friend.role == "TANK" then
            return false
        end
        return true
    end)

    return best_unit
end, "Casts Blessing of Sacrifice on an ally under 60% HP to help them survive Thunderclap.")

local sacred_toll = Spell(448791)
Reaction:PreCast("paladin", "priory", sacred_toll, spells.blessing_of_sacrifice, 1.5, function(unit)
    local best_unit = FriendManager:GetLowest(60, function(friend)
        if friend.role == "TANK" then
            return false
        end
        return true
    end)

    return best_unit
end, "Casts Blessing of Sacrifice on an ally under 60% HP to help them survive Sacred Toll.")

-- BoF someone inside castigator's shield

