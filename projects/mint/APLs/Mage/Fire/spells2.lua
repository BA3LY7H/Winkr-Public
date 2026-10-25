local unlocker,
---@class mint
mint,
addon = ...

--! Tea Locals !--
local UnitManager   = mint.UnitManager
local ObjectManager = mint.ObjectManager
local FriendManager = mint.FriendManager
local Events        = mint.EventManager
local Constants     = mint.Constants
local RaidEvents   	= mint.RaidEvents
local Totems 		= mint.TotemManager
local Queue 	   	= mint.Queue
local Spell         = mint.Spell.New
local Item 			= mint.Item.New
local target        = UnitManager:Get("target")
local player        = UnitManager:Get("player")
local None          = UnitManager:Get("none")
local bin 			= mint.bin

local vars 			= addon.mage.data.vars

local spells = {
	alter_time              = Spell(342245, { targeted = false }),
	arcane_explosion        = Spell(1449, { targeted = false }),
	arcane_intellect        = Spell(1459),
	blast_wave              = Spell(157981, { targeted = false }),
	blazing_barrier         = Spell(235313, { targeted = false }),
	combustion              = Spell(190319, { targeted = false }),
	cone_of_cold            = Spell(120, { targeted = false }),
	conjure_refreshment     = Spell(190336, { targeted = false }),
	counterspell            = Spell(2139),
	fire_blast              = Spell(108853, {
		ignore_casting = true,
		ignore_channel = true
	}),
	fireball                = Spell(133, {
		velocity = 40,
	}),
	flamestrike             = Spell(2120, { targeted = false, radius = 10 }),
	frost_nova              = Spell(122, { targeted = false }),
	frostbolt               = Spell(116),
	gravity_lapse           = Spell(449700),
	greater_invisibility    = Spell(110959, { targeted = false }),
	ice_cold                = Spell(414658, { targeted = false }),
	mass_barrier            = Spell(414660, { targeted = false }),
	mass_polymorph          = Spell(383121, { targeted = false }),
	mirror_image            = Spell(55342, { targeted = false }),
	phoenix_flames          = Spell(257541, {
		velocity = 50,
	}),
	polymorph               = Spell(118),
	pyroblast               = Spell(11366, {
		velocity = 35,
	}),
	remove_curse            = Spell(475, { beneficial = true, dispel = true }),
	scorch                  = Spell(2948, { ignore_moving = true }),
	shifting_power          = Spell(382440, { targeted = false }),
	shimmer                 = Spell(212653),
	slow_fall               = Spell(130),
	spellsteal              = Spell(30449, { effect = "magic", dispel = true }),
	time_warp               = Spell(80353, { targeted = false }),
}

local auras = {
    alter_time          = Spell(342246),
    arcane_intellect    = Spell(1459),
    blazing_barrier     = Spell(235313),
    combustion          = Spell(190319),
    feel_the_burn       = Spell(383395),
    greater_invis       = Spell(110960),
    greater_invis_dr    = Spell(113862),
    heat_shimmer        = Spell(457735),
    heating_up          = Spell(48107),
    hot_streak          = Spell(48108),
    hyperthermia        = Spell(383874),
    ice_cold            = Spell(414658),
    ignite              = Spell(12654),
    imp_scorch          = Spell(383608),
    mirror_image        = Spell(55342),
    phoenix_reborn      = Spell(1219304),
    spellfire_sphere    = Spell(448604),

	-- Negative
	devouring_rift 		= Spell(440313),
}

local talents = {
	sunfury_execution 	= Spell(449349),
}

local items = {
	hyperthread_wristwraps 	= Item(168989),
	signet_of_the_priory 	= Item(219308, { use_name = true }),
	tempered_potion 		= Item(212264),
}

local hot_streak_spells = {
	spells.fireball,
	spells.phoenix_flames,
	spells.pyroblast,
	-- spells.scorch
}

local function HotStreaksInFlight()
	local count = 0
	for k, spell in pairs(hot_streak_spells) do
		if Queue:IsInFlight(spell) then
			count = count + 1
		end
	end

	return count
end

vars.cast_remains_time = 0.3
vars.pooling_time = 10
-- sf_combustion_flamestrike
vars.sf_combustion_flamestrike = 5
	-- 5
	-- + (1 - bin(Talent:Enabled("mark_of_the_firelord"))) * 99
	-- + (1 - bin(Talent:Enabled("flame_patch") or Talent:Enabled("quickflame"))) * bin(Talent:Enabled("firefall")) * 99
	-- + bin(Talent:Enabled("firefall"))
	-- + (1 - bin(Talent:Enabled("flame_patch") or Talent:Enabled("quickflame"))) * 3
-- sf_filler_flamestrike
vars.sf_filler_flamestrike = 4
	-- 4
	-- + bin(Talent:Enabled("firefall"))
	-- + (1 - bin(Talent:Enabled("mark_of_the_firelord")))
	-- + (1 - bin(Talent:Enabled("flame_patch") or Talent:Enabled("quickflame")))
	-- + (1 - bin(Talent:Enabled("mark_of_the_firelord")) * (1 - bin(Talent:Enabled("flame_patch") or Talent:Enabled("quickflame"))) * 2)
	-- + (1 - bin(Talent:Enabled("mark_of_the_firelord")) * (1 - bin(Talent:Enabled("flame_patch") or Talent:Enabled("quickflame"))) * bin(Talent:Enabled("firefall")) * 99)

    -- actions.cds+=/variable,name=combustion_precast_time,value=(action.scorch.cast_time)-variable.cast_remains_time
vars.combustion_precast_time = spells.scorch:GetCastTime() - vars.cast_remains_time

-- bool scorch_execute_active( player_t* target ) const
-- {
--   if ( !p()->talents.scorch.ok() )
-- 	return false;

--   if ( p()->state.heat_shimmer && p()->buffs.heat_shimmer->check() )
-- 	return true;

--   return target->health_percentage() <= p()->talents.scorch->effectN( 2 ).base_value() + p()->talents.sunfury_execution->effectN( 2 ).base_value();
-- }

local function ScorchExecuteActive(unit)
	-- if unit doesn't exist, return false
	if not unit or not unit:GetExists() then
		return false
	end

	-- if we don't know scorch, return false
	if not spells.scorch:IsKnown() then
		return false
	end

	-- if we have heat shimmer active, return true
	if player:FindBuff(auras.heat_shimmer):Active() then
		return true
	end

	-- Sunfury talent increases threshold by 5%
	local threshold = 30 + (bin(talents.sunfury_execution:IsKnown()) * 5)

	-- if the unit is below the threshold, return true

	if unit:GetHP() < threshold then
		return true
	end
end

local function WillCurrentScorchCrit()
	if not target:GetExists() or target:IsFriend() then
		return false
	end

	-- Check Heat Shimmer
	if player:FindBuff(auras.heat_shimmer):Active() then
		return true
	end

	-- Sunfury talent increases threshold by 5%
	local threshold = 30 + (bin(talents.sunfury_execution:IsKnown()) * 5)

	-- Check Execute Threshold
	if target:GetHP() < threshold then
		return true
	end

	-- Check combustion
	if player:FindBuff(auras.combustion):Active() then
		return true
	end

	return false
end



local targets = {}

targets.kick = UnitManager:CreateSmartUnit("fire_kick", function()
	local closest = nil
	local closest_dist = math.huge
	
	if not mint.data.toggles.kicks then
		return None
	end

	ObjectManager.combat:loop(function(enemy)
		if enemy.dead then return false end
		if not enemy:IsCastingOrChanneling() then return false end
		if not enemy:IsKickable() then return false end
		-- if not Constants.TWWS2.kicks[enemy:GetCastSpellID()] then return false end
		if not spells.counterspell:IsInRange(enemy) then return false end
		if not player:HasLos(enemy) then return false end

		local dist = player:GetDistanceSquared(enemy)
		if dist < closest_dist then
			closest_dist = dist
			closest = enemy
		end

		return false
	end)

	if closest == nil then
		return None
	end

	return closest
end)

targets.spellsteal = UnitManager:CreateSmartUnit("fire_kick", function()
	local ss_target = nil
	
	-- if not mint.data.toggles.kicks then
	-- 	return None
	-- end

	ObjectManager.combat:loop(function(enemy)
		if enemy.dead then return false end
		if not spells.spellsteal:IsInRange(enemy) then return false end
		if not player:HasLos(enemy) then return false end
		if not enemy:HasSpellstealAura() then return false end

		ss_target = enemy
		return true
	end)

	if ss_target == nil then
		return None
	end

	return ss_target
end)

------------------------------
--- Items
------------------------------

-- use_item,name=hyperthread_wristwraps,if=hyperthread_wristwraps.fire_blast>=2&buff.combustion.remains&action.fire_blast.charges=0
items.hyperthread_wristwraps:AddCallback(function(item)
	-- hyperthread_wristwraps.fire_blast>=2
	if not spells.fire_blast:WasXOfYMostRecent(2, 3) then
		return false
	end

	-- &buff.combustion.remains
	if not player:FindBuff(auras.combustion):Active() then
		return false
	end

	-- &action.fire_blast.charges=0
	if spells.fire_blast:GetCharges() > 0 then
		return false
	end

	return item:Use(player)
end)

-- potion,if=!talent.sun_kings_blessing&cooldown.combustion.remains<=variable.combustion_precast_time|buff.combustion.remains>7|fight_remains<35
items.tempered_potion:AddCallback(function(item)
	if not target:GetExists() or target:IsFriend() then
		return false
	end
	
	-- &cooldown.combustion.remains<=variable.combustion_precast_time
	if spells.combustion:GetRemainingCD() <= vars.combustion_precast_time then
		return item:Use(player)
	end

	-- |buff.combustion.remains>7
	if player:FindBuff(auras.combustion):Remains() > 7 then
		return item:Use(player)
	end

	return false
end)

-- use_item,name=signet_of_the_priory,if=!talent.sun_kings_blessing&cooldown.combustion.remains<=variable.combustion_precast_time|buff.combustion.remains>7|fight_remains<20
items.signet_of_the_priory:AddCallback(function(item)
	if not target:GetExists() or target:IsFriend() then
		return false
	end
	
	-- &cooldown.combustion.remains<=variable.combustion_precast_time
	if spells.combustion:GetRemainingCD() <= vars.combustion_precast_time then
		return item:Use(player)
	end

	-- |buff.combustion.remains>7
	if player:FindBuff(auras.combustion):Remains() > 7 then
		return item:Use(player)
	end

	return false
end)

------------------------------
--- Alter Time
------------------------------
spells.alter_time:AddCallback(function(spell)

end)

------------------------------
--- Arcane Explosion
------------------------------
spells.arcane_explosion:AddCallback(function(spell)

end)

------------------------------
--- Arcane Intellect
------------------------------
spells.arcane_intellect:AddCallback(function(spell)

end)

------------------------------
--- Blast Wave
------------------------------
spells.blast_wave:AddCallback(function(spell)

end)

------------------------------
--- Blazing Barrier
------------------------------
spells.blazing_barrier:AddCallback("Pre-combat: Default", function(spell)
	spell:Cast(player)
end)

------------------------------
--- Combustion
------------------------------
spells.combustion:AddCallback("Combustion: Pre-cast", function(spell)
    if player:FindBuff(auras.combustion):Active() then return false end
    if not spells.fireball:IsCurrentCast() and not spells.scorch:IsCurrentCast() then return false end
    if player:TimeToCast() > vars.cast_remains_time then return false end

    return spell:Cast(player)
end)

------------------------------
--- Cone of Cold
------------------------------
spells.cone_of_cold:AddCallback(function(spell)

end)

------------------------------
--- Conjure Refreshment
------------------------------
spells.conjure_refreshment:AddCallback(function(spell)

end)

------------------------------
--- Counterspell
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

spells.counterspell:AddCallback("kick", function(spell)
	if not mint.data.toggles.kicks then return false end
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
--- Fire Blast
------------------------------
spells.fire_blast:AddCallback("Combustion: Default", function(spell)
	if not target:GetExists() or target:IsFriend() then
		return false
	end

	if C_Spell.IsCurrentSpell(spell.id) then
		mint:CombatLog("Not using Fire Blast because it is currently queued.")
		return false
	end

	-- This seems pointless
	-- if mint.gcd > mint.max_gcd then
	-- 	return false
	-- end

	if not player:FindBuff(auras.combustion):Active() then
		return false
	end

	if player:FindBuff(auras.hot_streak):Active() then
		return false
	end

	if HotStreaksInFlight() + (bin(player:FindBuff(auras.heating_up):Active()) * bin(mint.gcd > 0)) >= 2 then
		return false
	end

	return spell:Cast(target)
end)

spells.fire_blast:AddCallback("Filler: Hyperthermia", function(spell)
	if not target:GetExists() or target:IsFriend() then
		return false
	end

	if C_Spell.IsCurrentSpell(spell.id) then
		mint:CombatLog("Not using Fire Blast because it is currently queued.")
		return false
	end

	if not player:FindBuff(auras.heating_up):Active() then
		return false
	end

	if not player:FindBuff(auras.hyperthermia):Active() then
		return false
	end

	if spells.combustion:GetRemainingCD() <= vars.pooling_time then
		return false
	end

	return spell:Cast(target)
end)

-- fire_blast,use_off_gcd=1,use_while_casting=1,if=cooldown_react&buff.heating_up.react&action.fireball.executing&action.fireball.execute_remains<0.5&cooldown.combustion.remains>variable.pooling_time
spells.fire_blast:AddCallback("Filler: Fireball", function(spell)
	if not target:GetExists() or target:IsFriend() then
		return false
	end

	if C_Spell.IsCurrentSpell(spell.id) then
		mint:CombatLog("Not using Fire Blast because it is currently queued.")
		return false
	end

	-- &buff.heating_up.react
	if not player:FindBuff(auras.heating_up):Active() then
		return false
	end

	-- &action.fireball.executing
	if not player:IsCastingSpell(spells.fireball.id) then
		return false
	end

	-- &action.fireball.execute_remains<0.5
	if player:TimeToCast() > 0.5 then
		return false
	end

	-- &cooldown.combustion.remains>variable.pooling_time
	if spells.combustion:GetRemainingCD() <= vars.pooling_time then
		return false
	end

	return spell:Cast(target)
end)

spells.fire_blast:AddCallback("Filler: Scorch", function(spell)
	if not target:GetExists() or target:IsFriend() then
		return false
	end

	if C_Spell.IsCurrentSpell(spell.id) then
		mint:CombatLog("Not using Fire Blast because it is currently queued.")
		return false
	end

	-- If scorch will crit for certain we want NO buffs
	if WillCurrentScorchCrit() then
		-- &!buff.heating_up.react
		if player:FindBuff(auras.heating_up):Active() then
			return false
		end

		-- &!buff.hot_streak.react
		if player:FindBuff(auras.hot_streak):Active() then
			return false
		end
	else
		-- If scorch will not crit 100%, we want heating up
		if not player:FindBuff(auras.heating_up):Active() then
			return false
		end
	end

	-- &action.scorch.executing
	if not player:IsCastingSpell(spells.scorch.id) then
		return false
	end

	-- &action.scorch.execute_remains<0.5
	if player:TimeToCast() > 0.5 then
		return false
	end

	-- &cooldown.combustion.remains>variable.pooling_time
	if spells.combustion:GetRemainingCD() <= vars.pooling_time then
		return false
	end

	return spell:Cast(target)
end)

spells.fire_blast:AddCallback("Filler: Avoid Cap", function(spell)
	if not target:GetExists() or target:IsFriend() then
		return false
	end

	if C_Spell.IsCurrentSpell(spell.id) then
		mint:CombatLog("Not using Fire Blast because it is currently queued.")
		return false
	end

	-- &charges=3
	if spell:GetCharges() ~= 3 then
		return false
	end

	-- &cooldown.combustion.remains>variable.pooling_time*0.3
	if spells.combustion:GetRemainingCD() <= (vars.pooling_time * 0.3) then
		return false
	end

	return spell:Cast(target)
end)

spells.fire_blast:AddCallback("Filler: Glorious Incandescence", function(spell)
	if not target:GetExists() or target:IsFriend() then
		return false
	end

	if C_Spell.IsCurrentSpell(spell.id) then
		mint:CombatLog("Not using Fire Blast because it is currently queued.")
		return false
	end

	-- active_enemies>=2
	if target:GetEnemies(9) < 2 then
		return false
	end

	-- &buff.glorious_incandescence.react
	if not player:FindBuff(auras.glorious_incandescence):Active() then
		return false
	end

	-- &!buff.heating_up.react
	if player:FindBuff(auras.heating_up):Active() then
		return false
	end

	-- &!buff.hot_streak.react
	if player:FindBuff(auras.hot_streak):Active() then
		return false
	end

	-- &cooldown.combustion.remains>variable.pooling_time
	if spells.combustion:GetRemainingCD() <= vars.pooling_time then
		return false
	end

	return spell:Cast(target)
end)

------------------------------
--- Fireball
------------------------------
spells.fireball:AddCallback(function(spell)

end)

-- fireball,if=!player.moving
spells.fireball:AddCallback("Filler: Default", function(spell)
	if not target:GetExists() or target:IsFriend() then
		return false
	end

	if player:IsMoving() then
		return false
	end

	return spell:Cast(target)
end)

------------------------------
--- Flamestrike
------------------------------
spells.flamestrike:AddCallback("Combustion: Hyperthermia", function(spell)
	if not target:GetExists() or target:IsFriend() then
		return false
	end

	if not player:FindBuff(auras.hyperthermia):Active() then
		return false
	end

	if target:GetEnemies(9) < vars.sf_combustion_flamestrike then
		return false
	end

	return spell:CastUnder(target)
end)

spells.flamestrike:AddCallback("Combustion: Hot Streak", function(spell)
	if not target:GetExists() or target:IsFriend() then
		return false
	end

	if not player:FindBuff(auras.hot_streak):Active() then
		return false
	end

	if target:GetEnemies(9) < vars.sf_combustion_flamestrike then
		return false
	end

	return spell:CastUnder(target)
end)

spells.flamestrike:AddCallback("Combustion: Predicted Hot Streak", function(spell)
	if not target:GetExists() or target:IsFriend() then
		return false
	end

	if not player:IsCastingSpell(spells.scorch.id) then
		return false
	end

	if not player:FindBuff(auras.heating_up):Active() then
		return false
	end

	if target:GetEnemies(9) < vars.sf_combustion_flamestrike then
		return false
	end

	return spell:CastUnder(target)
end)

-- flamestrike,if=buff.hyperthermia.react&active_enemies>=variable.sf_filler_flamestrike
spells.flamestrike:AddCallback("Filler: Hyperthermia", function(spell)
	if not target:GetExists() or target:IsFriend() then
		return false
	end

	-- buff.hyperthermia.react
	if not player:FindBuff(auras.hyperthermia):Active() then
		return false
	end

	-- &active_enemies>=variable.sf_filler_flamestrike
	if target:GetEnemies(9) < vars.sf_combustion_flamestrike then
		return false
	end

	return spell:CastUnder(target)
end)

-- flamestrike,if=buff.hot_streak.react&active_enemies>=variable.sf_filler_flamestrike
spells.flamestrike:AddCallback("Filler: Hot Streak", function(spell)
	if not target:GetExists() or target:IsFriend() then
		return false
	end

	-- buff.hot_streak.react
	if not player:FindBuff(auras.hot_streak):Active() then
		return false
	end

	-- &active_enemies>=variable.sf_filler_flamestrike
	if target:GetEnemies(9) < vars.sf_combustion_flamestrike then
		return false
	end

	return spell:CastUnder(target)
end)

-- flamestrike,if=prev_gcd.1.scorch&buff.heating_up.react&active_enemies>=variable.sf_filler_flamestrike
spells.flamestrike:AddCallback("Filler: Predicted Hot Streak", function(spell)
	if not target:GetExists() or target:IsFriend() then
		return false
	end

	-- prev_gcd.1.scorch
	if not player:IsCastingSpell(spells.scorch.id) or not WillCurrentScorchCrit() then
		return false
	end

	-- &buff.heating_up.react
	if not player:FindBuff(auras.heating_up):Active() then
		return false
	end

	-- &active_enemies>=variable.sf_filler_flamestrike
	if target:GetEnemies(9) < vars.sf_combustion_flamestrike then
		return false
	end

	return spell:CastUnder(target)
end)

------------------------------
--- Frost Nova
------------------------------
spells.frost_nova:AddCallback(function(spell)

end)

------------------------------
--- Frostbolt
------------------------------
spells.frostbolt:AddCallback(function(spell)

end)

------------------------------
--- Gravity Lapse
------------------------------
spells.gravity_lapse:AddCallback(function(spell)

end)

------------------------------
--- Greater Invisibility
------------------------------
spells.greater_invisibility:AddCallback(function(spell)

end)

------------------------------
--- Ice Cold
------------------------------
spells.ice_cold:AddCallback(function(spell)

end)

------------------------------
--- Mass Barrier
------------------------------
spells.mass_barrier:AddCallback(function(spell)

end)

------------------------------
--- Mass Polymorph
------------------------------
spells.mass_polymorph:AddCallback(function(spell)

end)

------------------------------
--- Mirror Image
------------------------------
spells.mirror_image:AddCallback(function(spell)

end)

------------------------------
--- Phoenix Flames
------------------------------
spells.phoenix_flames:AddCallback("Combustion: Default", function(spell)
	if not target:GetExists() or target:IsFriend() then
		return false
	end

	return spell:Cast(target)
end)

-- phoenix_flames
spells.phoenix_flames:AddCallback("Filler: Default", function(spell)
	if not target:GetExists() or target:IsFriend() then
		return false
	end

	return spell:Cast(target)
end)

-- phoenix_flames,if=time=0&!talent.firestarter
spells.phoenix_flames:AddCallback("Opener", function(spell)
	local combat_time = GetTime() - mint.combatStartTime

	-- TODO: Add Firestarter check
	-- TODO: make check to be "have we cast a spell this combat"
	-- rather than "if combat time is low"
	if combat_time < 0.5 then
		return spell:Cast(target)
	end

	return false
end)

------------------------------
--- Polymorph
------------------------------
spells.polymorph:AddCallback(function(spell)

end)

------------------------------
--- Pyroblast
------------------------------
spells.pyroblast:AddCallback(function(spell)

end)

spells.pyroblast:AddCallback("Combustion: Hyperthermia", function(spell)
	if not target:GetExists() or target:IsFriend() then
		return false
	end

	if not player:FindBuff(auras.hyperthermia):Active() then
		return false
	end

	return spell:Cast(target)
end)

spells.pyroblast:AddCallback("Combustion: Hot Streak", function(spell)
	if not target:GetExists() or target:IsFriend() then
		return false
	end

	if not player:FindBuff(auras.hot_streak):Active() then
		return false
	end

	return spell:Cast(target)
end)

spells.pyroblast:AddCallback("Combustion: Predicted Hot Streak", function(spell)
	if not target:GetExists() or target:IsFriend() then
		return false
	end

	if not player:IsCastingSpell(spells.scorch.id) then
		return false
	end

	if not player:FindBuff(auras.heating_up):Active() then
		return false
	end

	return spell:Cast(target)
end)

-- pyroblast,if=buff.hyperthermia.react
spells.pyroblast:AddCallback("Filler: Hyperthermia", function(spell)
	if not target:GetExists() or target:IsFriend() then
		return false
	end

	-- buff.hyperthermia.react
	if not player:FindBuff(auras.hyperthermia):Active() then
		return false
	end

	return spell:Cast(target)
end)

-- pyroblast,if=buff.hot_streak.react&cooldown.combustion.remains>variable.pooling_time*0.3
spells.pyroblast:AddCallback("Filler: Hot Streak", function(spell)
	if not target:GetExists() or target:IsFriend() then
		return false
	end

	-- buff.hot_streak.react
	if not player:FindBuff(auras.hot_streak):Active() then
		return false
	end

	-- &cooldown.combustion.remains>variable.pooling_time*0.3
	if spells.combustion:GetRemainingCD() <= (vars.pooling_time * 0.3) then
		return false
	end

	return spell:Cast(target)
end)

-- pyroblast,if=prev_gcd.1.scorch&buff.heating_up.react&cooldown.combustion.remains>variable.pooling_time*0.3
spells.pyroblast:AddCallback("Filler: Predicted Hot Streak", function(spell)
	if not target:GetExists() or target:IsFriend() then
		return false
	end

	-- prev_gcd.1.scorch
	if not player:IsCastingSpell(spells.scorch.id) or not WillCurrentScorchCrit() then
		return false
	end

	-- &buff.heating_up.react
	if not player:FindBuff(auras.heating_up):Active() then
		return false
	end

	-- &cooldown.combustion.remains>variable.pooling_time*0.3
	if spells.combustion:GetRemainingCD() <= (vars.pooling_time * 0.3) then
		return false
	end

	return spell:Cast(target)
end)

------------------------------
--- Remove Curse
------------------------------
spells.remove_curse:AddCallback(function(spell)

end)

------------------------------
--- Scorch
------------------------------
spells.scorch:AddCallback("Combustion: Opener", function(spell)
    if not target:GetExists() then return false end
    if player:FindBuff(auras.combustion):Active() then return false end

    return spell:Cast(target)
end)

spells.scorch:AddCallback("Combustion: Heat Shimmer", function(spell)
	if not target:GetExists() or target:IsFriend() then
		return false
	end

	-- If we're in the execute window then we don't care about munching Heat Shimmer
	if ScorchExecuteActive(target) then
		return false
	end

	if not player:FindBuff(auras.heat_shimmer):Active() then
		return false
	end

	return spell:Cast(target)
end)

spells.scorch:AddCallback("Combustion: Default", function(spell)
	if not target:GetExists() or target:IsFriend() then
		return false
	end

	return spell:Cast(target)
end)

-- scorch,if=buff.heat_shimmer.react
spells.scorch:AddCallback("Filler: Heat Shimmer", function(spell)
	if not target:GetExists() or target:IsFriend() then
		return false
	end
	
	-- buff.heat_shimmer.react
	if not player:FindBuff(auras.heat_shimmer):Active() then
		return false
	end

	return spell:Cast(target)
end)

-- scorch,if=scorch_execute.active
spells.scorch:AddCallback("Filler: Execute", function(spell)
	if not target:GetExists() or target:IsFriend() then
		return false
	end

	-- We want to make sure scorch execute is active on this target
	if not ScorchExecuteActive(target) then
		return false
	end

	return spell:Cast(target)
end)

-- scorch,if=player.moving
spells.scorch:AddCallback("Filler: Movement", function(spell)
	if not target:GetExists() or target:IsFriend() then
		return false
	end

	return spell:Cast(target)
end)

------------------------------
--- Shifting Power
------------------------------

-- shifting_power,if=cooldown.combustion.remains>8
spells.shifting_power:AddCallback("Filler: Default", function(spell)
	-- We should add a check for movement heavy fights/events?
	if player:IsMoving() then
		return false
	end

	if spells.combustion:GetRemainingCD() < 8 then
		return false
	end

	return spell:Cast(player)
end)

------------------------------
--- Shimmer
------------------------------
spells.shimmer:AddCallback(function(spell)

end)

------------------------------
--- Slow Fall
------------------------------
spells.slow_fall:AddCallback(function(spell)

end)

------------------------------
--- Spellsteal
------------------------------
spells.spellsteal:AddCallback(function(spell)

end)

------------------------------
--- Time Warp
------------------------------
spells.time_warp:AddCallback(function(spell)

end)

addon.mage.data.spells 	= spells
addon.mage.data.auras 	= auras
addon.mage.data.talents = talents
addon.mage.data.items 	= items
addon.mage.data.targets = targets