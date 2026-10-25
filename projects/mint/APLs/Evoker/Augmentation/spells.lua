local unlocker, mint, addon = ...

local Spell = mint.Spell.New

local spells = {
    -- Core Abilities
    living_flame = Spell(361469),
    azure_strike = Spell(362969),
    eruption = Spell(395160),
    
    -- Empowers
    fire_breath = Spell(357208),
    upheaval = Spell(396286),
    
    -- Cooldowns / Mobility
    breath_of_eons = Spell(403631),
    ebon_might = Spell(395296),
    tip_the_scales = Spell(370553),
    hover = Spell(358267),
    quell = Spell(351338), -- Interrupt
    
    -- Buffs
    blistering_scales = Spell(360827),
    prescience = Spell(409311),
    
    -- Auras/Procs
    essence_burst = 359618,
    ebon_might_aura = 395296,
    prescience_aura = 409311
}

-- Helper to add standard target-based callbacks
local function AddStandardCallback(spell)
    spell:AddCallback(function(s, target)
        local unit = target
        -- If it's not a table (unit object), resolve it from UnitManager
        if type(unit) ~= "table" then
            unit = mint.UnitManager:Get(target or "target")
        end
        
        if unit:GetExists() then
            return s:Cast(unit)
        end
        return false
    end)
end

-- Helper for self-casts
local function AddSelfCallback(spell)
    spell:AddCallback(function(s)
        local player = mint.UnitManager:Get("player")
        return s:Cast(player)
    end)
end

-- Core Abilities
AddStandardCallback(spells.living_flame)
AddStandardCallback(spells.azure_strike)
AddStandardCallback(spells.eruption)

-- Empowers
AddStandardCallback(spells.fire_breath)
AddStandardCallback(spells.upheaval)

-- Cooldowns / Utility
AddSelfCallback(spells.breath_of_eons)
AddSelfCallback(spells.ebon_might)
AddSelfCallback(spells.tip_the_scales)
AddSelfCallback(spells.hover)
AddStandardCallback(spells.quell)

-- Buffs
AddStandardCallback(spells.prescience)
AddStandardCallback(spells.blistering_scales)

addon.evoker.data["augmentation"].spells = spells

addon.evoker.data["augmentation"].spells = spells

addon.evoker.data["augmentation"].spells = spells

-- Functional Finders for Augmentation
addon.evoker.GetPrescienceTarget = function()
    local best = mint.UnitManager:Get("none")
    mint.FriendManager:Loop(function(unit)
        if unit.pointer == UnitGUID("player") then return false end
        if unit.is_dead then return false end
        if unit:FindBuffByID(395296, true):Active() then return false end -- Prescience
        
        if unit.role == "DAMAGER" then
            best = unit
            return true -- Found one
        end
        return false
    end)
    return best
end

addon.evoker.GetAugmentationTankTarget = function()
    local tank = mint.FriendManager:GetFirstTank()
    if tank and not tank.is_dead then
        return tank
    end
    return mint.UnitManager:Get("none")
end
