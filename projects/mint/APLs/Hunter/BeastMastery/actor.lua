local unlocker, mint, addon = ...

-- ! Mint Locals !--
local ObjectManager = mint.ObjectManager
local UnitManager   = mint.UnitManager
local FriendManager = mint.FriendManager
local Constants     = mint.Constants
local SmartTarget   = mint.SmartTarget
local Events        = mint.EventManager.New()
local Notifications = mint.NotificationManager
local toggles       = mint.data.toggles
local Spell         = mint.Spell.New
local target        = UnitManager:Get("target")
local player        = UnitManager:Get("player")
local none          = UnitManager:Get("none")
local pet 			= UnitManager:Get("pet")
local pettarget     = UnitManager:Get("pettarget")
local sequences = {}
local settings      = mint.Settings
local profile       = settings.profile.hunter.beastmastery

--! Addon Locals !--
local bm 			= addon.hunter.bm
local spells 		= addon.hunter.data.bm.spells
local items 		= addon.hunter.data.bm.items
local auras 		= addon.hunter.data.bm.auras
local targets 		= addon.hunter.data.bm.targets
local talents 		= addon.hunter.data.bm.talents
local helpers 		= addon.hunter.data.bm.helpers

local function CombatTime()
    local startTime = mint.combatStartTime or 0
    return GetTime() - startTime
end

-- Helper to make sure our pet sticks to our target when spreading barbed shot.
Events:RegisterWoWEvent("UNIT_SPELLCAST_SUCCEEDED", function(...)
	local unit, castGUID, spellId = ...

	if unit ~= "player" then return end

	if spellId == 217200 then -- Barbed Shot
		PetAttack()
		mint.NotificationManager:AddNotification(spells.claw.icon, "PetAttack (Barbed Shot Redirect)", 3)
	end
end)

local Draw = mint.Draw:New()

local taColor = { 255, 220, 111, 255 }
local baColor = { 155, 89, 182, 255 }
local bcColor = { 241, 196, 15, 160 }
local combatColor = { 231, 76, 60, 255 }
local friendColor = { 39, 174, 96, 255 }


-- rotation (radians) for cone pointing "away from player" from candidate position
local function behindRotationFrom(cpos, ppos)
    -- dir away from player = (candidate - player)
    local dx, dy = (cpos.x - ppos.x), (cpos.y - ppos.y)
    return math.atan2(dy, dx)   -- rotation for your cone struct
end

Draw:Sync(function(draw)
    -- if targets.black_arrow:GetExists() then
    --     local pos = targets.black_arrow:GetPosition()
    --     if pos:IsValid() then
    --         draw:SetColor(255, 255, 255)
    --         draw:Text("Black Arrow Target", "GameFontNormal", pos.x, pos.y, pos.z + 2)
    --     end
    -- end

	if profile.petIndicator then
		local pos = pet:GetPosition()
		if pos:IsValid() then
			draw:SetColor(friendColor)
			mint.Utility:DrawFacingArrow(draw, pet)
			if pettarget:GetExists() then
				local tar = pettarget:GetPosition() 
				if tar:IsValid() then
					draw:SetColor(combatColor)
					draw:Line(pos.x, pos.y, pos.z, tar.x, tar.y, tar.z)
				end
			end
		end
	end

	-- ObjectManager.combat:loop(function(enemy)
	-- 	local pos = enemy:GetPosition()
	-- 	if pos:IsValid() then
	-- 		draw:SetColor(combatColor)
	-- 		draw:Circle(pos.x, pos.y, pos.z, 1, 3)
	-- 	end
	-- end)

	if pet:GetExists() then
		local pos = pet:GetPosition()
		if pos:IsValid() then
			draw:SetColor(bcColor)
			draw:Circle(pos.x, pos.y, pos.z, 10, 20)
		end
	end


	-- if targets.black_arrow_aoe:GetExists() then
    --     local pos = targets.black_arrow:GetPosition()
    --     if pos:IsValid() then
	-- 		local rot  = behindRotationFrom(pos, player:GetPosition())
    --         draw:SetColor(255, 255, 255)
    --         draw:Text("Best", "GameFontNormal", pos.x, pos.y, pos.z + 2)
	-- 		draw:SetColor(baColor)
	-- 		draw:Circle(pos.x, pos.y, pos.z, 1, 5)
	-- 		draw:Arc(pos.x, pos.y, pos.z, 8, 45, rot)
    --     end
	-- end

	if target:GetExists() and helpers.shouldCleave() then
        local pos = target:GetPosition()
        if pos:IsValid() then
			local rot  = behindRotationFrom(pos, player:GetPosition())
			draw:SetColor(taColor)
			draw:Arc(pos.x, pos.y, pos.z, 8, 45, rot)
        end
	end
end)

Draw:Enable()

local using = "unknown"

-- * ================================ *
-- * Actor Sync
-- * ================================ *
bm:Sync(function()
	if player:IsChanneling() then return false end
    if IsMounted() then return false end

	-- # Summon your pet if it is not out.
	-- actions.precombat=summon_pet

	spells.feign_death("Affix")

	-- ! Combat APL !--
	if player:IsInCombat() or player:IsPartyInCombat() then
		if not target:GetExists() or UnitCanAssist("player", target:GetPointer()) or UnitIsDeadOrGhost(target:GetPointer()) then
			SmartTarget:Acquire()
		end

		-- ! Off-GCD Actions !--
        -- $ Use Healthstone below user's threshold
        if items.healthstone() then return end

        -- $ Use Healing Potion below user's threshold
        if items.healing_potion() then return end

		-- $ Use Counter Shot to interrupt
		if spells.counter_shot() then return end

		-- $ Summon Pet if we don't have one in combat
		-- if 

		-- $ Use Dash if pet is not in melee range of it's target
		if spells.dash() then return end

		-- $ Use Claw/Bite/Smack if not on CD if pet is alive, in melee range, and not crowd controlled. 
		if spells.bite() then return end
		if spells.claw() then return end
		if spells.smack() then return end

		-- # Keep Auto Shot rolling (default ranged auto-attack).
		-- actions=auto_shot
		if spells.auto_shot() then return end

		if sequences.PLST:IsRunning() then
			sequences.PLST:Execute()
			return
		end

		if sequences.PLAoE:IsRunning() then
			sequences.PLAoE:Execute()
			return
		end

		if sequences.DROpener:IsRunning() then
			sequences.DROpener:Execute()
			return
		end

		if CombatTime() < 3 then
			if helpers.isDarkRanger() then
				sequences.DROpener:Execute()
				return
			else
				if helpers.shouldCleave() or sequences.PLAoE:IsRunning() then
					sequences.PLAoE:Execute()
					return
				elseif (not helpers.shouldCleave()) or sequences.PLST:IsRunning() then
					sequences.PLST:Execute()
					return
				end
			end
		end
		

		-- $ Use Exhilaration below emergency threshold.
		if spells.exhilaration("Emergency") then return end

		-- $ Use Fortitude of the Bear below emergency threshold.
		if spells.fortitude_of_the_bear() then return end

		-- TODO: Turtle emergency?

		-- TODO: Auto feign spells?

		-- TODO: other utility?

		-- $ Use Tranquilizing Shot as needed
		if spells.tranquilizing_shot() then return end

		-- * Cooldowns up front

		-- # Use your potion during Call of the Wild, or (without CotW) during Bestial Wrath, or if the fight ends soon (<31s).
		-- actions.cds+=/potion,if=buff.call_of_the_wild.up|!talent.call_of_the_wild&buff.bestial_wrath.up|fight_remains<31
		-- if items.tempered_potion() then return end

		-- * Combined for Pack Leader
		if helpers.isPackLeader() then

			-- 1. Beastial Wrath when aligning with Lead from the Front/Howl, or without TWW S3 4P, or with Multishot in AoE
			if spells.bestial_wrath() then return end

			-- 2. Barbed Shot (spread) if near cap OR (in AoE) have as many charges as Kill Command, CotW is ready, or Howl summon soon with quick recharge.
			if spells.barbed_shot() then return end

			-- 3. ST: Call of the Wild
			if spells.call_of_the_wild("ST") then return end

			-- 4. Bloodshed
			if spells.bloodshed() then return end

			-- 5. In cleave: Keep Beast Cleave active with Multishot if it’s fallen off (and either you don’t have Bloody Frenzy, or CotW isn’t about to come up).
			if spells.multishot() then return end

			-- $ Use Exhilaration below normal threshold
			if spells.exhilaration() then return end

			-- 6. In cleave: Use Call of the Wild as your major burst window
			if spells.call_of_the_wild("Cleave") then return end

			-- 7. In cleave: Use Explosive Shot when Thundering Hooves is talented.
			if spells.explosive_shot() then return end

			-- 8. In cleave: Use Kill Command on cooldown.
			-- 9. ST: Use Kill Command, but delay slightly if it would desync with Barbed Shot windows or Lead from the Front micro-timing.
			if spells.kill_command() then return end

			-- 10. ST: Keep Barbed Shot rolling on target (reapply/extend as needed).
			if spells.barbed_shot("ST Fallback") then return end

			-- 11. Cobra Shot (ST just dump). AoE: Dump with Cobra Shot if you’re about to cap focus, have high Hogstrider stacks, or Multishot isn’t talented.
			if spells.cobra_shot() then return end

		elseif helpers.isDarkRanger() then
			-- * Dark Ranger Combined

			-- 1. Kill Shot (Black Arrow) if available (snipe off targets)
			if spells.black_arrow() then using = "Black Arrow" return end

			-- 2. Bestial Wrath unless we are holding for CoTW
			if spells.bestial_wrath("Dark Ranger") then using = "Bestial Wrath" return end

			-- 3. Barbed shot to spread, avoiding withering fire tick overlap. Only cleave
			if spells.barbed_shot("DR: Cleave") then using = "Barbed Shot #1" return end

			-- 4. Bloodshed
			if spells.bloodshed() then using = "Bloodshed" return end
			
			-- 5. Cleave: Maintain Beast Cleave with Multishot unless CoTW is going to be used with Bloody Frenzy
			if spells.multishot() then using = "Multishot" return end
			
			-- 6. Call of the Wild
			if spells.call_of_the_wild() then using = "Call of the Wild" return end
			
			-- 7. Cleave: Use explosive shot with thundering hooves
			if spells.explosive_shot() then using = "Explosive Shot #1" return end
			
			-- 8. Cleave: Barbed shot if you have charges >= kill command charges
			-- if spells.barbed_shot("DR: Cleave") then using = "Barbed Shot #2" return end
			
			-- 9. Kill Command (Avoid withering fire tick overlap)
			if spells.kill_command("Dark Ranger") then using = "Kill Command" return end
			
			-- 10. ST: Barbed Shot as filler (Avoid withering fire tick overlap)
			if spells.barbed_shot("Dark Ranger") then using = "Barbed Shot #3" return end
			
			-- 11. Cobra Shot, ST: Always, In Cleave: Only if focus time to max < (max_gcd * 2)
			if spells.cobra_shot() then using = "Cobra Shot" return end
			
			-- 12. In Cleave: Explosive Shot if literally nothing else available.
			if spells.explosive_shot("DR: Filler") then using = "Explosive Shot #2" return end
		end

	else

	end
end)

-- local DebugFrame = mint.DebugFrame.New("Beast Mastery")

-- DebugFrame:AddRow("TTD", function()
--     return mint.TimeToDie.ActiveFightRemains()
-- end)

-- DebugFrame:AddRow("Using", function()
--     return using
-- end)

-- DebugFrame:AddRow("wfTick", function()
--     return helpers.wfTick()
-- end)

-- DebugFrame:AddRow("BA CD Remains", function()
--     return spells.black_arrow:GetRemainingCD()
-- end)


-- DebugFrame:AddRow("Tier (2p)", function()
--     return player:Has2p()
-- end)

-- DebugFrame:AddRow("GetEnemies(10)", function()
--     return target:GetExists() and target:GetEnemies(10)
-- end)

-- DebugFrame:AddRow("CombatTime()", function()
--     return CombatTime()
-- end)

-- DebugFrame:AddRow("Beast Cleave", function()
--     return player:FindBuff(auras.beast_cleave):Active()
-- end)

-- DebugFrame:AddRow("TTD", function()
--     return math.floor(mint.TimeToDie.ActiveFightRemains())
-- end)

-- DebugFrame:AddRow("Most Recent Cast", function()
-- 	local history = mint.data.lastCastOrder

-- 	if not history then
-- 		return "Unknown"
-- 	end

-- 	local lastId = history[#history]

-- 	local spell = Spell(lastId)

--     return spell and spell.name or "Unknown"
-- end)


-- * ================================ *
-- * Pack Leader Opener (ST)
-- * ================================ *
-- Hunter's Mark
-- Barbed Shot #1
-- Bloodshed (Trinkets/Potions)
-- Kill Command
-- Barbed Shot
-- Alternate KC/BS to 0 charges
-- Bestial Wrath

local function OpenerNotify(icon, text, dur)
	if not profile.openerNotifs then
		return false
	end

	Notifications:AddNotification(icon, text, dur)
end

local PackLeaderST = {
	{
		-- Hunter's Mark (if not present)
		name = "Hunter's Mark",
		func = function(self)
			if not pet:GetExists() then
				OpenerNotify(spells.kill_command.icon, "No pet found, skipping opener.", 3)
				return true
			end

			if not target:GetExists() then return false end

			if not target:IsBoss() then
				return true
			end

			-- if target:FindDebuff(auras.hunters_mark):Active() then
			-- 	return true
			-- end

			if spells.hunters_mark:IsOnCD() then
				OpenerNotify(spells.hunters_mark.icon, "On cooldown, skipping.", 3)
				return true
			end

			spells.hunters_mark:Cast(target)

			return false
		end,
	},
	{
		-- Barbed Shot
		name = "Barbed Shot #1",
		func = function(self)
			if not pet:GetExists() then
				OpenerNotify(spells.kill_command.icon, "No pet found, skipping opener.", 3)
				return true
			end

			if not target:GetExists() then
				return false 
			end

			if spells.barbed_shot:TimeSinceLastCast() < mint.max_gcd then
				return true
			end

			if spells.barbed_shot:GetCharges() < 1 then
				OpenerNotify(spells.barbed_shot.icon, "On cooldown, skipping.", 3)
				return true
			end

			spells.barbed_shot:Cast(target)

			return false
		end,
	},
	{
		-- Bloodshed + potions + trinkets
		name = "Bloodshed + Trinkets/Potions",
		func = function(self)
			if not pet:GetExists() then
				OpenerNotify(spells.kill_command.icon, "No pet found, skipping opener.", 3)
				return true
			end

			-- Make sure we actually have bloodshed
			if not IsPlayerSpell(talents.bloodshed.id) then
				return true
			end

			if not targets.bloodshed:GetExists() then
				return false 
			end

			-- if spells.bloodshed:TimeSinceLastCast() < mint.max_gcd then
			-- 	return true
			-- end

			if spells.bloodshed:IsOnCD() then
				-- OpenerNotify(spells.bloodshed.icon, "On cooldown, skipping.", 3)
				return true
			end

			spells.bloodshed:Cast(targets.bloodshed)

			return false
		end,
	},
	{
		-- Kill Command
		name = "Kill Command #1",
		func = function(self)
			if not pet:GetExists() then
				OpenerNotify(spells.kill_command.icon, "No pet found, skipping opener.", 3)
				return true
			end

			if not target:GetExists() then
				return false 
			end

			if spells.kill_command:TimeSinceLastCast() < mint.max_gcd then
				return true
			end

			if spells.kill_command:IsOnCD() then
				OpenerNotify(spells.kill_command.icon, "On cooldown, skipping.", 3)
				return true
			end

			spells.kill_command:Cast(target)

			return false
		end,
	},
	{
		-- Barbed Shot
		name = "Barbed Shot #2",
		func = function(self)
			if not pet:GetExists() then
				OpenerNotify(spells.kill_command.icon, "No pet found, skipping opener.", 3)
				return true
			end

			if not target:GetExists() then
				return false 
			end

			if spells.barbed_shot:TimeSinceLastCast() < mint.max_gcd then
				return true
			end

			if spells.barbed_shot:GetCharges() < 1 then
				OpenerNotify(spells.barbed_shot.icon, "On cooldown, skipping.", 3)
				return true
			end

			spells.barbed_shot:Cast(target)

			return false
		end,
	},
	{
		-- Kill Command / Barbed shot alternate until out of charges
		name = "KC/BS Alternate Spam",
		func = function(self)
			if not pet:GetExists() then
				OpenerNotify(spells.kill_command.icon, "No pet found, skipping opener.", 3)
				return true
			end

			if spells.kill_command:GetCharges() < 1 and spells.barbed_shot:GetCharges() < 1 then
				return true
			end

			if not target:GetExists() then
				return false 
			end

			if spells.barbed_shot:TimeSinceLastCast() < mint.max_gcd then
				spells.kill_command:Cast(target)
				return false
			end

			if spells.kill_command:TimeSinceLastCast() < mint.max_gcd then
				spells.barbed_shot:Cast(target)
				return false
			end

			-- Fallback for having an offset number of charges for some reason
			if spells.kill_command:GetCharges() < 1 and spells.barbed_shot:GetCharges() >= 1 then
				spells.barbed_shot:Cast(target)
				return false
			elseif spells.kill_command:GetCharges() >= 1 and spells.barbed_shot:GetCharges() < 1 then
				spells.kill_command:Cast(target)
				return false
			end


		end,
	},
	{
		-- Bestial Wrath
		name = "Bestial Wrath",
		func = function(self)
			if not pet:GetExists() then
				OpenerNotify(spells.kill_command.icon, "No pet found, skipping opener.", 3)
				return true
			end

			if not toggles.cooldowns then
				OpenerNotify(spells.bestial_wrath.icon, "CDs off, skipping.", 3)
				return true
			end

			if not target:GetExists() then
				return false 
			end

			if player:FindBuff(auras.bestial_wrath):Active() then
				OpenerNotify(spells.bloodshed.icon, "Bestial Wrath found, ST opener complete.", 3)
				return true
			end

			if spells.bestial_wrath:IsOnCD() then
				OpenerNotify(spells.bestial_wrath.icon, "On cooldown, skipping.", 3)
				return true
			end

			spells.bestial_wrath:Cast(player)
		end,
	}
}

local function PLSTReset()
	return false
end

-- Abort the opener if we're "stuck" in it.
local function PLSTAbort()
	if CombatTime() > 10 then
		return true
	end

	return false
end

sequences.PLST = mint.Sequence:New("PLST", PackLeaderST, PLSTReset, PLSTAbort)

-- * ================================ *
-- * Pack Leader Opener (AoE)
-- * ================================ *
-- Hunter's Mark
-- Bestial Wrath
-- Barbed Shot
-- Activate Beast Cleave
-- Kill Command
-- Barbed Shot
-- Bloodshed

local PackLeaderAoE = {
	{
		-- Hunter's Mark (if not present)
		name = "Hunter's Mark",
		func = function(self)
			if not pet:GetExists() then
				OpenerNotify(spells.kill_command.icon, "No pet found, skipping opener.", 3)
				return true
			end

			if not target:GetExists() then return false end

			if not target:IsBoss() then
				return true
			end

			-- if target:FindDebuff(auras.hunters_mark):Active() then
			-- 	return true
			-- end

			if spells.hunters_mark:IsOnCD() then
				OpenerNotify(spells.hunters_mark.icon, "On cooldown, skipping.", 3)
				return true
			end

			spells.hunters_mark:Cast(target)

			return false
		end,
	},
	{
		-- Bestial Wrath
		name = "Bestial Wrath",
		func = function(self)
			if not pet:GetExists() then
				OpenerNotify(spells.kill_command.icon, "No pet found, skipping opener.", 3)
				return true
			end

			if not toggles.cooldowns then
				OpenerNotify(spells.bestial_wrath.icon, "CDs off, skipping.", 3)
				return true
			end

			if not target:GetExists() then
				return false 
			end

			if spells.bestial_wrath:IsOnCD() then
				OpenerNotify(spells.bestial_wrath.icon, "On cooldown, skipping.", 3)
				return true
			end

			if player:FindBuff(auras.bestial_wrath):Active() or spells.bestial_wrath:IsOnCD() then
				OpenerNotify(spells.bestial_wrath.icon, "Bestial Wrath active or on CD, moving on.", 3)
				return true
			else
				spells.bestial_wrath:Cast(player)
			end

		end,
	},
	{
		-- Barbed Shot
		name = "Barbed Shot #1",
		func = function(self)
			if not pet:GetExists() then
				OpenerNotify(spells.kill_command.icon, "No pet found, skipping opener.", 3)
				return true
			end

			if not target:GetExists() then
				return false 
			end

			if spells.barbed_shot:TimeSinceLastCast() < mint.max_gcd then
				OpenerNotify(spells.barbed_shot.icon, "Barbed Shot cast, moving on.", 3)
				return true
			end

			if spells.barbed_shot:GetCharges() < 1 then
				OpenerNotify(spells.barbed_shot.icon, "On cooldown, skipping.", 3)
				return true
			end

			spells.barbed_shot:Cast(target)

			return false
		end,
	},
	{
		-- Activate Beast Cleave with Multishot or Call of the Wild (with Blood Frenzy)
		name = "Activate Beast Cleave",
		func = function(self)
			if not pet:GetExists() then
				OpenerNotify(spells.kill_command.icon, "No pet found, skipping opener.", 3)
				return true
			end

			if not target:GetExists() then
				return false 
			end

			if player:FindBuff(auras.beast_cleave):Active() then
				OpenerNotify(auras.beast_cleave.icon, "Beast Cleave found, moving on.", 3)
				return true
			end

			if IsPlayerSpell(talents.bloody_frenzy.id) and not spells.call_of_the_wild:IsOnCD() and toggles.cooldowns then
				spells.call_of_the_wild:Cast(target)
			end

			if not IsPlayerSpell(talents.multishot.id) then
				OpenerNotify(auras.beast_cleave.icon, "Beast Cleave not known, skipping.", 3)
				return true
			end

			spells.multishot:Cast(target)

			return false
		end,
	},
	{
		-- Kill Command
		name = "Kill Command #1",
		func = function(self)
			if not pet:GetExists() then
				OpenerNotify(spells.kill_command.icon, "No pet found, skipping opener.", 3)
				return true
			end

			if not target:GetExists() then
				return false 
			end

			if spells.kill_command:TimeSinceLastCast() < mint.max_gcd then
				OpenerNotify(spells.kill_command.icon, "Kill Command cast, moving on.", 3)
				return true
			end

			if spells.kill_command:IsOnCD() then
				OpenerNotify(spells.kill_command.icon, "On cooldown, skipping.", 3)
				return true
			end

			spells.kill_command:Cast(target)

			return false
		end,
	},
	{
		-- Barbed Shot
		name = "Barbed Shot #2",
		func = function(self)
			if not pet:GetExists() then
				OpenerNotify(spells.kill_command.icon, "No pet found, skipping opener.", 3)
				return true
			end

			if not target:GetExists() then
				return false 
			end

			if spells.barbed_shot:TimeSinceLastCast() < mint.max_gcd then
				OpenerNotify(spells.barbed_shot.icon, "Barbed Shot (#2) cast, moving on.", 3)
				return true
			end

			if spells.barbed_shot:IsOnCD() then
				OpenerNotify(spells.barbed_shot.icon, "On cooldown, skipping.", 3)
				return true
			end

			spells.barbed_shot:Cast(target)

			return false
		end,
	},
	{
		-- Bloodshed + potions + trinkets
		name = "Bloodshed + Trinkets/Potions",
		func = function(self)
			if not pet:GetExists() then
				OpenerNotify(spells.kill_command.icon, "No pet found, skipping opener.", 3)
				return true
			end

			-- Make sure we actually have bloodshed
			if not IsPlayerSpell(talents.bloodshed.id) then
				return true
			end

			if not targets.bloodshed:GetExists() then
				return false 
			end

			if spells.bloodshed:TimeSinceLastCast() < mint.max_gcd then
				OpenerNotify(spells.bloodshed.icon, "Bloodshed cast, AoE opener complete.", 3)
				return true
			end

			if spells.bloodshed:IsOnCD() then
				OpenerNotify(spells.bloodshed.icon, "On cooldown, AoE opener complete.", 3)
				return true
			end

			spells.bloodshed:Cast(targets.bloodshed)

			return false
		end,
	},
}


local function PLAoEReset()
	return false
end

-- Abort the opener if we're "stuck" in it.
local function PLAoEAbort()
	if CombatTime() > 10 then
		return true
	end

	return false
end

sequences.PLAoE = mint.Sequence:New("PLAoE", PackLeaderAoE, PLAoEReset, PLAoEAbort)

-- * ================================ *
-- * Dark Ranger Opener (ST)
-- * ================================ *

-- Ensure Hunter's Mark is active on the target from you or another Hunter in the group!
-- Use Black Arrow.
-- Use 2x Barbed Shot.
-- Use Bloodshed
-- Use all the Black Arrows you can.
-- Use Call of the Wild alongside your Potion and stat-granting on-use Trinkets.
-- Use all Black Arrows.
-- Use Bestial Wrath.
-- Use Barbed Shot.
-- Use Kill Command.

local DROpener = {
	{
		-- Hunter's Mark (if not present)
		name = "Hunter's Mark",
		func = function(self)
			if not pet:GetExists() then
				OpenerNotify(spells.kill_command.icon, "No pet found, skipping opener.", 3)
				return true
			end

			if not target:GetExists() then return false end

			if not target:IsBoss() then
				return true
			end

			if target:FindDebuff(auras.hunters_mark):Active() then
				OpenerNotify(spells.hunters_mark.icon, "#1: Hunter's Mark active, moving on.", 3)
				return true
			end

			if spells.hunters_mark:IsOnCD() then
				OpenerNotify(spells.hunters_mark.icon, "#1: CD Found, skipping.", 3)
				return true
			end

			spells.hunters_mark:Cast(target)

			return false
		end,
	},
	{
		-- Barbed Shot x2
		name = "Barbed Shot #1",
		func = function(self)
			if not target:GetExists() then
				return false 
			end

			if helpers.blackArrow() then
				spells.black_arrow:Cast(targets.black_arrow)
			end

			if spells.barbed_shot:IsOnCD() then
				OpenerNotify(spells.barbed_shot.icon, "#2: Out of charges, skipping.", 3)
				return true
			end

			spells.barbed_shot:Cast(targets.barbed_shot)

			return false
		end,
	},
	{
		-- Bloodshed
		name = "Bloodshed",
		func = function(self)
			if not target:GetExists() then
				return false 
			end

			if not toggles.cooldowns then
				return true
			end

			if helpers.blackArrow() then
				spells.black_arrow:Cast(targets.black_arrow)
			end

			if not IsPlayerSpell(talents.bloodshed.id) then
				OpenerNotify(spells.bloodshed.icon, "#3: Bloodshed not known, skipping.", 3)
				return true
			end

			if not targets.bloodshed:GetExists() then
				return false 
			end

			if spells.bloodshed:IsOnCD() then
				OpenerNotify(spells.bloodshed.icon, "#3: Bloodshed on CD, moving on.", 3)
				return true
			end

			spells.bloodshed:Cast(targets.bloodshed)

			return false
		end,
	},
	{
		-- Call of the Wild (Potions, trinkets)
		name = "Call of the Wild",
		func = function(self)
			if not toggles.cooldowns then
				OpenerNotify(spells.call_of_the_wild.icon, "#4: CDs toggled off, skipping.", 3)
				return true
			end

			if not target:GetExists() then
				return false 
			end

			if player:FindBuff(auras.call_of_the_wild):Active() then
				OpenerNotify(spells.call_of_the_wild.icon, "#4: CoTW found, moving on.", 3)
				return true
			end

			if spells.call_of_the_wild:IsOnCD() then
				OpenerNotify(spells.call_of_the_wild.icon, "#4: CoTW not available, moving on.", 3)
				return true
			end

			spells.call_of_the_wild:Cast(target)
		end,
	},
	{
		-- Bestial Wrath
		name = "Bestial Wrath",
		func = function(self)
			if not toggles.cooldowns then
				OpenerNotify(spells.bestial_wrath.icon, "#5: CDs toggled off, skipping.", 3)
				return true
			end

			if not target:GetExists() then
				return false 
			end

			if helpers.blackArrow() then
				spells.black_arrow:Cast(targets.black_arrow)
			end

			if player:FindBuff(auras.bestial_wrath):Active() then
				OpenerNotify(spells.bestial_wrath.icon, "#5: Bestial Wrath active, moving on.", 3)
				return true
			end

			if spells.bestial_wrath:IsOnCD() then
				OpenerNotify(spells.bestial_wrath.icon, "#5: Bestial Wrath not available, moving on.", 3)
				return true
			end

			spells.bestial_wrath:Cast(player)
		end,
	},
	{
		-- Barbed Shot
		name = "Barbed Shot #2",
		func = function(self)
			if not target:GetExists() then
				return false 
			end

			if helpers.blackArrow() then
				spells.black_arrow:Cast(targets.black_arrow)
			end

			if spells.barbed_shot:IsOnCD() then
				OpenerNotify(spells.barbed_shot.icon, "#6: Barbed Shot on CD, moving on.", 3)
				return true
			end

			if spells.barbed_shot:TimeSinceLastCast() < mint.max_gcd then
				OpenerNotify(spells.barbed_shot.icon, "#6: Barbed Shot used, moving on.", 3)
				return true
			end

			spells.barbed_shot:Cast(targets.barbed_shot)
			return false
		end,
	},
	{
		-- Kill Command
		name = "Kill Command",
		func = function(self)
			if not target:GetExists() then
				return false 
			end

			if helpers.blackArrow() then
				spells.black_arrow:Cast(targets.black_arrow)
			end

			if spells.kill_command:IsOnCD() then
				OpenerNotify(spells.kill_command.icon, "#7: Kill Command on CD, opener complete.", 3)
				return true
			end

			if spells.kill_command:TimeSinceLastCast() < mint.max_gcd then
				OpenerNotify(spells.kill_command.icon, "#7: Kill Command used, opener complete.", 3)
				return true
			end

			spells.kill_command:Cast(target)
			return false
		end,
	},
}

local function DROpenerReset()
	return false
end

-- Abort the opener if we're "stuck" in it.
local function DROpenerAbort()
	if CombatTime() > 13 then
		return true
	end

	return false
end

sequences.DROpener = mint.Sequence:New("DROpener", DROpener, DROpenerReset, DROpenerAbort)