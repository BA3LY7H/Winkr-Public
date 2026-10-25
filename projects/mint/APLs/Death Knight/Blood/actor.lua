local unlocker, mint, addon = ...

-- Framework References
local UnitManager   = mint.UnitManager
local FriendManager = mint.FriendManager
local ObjectManager = mint.ObjectManager
local SmartTarget   = mint.SmartTarget
local Dispel        = mint.Dispel
local Queue         = mint.Queue
local Settings      = mint.Settings

-- Actor & Spec Data
local blood   = addon.deathknight.blood
local data    = addon.deathknight.data["Blood"]
local spells  = data.spells
local auras   = data.auras
local items   = data.items
local targets = data.targets

-- Directly link settings to the actor for callback access
local profile = mint.Settings.profile.deathknight.blood
blood.settings = profile

-- Global Prototype Patch for Death Knight Runic Power
local Unit = mint.Unit
local originalGetPower = Unit.GetPower
Unit.GetPower = function(self, powerType)
    if not powerType then
        local _, class = UnitClass(self:GetPointer())
        if class == "DEATHKNIGHT" then
            return UnitPower(self:GetPointer(), 6)
        end
    end
    return originalGetPower(self, powerType)
end

local originalGetPP = Unit.GetPP
Unit.GetPP = function(self, powerType)
    if not powerType then
        local _, class = UnitClass(self:GetPointer())
        if class == "DEATHKNIGHT" then
            local max = UnitPowerMax(self:GetPointer(), 6)
            if not max or max == 0 then return 0 end
            return (UnitPower(self:GetPointer(), 6) / max) * 100
        end
    end
    return originalGetPP(self, powerType)
end

-- SmartObject Wrappers
local player = UnitManager:Get("player")
local target = UnitManager:Get("target")

blood:Sync(function()
    -------------------------------------------------------
    -- 1. Global Guards
    -------------------------------------------------------
    if player:IsDead() or IsMounted() then return end
    if player:IsCasting() or player:IsChanneling() then return end
    
    -- Relaxed GCD guard for better queuing (50ms window)
    if mint.gcd > 0.05 then return end
    if not mint.data.toggles.engine then return end

    -------------------------------------------------------
    -- 2. Utility & Survival Loop (Callback-Driven)
    -------------------------------------------------------
    -- Auto-Defensives
    if mint.data.toggles.defensives then
        if spells.vampiric_blood() then return end
        if spells.icebound_fortitude() then return end
        
        local hp = player:GetHP()
        if hp < profile.ams_hp and spells.anti_magic_shell:Cast(player) then return end
        if hp < profile.death_pact_hp and spells.death_pact:Cast(player) then return end
    end

    -- BF Awareness: Taunts
    if spells.dark_command() then return end
    
    -------------------------------------------------------
    -- 3. Main Combat APL (Tinkr Style)
    -------------------------------------------------------
    -- Target Acquisition & Proactive Threat Switching
    -- If we have an 'Auto Taunt' target and it's within reach, we switch to it to regain threat via Melee
    local taunt_unit = targets.taunt
    if taunt_unit:GetExists() and taunt_unit:IsWithin(8) then
        if not target:IsUnit(taunt_unit) then
             mint.console.log("|cFFFF0000[Target-Swap]|r Regaining aggro on:", taunt_unit.name)
             winkr_SetNPC(taunt_unit.guid) -- Native Snap-Target
        end
    end

    if not target.exists or target.is_dead or not target.can_attack then
        SmartTarget:Acquire()
    end
    
    if not player:IsInCombat() and not (target.exists and target.can_attack) then return end

    -- A. Maintain Cleaving Strikes (DnD)
    if profile.maintain_cleave then
        if spells.death_and_decay() then return end
    end

    -- B. Survival & RP Dump (Death Strike)
    if spells.death_strike() then return end

    -- C. Maintenance: Bone Shield
    local shield = player:FindBuffByID(auras.bone_shield)
    if (not shield or shield:Remains() < 3 or shield:Count() < (profile.bone_shield_min or 6)) then
        if target.exists and target:IsWithin(8) then
            if spells.marrowrend:Cast(target) then return end
        elseif target.exists and spells.death_caress:Cast(target) then
            return
        end
    end

    -- D. Maintenance: Blood Plague & AoE Pressure
    if target.exists and target:IsWithin(10) and spells.blood_boil:Castable(player) then
        local plague = target:FindDebuffByID(auras.blood_plague)
        if (not plague or plague:Remains() < 3 or spells.blood_boil:GetChargesFractional() > 1.8) then
            if spells.blood_boil:Cast(player) then return end
        end
    end

    -- E. Runic Power Generation (Filler)
    if target.exists and target:IsWithin(8) then
        if player:GetRunes() >= 1 then
            if spells.vampiric_strike.known and spells.vampiric_strike:Cast(target) then return end
            if spells.heart_strike:Cast(target) then return end
        end
    end

    -- F. Final Filler
    if target.exists and target:IsWithin(10) and spells.blood_boil:Castable(player) then
        if spells.blood_boil:Cast(player) then return end
    end

    -- G. Automated Minion Management
    if profile.auto_ghoul and not UnitExists("pet") then
        if spells.raise_dead:Cast(player) then return end
    end

end, 0.1)

-------------------------------------------------------
-- Debug Commands
-------------------------------------------------------
SLASH_BLOODDEBUG1 = "/blooddebug"
SlashCmdList["BLOODDEBUG"] = function(msg)
    local rpRaw = UnitPower("player", 6)
    local rpMint = player:GetPower(6) -- Force Runic Power
    local hpCount = player:GetHP()
    local shield = player:FindBuffByID(auras.bone_shield)
    local dsValue = profile.death_strike_rp or 75
    
    local report = "Blood DK Diagnostic Report:\n"
    report = report .. string.format("HP: %.1f%%, RP (Raw): %d, RP (Mint): %d\n", hpCount, rpRaw, rpMint)
    report = report .. string.format("Death Strike Trigger: %d\n", dsValue)
    
    if target:GetExists() then
        report = report .. string.format("Target: %s, Dead: %s, Enemy: %s, InRange: %s\n", 
            target:GetName() or "Unknown", tostring(target.is_dead), tostring(target.can_attack), tostring(spells.death_strike:IsInRange(target)))
    else
        report = report .. "Target: NONE\n"
    end
    
    report = report .. string.format("Bone Shield: %d stacks\n", shield and shield:Count() or 0)
    report = report .. string.format("Death Strike: Known: %s, Usable: %s, Affordable: %s\n", 
        tostring(spells.death_strike:IsKnown()), tostring(spells.death_strike:IsUsable()), tostring(spells.death_strike:CanAfford()))
    
    -- Print to console as well
    mint.console.log(report)
    
    -- Print to console and standard chat box
    mint.console.log(report)
    print(report)
end
