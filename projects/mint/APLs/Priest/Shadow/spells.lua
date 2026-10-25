local unlocker,
---@class mint
mint,
addon = ...

local UnitManager   = mint.UnitManager
local ObjectManager = mint.ObjectManager
local Spell         = mint.Spell.New
local target  	    = UnitManager:Get("target")
local player  		= UnitManager:Get("player")
local none   		= UnitManager:Get("none")

local spells = {
    shadow_word_pain      = Spell(589, { ignore_facing = true, ignore_moving = true }),
    vampiric_touch        = Spell(34914, { ignore_facing = true, ignore_moving = true }),
    mind_blast            = Spell(8092, { ignore_channel = true }),
    mind_flay             = Spell(15407, { ignore_moving = false }),
    shadow_word_madness   = Spell(335467, { ignore_channel = true }),
    shadow_word_death     = Spell(32379, { ignore_channel = true }),
    smite                 = Spell(585),
    silence               = Spell(15487, { ignore_facing = true, ignore_moving = true, kick = true }),
    power_word_fortitude  = Spell(21562, { ignore_facing = true, ignore_moving = true }),
    shadowform            = Spell(232698, { ignore_facing = true, ignore_moving = true }),
    tentacle_slam         = Spell(1227280, { ignore_moving = true }),
    power_infusion        = Spell(10060, { ignore_facing = true, ignore_moving = true }),
}

local auras = {
    shadow_word_pain      = Spell(589),
    vampiric_touch        = Spell(34914),
    shadow_word_madness   = Spell(335467),
}

local targets = {}

-- Smart Multidotting Target for VT
targets.vampiric_touch_spread = UnitManager:CreateSmartUnit("spread_vt", function()
    local best_tar = nil
    local highest_hp = 0

    ObjectManager.enemies:loop(function(enemy)
        if enemy:IsDead() then return false end
        if not enemy:GetExists() then return false end
        
        -- Never spread logic to current target via spread (actor.lua handles primary target)
        if target and enemy.guid == target.guid then return false end
        
        -- Needs to be in combat natively
        if not enemy.in_combat then return false end
        
        -- Utilize robust Winkr aura checking
        if enemy:FindDebuffByID(34914, true):Active() then return false end
        
        if not player:HasLos(enemy) then return false end

        local dist = player:GetDistanceSquared(enemy)
        if dist > (40 * 40) then return false end

        local health = enemy:GetHealth()
        if health > highest_hp then
            highest_hp = health
            best_tar = enemy
        end

        return false
    end)

    if best_tar == nil then return none end
    return best_tar
end, 0.25)

targets.swp_spread = UnitManager:CreateSmartUnit("spread_swp", function()
    local best_tar = nil
    ObjectManager.enemies:loop(function(enemy)
        if enemy:IsDead() or not enemy:GetExists() or not enemy.in_combat then return false end
        if target and enemy.guid == target.guid then return false end
        if enemy:FindDebuffByID(589, true):Active() then return false end
        if player:GetDistanceSquared(enemy) > (40 * 40) then return false end
        if not player:HasLos(enemy) then return false end
        best_tar = enemy
        return true -- break loop
    end)
    return best_tar or none
end, 0.25)

-- Define callbacks to automatically cast to the proper unit
spells.vampiric_touch:AddCallback(function(spell, unit)
    if type(unit) == "string" then unit = mint.UnitManager:Get(unit) end
    unit = unit or mint.UnitManager:Get("target")
    if not unit or not unit:GetExists() or unit:IsFriend() then return false end
    return spell:Cast(unit)
end)

spells.shadow_word_pain:AddCallback(function(spell, unit)
    if type(unit) == "string" then unit = mint.UnitManager:Get(unit) end
    unit = unit or mint.UnitManager:Get("target")
    if not unit or not unit:GetExists() or unit:IsFriend() then return false end
    return spell:Cast(unit)
end)

spells.shadow_word_madness:AddCallback(function(spell, unit)
    unit = unit or mint.UnitManager:Get("target")
    if not unit or not unit:GetExists() or unit:IsFriend() then return false end
    return spell:Cast(unit)
end)

spells.mind_blast:AddCallback(function(spell, unit)
    unit = unit or mint.UnitManager:Get("target")
    if not unit or not unit:GetExists() or unit:IsFriend() then return false end
    return spell:Cast(unit)
end)

spells.mind_flay:AddCallback(function(spell, unit)
    unit = unit or mint.UnitManager:Get("target")
    if not unit or not unit:GetExists() or unit:IsFriend() then return false end
    return spell:Cast(unit)
end)

spells.shadow_word_death:AddCallback(function(spell, unit)
    unit = unit or mint.UnitManager:Get("target")
    if not unit or not unit:GetExists() or unit:IsFriend() then return false end
    return spell:Cast(unit)
end)

spells.smite:AddCallback(function(spell, unit)
    unit = unit or mint.UnitManager:Get("target")
    if not unit or not unit:GetExists() or unit:IsFriend() then return false end
    return spell:Cast(unit)
end)

spells.power_word_fortitude:AddCallback(function(spell, unit)
    return spell:Cast(mint.UnitManager:Get("player"))
end)

spells.shadowform:AddCallback(function(spell, unit)
    return spell:Cast(mint.UnitManager:Get("player"))
end)

spells.tentacle_slam:AddCallback(function(spell, unit)
    unit = unit or mint.UnitManager:Get("target")
    if not unit or not unit:GetExists() or unit:IsFriend() then return false end
    return spell:Cast(unit)
end)

spells.power_infusion:AddCallback(function(spell, unit)
    return spell:Cast(mint.UnitManager:Get("player"))
end)

addon.priest.data["Shadow"].spells = spells
addon.priest.data["Shadow"].auras = auras
addon.priest.data["Shadow"].targets = targets
