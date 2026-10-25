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
local Spell         = mint.Spell.New
local target        = UnitManager:Get("target")
local player        = UnitManager:Get("player")
local None          = UnitManager:Get("none")

local toggles       = mint.data.toggles
local vars 			= addon.mage.data["Fire"].vars


local spells = {
	alter_time              = Spell(342245, { targeted = false }),
	arcane_explosion        = Spell(1449, { targeted = false }),
	arcane_intellect        = Spell(1459),
	blast_wave              = Spell(157981, { targeted = false }),
	blazing_barrier         = Spell(235313, { targeted = false }),
	combustion              = Spell(190319, { targeted = false, ignore_casting = true }),
	cone_of_cold            = Spell(120, { targeted = false }),
	conjure_refreshment     = Spell(190336, { targeted = false }),
	counterspell            = Spell(2139),
	fire_blast              = Spell(108853, {
		ignore_casting = true,
		ignore_channel = true
	}),
	fireball                = Spell(133),
	flamestrike             = Spell(2120, { targeted = false, radius = 10 }),
	frost_nova              = Spell(122, { targeted = false }),
	frostbolt               = Spell(116),
	gravity_lapse           = Spell(449700),
	greater_invisibility    = Spell(110959, { targeted = false }),
	ice_cold                = Spell(414658, { targeted = false }),
	mass_barrier            = Spell(414660, { targeted = false }),
	mass_polymorph          = Spell(383121, { targeted = false }),
	mirror_image            = Spell(55342, { targeted = false }),
	phoenix_flames          = Spell(257541),
	polymorph               = Spell(118),
	pyroblast               = Spell(11366),
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

local precasts = {
	[spells.scorch.id] = true,
	[spells.fireball.id] = true,
}


local function bin(arg)
	return arg and 1 or 0
end

local function LastGeneratorAttempt()
	local lowest = 2

	local ib = spells.fire_blast:TimeSinceLastAttempt()
	local pf = spells.phoenix_flames:TimeSinceLastAttempt()

	local min = math.min(ib, pf)

	if min < lowest then
		lowest = min
	end

	return lowest
end

local function ShouldPool(spell)
	-- local time_to_cap = spell:GetFullRechargeTime()

	-- if time_to_cap >= spells.combustion:GetRemainingCD() then
	-- 	return true
	-- end

	-- return false

	return spells.combustion:GetRemainingCD() < 12
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

targets.spellsteal = UnitManager:CreateSmartUnit("fire_spellsteal", function()
	local ss_target = nil
	
	-- if not mint.data.toggles.kicks then
	-- 	return None
	-- end

	ObjectManager.combat:loop(function(enemy)
		if enemy.dead then return false end
		-- if not Constants.TWWS2.kicks[enemy:GetCastSpellID()] then return false end
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

targets.decurse = UnitManager:CreateSmartUnit("fire_decurse", function()
	local decurse_tar = nil

	if not toggles.dispels then
		return None
	end

    FriendManager:Loop(function(friend)
        if friend.dead then return true end
		if not spells.remove_curse:IsInRange(friend) then return false end
        if not friend:HasDispellableAura(spells.remove_curse) then return false end
		if not player:HasLos(friend) then return false end

        decurse_tar = friend
        return true
    end)


	if decurse_tar == nil then
		return None
	end

	return decurse_tar
end)

-- targets.dispel = UnitManager:CreateSmartUnit("rdruid_dispel", function()
-- 	local dispel_tar = nil

-- 	UnitManager.friends:loop(function(friend)
-- 		if friend.dead then return false end
-- 		if not spells.natures_cure.inRange(friend) then return false end
-- 		if not friend.los() then return false end

-- 		if friend:Auras():HasAnyPriorityDispels(spells.natures_cure) then
-- 			dispel_tar = friend
-- 			return true
-- 		end

--         return false
-- 	end)

-- 	if dispel_tar == nil then
-- 		return None
-- 	end

-- 	return dispel_tar
-- end)

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

spells.blazing_barrier:AddCallback(function(spell)
	return spell:Cast(player)
end)

------------------------------
--- Combustion
------------------------------

spells.combustion:AddCallback(function(spell)
	if not mint.data.toggles.cooldowns then
		print("not using bust because cooldowns is off")
		return false
	end
	
	if not target:GetExists() then
		return false
	end

	-- We don't use combust dry
	if not precasts[player:GetCastSpellID()] then
		return false
	end

	if player:TimeToCast() > 0.5 then
		return false
	end

	return spells.combustion:Cast(player)
end)

------------------------------
--- Cone Of Cold
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

spells.fire_blast:AddCallback("HYP, Cap", function(spell)
	if not target:GetExists() then
		return false
	end

	if LastGeneratorAttempt() < 0.5 then
		return false
	end

	if spell:WasMostRecentCast() then
		return false
	end

	if ShouldPool(spell) then
		mint:CombatLog("Pooling", spell.name)
		return false
	end

	if spell:GetFullRechargeTime() < (mint.max_gcd * 2) then
		return spell:Cast(target)
	end
end)

spells.fire_blast:AddCallback("HYP, FTB", function(spell)
	if not target:GetExists() then
		return false
	end

	if LastGeneratorAttempt() < 0.5 then
		return false
	end

	if spell:WasMostRecentCast() then
		return false
	end

	if ShouldPool(spell) then
		mint:CombatLog("Pooling", spell.name)
		return false
	end


	if player:FindBuff(auras.feel_the_burn):Remains() < (mint.max_gcd * 2) then
		return spell:Cast(target)
	end
end)


local bracers = mint.Item.New(168989)

spells.fire_blast:AddCallback("Combust", function(spell)
	if not target:GetExists() then
		return false
	end

	if LastGeneratorAttempt() < 0.5 then
		return false
	end

	-- if spell:WasMostRecentCast() and not player:IsCasting() then
	if C_Spell.IsCurrentSpell(spell.id) then
		mint:CombatLog("Not using Fire Blast because it is currently queued.")
		return false
	end

	if spell:GetCharges() == 1 then
		spell:Cast(target)
		bracers:Use(player)
		return true
	else
		spell:Cast(target)
	end


end)

spells.fire_blast:AddCallback("MidCast", function(spell)
	if not target:GetExists() then
		return false
	end

	if LastGeneratorAttempt() < 0.5 then
		return false
	end

	if not precasts[player:GetCastSpellID()] then
		return false
	end

	if spell:WasMostRecentCast() then
		return false
	end

	if ShouldPool(spell) then
		mint:CombatLog("Pooling", spell.name)
		return false
	end

	if not player:FindBuff(auras.heating_up):Active() then
		return false
	end

	return spell:Cast(target)
end)

spells.fire_blast:AddCallback("Shifting Power", function(spell)
	if not target:GetExists() then
		return false
	end

	if player:GetCastSpellID() ~= spells.shifting_power.id then
		return false
	end

	if LastGeneratorAttempt() < 0.5 then
		return false
	end

	if spell:WasMostRecentCast() then
		return false
	end

	if ShouldPool(spell) then
		mint:CombatLog("Pooling", spell.name)
		return false
	end

	if spell:GetFullRechargeTime() < mint.max_gcd then
		return spell:Cast(target)
	end

	return false
end)

------------------------------
--- Fireball
------------------------------

spells.fireball:AddCallback("Combust", function(spell)
	if not target:GetExists() then
		return false
	end

	if player:IsMoving() then
		return false
	end

	return spell:Cast(target)
end)

spells.fireball:AddCallback(function(spell)
	if not target:GetExists() then
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

spells.flamestrike:AddCallback("Hot Streak", function(spell)
    if not target:GetExists() then
        return false
    end

	return spell:CastUnder(target)
end)

spells.flamestrike:AddCallback("Hyperthermia", function(spell)
    if not target:GetExists() then
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

spells.phoenix_flames:AddCallback("Opener", function(spell)
	if not target:GetExists() then
        return false
    end

	if vars.opener.phoenix then
		-- mint:Log("We have already cast Phoenix Flames in the opener.")
		return false
	end

	if player:GetCastSpellID() ~= spells.pyroblast.id
	and not spells.pyroblast:WasMostRecentCast() then
		-- mint:Log("We are holding Phoenix Flames until Pyro.")
		return false
	end

	if player:TimeToCast() > 0.3 then
		return false
	end

	if spell:Castable(target) then
		return spell:Cast(target)
	end
end)

spells.phoenix_flames:AddCallback("Combust", function(spell)
	if not target:GetExists() then
		return false
	end

	if spells.fire_blast:TimeSinceLastAttempt() < 0.5 then
		return false
	end

	return spell:Cast(target)
end)

spells.phoenix_flames:AddCallback(function(spell)
	if not target:GetExists() then
		return false
	end

	if spells.fire_blast:TimeSinceLastAttempt() < 0.5 then
		return false
	end

	if ShouldPool(spell) then
		mint:CombatLog("Pooling", spell.name)
		return false
	end

	return spell:Cast(target)
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
    if not target:GetExists() then
        return false
    end

	return spell:Cast(target)
end)

spells.pyroblast:AddCallback("Hot Streak", function(spell)
    if not target:GetExists() then
        return false
    end

	return spell:Cast(target)
end)

spells.pyroblast:AddCallback("Opener", function(spell)
    if not target:GetExists() then
        return false
    end

	if vars.opener.pyroblast then
		return false
	end

    return false
end)

spells.pyroblast:AddCallback("Hyperthermia", function(spell)
    if not target:GetExists() then
        return false
    end

    return spell:Cast(target)
end)

------------------------------
--- Remove Curse
------------------------------

spells.remove_curse:AddCallback("devRift", function(spell)
	spell:Cast(player)
end)

spells.remove_curse:AddCallback("help", function(spell)
	if not targets.decurse:GetExists() or targets.decurse:IsDead() then
        return false
    end
	
    return spell:Cast(targets.decurse)
end)

-- targets.dispel = UnitManager:CreateSmartUnit("rdruid_dispel", function()
	-- 	local dispel_tar = nil
	
	-- 	UnitManager.friends:loop(function(friend)
	-- 		if friend.dead then return false end
	-- 		if not spells.natures_cure.inRange(friend) then return false end
	-- 		if not friend.los() then return false end
	
	-- 		if friend:Auras():HasAnyPriorityDispels(spells.natures_cure) then
	-- 			dispel_tar = friend
	-- 			return true
	-- 		end
	
	--         return false
	-- 	end)
	
	-- 	if dispel_tar == nil then
	-- 		return None
	-- 	end
	
	-- 	return dispel_tar
	-- end)

------------------------------
--- Scorch
------------------------------

spells.scorch:AddCallback("Combust, Execute", function(spell)
	if not IsPlayerSpell(383604) then
		return false
	end

	if not target:GetExists() then
		return false
	end

	if target.hp >= 30 then
		return false
	end

	if target:FindDebuff(auras.imp_scorch):Remains() > 4 then
		return false
	end

	return spell:Cast(target)
end)

spells.scorch:AddCallback("Combust, Heat Shimmer", function(spell)
	if not IsPlayerSpell(457735) then
		return false
	end

	if not target:GetExists() then
		return false
	end

	if player:FindBuff(auras.heat_shimmer):Active() then
		return spell:Cast(target)
	end

	return false
end)

spells.scorch:AddCallback("Combust", function(spell)
	if not target:GetExists() then
		return false
	end

	if spells.phoenix_flames.charges_frac > 0.9 then
		return false
	end

	if spells.fire_blast.charges_frac > 0.9 then
		return false
	end

	return spell:Cast(target)
end)

spells.scorch:AddCallback("Execute, Refresh", function(spell)
	if not IsPlayerSpell(383604) then
		return false
	end

	if not target:GetExists() then
		return false
	end

	if target.hp >= 30 then
		return false
	end

	if target:FindDebuff(auras.imp_scorch):Remains() > 4 then
		return false
	end

	return spell:Cast(target)
end)

spells.scorch:AddCallback("Heat Shimmer, Refresh", function(spell)
	if not IsPlayerSpell(457735) then
		return false
	end
	
	if not target:GetExists() then
		return false
	end

	if not player:FindBuff(auras.heat_shimmer):Active() then
		return false
	end

	if target:FindDebuff(auras.imp_scorch):Remains() > 4 then
		return false
	end

	return spell:Cast(target)
end)

spells.scorch:AddCallback("Execute", function(spell)
	if not target:GetExists() then
		return false
	end

	if target.hp >= 30 then
		return false
	end

	return spell:Cast(target)
end)

spells.scorch:AddCallback("Filler", function(spell)
	if not target:GetExists() then
		return false
	end

	return spell:Cast(target)
end)

------------------------------
--- Shifting Power
------------------------------

spells.shifting_power:AddCallback(function(spell)
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
	if not targets.spellsteal:GetExists() then
		return false
	end

	return spell:Cast(targets.spellsteal)
end)

------------------------------
--- Time Warp
------------------------------

spells.time_warp:AddCallback(function(spell)

end)

addon.mage.data["Fire"].spells = spells
addon.mage.data["Fire"].auras = auras
addon.mage.data["Fire"].targets = targets