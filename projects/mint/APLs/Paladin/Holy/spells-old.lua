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
local MoveTimer 		= mint.data.MoveTimer
local max_gcd 			= mint.max_gcd
local gcd 				= mint.gcd
local toggles           = mint.data.toggles
local target  			= UnitManager:Get("target")
local player  			= UnitManager:Get("player")
local none   			= UnitManager:Get("none")
local vars              = addon.paladin.data["Holy"].vars

local function IsLightsmith()
	if UnitLevel("player") <= 70 then return false end
	return C_ClassTalents.GetActiveHeroTalentSpec() == 49
end

local function IsHerald()
	if UnitLevel("player") <= 70 then return false end
	return C_ClassTalents.GetActiveHeroTalentSpec() == 50
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
	flash_of_light = Spell(19750),
	hammer_of_justice = Spell(853),
	hammer_of_wrath = Spell(24275, { damage = "magic" }),
	holy_light = Spell(82326, { beneficial = true }),
	holy_prism = Spell(114165, { beneficial = true, damage = "magic" }),
	holy_shock = Spell(20473, { beneficial = true, damage = "magic" }),
	intercession = Spell(391054),
	judgment = Spell(275773, { damage = "magic", targeted = false }),
	lay_on_hands = Spell(633, { beneficial = true, ignore_casting = true }),
	light_of_dawn = Spell(85222, { beneficial = true }),
	rebuke = Spell(96231),
	rite_of_adjuration = Spell(433583),
	rite_of_sanctification = Spell(433568),
	shield_of_the_righteous = Spell(415091, { damage = "magic", targeted = false }),
	tyrs_deliverance = Spell(200652, { beneficial = true }),
	word_of_glory = Spell(85673, { beneficial = true }),
	sacred_weapon = Spell(432472, { targeted = true, beneficial = true }),
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
	blessing_of_summer = Spell(388007),
	unending_light = Spell(394709)
}

local talents = {
	veneration = Spell(392938, { targeted = false }),
}

------------------------------
--- Targets
------------------------------
local targets = {}

-- targets.lightspawn = UnitManager:CreateSmartUnit("hpal_lightspawn", function()
-- 	local lightspawn = nil

-- 	ObjectManager.summons:loop(function(unit)
-- 		-- print("Summon:", unit.name and unit.name or "Unknown")
-- 		if unit:IsDead() then return false end
-- 		if not unit:GetExists() then return false end
-- 		lightspawn = unit

-- 		return true
-- 	end)

-- 	if lightspawn == nil then
-- 		mint.console.log("No lightspawn found")
-- 		return none
-- 	end

-- 	return lightspawn
-- end)

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
--- Aura Mastery
------------------------------
spells.aura_mastery:AddCallback(function(spell)

end)

------------------------------
--- Avenging Wrath
------------------------------
spells.avenging_wrath:AddCallback(function(spell)

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
spells.beacon_of_virtue:AddCallback(function(spell)

end)

spells.beacon_of_virtue:AddCallback("Mythic+", function(spell)

end)

spells.beacon_of_virtue:AddCallback("Raid", function(spell)

end)

------------------------------
--- Blessing of Summer
------------------------------
spells.blessing_of_summer:AddCallback("bless", function(spell)
    return spell:Cast(player)
end)

------------------------------
--- Blessing of Autumn
------------------------------
spells.blessing_of_autumn:AddCallback("bless", function(spell)
    return spell:Cast(player)
end)

------------------------------
--- Blessing of Winter
------------------------------
spells.blessing_of_winter:AddCallback("bless", function(spell)
    return spell:Cast(player)
end)

------------------------------
--- Blessing of Spring
------------------------------
spells.blessing_of_spring:AddCallback("bless", function(spell)
    return spell:Cast(player)
end)

------------------------------
--- Cleanse
------------------------------
spells.cleanse:AddCallback("Smart Dispel", function(spell)
    if not targets.dispel:GetExists() or targets.dispel:IsDead() then
        return false
    end

	mint.console.log("Attempted to dispel target:", targets.dispel.name)

    return spell:Cast(targets.dispel)
end)

------------------------------
--- Consecration
------------------------------
spells.consecration:AddCallback(function(spell)
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

------------------------------
--- Divine Toll
------------------------------
spells.divine_toll:AddCallback(function(spell)

end)

spells.divine_toll:AddCallback("Healing", function(spell)
	-- Avoid casting if it will over cap Holy Power
	if player:GetPower(9) > 2 then return false end

    if FriendManager:GetCountBelow(90) >= 2 then
		-- In Raid, we want to cast on a target missing hp, not always ourselves.
		if IsInRaid() then
			local lowest = FriendManager:GetLowest(90) or none

			if lowest:GetExists() then
				return spell:Cast(lowest)
			end
		else
			return spell:Cast(player)
		end
    end

    return false
end)

-- spells.divine_toll:AddCallback("Healing", function(spell)

-- end)

-- spells.divine_toll:AddCallback("Damage", function(spell)

-- end)

------------------------------
--- Eternal Flame
------------------------------
spells.eternal_flame:AddCallback(function(spell)

end)

-- spells.eternal_flame:AddCallback("Lightspawn", function(spell)
-- 	if not targets.lightspawn:GetExists() then
-- 		return false
-- 	end

-- 	if targets.lightspawn:GetHP() > 80 then
-- 		return false
-- 	end

-- 	-- if targets.lightspawn:GetMeleeCount() < 1 then
-- 	-- 	return false
-- 	-- end

-- 	return spell:Cast(targets.lightspawn)
-- end)

spells.eternal_flame:AddCallback("Spread Dawnlight", function(spell)
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
        return spell:Cast(no_dawnlight)
    end

    return false
end)

spells.eternal_flame:AddCallback("Emergency", function(spell)
    local lowest = FriendManager:GetLowest(50) or none

    if lowest:GetExists() then
        return spell:Cast(lowest)
    end

    return false
end)

-- Blessing of summer does more damage with EF than SoTR (it includes overhealing)
spells.eternal_flame:AddCallback("Summer", function(spell)
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

spells.eternal_flame:AddCallback("Dump HP", function(spell)
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

------------------------------
--- Flash of Light
------------------------------
spells.flash_of_light:AddCallback(function(spell)

end)

------------------------------
--- Hammer of Justice
------------------------------
spells.hammer_of_justice:AddCallback(function(spell)

end)

spells.hammer_of_justice:AddCallback("Auto HoJ", function(spell)
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

spells.hammer_of_wrath:AddCallback(function(spell)
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

spells.holy_light:AddCallback("Spot Healing", function(spell)
	if not player:FindBuff(auras.divine_favor):Active() then
		return false
	end

	if player:IsCastingSpell(spell.id) then
		return false
	end

	if StopTimer:GetTime() < 0.25 then
		return false
	end

    local lowest = FriendManager:GetLowest(70) or none

    if lowest:GetExists() then
		spell:Cast(lowest)
	end

    return false
end)

------------------------------
--- Holy Prism
------------------------------
spells.holy_prism:AddCallback("Generate Dawnlights", function(spell)
	if not player:FindBuff(auras.avenging_wrath):Active() then
		return false
	end

	if not target:GetExists() or target:IsFriend() then
		return false
	end

	return spell:Cast(target)
end)

-- Cast on an enemy for AoE healing
spells.holy_prism:AddCallback("Group Healing", function(spell)
	-- If user is manually using wings, just use on CD
	-- If we don't haave wings up and the CD will be up before next prism
	-- is available, hold for wings
	if toggles.cooldowns
	and not player:FindBuff(auras.avenging_wrath):Active()
	and spells.avenging_wrath:GetRemainingCD() < 25 then
		return false
	end

    if FriendManager:GetCountBelow(95) >= 2 and target:GetExists() and target:IsEnemy() then
        return spell:Cast(target)
    end

    return false
end)

------------------------------
--- Holy Shock
------------------------------
spells.holy_shock:AddCallback(function(spell)

end)

-- spells.holy_shock:AddCallback("Lightspawn", function(spell)
-- 	if not targets.lightspawn:GetExists() then
-- 		return false
-- 	end

-- 	if targets.lightspawn:GetHP() > 80 then
-- 		return false
-- 	end

-- 	if player:GetPower(9) > 4 then
-- 		return false
-- 	end

-- 	if targets.lightspawn:GetMeleeCount() < 1 then
-- 		return false
-- 	end

-- 	return spell:Cast(targets.lightspawn)
-- end)

spells.holy_shock:AddCallback("Healing", function(spell)
    local lowest = FriendManager:GetLowest(90) or none

	if player:GetPower(9) > 4 then
		return false
	end

    if lowest:GetExists() then
        return spell:Cast(lowest)
    end
	
    return false
end)

spells.holy_shock:AddCallback("Damage", function(spell)

	if IsInRaid() and profile.hold_hs_charge and spell.charges < 2 then
		return false
	end

	if player:GetPower(9) > 4 then
		return false
	end

	if profile.summer_heal_spam and player:FindBuff(auras.blessing_of_summer):Active() then
		local no_beacon = FriendManager:GetLowest(false, function(friend)
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

------------------------------
--- Lay on Hands
------------------------------
spells.lay_on_hands:AddCallback(function(spell)

end)

spells.lay_on_hands:AddCallback("Emergency", function(spell)
    if not profile.loh_toggle then return false end
    local threshold = profile.loh_pct
    local lowest = FriendManager:GetLowest(threshold) or none

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
	local lowest = FriendManager:GetLowest(threshold) or none

	if lowest:GetExists() then
		return spell:Cast(lowest)
	end

	return false
end)

------------------------------
--- Light of Dawn
------------------------------
local function GetBestCone(angle, range, min)
	local pos = player:GetPosition()
	if not pos:IsValid() then return false end

	local cone_table = {}
	FriendManager:Loop(function(friend)
		if not friend.dead and player:GetDistanceSquared(friend) < (range * range) then
			local fpos = friend:GetPosition()
			if fpos:IsValid() then
				local angle_to_friend = pos:Angle(fpos)
				if angle_to_friend then
					cone_table[#cone_table + 1] = angle_to_friend
				end
			end
		end
	end)

	local best_angle
	if #cone_table > 0 then
		local max = 0
		table.sort(cone_table, function(a, b) return a < b end)

		for i = 1, #cone_table do
			local start_angle = cone_table[i]
			local j = i + 1
			while j <= #cone_table and cone_table[j] - start_angle <= angle do
				j = j + 1
			end
			local end_angle = cone_table[j-1]
			local points_count = j - i
			if points_count > max then
				max = points_count
				best_angle = (start_angle + end_angle) / 2
			end
		end

		if max < min then
			return false
		end
	end

	return best_angle
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

spells.light_of_dawn:AddCallback(function(spell)

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
		if right_down then MouseLookStop() end
		if left_down then CameraOrSelectMoveStop() end
		mint.FaceDirection(bestAngle, true)
		local res = spell:Cast(player)
		mint.FaceDirection(original, true)
		if right_down then MouseLookStart() end
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

spells.rebuke:AddCallback("Smart Kick", function(spell)
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

spells.shield_of_the_righteous:AddCallback("Dump HP", function(spell)
    if IsInRaid() then return false end
    -- if not targets.melee:GetExists() then return false end
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

------------------------------
--- Sacred Weapon
------------------------------
spells.sacred_weapon:AddCallback(function(spell)

end)

addon.paladin.data["Holy"].spells 	= spells
-- addon.paladin.data["Holy"].items 	= items
addon.paladin.data["Holy"].auras 	= auras
addon.paladin.data["Holy"].targets 	= targets