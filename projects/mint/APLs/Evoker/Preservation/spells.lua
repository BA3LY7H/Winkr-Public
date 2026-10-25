local unlocker, mint, addon = ...

local Spell = mint.Spell.New
local FriendManager = mint.FriendManager
local UnitManager = mint.UnitManager
local player = UnitManager:Get("player")
local none = UnitManager:Get("none")
local profile = mint.Settings.profile.evoker.preservation

local spells = {
    -- Core Healing Abilities
    living_flame = Spell(361469, { beneficial = true }),
    reversion = Spell(366155, { beneficial = true }),
    echo = Spell(364343, { beneficial = true }),
    verdant_embrace = Spell(360995, { beneficial = true }),
    emerald_blossom = Spell(355913, { targeted = true, beneficial = true, ignore_range = true, ignore_facing = true }),

    dream_breath = Spell(355936, { beneficial = true, targeted = false }), -- Non-targeted AoE
    rewind = Spell(357170, { beneficial = true, targeted = false }),
    
    -- DPS Abilities
    deep_breath = Spell(357210),
    fire_breath = Spell(357208, { targeted = false }),
    disintegrate = Spell(356995),
    azure_strike = Spell(362969),
    
    -- Utility
    quell = Spell(351338),
    blessing_of_the_bronze = Spell(364342, { beneficial = true, targeted = false, ignore_known = true }),
}

local auras = {
    echo = 364343,
    reversion = 366155,
    dream_breath = 355941,
    essence_burst = 359618,
    blessing_of_the_bronze = 364342,
}

addon.evoker.data["preservation"].spells = spells
addon.evoker.data["preservation"].auras = auras

----------------------------------------------------------------------------
-- Callbacks: Healing Logic
----------------------------------------------------------------------------

-- Echo: Spend Essence to apply buff to allies
spells.echo:AddCallback("Smart", function(spell)
    local lowest = FriendManager:GetLowest(95, function(unit)
        return not unit:FindBuff(auras.echo, true):Active()
    end)
    if lowest and lowest:GetExists() then
        return spell:Cast(lowest)
    end
    return false
end)

-- Reversion: Use on cooldown for HOT
spells.reversion:AddCallback("Smart", function(spell)
    local lowest = FriendManager:GetLowest(98, function(unit)
        return not unit:FindBuff(auras.reversion, true):Active()
    end)
    if lowest and lowest:GetExists() then
        return spell:Cast(lowest)
    end
    return false
end)

-- Verdant Embrace: Quick single-target burst
spells.verdant_embrace:AddCallback("Smart", function(spell)
    local lowest = FriendManager:GetLowest(profile.verdant_embrace_threshold)
    if lowest and lowest:GetExists() then
        return spell:Cast(lowest)
    end
    return false
end)

-- Emerald Blossom: AoE heal on group
spells.emerald_blossom:AddCallback("Smart", function(spell)
    local lowest = FriendManager:GetLowest(profile.emerald_blossom_threshold)
    if lowest and lowest:GetExists() then
        return spell:Cast(lowest)
    end
    return false
end)

-- Dream Breath: Frontal AoE healing
spells.dream_breath:AddCallback("Smart", function(spell)
    if FriendManager:GetCountBelow(profile.dream_breath_threshold) >= 2 then
        return spell:Cast(player)
    end
    return false
end)

-- Rewind: Massive damage window
spells.rewind:AddCallback("Emergency", function(spell)
    if FriendManager:GetCountBelow(profile.rewind_threshold) >= 3 then
        return spell:Cast(player)
    end
    return false
end)

-- Living Flame: Filler heal
spells.living_flame:AddCallback("Heal", function(spell)
    local lowest = FriendManager:GetLowest(profile.living_flame_threshold)
    if lowest and lowest:GetExists() then
        return spell:Cast(lowest)
    end
    return false
end)

----------------------------------------------------------------------------
-- Callbacks: DPS / Utility
----------------------------------------------------------------------------

-- Helper for standard unit-based casting (keyless)
local function AddStandardCallback(spell)
    spell:AddCallback(function(s, target_unit)
        local unit = target_unit
        if type(unit) ~= "table" then
            unit = UnitManager:Get(target_unit or "target")
        end
        if unit and unit:GetExists() and not unit:IsDead() then
            return s:Cast(unit)
        end
        return false
    end)
end

AddStandardCallback(spells.living_flame)
AddStandardCallback(spells.deep_breath)
AddStandardCallback(spells.fire_breath)
AddStandardCallback(spells.disintegrate)
AddStandardCallback(spells.azure_strike)

spells.quell:AddCallback("Smart Kick", function(spell)
    -- Target is already set in actor logic usually or we can scan
    local target = UnitManager:Get("target")
    if target:GetExists() and target:IsKickable() then
        return spell:Cast(target)
    end
    return false
end)

spells.blessing_of_the_bronze:AddCallback("Self", function(spell)
    return spell:Cast(player)
end)
