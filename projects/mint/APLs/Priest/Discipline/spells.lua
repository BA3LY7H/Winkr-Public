local unlocker, ---@class mint
mint, addon = ...

local UnitManager   = mint.UnitManager
local Spell         = mint.Spell.New
local target  	    = UnitManager:Get("target")
local player  		= UnitManager:Get("player")

local spells = {
    power_word_shield    = Spell(17, { beneficial = true, ignore_moving = true }),
    power_infusion       = Spell(10060, { beneficial = true, ignore_moving = true }),
    shadow_word_pain     = Spell(589, { ignore_facing = true, ignore_moving = true }),
    penance              = Spell(47540, { ignore_moving = true, beneficial = true }),
    mind_blast           = Spell(8092),
    smite                = Spell(585),
    power_word_radiance  = Spell(194509, { beneficial = true }),
    flash_heal           = Spell(2061, { beneficial = true, ignore_moving = true }),
    ultimate_penitence   = Spell(421453, { ignore_moving = true, beneficial = true }),
}

local auras = {
    power_word_shield = Spell(17),
    surge_of_light    = Spell(114255),
    atonement         = Spell(194384),
    shadow_word_pain  = Spell(589),
}

-- Simple Callbacks to cast easily by executing spells.flash_heal(friend)
for k, spell in pairs(spells) do
    spell:AddCallback(function(spell, unit)
        unit = unit or target
        if not unit or not unit:GetExists() then return false end
        return spell:Cast(unit)
    end)
end

addon.priest.data["Discipline"].spells = spells
addon.priest.data["Discipline"].auras = auras