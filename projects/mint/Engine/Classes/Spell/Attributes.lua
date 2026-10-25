local unlocker,
---@class mint
mint = ...

---@class Spell
local Spell = mint.Spell

--! Mint Locals !--

local UnitManager = mint.UnitManager
local player = UnitManager:Get("player")

-- Get the base cooldown of a spell
---@return number
function Spell:GetBaseCD()
    return select(1, GetSpellBaseCooldown(self.id))
end

-- Get the cooldown duration of a spell
---@return number
function Spell:GetCD()
    local info = C_Spell.GetSpellCooldown(self.id)
    return info and info.duration or 0
end

-- Get the remaining cooldown of a spell
---@return number
function Spell:GetRemainingCD()
    local info = C_Spell.GetSpellCooldown(self.id)
    if not info or not info.startTime then return 0 end

    if info.startTime == 0 then
        return 0
    end

    return info.startTime + info.duration - GetTime()
end

-- Get if a spell is on cooldown related to your GCD
-- Uses total CD duration (not remaining), matching retail Tinkr behavior.
-- GCD-only spells (duration ~1.5s) pass; real cooldowns (20s+) block.
---@return boolean
function Spell:IsOnCD()
    local cd = self:GetCD()
    return cd > (mint.max_gcd or 1.5) + 0.2
end

-- Get if a spell is ready to be used (not on CD)
---@return boolean
function Spell:IsReady()
    return not self:IsOnCD()
end

-- Get the spells charges
---@return number|nil
function Spell:GetCount()
    return C_Spell.GetSpellCastCount(self.id)
end

-- Get the spells charges
---@return number|nil
function Spell:GetCharges()
    local info = C_Spell.GetSpellCharges(self.id)
    return info and info.currentCharges or nil
end

-- Get the spells max charges
---@return number|nil
function Spell:GetMaxCharges()
    local info = C_Spell.GetSpellCharges(self.id)
    return info and info.maxCharges or nil
end

-- Get the spells fractional charges
---@return number
function Spell:GetChargesFractional()
    local info = C_Spell.GetSpellCharges(self.id)
    if not info then return 0 end

    -- If charges are fully recharged, return the max charges
    if info.currentCharges == info.maxCharges then
        return info.maxCharges
    end

    if not info.cooldownDuration or info.cooldownDuration <= 0 then
        return info.currentCharges
    end

    -- If no charges available, calculate partial recovery toward first charge
    if info.currentCharges == 0 then
        local timeSinceStart = GetTime() - (info.cooldownStartTime or 0)
        return math.min(timeSinceStart / info.cooldownDuration, 1)
    end

    -- cooldownDuration is already per-charge, not total
    local timeSinceStart = GetTime() - (info.cooldownStartTime or 0)
    local fractionalCharge = timeSinceStart / info.cooldownDuration

    return math.min(info.currentCharges + fractionalCharge, info.maxCharges)
end


-- Get the spell's cast time in seconds
---@return number
function Spell:GetCastTime()
    local info = C_Spell.GetSpellInfo(self.id)
    return (info and info.castTime and info.castTime / 1000) or 0
end

-- Get if the spell is known
---@return boolean
function Spell:IsKnown()
	local IsSpellKnown, IsPlayerSpell, IsSpellKnownOrOverridesKnown = IsSpellKnown, IsPlayerSpell, IsSpellKnownOrOverridesKnown

    local isKnown = IsSpellKnown(self.id)
    local isPlayerSpell = IsPlayerSpell(self.id)
	local overridesKnown = IsSpellKnownOrOverridesKnown(self.id)

    return isKnown or isPlayerSpell or overridesKnown or false
end

-- Get if the spell is usable
---@return boolean
function Spell:IsUsable()
    local usable, resource = C_Spell.IsSpellUsable(self.id)
    return usable and not resource
end

function Spell:get_usable()
    return self:IsUsable()
end

-- Get if the spell is affordable
---@return boolean
function Spell:CanAfford()
    local usable, insufficientPower = C_Spell.IsSpellUsable(self.id)
    if not usable then
        return not insufficientPower
    end
    return true
end

-- Get the spell's maximum range
---@return number
function Spell:get_range()
    local info = C_Spell.GetSpellInfo(self.id)
    if info and info.maxRange and info.maxRange > 0 then
        return info.maxRange
    end
    return 40 -- Default to 40 yards if unknown
end

-- Get if the spell is in range of given Unit
---@param unit Unit
---@return boolean
function Spell:IsInRange(unit)
    local has_range = C_Spell.SpellHasRange(self.id)

    if not has_range then
        return true
    end

    local pointer = unit:GetPointer()
    -- Guard against nil pointer which would crash C_Spell
    if not pointer then return false end
    
    local in_range = C_Spell.IsSpellInRange(self.id, pointer)

    -- explicitly check for 1/true (in range)
    if in_range == 1 or in_range == true then
        return true
    end

    -- fallback: if WoW says nil or 0 (false), it often means the unit is invalid for that token (GUIS issue).
    -- We verify distance manually for all GUIDs to prevent API false-negatives, especially for utility spells.
    if type(pointer) == "string" and string.find(pointer, "-") then
        local radius = self:get_range() or 40
        -- Add 1.5yd buffer for Hitbox/Combat Reach
        return unit:GetDistance(mint.UnitManager:Get("player")) <= (radius + 1.5)
    end

    -- For standard units (target/mouseover), we trust the hard 0/false.
    if in_range == 0 or in_range == false then
        return false
    end

    return false 
end

-- Get the full cooldown (time until all charges are available)
---@return number
function Spell:GetFullRechargeTime()
	local info = C_Spell.GetSpellCooldown(self.id)
	if not info or not info.isEnabled then return 0 end
	if info.isEnabled == 0 then
		return 0
	end

	local chargeInfo = C_Spell.GetSpellCharges(self.id)
	if not chargeInfo then return 0 end
	if chargeInfo.currentCharges == chargeInfo.maxCharges then
		return 0
	end

	if chargeInfo.currentCharges == 0 then
		return info.startTime + info.duration - GetTime()
	end

	return chargeInfo.cooldownStartTime + chargeInfo.cooldownDuration - GetTime()
end

-- Get the spell's travel time
---@return number
function Spell:GetTravelTime()
	return self.travel_time or 0
end