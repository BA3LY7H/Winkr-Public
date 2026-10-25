local unlocker, mint = ...

----------------------------
-- Localize WoW API
----------------------------
-- Removed localized WoW APIs to ensure Winkr-hooked globals are used at runtime.

local Unit = mint.Unit

----------------------------
-- Basic Unit Info / Utility
----------------------------

-- Get the unit's memory pointer or GUID, depending on unlocker
---@return string
function Unit:GetPointer()
	-- For any unit with a guid, try to find a standard token first
    -- Check standard tokens for a match
    if self.guid and self.guid ~= "" then
        if UnitGUID("player") == self.guid then return "player" end
        if UnitGUID("target") == self.guid then return "target" end
        if UnitGUID("focus") == self.guid then return "focus" end
        if UnitGUID("mouseover") == self.guid then return "mouseover" end
    end
    
    if self.isOMUnit then
        return self.guid
    end

	-- Standard token units (player, target, party1, etc.) - return the token
	return self.pointer
end

-- Check if unit exists
---@return boolean
function Unit:GetExists()
    local pointer = self:GetPointer()
    
    -- Native Winkr GUID validation
    if unlocker.name == "winkr" and type(pointer) == "string" and pointer:match("-") then
        return winkr_IsValidObject(pointer)
    end
    
    -- Standard WoW Existence Check
    if UnitExists(pointer) then return true end
    
    -- Fallback for broken hooks: if it has a GUID, it exists.
    if type(pointer) == "string" and UnitGUID(pointer) then return true end

	return false
end

-- Check if the unit is the same as another
---@param other Unit
---@return boolean
function Unit:IsUnit(other)
    local otherUnit = type(other) == "table" and other:GetPointer() or other
	return UnitIsUnit(self:GetPointer(), otherUnit)
end

-- Check if unit is a boss
---@return boolean
function Unit:IsBoss()
    if not self:GetExists() then return false end

    -- Get unit classification
    local classification = UnitClassification(self:GetPointer())

    -- Health comparison
    local unitMaxHealth = UnitHealthMax(self:GetPointer())
    local playerMaxHealth = UnitHealthMax("player")

    -- Instance info
    local inInstance, instanceType = IsInInstance()

    -- Check for worldboss classification (most reliable)
    if classification == "worldboss" then
        return true
    end

    -- Check for negative level (boss level)
    if UnitLevel(self:GetPointer()) < 0 then
        return true
    end

    -- Health-based checks (non-trivial units)
    if not UnitIsTrivial(self:GetPointer()) then
        -- Rare with significant health
        if classification == "rare" and unitMaxHealth > 4 * playerMaxHealth then
            return true
        -- Rareelite classification
        elseif classification == "rareelite" then
            return true
        -- Elite with high health outside raid instances
        elseif classification == "elite" and unitMaxHealth > 4 * playerMaxHealth and instanceType ~= "raid" then
            return true
        end
    end

    -- Check for training dummies
    local unitName = UnitName(self:GetPointer())
    if unitName then
        local dummyNames = {
            "Target Dummy", "Training Dummy", "Raider's Training Dummy",
            "Dungeoneer's Training Dummy", "Resilient Target", "Sturdy Target"
        }

        for _, name in ipairs(dummyNames) do
            if unitName:find(name) then
                return true
            end
        end
    end

    -- Check if unit is in Constants.Targets["priority"]
    local unitID = self.id
    if unitID and mint.Constants and mint.Constants.Targets and mint.Constants.Targets["priority"] then
        if mint.Constants.Targets["priority"][unitID] then
            return true
        end
    end

    return false
end

-- Check if the unit is friendly to the player
---@return boolean
function Unit:IsFriend()
	return UnitCanAssist("player", self:GetPointer())
end

-- Check if the unit is an enemy to the player
---@return boolean
function Unit:IsEnemy()
	return UnitCanAttack("player", self:GetPointer())
end

-- Check if the unit is dead or ghost
---@return boolean
function Unit:IsDead()
	return UnitIsDeadOrGhost(self:GetPointer())
end

-- Check if the unit is flying
---@return boolean
function Unit:IsFlying()
	return IsFlying(self:GetPointer())
end

-- Check if the unit is mounted
---@return boolean
function Unit:IsMounted()
	if not UnitIsUnit(self:GetPointer(), "player") then
		return false
	else
		return IsMounted()
	end
end

-- Check if unit is moving
---@return boolean
function Unit:IsMoving()
	return GetUnitSpeed(self:GetPointer()) > 0
end

-- Check is unit is swimming
---@return boolean
function Unit:IsSwimming()
	return IsSwimming(self:GetPointer())
end

-- Check if the unit is in range of the player
---@return boolean
function Unit:RangeCheck()
	if UnitIsUnit(self:GetPointer(), "player") then
		return true
	end
	if UnitExists(self:GetPointer()) and UnitInRange(self:GetPointer()) then
		return true
	end
	return false
end

-- Check if the unit is in combat
---@return boolean
function Unit:IsInCombat()
	return UnitAffectingCombat(self:GetPointer())
end

-- Check if the unit is sitting
---@return boolean
function Unit:IsSitting()
	return mint.UnitIsSitting(self:GetPointer())
end


-- Get the unit's reaction number
---@return number
function Unit:GetReaction()
	if not self:GetExists() then return 0 end
	local reaction = UnitReaction(self:GetPointer(), "player")
	if not reaction then
		return 0
	end
	return reaction
end

-- Get the unit's level
---@return number
function Unit:GetLevel()
	if not self:GetExists() then return 0 end
	local level = UnitLevel(self:GetPointer())
	if not level then
		return 0
	end
	return level
end

-- Get non-localized unit's race name
---@return string
function Unit:GetRace()
	if not self:GetExists() then return "" end
	local race = select(2, UnitRace(self:GetPointer()))
	if not race then return "" end
	return race
end

----------------------------
--- Health Functions
----------------------------

-- Get a unit's current health
---@return number
function Unit:GetHealth()
	return UnitHealth(self:GetPointer())
end

-- Get a unit's maximum health
---@return number
function Unit:GetMaxHealth()
	return UnitHealthMax(self:GetPointer())
end

-- Get a unit's health percentage
---@return number
function Unit:GetHP()
	local max = self:GetMaxHealth() or 0
	if max == 0 then return 100 end
	return (self:GetHealth() or 0) / max * 100
end

-- Get the predicted healing on the unit.
---@param from string? | Can provide this to only get healing from a particular source.
---@return number
function Unit:GetIncomingHealing(from)
    return UnitGetIncomingHeals(self:GetPointer(), from)
end

----------------------------
--- Absorb Functions
----------------------------

-- Get a unit's current absorb shield
---@return number
function Unit:GetAbsorbs()
	return UnitGetTotalAbsorbs(self:GetPointer())
end

-- Get a unit's current heal absorbs
---@return number
function Unit:GetHealAbsorbs()
	return UnitGetTotalHealAbsorbs(self:GetPointer())
end

----------------------------
--- Realized Health Functions
----------------------------

-- Get realized health
---@return number
function Unit:GetRealizedHealth()
    return self:GetHealth() - self:GetHealAbsorbs()
end

-- get realized health percentage
---@return number
function Unit:GetRealizedHP()
    local max = self:GetMaxHealth() or 0
    if max == 0 then return 100 end
    return (self:GetRealizedHealth() or 0) / max * 100
end

-- Get the unit's HP including predicted incoming healing.
---@param from string? | Can provide this to only get healing from a particular source.
---@return number
function Unit:GetPredictedHP(from)
    local max = self:GetMaxHealth() or 0
    if max == 0 then return 100 end
    return ((self:GetRealizedHealth() or 0) + (self:GetIncomingHealing(from) or 0)) / max * 100
end

----------------------------
-- Power Functions
----------------------------

-- Get the unit's power type (e.g. mana, rage)
---@return number
function Unit:GetPowerType()
	return select(1, UnitPowerType(self:GetPointer()))
end

-- Get the units runes remaining
---@return number
function Unit:GetRunes()
	local count = 0
	for i = 1, 6 do
		count = count + GetRuneCount(i)
	end

	return count
end

-- Get the unit's current power
---@param powerType number?
---@return number
function Unit:GetPower(powerType)
	powerType = powerType or self:GetPowerType()
	return UnitPower(self:GetPointer(), powerType)
end

-- Get the unit's max power
---@param powerType number?
---@return number
function Unit:GetMaxPower(powerType)
	powerType = powerType or self:GetPowerType()
	return UnitPowerMax(self:GetPointer(), powerType)
end

-- Get the unit's power as a percentage
---@param powerType number?
---@return number
function Unit:GetPP(powerType)
	powerType = powerType or self:GetPowerType()
	local max = self:GetMaxPower(powerType) or 0
	if max == 0 then return 0 end
	return (self:GetPower(powerType) or 0) / max * 100
end

--- Returns seconds until this unit reaches max power for the given powerType.
---@param powerType number? -- defaults to self:GetPowerType()
---@return number           -- seconds; 0 if already capped; math.huge if regen unknown/zero
function Unit:TimeToMaxPower(powerType)
    powerType = powerType or self:GetPowerType()

    local currentPower   = self:GetPower(powerType)
    local maxPower       = self:GetMaxPower(powerType)
    local powerDeficit   = maxPower - currentPower
    if powerDeficit <= 0 then return 0 end

    -- So we aren't spamming the api
    local cacheKey = "ttmp_" .. tostring(powerType)
    local cached = self.cache:Get(cacheKey)
    if cached then
        return cached
    end

    -- Get regen from api ez
    local r1, r2 = GetPowerRegenForPowerType(powerType) -- wtf when did this get added
    local regen = (r2 or r1 or 0) -- r2 is combat, which is what we typically want

    -- If this is somehow negative or zero, return math.huge
    if regen <= 0 then
        self.cache:Set(cacheKey, math.huge, 0.2)
        return math.huge
    end

    local seconds = powerDeficit / regen
    if seconds < 0 then seconds = 0 end

    self.cache:Set(cacheKey, seconds, 0.25)
    return seconds
end

-- Returns time to max energy in seconds.
---@return number
function Unit:TimeToMaxEnergy()
    return self:TimeToMaxPower(3)
end

-- Returns time to max focus in seconds.
---@return number
function Unit:TimeToMaxFocus()
    return self:TimeToMaxPower(2)
end

----------------------------
-- Distance / Vector Functions
----------------------------

-- Get the unit's 3D world position
---@return Vector3
function Unit:GetPosition()
	local x, y, z = mint.ObjectPosition(self:GetPointer())
	return mint.Vector3:New(x, y, z)
end

-- Get the distance from the player to this unit
---@return number
function Unit:GetPlayerDistance()
	local player = mint.UnitManager:Get("player")
	return player:GetPosition():Distance(self:GetPosition())
end

-- Get the distance to another unit (or player by default)
---@param other Unit?
---@return number
function Unit:GetDistance(other)
	if not other then
		if UnitIsUnit(self:GetPointer(), "player") then
			error("You cannot check distance from player to player.")
		else
			other = mint.UnitManager:Get("player")
		end
	end
	return self:GetPosition():Distance(other:GetPosition())
end

-- Get the squared distance to another unit
---@param other Unit
---@return number
function Unit:GetDistanceSquared(other)
	return self:GetPosition():DistanceSquared(other:GetPosition())
end

-- Check if the unit is within a limit of another unit
---@param limit number
---@param other Unit?
---@return boolean
function Unit:IsWithin(limit, other)
	other = other or mint.UnitManager:Get("player")
	return self:GetPosition():DistanceSquared(other:GetPosition()) <= (limit * limit)
end

-- Check if the unit is facing another
---@param unit Unit
---@param bound number?
---@return boolean
function Unit:IsFacing(unit, bound)
    if self:IsUnit(unit) then return true end -- You're always facing yourself!
	bound = bound or 90
	local rot = mint.ObjectRotation(self:GetPointer())
	local x, y = select(1, mint.ObjectPosition(self:GetPointer()))
	local x2, y2 = select(1, mint.ObjectPosition(unit:GetPointer()))
	if not x or not x2 or not rot then return false end
	local angle = math.deg(math.atan2(y2 - y, x2 - x) - rot) % 360
	if angle > 180 then angle = angle - 360 end
	return math.abs(angle) < bound
end

-- Check if the unit is in melee range
---@param unit Unit
---@return boolean
function Unit:InMelee(unit)
	local x, y, z = mint.ObjectPosition(self:GetPointer())
	local x2, y2, z2 = mint.ObjectPosition(unit:GetPointer())
	if not x or not x2 then return false end

	local scr = mint.ObjectCombatReach(self:GetPointer())
	local ucr = mint.ObjectCombatReach(unit:GetPointer())
	if not scr or not ucr then return false end

	local dist = math.sqrt((x - x2)^2 + (y - y2)^2 + (z - z2)^2)
	local maxDist = math.max((scr + 1.3333) + ucr, 5.0) + 1.0 + (IsPlayerSpell(196924) and 3 or 0)
	return dist <= maxDist
end

-- Calculate aggro range based on level difference
---@return number
function Unit:GetAggroRange()
	local radius = 20 + (self.level - UnitLevel("player"))
	return math.max(5, math.min(radius, 45))
end

-- Get the adjusted attack range to another unit
---@param other Unit?
---@return number
function Unit:GetAttackRange(other)
	if not other then
		if UnitIsUnit(self:GetPointer(), "player") then
			error("You cannot check distance from player to player.")
		else
			other = mint.UnitManager:Get("player")
		end
	end

	local scr = mint.ObjectCombatReach(self:GetPointer())
	local ocr = mint.ObjectCombatReach(other:GetPointer())
	if not scr or not ocr then return 99 end

	local dist = self:GetPosition():Distance(other:GetPosition()) - (math.max((scr + 1.3333) + ocr, 5.0) + 1.0)
	return dist
end

-- Get the combat reach for a unit
---@return number
function Unit:GetCombatReach()
    return mint.ObjectCombatReach(self:GetPointer())
end

----------------------------
-- Line of Sight (LOS)
----------------------------


-- Los flags for HasLos
local losFlag = bit.bor(0x1, 0x10)

-- Check if this unit can see another
---@param unit Unit?
---@return boolean
function Unit:HasLos(unit)
	unit = unit or mint.UnitManager:Get("player")
	if not unit or not unit:GetExists() then return false end
	if self:IsUnit(unit) then return true end

	local guid = unit.guid
	local cached = self.cache:Get("can_see_" .. guid)
	if cached then return cached end

	local attx1, atty1, attz1 = mint.ObjectAttachmentPosition(self:GetPointer(), mint.AttachFlags["back"])
	local attx2, atty2, attz2 = mint.ObjectAttachmentPosition(unit:GetPointer(), mint.AttachFlags["back"])
	if not attx1 or not attx2 then 
        mint.console.log(string.format("[LoS DEBUG] %s: Missing Coords (Source: %s, Target: %s)", unit:GetName() or "Unknown", tostring(attx1), tostring(attx2)))
        self.cache:Set("can_see_" .. guid, false, 0.4) 
        return false 
    end

	if (attx1 == 0 and atty1 == 0 and attz1 == 0) or (attx2 == 0 and atty2 == 0 and attz2 == 0) then
		self.cache:Set("can_see_" .. guid, false, 0.4)
		return false
	end

	local x, y, z = mint.TraceLine(attx1, atty1, attz1, attx2, atty2, attz2, losFlag)
	local result = (x == 0 and y == 0 and z == 0)
    
    if not result then
        mint.console.log(string.format("[LoS DEBUG] %s: Blocked at %.2f, %.2f, %.2f", unit:GetName() or "Unknown", x, y, z))
    end

	self.cache:Set("can_see_" .. guid, result, 0.4)
	return result
end

-- Can the unit attack another
---@param other Unit?
---@return boolean
function Unit:CanAttack(other)
	if not other then error("Unit:CanAttack - Other unit is required") end
	return self:GetExists() and other:GetExists() and UnitCanAttack(self:GetPointer(), other:GetPointer())
end

----------------------------
-- Casting / Channeling
----------------------------

-- Is the unit casting a specific spell
---@param spell_id number
---@return boolean
function Unit:IsCastingSpell(spell_id)
	return self:GetCastSpellID() == spell_id
end

-- Is the unit casting a spell
---@return boolean
function Unit:IsCasting()
	return UnitCastingInfo(self:GetPointer()) ~= nil
end

-- Is the unit channeling a spell
---@return boolean
function Unit:IsChanneling()
	return UnitChannelInfo(self:GetPointer()) ~= nil
end

-- Is the unit either casting or channeling
---@return boolean
function Unit:IsCastingOrChanneling()
	return self:IsCasting() or self:IsChanneling()
end

-- Get the spell ID being cast/channelled
---@return number | nil
function Unit:GetCastSpellID()
	local _, _, _, _, _, _, _, _, spell_id = UnitCastingInfo(self:GetPointer())
	if not spell_id then
		_, _, _, _, _, _, _, spell_id = UnitChannelInfo(self:GetPointer())
	end
	return spell_id
end

-- Get the spell object being cast/channelled
---@return Spell | nil
function Unit:GetCastSpell()
	local spellId = self:GetCastSpellID()

    if spellId then
        return mint.Spell.New(spellId)
    end
end

-- Get time when the cast will end
---@return number
function Unit:GetCastEndTime()
	local _, _, _, _, end_time = UnitCastingInfo(self:GetPointer())
	if not end_time then _, _, _, _, end_time = UnitChannelInfo(self:GetPointer()) end
	return end_time and end_time / 1000 or 0
end

-- Get time remaining for cast to finish
---@return number
function Unit:TimeToCast()
	local _, _, _, _, end_time = UnitCastingInfo(self:GetPointer())
	if end_time then return end_time / 1000 - GetTime() end
	return 0
end

-- Get the time since the unit started to cast
---@return number
function Unit:GetTimeSinceStartedCast()
	local start_time = self:GetCastStartTime()
	if start_time == 0 then return 0 end
	return GetTime() - start_time
end

-- Get the percentage of the cast that has completed
---@return number
function Unit:GetCastPercent()
	local start_time = self:GetCastStartTime()
	local end_time = self:GetCastEndTime()
	if start_time == 0 or end_time == 0 or end_time == start_time then return 0 end
	return (GetTime() - start_time) / (end_time - start_time) * 100
end

-- Determine if the unit is within the cast percentage window provided
---@param min number -- Minimum percentage of cast completed
---@param max number -- Maximum percentage of cast completed
---@return boolean
function Unit:IsWithinCastWindow(min, max)
	local percent = self:GetCastPercent()
	if percent >= min and percent <= max then
		return true
	end
	return false
end

-- Get the start time of cast/channel
---@return number
function Unit:GetCastStartTime()
	local _, _, _, start_time = UnitCastingInfo(self:GetPointer())
	if not start_time then _, _, _, start_time = UnitChannelInfo(self:GetPointer()) end
	return start_time and start_time / 1000 or 0
end

-- Is the current cast/channel kickable
---@return boolean
function Unit:IsKickable()
	local _, _, _, _, _, _, _, kick_immune = UnitCastingInfo(self:GetPointer())
	if kick_immune == nil then
		_, _, _, _, _, _, kick_immune = UnitChannelInfo(self:GetPointer())
	end
	return kick_immune == false
end

-- Get the target of the unit's current cast
---@return string
function Unit:GetCastTarget()
	return mint.UnitCastTarget(self:GetPointer())
end

----------------------------
-- Miscellaneous
----------------------------

-- Count number of "dangerous" timers active on this unit
---@return number
function Unit:GetDanger()
	local count = 0
	for k, v in pairs(self.timers) do
		if v > GetTime() then
			count = count + 1
		else
			self.timers[k] = nil
		end
	end
	return count
end

-- Sets a unit's danger status
---@param spell_id number
---@param expiration number
function Unit:SetDanger(spell_id, expiration)
    mint:Log("Setting danger for " .. self.name .. " due to " .. spell_id .. " until " .. expiration)
    self.timers[spell_id] = expiration
end

----------------------------
--- Combat Tracking
----------------------------

-- Set combat time if affecting combat and return the difference between now and the last time
---@return number
function Unit:TimeSinceLastCombatEvent()
    return GetTime() - self.last_combat_event_time
end

-- Set the last combat event time
---@param time number
---@return nil
function Unit:UpdateCombatTimer(time)
    self.last_combat_event_time = time
end

-- Get combat odds (if the last combat time is less than 1 minute ago return 1 / time, else return 0)
-- the closer to 0 the more likely the unit is to be in combat (0 = 100%) 60 = 0%
---@return number
function Unit:CombatConfidence()
    local time = self:TimeSinceLastCombatEvent()
    local percent = 1 - (time / 60)

    return percent * 100
end

-- Get if anyone in the unit's party is in combat
---@return boolean
function Unit:IsPartyInCombat()
	if self:IsInCombat() then return true end

	local in_combat = false

	mint.FriendManager:Loop(function(unit)
		if unit:IsInCombat() then
			in_combat = true
			return true
		end
	end)

	return in_combat
end

-- Return if the unit is a tank.
---@return boolean
function Unit:IsTank()
    return UnitGroupRolesAssigned(self:GetPointer()) == "TANK"
end

-- Return if this unit is tanking the enemy
---@param enemy Unit
---@return boolean
function Unit:IsTanking(enemy)
    -- UnitDetailedThreatSituation(unitID, targetUnitID)
    -- returns: isTanking, status, threatpct, rawthreatpct, threatvalue
    local isTanking = UnitDetailedThreatSituation(self:GetPointer(), enemy:GetPointer())
    return isTanking
end

-- Return if anyone in the party (excluding the player) is being tanked by this enemy
---@param enemy Unit
---@return boolean
function Unit:IsFriendTanking(enemy)
	local isBeingTanked = false
	mint.FriendManager:Loop(function(friend)
        -- We only care if OTHER party members ARE being tanked
        if friend:Is(mint.UnitManager:Get("player")) then return false end

		if friend:IsTanking(enemy) then
			isBeingTanked = true
			return true -- Break loop
		end
	end)
	return isBeingTanked
end

-- Return if this unit is the same as the target unit
---@param other Unit|string
---@return boolean
function Unit:Is(other)
    if not other then return false end
    local otherPointer = type(other) == "table" and other:GetPointer() or other
    if not otherPointer then return false end
    
    return UnitIsUnit(self:GetPointer(), otherPointer)
end

----------------------------
--- Unit Counting
----------------------------

--- Get number of enemies within a radius of this unit
---@param radius number -- The radius to check for enemies
---@return number -- The number of enemies within the radius
function Unit:GetEnemies(radius)

	local cached = self.cache:Get("enemies_" .. radius)

	if cached then
		return cached
	end

    local count = 0

    mint.ObjectManager.enemies:loop(function(enemy)
		enemy:Update()
        if enemy.is_dead then return false end
        if not enemy:GetExists() then return false end
        if not enemy.can_attack then return false end

        if enemy:IsWithin(radius, self) then
            count = count + 1
        end

        return false
    end)

	self.cache:Set("enemies_" .. radius, count, 0.25)

    return count
end

function Unit:GetMeleeCount()
	local cached = self.cache:Get("enemies_melee")

	if cached then
		return cached
	end

    local count = 0

    mint.ObjectManager.enemies:loop(function(enemy)
		enemy:Update()
        if enemy.is_dead then return false end
        if not enemy:GetExists() then return false end
        if not enemy.can_attack then return false end

        if self:InMelee(enemy) then
            count = count + 1
        end

        return false
    end)

	self.cache:Set("enemies_melee", count, 0.25)

    return count
end

-- Get the angle between the unit and the target in raidans
---@param Target Unit
---@return number
function Unit:GetAngle(Target)
	if not Target:GetExists() then
		return 0
	end

	local me = self:GetPosition()
	local them = Target:GetPosition()

	local angle = me:Angle(them)

	return angle
end

-- Get the angle between the unit and the target in raidans
---@param Target Unit
---@return number
function Unit:GetAngle2D(Target)
	if not Target then
		return 0
	end

	local me = self:GetPosition()
	local them = Target:GetPosition()

	local angle = me:Angle2D(them)

	return angle
end

-- Get the facing direction in radians of the unit
---@return number
function Unit:GetFacing()
	local rot = mint.ObjectRotation(self:GetPointer())

	return rot or 0
end

-- Check if target is within a arc around the unit (angle, distance) accounting for a rotation of self
---@param tar Unit
---@param angle number
---@param dist number
---@param rotation? number
---@return boolean
function Unit:IsWithinCone(tar, halfAngle, dist, rotation)
	if not tar:GetExists() then
		return false
	end

	local facing = self:GetAngle(tar)
	rotation = rotation or self:GetFacing()

	local diff = math.abs(facing - rotation)

	if diff > math.pi then
		diff = math.abs(diff - math.pi * 2)
	end

	return diff <= math.rad(halfAngle) and self:GetDistanceSquared(tar) <= (dist * dist)
end

function Unit:CanCastMove()
	if self:FindAnyBuff(mint.Constants.move_spells):Active() then
		return true
	end

	return false
end

-- Returns if the unit is able to be disoriented
function Unit:CanDisorient()
	local data = mint.Constants.TWWS3.mdt_data[self.id]

	if not data then return true end

	return data.Disorient
end

-- Returns if the unit is able to be gripped
function Unit:CanGrip()
	local data = mint.Constants.TWWS3.mdt_data[self.id]

	if not data then return true end

	return data.Grip
end

-- Returns if the unit is able to be feared
function Unit:CanFear()
	local data = mint.Constants.TWWS3.mdt_data[self.id]

	if not data then return true end

	return data.Fear
end

-- Returns if the unit is able to be rooted
function Unit:CanRoot()
	local data = mint.Constants.TWWS3.mdt_data[self.id]

	if not data then return true end

	return data.Root
end

-- Returns if the unit is able to be silenced
function Unit:CanSilence()
	local data = mint.Constants.TWWS3.mdt_data[self.id]

	if not data then return true end

	return data.Silence
end

-- Returns if the unit is able to be slowed
function Unit:CanSlow()
	local data = mint.Constants.TWWS3.mdt_data[self.id]

	if not data then return true end

	return data.Slow
end

-- Returns if the unit is able to be stunned
function Unit:CanStun()
	local data = mint.Constants.TWWS3.mdt_data[self.id]

	if not data then return true end

	return data.Stun
end

-- Returns if the unit is able to be taunted
function Unit:CanTaunt()
	local data = mint.Constants.TWWS3.mdt_data[self.id]

	if not data then return true end

	return data.Taunt
end

-- Returns if the unit is able to be incapacitated
function Unit:CanIncapacitate()
	local data = mint.Constants.TWWS3.mdt_data[self.id]

	if not data then return true end

	return data.Incapacitate
end

-- Returns if the unit is able to be interrupted (ie: if they are a caster)
function Unit:CanInterrupt()
	local data = mint.Constants.TWWS3.mdt_data[self.id]

	if not data then return true end

	return data.Interruptible
end

local dummyUnits = {
    -- City (SW, Orgri, ...)
    [31146] = true,  -- Raider's Training Dummy
    [31144] = true,  -- Training Dummy
    [32666] = true,  -- Training Dummy
    [32667] = true,  -- Training Dummy
    [46647] = true,  -- Training Dummy
    [114832] = true, -- PvP Training Dummy
    [153285] = true, -- Training Dummy
    [153292] = true, -- Training Dummy
    -- MoP Shrine of Two Moons
    [67127] = true,  -- Training Dummy
    -- WoD Alliance Garrison
    [87317] = true,  -- Mage Tower Damage Training Dummy
    [87318] = true,  -- Mage Tower Damage Dungeoneer's Training Dummy (& Garrison)
    [87320] = true,  -- Mage Tower Damage Raider's Training Dummy
    [88314] = true,  -- Tanking Dungeoneer's Training Dummy
    [88316] = true,  -- Healing Training Dummy ----> FRIENDLY
    -- WoD Horde Garrison
    [87760] = true,  -- Mage Tower Damage Training Dummy
    [87761] = true,  -- Mage Tower Damage Dungeoneer's Training Dummy (& Garrison)
    [87762] = true,  -- Mage Tower Damage Raider's Training Dummy
    [88288] = true,  -- Tanking Dungeoneer's Training Dummy
    [88289] = true,  -- Healing Training Dummy ----> FRIENDLY
    -- Legion Druid Class Order Hall
    [113964] = true, -- Raider's Training Dummy
    [113966] = true, -- Dungeoneer's Training Dummy
    -- Legion Mage Class Order Hall
    [103397] = true, -- Greater Bullwark Construct
    [103404] = true, -- Bullwark Construct
    [103402] = true, -- Lesser Bullwark Construct
    -- Legion Priest Class Order Hall
    [107555] = true, -- Bound void Wraith
    [107556] = true, -- Bound void Walker
    -- Legion Rogue Class Order Hall
    [92164] = true,  -- Training Dummy
    [92165] = true,  -- Dungeoneer's Training Dummy
    [92166] = true,  -- Raider's Training Dummy
    -- Legion Warlock Class Order Hall
    [101956] = true, -- Rebellious Fel Lord
    [102045] = true, -- Rebellious WrathGuard
    [102048] = true, -- Rebellious Felguard
    [102052] = true, -- Rebellious imp
    -- BfA Dazar'Alor
    [144081] = true, -- Training Dummy
    [144082] = true, -- Training Dummy
    [144085] = true, -- Training Dummy
    [144086] = true, -- Raider's Training Dummy
    -- BfA Boralus
    [126781] = true, -- Training Dummy
    [131983] = true, -- Raider's Training Dummy
    [131989] = true, -- Training Dummy
    [131992] = true, -- Dungeoneer's Training Dummy
    -- Shadowlands Kyrian
    [154564] = true, -- Valiant's Humility
    [154567] = true, -- Purity's Cleaning
    [154580] = true, -- Reinforced Guardian
    [154583] = true, -- Starlwart Guardian
    [154585] = true, -- Valiant's Resolve
    [154586] = true, -- Stalwart Phalanx
    [160325] = true, -- Humility's Obedience
    -- Shadowlands Venthyr
    [173942] = true, -- Training Dummy
    [175449] = true, -- Raider's Training Dummy
    [175450] = true, -- Dungeoneer's Training Dummy
    [175451] = true, -- Dungeoneer's Tanking Dummy
    [175452] = true, -- Raider's Tanking Dummy
    [175455] = true, -- Cleave Training Dummy
    [175456] = true, -- Swarm Training Dummy
    [175462] = true, -- Sinfall Fiend
    -- Shadowlands Night Fae
    [174565] = true, -- Dungeoneer's Tanking Dummy
    [174566] = true, -- Raider's Tanking Dummy
    [174567] = true, -- Raider's Training Dummy
    [174568] = true, -- Dungeoneer's Training Dummy
    [174569] = true, -- Training Dummy
    [174570] = true, -- Swarm Training Dummy
    [174571] = true, -- Cleave Training Dummy
    -- Shadowlands Necrolord
    [174484] = true, -- Dungeoneer's Training Dummy
    [174487] = true, -- Training Dummy
    [174488] = true, -- Raider's Training Dummy
    [174491] = true, -- Tanking Dummy
    -- DargonFlight Valdrakken
    [198594] = true, -- Cleave Training Dummy
    [194648] = true, -- Training Dummy
    [189632] = true, -- Animated Duelist
    [194643] = true, -- Dungeoneer's Training Dummy
    [194644] = true, -- Dungeoneer's Training Dummy
    [197833] = true, -- PvP Training Dummy
    [189617] = true, -- Boulderfist
    [194649] = true, -- Normal Tank Dummy
    -- DargonFlight Iskaara
    [193563] = true, -- Training Dummy
    -- Other
    [65310] = true,  -- Turnip Punching Bag (toy)
    [66374] = true,  -- Anatomical Dummy (toy)
    [196394] = true, -- Tuskarr Training Dummy (toy)
    [196406] = true, -- Rubbery Fish Head (toy)
    [199057] = true, -- Black Dragon's Challenge Dummy (toy)
	-- TWW Dummies
	[225983] = true, -- Dungeoneer's Training Dummy
	[225984] = true, -- Training Dummy
	[225985] = true, -- Raiders's Training Dummy
	[225982] = true, -- Cleave Training Dummy
}

function Unit:IsDummy()
    local npcId = self.id
    return npcId and npcId >= 0 and dummyUnits[npcId] == true or false
end


---@param npcId? number
function Unit:IsInBossList(npcId)
    npcId = npcId or self.id
    for i = 1, 4 do
        local thisUnit = mint.UnitManager:Get(string.format("boss%d", i))
        if thisUnit:GetExists() and thisUnit.id == npcId then
            return true
        end
    end
end

---@param npcId number
function Unit:SpecialTTDPercentage(npcId)
    local specialTTDPercentage = mint.TimeToDie.specialTTDPercentageData[npcId]
    if not specialTTDPercentage then return 0 end

    if type(specialTTDPercentage) == "number" then
        return specialTTDPercentage
    end

    return specialTTDPercentage(self)
end

---@param npcId? number
---@param hp? number
function Unit:CheckHPFromBossList(npcId, hp)
    npcId = npcId or self.id
    local thisHP = hp or 100
    for i = 1, 4 do
        local thisUnit = mint.UnitManager:Get(string.format("boss%d", i))
        if thisUnit:GetExists() and thisUnit.id == npcId and thisUnit:GetHP() <= thisHP then
            return true
        end
    end

    return false
end

function Unit:TimeToX(percentage, minSamples)
    if self:IsDummy() then return 6666 end
    local seconds = 8888
    local unitGuid = self.guid
    if not unitGuid then
		-- mint:Debug("Unit:TimeToX: No GUID")
        return seconds
    end
    local unitTable = mint.TimeToDie.Units[unitGuid]
    -- Simple linear regression
    -- ( E(x^2)  E(x) )  ( a )  ( E(xy) )
    -- ( E(x)     n  )  ( b ) = ( E(y)  )
    -- Format of the above: ( 2x2 Matrix ) * ( 2x1 Vector ) = ( 2x1 Vector )
    -- Solve to find a and b, satisfying y = a + bx
    -- Matrix arithmetic has been expanded and solved to make the following operation as fast as possible
    if unitTable then
		-- mint:Debug("Unit:TimeToX: Unit Table Found")
        minSamples = minSamples or 3
        local values = unitTable[1]
        local n = #values
		-- mint:Debug("Unit:TimeToX: Samples: " .. #values)
        if n > minSamples then
            local a, b = 0, 0
            local ex2, ex, exy, ey = 0, 0, 0, 0

            for i = 1, n do
                local value = values[i]
                local x, y = value[1], value[2]

                ex2 = ex2 + x * x
                ex = ex + x
                exy = exy + x * y
                ey = ey + y
            end
            -- Invariant to find matrix inverse
            local invariant = 1 / (ex2 * n - ex * ex)
            -- Solve for a and b
            a = (-ex * exy * invariant) + (ex2 * ey * invariant)
            b = (n * exy * invariant) - (ex * ey * invariant)
            if b ~= 0 then
                -- Use best fit line to calculate estimated time to reach target health
                seconds = (percentage - a) / b
                -- Subtract current time to obtain "time remaining"
                seconds = math.min(7777, seconds - (GetTime() - unitTable[2]))

				-- mint:Debug("Unit:TimeToX: Seconds: " .. seconds)
                if seconds < 0 then 
					seconds = 9999 
				end
            end
        end
    end

	-- mint:Debug("Unit:TimeToX: Final Seconds: " .. seconds)
    return seconds
end

---@param minSamples? number
function Unit:TimeToDie(minSamples)
    if not self:GetExists() then
        return 11111
    end
    local unitGuid = self.guid
    if not unitGuid then return 11111 end

    minSamples = minSamples or 3
    ---@type {TTD: {[number]: number}}
	-- mint:Debug("Unit:TimeToDie: Is Cached: " .. tostring(mint.ttd_cache:IsCached(unitGuid)))

    local unitInfo = mint.ttd_cache:IsCached(unitGuid) and mint.ttd_cache:Get(unitGuid) or {}

    local ttd = unitInfo.TTD

    if not ttd then
        ttd = {}
        unitInfo.TTD = ttd
    end

    if not ttd[minSamples] then
        ttd[minSamples] = self:TimeToX(self:SpecialTTDPercentage(self.id), minSamples)
		mint.ttd_cache:Set(unitGuid, unitInfo, .5)
    end


    return ttd[minSamples]
end

-- Get the boss unit TimeToDie
---@param minSamples? number
function Unit:BossTimeToDie(minSamples)
    if self:IsInBossList() or self:IsDummy() then
        return self:TimeToDie(minSamples)
    end

    return 11111
end

-- Get if the unit meets the TimeToDie requirements.
---@param operator CompareThisTable
---@param value number
---@param offset number
---@param valueThreshold number
---@param minSamples? number
function Unit:FilteredTimeToDie(operator, value, offset, valueThreshold, minSamples)
    local TTD = self:TimeToDie(minSamples)

    return TTD < (valueThreshold or 7777) and mint.ttd_util.CompareThis(operator, TTD + (offset or 0), value) or false
end

-- Get if the boss unit meets the TimeToDie requirements.
---@param operator CompareThisTable
---@param value number
---@param offset number
---@param valueThreshold number
---@param minSamples? number
function Unit:BossFilteredTimeToDie(operator, value, offset, valueThreshold, minSamples)
    if self:IsInBossList() or self:IsDummy() then
        return self:FilteredTimeToDie(operator, value, offset, valueThreshold, minSamples)
    end

    return false
end

function Unit:TTDIsValid(minSamples)
	minSamples = minSamples or 3
	return self:TimeToDie(minSamples) < 7777
end

-- Get if the Time To Die is Valid for an Unit (i.e. not returning a warning code).
---@param minSamples? number
function Unit:TimeToDieIsNotValid(minSamples)
	minSamples = minSamples or 3
    return self:TimeToDie(minSamples) >= 7777
end

-- Get if the Time To Die is Valid for a boss Unit (i.e. not returning a warning code or not being a boss).
---@param minSamples? number
function Unit:BossTimeToDieIsNotValid(minSamples)
    if self:IsInBossList() then
        return self:TimeToDieIsNotValid(minSamples)
    end

    return true
end

---@param rect { origin: Vector3, rotation: number, w: number, l: number }
---@return boolean
function Unit:IsInRectangle(rect)
	local me = self:GetPosition()
    local o = rect.origin

    -- Check that the unit and origin have valid positions
    if me:IsValid() and o:IsValid() then

        local l = rect.l
        local w = rect.w
        -- Rectangle is defined with 'origin' at the center of the **back** edge,
        -- facing 'rotation' radians along its length.
        local rot = rect.rotation or 0

        local pad = math.max(self:GetCombatReach() or 0, 1.5)

        -- Unit vectors for the rectangle's local frame on the XY plane:
        -- forward (length direction) and right (width direction).
        local c, s = math.cos(rot), math.sin(rot)
        local fx, fy =  c,  s      -- forward (+length)
        local rx, ry = -s,  c      -- right   (+width)

        -- Translate the unit into the rectangle's local space
        local dx, dy = me.x - o.x, me.y - o.y
        local x = dx * fx + dy * fy   -- forward axis; back edge is x = 0
        local y = dx * rx + dy * ry   -- right axis; centered, width spans [-w/2, +w/2]

        -- Bounds check in local space
        local halfW = 0.5 * w
        local eps = 1e-6

        -- Fast inside test (no radius): origin is back-edge center => x ∈ [0, l]
        if x >= -eps and x <= l + eps and math.abs(y) <= halfW + eps then
            return true
        end

                -- ! This is only called if the unit is outside of the actual rectangle.
        -- ! Checks if their hitbox will be hit by the rectangle.
        -- Circle-vs-rectangle: clamp to closest point on the rectangle, then check distance ≤ r
        local function clamp(v, a, b)
            if v < a then return a elseif v > b then return b else return v end
        end

        local cx = clamp(x, 0, l)
        local cy = clamp(y, -halfW, halfW)
        local dxr, dyr = x - cx, y - cy
        return (dxr*dxr + dyr*dyr) <= (pad*pad + eps)
    end


	return false
end

---@param circle Vector3
---@param radius number
---@return boolean
function Unit:IsInCircle(circle, radius)
    local me = self:GetPosition()
    
    if me:IsValid() then
        return me:Distance(circle) <= radius
    end

    return false
end

---@param cone { origin: Vector3, rotation: number, angle: number, radius: number }
---@return boolean
function Unit:IsInCone(cone)
    local me = self:GetPosition()

    if me:IsValid() then
		local relative = me - cone.origin

		local dist = relative.magnitude

		if dist > cone.radius then
			return false
		end

		local dir = relative:Normalize()

		local forward = mint.Vector3:New(math.cos(cone.rotation), math.sin(cone.rotation), 0)

		local angle = math.acos(forward:Dot(dir))

		local half_angle = math.rad(cone.angle / 2)

		return angle <= half_angle
    end

    return false
end

local tier = {
    ["hunter"] = { 237649, 237647, 237646, 237645, 237644 }
}

--- Check if 2p is equipped for Manaforge Omega
---@return boolean
function Unit:Has2p()
    local count = 0

    local tierSet = tier[mint.class]
    if tierSet then
        for i = 1, #tierSet do
            if count >= 2 then
                break;
            end
            if IsEquippedItem(tierSet[i]) then
                count = count + 1
            end
        end
    end

    return count >= 2
end

--- Check if 4p is equipped for Manaforge Omega
---@return boolean
function Unit:Has4p()
    local count = 0

    local tierSet = tier[mint.class]
    if tierSet then
        for i = 1, #tierSet do
            if count >= 4 then
                break;
            end
            if IsEquippedItem(tierSet[i]) then
                count = count + 1
            end
        end
    end

    return count >= 4
end

-- Alias: GetHealthPercent → GetHP (BUG-02)
Unit.GetHealthPercent = Unit.GetHP

-- Get the unit's display name
---@return string?
function Unit:GetName()
    return self.name
end

-- Check if the unit is engaged in combat (has threat on anything)
---@return boolean
function Unit:IsEngaged()
    return self:IsInCombat()
end

-- Check if the unit is currently casting something interruptible
---@return boolean
function Unit:IsInterruptible()
    return self:IsCasting() and self:IsKickable()
end
