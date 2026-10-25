local unlocker, ---@class mint
mint, addon = ...

-- ! Mint Locals !--
local UnitManager       = mint.UnitManager
local ObjectManager     = mint.ObjectManager
local FriendManager     = mint.FriendManager
local Events            = mint.EventManager.New()
local Constants         = mint.Constants
local Spell             = mint.Spell.New
local Item              = mint.Item.New
local Cache             = mint.Cache.New()
local target            = UnitManager:Get("target")
local player            = UnitManager:Get("player")
local pet               = UnitManager:Get("pet")
local none              = UnitManager:Get("none")
local bin               = mint.bin
local toggles           = mint.data.toggles
local settings          = mint.Settings
local profile           = settings.profile.paladin.protection

local StopTimer = mint.data.StopTimer
local MoveTimer = mint.data.MoveTimer

local function CombatTime()
    local startTime = mint.combatStartTime or 0
    return GetTime() - startTime
end

local spells = {
	auto_attack 				= Spell(6603),
	ardent_defender 			= Spell(31850),
	avengers_shield 			= Spell(31935),
	avenging_wrath 				= Spell(31884, { targeted = false }),
	bastion_of_light 			= Spell(378974, { targeted = false }),
	blessed_hammer 				= Spell(204019, { targeted = false }),
	blessing_of_freedom 		= Spell(1044),
	blessing_of_protection 		= Spell(1022),
	blessing_of_sacrifice 		= Spell(6940),
	blessing_of_spellwarding 	= Spell(204018),
	blinding_light 				= Spell(115750, { targeted = false }),
	cleanse 					= Spell(4987),
	cleanse_toxins 				= Spell(213644),
	consecration 				= Spell(26573, { targeted = false }),
	devotion_aura 				= Spell(465, { targeted = false }),
	divine_shield 				= Spell(642, { targeted = false }),
	divine_steed 				= Spell(190784, { targeted = false }),
	divine_toll 				= Spell(375576, { targeted = false }),
	eye_of_tyr 					= Spell(387174, { targeted = false }),
	flash_of_light 				= Spell(19750),
	guardian_of_ancient_kings 	= Spell(86659, { targeted = false }),
	hammer_of_justice 			= Spell(853),
	hammer_of_wrath 			= Spell(24275),
	hammer_of_light				= Spell(427453, { cast_by_id = true }),
	hand_of_reckoning 			= Spell(62124),
	holy_bulwark 				= Spell(432459),
	intercession 				= Spell(391054),
	judgment 					= Spell(275779),
	lay_on_hands 				= Spell(633),
	moment_of_glory 			= Spell(327193, { targeted = false }),
	rebuke 						= Spell(96231),
	rite_of_sanctification 		= Spell(433568),
	sacred_weapon 				= Spell(432472),
	shield_of_the_righteous 	= Spell(53600, { targeted = false }),
	word_of_glory 				= Spell(85673),
	of_dusk_and_dawn			= Spell(409441)
}

local auras = {
	avenging_wrath 				= Spell(31884),
	barricade_of_faith			= Spell(385724),
	blessed_assurance 			= Spell(433019),
	blessing_of_protection 		= Spell(1022),
	bulwark_of_order			= Spell(209388),
	bulwark_of_righteous_fury 	= Spell(386652),
	consecration 				= Spell(188370),
	devotion_aura 				= Spell(465),
	divine_purpose 				= Spell(223819),
	divine_toll_resonance		= Spell(386730),
	eye_of_tyr					= Spell(387174), -- this is active on effected enemies
	faith_in_the_light 			= Spell(379041),
	faiths_armor				= Spell(379017),
	forbearance 				= Spell(25771),
	holy_bulwark				= Spell(432496),
	holy_bulwark_shield			= Spell(432607),
	moment_of_glory 			= Spell(327193),
	redoubt 					= Spell(280375),
	rite_of_sanctification 		= Spell(433550),
	sacred_weapon 				= Spell(432502),
	shield_of_the_righteous 	= Spell(132403),
	shining_light				= Spell(327510),
	shining_light_stacks 		= Spell(182104),
	strength_in_adversity		= Spell(393038),
	blessing_of_dawn			= Spell(385127),
	shake_the_heavens			= Spell(431536),
    inner_resilience            = Spell(450706), -- priory trinket defensive aura
    judgment                    = Spell(197277),
    masterwork                  = Spell(1238903),
}

local talents = {
    of_dusk_and_dawn = Spell(409441)
}

local items = {
    tome_of_lights_devotion     = Item(219309),
    healing_potion              = Item(244839),
    healthstone                 = Item(5512),
    tempered_potion             = Item(212264),
}

local blacklist = {
    -- Ara'kara
    [215968] = "Black Blood",
    [215826] = "Black Blood"
}

local dispelTypes = {
	["Poison"] = true,
	["Disease"] = true
}

local targets = {}

------------------------------
--- Helper Functions
------------------------------
local function IsTemplar()
	if UnitLevel("player") <= 70 then return false end
	return C_ClassTalents.GetActiveHeroTalentSpec() == 48
end

local function IsLightsmith()
	if UnitLevel("player") <= 70 then return false end
	return C_ClassTalents.GetActiveHeroTalentSpec() == 49
end

local function GetNextArmament()
	local info = C_Spell.GetSpellInfo(432459)

	if info.iconID == 5927637 then
		return "Sacred Weapon"
	else
		return "Holy Bulwark"
	end
end

------------------------------
--- SoTR Targets
------------------------------
local function SoTRTargets()
    local cached = Cache:Get("prot_sotr_targets")
    if cached then
        return cached
    end

    local player = mint.UnitManager:Get("player")
    if not player or not player:GetExists() then
        return 0
    end

    local count = 0
    local pcr = mint.ObjectCombatReach(player:GetPointer()) or 0
    local maxRange = 8.0

    ObjectManager.combat:loop(function(enemy)
        -- Basic validity checks
        if enemy.dead or not enemy:GetExists() or not enemy:IsEnemy() then
            return false
        end

        -- Cone check: 180° total => 90° bound
        if not player:IsFacing(enemy, 67.5) then
            return false
        end

        -- Edge-to-edge distance using combat reach (player + enemy)
        local ecr = mint.ObjectCombatReach(enemy:GetPointer()) or 0
        local distCenter = player:GetPosition():Distance(enemy:GetPosition())
        local edgeDist = distCenter - (pcr + ecr)

        if edgeDist <= maxRange + 1e-3 then
            count = count + 1
        end

        return false
    end)

    Cache:Set("prot_sotr_targets", count, 0.25)
    return count
end

------------------------------
--- Interrupt Logic
-- * This is much more in-depth for protection to be perfectly efficient.
------------------------------
local REB_PCT_MIN = 15   -- inclusive
local REB_PCT_MAX = 55   -- inclusive
local REBUKE_CAST_THRESHOLD_PCT = nil

local function NewRebukeCastThreshold()
    local v = math.random(REB_PCT_MIN, REB_PCT_MAX)
    if v == REBUKE_CAST_THRESHOLD_PCT then
        return NewRebukeCastThreshold()
    end
    REBUKE_CAST_THRESHOLD_PCT = v
    return v
end

-- Initialize once on load
NewRebukeCastThreshold()

-- Tunables
local SHIELD_SPEED_YDPS      = 35.0      -- projectile speed (yards/second)
local SHIELD_BUFFER_SECONDS  = 0.12      -- network + animation buffer
local REBUKE_CAST_THRESHOLD  = 0.30      -- 30% cast progress
local CHANNEL_KICK_TIME      = 0.45      -- seconds since channel started
local PENDING_TTL            = 1.25      -- seconds to avoid rebuking a target we just shielded

-- Pending Shield map: dest_guid -> expire_time
local PENDING_SHIELD = {}

-- Compute if Shield can land before the cast finishes.
local function can_interrupt_in_time_with_shield(enemy)
    local time_remaining = enemy:TimeToCast()
    if time_remaining <= 0 then return false end

    local distance = player:GetDistance(enemy)
    -- Use mint.gcd for GCD remains. Support both function or value forms.
    local gcd = mint.gcd

    local travel = (distance / SHIELD_SPEED_YDPS) + SHIELD_BUFFER_SECONDS
    local time_to_land = travel + gcd

    return time_to_land <= time_remaining, travel, distance
end

local function mark_pending_shield(dest_guid, travel)
    if not dest_guid then return end
    local now = GetTime()
    local ttl = (travel and travel > 0) and math.max(travel, PENDING_TTL) or PENDING_TTL
    PENDING_SHIELD[dest_guid] = now + ttl
end

local function is_pending_shield(dest_guid)
    if not dest_guid then return false end
    local exp = PENDING_SHIELD[dest_guid]
    if not exp then return false end
    if exp < GetTime() then
        PENDING_SHIELD[dest_guid] = nil
        return false
    end
    return true
end

-- Keep PENDING_SHIELD tidy based on CLEU for Avenger's Shield
Events:RegisterWoWEvent("COMBAT_LOG_EVENT_UNFILTERED", function()
    local ts, sub_event, _, source_guid, _, _, _, dest_guid, _, _, _, spell_id = CombatLogGetCurrentEventInfo()
    if source_guid ~= UnitGUID("player") then return end
    if spell_id ~= spells.avengers_shield.id then return end

    if sub_event == "SPELL_CAST_SUCCESS" then
        -- Conservative TTL so we don't immediately Rebuke the same target.
        mark_pending_shield(dest_guid, 0.9)
        return
    end

    if sub_event == "SPELL_DAMAGE" or sub_event == "SPELL_MISSED" then
        if dest_guid then
            PENDING_SHIELD[dest_guid] = nil
        end
    end
end)

------------------------------
--- Smart Units
------------------------------
    -- * Best unit to taunt during dungeons. We use highest max HP, as that is typically the most dangerous.
    targets.taunt = UnitManager:CreateSmartUnit("ppal_taunt", function(unit)
        local taunt_target = nil
        local highest_health = 0

        if IsInRaid() then return none end

        ObjectManager.combat:loop(function(enemy)
            if CombatTime() < 2 then return false end
            enemy:Update()
            if blacklist[enemy.id] then return false end
            if enemy.dead then return false end
            if player:IsTanking(enemy) then return false end
            if not spells.hand_of_reckoning:IsInRange(enemy) then return false end
            if not player:HasLos(enemy) then return false end

            -- If they're casting then there is no point, they won't move
            if enemy:IsCastingOrChanneling() then return false end

            if not player:IsFriendTanking(enemy) then return false end

            -- Largest max HP usually means more dangerous
            local health = enemy:GetMaxHealth()

            if health > highest_health then
                highest_health = health
                taunt_target = enemy
            end

            return false
        end)

        return taunt_target or none
    end)

    -- * Best unit that we are able to cast Hammer of Wrath on.
    targets.hammer_snipe = UnitManager:CreateSmartUnit("ppal_how_snipe", function()
        if not target:GetExists() or target:IsFriend() then
            return none
        end

        if player:FindBuff(auras.avenging_wrath):Active() then
            return target
        end

        -- Always prioritize our current target
        if target:GetExists() and target:IsEnemy() and target:GetHP() < 20 then
            return target
        end

        local best_tar = nil
        
        ObjectManager.combat:loop(function(enemy)
            enemy:Update()
            if enemy.dead then return false end
            if not player:IsFriendTanking(enemy) and not player:IsTanking(enemy) then return false end
            if enemy:GetHP() >= 20 then return false end
            if not spells.hammer_of_wrath:IsInRange(enemy) then return false end
            if not player:HasLos(enemy) then return false end

            best_tar = enemy
            return true
        end)

        if best_tar then
            return best_tar
        else
            -- If there are no units below 35%, just use target :(
            return target
        end
    end)

    -- * The unit with the lowest remaining duration on Judgment and the highest remaining health:
    --   1) If current target is a valid enemy for Judgment AND lacks our Judgment debuff, pick it immediately.
    --   2) Otherwise, pick the enemy that HAS our Judgment debuff with the LOWEST remaining duration.
    --      - Tie-breaker: higher remaining health.
    --   3) If no enemies have the debuff, pick the valid enemy with the HIGHEST remaining health.
    local function ValidEnemy(spell, target)
        if target.dead then return false end
        if not target:IsEnemy() then return false end
        if not spell:IsInRange(target) then return false end
        if not player:HasLos(target) then return false end
        if not player:IsFacing(target) then return false end

        return true
    end

    targets.judgment = UnitManager:CreateSmartUnit("ppal_judgment", function()
        -- 1) Prefer current target immediately if it's valid and does NOT have our Judgment debuff.
        if target:GetExists() and ValidEnemy(spells.judgment, target) then
            local jd = target:FindDebuff(auras.judgment)
            if not jd or not jd:Active() then
                return target
            end
        end

        -- 2) Among units that already have Judgment, choose the one with the lowest remaining duration.
        local best_debuff_unit      = nil
        local best_debuff_remains   = math.huge
        local best_debuff_unit_hp   = -1

        -- 3) Fallback tracker: highest remaining health among all valid enemies (used if no one has the debuff).
        local highest_hp_unit       = nil
        local highest_hp_value      = -1

        ObjectManager.combat:loop(function(enemy)
            enemy:Update()
            if not ValidEnemy(spells.judgment, target) then return false end

            -- Track fallback: highest remaining health
            local hp = enemy:GetHealth()
            if hp > highest_hp_value then
                highest_hp_value = hp
                highest_hp_unit  = enemy
            end

            -- Consider only enemies that currently have our Judgment debuff for the primary selection
            local jd = enemy:FindDebuff(auras.judgment)
            if jd and jd:Active() then
                local remains = jd:Remains() or 0
                if (remains < best_debuff_remains) or (remains == best_debuff_remains and hp > best_debuff_unit_hp) then
                    best_debuff_remains = remains
                    best_debuff_unit_hp = hp
                    best_debuff_unit    = enemy
                end
            end

            return false
        end)

        if best_debuff_unit then
            return best_debuff_unit
        end

        if highest_hp_unit then
            return highest_hp_unit
        end

        return none
    end)


    -- * The friend with the longest duration on a dispellable aura.
    -- Dispel Handling
    targets.dispel = UnitManager:CreateSmartUnit("ppal_dispel", function()
        local dispel_tar = nil

        if not toggles.dispels then
            return none
        end

        FriendManager:Loop(function(friend)
            if friend:IsDead() then return false end
            if not spells.cleanse_toxins:IsInRange(friend) then return false end
            if not friend:HasDebuffType(dispelTypes) then return false end
            -- if not player:HasLos(friend) then return false end

            dispel_tar = friend

            return true
        end)


        if dispel_tar == nil then
            return none
        end

        return dispel_tar
    end)

    -- * The best avenger's shield target, primarily for interrupts.
    targets.avengers_shield = UnitManager:CreateSmartUnit("ppal_avengers_shield", function()
        local chosen       = nil
        local best_dist    = -1
        local best_castpct = -1

        ObjectManager.combat:loop(function(enemy)
            enemy:Update()
            if enemy.dead then return false end
            if not enemy:IsCastingOrChanneling() then return false end
            if not enemy:IsKickable() then return false end
            if not spells.avengers_shield:IsInRange(enemy) then return false end
            if not player:HasLos(enemy) then return false end
            if not player:IsFacing(enemy) then return false end

            local ok, travel, dist = can_interrupt_in_time_with_shield(enemy)
            if not ok then return false end

            local pct = enemy:GetCastPercent()

            -- Primary: farther distance; Secondary: higher cast percent
            if (dist > best_dist) or (dist == best_dist and pct > best_castpct) then
                best_dist    = dist
                best_castpct = pct
                chosen       = enemy
            end
            return false
        end)

        if chosen then
            return chosen
        end

        -- Fallback: use current target for damage if it's valid (even if not casting)
        if target:GetExists()
            and not target:IsDead()
            and target:IsEnemy()
            and spells.avengers_shield:IsInRange(target)
            and player:HasLos(target)
            and player:IsFacing(target)
        then
            return target
        end

        return none
    end)


    -- * The best unit to interrupt with Rebuke.
    targets.kick = UnitManager:CreateSmartUnit("ppal_kick", function()
        if not mint.data.toggles.kicks then
            return none
        end

        local best = nil
        local best_pct = -1

        ObjectManager.combat:loop(function(enemy)
            enemy:Update()
            if enemy.dead then return false end
            if not enemy:IsCastingOrChanneling() then return false end
            if not enemy:IsKickable() then return false end
            if not spells.rebuke:IsInRange(enemy) then return false end

            local guid = enemy.guid
            if is_pending_shield(guid) then return false end

            local pct = enemy:GetCastPercent()
            if pct > best_pct then
                best_pct = pct
                best     = enemy
            end
            return false
        end)

        return best or none
    end)

    -- * The best unit to interrupt with Hammer of Justice.
    targets.stun = UnitManager:CreateSmartUnit("ppal_stun", function()
        if not toggles.kicks then return none end
        if not profile.auto_hoj then return none end

        local best = nil
        local best_pct = -1

        ObjectManager.combat:loop(function(enemy)
            enemy:Update()
            if enemy.dead then return false end
            if not enemy:IsCastingOrChanneling() then return false end
            if not enemy:CanStun() then return false end

            local kickable = enemy:IsKickable()
            local rebuke_ok = kickable and (not spells.rebuke:IsOnCD()) and spells.rebuke:IsInRange(enemy)
            if rebuke_ok then return false end

            local guid = enemy.guid
            if is_pending_shield(guid) then return false end

            if not spells.hammer_of_justice:IsInRange(enemy) then return false end

            local pct = enemy:GetCastPercent()
            if pct > best_pct then
                best_pct = pct
                best     = enemy
            end
            return false
        end)

        return best or none
    end)

------------------------------
--- Hero Talent Functions
------------------------------

------------------------------
--- Tome of Light's Devotion
------------------------------
items.tome_of_lights_devotion:AddCallback("Offensive", function(item)
    if not item:IsEquippedAndUsable() then return false end

    if player:FindBuff(auras.inner_resilience):Active() then
        return item:Use(none)
    end

    return false
end)

------------------------------
--- Healing Potion
------------------------------
items.healing_potion:AddCallback(function(item)
    if not item:IsEquippedAndUsable() then return false end

    if player:GetHP() > profile.potion_threshold then
        return false
    end

    return item:Use(none)
end)

------------------------------
--- Healthstone
------------------------------
items.healthstone:AddCallback(function(item)
    if not item:IsEquippedAndUsable() then return false end

    if player:GetHP() > profile.stone_threshold then
        return false
    end

    return item:Use(none)
end)

------------------------------
--- Tempered Potion
------------------------------
items.tempered_potion:AddCallback(function(item)
    if not profile.offensive_potions then return false end
    if not item:IsEquippedAndUsable() then return false end

    if not player:FindBuff(auras.avenging_wrath):Active() then
        return false
    end

    return item:Use(none)
end)

------------------------------
--- Auto Attack
------------------------------
spells.auto_attack:AddCallback(function(spell)

end)

------------------------------
--- Ardent Defender
------------------------------
spells.ardent_defender:AddCallback(function(spell)

end)

------------------------------
--- Avenger's Shield
------------------------------
spells.avengers_shield:AddCallback("Snipe Interrupts", function(spell)
    local u = targets.avengers_shield
    if not u:GetExists() or u:IsFriend() then return false end
    if not u:IsCastingOrChanneling() then return false end
    if not u:IsKickable() then return false end
    if not spell:IsInRange(u) then return false end
    if not player:HasLos(u) then return false end
    if not player:IsFacing(u) then return false end

    local ok_in_time, travel = can_interrupt_in_time_with_shield(u)
    if not ok_in_time then return false end

    if spell:Cast(u) then
        local guid = u.guid
        mark_pending_shield(guid, travel)
        return mint.NotificationManager:AddNotification(135874, "Interrupted " .. C_Spell.GetSpellName(u:GetCastSpellID() or 853), 3)
    end

    return false
end)

-- # Use Avenger’s Shield in AoE (3+ targets) to trigger Bulwark buff if it’s not already up.
-- actions.standard+=/avengers_shield,if=!buff.bulwark_of_righteous_fury.up&spell_targets.shield_of_the_righteous>=3
spells.avengers_shield:AddCallback("Multi Target", function(spell)
    if not targets.avengers_shield:GetExists() or targets.avengers_shield:IsFriend() then 
        return false 
    end

    if SoTRTargets() <= 3 then return false end

    if player:FindBuff(auras.bulwark_of_righteous_fury):Active() then
        return false
    end

    return spell:Cast(targets.avengers_shield)
end)

-- # Use Avenger’s Shield if Lights Guidance isn’t talented.
-- * This is Lightsmith exclusive logic.
-- actions.standard+=/avengers_shield,if=!talent.lights_guidance.enabled
spells.avengers_shield:AddCallback("Lightsmith", function(spell)
    if not targets.avengers_shield:GetExists() or targets.avengers_shield:IsFriend() then 
        return false 
    end

    if IsTemplar() then return false end

    return spell:Cast(targets.avengers_shield)
end)

-- # Cast Avenger’s Shield as filler/priority damage.
-- actions.standard+=/avengers_shield
spells.avengers_shield:AddCallback(function(spell)
    if not targets.avengers_shield:GetExists() or targets.avengers_shield:IsFriend() then 
        return false 
    end

    return spell:Cast(targets.avengers_shield)
end)

------------------------------
--- Avenging Wrath
------------------------------
spells.avenging_wrath:AddCallback(function(spell)
	if not mint.data.toggles.cooldowns then
		return false
	end

	if player:GetEnemies(12) < 1 then
		return false
	end

	-- Need to add TTD
    if mint.TimeToDie.ActiveFightRemains() < 15 then
        return false
    end

	return spell:Cast(player) and mint.NotificationManager:AddNotification(135875, "Avenging Wrath", 3)
end)

------------------------------
--- Bastion of Light
------------------------------
spells.bastion_of_light:AddCallback(function(spell)

end)

------------------------------
--- Blessed Hammer
------------------------------
spells.blessed_hammer:AddCallback(function(spell)
	if not target:GetExists() or target:IsFriend() then
		return false
	end

	-- If we are already capped and no one is around, hold.
	if player:GetPower(9) > 4 and SoTRTargets() == 0 then
		return false
	end

	return spell:Cast(none)
end)

-- # Use Blessed Hammer under the same conditions (Blessed Assurance active, <3 targets).
-- actions.standard+=/blessed_hammer,if=buff.blessed_assurance.up&spell_targets.shield_of_the_righteous<3
spells.blessed_hammer:AddCallback("Low Targets", function(spell)
	if not target:GetExists() or target:IsFriend() then return false end

    if not player:FindBuff(auras.blessed_assurance):Active() then
        return false
    end

    if SoTRTargets() >= 3 or SoTRTargets() == 0 then return false end

	return spell:Cast(none)
end)

-- # Use Blessed Hammer if Blessed Assurance or Shake the Heavens is active (<3 AoE).
-- actions.standard+=/blessed_hammer,if=(buff.blessed_assurance.up&spell_targets.shield_of_the_righteous<3)|buff.shake_the_heavens.up
spells.blessed_hammer:AddCallback("Shake the Heavens", function(spell)
	if not target:GetExists() or target:IsFriend() then return false end

    if player:FindBuff(auras.shake_the_heavens):Active() then
        return spell:Cast(none)
    else
        if not player:FindBuff(auras.blessed_assurance):Active() then
            return false
        end

        if SoTRTargets() >= 3 or SoTRTargets() == 0 then return false end

        return spell:Cast(none)
    end

    return false
end)

------------------------------
--- Blessing of Freedom
------------------------------
spells.blessing_of_freedom:AddCallback(function(spell)

end)

------------------------------
--- Blessing of Protection
------------------------------
spells.blessing_of_protection:AddCallback(function(spell)

end)

------------------------------
--- Blessing of Sacrifice
------------------------------
spells.blessing_of_sacrifice:AddCallback(function(spell)

end)

------------------------------
--- Blessing of Spellwarding
------------------------------
spells.blessing_of_spellwarding:AddCallback(function(spell)

end)

------------------------------
--- Blinding Light
------------------------------
spells.blinding_light:AddCallback(function(spell)

end)

------------------------------
--- Cleanse
------------------------------
spells.cleanse:AddCallback(function(spell)

end)

------------------------------
--- Cleanse Toxins
------------------------------
spells.cleanse_toxins:AddCallback(function(spell)

end)

------------------------------
--- Consecration
------------------------------
spells.consecration:AddCallback("Maintain Buff", function(spell)
	if player:FindBuff(auras.consecration):Active() then
		return false
	end

	if StopTimer:GetTime() < 0.20 then
		return false
	end

	if player:GetEnemies(12) < 1 then
		return false
	end

	if player:IsMoving() then
		return false
	end

	return spell:Cast(none)
end)

spells.consecration:AddCallback("Filler", function(spell)
	return spell:Cast(none)
end)

------------------------------
--- Devotion Aura
------------------------------
spells.devotion_aura:AddCallback(function(spell)
    if player:FindBuff(auras.devotion_aura):Active() then
		return false
	end

	if player:IsMounted() then
		return false
	end

	return spell:Cast(player)
end)

------------------------------
--- Divine Shield
------------------------------
spells.divine_shield:AddCallback(function(spell)

end)

------------------------------
--- Divine Steed
------------------------------
spells.divine_steed:AddCallback(function(spell)

end)

------------------------------
--- Divine Toll
------------------------------
spells.divine_toll:AddCallback("Multi Target", function(spell)
    if not addon.paladin.settings["Protection"].DivineToll then return false end
    if SoTRTargets() < 3 then return false end
    if not target:GetExists() or target:IsFriend() then return false end
    if player:GetPower(9) > 0 then return false end

    return spell:Cast(none)
end)

-- # Cast Divine Toll if no adds soon, or next adds wave is more than 10s away.
-- * In M+ content, we're going to press this manually, or with <4 Holy Power in single target, or 0 Holy Power in multi target.
-- actions.standard+=/divine_toll,if=(!raid_event.adds.exists|raid_event.adds.in>10)
spells.divine_toll:AddCallback("Single Target", function(spell)
    if not addon.paladin.settings["Protection"].DivineToll then return false end
    if SoTRTargets() > 1 then return false end
    if not target:GetExists() or target:IsFriend() then return false end
    if player:GetPower(9) > 4 then return false end

    return spell:Cast(none)
end)

------------------------------
--- Eye of Tyr
------------------------------
spells.eye_of_tyr:AddCallback(function(spell)

end)

-- # Use Eye of Tyr if you have Inmost Light (adds in >=45s or 3+ targets) and no Lights Deliverance.
-- * This is Lightsmith exclusive logic.
-- actions.standard+=/eye_of_tyr,if=(talent.inmost_light.enabled&raid_event.adds.in>=45|spell_targets.shield_of_the_righteous>=3)&!talent.lights_deliverance.enabled
spells.eye_of_tyr:AddCallback("Lightsmith", function(spell)
    if IsTemplar() then return false end
    if not target:GetExists() or target:IsFriend() then 
        return false 
    end

    if SoTRTargets() < 3 then
        return false
    end

    if StopTimer:GetTime() < 0.25 then
		return false
	end

	if player:IsMoving() then
		return false
	end

    return spell:Cast(none)
end)

------------------------------
--- Flash of Light
------------------------------
spells.flash_of_light:AddCallback(function(spell)

end)

------------------------------
--- Guardian of Ancient Kings
------------------------------
spells.guardian_of_ancient_kings:AddCallback(function(spell)

end)

------------------------------
--- Hammer of Justice
------------------------------
spells.hammer_of_justice:AddCallback("Interrupt", function(spell)
    if not toggles.kicks then return false end
    local u = targets.stun
    if not u:GetExists() then return false end
    if not u:IsCastingOrChanneling() then return false end
    if not spell:IsInRange(u) then return false end

    -- If a proper kick is available, prefer it over stun.
    if u:IsKickable() and (not spells.rebuke:IsOnCD()) and spells.rebuke:IsInRange(u) then
        return false
    end

    local threshold_pct = REBUKE_CAST_THRESHOLD_PCT or NewRebukeCastThreshold()

    if u:IsCasting() then
        if u:GetCastPercent() < threshold_pct then
            return false
        end
        return spell:Cast(u) and mint.NotificationManager:AddNotification(135963, "Interrupt " .. C_Spell.GetSpellName(u:GetCastSpellID() or 853), 3)
    end

    if u:IsChanneling() then
        if u:GetTimeSinceStartedCast() < CHANNEL_KICK_TIME then
            return false
        end

        return spell:Cast(u) and mint.NotificationManager:AddNotification(135963, "Interrupt " .. C_Spell.GetSpellName(u:GetCastSpellID() or 853), 3)
    end

    return false
end)


------------------------------
--- Hammer of Wrath
------------------------------
spells.hammer_of_wrath:AddCallback(function(spell)
    if not targets.hammer_snipe:GetExists() or targets.hammer_snipe:IsFriend() then
		return false
	end

    return spell:Cast(targets.hammer_snipe)
end)

------------------------------
--- Hammer of Light
------------------------------
spells.hammer_of_light:AddCallback(function(spell)

end)

------------------------------
--- Hand of Reckoning
------------------------------
spells.hand_of_reckoning:AddCallback(function(spell)
	if not targets.taunt:GetExists() or targets.taunt:IsFriend() then
		return false
	end

	return spell:Cast(targets.taunt)
end)

------------------------------
--- Holy Bulwark
------------------------------
spells.holy_bulwark:AddCallback(function(spell)
    if GetNextArmament() == "Sacred Weapon" then
		return false
	end

	return spell:Cast(player) and mint.NotificationManager:AddNotification(5927636, "Holy Bulwark", 3)
end)

------------------------------
--- Intercession
------------------------------
spells.intercession:AddCallback(function(spell)

end)

------------------------------
--- Judgment
------------------------------
-- # Cast Judgment when the target’s Judgment debuff is about to fall off,
-- # or when you have 2+ charges or the recharge will finish within a GCD.
-- actions.standard=judgment,target_if=min:debuff.judgment.remains,if=charges>=2|full_recharge_time<=gcd.max
spells.judgment:AddCallback("Avoid Cap", function(spell)
    if not targets.judgment:GetExists() or targets.judgment:IsFriend() then
		return false
	end

    if spell:GetFullRechargeTime() > mint.max_gcd then
		return false
	end

	return spell:Cast(targets.judgment)
end)

-- # Cast Judgment in AoE if 4+ targets, Bulwark buff stacked to 3+, and you’re low on Holy Power (<3).
-- * We want to target the unit with lowest judgment debuff time. This is essentially trying to get us enough Holy Power to cast SoTR ASAP
-- actions.standard+=/judgment,target_if=min:debuff.judgment.remains,if=spell_targets.shield_of_the_righteous>3&buff.bulwark_of_righteous_fury.stack>=3&holy_power<3
spells.judgment:AddCallback("Multi Target", function(spell)
    -- The whole point is to generate HP for SoTR
    if player:GetPower(9) >= 3 then return false end

    -- Requires 4+ SotR targets
    if SoTRTargets() <= 3 then return false end

    -- Require Bulwark of Righteous Fury at 3+ stacks to make the coming SotR hit hard.
    local borf = player:FindBuff(auras.bulwark_of_righteous_fury)
    if not borf or not borf:Active() or borf:Count() < 3 then return false end

    local u = targets.judgment
    if not u:GetExists() or u:IsFriend() then return false end

    return spell:Cast(u)
end)

-- # Use Judgment during Avenging Wrath if Hammer and Anvil talent is active.
-- * Judgment target should probably be within melee range (or like 12 yards) of the player to maximize Hammer & Anvil damage.
-- actions.standard+=/judgment,target_if=min:debuff.judgment.remains,if=(buff.avenging_wrath.up&talent.hammer_and_anvil.enabled)
spells.judgment:AddCallback("Wings", function(spell)
    if not targets.judgment:GetExists() or targets.judgment:IsFriend() then
		return false
	end

    if not player:FindBuff(auras.avenging_wrath):Active() then
        return false
    end

    return spell:Cast(targets.judgment)
end)

-- # Keep Judgment rolling normally.
-- actions.standard+=/judgment,target_if=min:debuff.judgment.remains
spells.judgment:AddCallback(function(spell)
    if not targets.judgment:GetExists() or targets.judgment:IsFriend() then
		return false
	end

    return spell:Cast(targets.judgment)
end)

------------------------------
--- Lay on Hands
------------------------------
spells.lay_on_hands:AddCallback(function(spell)
	if player:GetHP() > profile.loh_threshold then return false end
	if player:FindDebuff(auras.forbearance):Active() then return false end

	return spell:Cast(player) and mint.NotificationManager:AddNotification(135928, "Lay on Hands (Prevent Death)", 3)
end)

------------------------------
--- Moment of Glory
------------------------------
spells.moment_of_glory:AddCallback(function(spell)

end)

------------------------------
--- Rebuke
------------------------------
spells.rebuke:AddCallback("Interrupt", function(spell)
    if not mint.data.toggles.kicks then return false end
    local u = targets.kick
    if not u:GetExists() then return false end
    if not u:IsCastingOrChanneling() then return false end
    if not u:IsKickable() then return false end
    if not spell:IsInRange(u) then return false end

    -- Skip if we just sent a shield
    local guid = u.guid
    if is_pending_shield(guid) then return false end

    local threshold_pct = REBUKE_CAST_THRESHOLD_PCT or NewRebukeCastThreshold()

    if u:IsCasting() then
        if u:GetCastPercent() < threshold_pct then
            return false
        end
        if spell:Cast(u) then
            -- pick a fresh % for the next kick
            NewRebukeCastThreshold()
            mint.NotificationManager:AddNotification(523893, "Interrupted " .. C_Spell.GetSpellName(u:GetCastSpellID() or 853), 3)
            return true
        end
        return false
    end

    if u:IsChanneling() then
        if u:GetTimeSinceStartedCast() < CHANNEL_KICK_TIME then
            return false
        end
        if spell:Cast(u) then
            -- also refresh for symmetry after a channel kick
            NewRebukeCastThreshold()
            mint.NotificationManager:AddNotification(523893, "Interrupted " .. C_Spell.GetSpellName(u:GetCastSpellID() or 853), 3)
            return true
        end
        return false
    end

    return false
end)


------------------------------
--- Rite of Sanctification
------------------------------
spells.rite_of_sanctification:AddCallback(function(spell)

end)

------------------------------
--- Sacred Weapon
------------------------------
local function WillCastAvengingWrathSoon()
    -- Mirrors the Avenging Wrath callback logic so Sacred Weapon holds only when Wings would *actually* be used.
    if not toggles.cooldowns then return false end
    if player:GetEnemies(12) < 1 then return false end

    -- Your AW callback refuses to cast if TTD < 15
    local ttd = mint.TimeToDie.ActiveFightRemains()
    if ttd < 15 then return false end

    -- If AW is ready now, we consider it "about to be cast".
    if not spells.avenging_wrath:IsOnCD() then return true end

    -- If AW CD is short, and there’s enough fight time to still get a full AW after it comes up,
    -- treat it as "soon".
    local rem = spells.avenging_wrath:GetRemainingCD()
    -- small cushion ~= one GCD; adjust if you like
    if rem <= (15 + mint.max_gcd) and ttd > (15 + rem + mint.max_gcd) then
        return true
    end

    return false
end

-- # Cast Sacred Weapon when it’s the next armament and:
-- # you don’t have it up or it’s about to fall (<6s), AW not active, AW coming soon,
-- # and you’re at max Masterwork stacks.
-- * Again, we send this at 5 MW stacks. Ideally, as soon as we get the second charge so we can send bulwark right after.
-- * We can use this logic to check around wings as well.
-- * We want to wait until Masterwork is about to fall off ( < 3 seconds) before sending, as it will send 100% lesser 
-- * weapons while at 5 stacks with weapon next
-- actions.standard+=/holy_armaments,if=next_armament=sacred_weapon&((!buff.sacred_weapon.up|(buff.sacred_weapon.remains<6&!buff.avenging_wrath.up&cooldown.avenging_wrath.remains<=30))&(!set_bonus.thewarwithin_season_3_4pc|buff.masterwork.stack=5))
spells.sacred_weapon:AddCallback(function(spell)
    if GetNextArmament() ~= "Sacred Weapon" then return false end
    -- if C_Spell.IsCurrentSpell(spell.id) then return false end

    local mw = player:FindBuff(auras.masterwork)
    local sw_buff = player:FindBuff(auras.sacred_weapon)
    if sw_buff:Active() and sw_buff:Remains() > 6 then
        return false
    end

    if WillCastAvengingWrathSoon() then
        return false
    end

    -- Masterwork logic
    -- We only want to press Sacred Weapon at 5 stacks of Masterwork,
    if not mw or not mw:Active() or mw:Count() < 5 then
        return false
    end

    return spell:Cast(player) and mint.NotificationManager:AddNotification(5927637, "Sacred Weapon", 3)
end)

------------------------------
--- Shield of the Righteous
------------------------------
local lastSoTR = false

-- # Without the S2 4pc, just spend Shield of the Righteous when Righteous Protector is available,
-- # Hammer of Light is not ready, and ICD is free.
-- * Righteous Protector has a 1 second ICD on providing CDR for cooldowns, so we want to make sure we take advantage of that.
-- actions.standard+=/shield_of_the_righteous,if=!set_bonus.thewarwithin_season_2_4pc&(!talent.righteous_protector.enabled|cooldown.righteous_protector_icd.remains=0)&!buff.hammer_of_light_ready.up
spells.shield_of_the_righteous:AddCallback("CDR", function(spell)
    if C_Spell.IsCurrentSpell(spell.id) then return false end

    -- Require 3 HP unless Divine Purpose is active
    if player:GetPower(9) < 3 and not player:FindBuff(auras.divine_purpose):Active() then
        return false
    end

    -- don't cast SoTR into nothing unless we need to
    if SoTRTargets() == 0 then
        if player:GetPower(9) < 5 then
            local redoubt = player:FindBuff(auras.redoubt)
            if redoubt:Active() and redoubt:Count() >= 3 and (redoubt:Remains() > mint.max_gcd * 2) then
                return false
            end
        end
    end

    -- If we cast another SotR within 1.0s, we won’t get an extra RP proc.
    -- Wait until at least 1 sec has elapsed since the last successful SotR.
    local now = GetTime()
    if lastSoTR and (now - lastSoTR) < 1 then
        return false
    end

    if spell:Cast(none) then
        lastSoTR = now
        return true
    end

    return false
end)

-- # Spend Holy Power at 5 if Blessing of Dawn isn’t up, or you don’t have Lights Guidance.
-- * Dawn is generated by 3 generators, SoTR or WoG spends it (does 30% more dmg/heal), and provides Dusk, which is 4% Damage reduction
-- actions.standard+=/shield_of_the_righteous,if=holy_power=5&(!buff.blessing_of_dawn.up|!talent.lights_guidance.enabled)
spells.shield_of_the_righteous:AddCallback("Dump", function(spell)
    if C_Spell.IsCurrentSpell(spell.id) then return false end
    if player:GetPower(9) < 5 then return false end

    return spell:Cast(none)
end)


------------------------------
--- Word of Glory
------------------------------
spells.word_of_glory:AddCallback("Shining Light: Low HP", function(spell)
	if not player:FindOwnBuffByID(auras.shining_light.id):Active() then
		return false
	end

    if player:GetHP() > profile.sl_wog_threshold then
        return false
    end

	return spell:Cast(player) and mint.NotificationManager:AddNotification(133192, "Word of Glory (SL + Low HP)", 3)
end)

spells.word_of_glory:AddCallback("Prevent Death", function(spell)
    if player:GetHP() > profile.wog_threshold then
        return false
    end

	return spell:Cast(player) and mint.NotificationManager:AddNotification(133192, "Word of Glory (Prevent Death)", 3)
end)

spells.word_of_glory:AddCallback("Shining Light", function(spell)
    if not player:FindOwnBuffByID(auras.shining_light.id):Active() then
		return false
	end

	return spell:Cast(player) and mint.NotificationManager:AddNotification(133192, "Word of Glory (Proc)", 3)
end)

------------------------------
--- Of Dusk and Dawn
------------------------------
spells.of_dusk_and_dawn:AddCallback(function(spell)

end)

addon.paladin.data["Protection"].spells = spells
addon.paladin.data["Protection"].items = items
addon.paladin.data["Protection"].auras = auras
addon.paladin.data["Protection"].talents = talents
addon.paladin.data["Protection"].targets = targets
addon.paladin.data["Protection"].cache = Cache
