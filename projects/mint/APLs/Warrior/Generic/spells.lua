local unlocker, ---@class mint
mint, addon = ...

local Spell = mint.Spell.New
local Aura = mint.Spell.New

addon.warrior.data["generic"].spells = {
    auto_attack = Spell(6603),
    charge = Spell(100),
    slam = Spell(1464),
    shield_strike = Spell(23922),
    whirlwind = Spell(1680),
}

addon.warrior.data["generic"].auras = {
    charge_root = Aura(105771),
}

addon.warrior.data["generic"].targets = {}

local spells = addon.warrior.data["generic"].spells
local target = mint.UnitManager:Get("target")

spells.auto_attack:AddCallback(function(spell)
    if not target:GetExists() or target:IsFriend() then return false end
    return spell:Cast(target)
end)

spells.charge:AddCallback(function(spell)
    if not target:GetExists() or target:IsFriend() then return false end
    return spell:Cast(target)
end)

spells.slam:AddCallback(function(spell)
    if not target:GetExists() or target:IsFriend() then return false end
    return spell:Cast(target)
end)

spells.shield_strike:AddCallback(function(spell)
    if not target:GetExists() or target:IsFriend() then return false end
    return spell:Cast(target)
end)

spells.whirlwind:AddCallback(function(spell)
    -- Whirlwind is self-centered AoE, cast without target
    local usable, noResource = C_Spell.IsSpellUsable(1680)
    if not usable or noResource then return false end
    local cdInfo = C_Spell.GetSpellCooldown(1680)
    if cdInfo and cdInfo.duration > 1.5 then return false end
    CastSpellByName("Whirlwind")
    spell.lastCastAttempt = GetTime()
    return true
end)
