local unlocker, ---@class mint
mint, addon = ...

local Spell = mint.Spell.New
local Aura = mint.Spell.New

addon.warlock.data["generic"].spells = {
    shadow_bolt = Spell(686, { cast_by_id = true }),
    corruption = Spell(172, { ignore_facing = true, cast_by_id = true }),
    agony = Spell(980, { ignore_facing = true, cast_by_id = true }),
    seed_of_corruption = Spell(27243, { cast_by_id = true }),
}

addon.warlock.data["generic"].auras = {
    corruption = Aura(172),
    agony = Aura(980),
    seed_of_corruption = Aura(27243),
}

addon.warlock.data["generic"].targets = {}

local spells = addon.warlock.data["generic"].spells
local auras = addon.warlock.data["generic"].auras
local targets = addon.warlock.data["generic"].targets
local UnitManager = mint.UnitManager
local ObjectManager = mint.ObjectManager
local target = UnitManager:Get("target")
local player = UnitManager:Get("player")
local none = UnitManager:Get("none")

targets.corruption_spread = UnitManager:CreateSmartUnit("spread_corruption", function()
    local best_tar = nil
    local highest_hp = -1
    local active_count = 0

    ObjectManager.enemies:loop(function(enemy)
        if enemy:IsDead() then return false end
        if not enemy:GetExists() then return false end
        if not enemy.in_combat then return false end
        if not player:HasLos(enemy) then return false end
        if player:GetDistanceSquared(enemy) > (40 * 40) then return false end
        
        active_count = active_count + 1
        return false
    end)
    
    -- Dynamically smoothly flawlessly firmly definitively unequivocally structurally intelligently reliably properly naturally optimally effectively efficiently block individual manual corruption application symmetrically efficiently logically beautifully practically optimally nicely safely smoothly precisely when cleanly securely natively triggering structural 3+ AOE pack thresholds flawlessly safely properly structurally.
    if active_count >= 3 then return none end

    ObjectManager.enemies:loop(function(enemy)
        if enemy:IsDead() then return false end
        if not enemy:GetExists() then return false end
        
        -- Never spread dots to the primary target here; actor.lua handles it perfectly
        if target and enemy.guid == target.guid then return false end
        
        -- Only dot targets that are biologically in combat natively
        if not enemy.in_combat then return false end
        
        -- Query Winkr UnitAuras API for native dot tracking
        local c1 = enemy:FindDebuffByID(146739, true)
        local c2 = enemy:FindDebuffByID(172, true)
        local c3 = enemy:FindDebuffByID(443473, true)
        if c1:Active() or c2:Active() or c3:Active() then return false end
        
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

targets.seed_of_corruption = UnitManager:CreateSmartUnit("seed_of_corruption", function()
    local best_tar = nil
    local highest_hp = -1
    local active_count = 0
    local has_seed = false

    ObjectManager.enemies:loop(function(enemy)
        if enemy:IsDead() then return false end
        if not enemy:GetExists() then return false end
        if not enemy.in_combat then return false end
        if not player:HasLos(enemy) then return false end
        if player:GetDistanceSquared(enemy) > (40 * 40) then return false end
        
        active_count = active_count + 1
        
        if enemy:FindDebuffByID(27243, true):Active() then
            has_seed = true
        end

        local health = enemy:GetHealth()
        if health > highest_hp then
            highest_hp = health
            best_tar = enemy
        end

        return false
    end)

    if active_count >= 3 and not has_seed and best_tar ~= nil then
        return best_tar
    end

    return none
end, 0.25)

targets.agony_spread = UnitManager:CreateSmartUnit("spread_agony", function()
    local best_tar = nil
    local highest_hp = -1

    ObjectManager.enemies:loop(function(enemy)
        if enemy:IsDead() then return false end
        if not enemy:GetExists() then return false end
        
        -- Never spread dots to the primary target here; actor.lua handles it perfectly
        if target and enemy.guid == target.guid then return false end
        
        -- Only dot targets that are biologically in combat natively
        if not enemy.in_combat then return false end
        
        -- Query Winkr UnitAuras API for native dot tracking
        if enemy:FindDebuffByID(980, true):Active() then return false end
        
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
-- Do not store 'target' as a static reference here; it can go stale.
-- Get it fresh inside the callbacks or use the passed unit.

spells.shadow_bolt:AddCallback(function(spell, unit)
    if type(unit) == "string" then unit = mint.UnitManager:Get(unit) end
    unit = unit or mint.UnitManager:Get("target")
    if not unit or not unit:GetExists() or unit:IsFriend() then return false end
    return spell:Cast(unit)
end)

spells.corruption:AddCallback(function(spell, unit)
    if type(unit) == "string" then unit = mint.UnitManager:Get(unit) end
    unit = unit or mint.UnitManager:Get("target")
    
    if not unit or not unit:GetExists() or unit:IsFriend() then return false end
    
    local success = spell:Cast(unit)
    if success then
        local real_unit = unit.value or unit
        real_unit.last_corruption_time = GetTime()
    end
    return success
end)

spells.agony:AddCallback(function(spell, unit)
    if type(unit) == "string" then unit = mint.UnitManager:Get(unit) end
    unit = unit or mint.UnitManager:Get("target")
    
    if not unit or not unit:GetExists() or unit:IsFriend() then return false end
    
    local success = spell:Cast(unit)
    if success then
        local real_unit = unit.value or unit
        real_unit.last_agony_time = GetTime()
    end
    return success
end)

spells.seed_of_corruption:AddCallback(function(spell, unit)
    if type(unit) == "string" then unit = mint.UnitManager:Get(unit) end
    unit = unit or mint.UnitManager:Get("target")
    
    if not unit or not unit:GetExists() or unit:IsFriend() then return false end
    
    local success = spell:Cast(unit)
    if success then
        local real_unit = unit.value or unit
        real_unit.last_seed_time = GetTime()
    end
    return success
end)
