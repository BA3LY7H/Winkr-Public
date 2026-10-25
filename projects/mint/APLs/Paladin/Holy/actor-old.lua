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
local Events 			= mint.EventManager
local Constants 		= mint.Constants
local Totems 			= mint.TotemManager
local SmartTarget 		= mint.SmartTarget
local Queue 			= mint.Queue
local Dispel 			= mint.Dispel
local Spell 			= mint.Spell.New
local bin 				= mint.bin
local StopTimer 		= mint.data.StopTimer
local MoveTimer 		= mint.data.MoveTimer
local max_gcd 			= mint.max_gcd
local gcd 				= mint.gcd
local toggles           = mint.data.toggles
local Item 				= mint.Item.New
local target 			= UnitManager:Get("target")
local player 			= UnitManager:Get("player")
local none 				= UnitManager:Get("none")
local Settings          = mint.Settings
local profile           = Settings.profile.paladin.holy

--! Addon Locals !--
local holy 			    = addon.paladin.holy
local spells 			= addon.paladin.data["Holy"].spells
local auras 			= addon.paladin.data["Holy"].auras
-- local items 			= addon.paladin.data["Holy"].items
local targets 			= addon.paladin.data["Holy"].targets
local vars 				= addon.paladin.data["Holy"].vars

mint.CommandMe:Register("test", "Set zoom to 70.", function()
	unlocker.SetCameraZoom(70)
end)

local health_pot  = Item(211880)
local healthstone = Item(5512)

-- Lightspawn ID: 224241
-- local Draw = mint.Draw:New()

-- local flames = mint.Spell.New(471927)
-- local shock = mint.Spell.New(460576)

-- Draw:Sync(function(draw)
-- 	FriendManager:LoopRaw(function(friend)
-- 		if friend:FindDebuff(flames):Active() then
-- 			local pos = friend:GetPosition()
-- 			draw:Text(friend.name .. " (Flame)", "GameFontNormal", pos.x, pos.y, pos.z + 2)
-- 		elseif friend:FindDebuff(shock):Active() then
-- 			local pos = friend:GetPosition()
-- 			draw:Text(friend.name .. " (Shock)", "GameFontNormal", pos.x, pos.y, pos.z + 2)
-- 		end
-- 	end)
-- end)

-- Draw:Enable()

------------------------------
--- Sync
------------------------------

holy:Sync(function()
	if player:IsChanneling() then return end
    if IsMounted() then return end


    ------------------------------
	--- Combat Rotation
	------------------------------
	if player:IsInCombat() then
		if not target.exists or UnitCanAssist("player", target:GetPointer()) or UnitIsDeadOrGhost(target:GetPointer()) then
			SmartTarget:Acquire()
		end

		if player:GetRealizedHP() < profile.healthpot_pct then
			health_pot:Use(player)
		end

		if player:GetRealizedHP() < profile.healthstone_pct then
			healthstone:Use(player)
		end

		--[[combat_apl:AddAction("hpal_potion", function()
			Caffeine.PlayerUtil:CombatPotion()
		end)
		combat_apl:AddAction("hpal_heal_potion", function()
			Caffeine.PlayerUtil:HealingPotion()
		end)
		combat_apl:AddAction("hpal_healthstone", function()
			Caffeine.PlayerUtil:Healthstone()
		end)
		combat_apl:AddAction("hpal_mana_potion", function()
			Caffeine.PlayerUtil:ManaPotion()
		end)]]

        -- In Mythic+, automatically brez dead targets
		spells.intercession("M+ Brez")

		-- Defensives
		-- spells.divine_protection()
		-- spells.divine_shield()

		-- Blessings on CD (They're off GCD)
		spells.blessing_of_summer("bless")
		spells.blessing_of_autumn("bless")
		spells.blessing_of_winter("bless")
		spells.blessing_of_spring("bless")

		-- Lay on Hands to save someone
		spells.lay_on_hands("Emergency")
		spells.blessing_of_sacrifice("Emergency")

		-- Lightsmith Armaments
		-- spells.holy_bulwark("auto_armaments")

		-- Emergency Healing
        spells.eternal_flame("Emergency")
        spells.word_of_glory("Emergency")

		-- Healing Holy Prism for emergency
		-- spells.holy_prism("Spot Healing")

        -- Kick
        spells.rebuke("Smart Kick")

		-- Auto HoJ
		spells.hammer_of_justice("Auto HoJ")

		-- Use LoD on 5 targets
		-- spells.light_of_dawn("raid_lod")

        -- Dispel
        if toggles.dispels then
			-- Dispel:Scan()
            spells.cleanse("Smart Dispel")
        end

		-- Spend Dawnlight Charges after Holy Prism
		spells.eternal_flame("Spread Dawnlight")

		-- Use Holy Prism on enemy if we have Avenging Wrath active
		-- This is so we can generate dawnlights
		spells.holy_prism("Generate Dawnlights")

		-- Divine Toll
		spells.divine_toll("Healing")

		-- Hold prism if wings is going to be off cooldown in the next 25 seconds.
		-- As soon as wings is popped we should be popping prism and spreading dawnlights
		-- Holy Prism (aggro)
		spells.holy_prism("Group Healing")

        -- Beacon of Virtue (Mythic+)
		-- spells.beacon_of_virtue("Mythic+")

		-- Beacon of Virtue (Raid)
		-- spells.beacon_of_virtue("Raid")

		-- spells.eternal_flame("Lightspawn")

		-- Use LoD if we can
		spells.light_of_dawn("Dump HP")

		-- Spend to prevent over capping
		spells.eternal_flame("Dump HP")
		-- spells.word_of_glory("Dump HP")

		-- Spend holy power for damage during Blessing of Summer
		spells.eternal_flame("Summer")

        -- Dump with Shield of the Righteous if we don't need healing
		spells.shield_of_the_righteous("Dump HP")

        -- Holy shock (2 Charges)
        if spells.holy_shock:GetCharges() == 2 then
            spells.holy_shock("Healing")
			-- spells.holy_shock("Lightspawn")
            spells.holy_shock("Damage")
        end

        -- Judgment
		-- Hold if we have awakening proc and holy prism is on cooldown
		-- Hold if we have proc and holy prism is available if we have < 2 holy power
		spells.judgment()

        -- Hammer of Wrath with Veneration talent
        spells.hammer_of_wrath("Veneration")

		-- Crusader Strike
		spells.crusader_strike()

        -- Holy Shock (1 Charge)
		spells.holy_shock("Healing")
		-- spells.holy_shock("Lightspawn")
		spells.holy_shock("Damage")

		-- Consecration if it isn't active
		spells.consecration()

		-- Holy Light with proc while not moving
		spells.holy_light("Spot Healing")

		-- Hammer of Wrath without Veneration talent
        spells.hammer_of_wrath()

    ------------------------------
	--- Resting Rotation
	------------------------------
    else
        spells.holy_shock("Healing")
        spells.eternal_flame("Emergency")
        spells.word_of_glory("Emergency")

        if mint.data.toggles.dispels then
			-- Dispel:Scan()
            spells.cleanse("Smart Dispel")
        end

        -- Place Beacon of Light/Beacon of Faith if not present
	end
end)

-- The following assumes you won't overcap HP with infused Flash of Lights or Holy Shock, DO NOT OVERCAP HOLY POWER.
-- RAID
-- 1. Virtue if 5+ people injured
-- 2. Holy Prism
-- 3. Eternal Flame
-- 4. Holy Shock
-- 5. Infusion Judgment
-- 6. Infusion Flash of Light
-- 7. Crusader Strike
-- 8. Hammer of Wrath

-- KEYS
-- 1. Virtue if 2+ people injured
-- 2. Holy Prism
-- 3. Infusion Flash of Light DURING Virtue
-- 4. Eternal Flame
-- 5. Holy Shock
-- 6. Infusion Flash of Light OUTSIDE of Virtue
-- 7. Judgment
-- 8. Crusader Strike
-- 9. Hammer of Wrath

-- MERGED
-- 1. Beacon of Virtue
	-- 2+ players in M+, 5+ in raid
-- 2. Holy Prism
-- 3a. Keys: Infusion Flash of Light while BoV is active
-- 3b. Eternal Flame
-- 4. Holy Shock
-- 5a. Keys: Infusion Flash of Light outside BoV
-- 5b. Raid: Infusion Judgement
-- 5c. Keys: Judgement
-- 6. Raid: Infusion Flash of Light
-- 7. Crusader Strike
-- 8. Hammer of Wrath

-- DAMAGE ROTATION
-- RAID
-- NONE. WE'RE RAIDING NOT M+ING DON'T PRESS SHIELD OF THE RIGHTEOUS OR CONSECRATION EVER.

-- KEYS
-- 1. Keep your manual Consecration down
-- 2. Judgment
-- 3. Holy Prism
-- 4. Shield of the Righteous
-- 5. Holy Shock
-- 6. Crusader Strike
-- 7. Hammer of Wrath

-- COOLDOWNS
-- RAID
-- 1. For Seasons, send all on CD on yourself. Only send Summer with your actual Wings press (not awakening).
-- 2. Holy Prism on CD.
-- 3. Wings on CD unless a big damage event is coming up. It's better to hold DT than to hold Wings. Most of Heralds power comes from using wings frequently.
-- 4. Divine Toll as much as possible, remember a lot of DT's power is in Rising Sunlight and Holy Power generation, not the upfront heal.

-- KEYS
-- 1. For Seasons, send all on CD on yourself. Only send Summer with your actual Wings press (not awakening).
-- 2. Holy Prism on CD.
-- 3. Wings on CD unless a big damage event is coming up. It's better to hold DT than to hold Wings. Most of Heralds power comes from using wings frequently.
-- 4. Divine Toll as much as possible, remember a lot of DT's power is in Rising Sunlight and Holy Power generation, not the upfront heal.
-- 5. Bubble if big group damage is coming and you don't have any throughput. Pair with Sac if available.
-- 6. Use LoH / Sac for spot healing help liberally, everyone always underuses these.