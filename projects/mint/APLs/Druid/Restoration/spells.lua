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
local profile       = Settings.profile.druid.resto

local use_cds 		= mint.data.toggles.cooldowns
local use_kicks 	= mint.data.toggles.kicks
local use_defs 		= mint.data.toggles.defensives

local spells = {
	adaptive_swarm = Spell(391888),
	barkskin = Spell(22812),
	bear_form = Spell(5487),
	berserk = Spell(106951),
	bristling_fur = Spell(155835),
	brutal_slash = Spell(202028),
	cat_form = Spell(768),
	celestial_alignment = Spell(194223),
	convoke_the_spirits = Spell(391528),
	efflorescence = Spell(145205),
	entangling_roots = Spell(339),
	feral_frenzy = Spell(274837),
	ferocious_bite = Spell(22568),
	flourish = Spell(197721),
	force_of_nature = Spell(205636),
	frenzied_regeneration = Spell(22842),
	fury_of_elune = Spell(202770),
	grove_guardians = Spell(102693),
	growl = Spell(6795),
	heart_of_the_wild = Spell(319454),
	incarnation_avatar_of_ashamane = Spell(102543),
	incarnation_chosen_of_elune = Spell(102560),
	incarnation_guardian_of_ursoc = Spell(102558),
	innervate = Spell(29166),
	ironbark = Spell(102342),
	lifebloom = Spell(33763),
	lunar_beam = Spell(204066),
	mangle = Spell(33917),
	mark_of_the_wild = Spell(1126),
	maul = Spell(6807),
	moonfire = Spell(8921),
	natures_cure = Spell(88423),
	natures_swiftness = Spell(132158),
	natures_vigil = Spell(124974),
	new_moon = Spell(274281),
	primal_wrath = Spell(285381),
	prowl = Spell(5215),
	pulverize = Spell(80313),
	rage_of_the_sleeper = Spell(200851),
	raze = Spell(400254),
	rebirth = Spell(20484),
	regrowth = Spell(8936),
	rejuvenation = Spell(774),
	renewal = Spell(108238),
	revitalize = Spell(212040),
	revive = Spell(50769),
	shred = Spell(5221),
	skull_bash = Spell(106839),
	solar_beam = Spell(78675),
	soothe = Spell(2908),
	stampeding_roar = Spell(106898),
	starfall = Spell(191034),
	starfire = Spell(197628),
	starsurge = Spell(197626),
	stellar_flare = Spell(202347),
	survival_instincts = Spell(61336),
	swiftmend = Spell(18562),
	swipe = Spell(213764),
	symbiotic_relationship = Spell(474750),
	teleport_moonglade = Spell(18960),
	tiger_dash = Spell(252216),
	tigers_fury = Spell(5217),
	tranquility = Spell(740),
	travel_form = Spell(783),
	ursols_vortex = Spell(102793),
	warrior_of_elune = Spell(202425),
	wild_growth = Spell(48438),
	wild_mushroom = Spell(88747),
	wrath = Spell(5176),
}


local auras = {

}

local talents = {

}

local targets = {}
local helpers = {}

--[[local valid_chi_ji_tft = {
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
	if not profile.use_cocoon then return end
	local danger_target = mint.FriendManager:GetLowest(danger_percent()) or none
	if danger_target.exists and danger_target.alive then
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
	if player:FindBuff(auras.mana_tea):Count() > 2 and player:FindBuff(auras.strength_of_the_black_ox):Active() then
		return self:Cast(none)
	end
end)
spells.mana_tea:AddCallback("mana_tea_yulon_ramp", function(self)
	if not helpers.yulon_cast().exists and player:FindBuff(auras.mana_tea):Count() > 3 and
			player:FindBuff(auras.mana_tea_mana_reduction):Inactive() then
		return self:Cast(none)
	end
end)
spells.mana_tea:AddCallback("mana_tea_chiji_ramp", function(self)
	if not helpers.chiji_cast().exists and player:FindBuff(auras.mana_tea):Count() > 3 and
			player:FindBuff(auras.teachings_of_the_monastery):Count() > teachings_stacks() and
			player:FindBuff(auras.mana_tea_mana_reduction):Inactive() then
		self:Cast(none)
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
	end
	return lowest_target.exists and
			valid_tft_spell(spells.vivify)
end
spells.vivify:AddCallback("instant_or_sm_channel", function(self)
	if can_vivify() and (player:FindBuff(auras.instant_vivify):Active() or
			player:IsCastingSpell(spells.soothing_mist.id)) then
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
	if IsInRaid() and spells.chi_ji.known then
		local danger_target = FriendManager:GetLowest(danger_percent()) or none
		if danger_target.exists and danger_target:FindBuff(auras.renewing_mist, true):Inactive() and
				valid_tft_spell(self) then
			return self:Cast(danger_target)
		end
	else
		local lowest_target = FriendManager:GetLowest(99) or none
		if can_renewing_mist() and valid_tft_spell(self) then
			return self:Cast(lowest_target)
		end
	end
end)
spells.renewing_mist:AddCallback("renewing_mist_ramp", function(self)
	local lowest_target = FriendManager:GetLowest(99) or none
	if lowest_target.exists and can_renewing_mist() and self:GetCharges() >= 1 and valid_tft_spell(self) then
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
	if self.count < 3 then
		return false
	end
	if yulon_or_chiji_cast().exists then
		return false
	end
	if IsInRaid() and talents.shaohaos_lessons:IsKnown() then
		return false
	else
		if FriendManager:GetCountBelow(aoe_heal_percent()) >= 5 or
				(yulon_or_chiji().cd > 32 or
						self.count > 8) then
			return self:Cast(FriendManager:GetLowest())
		end
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
	local lowest_target = FriendManager:GetLowest(99, function(unit)
		if unit:FindBuff(auras.enveloping_mist, true):Active() then
			return false
		end
		return true
	end) or player
	if valid_tft_spell(self) and lowest_target.exists and player:FindBuff(auras.strength_of_the_black_ox):Active() then
		return self:Cast(lowest_target)
	end
end)
spells.enveloping_mist:AddCallback("env_mist_yulon_ramp", function(self)
	if not valid_tft_spell(self) then
		return false
	end
	local lowest_target = FriendManager:GetLowest(99, function(unit)
		if unit:FindBuff(auras.enveloping_mist, true):Active() then
			return false
		end
		return true
	end) or none
	if spells.soothing_mist:IsKnown() then
		if lowest_target.exists and
				FriendManager:GetNumFriendsWithBuff(auras.enveloping_breath) < FriendManager:GetCount() / 2 and
				player:IsCastingSpell(spells.soothing_mist.id) then
			return self:Cast(lowest_target)
		end
	else
		if lowest_target.exists and
				FriendManager:GetNumFriendsWithBuff(auras.enveloping_breath) < FriendManager:GetCount() / 2 then
			return self:Cast(lowest_target)
		end
	end
end)
spells.enveloping_mist:AddCallback("env_mist_at_2_buff", function(self)
	local lowest_target = FriendManager:GetLowest(99, function(unit)
		if unit:FindBuff(auras.enveloping_mist, true):Active() then
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
	]]--[[if GetPercentValue('mw_revival_restoral_percentage') == 0 then
		return false
	end]]--[[
	-- GetPercentValue('mw_revival_restoral_percentage')
	-- GetPercentValue('mw_revival_restoral_units')
	if use_cds and
			FriendManager:GetCountBelow(aoe_heal_percent()) >= 5 then
		return self:Cast(none)
	end
end)

spells.restoral:AddCallback(function(self)
	]]--[[if GetPercentValue('mw_revival_restoral_percentage') == 0 then
		return false
	end]]--[[
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
			self:GetTimeSinceLastCastAttempt() > 5 then
		return self:Cast(target)
	end
end)]]

addon.druid.data["Restoration"].helpers = helpers
addon.druid.data["Restoration"].spells  = spells
addon.druid.data["Restoration"].auras 	 = auras
addon.druid.data["Restoration"].talents = talents
addon.druid.data["Restoration"].targets = targets