local unlocker,
---@class mint
mint = ...

local Unit          = mint.Unit

---@class UnitManager
---@field units table
---@field smartUnits table
---@field cache Cache | table
local UnitManager = {
    units = {},
    smartUnits = {},
    cache = {}
}

function UnitManager:__index(k)
    if k == 'none' then
        print("UnitManager:__index - Returning none")
        return self:Get('none')
    end

    if UnitManager[k] then
        return UnitManager[k]
    end

    local k = k or 'none'

    if self.smartUnits[k] then
        if not self.cache:IsCached(k) then
            self.smartUnits[k].unit:Update()
            self.cache:Set(k, self.smartUnits[k].unit, 0.2)
        end

        return self.smartUnits[k].unit
    end

    local kguid = mint.ObjectGUID(k)

    if kguid and self.units[kguid] then
        return self.units[kguid]
    end

    if self.units[kguid] == nil then
        local obj = mint.Object(k)
        if obj and obj ~= "" then
            local unit = Unit:Create(obj)
            self:SetUnit(unit)
            return unit
        end
    end

    return self.units['none']
end

-- Constructor
---@return UnitManager
function UnitManager:New()
    local self = setmetatable({}, UnitManager)
    self.units = {}
    self.smartUnits = {}
    self.cache = mint.Cache:New()

    return self
end

-- Returns a unit SmartObject that can be used later
---@param token string
---@return Unit
function UnitManager:Get(token)
    local token_guid = mint.ObjectGUID(token)

    -- Unit has a guid and is not saved
    if token_guid and self.units[token_guid] == nil then
        if token == 'none' then
            self.units['none'] = Unit:Create("none")
        else
            local obj = mint.Object(token_guid)
            if obj and obj ~= "" then
                self.units[token_guid] = Unit:Create(obj)
            end
        end
    end

    -- Return a unit SmartObject with no cache time, refreshable
    return mint.SmartObject:New(self.units[token_guid] or self.units['none'], function()
        local this_guid = mint.ObjectGUID(token) or 'none'

        if self.units[this_guid] == nil then
            if token == 'none' then
                self.units['none'] = Unit:Create("none")
            else
                local obj = mint.Object(this_guid)
                if obj and obj ~= "" then
                    self.units[this_guid] = Unit:Create(obj)
                end
            end
        end

        return self.units[this_guid] or self.units['none']
    end)
end

-- Create a smart unit and cache it for .2 seconds
---@param token string
---@param cb fun():Unit
---@return Unit
function UnitManager:CreateSmartUnit(token, cb, cacheTime)
    local this_unit = cb()
    local cachedUnit = mint.SmartObject:New(this_unit, cb, 0.2)
	local cacheTime = cacheTime or 0.2

    if this_unit == nil then
        error("UnitManager:CreateSmartUnit - Invalid unit: " .. token)
    end

    if self.smartUnits[token] == nil then
        self.smartUnits[token] = {
            unit = cachedUnit,
            cb = cb
        }
    end

    self.cache:Set(token, cachedUnit, cacheTime)

    -- print("UnitManager: Creating SmartUnit:", token, "with", cachedUnit)

    return cachedUnit
end

-- Retrieve a unit by it's GUID
---@param guid string?
function UnitManager:GetUnitByGUID(guid)
    if not guid or guid == "" then
		error("UnitManager:GetUnitByGUID - Invalid or missing GUID")
	end

	return self.units[guid]
end

-- Set a unit in the UnitManager
---@param unit Unit
function UnitManager:SetUnit(unit)
    if not unit or not unit.guid then
		error("UnitManager:SetUnit - Invalid or missing unit")
	end

	self.units[unit.guid] = unit
end

-- Return the number of living enemies with this aura
---@param aura Aura
function UnitManager:GetNumEnemiesWithDebuff(aura, playerOnly)
    local cached = self.cache:Get("num_enemies_" .. aura.name)

    if cached then
        return cached
    end
    local count = 0

    mint.ObjectManager.combat:loop(function(enemy)
        if enemy.in_range and enemy.can_attack then
            if enemy:FindDebuff(aura, playerOnly and true or false):Active() then
                count = count + 1
            end
        end
    end)

    self.cache:Set("num_enemies_" .. aura.name, count, 0.5)

    return count
end

-- -- Smart AoE for placed spells
-- function UnitManager:SmartAoE(radius, range, anchor)

-- end

function UnitManager:GetInterruptibleUnits()
    local cached = self.cache:Get("interruptible_enemies")

    if cached then
        return cached
    end

    local count = 0

    mint.ObjectManager.combat:loop(function(enemy)
        if enemy.in_range and enemy.can_attack then
            if enemy:IsInterruptible() then
                count = count + 1
            end
        end
    end)

    self.cache:Set("interruptible_enemies", count, 1)

    return count
end

return UnitManager