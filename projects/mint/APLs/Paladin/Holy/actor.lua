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

local function IsLightsmith()
	if UnitLevel("player") <= 70 then return false end
	return C_ClassTalents.GetActiveHeroTalentSpec() == 49
end

local function IsHerald()
	if UnitLevel("player") <= 70 then return false end
	return C_ClassTalents.GetActiveHeroTalentSpec() == 50
end

local health_pot  = Item(211880)
local healthstone = Item(5512)

------------------------------
--- Spellcast Listener
------------------------------

local events = mint.EventManager:New()
-- Automatically cast Blessing of Summer on Avenging Wrath cast.
events:RegisterWoWEvent("UNIT_SPELLCAST_SUCCEEDED", function(...)
	local unit, _, spellId = ...
	if unit ~= "player" then return end
	if spellId == spells.avenging_wrath.id then
		spells.blessing_of_summer("Self")
	end
end)

------------------------------
--- Sync
------------------------------


local health_pot  = Item(244839)
local healthstone = Item(5512)

local using = "None"

holy:Sync(function()
	if player:IsChanneling() then return end
    if IsMounted() then return end

	-- In Combat
	if player:IsInCombat() then
		-- Auto Targeting
		if not target.exists or UnitCanAssist("player", target:GetPointer()) or UnitIsDeadOrGhost(target:GetPointer()) then
			SmartTarget:Acquire()
		end
		
		-- Utility actions (off GCD)
		-- Healthstone/Health Potion
		-- items.healthstone("Imminent Death")
		-- items.health_potion("Imminent Death")

		if player:GetHP() < profile.healthpot_pct then
			health_pot:Use(player)
		end

		if player:GetHP() < profile.healthstone_pct then
			healthstone:Use(player)
		end

		spells.divine_protection()

		-- Kick
		spells.rebuke("Utility: Smart Kick")

		-- Emergency Lay on Hands
		spells.lay_on_hands("Imminent Death")
		spells.blessing_of_sacrifice("Emergency")

		-- Dispel
		spells.cleanse("Utility: Smart Dispel")

		-- Blessings on self on CD, except summer unless toggled on.
		if profile.summer_on_cd then
			spells.blessing_of_summer("Self")
		end
		spells.blessing_of_autumn("Self")
		spells.blessing_of_winter("Self")
		spells.blessing_of_spring("Self")

		if IsLightsmith() then
			-- 1. Cast  Beacon of Virtue for AoE healing as needed
			if spells.beacon_of_virtue("Raid") then using = "Beacon of Virtue" return end
			-- 2. Cast  Holy Prism on an enemy target
			if spells.holy_prism("Raid: Lightsmith") then using = "Holy Prism" return end
			if spells.divine_toll("Raid") then using = "Divine Toll" return end
			-- 3. Spend Holy Power on 5 Holy Power (check notes)
			if spells.word_of_glory("Raid") then using = "Word of Glory" return end
			if spells.light_of_dawn("Raid: Lightsmith") then using = "Light of Dawn" return end
			-- 4. During  Beacon of Virtue - Spend  Infusion of Light procs (check notes)
			if spells.flash_of_light("Raid: Infusion") then using = "FoL" return end
			if spells.judgment("Raid: Infusion") then using = "Judgment (Infusion)" return end
			-- 5. During  Beacon of Virtue - Spend Holy Power on 3 or 4 Holy Power
			-- 6. During  Beacon of Virtue - Cast  Holy Shock
			-- 7. Cast  Judgment
			if spells.judgment("Raid") then using = "Judgment" return end
			-- 8. Cast  Crusader Strike
			if spells.crusader_strike("Raid: Lightsmith") then using = "Crusader Strike" return end
			-- 9. Spend  Infusion of Light procs (check notes)
			if spells.holy_bulwark("Raid") then using = "Holy Bulwark" return end
			if spells.sacred_weapon("Raid") then using = "Sacred Weapon" return end
			-- 10. Cast  Holy Shock
			if spells.holy_shock("Raid") then using = "Holy Shock" return end
			-- 11. Cast  Consecration if on 5 stacks of  Divine Guidance
			if spells.consecration("Raid: Lightsmith") then using = "Consecration" return end
			if spells.holy_shock("Raid: Damage") then using = "Holy Shock" return end
			-- 13. Cast  Flash of Light
			if spells.hammer_of_wrath("Raid") then using = "Hammer of Wrath" return end
			-- 12. Spend Holy Power
			if spells.shield_of_the_righteous("Raid") then using = "SoTR" return end
			return
		end
		if IsInRaid() then
			-- 1. Virtue if 5+ people injured
			if spells.beacon_of_virtue("Raid") then using = "Beacon of Virtue 1" return end
			if spells.beacon_of_virtue("Raid: Wings") then using = "Beacon of Virtue 2" return end
			-- 1a. Emergency Eternal Flame
			if spells.eternal_flame("Raid: Emergency") then using = "Eternal Flame 1" return end
			-- 1b. Spread Dawnlight charges
			if spells.eternal_flame("Raid: Spread Dawnlight") then using = "Eternal Flame (DL)" return end
			-- 1b. Divine Toll if 2+ people are injured.
			if spells.divine_toll("Raid") then using = "Divine Toll" return end
			-- 2. Holy Prism
			-- 2a. Generate Dawnlights
			if spells.holy_prism("Raid: Dawnlights") then using = "Holy Prism (DL)" return end
			-- 2b. Group Healing
			if spells.holy_prism("Raid") then using = "Holy Prism" return end
			-- 3. Eternal Flame
			if spells.eternal_flame("Raid") then using = "Eternal Flame 2" return end
			-- 3a. Shield of the Righteous when capped and no healing
			if spells.shield_of_the_righteous("Raid") then using = "SoTR" return end
			-- 4. Holy Shock
			if spells.holy_shock("Raid") then using = "Holy Shock" return end
			-- 6. Infusion Flash of Light
			if spells.flash_of_light("Raid: Infusion") then using = "Flash of Light (Infusion)" return end
			-- 5. Infusion Judgment
			if spells.judgment("Raid: Infusion") then using = "Judgment (Infusion)" return end

			if spells.flash_of_light("Raid: Hard Cast") then using = "Flash of Light" return end
			-- 7. Judgment
			if spells.judgment("Raid") then using = "Judgment" return end
			-- 8. Hammer of Wrath
			if spells.hammer_of_wrath("Raid") then using = "Hammer of Wrath" return end
			-- 9. Crusader Strike
			if spells.crusader_strike("Raid") then using = "Crusader Strike" return end

			if spells.holy_shock("Raid: Damage") then using = "Holy Shock" return end
		else

			-- Healing Spell Priority:
			-- 1. Virtue if 2+ people injured
			spells.beacon_of_virtue("Keys")
			-- 1a. Spread Dawnlights after Holy Prism
			spells.eternal_flame("Keys: Spread Dawnlight")
			-- 1b. Generate Dawnlight stacks with Holy Prism
			spells.holy_prism("Keys: Generate Dawnlight")
			-- 1c. Use Divine Toll
			spells.divine_toll("Keys")
			-- 2. Holy Prism
			spells.holy_prism("Keys")
			-- 2a. Spend HP on Eternal Flame
			spells.eternal_flame("Keys")
			-- 2b. Spam Eternal Flame during Blessing of Summer
			spells.eternal_flame("Keys: Blessing of Summer")
			-- 2c. Spend HP on SoTR if no one is injured.
			spells.shield_of_the_righteous("Keys")
			-- 3. Infusion Flash of Light DURING Virtue
			spells.flash_of_light("Keys: Infusion (Virtue)")
			-- 4. Eternal Flame
			spells.eternal_flame("Keys")
			-- 5. Holy Shock
			spells.holy_shock("Keys: Healing")
			spells.holy_shock("Keys: Damage")
			-- 6. Infusion Flash of Light OUTSIDE of Virtue
			spells.flash_of_light("Keys: Infusion")
			-- 6a. Consecration
			spells.consecration("Keys")
			-- 7. Judgment
			spells.judgment("Keys")
			-- 8. Crusader Strike
			spells.crusader_strike("Keys")
			-- 9. Hammer of Wrath
			spells.hammer_of_wrath("Keys")
		end
    else
        spells.holy_shock("Keys: Healing")
        spells.eternal_flame("Imminent Death")

        if mint.data.toggles.dispels then
			-- Dispel:Scan()
            spells.cleanse("Utility: Smart Dispel")
        end
	end
end)

local DebugFrame = mint.DebugFrame.New("Holy")

DebugFrame:AddRow("Active Spell", function()
    return using
end)

-- local DebugFrame = mint.DebugFrame.New("Holy Paladin")

-- DebugFrame:AddRow("Buffer", function()
--     return profile.healing_buffer
-- end)

-- DebugFrame:AddRow("100 - Buffer", function()
--     return 100 - profile.healing_buffer
-- end)

-- DebugFrame:AddRow("LoH Toggle", function()
--     return profile.loh_toggle
-- end)

-- DebugFrame:AddRow("LoH Percent", function()
--     return profile.loh_pct
-- end)



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
