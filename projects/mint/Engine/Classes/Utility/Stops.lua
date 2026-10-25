local unlocker,
---@class mint
mint = ...

------------------------------
--- Locals
------------------------------
local Constants 		= mint.Constants
local UnitManager 		= mint.UnitManager
local ObjectManager 	= mint.ObjectManager
local Interface 		= mint.Interface
local toggles 			= mint.data.toggles
local settings 			= mint.Settings
local ClassStops 		= Constants.ClassStopMap
local ClassKicks 		= Constants.ClassKickMap

local function IsKickEnabled(spell_id)
	for _, spell_obj in pairs(settings.profile.kicks) do
		if spell_obj.spell_id == spell_id and spell_obj.enabled then
			return true
		end
	end

	return false
end

---@class Stop
---@field my_stops table
---@field kick_target Unit
---@field my_kick Spell
local Stop = {}
Stop.__index = Stop

-- Create a new stop utility
---@return Stop
function Stop:New()
	local self = setmetatable({}, Stop)

	local char_class = UnitClassBase("player")
	local spec_index = GetSpecialization()
	local spec_id = GetSpecializationInfo(spec_index)
	
	self.my_kick = ClassKicks[char_class] and ClassKicks[char_class][spec_id] or mint.Spell.New(12345)
	self.my_stops = ClassStops[char_class] and ClassStops[char_class][spec_id] or {}

	local function refresh()

	end

	Interface:RegisterRefreshCallback(refresh)

	-- We want a kick and stop target, so we can differentiate and assign cost?
	self.kick_target = UnitManager:CreateSmartUnit("smart_kick", function()
		local best_kick = nil
		local lowest_ttc = math.huge
		
		if not mint.data.toggles.kicks then
			return UnitManager:Get("none")
		end
	
		ObjectManager.combat:loop(function(enemy)
			if enemy.dead then return false end
			if not enemy:IsCastingOrChanneling() then return false end
			if not enemy:IsKickable() then return false end
			if not IsKickEnabled(enemy:GetCastSpellID()) then return false end
			if not self.my_kick:IsInRange(enemy) then return false end
			if not UnitManager:Get("player"):HasLos(enemy) then return false end

			local TTC = enemy:TimeToCast()
			if TTC < lowest_ttc then
				lowest_ttc = TTC
				best_kick = enemy
			end

			return false
		end)
	
		if best_kick == nil then
			return UnitManager:Get("none")
		end
	
		return best_kick
	end)

	local cast_percent
	local channel_time

	local function NewPercent()
		local new = math.random(40, 80)

		if new == cast_percent then
			return NewPercent()
		end

		cast_percent = new
		return cast_percent
	end

	local function NewChannelTime()
		local new = math.random(85, 95)

		new = new / 100

		if new == channel_time then
			return NewChannelTime()
		end

		channel_time = new
		return channel_time
	end

	cast_percent = NewPercent()
	channel_time = NewChannelTime()

	self.my_kick:AddCallback("kick", function(spell)
		if not mint.data.toggles.kicks then return false end
		if not self.kick_target:GetExists() then return false end
	
		if self.kick_target:IsCasting() then
			if self.kick_target:GetCastPercent() >= cast_percent then
				if spell:Cast(self.kick_target) then
					cast_percent = NewPercent()
					return true
				end
			end
		end
	
		if self.kick_target:IsChanneling() then
			if self.kick_target:GetTimeSinceStartedCast() >= channel_time then
				if spell:Cast(self.kick_target) then
					channel_time = NewChannelTime()
					return true
				end
			end
		end
	
		return false
	end)

	return self
end


function Stop:Scan()
	self.my_kick("kick")
end

return Stop