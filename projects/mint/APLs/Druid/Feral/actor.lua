local unlocker,
---@class mint
mint,
addon = ...

--------------
--- Locals ---
--------------

local feral         = addon.druid.feral
local spells        = addon.spells
local player        = mint.UnitManager:Get("player")
local actionList    = {}

--------------------
--- Action Lists ---
--------------------

-- Action List - Extra
actionList.Extra = function ()
    spells.autoLoot()
    spells.catForm("moving")
    spells.travelForm("swimming")
    spells.catForm("fall_protection")
    spells.markOfTheWild()
end -- End Action List - Extra

-- Action List - Defensive
actionList.Defensive = function()
    spells.catForm("break_cc")
    spells.renewal()
    -- spells.removeCorruption()
    spells.barkskin()
    spells.survivalInstincts()
    spells.rejuvenation()
    spells.regrowth()
end -- End Action List - Defensive

-- Action List - Interrupts
actionList.Interrupts = function()
    spells.skullBash()
    -- spells.mightyBash()
    -- spells.maim()
end -- End Action List - Interrupts

-- Action List - Cooldown
actionList.Cooldown = function()
    spells.berserk()
    spells.convokeTheSpirits()
    spells.feralFrenzy()
end -- End Action List - Cooldown

-- Action List - PreCombat
actionList.PreCombat = function()
    spells.catForm("target_near")
    spells.prowl("auto_prowl")
    -- spells.wrath("precombat")
    spells.rake("precombat")
    spells.shred("precombat")
    spells.autoAttack("precombat")
end -- End Action List - PreCombat

-- Action List - Combat
actionList.Combat = function()
    spells.catForm("combat")
    spells.ferociousBite("execute")
    spells.autoAttack()
    spells.rake("stealth")
    spells.berserk()
    spells.tigersFury()
    spells.primalWrath()
    spells.rip()
    spells.ferociousBite()
    spells.thrash()
    spells.rake()
    spells.brutalSlash()
    spells.swipe()
    spells.shred()
    -- spells.moonfire()
    -- spells.wrath()
end -- End Action List - Combat

feral:Sync(function()
    if not player:IsDead() and not player:IsMounted() and not player:IsFlying() then
        actionList.Extra()
        actionList.Defensive()
        actionList.PreCombat()
        actionList.Interrupts()
        actionList.Cooldown()
        actionList.Combat()
    end
end)