local unlocker,
---@class mint
mint,
addon = ...

--! Tea Locals !--
local RaidEvents   	= mint.RaidEvents
local UnitManager   = mint.UnitManager
local Events        = mint.EventManager
local Constants     = mint.Constants
local Totems 		= mint.TotemManager
local SmartTarget 	= mint.SmartTarget
local Queue 		= mint.Queue
local Dispel 		= mint.Dispel
local target        = UnitManager:Get("target")
local player        = UnitManager:Get("player")
local none          = UnitManager:Get("none")
local bin 			= mint.bin

--! Addon Locals !--
local fire 			= addon.mage.fire
local spells 		= addon.mage.data.spells
local auras 		= addon.mage.data.auras
local items 		= addon.mage.data.items
local targets 		= addon.mage.data.targets
local vars 			= addon.mage.data.vars
local seqs 			= addon.mage.data.sequences
local in_flight 	= addon.mage.data.in_flight


-- https://github.com/simulationcraft/simc/wiki/Action-List-Conditional-Expressions
-- https://github.com/simulationcraft/simc/wiki/ActionLists
-- notes
-- cooldown_react is just not on cooldown
-- buff.name.react is just if the buff exists with human reaction time
-- action.name.executing evaluates to 1 if the action is currently being cast or channeled, 0 otherwise

--[[
	Hekili uses this:

	if k == "action_cooldown" then return ability and ability.cooldown or 0
            elseif k == "cast_delay" then return 0
            elseif k == "cast_regen" then
                local resType = class.primaryResource
                local amount, resource

                if ability then
                    amount, resource = ability.spend

                    if not resource and ability.spendType then
                        resource = ability.spendType
                    end
                end

                resType = resource or resType

                local regen = t[ resType ].regen
                if regen == 0.001 then regen = 0 end

                if not amount then return t.gcd.execute * regen end
                return ( max( t.gcd.execute, ability.cast or 0 ) * regen ) - ( ability.spend or 0 )

            elseif k == "cast_time" then return ability and ability.cast or 0
            elseif k == "charges" then return cooldown.charges
            elseif k == "charges_fractional" then return cooldown.charges_fractional
            elseif k == "charges_max" or k == "max_charges" then return ability and ability.charges or 1
            elseif k == "cooldown_duration" then return cooldown.duration
            elseif k == "cooldown_react" or k == "cooldown_up" then return cooldown.remains == 0
            elseif k == "cooldown_remains" then return cooldown.remains
            elseif k == "cost" then
                if not ability then return 0 end

                local c = ability.cost
                if c then return c end

                c = ability.spend
                if c and c > 0 and c < 1 then
                    c = c * t[ ability.spendType or class.primaryResource ].modmax
                end
                return c or 0

            elseif k == "crit_pct_current" or k == "crit_percent_current" then return ability and ability.critical or t.stat.crit
            elseif k == "execute_remains" then
                -- TODO:  Check out if this is functioning as expected.
                -- Should buff.casting already suffice for a cast?  A queued cast should already trigger a casting buff.
                return ( t:IsCasting( action ) and max( t:QueuedCastRemains( action ), t.gcd.remains ) ) or ( t.prev[1][ action ] and t.gcd.remains ) or 0

            elseif k == "execute_time" then return max( t.gcd.execute, ability and ability.cast or 0 )
            elseif k == "executing" then return t:IsCasting( action ) or ( t.prev[ 1 ][ action ] and t.gcd.remains > 0 )
            elseif k == "full_recharge_time" or k == "time_to_max_charges" then return cooldown.full_recharge_time
            elseif k == "hardcast" then return false -- will set to true if/when a spell is hardcast.
            elseif k == "in_flight" or k == "in_flight_to_target" then return model and model.in_flight or false
            elseif k == "in_flight_remains" then return model and model.in_flight_remains or 0
            elseif k == "in_range" then return model.in_range
            elseif k == "recharge" then return cooldown.recharge
            elseif k == "recharge_time" then return cooldown.recharge_time
            elseif k == "travel_time" then
                local f, v = ability.flightTime or 0, ability.velocity or 0
                if f > 0 then return f end
                if v == 0 then return 0 end
                return t.target.maxR / v

            end
]]

local function precombat()
	-- # Executed before combat begins. Accepts non-harmful actions only.
	-- arcane_intellect
		-- This should be cast if a pull timer starts and someone in range
		-- does not have arcane intellect
		-- or if a player joins the raid and does not have arcane intellect
		-- ensure random delay between 6 and 12 before casting.
	-- mirror_image
		-- This should be run at 5 on pull timer
	-- frostfire_bolt,if=talent.frostfire_bolt
		-- This should be run at 2? on pull timer
	-- pyroblast
		-- This should be run at 3 on pull timer
end

local function cds()
	-- # Opener
	-- phoenix_flames,if=time=0&!talent.firestarter
	spells.phoenix_flames("Opener")

	-- # Items, Racials and Externals
	-- potion,if=!talent.sun_kings_blessing&cooldown.combustion.remains<=variable.combustion_precast_time|buff.combustion.remains>7|fight_remains<35
	items.tempered_potion()

	-- use_item,name=neural_synapse_enhancer,if=!talent.sun_kings_blessing&cooldown.combustion.remains<=variable.combustion_precast_time|buff.combustion.remains>7|fight_remains<20
	-- use_item,effect_name=gladiators_badge,if=!talent.sun_kings_blessing&cooldown.combustion.remains<=variable.combustion_precast_time|buff.combustion.remains>7|fight_remains<20
	-- use_item,name=flarendos_pilot_light,if=!talent.sun_kings_blessing&cooldown.combustion.remains<=variable.combustion_precast_time|buff.combustion.remains>7|fight_remains<20
	-- use_item,name=house_of_cards,if=!talent.sun_kings_blessing&cooldown.combustion.remains<=variable.combustion_precast_time|buff.combustion.remains>7|fight_remains<20
	-- use_item,name=signet_of_the_priory,if=!talent.sun_kings_blessing&cooldown.combustion.remains<=variable.combustion_precast_time|buff.combustion.remains>7|fight_remains<20
	items.signet_of_the_priory()

	-- use_item,name=funhouse_lens,if=!talent.sun_kings_blessing&cooldown.combustion.remains<=variable.combustion_precast_time|buff.combustion.remains>7|fight_remains<20
	-- use_item,name=soulletting_ruby,if=!talent.sun_kings_blessing&cooldown.combustion.remains<=variable.combustion_precast_time|buff.combustion.remains>7|fight_remains<20
	-- use_item,name=quickwick_candlestick,if=!talent.sun_kings_blessing&cooldown.combustion.remains<=variable.combustion_precast_time|buff.combustion.remains>7|fight_remains<20
	-- use_item,name=hyperthread_wristwraps,if=hyperthread_wristwraps.fire_blast>=2&buff.combustion.remains&action.fire_blast.charges=0
	items.hyperthread_wristwraps()
	
	-- use_items
	-- blood_fury,if=!talent.sun_kings_blessing&cooldown.combustion.remains<=variable.combustion_precast_time|buff.combustion.remains>7|fight_remains<20
	-- berserking,if=buff.combustion.remains>7|fight_remains<20
	-- fireblood,if=buff.combustion.remains>7|fight_remains<10
	-- ancestral_call,if=!talent.sun_kings_blessing&cooldown.combustion.remains<=variable.combustion_precast_time|buff.combustion.remains>7|fight_remains<20
	-- invoke_external_buff,name=power_infusion,if=buff.power_infusion.down&(cooldown.combustion.remains<=variable.combustion_precast_time|buff.combustion.remains>7|fight_remains<20)
	-- invoke_external_buff,name=blessing_of_summer,if=buff.blessing_of_summer.down
end

local function sf_combustion()
	-- combustion,use_off_gcd=1,use_while_casting=1,if=buff.combustion.down&(action.fireball.executing&action.fireball.execute_remains<variable.cast_remains_time|action.scorch.executing&action.scorch.execute_remains<variable.cast_remains_time)
	spells.combustion("Combustion: Pre-cast")

	-- scorch,if=buff.combustion.down
	spells.scorch("Combustion: Opener")

	-- fire_blast,use_off_gcd=1,use_while_casting=1,if=cooldown_react&gcd.remains<gcd.max&buff.combustion.up&!buff.hot_streak.react&hot_streak_spells_in_flight+buff.heating_up.react*(gcd.remains>0)<2
	spells.fire_blast("Combustion: Default")

	-- flamestrike,if=buff.hyperthermia.react&active_enemies>=variable.sf_combustion_flamestrike
	spells.flamestrike("Combustion: Hyperthermia")

	-- flamestrike,if=buff.hot_streak.react&active_enemies>=variable.sf_combustion_flamestrike
	spells.flamestrike("Combustion: Hot Streak")

	-- flamestrike,if=prev_gcd.1.scorch&buff.heating_up.react&active_enemies>=variable.sf_combustion_flamestrike
	spells.flamestrike("Combustion: Predicted Hot Streak")

	-- pyroblast,if=buff.hyperthermia.react
	spells.pyroblast("Combustion: Hyperthermia")

	-- pyroblast,if=buff.hot_streak.react
	spells.pyroblast("Combustion: Hot Streak")

	-- pyroblast,if=prev_gcd.1.scorch&buff.heating_up.react
	spells.pyroblast("Combustion: Predicted Hot Streak")

	-- scorch,if=buff.heat_shimmer.react&!scorch_execute.active
	spells.scorch("Combustion: Heat Shimmer")

	-- phoenix_flames
	spells.phoenix_flames("Combustion: Default")

	-- scorch
	spells.scorch("Combustion: Default")
end

local function sf_filler()
	-- fire_blast,use_off_gcd=1,use_while_casting=1,if=cooldown_react&buff.heating_up.react&buff.hyperthermia.react&cooldown.combustion.remains>variable.pooling_time
	spells.fire_blast("Filler: Hyperthermia")

	-- fire_blast,use_off_gcd=1,use_while_casting=1,if=cooldown_react&buff.heating_up.react&action.fireball.executing&action.fireball.execute_remains<0.5&cooldown.combustion.remains>variable.pooling_time
	spells.fire_blast("Filler: Fireball")

	-- fire_blast,use_off_gcd=1,use_while_casting=1,if=cooldown_react&!buff.heating_up.react&!buff.hot_streak.react&action.scorch.executing&action.scorch.execute_remains<0.5&cooldown.combustion.remains>variable.pooling_time
	spells.fire_blast("Filler: Scorch")

	-- fire_blast,use_off_gcd=1,use_while_casting=1,if=cooldown_react&charges=3&cooldown.combustion.remains>variable.pooling_time*0.3
	spells.fire_blast("Filler: Avoid Cap")

	-- fire_blast,use_off_gcd=1,if=active_enemies>=2&cooldown_react&buff.glorious_incandescence.react&!buff.heating_up.react&!buff.hot_streak.react&cooldown.combustion.remains>variable.pooling_time
	spells.fire_blast("Filler: Glorious Incandescence")

	-- Don't cancel shifting power
	if player:IsChanneling() then return false end

	-- flamestrike,if=buff.hyperthermia.react&active_enemies>=variable.sf_filler_flamestrike
	spells.flamestrike("Filler: Hyperthermia")

	-- flamestrike,if=buff.hot_streak.react&active_enemies>=variable.sf_filler_flamestrike
	spells.flamestrike("Filler: Hot Streak")

	-- flamestrike,if=prev_gcd.1.scorch&buff.heating_up.react&active_enemies>=variable.sf_filler_flamestrike
	spells.flamestrike("Filler: Predicted Hot Streak")

	-- pyroblast,if=buff.hyperthermia.react
	spells.pyroblast("Filler: Hyperthermia")

	-- pyroblast,if=buff.hot_streak.react&cooldown.combustion.remains>variable.pooling_time*0.3
	spells.pyroblast("Filler: Hot Streak")

	-- pyroblast,if=prev_gcd.1.scorch&buff.heating_up.react&cooldown.combustion.remains>variable.pooling_time*0.3
	spells.pyroblast("Filler: Predicted Hot Streak")

	-- shifting_power,if=cooldown.combustion.remains>8
	spells.shifting_power("Filler: Default")

	-- scorch,if=buff.heat_shimmer.react
	spells.scorch("Filler: Heat Shimmer")

	-- meteor,if=active_enemies>=2
	-- I'm skipping meteor for now

	-- phoenix_flames
	spells.phoenix_flames("Filler: Default")

	-- scorch,if=scorch_execute.active
	spells.scorch("Filler: Execute")

	-- TODO: We probably want to default to scorch on some movement heavy fights?
	-- fireball,if=!player.moving
	spells.fireball("Filler: Default")

	-- scorch,if=player.moving
	spells.scorch("Filler: Movement")
end

-- TODO: Add out of combat shifting power (THIS IS IMPORTANT)
-- TODO: Add out of combat shield
-- TODO: Add Arcane Intellect 
-- TODO: Add conjure food at start of key


fire:Sync(function()
    local combust_active    = player:FindBuff(auras.combustion):Active()
    local combust_remains   = player:FindBuff(auras.combustion):Remains()

    -- If we do not have hot streak up, and we are not casting a scorch that will crit
    -- Call the CDs list

	if player:IsInCombat() then

		-- Kicks
		spells.counterspell("kick")

		-- Remove Curse homies
		Dispel:ScanForDispel()

		-- Auto Target
		if not target:GetExists() or UnitCanAssist("player", target:GetPointer()) or UnitIsDeadOrGhost(target:GetPointer()) then
			SmartTarget:Acquire()
		end

		-- If tank is still grouping stuff, we want to continue evaluating for targets
		if GetTime() - mint.combatStartTime < 5 and not IsCurrentTargetGood() then
			SmartTarget:Acquire()
		end

		-- call_action_list,name=cds,if=!(buff.hot_streak.up&prev_gcd.1.scorch)
		if not (player:FindBuff(auras.hot_streak):Active() and player:IsCastingSpell(spells.scorch.id)) then
			cds()
		end
		-- run_action_list,name=sf_combustion,if=cooldown.combustion.remains<=variable.combustion_precast_time|buff.combustion.react|buff.combustion.remains>5
		if spells.combustion:GetRemainingCD() < vars.combustion_precast_time or combust_active or combust_remains > 5 then
			sf_combustion()
		else -- run_action_list,name=sf_filler
			sf_filler()
		end
	else
		if not player:IsCastingOrChanneling() and not player:IsSitting() then
			spells.blazing_barrier("Pre-combat: Default")
		end
	end
end)