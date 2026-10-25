local unlocker, mint, addon = ...
local Spell = mint.Spell.New
local Item  = mint.Item.New
local player = mint.UnitManager:Get("player")
local target = mint.UnitManager:Get("target")

local spells = {
    -- Core Abilities
    heart_strike        = Spell(206930, { damage = "physical", cast_by_id = true, ignore_facing = true }),
    marrowrend          = Spell(195182, { damage = "physical", cast_by_id = true, ignore_facing = true }),
    blood_boil          = Spell(50842,  { damage = "magic", targeted = false, cast_by_id = true }),
    death_strike        = Spell(49998,  { damage = "physical", cast_by_id = true, ignore_facing = true }),
    death_and_decay     = Spell(43265,  { damage = "magic", targeted = false, cast_by_id = true }),
    death_caress        = Spell(195292, { damage = "physical", velocity = 25, cast_by_id = true }),
    vampiric_strike     = Spell(433901, { damage = "physical", cast_by_id = true, ignore_facing = true }), -- San'layn replacement
    
    -- Utility & CC
    mind_freeze         = Spell(47528,  { kick = true, ignore_casting = true, cast_by_id = true }),
    asphyxiate          = Spell(221562, { ignore_casting = true, cast_by_id = true }),
    blinding_sleet      = Spell(207167, { targeted = false, cast_by_id = true }),
    chains_of_ice       = Spell(45524,  { velocity = 25, cast_by_id = true }),
    death_grip          = Spell(49576,  { ignore_casting = true, velocity = 30, cast_by_id = true }),
    dark_command        = Spell(56222,  { ignore_casting = true, cast_by_id = true }),
    gorefiends_grasp    = Spell(108199, { targeted = false, cast_by_id = true }),
    
    -- Defensives
    vampiric_blood      = Spell(55233,  { ignore_casting = true, cast_by_id = true }),
    icebound_fortitude  = Spell(48792,  { ignore_casting = true, cast_by_id = true }),
    anti_magic_shell    = Spell(48707,  { ignore_casting = true, cast_by_id = true }),
    death_pact          = Spell(48743,  { ignore_casting = true, cast_by_id = true }),
    lichborne           = Spell(49039,  { ignore_casting = true, cast_by_id = true }),
    
    -- Cooldowns
    dancing_rune_weapon = Spell(49028,  { ignore_casting = true, cast_by_id = true }),
    raise_dead          = Spell(46585,  { targeted = false, ignore_casting = true, cast_by_id = true }),
    raise_ally          = Spell(61999,  { beneficial = true, cast_by_id = true }),
    
    -- Movement
    deaths_advance      = Spell(48265,  { ignore_casting = true, cast_by_id = true }),
    wraith_walk         = Spell(212552, { ignore_casting = true, cast_by_id = true }),
}

local auras = {
    -- Buffs
    bone_shield             = { id = 195181 },
    cleaving_strikes        = { id = 43265 },
    dancing_rune_weapon     = { id = 81256 },
    hemostasis              = { id = 273946 },
    crimson_scourge         = { id = 81136 },
    visceral_strength       = { id = 434157 },
    bloodied_blade          = { id = 458753 },
    essence_blood_queen     = { id = 433925 },
    
    -- Debuffs
    blood_plague            = { id = 55078 },
}

local items = {
    healthstone = Item(5512),
}

-- Registry assignment
addon.deathknight.data["Blood"].spells = spells
addon.deathknight.data["Blood"].auras  = auras
addon.deathknight.data["Blood"].items  = items

local targets = {}
addon.deathknight.data["Blood"].targets = targets

------------------------------
-- Smart Units (Tinkr Style)
------------------------------


-- Automated battlefield-aware interrupt selection
targets.kick = mint.UnitManager:CreateSmartUnit("bdk_kick", function()
    if not mint.data.toggles.kicks then return mint.UnitManager:Get("none") end
    
    local best = nil
    local best_pct = -1

    mint.ObjectManager.combat:loop(function(enemy)
        if enemy.dead or not enemy:GetExists() or not enemy:IsKickable() then return end
        
        if player:GetDistance(enemy) <= 15 and player:HasLos(enemy) then
            local pct = enemy:GetCastPercent()
            if pct > best_pct then
                best_pct = pct
                best = enemy
            end
        end
        return false
    end)
    return best or mint.UnitManager:Get("none")
end)

-- Best unit to taunt (Dark Command).
-- Filters for mobs attacking allies (Healers/DPS) that the player is not currently tanking.
targets.taunt = mint.UnitManager:CreateSmartUnit("blood_dk_taunt", function()
    -- Robust Group Check: Only taunt if in a real party/raid
    if GetNumGroupMembers() <= 1 then return mint.UnitManager:Get("none") end

    local player = mint.UnitManager:Get("player")
    local taunt_target = nil
    local highest_health = 0

    -- Scanning combatants for escaped aggro
    mint.ObjectManager.enemies:loop(function(enemy)
        enemy:Update()
        
        -- Guard: Skip if unit is dead or name is not yet resolved
        if enemy.is_dead or not enemy:GetExists() or not enemy.can_attack or enemy.name == "Unknown" then 
            return false 
        end
        
        -- Guard: Only within Dark Command range (30 yds)
        if not enemy:IsWithin(30, player) then return false end
        if not player:HasLos(enemy) then return false end

        -- Hard Logic: 
        -- 1. Player is NOT currently being tanked by this mob
        -- 2. Mob IS currently tanking a HEALER or DAMAGER from your party
        if not player:IsTanking(enemy) then
             local isAttackingHighValueTarget = false
             
             mint.FriendManager:Loop(function(friend)
                 -- We are only protecting non-tank PLAYERS (Healers/DPS)
                 -- Roles are only set for human players in groups
                 if not friend:Is(player) and (friend.role == "HEALER" or friend.role == "DAMAGER") then
                     if friend:IsTanking(enemy) then
                         isAttackingHighValueTarget = true
                         return true -- Found a reason to taunt
                     end
                 end
             end)

             if isAttackingHighValueTarget then
                 local health = enemy:GetMaxHealth()
                 if health > highest_health then
                     highest_health = health
                     taunt_target = enemy
                 end
             end
        end

        return false
    end)

    return taunt_target or mint.UnitManager:Get("none")
end)

------------------------------
-- Smart Callbacks
------------------------------

-- Death and Decay (Cleave Maintenance)
spells.death_and_decay:AddCallback(function(spell)
    if player:FindBuffByID(auras.cleaving_strikes):Active() then return false end
    
    -- Sync with Retail Tinkr: Movement Guard (Ground spells only fire when still)
    if player:IsMoving() then 
        return false 
    end

    -- Cast under player if in melee combat
    if player:GetEnemies(8) > 0 then
        return spell:CastUnder(player)
    end
    
    -- Otherwise cast under target if valid
    if target.exists and target.can_attack and not target.is_dead and player:GetDistance(target) <= 30 then
        return spell:CastUnder(target)
    end
    
    return false
end)

-- Dark Command (Taunt)
spells.dark_command:AddCallback(function(spell)
    -- Autonomous Background Taunting
    local u = targets.taunt
    if u:GetExists() and u.name ~= "Unknown" and spell:Castable(u) then
        mint.console.log("|cFFFF0000[Auto-Taunt]|r Protecting party member from:", u.name)
        return spell:Cast(u)
    end
    
    return false
end)

-- Death Grip (Emergency Taunt/Pull)
spells.death_grip:AddCallback(function(spell)
    local u = targets.taunt
    if u:GetExists() and not u:IsWithin(10) then
        return spell:Cast(u)
    end
    return false
end)

-- Mind Freeze (Kick)
spells.mind_freeze:AddCallback(function(spell)
    local u = targets.kick
    if u:GetExists() then
        if u:GetCastPercent() >= 25 or u:IsChanneling() then
            return spell:Cast(u)
        end
    end
    return false
end)

-- Death Strike (Survival & RP Dump)
spells.death_strike:AddCallback(function(spell)
    local hp = player:GetHP()
    local rp = player:GetPower(6) -- Force Runic Power (6)
    local profile = (addon.deathknight.blood and addon.deathknight.blood.settings) or {}
    local threshold = profile.death_strike_rp or 75
    
    -- Hard RP dump at 90+ or threshold breach
    if (hp < (profile.death_strike_hp or 70) or rp > threshold or rp > 90) then
        if target:GetExists() and target.can_attack and not target.is_dead and spell:IsInRange(target) then
            return spell:Cast(target)
        end
        
        -- Proximity dump
        local enemies = mint.ObjectManager.enemies
        local result = false
        enemies:each(function(e)
            if e:GetExists() and not e.is_dead and spell:IsInRange(e) then
                if spell:Cast(e) then result = true return true end
            end
            return false
        end)
        return result
    end
    return false
end)

-- Defensives
spells.vampiric_blood:AddCallback(function(spell)
    local profile = (addon.deathknight.blood and addon.deathknight.blood.settings) or {}
    if player:GetHP() < (profile.vampiric_blood_hp or 40) then
        return spell:Cast(player)
    end
    return false
end)

spells.icebound_fortitude:AddCallback(function(spell)
    local profile = (addon.deathknight.blood and addon.deathknight.blood.settings) or {}
    if player:GetHP() < (profile.icebound_hp or 30) then
        return spell:Cast(player)
    end
    return false
end)
