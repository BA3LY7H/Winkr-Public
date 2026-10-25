local unlocker,
---@class mint
mint = ...

---@class Aura
---@field aura AuraData
---@field auraInstanceID number
local Aura = {}
Aura.__index = Aura

function Aura.CreateBlank()
    local instance = setmetatable({}, Aura)

    instance.aura = {
        name = nil,
        icon = 0,
        applications = 0,
        dispelType = nil,
        duration = 0,
        expirationTime = 0,
        source = nil,
        isStealable = false,
        nameplateShowPersonal = false,
        spellId = 0,
        canApplyAura = false,
        nameplateShowAll = false,
        timeMod = 0,
        auraInstanceID = 0,
        points = {},
        charges = 0,
        maxCharges = 0,
        dispelName = nil,
        sourceUnit = nil,
        isFromPlayerOrPlayerPet = false,
        isBossAura = false,
        isNameplateOnly = false,
        isRaid = false,

        index = nil,
        isHelpful = false,
        isHarmful = false
    }

    return instance
end

---@param aura_data AuraData
---@return Aura
function Aura.CreateFromAuraData(aura_data)
    local instance = setmetatable({}, Aura)
    instance.aura = aura_data
	instance.auraInstanceID = aura_data.auraInstanceID or 0

    return instance
end

-- Check if the aura is valid
---@return boolean
function Aura:IsValid()
    return self.aura and self.aura.name ~= nil
end

-- Check if the aura is up
---@return boolean
function Aura:Active()
    return self:IsValid() and (self:GetDuration() == 0 or self:Remains() > 0)
end

-- Check if the aura is down
---@return boolean
function Aura:Inactive()
    return not self:Active()
end

-- Get the auras type
---@return string
function Aura:GetType()
    return self.aura.isHarmful and "HARMFUL" or "HELPFUL"
end

-- Get the auras spell ID
---@return number
function Aura:GetSpellID()
    return self.aura.spellId
end

-- Get the auras name
---@return string
function Aura:GetName()
    return self.aura.name or "Unknown"
end

-- Get the auras icon
---@return number
function Aura:GetIcon()
    return self.aura.icon
end

-- Get the auras count
---@return number
function Aura:Count()
    return self.aura.applications
end

-- Get the auras value
---@return number[]
function Aura:Value()
	return self.aura.points
end

-- Get the auras dispel class
---@return string
function Aura:GetDispelClass()
    return self.aura.dispelName
end

-- Get the auras duration
---@return number
function Aura:GetDuration()
    return self.aura.duration
end

-- Get the auras remaining time
---@return number
function Aura:Remains()
    local remainingTime = self.aura.expirationTime - GetTime()

    if remainingTime < 0 then
        remainingTime = 0
    end

    return remainingTime
end

-- Check if the aura should be refreshed based on a threshold percentage of its duration
---@return boolean
function Aura:Refresh()
    return self.aura.duration == 0 or (self.aura.expirationTime - GetTime()) < (self.aura.duration * 0.3)
end

-- Get the auras expiration time
---@return number
function Aura:GetExpirationTime()
    return self.aura.expirationTime
end

-- Get the auras source
---@return Unit|nil
function Aura:GetSource()
    local guid = UnitGUID(self.aura.sourceUnit)

    return guid and mint.UnitManager:GetUnit(guid) or nil
end

-- Get the auras stealable status
---@return boolean
function Aura:GetIsStealable()
    return self.aura.isStealable
end

-- Get the auras nameplate show personal status
---@return boolean
function Aura:GetNameplateShowPersonal()
    return self.aura.nameplateShowPersonal
end

-- Get the auras spell id
---@return Spell
function Aura:GetSpell()
	return mint.Spell.New(self.aura.spellId)
end

-- Get the auras can apply aura status
---@return boolean
function Aura:GetCanApplyAura()
    return self.aura.canApplyAura
end

-- Get the auras is boss debuff status
---@return boolean
function Aura:GetIsBossDebuff()
    return self.aura.isBossAura
end

-- Get the auras cast by player status
---@return boolean
function Aura:GetCastByPlayer()
    return self.aura.isFromPlayerOrPlayerPet
end

-- Get the auras nameplate show all status
---@return boolean
function Aura:GetNameplateShowAll()
    return self.aura.nameplateShowAll
end

-- Get the auras time mod
---@return number
function Aura:GetTimeMod()
    return self.aura.timeMod
end

-- Check if the aura is a buff
---@return boolean
function Aura:IsBuff()
    return self.aura.isHelpful
end

-- Check if the aura is a debuff
---@return boolean
function Aura:IsDebuff()
    return self.aura.isHarmful
end

-- Get aura instance id
---@return number
function Aura:GetAuraInstanceID()
    return self.aura.auraInstanceID
end

-- Check if the aura is dispelable by a spell
---@param spell Spell
function Aura:IsDispelableBySpell(spell)
    if not spell then return false end
    -- Using Forbearance as a test case
    -- if self:GetSpellID() == 25771 then
    --     mint.console.log("Detected test aura")
    --     if spell.dispel_magic then
    --         mint.console.log("Aura is dispelable by magic")
    --         return true
    --     end
    -- end

    if self:GetDispelClass() == nil then
		if self:GetSpellID() == 440313 then
			return true
		end
		mint.console.log("Dispel class is nil for " .. self:GetName())
        return false
    end

    if self:GetDispelClass() == 'Magic' and spell.dispel_magic then
        return true
    end

    if self:GetDispelClass() == 'Curse' and spell.dispel_curse then
        return true
    end

    if self:GetDispelClass() == 'Poison' and spell.dispel_poison then
        return true
    end

    if self:GetDispelClass() == 'Disease' and spell.dispel_disease then
        return true
    end

	mint.console.log("Aura " .. self:GetName() .. " is not dispelable by " .. spell.name)
    return false
end

return Aura