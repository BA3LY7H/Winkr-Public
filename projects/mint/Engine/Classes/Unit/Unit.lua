local unlocker,
---@class mint
mint = ...

----------------------------
--- Localize WoW API
----------------------------

-- Removed localized WoW APIs to ensure Winkr-hooked globals are used at runtime.

---@class Unit
---@field isOMUnit boolean
---@field pointer string
---@field guid string
---@field name string
---@field class string
---@field timers table
---@field cache Cache
---@field auratable AuraTable
---@field auras table
---@field buffs table
---@field debuffs table
---@field creature_type string
---@field health number
---@field max_health number
---@field heal_absorbs number
---@field hp number
---@field role string
---@field is_dead boolean
---@field in_range boolean
---@field can_assist boolean
---@field can_attack boolean
---@field id number
---@field level number
---@field reaction number
---@field race string
local Unit = {}
Unit.__index = Unit


-- Constructor
---@param token string
---@return Unit
function Unit:Create(token, isOMUnit)
	local self = setmetatable({}, Unit)

	if type(token) ~= "string" or strlen(token) == 0 then
		error("Unit:Create(token) - token must be a string with length > 0")
		return self
	end


	self.isOMUnit = isOMUnit or false
	self.pointer = token
	-- If token looks like a GUID (contains "-"), use it directly; otherwise resolve via UnitGUID
	self.guid = (type(token) == "string" and token:find("-")) and token or UnitGUID(token) or ""
	self.name = "Unknown"
	self.class = "Unknown"

	self.timers = {}
	self.cache = mint.Cache:New()

	self.auras = {}
	self.buffs = {}
	self.debuffs = {}

	self.id = mint.ObjectID(self:GetPointer())

	self.last_combat_event_time = 0

	self:Update()

	-- self.auratable = mint.AuraTable.New(self)

	return self
end

-- Updates the Unit's information
function Unit:Update()
	local pointer = self:GetPointer()

	-- For winkr units that don't map to standard tokens, use the NPC hack
	-- to temporarily make WoW APIs work on this unit
	if unlocker.name == "winkr" and type(self.guid) == "string" and #self.guid > 5 then
		local isToken = pointer and type(pointer) == "string" and not string.find(pointer, "-")
		if not isToken then
			winkr_SetNPC(self.guid)
			pointer = "npc"
		end
	end

	if self.name == "Unknown" then
		self.name = UnitName(pointer) or "Unknown"
	end

	if self.class == "Unknown" then
		self.class = UnitClass(pointer) or "Unknown"
	end

	self.creature_type = UnitCreatureType(pointer)

	self.health = UnitHealth(pointer) or 0

	self.max_health = UnitHealthMax(pointer) or 0

	self.heal_absorbs = UnitGetTotalHealAbsorbs(pointer) or 0

	self.absorbs = UnitGetTotalAbsorbs(pointer) or 0

	self.realized_health = (self.health or 0) - (self.heal_absorbs or 0)

	self.heal_prediction = UnitGetIncomingHeals(pointer) or 0

	if self.max_health and self.max_health > 0 then
		self.hp = self.health / self.max_health * 100
		self.realized_hp = ((self.health + self.absorbs) - self.heal_absorbs) / self.max_health * 100
	else
		self.hp = 100
		self.realized_hp = 100
	end

	self.role = UnitGroupRolesAssigned(pointer)

	self.is_dead = UnitIsDeadOrGhost(pointer)
	if self.is_dead == nil then self.is_dead = false end
	self.dead = self.is_dead

	self.in_range = self:RangeCheck()

	self.can_assist = UnitCanAssist("player", pointer)

	self.can_attack = UnitCanAttack("player", pointer)
	if self.can_attack == nil then self.can_attack = false end

	-- For winkr OM units without tokens, try to detect attackability from reaction
	if self.isOMUnit and not self.can_attack then
		local reaction = UnitReaction(pointer, "player")
		if reaction and reaction <= 4 then
			self.can_attack = true
		end
	end

	-- Combat detection for OM units
	if self.isOMUnit then
		-- Check HP, Threat, or if the unit is targeting the player
		local has_threat = UnitThreatSituation("player", pointer)
		if self.can_attack and ( (self.hp and self.hp < 100) or (has_threat and has_threat > 0) ) then
			self.in_combat = true
			self.last_combat_event_time = GetTime()
		else
			self.in_combat = false
		end
	end

	self.level = UnitLevel(pointer)

	self.race = select(2, UnitRace(pointer))

	self.reaction = UnitReaction(pointer, "player") or 10

	self.exists = self:GetExists()

	self.alive = not (self.is_dead or false)
end

function Unit:FindOwnBuffByID(spell_id)
	local spell_id = type(spell_id) == "table" and spell_id.id or spell_id
	local pointer = self:GetPointer()

	-- Try to use the player-specific API first for efficiency if it exists
	if UnitIsUnit(pointer, "player") and C_UnitAuras.GetPlayerAuraBySpellID then
		local aura_data = C_UnitAuras.GetPlayerAuraBySpellID(spell_id)
		if aura_data then
			return mint.Aura.CreateFromAuraData(aura_data)
		end
	end

	-- Robust fallback: use FindDebuffByID/FindBuffByID with playerOnly filter
	local aura = self:FindDebuffByID(spell_id, true)
	if aura:Active() then return aura end

	aura = self:FindBuffByID(spell_id, true)
	if aura:Active() then return aura end

	return mint.Aura.CreateBlank()
end

--- Find an aura by spell ID, scanning by index
--- @param spell_id number|table
--- @param filter string -- e.g. "HELPFUL" or "HARMFUL|PLAYER"
--- @return Aura
function Unit:FindAuraByID(spell_id, filter)
	local spell_id_val = type(spell_id) == "table" and spell_id.id or spell_id
	local pointer = self:GetPointer()
	local filter_str = filter or "HELPFUL"

	-- Build a lookup table if original spell_id was a table of IDs
	local target_ids = {}
	if type(spell_id) == "table" and spell_id.id == nil then
		for _, id in pairs(spell_id) do
			target_ids[type(id) == "table" and id.id or id] = true
		end
	else
		target_ids[spell_id_val] = true
	end

	-- Scan by index — C_UnitAuras hooks automatically redirect GUID units
	-- to winkr_UnitAuras bridge data (see Wrappers.lua aura hook system)
	for i = 1, 40 do
		local aura_data = C_UnitAuras.GetAuraDataByIndex(pointer, i, filter_str)
		if not aura_data then break end
		if target_ids[aura_data.spellId] then
			return mint.Aura.CreateFromAuraData(aura_data)
		end
	end

	return mint.Aura.CreateBlank()
end

--- Find a buff by its spell ID
--- @param spell_id number|table
--- @param playerOnly boolean?
--- @return Aura
function Unit:FindBuffByID(spell_id, playerOnly)
	local filter = "HELPFUL" .. (playerOnly and "|PLAYER" or "")
	return self:FindAuraByID(spell_id, filter)
end

--- Find a debuff by its spell ID
--- @param spell_id number|table
--- @param playerOnly boolean?
--- @return Aura
function Unit:FindDebuffByID(spell_id, playerOnly)
	local filter = "HARMFUL" .. (playerOnly and "|PLAYER" or "")
	return self:FindAuraByID(spell_id, filter)
end

local dumpTimer = 0

function Unit:FindBuff(spell_id, playerOnly)
	local spell_id = type(spell_id) == "table" and spell_id.id or spell_id
	local name = C_Spell.GetSpellName(spell_id)
	if not name then return mint.Aura.CreateBlank() end

	-- if self.auras[name] then
	-- 	if self.auras[name]:Remains() > 0 then
	-- 		return self.auras[name]
	-- 	else
	-- 		self.auras[name] = nil
	-- 	end
	-- end

	local filter_str = "HELPFUL" .. (playerOnly and "|PLAYER" or "")

	local aura_data = C_UnitAuras.GetAuraDataBySpellName(self:GetPointer(), name, filter_str)

	if not aura_data then
		return mint.Aura.CreateBlank()
	end

	local aura = mint.Aura.CreateFromAuraData(aura_data)

	-- self.auras[name] = aura

	return aura
end

-- Find any buff from a list of spell identifiers
---@param spell_list List
---@param playerOnly boolean?
---@return Aura
function Unit:FindAnyBuff(spell_list, playerOnly)
	return spell_list:reduce(function(acc, cur)
		local aura = self:FindBuff(cur, playerOnly)
		if aura:Active() then
			return aura, true
		end
		return acc, false
	end, mint.Aura.CreateBlank())
end

-- Find any buff from a list of spell identifiers, using ID. Only works on player.
---@param spell_list List
---@return Aura
function Unit:FindAnyBuffByID(spell_list)
	return spell_list:reduce(function(acc, cur)
		local aura = self:FindOwnBuffByID(cur.id)
		if aura:Active() then
			return aura, true
		end
		return acc, false
	end, mint.Aura.CreateBlank())
end

function Unit:FindDebuff(spell_id, playerOnly)
	local spell_id = type(spell_id) == "table" and spell_id.id or spell_id

	local name = C_Spell.GetSpellName(spell_id)
	if not name then return mint.Aura.CreateBlank() end

	-- if self.auras[name] then
	-- 	if self.auras[name]:Remains() > 0 then
	-- 		return self.auras[name]
	-- 	else
	-- 		self.auras[name] = nil
	-- 	end
	-- end

	local filter_str = "HARMFUL" .. (playerOnly and "|PLAYER" or "")

	local aura_data = C_UnitAuras.GetAuraDataBySpellName(self:GetPointer(), name, filter_str)

	if not aura_data then
		return mint.Aura.CreateBlank()
	end

	local aura = mint.Aura.CreateFromAuraData(aura_data)

	-- self.auras[name] = aura

	return aura
end

-- Find any debuff from a list of spell identifiers
---@param spell_list List
---@param playerOnly boolean?
---@return Aura
function Unit:FindAnyDebuff(spell_list, playerOnly)
	return spell_list:reduce(function(acc, cur)
		local aura = self:FindDebuff(cur, playerOnly)
		if aura:Active() then
			return aura, true
		end
		return acc, false
	end, mint.Aura.CreateBlank())
end

-- Returns if the unit has a spellstealable aura
function Unit:HasSpellstealAura()
	return self:FindAnyBuff(mint.Constants.TWWS2.spellsteal_spells):Active()
end

-- Returns if the unit has a purgable aura
function Unit:HasPurgeAura()
	return self:FindAnyBuff(mint.Constants.TWWS3.purgeList):Active()
end

-- Returns if the unit has a soothable aura
function Unit:HasSootheAura()
	return self:FindAnyBuff(mint.Constants.TWWS3.sootheList):Active()
end

--- Find the longest-remaining active buff from a list.
--- @param spellList List   	-- List of spell IDs
--- @param playerOnly boolean? 	-- If true, only consider buffs cast by the player
--- @return Aura              	-- The Aura with the longest remaining time, or a blank Aura if none are active
function Unit:FindLongestBuffFromList(spellList, playerOnly)
	return spellList:reduce(function(bestAura, cur)
        local aura = self:FindBuff(cur, playerOnly)
        if aura:Active() then
            -- Compute "effective" remains (infinite-duration counts as longest)
            local auraRem = (aura:GetDuration() == 0) and math.huge or aura:Remains()
            local bestRem = (bestAura:Active() and ((bestAura:GetDuration() == 0) and math.huge or bestAura:Remains())) or -1
            if auraRem > bestRem then
                return aura, true
            end
        end
        return bestAura, false
    end, mint.Aura.CreateBlank())
end

--- Find the longest-remaining active debuff from a list.
--- @param spellList List   	-- List of spell IDs
--- @param playerOnly boolean? 	-- If true, only consider buffs cast by the player
--- @return Aura              	-- The Aura with the longest remaining time, or a blank Aura if none are active
function Unit:FindLongestDebuffFromList(spellList, playerOnly)
	return spellList:reduce(function(bestAura, cur)
        local aura = self:FindDebuff(cur, playerOnly)
        if aura:Active() then
            -- Compute "effective" remains (infinite-duration counts as longest)
            local auraRem = (aura:GetDuration() == 0) and math.huge or aura:Remains()
            local bestRem = (bestAura:Active() and ((bestAura:GetDuration() == 0) and math.huge or bestAura:Remains())) or -1
            if auraRem > bestRem then
                return aura, true
            end
        end
        return bestAura, false
    end, mint.Aura.CreateBlank())
end

-- Returns if the unit has a debuff of the specific type
function Unit:HasDebuffType(types, checkWhitelist)
	local has_debuff = false
	local pointer = self:GetPointer()
	local i = 1
	while true do
		local auraData = C_UnitAuras.GetAuraDataByIndex(pointer, i, "HARMFUL")
		if not auraData then break end
		local dispelType = auraData.dispelName
		local spellId = auraData.spellId
		if dispelType and types[dispelType] and (not checkWhitelist or (mint.Settings.profile.dispels[tostring(spellId)] and mint.Settings.profile.dispels[tostring(spellId)].enabled)) then
			has_debuff = true
			break
		end
		i = i + 1
	end

	return has_debuff
end

-- Return if the unit has an aura dispellable by spell provided.
---@param spell Spell
---@return boolean
---@return Aura
function Unit:HasDispellableAura(spell)
	local debuffs = mint.Constants.DispelList
	local delay = mint.data.vars.dispel_delay or 0.5
	local player = mint.UnitManager:Get("player")


	local active_aura = debuffs:reduce(function(acc, cur)
		-- mint.console.log("Checking for aura " .. cur.spell.id)
		local aura = self:FindDebuff(cur.spell)

		if aura:Active() and aura:IsDispelableBySpell(spell) then
			mint.console.log("Aura found:", cur.spell.name)
			if not cur.condition(self, player, cur.spell) then
				mint.console.log("Aura condition is not met for " .. cur.spell.name)
				return acc, false
			end

			-- For "infinite" debuffs
			if aura:GetDuration() == 0 or aura:Remains() == 0 then
				mint.console.log("Aura is infinite")
				if not self.delay_checks then
					self.delay_checks = {}
				end

				-- This is a cursed aura
				if not self.delay_checks[aura:GetSpell().id] then
					mint.console.log(cur.spell.name, "has been added to delay checks")
					self.delay_checks[aura:GetSpell().id] = GetTime()
				end

				if GetTime() - self.delay_checks[aura:GetSpell().id] > delay then
					mint.console.log(cur.spell.name, "has been removed from delay checks, returned aura")
					self.delay_checks[aura:GetSpell().id] = false
					return aura, true
				end

				return acc, false
			end

			local maxDur = aura:GetDuration()
			local remains = aura:Remains()
			local waited = maxDur - remains
			if waited > delay then
				return aura, true
			end

			return acc, false
		end

		mint.console.log(cur.spell.name, "is", aura:Active() and "active" or "inactive", "and", aura:IsDispelableBySpell(spell) and "is dispellable" or "is not dispellable")
		return acc, false
	end, mint.Aura.CreateBlank())

	mint.console.log("Reduce function completed, active_aura is: " .. (active_aura and tostring(active_aura) or "nil"))

	if not active_aura or not active_aura:Active() then
		mint.console.log("No active dispellable aura found")
		return false, active_aura
	end

	mint.console.log("Proper aura found: " .. active_aura:GetSpellID())
	return true, active_aura
end

return Unit