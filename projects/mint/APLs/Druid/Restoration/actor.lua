local unlocker,
---@class mint
mint,
addon = ...

--! Tea Locals !--
local RaidEvents   	= mint.RaidEvents
local UnitManager   = mint.UnitManager
local FriendManager = mint.FriendManager
local Events        = mint.EventManager
local Constants     = mint.Constants
local Item 			= mint.Item.New
local Totems 		= mint.TotemManager
local SmartTarget 	= mint.SmartTarget
local target        = UnitManager:Get("target")
local player        = UnitManager:Get("player")
local none          = UnitManager:Get("none")
local focus			= UnitManager:Get("focus")
local Settings      = mint.Settings
local profile       = Settings.profile.druid.restoration

--! Addon Locals !--
local resto 		= addon.druid.resto
local spells 		= addon.druid.data.spells
local auras 		= addon.druid.data.auras
local talents 		= addon.druid.data.talents
local targets 		= addon.druid.data.targets
local helpers		= addon.druid.data.helpers
local use_cds 		= mint.data.toggles.cooldowns
local use_kicks 	= mint.data.toggles.kicks
local use_defs 		= mint.data.toggles.defensives

local health_pot  = Item(211880)
local healthstone = Item(5512)

resto:Sync(function()
	if player:IsChanneling() then return end

	if player:IsInCombat() then
		spells.thunder_focus_tea("tft_with_celestial")
		spells.expel_harm("expel_def")
		spells.fortifying_brew("brew_def")

		if player:GetRealizedHP() < 35 then
			health_pot:Use(player)
		end

		if player:GetRealizedHP() < 40 then
			healthstone:Use(player)
		end

		spells.revival()
		spells.restoral()
		spells.life_cocoon("cocoon danger")
		spells.touch_of_death()

		if focus.exists and focus:IsFriend() and player:GetCastSpellID() == spells.soothing_mist.id then
			spells.renewing_mist("sm_channel_gonna_die")
			spells.vivify("sm_channel_gonna_die")
			if focus:GetRealizedHP() > 80 then
				SpellStopCasting()
			end
		elseif helpers.chiji_cast().exists then
			--[[ChiJiAPL:AddAction("mw_ramp_racials_trinkets", function(self)
				Caffeine.Racials:Cast()
				Caffeine.Trinkets:Use()
			end)]]
			spells.sheiluns_gift("sheilun_chiji_ramp")
			spells.renewing_mist("renewing_mist_ramp")
			spells.mana_tea("mana_tea_chiji_ramp")
			spells.chi_ji("chi_ji_ramp")
			spells.jadefire_stomp("stomp_jadefire_teachings_down")
			spells.jadefire_stomp("stomp_awakened_jadefire_down")
			spells.enveloping_mist("env_mist_at_2_buff")
			spells.blackout_kick("blackout_kick_teachings_ramp")
			spells.rising_sun_kick("rsk_rising_mist")
			spells.tiger_palm("tp_chiji_ramp")
			spells.rushing_wind_kick("rwk_rising_mist")
			spells.spinning_crane_kick("sck_rising_mist")
		elseif helpers.yulon_cast().exists then
			spells.renewing_mist("renewing_mist_tft")
			--[[YulonAPL:AddAction("mw_ramp_racials_trinkets", function(self)
				Caffeine.Racials:Cast()
				Caffeine.Trinkets:Use()
			end)]]
			spells.sheiluns_gift("sheilun_yulon_ramp")
			spells.tiger_palm("tp_yulon_ramp")
			spells.renewing_mist("renewing_mist_ramp")
			spells.mana_tea("mana_tea_yulon_ramp")
			spells.yulon("yulon_ramp")
			spells.soothing_mist("soothing_mist_tom")
			spells.enveloping_mist("env_mist_yulon_ramp")
			spells.rising_sun_kick("rsk_yulon_ramp")
			spells.rushing_wind_kick("rwk_yulon_ramp")
			spells.vivify("viv_ramp")
			spells.blackout_kick("blackout_kick_teachings_ramp")
			spells.spinning_crane_kick("sck_rising_mist")
		else
			spells.soothing_mist("soothing_mist_gonna_die")
			spells.leg_sweep("leg_sweep_auto_interrupt")
			spells.jadefire_stomp("stomp_jadefire_teachings_down")
			spells.jadefire_stomp("stomp_awakened_jadefire_down")
			spells.mana_tea("mana_tea_ox")
			spells.enveloping_mist("env_mist_ox")
			spells.enveloping_mist("env_mist_at_2_buff")
			spells.rising_sun_kick("rsk_rising_mist")
			spells.rushing_wind_kick("rwk_rising_mist")
			spells.blackout_kick("blackout_kick_rising_mist_teachings")
			spells.crackling_jade_lightning("crackling_jade_lightning")
			spells.celestial_conduit()
			spells.renewing_mist("renewing_mist_target_exists")
			spells.mana_tea("mana_tea_condition")
			spells.soothing_mist("soothing_mist_tom")
			spells.enveloping_mist("env_mist_tft")
			spells.sheiluns_gift("sheilun_aoe_heal")
			spells.vivify("instant_or_sm_channel")
			spells.vivify("viv_cleave")
			spells.chi_burst()
			spells.tiger_palm("tiger_palm")
			spells.spinning_crane_kick("sck_rising_mist")
		end
	end
end)