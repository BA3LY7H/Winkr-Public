local unlocker, ---@class mint
mint, addon = ...

local UnitManager   = mint.UnitManager
local ObjectManager = mint.ObjectManager
local Spell         = mint.Spell.New
local target  	    = UnitManager:Get("target")
local player  		= UnitManager:Get("player")
local none   		= UnitManager:Get("none")

local spells = {
    -- Core Abilities
    stormstrike         = Spell(17364),
    primal_strike       = Spell(73899), -- Primal Strike (low-level fallback)
    lava_lash           = Spell(408507),
    crash_lightning     = Spell(187874),
    lightning_bolt      = Spell(188196),
    chain_lightning     = Spell(188443),
    flame_shock         = Spell(470411, { ignore_facing = true, ignore_moving = true }),
    wind_shear          = Spell(57994, { kick = true }),
    feral_spirit        = Spell(51533, { targeted = false }),
    sundering           = Spell(197214, { targeted = false }),
    primordial_wave     = Spell(375982),
    doom_winds          = Spell(384352, { targeted = false }),
    ascendance          = Spell(114051, { targeted = false }),
    windstrike          = Spell(115356), -- Ascendance version of SS
    
    -- Buffs / Imbues / Shields
    skyfury             = Spell(462854, { ignore_facing = true, ignore_moving = true }),
    windfury_weapon     = Spell(33757, { ignore_facing = true, ignore_moving = true }),
    flametongue_weapon  = Spell(318038, { ignore_facing = true, ignore_moving = true }),
    lightning_shield    = Spell(192106, { ignore_facing = true, ignore_moving = true }),
    earth_shield        = Spell(974, { ignore_facing = true, ignore_moving = true }),
    
    -- Utility / Healing
    recuperate          = Spell(439709, { ignore_facing = true, ignore_moving = true }), -- OOC Heal (Midnight)
    healing_surge       = Spell(8004),
    
    -- Hero Talents (Midnight)
    surging_totem       = Spell(444995, { targeted = false }),
    voltaic_blaze       = Spell(470057),
    tempest             = Spell(454009),
}

local auras = {
    flame_shock         = Spell(188389),
    hot_hand            = Spell(215785),
    whirling_fire       = Spell(444985),
    crash_lightning     = Spell(187878),
    maelstrom_weapon    = Spell(187881),
    skyfury             = Spell(462854),
    lightning_shield    = Spell(192106),
    earth_shield        = Spell(974),
    ascendance          = Spell(114051),
    doom_winds          = Spell(384352),
}

-- Smart units for auto-interrupt
local targets = {}
targets.kick = UnitManager:CreateSmartUnit("enha_kick", function()
    local best = nil
    local best_pct = -1
    ObjectManager.combat:loop(function(enemy)
        if enemy:IsDead() or not enemy:IsEnemy() then return false end
        if not enemy:IsCastingOrChanneling() or not enemy:IsKickable() then return false end
        if not spells.wind_shear:IsInRange(enemy) then return false end
        
        local pct = enemy:GetCastPercent()
        if pct > best_pct then
            best_pct = pct
            best = enemy
        end
        return false
    end)
    return best or none
end, 0.1)

-- Map to addon data
addon.shaman.data["Enhancement"].spells  = spells
addon.shaman.data["Enhancement"].auras   = auras
addon.shaman.data["Enhancement"].targets = targets
