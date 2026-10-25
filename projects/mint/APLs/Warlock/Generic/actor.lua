local unlocker, ---@class mint
mint, addon = ...

local UnitManager   = mint.UnitManager
local ObjectManager = mint.ObjectManager
local gen       = addon.warlock.generic
local spells    = addon.warlock.data["generic"].spells
local auras     = addon.warlock.data["generic"].auras

local targets   = addon.warlock.data["generic"].targets
local SmartTarget = mint.SmartTarget

--------------------------------------------------------------------------------
-- Main Rotation Engine Loop
--------------------------------------------------------------------------------
gen:Sync(function()
    local player = UnitManager:Get("player")
    local target = UnitManager:Get("target")
    if not player or not player.alive then return end

    -- GCD Guard
    if mint.gcd > 0.1 then return end
    if UnitCastingInfo("player") or UnitChannelInfo("player") then return end

    -- Target validation for filler
    local hasTarget = UnitExists("target") and UnitCanAttack("player", "target") and not UnitIsDeadOrGhost("target")

    -- Auto-attack if target exists
    if hasTarget and not C_Spell.IsCurrentSpell(6603) then
        StartAttack()
    end

    -- Auto-Target: Swap to best target when current dies or is invalid
    if not hasTarget then
        SmartTarget:Acquire()
        return
    end

    ----------------------------------------------------------------------------
    -- 1. Maintain DoTs on Primary Target
    ----------------------------------------------------------------------------
    if hasTarget then
        if not target:FindDebuff(auras.agony, true):Active() then
            if spells.agony() then return true end
        end
        if not target:FindDebuff(auras.corruption, true):Active() then
            if spells.corruption() then return true end
        end
    end

    ----------------------------------------------------------------------------
    -- 2. Multi-DoT & Maintain: Agony
    ----------------------------------------------------------------------------
    if targets.agony_spread:GetExists() then
        if spells.agony(targets.agony_spread) then
            mint.console.log("Spreading Agony to:", targets.agony_spread.name)
            return
        end
    end

    ----------------------------------------------------------------------------
    -- 2.5 AOE Filler: Seed of Corruption
    ----------------------------------------------------------------------------
    if targets.seed_of_corruption:GetExists() then
        if spells.seed_of_corruption(targets.seed_of_corruption) then
            mint.console.log("Casting Seed of Corruption on:", targets.seed_of_corruption.name)
            return
        end
    end

    ----------------------------------------------------------------------------
    -- 2.6 Multi-DoT & Maintain: Corruption
    ----------------------------------------------------------------------------
    if targets.corruption_spread:GetExists() then
        if spells.corruption(targets.corruption_spread) then
            mint.console.log("Spreading Corruption to:", targets.corruption_spread.name)
            return
        end
    end

    ----------------------------------------------------------------------------
    -- 3. Filler: Shadow Bolt
    ----------------------------------------------------------------------------
    if hasTarget and not player:IsMoving() then
        if spells.shadow_bolt() then 
            return 
        end
    end
end)
