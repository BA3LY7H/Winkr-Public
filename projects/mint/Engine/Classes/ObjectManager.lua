local unlocker,
---@class mint
mint = ...

local Unit = mint.Unit
local UnitManager = mint.UnitManager

---@class ObjectManager
local Objects = {}
Objects.__index = Objects

function Objects:New()
    local self = setmetatable({}, Objects)

    self.units      = mint.List:New()
    self.enemies    = mint.List:New()
    self.combat     = mint.List:New() -- enemies in combat with us
    self.summons    = mint.List:New() -- Units created by players

    return self
end

-- We check to see if the unit is in the unit manager already
-- if not, we create a new unit and register it with the unit manager

local summons = {
    [224241] = true, -- Lightspawn
    [182892] = true, -- Effloresence
}

function Objects:Update()
    self.units:clear()
    self.enemies:clear()
    self.combat:clear()
    self.summons:clear()

    local units = mint.Objects(5)
    local players = mint.Objects(6)
    local player = mint.Objects(7)

    for _, object in pairs(units) do
        local unit = UnitManager:GetUnitByGUID(object)

        if not unit then
            unit = Unit:Create(object, true)
            UnitManager:SetUnit(unit)
        else
            unit:Update()
        end

        self.units:push(unit)

        if unit.can_attack then
            self.enemies:push(unit)

            if unit:CombatConfidence() > 80 or unit.in_combat or unit:IsUnit("target") then
                self.combat:push(unit)
            end
        end

        if summons[unit.id] then
            self.summons:push(unit)
        end
    end

    for _, object in pairs(players) do
        local unit = UnitManager:GetUnitByGUID(object)

        if not unit then
            unit = Unit:Create(object, true)
            UnitManager:SetUnit(unit)
        else
            unit:Update()
        end

        self.units:push(unit)
    end

    for _, object in pairs(player) do
        local unit = UnitManager:GetUnitByGUID(object)

        if not unit then
            unit = Unit:Create(object, true)
            UnitManager:SetUnit(unit)
        else
            unit:Update()
        end

        self.units:push(unit)
    end
end

return Objects