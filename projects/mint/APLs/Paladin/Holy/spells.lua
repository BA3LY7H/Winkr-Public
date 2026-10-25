local unlocker,
---@class mint
mint,
addon = ...

------------------------------
--- Locals
------------------------------
local RaidEvents 		= mint.RaidEvents
local UnitManager 		= mint.UnitManager
local FriendManager 	= mint.FriendManager
local ObjectManager 	= mint.ObjectManager
local Events  			= mint.EventManager
local Constants  		= mint.Constants
local Totems 			= mint.TotemManager
local SmartTarget 		= mint.SmartTarget
local Settings          = mint.Settings
local profile           = Settings.profile.paladin.holy
local Queue 			= mint.Queue
local Dispel 			= mint.Dispel
local Spell 			= mint.Spell.New
local bin 				= mint.bin
local StopTimer 		= mint.data.StopTimer
local Item 				= mint.Item.New
local MoveTimer 		= mint.data.MoveTimer
local max_gcd 			= mint.max_gcd
local gcd 				= mint.gcd
local toggles           = mint.data.toggles
local target  			= UnitManager:Get("target")
local player  			= UnitManager:Get("player")
local focus  			= UnitManager:Get("focus")
local none   			= UnitManager:Get("none")
local focus   			= UnitManager:Get("focus")
local vars              = addon.paladin.data["Holy"].vars

local function IsLightsmith()
	if UnitLevel("player") <= 70 then return false end
	return C_ClassTalents.GetActiveHeroTalentSpec() == 49
end

local function IsHerald()
	if UnitLevel("player") <= 70 then return false end
	return C_ClassTalents.GetActiveHeroTalentSpec() == 50
end

local function GetNextArmament()
	local info = C_Spell.GetSpellInfo(432459)

	if info.iconID == 5927637 then
		return "Sacred Weapon"
	else
		return "Holy Bulwark"
	end
end

local spells = {
	aura_mastery = Spell(31821, { beneficial = true }),
	avenging_wrath = Spell(31884, { beneficial = true }),
	beacon_of_faith = Spell(156910, { beneficial = true }),
	beacon_of_light = Spell(53563, { beneficial = true }),
	beacon_of_virtue = Spell(200025, { beneficial = true }),
	blessing_of_freedom = Spell(1044),
	blinding_light = Spell(115750, { targeted = false }),
	blessing_of_summer = Spell(388007, { beneficial = true }),
	blessing_of_autumn = Spell(388010, { beneficial = true }),
	blessing_of_winter = Spell(388011, { beneficial = true }),
	blessing_of_spring = Spell(388013, { beneficial = true }),
	blessing_of_protection = Spell(1022, { beneficial = true }),
	blessing_of_sacrifice = Spell(6940, { beneficial = true, ignore_casting = true }),
	cleanse = Spell(4987, { effect = "magic", dispel = true, beneficial = true, ignore_casting = true }),
	consecration = Spell(26573),
	crusader_aura = Spell(32223),
	crusader_strike = Spell(35395, { damage = "physical", targeted = false }),
	divine_protection = Spell(498),
	divine_shield = Spell(642),
	divine_steed = Spell(190784),
	divine_toll = Spell(375576, { beneficial = true }),
	eternal_flame = Spell(156322, { beneficial = true }),
	flash_of_light = Spell(19750, { ignore_usable = true, prevent_double = true }),
	hammer_of_justice = Spell(853),
	hammer_of_wrath = Spell(24275, { damage = "magic" }),
	holy_light = Spell(82326, { beneficial = true }),
	holy_prism = Spell(114165, { beneficial = true, damage = "magic" }),
	holy_shock = Spell(20473, { beneficial = true, damage = "magic" }),
	intercession = Spell(391054),
	judgment = Spell(275773, { damage = "magic", targeted = false }),
	lay_on_hands = Spell(633, { beneficial = true, ignore_casting = true, ignore_usable = true }),
	light_of_dawn = Spell(85222, { beneficial = true }),
	rebuke = Spell(96231),
	rite_of_adjuration = Spell(433583),
	rite_of_sanctification = Spell(433568),
	shield_of_the_righteous = Spell(415091, { damage = "magic", targeted = false }),
	tyrs_deliverance = Spell(200652, { beneficial = true }),
	word_of_glory = Spell(85673, { beneficial = true }),
	sacred_weapon = Spell(432472, { targeted = true, beneficial = true }),
	holy_bulwark = Spell(432459, { targeted = true, beneficial = true }),
	blessing_of_the_forge = Spell(433011),
}

local auras = {
	avenging_wrath = Spell(31884),
	dawnlight = Spell(431381),
	divine_favor = Spell(210294),
	infusion_of_light = Spell(54149),
	consecration = Spell(188370),
	shining_righteousness = Spell(414445),
	beacon_of_virtue = Spell(200025),
	beacon_of_faith = Spell(156910),
	beacon_of_light = Spell(53563),
	sacred_weapon = Spell(432502),
	holy_bulwark = Spell(432496),
	dawnlight_charges = Spell(431522),
	awakening = Spell(414196),
	awakening_ready = Spell(414193),
	blessing_of_summer = Spell(388007),
	unending_light = Spell(394709),
	nexus_king_aura = Spell(1239997),
	masterwork = Spell(1238903),
	divine_guidance = Spell(460822),
	blessing_of_anshe = Spell(445204),
	blessed_assurance = Spell(433019)
}

local talents = {
	veneration = Spell(392938, { targeted = false }),
	divine_guidance = Spell(433106),
	blessed_assurance = Spell(433015)
}

local nexus_kings_command = Item(242400)

------------------------------
--- Targets
------------------------------
local targets = {}

targets.lightspawn = UnitManager:CreateSmartUnit("hpal_lightspawn", function()
	local lightspawn = nil

	ObjectManager.units:loop(function(unit)
		-- print("Summon:", unit.name and unit.name or "Unknown")
		-- if unit:IsDead() then return false end
		-- if not unit:GetExists() then return false end
        if unit.id == 224241 then
            lightspawn = unit

            return true
        end
        
        return false
	end)

	if lightspawn == nil then
		mint.console.log("No lightspawn found")
		return none
	end

	return lightspawn
end)

local types = {
	["Poison"] = true,
	["Disease"] = true,
	["Magic"] = true,
}

-- Dispel Handling
targets.dispel = UnitManager:CreateSmartUnit("hpal_dispel", function()
	local dispel_tar = nil

	if not toggles.dispels then
		return none
	end

    FriendManager:Loop(function(friend)
        if friend:IsDead() then return false end
		if not spells.cleanse:IsInRange(friend) then return false end
		if not friend:HasDebuffType(types) then return false end
		-- if not player:HasLos(friend) then return false end

        dispel_tar = friend

        return true
    end)


	if dispel_tar == nil then
		return none
	end

	return dispel_tar
end)

-- Beacon of Virtue target in raid
-- Score = (2 * % missing HP) + (1 * distance in yards)
-- Picks the highest-scoring friendly unit. If no one is injured, returns none.
targets.bov_raid = UnitManager:CreateSmartUnit("hpal_bov_raid", function()
    local bovTar    = nil
    local bestScore = -1

    FriendManager:Loop(function(friend)
        friend:Update()
        if friend:IsDead() then return false end

		local hp = friend:GetRealizedHP()
		if hp > (100 - profile.beacon_buffer) then
			return true
		end

        local missing = math.max(0, 100 - hp)
        local dist = player:GetDistance(friend)

        local score = (2 * missing) + dist
        if score > bestScore then
            bestScore = score
            bovTar    = friend
        end

        return false
    end)

    return bovTar or none
end)


-- Nexus-King's Command Trinket
targets.oath_sworn = UnitManager:CreateSmartUnit("oath_sworn", function()
	if not nexus_kings_command:IsEquipped() then
		return none
	end

	local heal_tar = nil

	FriendManager:Loop(function(friend)
		if friend:IsDead() then return false end
		if friend:FindBuff(auras.nexus_king_aura, true):Inactive() then return false end
		-- if not player:HasLos(friend) then return false end

		heal_tar = friend

		return true
	end)


	if heal_tar == nil then
		return none
	end

	return heal_tar
end)

-- Battle Resurrection
targets.battle_res = UnitManager:CreateSmartUnit("hpal_brez", function()
	local bres_tar = nil

    FriendManager:Loop(function(friend)
        if not friend.dead then return true end
		if not spells.intercession:IsInRange(friend) then return false end

        bres_tar = friend
        return true
    end)


	if bres_tar == nil then
		return none
	end

	return bres_tar
end)

-- Melee Enemy (For "auto target" when player target is bad)
targets.melee = UnitManager:CreateSmartUnit("hpal_melee", function()
    if target:GetExists() and target:IsEnemy() and not target:IsDead() and player:InMelee(target)
    and player:IsFacing(target, 120) then
        return target
    end

	local melee_tar = nil
    local highest_hp = 0

    ObjectManager.combat:each(function(enemy)
        enemy:Update()
        if enemy:IsDead() then return false end
        if not player:InMelee(enemy) then return false end
        if not player:IsFacing(enemy) then return false end

        if enemy:GetHP() > highest_hp then
            highest_hp = enemy:GetHP()
            melee_tar = enemy
        end

        return false
    end)


	if melee_tar == nil then
		return none
	end

	return melee_tar
end)

-- Rebuke
targets.kick = UnitManager:CreateSmartUnit("hpal_rebuke", function()
	local closest = nil
	local closest_dist = math.huge

	if not toggles.kicks then
		return none
	end

	ObjectManager.combat:loop(function(enemy)
		if enemy.dead then return false end
		if not enemy:IsCastingOrChanneling() then return false end
		if not enemy:IsKickable() then return false end
		if not spells.rebuke:IsInRange(enemy) then return false end
        if not player:IsFacing(enemy, 120) then return false end
		local str_key = tostring(enemy:GetCastSpellID())
		if not Settings.profile.kicks[str_key] then return false end
		if not Settings.profile.kicks[str_key].enabled then return false end

		local dist = player:GetDistanceSquared(enemy)
		if dist < closest_dist then
			closest_dist = dist
			closest = enemy
		end

		return false
	end)

	if closest == nil then
		return none
	end

	return closest
end)

targets.stun = UnitManager:CreateSmartUnit("hpal_stun", function()
	local closest = nil
	local closest_dist = math.huge

	if not toggles.kicks then
		return none
	end

	if not profile.auto_hoj then
		return none
	end

	ObjectManager.combat:loop(function(enemy)
		if enemy.dead then return false end
		if not enemy:IsCastingOrChanneling() then return false end
		if not enemy:CanStun() then return false end
		-- We want to use kick before stun
		if spells.rebuke:IsInRange(enemy) and not spells.rebuke:IsOnCD() then return false end
		if not spells.hammer_of_justice:IsInRange(enemy) then return false end
        if not player:IsFacing(enemy, 120) then return false end
		local str_key = tostring(enemy:GetCastSpellID())
		if not Settings.profile.kicks[str_key] then return false end
		if not Settings.profile.kicks[str_key].enabled then return false end

		local dist = player:GetDistanceSquared(enemy)
		if dist < closest_dist then
			closest_dist = dist
			closest = enemy
		end

		return false
	end)

	if closest == nil then
		return none
	end

	return closest
end)

-- Season Targets

------------------------------
--- Helpers
------------------------------

------------------------------
--- Divine Protection
------------------------------
spells.divine_protection:AddCallback(function(spell)
	if not toggles.defensives then return false end

	if player:GetRealizedHP() < 60 then
		return spell:Cast(player)
	end
end)

------------------------------
--- Aura Mastery
------------------------------
spells.aura_mastery:AddCallback(function(spell)

end)

------------------------------
--- Avenging Wrath
------------------------------
spells.avenging_wrath:AddCallback(function(spell)
    if not toggles.cooldowns then return false end

end)

------------------------------
--- Beacon of Faith
------------------------------
spells.beacon_of_faith:AddCallback(function(spell)

end)

------------------------------
--- Beacon of Light
------------------------------
spells.beacon_of_light:AddCallback(function(spell)

end)

------------------------------
--- Beacon of Virtue
------------------------------
spells.beacon_of_virtue:AddCallback("Keys", function(spell)
    if not toggles.cooldowns then return false end

	if FriendManager:GetCountBelow(100 - profile.healing_buffer) < 2 then return false end

	return spell:Cast(player)

end)

spells.beacon_of_virtue:AddCallback("Raid", function(spell)
    if not toggles.cooldowns then return false end
	if not targets.bov_raid:GetExists() then return false end
	if FriendManager:GetCountBelow(100 - profile.beacon_buffer) < 5 then return false end

    return spell:Cast(targets.bov_raid)
end)

spells.beacon_of_virtue:AddCallback("Raid: Wings", function(spell)
    if not toggles.cooldowns then return false end
	if not targets.bov_raid:GetExists() then return false end
	if not player:FindBuff(auras.avenging_wrath):Active() then
		return false
	end
	if player:FindBuff(auras.avenging_wrath):Remains() < 8 then
		return false
	end
	if FriendManager:GetCountBelow(100 - profile.beacon_buffer) < 2 then return false end

    return spell:Cast(targets.bov_raid) and mint.NotificationManager:AddNotification(1030094, "Beacon: Wings", 3)
end)

------------------------------
--- Blessing of Summer
------------------------------
spells.blessing_of_summer:AddCallback("Self", function(spell)
    return spell:Cast(player)
end)

------------------------------
--- Blessing of Autumn
------------------------------
spells.blessing_of_autumn:AddCallback("Self", function(spell)
    return spell:Cast(player)
end)

------------------------------
--- Blessing of Winter
------------------------------
spells.blessing_of_winter:AddCallback("Self", function(spell)
    return spell:Cast(player)
end)

------------------------------
--- Blessing of Spring
------------------------------
spells.blessing_of_spring:AddCallback("Self", function(spell)
    return spell:Cast(player)
end)

------------------------------
--- Cleanse
------------------------------
spells.cleanse:AddCallback("Utility: Smart Dispel", function(spell)
    if not toggles.dispels then return false end
    if not targets.dispel:GetExists() or targets.dispel:IsDead() then
        return false
    end

	-- mint.console.log("Attempted to dispel target:", targets.dispel.name)

    return spell:Cast(targets.dispel) and mint.NotificationManager:AddNotification(135949, "Dispelling " .. targets.dispel.name, 3)
end)

------------------------------
--- Consecration
------------------------------
spells.consecration:AddCallback("Keys", function(spell)
    if not target:GetExists() then
        return false
    end

    if StopTimer:GetTime() < 0.5 then
        return false
    end

    if player:GetMeleeCount() < 1 then
        return false
    end

    -- If a unit below 80% hp exists do not place
    if FriendManager:GetLowest(80) then
        return false
    end

    if player:FindBuff(auras.consecration):Active() then
        return false
    end

    return spell:Cast(player)
end)

spells.consecration:AddCallback("Raid: Lightsmith", function(spell)
	if not IsPlayerSpell(95235) then return false end

	if not target:GetExists() then
		return false
	end

	if StopTimer:GetTime() < 0.5 then
		return false
	end

	if player:GetMeleeCount() < 1 then
		return false
	end

	-- If a unit below 80% hp exists do not place
	if FriendManager:GetLowest(80) then
		return false
	end

	if player:FindBuff(auras.consecration):Active() then
		return false
	end

	if player:FindBuff(auras.divine_guidance):Count() < 5 then
		return false
	end

	return spell:Cast(player)
end)

------------------------------
--- Crusader Strike
------------------------------
spells.crusader_strike:AddCallback(function(spell)
    if not targets.melee:GetExists() then
        return false
    end

	if player:GetPower(9) > 4 then
		return false
	end

    return spell:Cast(targets.melee)
end)

spells.crusader_strike:AddCallback("Keys", function(spell)
    if not targets.melee:GetExists() then
        return false
    end

	if player:GetPower(9) > 4 then
		return false
	end

    return spell:Cast(targets.melee)
end)

spells.crusader_strike:AddCallback("Raid", function(spell)
    if not targets.melee:GetExists() then
        return false
    end

	if player:GetPower(9) > 4 then
		return false
	end

    return spell:Cast(targets.melee)
end)

spells.crusader_strike:AddCallback("Raid: Lightsmith", function(spell)
	if talents.blessed_assurance.known and player:FindBuff(auras.blessed_assurance):Inactive() and
			player:GetPower(9) > 3 then
		return false
	end

	if not targets.melee:GetExists() then
		return false
	end

	if player:GetPower(9) > 4 then
		return false
	end

	return spell:Cast(targets.melee)
end)

------------------------------
--- Divine Toll
------------------------------
spells.divine_toll:AddCallback(function(spell)
	-- Avoid casting if it will over cap Holy Power
	if player:GetPower(9) > 2 then return false end

    if FriendManager:GetCountBelow(99) >= 2 then
		-- In Raid, we want to cast on a target missing hp, not always ourselves.
		if IsInRaid() then
			local lowest = FriendManager:GetLowest(100 - profile.healing_buffer) or none

			if lowest:GetExists() then
				return spell:Cast(lowest)
			end
		else
			return spell:Cast(player)
		end
    end

    return false
end)

spells.divine_toll:AddCallback("Keys", function(spell)
	-- Avoid casting if it will over cap Holy Power
	if player:GetPower(9) > 2 then return false end

    if FriendManager:GetCountBelow(100 - profile.healing_buffer) >= 2 then
		return spell:Cast(player)
    end

    return false
end)

spells.divine_toll:AddCallback("Raid", function(spell)
	-- Avoid casting if it will over cap Holy Power
	if player:GetPower(9) > 2 then return false end

    if FriendManager:GetCountBelow(100 - profile.healing_buffer) >= 2 then
		local lowest = FriendManager:GetLowest(100 - profile.healing_buffer) or none

		if lowest:GetExists() then
			return spell:Cast(lowest)
		end
    end

    return false
end)

------------------------------
--- Eternal Flame
------------------------------
spells.eternal_flame:AddCallback("Imminent Death", function(spell)
    local lowest = FriendManager:GetLowest(50) or none
    if lowest:GetExists() then
        return spell:Cast(lowest)
    end

    return false
end)

spells.eternal_flame:AddCallback("Raid: Emergency", function(spell)
    local lowest = FriendManager:GetLowest(30) or none
    if lowest:GetExists() then
        return spell:Cast(lowest)
    end

    return false
end)

spells.eternal_flame:AddCallback("Raid", function(spell)
    local lowest = FriendManager:GetLowest(100 - profile.healing_buffer) or none
    local any = FriendManager:GetLowest(false)

    -- If we're not capped, don't cast
    if player:GetPower(9) < 4 then return false end

    -- If anyone is below 90% hp, cast on them
    if lowest:GetExists() then
        return spell:Cast(lowest)
    end

	if targets.oath_sworn:GetExists() then
		return spell:Cast(targets.oath_sworn)
	end

    if focus:GetExists() then
        return spell:Cast(focus)
    end

    -- If we are capped and do not have a target for shield of the righteous, cast on any target
    if not targets.melee:GetExists() then
        return spell:Cast(any)
    end

    return false
end)


spells.eternal_flame:AddCallback("Raid: Spread Dawnlight", function(spell)
	-- We do not want to cast this if we can't spread dawnlight
	if not player:FindBuff(auras.dawnlight_charges):Active() then
		return false
	end

	-- Get the lowest friend without dawnlight, otherwise any friend without it.
	local no_dawnlight = FriendManager:GetLowest(false, function(friend)
		if friend:FindBuff(auras.dawnlight):Active() then
			return false
		end

		return true
	end) or none

    if no_dawnlight:GetExists() then
		local name = no_dawnlight.name or "Unknown"
        return spell:Cast(no_dawnlight) and mint.NotificationManager:AddNotification(135433, "Spread Dawnlight", 3)
    end

    return false
end)


spells.eternal_flame:AddCallback("Keys: Spread Dawnlight", function(spell)
	-- We do not want to cast this if we can't spread dawnlight
	if not player:FindBuff(auras.dawnlight_charges):Active() then
		return false
	end

	-- Get the lowest friend without dawnlight, otherwise any friend without it.
	local no_dawnlight = FriendManager:GetLowest(100 - profile.healing_buffer, function(friend)
		if friend:FindBuff(auras.dawnlight):Active() then
			return false
		end

		return true
	end) or none

    if no_dawnlight:GetExists() then
        return spell:Cast(no_dawnlight)
    end

    return false
end)

-- Blessing of summer does more damage with EF than SoTR (it includes overhealing)
spells.eternal_flame:AddCallback("Keys: Blessing of Summer", function(spell)
	if not profile.summer_heal_spam then return false end
	if not player:FindBuff(auras.blessing_of_summer):Active() then
		return false
	end

    local lowest = FriendManager:GetLowest(90) or none

    -- If anyone is below 90% hp, cast on them
    if lowest:GetExists() then
        return spell:Cast(lowest)
	else
		-- EF heals ourselves extra, so we are the best target if all topped
		return spell:Cast(player)
	end

    return false
end)

spells.eternal_flame:AddCallback("Keys", function(spell)
    local lowest = FriendManager:GetLowest(90) or none
    local any = FriendManager:GetLowest()

    -- If we're not capped, don't cast
    if player:GetPower(9) < 4 then return false end

    -- If anyone is below 90% hp, cast on them
    if lowest:GetExists() then
        return spell:Cast(lowest)
    end

    if focus:GetExists() then
        return spell:Cast(focus)
    end

    -- If we are capped and do not have a target for shield of the righteous, cast on any target
    if not targets.melee:GetExists() then
        return spell:Cast(any)
    end

    return false
end)

------------------------------
--- Flash of Light
------------------------------
spells.flash_of_light:AddCallback("Keys: Infusion (Virtue)", function(spell)
    if not player:FindBuff(auras.infusion_of_light):Active() then return false end
    if not player:FindBuff(auras.beacon_of_virtue):Active() then return false end

    local lowest = FriendManager:GetLowest(100 - profile.healing_buffer) or none
    if not lowest:GetExists() then return false end

    return spell:Cast(lowest)
end)

spells.flash_of_light:AddCallback("Keys: Infusion", function(spell)
    if not player:FindBuff(auras.infusion_of_light):Active() then return false end

    local lowest = FriendManager:GetLowest(100 - profile.healing_buffer) or none
    if not lowest:GetExists() then return false end

    return spell:Cast(lowest)
end)

spells.flash_of_light:AddCallback("Raid: Infusion", function(spell)
    if not player:FindBuff(auras.infusion_of_light):Active() then return false end

    local lowest = FriendManager:GetLowest(100 - profile.healing_buffer) or none
    if not lowest:GetExists() then return false end

    return spell:Cast(lowest)
end)

spells.flash_of_light:AddCallback("Raid: Hard Cast", function(spell)
	if player:IsMoving() then return false end

	local lowest = FriendManager:GetLowest(100 - profile.healing_buffer) or none
	if not lowest:GetExists() then return false end

	return spell:Cast(lowest)
end)

------------------------------
--- Hammer of Justice
------------------------------
spells.hammer_of_justice:AddCallback(function(spell)

end)

spells.hammer_of_justice:AddCallback("Utility: HoJ Interrupt", function(spell)
	if not toggles.kicks then return false end
	if not targets.stun:GetExists() then return false end

	if targets.stun:IsCasting() then
		if targets.stun:GetCastPercent() >= 30 then
			if spell:Cast(targets.stun) then
				return true
			end
		end
	end

	if targets.kick:IsChanneling() then
		if targets.kick:GetTimeSinceStartedCast() >= 0.45 then
			if spell:Cast(targets.stun) then
				return true
			end
		end
	end

	return false
end)

------------------------------
--- Hammer of Wrath
------------------------------
spells.hammer_of_wrath:AddCallback("Veneration", function(spell)
	if not IsPlayerSpell(talents.veneration.id) then return false end

    if not target:GetExists() or target:IsFriend() then
        return false
    end

    return spell:Cast(target)
end)

spells.hammer_of_wrath:AddCallback("Raid", function(spell)
    if not target:GetExists() or target:IsFriend() then
        return false
    end

    return spell:Cast(target)
end)

spells.hammer_of_wrath:AddCallback("Keys", function(spell)
    if not target:GetExists() or target:IsFriend() then
        return false
    end

    return spell:Cast(target)
end)

------------------------------
--- Holy Light
------------------------------
spells.holy_light:AddCallback(function(spell)

end)

------------------------------
--- Holy Bulwark
------------------------------
spells.holy_bulwark:AddCallback("Raid", function(spell)
	if GetNextArmament() == "Sacred Weapon" then
		return false
	end

	local mw = player:FindBuff(auras.masterwork)

	if mw:Inactive() then
		return false
	end

	if mw:Count() < 5 then
		return false
	end

	return spell:Cast(player) and mint.NotificationManager:AddNotification(5927636, "Holy Bulwark", 3)
end)

------------------------------
--- Sacred Weapon
------------------------------
spells.sacred_weapon:AddCallback("Raid", function(spell)
	if GetNextArmament() ~= "Sacred Weapon" then return false end
	-- if C_Spell.IsCurrentSpell(spell.id) then return false end

	local mw = player:FindBuff(auras.masterwork)

	if mw:Inactive() then
		return false
	end

	if mw:Count() < 5 then
		return false
	end

	return spell:Cast(player) and mint.NotificationManager:AddNotification(5927637, "Sacred Weapon", 3)
end)

------------------------------
--- Holy Prism
------------------------------
spells.holy_prism:AddCallback("Keys: Generate Dawnlight", function(spell)
	if not player:FindBuff(auras.avenging_wrath):Active() then
		return false
	end

	if not target:GetExists() or target:IsFriend() then
		return false
	end

	return spell:Cast(target)
end)

-- Cast on an enemy for AoE healing
spells.holy_prism:AddCallback("Keys", function(spell)
	-- If user is manually using wings, just use on CD
	-- If we don't haave wings up and the CD will be up before next prism
	-- is available, hold for wings
	if toggles.cooldowns
	and not player:FindBuff(auras.avenging_wrath):Active()
	and spells.avenging_wrath:GetRemainingCD() < 25 then
		return false
	end

    if FriendManager:GetCountBelow(100 - profile.healing_buffer) >= 2 and target:GetExists() and target:IsEnemy() then
        return spell:Cast(target)
    end

    return false
end)

spells.holy_prism:AddCallback("Raid", function(spell)
	if toggles.cooldowns
	and not player:FindBuff(auras.avenging_wrath):Active()
	and spells.avenging_wrath:GetRemainingCD() < 25 then
		return false
	end

	if not target:GetExists() or target:IsFriend() then
		return false
	end

	if FriendManager:GetCountBelow(100 - profile.healing_buffer) < 4 then
		return false
	end

    return spell:Cast(target) and mint.NotificationManager:AddNotification(613408, "Healing (No Wings/BoV)", 3)
end)

spells.holy_prism:AddCallback("Raid: Dawnlights", function(spell)
	if toggles.cooldowns
	and not player:FindBuff(auras.avenging_wrath):Active()
	and spells.avenging_wrath:GetRemainingCD() < 25 then
		return false
	end

	if not player:FindBuff(auras.avenging_wrath):Active() 
	and FriendManager:GetNumFriendsWithBuff(auras.beacon_of_virtue) < 1 then
		return false
	end

	if not target:GetExists() or target:IsFriend() then
		return false
	end

	return spell:Cast(target) and mint.NotificationManager:AddNotification(613408, "Generating Dawnlight (Wings/BoV)", 3)
end)

spells.holy_prism:AddCallback("Raid: Lightsmith", function(spell)
	if not target:GetExists() or target:IsFriend() then
		return false
	end

	if FriendManager:GetCountBelow(100 - profile.healing_buffer) < 4 then
		return false
	end

	return spell:Cast(target) and mint.NotificationManager:AddNotification(613408, "Healing (No Wings/BoV)", 3)
end)


------------------------------
--- Holy Shock
------------------------------
spells.holy_shock:AddCallback(function(spell)

end)

spells.holy_shock:AddCallback("Raid", function(spell)
	if player:GetPower(9) > 4 then
		return false
	end

    local lowest = FriendManager:GetLowest(100 - profile.healing_buffer) or none

	if targets.oath_sworn:GetExists() then
		return spell:Cast(targets.oath_sworn)
	end

    if lowest:GetExists() then
        return spell:Cast(lowest)
	end
	
    return false
end)

spells.holy_shock:AddCallback("Raid: Damage", function(spell)
	if not profile.holy_shock_dps then return false end
	if profile.hold_hs_charge and spell:GetCharges() < 2 then return false end

	if player:GetPower(9) > 4 then
		return false
	end

	if target:GetExists() then
		return spell:Cast(target)
	end

	return false
end)

spells.holy_shock:AddCallback("Keys: Healing", function(spell)
    local threshold = focus:GetExists() and 75 or 90
    local lowest = FriendManager:GetLowest(threshold) or none

	if player:GetPower(9) > 4 then
		return false
	end

    if lowest:GetExists() then
        return spell:Cast(lowest)
    end

    if focus:GetExists() then
        return spell:Cast(focus)
    end
	
    return false
end)

spells.holy_shock:AddCallback("Keys: Damage", function(spell)
	if player:GetPower(9) > 4 then
		return false
	end

	if profile.summer_heal_spam and player:FindBuff(auras.blessing_of_summer):Active() then
		local no_beacon = FriendManager:GetLowest(100 - profile.healing_buffer, function(friend)
			if friend:FindBuff(auras.beacon_of_faith):Active() 
			or friend:FindBuff(auras.beacon_of_light):Active() then
				return false
			end

			return true
		end) or none

		if no_beacon:GetExists() then
			return spell:Cast(no_beacon)
		end

		return false
	else
		if target:GetExists() and target:IsEnemy() then
			return spell:Cast(target)
		end

		return false
	end
end)

------------------------------
--- Intercession
------------------------------
spells.intercession:AddCallback(function(spell)

end)

spells.intercession:AddCallback("M+ Brez", function(spell)
    if C_ChallengeMode.IsChallengeModeActive() then
        if targets.battle_res:GetExists() and targets.battle_res:IsDead() then
            return spell:Cast(targets.battle_res)
        end
    end

    return false
end)

------------------------------
--- Judgment
------------------------------
spells.judgment:AddCallback(function(spell)
    -- if IsInRaid() then return false end
	-- Hold Awakening proc until we have prism available
	-- Unless we still have the dawnlight charges available
	if player:FindBuff(auras.awakening):Count() == 15
	and spells.holy_prism:IsOnCD() 
	and not player:FindBuff(auras.dawnlight_charges):Active() then
		return false
	end

	-- Don't send awakening proc without 2 power
	if player:GetPower(9) < 2 and player:FindBuff(auras.awakening):Count() == 15 then
		return false
	end

    if not target:GetExists() or target:IsFriend() then
        return false
    end

    return spell:Cast(target)
end)

spells.judgment:AddCallback("Keys", function(spell)
	-- Hold Awakening proc until we have prism available
	-- Unless we still have the dawnlight charges available
	if player:FindBuff(auras.awakening):Count() == 15
	and spells.holy_prism:IsOnCD() 
	and not player:FindBuff(auras.dawnlight_charges):Active() then
		return false
	end

	-- Don't send awakening proc without 2 power
	if player:GetPower(9) < 2 and player:FindBuff(auras.awakening):Count() == 15 then
		return false
	end

    if not target:GetExists() or target:IsFriend() then
        return false
    end

    return spell:Cast(target)
end)

spells.judgment:AddCallback("Raid: Infusion", function(spell)
    if not player:FindBuff(auras.infusion_of_light):Active() then return false end
	if FriendManager:GetNumFriendsWithBuff(auras.beacon_of_virtue) > 0 then return false end
    if not target:GetExists() or target:IsFriend() then return false end
	if player:GetPP() < profile.judge_mana then return false end

    return spell:Cast(target)
end)

-- If we are in wings already, we send for extension
-- If we are not in wings and we don't have prism ready, we want to hold this.
spells.judgment:AddCallback("Raid", function(spell)
	if player:FindBuff(auras.awakening_ready):Active()
	and spells.holy_prism:IsOnCD() and spells.holy_prism:GetRemainingCD() < player:FindBuff(auras.awakening_ready):Remains()
	and not player:FindBuff(auras.dawnlight_charges):Active()
	and not player:FindBuff(auras.avenging_wrath):Active() then
		return false
	end

	if player:GetPP() < profile.judge_mana 
	and player:FindBuff(auras.awakening_ready):Inactive() then
		return false
	end

	-- Don't send awakening proc without 2 power
	if player:GetPower(9) < 2 and player:FindBuff(auras.awakening_ready):Active() then
		return false
	end

	-- Don't spend infusions on judgment when we have beacon active, should be FoL
	if player:FindBuff(auras.infusion_of_light):Active() and
			FriendManager:GetNumFriendsWithBuff(auras.beacon_of_virtue) > 0 then return false end
    if not target:GetExists() or target:IsFriend() then return false end

    return spell:Cast(target)
end)

------------------------------
--- Lay on Hands
------------------------------
spells.lay_on_hands:AddCallback("Imminent Death", function(spell)
    if not profile.loh_toggle then return false end
    local threshold = profile.loh_pct
    local lowest = FriendManager:GetLowest(threshold, function(friend)
		if friend.role == "TANK" and friend.class == "Paladin" then
			return false
		end

		return true
	end) or none

    if lowest:GetExists() then
        if addon.paladin.settings["Holy"].LoHDelay then
            -- If we checked more than 0.5 seconds ago, cast spell
            if lowest.loh_check then
                local diff = GetTime() - lowest.loh_check > 0.5
                if diff < 3 and diff > 0.5 then
                    lowest.loh_check = nil
                    return spell:Cast(lowest)
                elseif diff > 3 then
                    -- We don't want a stale loh check to be used
                    lowest.loh_check = GetTime()
                else
                    return false
                end
            end
            return false
        else
            return spell:Cast(lowest)
        end
    end

    return false
end)

------------------------------
--- Blessing of Sacrifice
------------------------------
spells.blessing_of_sacrifice:AddCallback(function(spell)

end)

spells.blessing_of_sacrifice:AddCallback("Emergency", function(spell)
	if not profile.bos_toggle then return false end
	local threshold = profile.bos_pct
	local lowest = FriendManager:GetLowest(threshold, function(friend)
		if friend:IsUnit(player) then
			return false
		end

		if friend.role == "TANK" and spells.divine_shield.on_cd then
			return false
		end

		return true
	end) or none

	if lowest:GetExists() then
		return spell:Cast(lowest)
	end

	return false
end)

------------------------------
--- Light of Dawn
------------------------------
local TWO_PI = 2 * math.pi

local function is_number(x)
    return type(x) == "number" and x == x -- filters NaN too
end

local function normalize_angle(a)
    -- normalize to [0, 2π)
    a = a % TWO_PI
    if a < 0 then a = a + TWO_PI end
    return a
end

local function ensure_radians(width)
    -- If width looks like degrees (e.g., 90), convert to radians.
    -- Heuristic: anything > 2π is probably degrees.
    if width > TWO_PI then
        return math.rad(width)
    end
    return width
end

local function GetBestCone(angle_width, range, min_hits)
    local pos = player:GetPosition()
    if not pos or not pos.IsValid or not pos:IsValid() then return false end

    angle_width = ensure_radians(angle_width)

    -- Collect clean, numeric angles within range
    local angles = {}
    FriendManager:Loop(function(friend)
        if not friend.dead and player:GetDistanceSquared(friend) < (range * range) then
            local fpos = friend:GetPosition()
            if fpos and fpos.IsValid and fpos:IsValid() then
                local a = pos:Angle(fpos)      -- Expect radians
                if is_number(a) then
                    angles[#angles + 1] = normalize_angle(a)
                end
            end
        end
    end)

    if #angles == 0 then return false end

    -- Sort ascending; no custom comparator needed
    table.sort(angles)

    -- Handle circular wrap: duplicate each angle shifted by +2π
    local n = #angles
    for i = 1, n do
        angles[#angles + 1] = angles[i] + TWO_PI
    end

    local best_center = nil
    local best_count  = 0

    local j = 1
    for i = 1, n do
        local start_a = angles[i]
        -- advance j while still within window
        while j <= i + n - 1 and (angles[j] - start_a) <= angle_width do
            j = j + 1
        end
        local end_a = angles[j - 1]
        local count = (j - 1) - i + 1
        if count > best_count then
            best_count  = count
            best_center = normalize_angle(start_a + (end_a - start_a) / 2)
        end
    end

    if best_count < (min_hits or 0) then
        return false
    end

    return best_center
end

local function dawnDistance()
	local range = 15

	local node_info = C_Traits.GetNodeInfo(C_ClassTalents.GetActiveConfigID(), 81583)

	if node_info.activeRank == 1 then
		range = 25
	elseif node_info.activeRank == 2 then
		range = 40
	end

	return range
end

local function InjuredFacingCount(check_count)
	local distance = dawnDistance()
	local count = 0
	FriendManager:LoopRaw(function(unit)
		if player:GetDistance(unit) > distance then return false end
		if player:IsFacing(unit, 45) then
			count = count + 1
		end
		if count >= check_count then
			return true
		end
	end)
	return count
end

spells.light_of_dawn:AddCallback(function(spell)

end)

spells.light_of_dawn:AddCallback("Raid: Lightsmith", function(spell)
	if not profile.auto_lod then return false end
	if player:IsMoving() then return false end
	-- if player:FindBuff(auras.unending_light):Count() < 8 then return false end
	if FriendManager:GetCountBelow(100 - profile.healing_buffer) < 5 then return false end

	if InjuredFacingCount(5) >= 5 then
		return spell:Cast(player)
	end
end)

spells.light_of_dawn:AddCallback("Dump HP", function(spell)
	if not IsInRaid() then return false end
	if not profile.auto_lod then return false end
	if player:IsMoving() then return false end
	if player:FindBuff(auras.unending_light):Count() < 8 then return false end
	local bestAngle = GetBestCone(90, dawnDistance(), 4)
	if bestAngle then
		local original = player:GetFacing()
		local left_down = IsMouseButtonDown(1)
		local right_down = IsMouseButtonDown(2)
		if left_down then
			local focus = GetMouseFocus()
			if focus ~= WorldFrame then
				left_down = false
			end
		end
		if right_down then MouselookStop() end
		if left_down then CameraOrSelectMoveStop() end
		mint.FaceDirection(bestAngle, true)
		local res = spell:Cast(player)
		mint.FaceDirection(original, true)
		if right_down then MouselookStart() end
		if left_down then CameraOrSelectOrMoveStart() end
		return res
	end
end)

------------------------------
--- Rebuke
------------------------------
local cast_percent
local channel_time

local function NewPercent()
	local new = math.random(40, 80)

	if new == cast_percent then
		return NewPercent()
	end

	cast_percent = new
	return cast_percent
end

local function NewChannelTime()
	local new = math.random(70, 90)

	new = new / 100

	if new == channel_time then
		return NewChannelTime()
	end

	channel_time = new
	return channel_time
end

cast_percent = NewPercent()
channel_time = NewChannelTime()

spells.rebuke:AddCallback("Utility: Smart Kick", function(spell)
	if not toggles.kicks then return false end
	if not targets.kick:GetExists() then return false end

	if targets.kick:IsCasting() then
		if targets.kick:GetCastPercent() >= 30 then
			if spell:Cast(targets.kick) then
				cast_percent = NewChannelTime()
				return true
			end
		end
	end

	if targets.kick:IsChanneling() then
		if targets.kick:GetTimeSinceStartedCast() >= channel_time then
			if spell:Cast(targets.kick) then
				cast_percent = NewChannelTime()
				return true
			end
		end
	end

	return false
end)

------------------------------
--- Shield of the Righteous
------------------------------
spells.shield_of_the_righteous:AddCallback(function(spell)

end)

spells.shield_of_the_righteous:AddCallback("Raid", function(spell)
    if C_Spell.IsCurrentSpell(spell.id) then return false end

	-- If there is any injured target, we should be healing over DPS
	local lowest = FriendManager:GetLowest(100 - profile.healing_buffer) or none
	if lowest:GetExists() then
		return false
	end

    if player:GetPower(9) >= 4 then
        return spell:Cast(none)
    end

    return false
end)

spells.shield_of_the_righteous:AddCallback("Keys", function(spell)
    if C_Spell.IsCurrentSpell(spell.id) then return false end

    if player:GetPower(9) >= 4 then
        return spell:Cast(none)
    end

    return false
end)

------------------------------
--- Word of Glory
------------------------------
spells.word_of_glory:AddCallback(function(spell)

end)

spells.word_of_glory:AddCallback("Emergency", function(spell)
    local lowest = FriendManager:GetLowest(50) or none

    if lowest:GetExists() then
        return spell:Cast(lowest)
    end

    return false
end)

spells.word_of_glory:AddCallback("Dump HP", function(spell)
    local lowest = FriendManager:GetLowest(90) or none
    local any = FriendManager:GetLowest()

    -- If we're not capped, don't cast
    if player:GetPower(9) < 4 then return false end

    -- If anyone is below 90% hp, cast on them
    if lowest:GetExists() then
        return spell:Cast(lowest)
    end

    -- If we are capped and do not have a target for shield of the righteous, cast on any target
    if not targets.melee:GetExists() then
        return spell:Cast(any)
    end

    return false
end)

spells.word_of_glory:AddCallback("Raid", function(spell)
	local lowest = FriendManager:GetLowest(100 - profile.healing_buffer) or none

	-- If we're not capped, don't cast
	if player:GetPower(9) < 4 then return false end

	-- If anyone is below 90% hp, cast on them
	if lowest:GetExists() then
		return spell:Cast(lowest)
	end

	if focus:GetExists() then
		return spell:Cast(focus)
	end

	return false
end)

------------------------------
--- Sacred Weapon
------------------------------
spells.sacred_weapon:AddCallback(function(spell)

end)

addon.paladin.data["Holy"].spells 	= spells
-- addon.paladin.data["Holy"].items 	= items
addon.paladin.data["Holy"].auras 	= auras
addon.paladin.data["Holy"].targets 	= targets