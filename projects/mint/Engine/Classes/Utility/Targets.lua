local unlocker,
---@class mint
mint = ...

------------------------------
--- Locals
------------------------------
local Constants 		= mint.Constants
local UnitManager 		= mint.UnitManager
local ObjectManager 	= mint.ObjectManager
local FriendManager 	= mint.FriendManager
local Interface 		= mint.Interface
local Settings          = mint.Settings
local EventManager  	= mint.EventManager
local toggles 			= mint.data.toggles
local ClassDispels 		= Constants.ClassDispelMap
local player            = UnitManager:Get("player")
local target            = UnitManager:Get("target")
local none              = UnitManager:Get("none")

---@class SmartTarget
local SmartTarget = {}
SmartTarget.__index = SmartTarget

-- Create a new SmartTarget utility
---@return SmartTarget
function SmartTarget:New()
	local self = setmetatable({}, SmartTarget)

	return self
end

local SmartTargetUnit = UnitManager:CreateSmartUnit("SmartTarget", function(max_range)
    local best_unit = none
    local highest_hp = 0
    local range = max_range or 40

	ObjectManager.combat:loop(function(enemy)
        enemy:Update()
		if enemy:IsDead() or not enemy:GetExists() then return false end
        if enemy:GetDistance(player) > range then return false end
		if not player:HasLos(enemy) then return false end

        -- Priorities:
        -- 1. Priority targets (if we add a list later)
        -- 2. Highest absolute health (as requested)
        if enemy.health > highest_hp then
            best_unit = enemy
            highest_hp = enemy.health
        end

		return false -- continue loop
	end)

    return best_unit
end)

function SmartTarget:Acquire(range)
    -- Global Toggle Check
    if Settings.profile.general and Settings.profile.general.smart_target == false then
        return
    end

    -- Safety Guards
    if player:IsCasting() or player:IsChanneling() then return end

    -- Trigger acquisition if target is dead, friendly, or missing
    local targetValid = target:GetExists() and not target:IsDead() and UnitCanAttack("player", target:GetPointer())
    
    if not targetValid then
        local found = SmartTargetUnit:Get(range)
        if found and found:GetExists() and not found:Is(target) then
            local name = found.name
            if name == "Unknown" then
                name = UnitName(found:GetPointer()) or "Unknown Target"
            end
            
            mint.console.log("|cFF00FF00[SmartTarget]|r Snapping to:", name)
            
            if unlocker.name == "winkr" then
                winkr_SetNPC(found.guid)
                TargetUnit("npc")
            else
                TargetUnit(found:GetPointer())
            end
        end
    end
end

return SmartTarget
