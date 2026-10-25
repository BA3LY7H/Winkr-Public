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
local settings 			= mint.Settings
local EventManager  	= mint.EventManager
local toggles 			= mint.data.toggles
local ClassDispels 		= Constants.ClassDispelMap

---@class Dispel
---@field my_dispels table
---@field events EventManager
---@field dispel_delay number
---@field scan_speed number
---@field scan_tick number
---@field GetNewDelay fun(self: Dispel): number
local Dispel = {}
Dispel.__index = Dispel

-- Create a new dispel utility
---@return Dispel
function Dispel:New()
	local self = setmetatable({}, Dispel)

	local char_class = UnitClassBase("player")
	local spec_index = GetSpecialization()
	local spec_id = GetSpecializationInfo(spec_index)
	
	self.my_dispels = ClassDispels[char_class] and ClassDispels[char_class][spec_id] or {}
	self.dispel_delay = mint.data.vars.dispel_delay
	self.scan_speed = 0.25
	self.scan_tick = 0

	-- Update spec dispels on talent updates
	self.events = EventManager:New()
	self.events:RegisterWoWEvent("PLAYER_TALENT_UPDATE", function()
		local char_class = UnitClassBase("player")
		local spec_index = GetSpecialization()
		local spec_id = GetSpecializationInfo(spec_index)

		self.my_dispels = ClassDispels[char_class] and ClassDispels[char_class][spec_id] or {}
	end)

	self.events:RegisterWoWEvent("PLAYER_SPECIALIZATION_CHANGED", function()
		local char_class = UnitClassBase("player")
		local spec_index = GetSpecialization()
		local spec_id = GetSpecializationInfo(spec_index)

		self.my_dispels = ClassDispels[char_class] and ClassDispels[char_class][spec_id] or {}
	end)

	-- self:RefreshDispelDB()

	-- local function refresh()
	-- 	self:RefreshDispelDB()
	-- end

	-- Interface:RegisterRefreshCallback(refresh)

	return self
end

-- Set a new delay for dispels
---@return number
function Dispel:GetNewDelay()
	local new = math.random(8, 25) / 10

	if new == self.dispel_delay then
		return self:GetNewDelay()
	end

	self.dispel_delay = new
	return self.dispel_delay
end

-- Refresh the database of dispel debuffs based on config values
-- function Dispel:RefreshDispelDB()
-- 	self.dispel_db = {}
-- 	local specName = Constants.SpecNameByID[mint.specId]

-- 	Settings:VerifyDefaults("dispels",
-- 	Constants.Defaults.dispels[mint.class])

-- 	local base_debuffs = Settings.profile.dispels
-- 	-- local base_debuffs = Interface.config:Read({ "Dispels", char_class, spec_id }, {})

-- 	if base_debuffs then
-- 		for _, debuff in ipairs(base_debuffs) do
-- 			-- local enabled = debuff.enabled
-- 			local enabled = true

-- 			-- If the config for this DEBUFF is enabled
-- 			if enabled then
-- 				-- Check to see if any of MY dispels are enabled for it
-- 				if self.my_dispels then
-- 					for _, spell in ipairs(self.my_dispels) do
-- 						local spell_id = spell.id
-- 						-- If my dispel is enabled for this debuff
-- 						if debuff[spell_id] then

-- 							-- Add this spell to the Dispel DB
-- 							if not self.dispel_db[spell_id] then
-- 								self.dispel_db[spell_id] = {}
-- 							end
							
-- 							-- If the spell is not already in the DB, add it
-- 							self.dispel_db[spell_id].spell_id = true
-- 						end
-- 					end
-- 				end
-- 			end
-- 		end
-- 	end
-- end

local function IsDispelEnabled(spell_id)
	for _, debuff in pairs(settings.profile.dispels) do
		if debuff.spell_id == spell_id and debuff.enabled then
			return true
		end
	end

	return false
end


function Dispel:Scan()
	-- We only want to loop over the friend manager at scan speed
	if GetTime() - self.scan_tick < self.scan_speed then
		return false
	end
	self.scan_tick = GetTime()

	FriendManager:Loop(function(friend)
		if friend.is_dead then return true end -- Break on dead friend

		local should_dispel = false
		local dispel_spell = nil

		local idx = 1
		while true do
			local auraData = C_UnitAuras.GetAuraDataByIndex(friend:GetPointer(), idx, "HARMFUL")
			if not auraData then break end
			idx = idx + 1

			local debuff_id = auraData.spellId
			local dispel_type = auraData.dispelName
			local duration = auraData.duration or 0
			local expiration = auraData.expirationTime or 0

			local debuff_data = Constants.TWWS2.debuff_map[debuff_id]
			if debuff_data and IsDispelEnabled(debuff_id) then
				local delay = mint.data.vars.dispel_delay or 0.5

				for _, dispel in ipairs(self.my_dispels) do

					-- Check if this dispel can even remove this type
					if dispel:CanDispelType(dispel_type) then

						-- Check condition
						if debuff_data and debuff_data.condition then
							-- If the condition is met, send the dispel
							if debuff_data.condition(friend) then
								local remains = expiration - GetTime()

								if duration == 0 or remains == 0 then
									if not friend.delay_checks then
										friend.delay_checks = {}
									end

									if not friend.delay_checks[debuff_id] then
										friend.delay_checks[debuff_id] = GetTime()
									end

									if GetTime() - friend.delay_checks[debuff_id] > delay then
										friend.delay_checks[debuff_id] = false
										should_dispel = true
										dispel_spell = dispel
										break
									end
								end

								local waited = duration - remains
								if waited > delay then
									should_dispel = true
									dispel_spell = dispel
									break
								end
							end
						end
					end
				end
			end
			if should_dispel then break end
		end

		if should_dispel and dispel_spell then
			mint.data.vars.dispel_delay = self:GetNewDelay()
			return dispel_spell:Cast(friend)
		end
	end)
end

return Dispel