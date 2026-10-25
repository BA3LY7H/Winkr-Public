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
local none          = UnitManager:Get("none")
local focus         = UnitManager:Get("focus")
local Settings      = mint.Settings
local profile       = Settings.profile.monk.mistweaver

local toggles       = mint.data.toggles
local use_cds 		= mint.data.toggles.cooldowns
local use_kicks 	= mint.data.toggles.kicks
local use_defs 		= mint.data.toggles.defensives

local spells = {
	blackout_kick = Spell(100784),
	celestial_conduit = Spell(443028),
	chi_torpedo = Spell(115008),
	chi_burst = Spell(123986, { targeted = false }),
	crackling_jade_lightning = Spell(117952),
	detox = Spell(115450, { dispel = true, beneficial = true }),
	diffuse_magic = Spell(122783, { targeted = false }),
	enveloping_mist = Spell(124682, { beneficial = true, prevent_double = true }),
	expel_harm = Spell(322101, { targeted = false, beneficial = true }),
	fortifying_brew = Spell(115203, { targeted = false }),
	chi_ji = Spell(325197),
	yulon = Spell(322118),
	jadefire_stomp = Spell(388193, { targeted = false }),
	leg_sweep = Spell(119381),
	life_cocoon = Spell(116849, { beneficial = true }),
	mana_tea = Spell(115294, { targeted = false, ignore_channel = true }),
	paralysis = Spell(115078, { cc = true }),
	provoke = Spell(115546),
	reawaken = Spell(212051),
	renewing_mist = Spell(115151),
	restoral = Spell(388615),
	revival = Spell(115310),
	resuscitate = Spell(115178),
	ring_of_peace = Spell(116844),
	rising_sun_kick = Spell(107428, { ignore_channel = true }),
	rushing_wind_kick = Spell(467307, { ignore_channel = true }),
	sheiluns_gift = Spell(399491),
	soothing_mist = Spell(115175, { ignore_channel = true }),
	spear_hand_strike = Spell(116705, { kick = true }),
	spinning_crane_kick = Spell(101546, { ignore_moving = true, targeted = false}),
	thunder_focus_tea = Spell(116680, { targeted = false }),
	tiger_palm = Spell(100780, { ignore_channel = true }),
	tigers_lust = Spell(116841, { beneficial = true }),
	touch_of_death = Spell(322109),
	transcendence = Spell(101643),
	transcendence_transfer = Spell(119996),
	vivify = Spell(116670, { beneficial = true, ignore_channel = true, ignore_moving = true }),
	zen_flight = Spell(125883),
}


local auras = {
	instant_vivify             = Spell(392883),
	renewing_mist              = Spell(119611),
	enveloping_mist            = Spell(124682),
	enveloping_breath          = Spell(325209),
	mana_tea                   = Spell(115867),
	anger                      = Spell(400106),
	fear                       = Spell(400103),
	doubt                      = Spell(400097),
	despair                    = Spell(400100),
	awakened_jadefire          = Spell(389387),
	yulons_blessing            = Spell(389422),
	chi_ji_env_mist            = Spell(343820),
	zen_pulse                  = Spell(446334),
	jadefire_teachings         = Spell(388026),
	teachings_of_the_monastery = Spell(202090),
	strength_of_the_black_ox   = Spell(443112),
	transcendence_ally         = Spell(434767),
	transcendence_set          = Spell(101643),
	jade_empowerment           = Spell(467317),
	mana_tea                   = Spell(115867),
	mana_tea_mana_reduction    = Spell(197908),
	devouring_rift             = Spell(440313),
	soothing_breath			   = Spell(343737)
}

local talents = {
	tear_of_morning          = Spell(387991),
	rising_mist              = Spell(274909),
	peer_into_peace          = Spell(440008),
	ancient_teachings        = Spell(388023),
	zen_pulse                = Spell(446326),
	improved_detox           = Spell(388874),
	shaohaos_lessons         = Spell(400089),
	improved_touch           = Spell(322113),
	secret_infusion          = Spell(388491),
	jadefire_teachings       = Spell(467293),
	awakened_jadefire        = Spell(388779),
	emperors_favor			 = Spell(471761)
}

local targets = {}

local types = {
	["Poison"] = true,
	["Disease"] = true,
	["Magic"] = true,
}

-- Dispel Handling
targets.dispel = UnitManager:CreateSmartUnit("mw_dispel", function()
	local dispel_tar = nil

	if not toggles.dispels then
		return none
	end

	FriendManager:Loop(function(friend)
		if friend:IsDead() then return false end
		if not spells.detox:IsInRange(friend) then return false end
		if not friend:HasDebuffType(types, true) then return false end
		-- if not player:HasLos(friend) then return false end

		dispel_tar = friend

		return true
	end)


	if dispel_tar == nil then
		return none
	end

	return dispel_tar
end)

-- Rebuke
targets.kick = UnitManager:CreateSmartUnit("mw_kick", function()
	local closest = nil
	local closest_dist = math.huge

	if not toggles.kicks then
		return none
	end

	ObjectManager.combat:loop(function(enemy)
		if enemy.dead then return false end
		if not enemy:IsCastingOrChanneling() then return false end
		if not enemy:IsKickable() then return false end
		if not spells.spear_hand_strike:IsInRange(enemy) then return false end
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

local helpers = {}

local valid_chi_ji_tft = {
	[spells.rising_sun_kick.id] = true,
	[spells.enveloping_mist.id] = true,
	[spells.renewing_mist.id] = true
}

local valid_yulon_tft = {
	[spells.renewing_mist.id] = true,
	[spells.enveloping_mist.id] = true,
	[spells.rushing_wind_kick.id] = true,
	[spells.rising_sun_kick.id] = true
}

local function valid_tft_spell(spell)
	if player:FindBuff(spells.thunder_focus_tea):Inactive() then
		return true
	end

	if spells.chi_ji.known then
		if valid_chi_ji_tft[spell.id] then
			return true
		end
	end

	if spells.yulon.known then
		if valid_yulon_tft[spell.id] then
			return true
		end
	end

	return false
end

local function rwk_or_rsk()
	if IsPlayerSpell(spells.rushing_wind_kick.id) then
		return spells.rushing_wind_kick
	else
		return spells.rising_sun_kick
	end
end

local function yulon_or_chiji()
	if spells.chi_ji.known then
		return spells.chi_ji
	end

	if spells.yulon.known then
		return spells.yulon
	end
end

local function teachings_stacks()
	local stacks = player:GetEnemies(8)
	if stacks > 4 then
		stacks = 4
	end
	return stacks
end

local function danger_percent()
	return profile.danger_pct
end

local function aoe_heal_percent()
	return profile.aoe_heal_pct
end

function helpers.yulon_cast()
	return spells.yulon:IsKnown() and Totems:IsActive(spells.yulon.id) and player or none
end

function helpers.chiji_cast()
	return spells.chi_ji:IsKnown() and Totems:IsActive(spells.chi_ji.id) and player or none
end

local function yulon_or_chiji_cast()
	if spells.chi_ji.known then
		return helpers.chiji_cast()
	end

	if spells.yulon.known then
		return helpers.yulon_cast()
	end
end

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

spells.spear_hand_strike:AddCallback("Smart Kick", function(spell)
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

spells.detox:AddCallback("Smart Dispel", function(spell)
	if not targets.dispel:GetExists() or targets.dispel:IsDead() then
		return false
	end

	mint.console.log("Attempted to dispel target:", targets.dispel.name)

	return spell:Cast(targets.dispel)
end)

spells.thunder_focus_tea:AddCallback("tft_with_celestial", function(self)
	if IsInRaid() and yulon_or_chiji().known then
		if yulon_or_chiji().cd > 30 then
			return self:Cast(none)
		end
	end

	if player:FindBuff(spells.thunder_focus_tea):Inactive() then
		return self:Cast(player)
	end
end)

spells.fortifying_brew:AddCallback("brew_def", function(self)
	-- GetPercentValue('mw_fortifying_brew_hp')
	if player:GetRealizedHP() <= 50 then
		self:Cast(none)
	end
end)

spells.expel_harm:AddCallback("expel_def", function(self)
	if valid_tft_spell(self) and
			player:GetRealizedHP() <= 80 then
		return self:Cast(none)
	end
end)

spells.jadefire_stomp:AddCallback("stomp_jadefire_teachings_down", function(self)
	if target.exists and player:InMelee(target) and talents.jadefire_teachings.known and
			(player:FindBuff(auras.jadefire_teachings):Inactive() or
					player:FindBuff(auras.jadefire_teachings):Remains() < 5) then
		return self:Cast(none)
	end
end)
spells.jadefire_stomp:AddCallback("stomp_awakened_jadefire_down", function(self)
	if target.exists and player:InMelee(target) and talents.awakened_jadefire.known and
			player:FindBuff(auras.awakened_jadefire):Inactive() then
		return self:Cast(none)
	end
end)

spells.life_cocoon:AddCallback("cocoon danger", function(self)
	if not addon.monk.settings["Mistweaver"].use_cocoon then return end
	local danger_target = mint.FriendManager:GetLowest(danger_percent()) or none
	if danger_target:GetExists() and danger_target.alive then
		return self:Cast(danger_target)
	end
end)

spells.chi_burst:AddCallback(function(self)
	if not player:IsMoving() and
			player:GetEnemies(40) == player:GetEnemies(8) and target:IsEnemy() and player:IsFacing(target) then
		return self:Cast(none)
	end
end)

spells.mana_tea:AddCallback('mana_tea_condition', function(self)
	if not IsInRaid() then return false end -- just use manually in between packs in keys
	if talents.rising_mist.known then
		if player:GetPP() < 90 and player:FindBuff(auras.mana_tea):Count() > 10 then
			return self:Cast(none)
		end
	else
		if player:FindBuff(auras.mana_tea):Count() > 2 then
			return self:Cast(none)
		end
	end
end)
spells.mana_tea:AddCallback('mana_tea_ox', function(self)
	if not IsInRaid() then return false end
	if player:FindBuff(auras.mana_tea):Count() > 2 and player:FindBuff(auras.strength_of_the_black_ox):Active() then
		return self:Cast(none)
	end
end)
spells.mana_tea:AddCallback("mana_tea_yulon_ramp", function(self)
	if not IsInRaid() then return false end
	if not helpers.yulon_cast().exists and player:FindBuff(auras.mana_tea):Count() > 3 and
			player:FindBuff(auras.mana_tea_mana_reduction):Inactive() then
		return self:Cast(none)
	end
end)
spells.mana_tea:AddCallback("mana_tea_chiji_ramp", function(self)
	if not IsInRaid() then return false end
	if not helpers.chiji_cast().exists and player:FindBuff(auras.mana_tea):Count() > 3 and
			player:FindBuff(auras.teachings_of_the_monastery):Count() > teachings_stacks() and
			player:FindBuff(auras.mana_tea_mana_reduction):Inactive() then
		return self:Cast(none)
	end
end)

spells.soothing_mist:AddCallback("soothing_mist_tom", function(self)
	local lowest_target = FriendManager:GetLowest(99) or none
	if not player:IsCastingSpell(spells.soothing_mist.id) and
			lowest_target.exists and lowest_target.alive and
			talents.tear_of_morning:IsKnown() or talents.peer_into_peace:IsKnown() then
		return self:Cast(lowest_target)
	end
end)

spells.soothing_mist:AddCallback("soothing_mist_gonna_die", function(self)
	if not player:IsCastingSpell(spells.soothing_mist.id) and
			focus.exists and focus.alive and focus:GetRealizedHP() < 30 then
		return self:Cast(focus)
	end
end)

local function can_vivify()
	local lowest_target = none
	if IsInRaid() and spells.chi_ji.known then
		if player:IsCastingSpell(spells.soothing_mist.id) then
			return true
		end
		local danger_target = mint.FriendManager:GetLowest(danger_percent()) or none
		if danger_target.exists then
			lowest_target = FriendManager:GetLowest(danger_percent()) or none
		elseif player:FindBuff(auras.zen_pulse):Active() and
				player:FindBuff(auras.instant_vivify):Active() and
				FriendManager:GetCountBelow(aoe_heal_percent()) then
			lowest_target = FriendManager:GetLowest(aoe_heal_percent()) or none
		else
			lowest_target = none
		end
	else
		lowest_target = FriendManager:GetLowest(aoe_heal_percent()) or none
	end
	return lowest_target.exists and
			valid_tft_spell(spells.vivify)
end
spells.vivify:AddCallback("instant_or_sm_channel", function(self)
	if can_vivify() and (player:FindBuff(auras.instant_vivify):Active() or
			player:IsCastingSpell(spells.soothing_mist.id) or player:FindBuff(auras.zen_pulse):Active()) then
		self:Cast(FriendManager:GetLowest())
	end
end)
spells.vivify:AddCallback("sm_channel_gonna_die", function(self)
	if player:IsCastingSpell(spells.soothing_mist.id) and focus.alive and focus:GetRealizedHP() < 30 then
		self:Cast(focus)
	end
end)
spells.vivify:AddCallback("viv_cleave", function(self)
	if can_vivify() and FriendManager:GetCountBelow(aoe_heal_percent()) >= 5 then
		self:Cast(FriendManager:GetLowest())
	end
end)
spells.vivify:AddCallback("viv_ramp", function(self)
	if can_vivify() and talents.tear_of_morning:IsKnown() and player:IsCastingSpell(spells.soothing_mist.id) and
			FriendManager:GetNumFriendsWithBuff(auras.enveloping_mist) > 6 and
			player:FindBuff(auras.zen_pulse):Active() then
		self:Cast(FriendManager:GetLowest())
	end
end)
spells.vivify:AddCallback("viv_ooc", function(self)
	local lowest_target = FriendManager:GetLowest(99)
	if can_vivify() and
			player:FindBuff(auras.instant_vivify):Active() then
		self:Cast(lowest_target)
	end
end)

local function can_renewing_mist()
	local lowest_target = FriendManager:GetLowest(99) or none
	return lowest_target.exists and lowest_target:FindBuff(auras.renewing_mist, true):Inactive() and
			FriendManager:GetNumFriendsWithBuff(auras.renewing_mist) < 6
end

spells.renewing_mist:AddCallback('renewing_mist_target_exists', function(self)
	if spells.chi_ji.known then
		local danger_target = FriendManager:GetLowest(danger_percent()) or none
		if danger_target.exists and danger_target:FindBuff(auras.renewing_mist, true):Inactive() and
				valid_tft_spell(self) then
			return self:Cast(danger_target)
		end
	elseif spells.yulon.known then
		local lowest_target = FriendManager:GetLowest(false, function(friend)
			local buff = friend:FindBuff(auras.renewing_mist)
			if buff:Active() and buff:Remains() > 6 then return false end

			return true
		end) or none
		if lowest_target:GetExists() and valid_tft_spell(self) then
			return self:Cast(lowest_target)
		end
	end
end)
spells.renewing_mist:AddCallback("renewing_mist_ramp", function(self)
	local lowest_target = FriendManager:GetLowest(99) or none
	if lowest_target.exists and can_renewing_mist() and valid_tft_spell(self) then
		return self:Cast(lowest_target)
	end
end)
spells.renewing_mist:AddCallback("renewing_mist_ooc", function(self)
	local lowest_target = FriendManager:GetLowest(99) or none
	if lowest_target.exists and self:GetCharges() > 1 and valid_tft_spell(self) then
		return self:Cast(lowest_target)
	end
end)
spells.renewing_mist:AddCallback("renewing_mist_tft", function(self)
	local lowest_target = FriendManager:GetLowest(99) or none
	if lowest_target.exists and player:FindBuff(spells.thunder_focus_tea):Active() then
		return self:Cast(lowest_target)
	end
end)

spells.rising_sun_kick:AddCallback("rsk_rising_mist", function(self)
	if player:InMelee(target) and valid_tft_spell(self) and not IsPlayerSpell(spells.rushing_wind_kick.id) and talents.rising_mist:IsKnown() then
		return self:Cast(target)
	end
end)
spells.rising_sun_kick:AddCallback("rsk_yulon_ramp", function(self)
	if player:InMelee(target) and valid_tft_spell(self) and FriendManager:GetNumFriendsWithBuff(auras.enveloping_mist) > 3 then
		return self:Cast(target)
	end
end)

spells.rushing_wind_kick:AddCallback("rwk_rising_mist", function(self)
	if valid_tft_spell(self) and IsPlayerSpell(spells.rushing_wind_kick.id) and player:InMelee(target) and talents.rising_mist:IsKnown() then
		return self:Cast(target)
	end
end)
spells.rushing_wind_kick:AddCallback("rwk_yulon_ramp", function(self)
	if player:InMelee(target) and valid_tft_spell(self) and IsPlayerSpell(spells.rushing_wind_kick.id) and
			FriendManager:GetNumFriendsWithBuff(auras.enveloping_mist) > 3 then
		return self:Cast(target)
	end
end)


spells.tiger_palm:AddCallback("tiger_palm", function(self)
	if rwk_or_rsk().on_cd and player:FindBuff(auras.teachings_of_the_monastery):Count() < 4 then
		return self:Cast(target)
	end
end)
spells.tiger_palm:AddCallback("tp_yulon_ramp", function(self)
	if talents.rising_mist:IsKnown() and player:FindBuff(auras.teachings_of_the_monastery):Count() < 4
			and not helpers.yulon_cast().exists then
		return self:Cast(target)
	end
end)
spells.tiger_palm:AddCallback("tp_chiji_ramp", function(self)
	if talents.rising_mist:IsKnown() and player:FindBuff(auras.teachings_of_the_monastery):Count() < 4 then
		return self:Cast(target)
	end
end)

spells.spinning_crane_kick:AddCallback("sck_rising_mist", function(self)
	if player:GetEnemies(8) > 5 and rwk_or_rsk().on_cd and spells.blackout_kick.on_cd and talents.rising_mist:IsKnown() then
		return self:Cast(target)
	end
end)


spells.blackout_kick:AddCallback("blackout_kick_rising_mist_teachings", function(self)
	if player:InMelee(target) and rwk_or_rsk().on_cd and talents.rising_mist:IsKnown() and
			player:FindBuff(auras.teachings_of_the_monastery):Count() >= teachings_stacks() then
		return self:Cast(target)
	end
end)
spells.blackout_kick:AddCallback("blackout_kick_teachings", function(self)
	if player:InMelee(target) and rwk_or_rsk().on_cd and
			player:FindBuff(auras.teachings_of_the_monastery):Count() >= teachings_stacks() then
		return self:Cast(target)
	end
end)
spells.blackout_kick:AddCallback("blackout_kick_teachings_ramp", function(self)
	if player:InMelee(target) and rwk_or_rsk().on_cd and
			player:FindBuff(auras.teachings_of_the_monastery):Count() >= teachings_stacks() and
			yulon_or_chiji_cast().exists then
		return self:Cast(target)
	end
end)

spells.touch_of_death:AddCallback(function(self)
	if not addon.monk.settings["Mistweaver"].use_tod then return end
	return self:Cast(target)
end)

spells.sheiluns_gift:AddCallback("sheilun_aoe_heal", function(self)
	if talents.emperors_favor.known then
		return false
	end
	if self.count < 3 then
		return false
	end
	if yulon_or_chiji_cast().exists then
		return false
	end
	if IsInRaid() and talents.shaohaos_lessons:IsKnown() then
		return false
	else
		local lowest_target = FriendManager:GetLowest(90) or none
		if lowest_target:GetExists() and FriendManager:GetCountBelow(aoe_heal_percent()) >= 3 and self.count > 5 then
			return self:Cast(lowest_target)
		end
	end
end)
spells.sheiluns_gift:AddCallback("sheilun_st_heal", function(self)
	if not talents.emperors_favor.known then
		return false
	end
	if self.count < 3 then
		return false
	end
	if yulon_or_chiji_cast().exists then
		return false
	end
	local lowest_target = FriendManager:GetLowest(90) or none
	if lowest_target:GetExists() and self.count > 3 then
		return self:Cast(lowest_target)
	end
end)
spells.sheiluns_gift:AddCallback("sheilun_chiji_ramp", function(self)
	if yulon_or_chiji_cast().exists then
		return false
	end
	if talents.shaohaos_lessons:IsKnown() and
			player:FindBuff(auras.anger):Inactive() and player:FindBuff(auras.fear):Inactive() and
			player:FindBuff(auras.doubt):Inactive() and player:FindBuff(auras.despair):Inactive() then
		return self:Cast(FriendManager:GetLowest())
	end
end)
spells.sheiluns_gift:AddCallback("sheilun_yulon_ramp", function(self)
	if yulon_or_chiji_cast().exists then
		return false
	end
	return talents.shaohaos_lessons:IsKnown() and player:FindBuff(auras.anger):Inactive() and
			player:FindBuff(auras.fear):Inactive() and player:FindBuff(auras.doubt):Inactive() and
			player:FindBuff(auras.despair):Inactive()
end)

spells.yulon:AddCallback("yulon_ramp", function(self)
	if not helpers.yulon_cast().exists then
		return self:Cast(none)
	end
end)

spells.chi_ji:AddCallback("chi_ji_ramp", function(self)
	if not helpers.chiji_cast().exists and  player:FindBuff(auras.teachings_of_the_monastery):Count() > teachings_stacks() then
		return self:Cast(none)
	end
end)

spells.renewing_mist:AddCallback("sm_channel_gonna_die", function(self)
	if player:IsCastingSpell(spells.soothing_mist.id) and focus.alive and focus:GetRealizedHP() < 30 and
			focus:FindBuff(auras.renewing_mist, true):Inactive() then
		return self:Cast(focus)
	end
end)
spells.enveloping_mist:AddCallback("env_mist_ox", function(self)
	if player:FindBuff(auras.strength_of_the_black_ox):Inactive() then
		return false
	end

	local lowest_target = FriendManager:GetLowest(false, function(unit)
		if unit:FindBuff(auras.enveloping_mist, true):Active() then
			return false
		end
		return true
	end) or player

	if valid_tft_spell(self) and lowest_target.exists then
		return self:Cast(lowest_target)
	end
end)
spells.enveloping_mist:AddCallback("env_mist_yulon_ramp", function(self)
	if not valid_tft_spell(self) then
		return false
	end
	local lowest_target = FriendManager:GetLowest(false, function(unit)
		if unit:FindBuff(auras.enveloping_breath):Active() then
			return false
		end
		return true
	end) or none
	if lowest_target.exists and
			FriendManager:GetNumFriendsWithBuff(auras.enveloping_breath) < math.floor((FriendManager:GetCount() / 1.3) + 0.5) then
		return self:Cast(lowest_target)
	end
end)
spells.enveloping_mist:AddCallback("env_mist_at_2_buff", function(self)
	local lowest_target = FriendManager:GetLowest(99, function(unit)
		if unit:FindBuff(auras.enveloping_mist, true):Active() then
			return false
		end
		if unit:FindBuff(auras.enveloping_breath, true):Active() then
			return false
		end
		return true
	end) or none
	if valid_tft_spell(self) and lowest_target.exists and player:FindBuff(auras.chi_ji_env_mist):Count() > 1 then
		return self:Cast(lowest_target)
	end
end)
spells.enveloping_mist:AddCallback("env_mist_tft", function(self)
	local lowest_target = FriendManager:GetLowest(99, function(unit)
		if unit:FindBuff(auras.enveloping_mist, true):Active() then
			return false
		end
		return true
	end) or none
	if valid_tft_spell(self) and lowest_target.exists and player:FindBuff(spells.thunder_focus_tea):Active() then
		return self:Cast(lowest_target)
	end
end)

spells.revival:AddCallback(function(self)
	--[[if GetPercentValue('mw_revival_restoral_percentage') == 0 then
		return false
	end]]
	-- GetPercentValue('mw_revival_restoral_percentage')
	-- GetPercentValue('mw_revival_restoral_units')
	if use_cds and
			FriendManager:GetCountBelow(aoe_heal_percent()) >= 5 then
		return self:Cast(none)
	end
end)

spells.restoral:AddCallback(function(self)
	--[[if GetPercentValue('mw_revival_restoral_percentage') == 0 then
		return false
	end]]
	-- GetPercentValue('mw_revival_restoral_percentage')
	-- GetPercentValue('mw_revival_restoral_units')
	if use_cds and
			FriendManager:GetCountBelow(aoe_heal_percent()) >= 5 then
		return self:Cast(none)
	end
end)

spells.celestial_conduit:AddCallback(function(self)
	-- GetBooleanValue('monk_mw_celestial_conduit')
	if use_cds and profile.celestial_conduit and
			(FriendManager:GetCountBelow(aoe_heal_percent()) >= 5 or
					player:GetEnemies(20) >= 5) then
		return self:Cast(none)
	end
end)

spells.leg_sweep:AddCallback("leg_sweep_auto_interrupt", function(self)
	-- NumEnemiesCastingWithinDistance(player, 8) > 1
	if profile.auto_leg_sweep then
		return self:Cast(none)
	end
end)

spells.crackling_jade_lightning:AddCallback("crackling_jade_lightning", function(self)
	if talents.jadefire_teachings.known and
			player:FindBuff(auras.jadefire_teachings):Inactive() then
		return false
	end
	if profile.auto_cjl and player:FindBuff(auras.jade_empowerment):Active() and
			self:TimeSinceLastCast() > 5 then
		return self:Cast(target)
	end
end)

addon.monk.data.helpers = helpers
addon.monk.data.spells 	= spells
addon.monk.data.auras 	= auras
addon.monk.data.talents = talents
addon.monk.data.targets = targets