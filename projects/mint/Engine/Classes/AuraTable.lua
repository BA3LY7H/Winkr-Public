-- local unlocker,
-- ---@class mint
-- mint = ...

-- ----------------------------
-- --- Constants & Locals
-- ----------------------------
-- local CreateFromAuraData = mint.Aura.CreateFromAuraData
-- local GetAuraDataByAuraInstanceID = C_UnitAuras.GetAuraDataByAuraInstanceID
-- local UnitGUID = UnitGUID

-- ---@class AuraTable
-- ---@field unit Unit
-- ---@field guid string
-- ---@field auras table
-- ---@field player_buffs table
-- ---@field player_debuffs table
-- ---@field buffs table
-- ---@field debuffs table
-- local AuraTable = {}
-- AuraTable.__index = AuraTable

-- -- Constructor
-- function AuraTable.New(unit)
--     local instance = setmetatable({}, AuraTable)

-- 	instance.unit = unit
--     instance.guid = unit.guid
--     instance.auras = {}
-- 	instance.player_buffs = {}
-- 	instance.player_debuffs = {}
--     instance.buffs = {}
--     instance.debuffs = {}

-- 	instance.populated = false

--     return instance
-- end

-- -- Update the aura table based on update info
-- ---@param UnitID string
-- ---@param updateInfo UnitAuraUpdateInfo
-- function AuraTable:Update(UnitID, updateInfo)
-- 	local playerGUID = UnitGUID("player")

-- 	if (not updateInfo)
-- 	or (updateInfo and updateInfo.isFullUpdate) then
-- 		-- Track Player Buffs
-- 		AuraUtil.ForEachAura(UnitID, "PLAYER|HELPFUL", nil,
-- 			function(aura)
-- 				if aura and aura.auraInstanceID then
-- 					local new_aura = CreateFromAuraData(aura)
-- 					self.player_buffs[aura.auraInstanceID] = new_aura
-- 				end
-- 			end,
-- 		true)
-- 		-- Track Player Debuffs
-- 		AuraUtil.ForEachAura(UnitID, "PLAYER|HARMFUL", nil,
-- 			function(aura)
-- 				if aura and aura.auraInstanceID then
-- 					local new_aura = CreateFromAuraData(aura)
-- 					self.player_debuffs[aura.auraInstanceID] = new_aura
-- 				end
-- 			end,
-- 		true)

-- 		-- Track All Debuffs
-- 		AuraUtil.ForEachAura(UnitID, "HARMFUL", nil,
-- 			function(aura)
-- 				if aura and aura.auraInstanceID then
-- 					local new_aura = CreateFromAuraData(aura)
-- 					self.debuffs[aura.auraInstanceID] = new_aura
-- 				end
-- 			end,
-- 		true)

-- 		-- Track All Buffs
-- 		AuraUtil.ForEachAura(UnitID, "HELPFUL", nil,
-- 			function(aura)
-- 				if aura and aura.auraInstanceID then
-- 					local new_aura = CreateFromAuraData(aura)
-- 					self.buffs[aura.auraInstanceID] = new_aura
-- 				end
-- 			end,
-- 		true)
-- 	end

-- 	if updateInfo and updateInfo.addedAuras then
-- 		for _, aura in pairs(updateInfo.addedAuras) do
-- 			if aura and aura.auraInstanceID and aura.sourceUnit and (UnitGUID(aura.sourceUnit) == playerGUID) then
-- 				if aura.isHelpful then
-- 					local new_aura = CreateFromAuraData(aura)
-- 					self.player_buffs[aura.auraInstanceID] = new_aura
-- 				elseif aura.isHarmful then
-- 					local new_aura = CreateFromAuraData(aura)
-- 					self.player_debuffs[aura.auraInstanceID] = new_aura
-- 				end
-- 			end

-- 			if aura and aura.auraInstanceID then
-- 				if aura.isHelpful then
-- 					local new_aura = CreateFromAuraData(aura)
-- 					self.buffs[aura.auraInstanceID] = new_aura
-- 				elseif aura.isHarmful then
-- 					local new_aura = CreateFromAuraData(aura)
-- 					self.debuffs[aura.auraInstanceID] = new_aura
-- 				end
-- 			end
-- 		end
-- 	end

-- 	if updateInfo and updateInfo.updatedAuraInstanceIDs then
-- 		for _, auraInstanceID in pairs(updateInfo.updatedAuraInstanceIDs) do
-- 			local aura = GetAuraDataByAuraInstanceID(UnitID, auraInstanceID)

-- 			if aura and aura.auraInstanceID and aura.sourceUnit and (UnitGUID(aura.sourceUnit) == playerGUID) then
-- 				if aura.isHelpful then
-- 					local new_aura = CreateFromAuraData(aura)
-- 					self.player_buffs[aura.auraInstanceID] = new_aura
-- 				elseif aura.isHarmful then
-- 					local new_aura = CreateFromAuraData(aura)
-- 					self.player_debuffs[aura.auraInstanceID] = new_aura
-- 				end
-- 			end

-- 			if aura and aura.auraInstanceID then
-- 				if aura.isHelpful then
-- 					local new_aura = CreateFromAuraData(aura)
-- 					self.buffs[aura.auraInstanceID] = new_aura
-- 				elseif aura.isHarmful then
-- 					local new_aura = CreateFromAuraData(aura)
-- 					self.debuffs[aura.auraInstanceID] = new_aura
-- 				end
-- 			end
-- 		end
-- 	end

-- 	if updateInfo and updateInfo.removedAuraInstanceIDs then
-- 		for _, auraInstanceID in pairs(updateInfo.removedAuraInstanceIDs) do
			
-- 			for id, aura in pairs(self.player_buffs) do
-- 				if auraInstanceID == aura.auraInstanceID then
-- 					self.player_buffs[id] = nil
-- 				end
-- 			end
-- 			for id, aura in pairs(self.player_debuffs) do
-- 				if auraInstanceID == aura.auraInstanceID then
-- 					self.player_debuffs[id] = nil
-- 				end
-- 			end
-- 			for id, aura in pairs(self.buffs) do
-- 				if auraInstanceID == aura.auraInstanceID then
-- 					self.buffs[id] = nil
-- 				end
-- 			end
-- 			for id, aura in pairs(self.debuffs) do
-- 				if auraInstanceID == aura.auraInstanceID then
-- 					self.debuffs[id] = nil
-- 				end
-- 			end
-- 		end
-- 	end
-- end

-- -- Update all buffs a unit has
-- function AuraTable:UpdateBuffs()
-- 	AuraUtil.ForEachAura(self.unit:GetPointer(), "HELPFUL", nil, function(aura)
-- 		if aura and aura.auraInstanceID then
-- 			local new_aura = CreateFromAuraData(aura)
-- 			self.buffs[aura.auraInstanceID] = new_aura
-- 		end
-- 	end, true)
-- end

-- -- Update all buffs a unit has from the player
-- function AuraTable:UpdatePlayerBuffs()
-- 	AuraUtil.ForEachAura(self.unit:GetPointer(), "PLAYER|HELPFUL", nil, function(aura)
-- 		if aura and aura.auraInstanceID then
-- 			local new_aura = CreateFromAuraData(aura)
-- 			self.player_buffs[aura.auraInstanceID] = new_aura
-- 		end
-- 	end, true)
-- end

-- -- Update all debuffs a unit has
-- function AuraTable:UpdateDebuffs()
-- 	AuraUtil.ForEachAura(self.unit:GetPointer(), "HARMFUL", nil, function(aura)
-- 		if aura and aura.auraInstanceID then
-- 			local new_aura = CreateFromAuraData(aura)
-- 			self.debuffs[aura.auraInstanceID] = new_aura
-- 		end
-- 	end, true)
-- end

-- -- Update all debuffs a unit has from the player
-- function AuraTable:UpdatePlayerDebuffs()
-- 	AuraUtil.ForEachAura(self.unit:GetPointer(), "PLAYER|HARMFUL", nil, function(aura)
-- 		if aura and aura.auraInstanceID then
-- 			local new_aura = CreateFromAuraData(aura)
-- 			self.player_debuffs[aura.auraInstanceID] = new_aura
-- 		end
-- 	end, true)
-- end

-- function AuraTable:Populate()
-- 	-- Clear current tables
-- 	self.player_buffs = {}
-- 	self.player_debuffs = {}
-- 	self.buffs = {}
-- 	self.debuffs = {}

-- 	-- Populate tables
-- 	self:UpdateBuffs()
-- 	self:UpdatePlayerBuffs()
-- 	self:UpdateDebuffs()
-- 	self:UpdatePlayerDebuffs()
-- end

-- function AuraTable:GetBuffs(playerOnly)
-- 	if not self.populated then
-- 		self.populated = true
-- 		self:Populate()
-- 	end

-- 	-- Check to make sure "target" or "focus" didn't change etc
-- 	if self.unit.guid ~= self.guid then
-- 		self.guid = self.unit.guid
-- 		self:Populate()
-- 	end

-- 	return playerOnly and self.player_buffs or self.buffs
-- end

-- function AuraTable:GetDebuffs(playerOnly)
-- 	if not self.populated then
-- 		self.populated = true
-- 		self:Populate()
-- 	end

-- 	-- Check to make sure "target" or "focus" didn't change etc
-- 	if self.unit.guid ~= self.guid then
-- 		self.guid = self.unit.guid
-- 		self:Populate()
-- 	end

-- 	return playerOnly and self.player_debuffs or self.debuffs
-- end

-- -- Check if a unit has a specific buff
-- ---@param spell Spell
-- ---@param playerOnly boolean
-- function AuraTable:FindBuff(spell, playerOnly)
-- 	 -- We do this because we want to ensure the buffs are updated
-- 	 -- ie: if a unit got a buff before player rendered them
-- 	local auras = self:GetBuffs(playerOnly)

	
-- end

-- return AuraTable