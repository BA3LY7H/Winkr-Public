local unlocker, mint, addon = ...

local Spell = mint.Spell.New

local spells = {
    -- Core Abilities (ignore_channel: actor handles channel protection directly)
    living_flame = Spell(361469, { ignore_channel = true }),
    azure_strike = Spell(362969, { ignore_channel = true }),
    azure_sweep = Spell(1265867, { ignore_channel = true }),
    disintegrate = Spell(356995, { ignore_channel = true, ignore_usable = true }),
    pyre = Spell(357211, { ignore_channel = true }),
    
    -- Empowers (ignore_channel: empowers register as 'channeling' in WoW API)
    fire_breath = Spell(357208, { ignore_channel = true }),
    eternity_surge = Spell(359073, { ignore_channel = true }),
    
    -- Cooldowns / Mobility
    dragonrage = Spell(375087),
    deep_breath = Spell(353683),
    shattering_star = Spell(1265804),
    tip_the_scales = Spell(370553),
    hover = Spell(358267),
    quell = Spell(351338, { kick = true }), -- Interrupt
    -- Buffs
    blessing_of_the_bronze = Spell(364342, { targeted = false, beneficial = true }),
    source_of_magic = Spell(369459, { beneficial = true }),
    
    -- Dispels
    expunge = Spell(365585, { dispel = true, beneficial = true }),
    cauterizing_flame = Spell(374251, { dispel = true, beneficial = true }),
    
    -- Scalecommander Specific
    mass_disintegrate = Spell(433767),
    
    -- Flameshaper Specific
    consume_flame = Spell(444088),
}

-- Helper to add standard target-based callbacks
-- Now forwards the optional 'rank' argument for empowered spells
local function AddStandardCallback(spell)
    spell:AddCallback(function(s, target, rank)
        local unit = target
        -- If it's not a table (unit object), resolve it from UnitManager
        if type(unit) ~= "table" then
            unit = mint.UnitManager:Get(target or "target")
        end
        
        if unit:GetExists() and not unit:IsDead() then
            return s:Cast(unit, rank)
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
AddStandardCallback(spells.azure_sweep)
AddStandardCallback(spells.disintegrate)
AddStandardCallback(spells.pyre)
AddStandardCallback(spells.shattering_star)

-- Empowers
AddStandardCallback(spells.fire_breath)
AddStandardCallback(spells.eternity_surge)

-- Cooldowns
AddSelfCallback(spells.dragonrage)
AddSelfCallback(spells.tip_the_scales)
AddSelfCallback(spells.hover)
AddStandardCallback(spells.quell)

-- Buffs (Explicitly restricted to OOC to prevent Engine auto-casting loops)
spells.blessing_of_the_bronze:AddCallback(function(s)
    local player = mint.UnitManager:Get("player")
    if player.in_combat then return false end
    return s:Cast(player)
end)

spells.source_of_magic:AddCallback(function(s, target, rank)
    local player = mint.UnitManager:Get("player")
    if player.in_combat then return false end
    local unit = target
    if type(unit) ~= "table" then unit = mint.UnitManager:Get(target or "target") end
    if unit:GetExists() and not unit:IsDead() then
        return s:Cast(unit, rank)
    end
    return false
end)

-- Dispels
AddStandardCallback(spells.expunge)
AddStandardCallback(spells.cauterizing_flame)

-- Hero / Spec Specific
if spells.mass_disintegrate then AddStandardCallback(spells.mass_disintegrate) end
if spells.consume_flame then AddStandardCallback(spells.consume_flame) end

addon.evoker.data["devastation"].spells = spells
