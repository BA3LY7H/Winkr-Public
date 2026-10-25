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
local Interface 	= mint.Interface
local FriendManager = mint.FriendManager
local toggles 		= mint.data.toggles
local StopTimer 	= mint.data.StopTimer
local MoveTimer 	= mint.data.MoveTimer
local target        = UnitManager:Get("target")
local player        = UnitManager:Get("player")
local none          = UnitManager:Get("none")

--! Addon Locals !--
local fire 			= addon.mage.fire
local spells 		= addon.mage.data["Fire"].spells
local auras 		= addon.mage.data["Fire"].auras
local targets 		= addon.mage.data["Fire"].targets
local vars 			= addon.mage.data["Fire"].vars
local seqs 			= addon.mage.data["Fire"].sequences
local in_flight 	= addon.mage.data["Fire"].in_flight
local settings 		= addon.mage.settings["Fire"]

-- Default off
settings.Flamestrike = false

Interface:AddQuickButton("Spell_fire_selfdestruct", "Flamestrike", "Flamestrike", function()
    settings.Flamestrike = not settings.Flamestrike

    if settings.Flamestrike then
        mint:Log("Mint will now recommend Flamestrike on 5+ targets.")
    else
        mint:Log("Mint will continue to recommend Pyroblast at 5+ targets.")
    end
end)

in_flight = {
	[133] 		= {}, -- Fireball
	[257541] 	= {}, -- Phoenix Flames
	[11366] 	= {}, -- Pyroblast
	[2948] 		= {}, -- Scorch
}

vars.opener = {}

local precasts = {
	[spells.scorch.id] = true,
	[spells.fireball.id] = true,
}

local function GetFlying(spell_id)
	if in_flight[spell_id] then
		return #in_flight[spell_id]
	end

	return 0
end

local function HotStreaksFlying()
	local count = #in_flight[11366] + #in_flight[257541] + #in_flight[133] + #in_flight[2948]

	return count
end


local bracers = mint.Item.New(168989)
local signet = mint.Item.New(219308, { use_name = true })
local temp_pot = mint.Item.New(212264)

local chocolate = mint.Item.New(44791)

-- --! In Flight Tracking !--

local flight_tracking = {
	-- [108853] 		= true, -- Fire Blast
	[133]			= true, -- Fireball
	[257541]		= true, -- Phoenix Flames
	[11366]			= true, -- Pyroblast
	[2948]			= true, -- Scorch
}

mint.CommandMe:Register("resetHS", "reset hot streak flying", function()
	in_flight = {
		[133] 		= {}, -- Fireball
		[257541] 	= {}, -- Phoenix Flames
		[11366] 	= {}, -- Pyroblast
		[2948] 		= {}, -- Scorch
	}
end)

mint.CommandMe:Register("test", "reset hot streak flying", function()
	unlocker.SetCameraZoom(100)
end)

local events = mint.EventManager:New()


local should_shift = vars.should_shift
should_shift = false


events:RegisterWoWEvent("UNIT_SPELLCAST_SUCCEEDED", function(...)
	local unit, castGUID, spellID = ...


	if unit ~= "player" then return end

	if flight_tracking[spellID] then
		table.insert(in_flight[spellID], { guid = castGUID, time = GetTime() })

		local index = #in_flight[spellID]

		C_Timer.After(1, function()
			if in_flight[spellID][index] and in_flight[spellID][index].guid == castGUID then
				-- We only want to reset here if it's still "in flight" after this long, 
				-- meaning the mob died before damage event went off
				in_flight[spellID][index] = nil
			end
		end)
	end

	if spellID == spells.shifting_power.id then
		should_shift = false
	end
end)

local predicted_hot_streak = vars.predicted_hot_streak
predicted_hot_streak = false

function IsCurrentTargetGood()
	if not target:GetExists() then return false end

	-- if target:GetDistanceSquared(player) > (40 * 40) then return false end

	-- if not player:HasLos(target) then return false end

	if Constants.Targets["priority"][target.id] then
		return true
	end

	return true
end


events:RegisterWoWEvent("COMBAT_LOG_EVENT_UNFILTERED", function()
	local args = { CombatLogGetCurrentEventInfo() }
	
	local sub_event = args[2]
	local source_guid = args[4]
	local dest_guid = args[8]
	local spell_id = args[12]
	local value = args[16]

	-- Events that originate from the player
	if UnitGUID("player") == source_guid then
		-- If we just used a spender
		if sub_event == "SPELL_DAMAGE" then
			if flight_tracking[spell_id] then

				if in_flight[spell_id] then
					table.remove(in_flight[spell_id], 1)
					if player:FindBuff(auras.heating_up):Active() then
						local time = GetTime()
						predicted_hot_streak = time
						C_Timer.After(1, function()
							if predicted_hot_streak == time then
								predicted_hot_streak = false
							end
						end)
					end
				end
			end
		end
	end

	if UnitGUID("player") == dest_guid then
		if sub_event == "SPELL_AURA_REMOVED" then
			if spell_id == 48108 or spell_id == 48107 then
				predicted_hot_streak = false
			end

			if spell_id == 383874 then
				should_shift = true
			end
		end
	end
end)

local markers = {
	[0] = "None",
	[1] = "Star",
	[2] = "Circle",
	[3] = "Diamond",
	[4] = "Triangle",
	[5] = "Moon",
	[6] = "Square",
	[7] = "Cross",
	[8] = "Skull",
}

local Draw = mint.Draw:New()

local trash = mint.Spell.New(461536)
local gameObjects = mint.Objects(8)
local areaTriggers = 

Draw:Sync(function(draw)
	FriendManager:LoopRaw(function(friend)
		if friend:FindDebuff(trash):Active() then
			local pos = friend:GetPosition()
			local marker = GetRaidTargetIndex(friend:GetPointer()) and GetRaidTargetIndex(friend:GetPointer()) or 0
			local markerStr =  marker and ("{rt" .. marker .. "}") or ""
			local str = friend.name .. " " .. markerStr
			draw:Text(str, "GameFontNormal", pos.x, pos.y, pos.z + 2)
		end
	end)

	for _, obj in ipairs(gameObjects) do
		local name = UnitName(obj)
		local x, y, z = mint.ObjectPosition(obj)
		if x and y and z then
			draw:Text(name, "GameFontNormal", x, y, z + 2)
		end

	end

	for _, obj in ipairs(mint.Objects(11)) do
		local id = unlocker.ObjectID(obj)
		local x, y, z = mint.ObjectPosition(obj)
		if x and y and z then
			if id == 36993 then
				draw:Text("Discarded Doomsplosive", "GameFontNormal", x, y, z + 2)
			end
		end
	end


	-- mint.ObjectManager.enemies:each(function(enemy)
    --     enemy:Update()
	-- 	if not enemy:GetExists() then return false end
	-- 	-- if enemy:GetName() ~= "Discarded Doomsplosive" then return false end

	-- 	local pos = enemy:GetPosition()
	-- 	draw:Text(enemy.name, "GameFontNormal", pos.x, pos.y, pos.z + 2)
    -- end)
end)

Draw:Enable()

-- local ObjectTrackedInQuest = unlocker.ObjectTrackedInQuest

-- local Draw = mint.Draw:New()

-- local races = {
-- 	["Blood Elf"] = true,
-- 	["Draenei"] = false,
-- 	["Dwarf"] = false,
-- 	["Gnome"] = false,
-- 	["Goblin"] = true,
-- 	["Human"] = false,
-- 	["Night Elf"] = false,
-- 	["Orc"] = true,
-- 	["Tauren"] = true,
-- 	["Troll"] = true,
-- 	["Undead"] = true,
-- 	["Worgen"] = false,
-- }

-- Draw:Sync(function(draw)
-- 	local objects = mint.Objects(8)

--     for _, object in pairs(objects) do
--         local name = mint.ObjectName(object)

-- 		-- if name == "Brightly Colored Egg" then
--         --     local x, y, z = mint.ObjectPosition(object)
--         --     local pos = mint.Vector3:New(x, y, z)
-- 		-- 	draw:Text("egg", "GameFontNormal", pos.x, pos.y, pos.z)
--         -- end

-- 		local should_draw, additional_text = ObjectTrackedInQuest(object)
-- 		if should_draw then
-- 			local x, y, z = mint.ObjectPosition(object)
-- 			local str = mint.ObjectName(object) .. (additional_text or "")
-- 			draw:Text(str, "GameFontNormal", x, y, z + 2)
-- 		end

--         if UnitName(object) == "Mislaid Curiosity" and mint.ObjectLootable(object) then
-- 			local x, y, z = mint.ObjectPosition(object)
-- 			draw:Text("MC", "GameFontNormal", x, y, z + 2)
--         end
--     end

-- 	local players = mint.Objects(6)
-- 	for _, object in pairs(players) do
        
--         local race = UnitRace(object)

-- 		if races[race] then
-- 			local x, y, z = mint.ObjectPosition(object)
--             local pos = mint.Vector3:New(x, y, z)
-- 			draw:Text(race, "GameFontNormal", pos.x, pos.y, pos.z)
-- 		end
--     end
-- end)

-- Draw:Enable()

-- local Interact = C_PlayerInteractionManager.InteractUnit

-- C_Timer.NewTicker(1, function()
-- 	local objects = mint.Objects(8)
--     local mx, my, mz = mint.ObjectPosition("player")
--     local ppos = mint.Vector3:New(mx, my, mz)

--     for _, object in pairs(objects) do
--         local name = mint.ObjectName(object)

--         if name == "Brightly Colored Egg" then
--             local x, y, z = mint.ObjectPosition(object)
--             local pos = mint.Vector3:New(x, y, z)

--             if pos:Distance(ppos) < 5 and not player:IsCastingOrChanneling() then
--                 Interact(object)
--             end
--         end
--     end
-- end)



fire:Sync(function()

	local use_cds = mint.data.toggles.cooldowns
	local use_kicks = mint.data.toggles.kicks
	local use_defs = mint.data.toggles.defensives
	-- if not vars.opener.phoenix then
	-- 	if spells.phoenix_flames:WasLastCast() then
	-- 		vars.opener.phoenix = true
	-- 	end
	-- end

	-- if not vars.opener.pyroblast or not vars.opener.phoenix then
	-- 	if player:GetCastSpellID() == spells.pyroblast.id then
	-- 		vars.opener.pyroblast = true
	-- 	else
	-- 		spells.pyroblast("Opener")
	-- 	end
	-- 	spells.phoenix_flames("Opener")
	-- end

	--------------------------
	-- OOC Utility
	--------------------------

	--------------------------
	-- High Priority Actions
	--------------------------
	-- Cancel Shifting Power after next tick if Combust/Hyperthermia procs/is available

	if player:GetCastSpellID() == spells.pyroblast.id then
		SpellStopCasting()
	end

	if player:GetCastSpellID() == spells.flamestrike.id then
		SpellStopCasting()
	end

	--------------------------
	-- Opener
	--------------------------
	-- For the opener, we only need pre-pyro into phoenix flames
	-- After that, it's just your typical combustion setup

	-- Pre-cast Pyroblast with < 3 seconds on pull timer
	-- spells.pyroblast("Opener")
	-- Queue Phoenix Flames
	-- spells.phoenix_flames("Opener")

	if player:IsInCombat() then
		--------------------------
		-- Combustion Setup
		--------------------------
		-- Scorch (Fireball at 104% Haste+)
		-- Cast Combustion 75% of the way through the cast
		-- Cast Fire Blast if we do not have Hot Streak
		-- Pyroblast
		-- Pyroblast

		spells.counterspell("kick")

		if not target:GetExists() or UnitCanAssist("player", target:GetPointer()) or UnitIsDeadOrGhost(target:GetPointer()) then
			SmartTarget:Acquire()
		end

		-- If tank is still grouping stuff, we want to continue evaluating for targets
		if GetTime() - mint.combatStartTime < 5 and not IsCurrentTargetGood() then
			SmartTarget:Acquire()
		end

		-- We don't want to be spamming spellsteal
		if spells.spellsteal:TimeSinceLastCast() > 5 then
			spells.spellsteal()
		end

		-- This handles Scorch, Combust, FB, Pyro x2
		if use_cds and (spells.combustion.ready or seqs.combustion_setup:IsRunning()) then
			seqs.combustion_setup:Execute()
			return
		end

		-- Decurse
		if player:FindDebuff(auras.devouring_rift):Active() and player:FindDebuff(auras.devouring_rift):Remains() < 3 then
			spells.remove_curse("devRift")
		end

		--------------------------
		-- Combustion Priority
		--------------------------
		if player:FindBuff(auras.combustion):Active() then

			-- At this point just send them here as well.
			if not signet:HasCooldown() then
				signet:Use(player)
			end

			if not temp_pot:HasCooldown() then
				temp_pot:Use(player)
			end

			-- Hyperthermia during combust??
			-- Hyperthermia Active:
			if player:FindBuff(auras.hyperthermia):Active() then
				-- Heating Up active:
				if player:FindBuff(auras.heating_up):Active() then
					-- Fire Blast if it will be capped within 2 GCDs
					spells.fire_blast("HYP, Cap")
					-- Fire Blast if Feel the Burn will fall off within 2 GCDs
					spells.fire_blast("HYP, FTB")
				end

				-- Spam Spender
				if target:GetEnemies(9) >= 5 and settings.Flamestrike then
					spells.flamestrike("Hyperthermia")
				else
					spells.pyroblast("Hyperthermia")
				end
				return
			else
				if spells.fire_blast:WasXOfYMostRecent(2, 3) and spells.fire_blast.charges_frac < 1 then
					-- print("CD:", bracers:HasCooldown(), "FB:", spells.fire_blast:TimeSinceLastAttempt())
					if not bracers:HasCooldown() then
						-- print("Should be using bracers")
						bracers:Use(player)
					end
				end

				-- Spend Hot Streak
				if player:FindBuff(auras.hot_streak):Active()
				or (player:FindBuff(auras.heating_up):Active() and (HotStreaksFlying() > 0))
				or predicted_hot_streak then
					-- Pyroblast
					if target:GetEnemies(9) >= 5 and settings.Flamestrike then
						spells.flamestrike("Hot Streak")
					else
						spells.pyroblast("Hot Streak")
					end
				else
					-- Generate Hot Streak
					-- Scorch if target is < 30% HP and Imp. Scorch has < 4 seconds remaining
					spells.scorch("Combust, Execute")
					-- Scorch if Heat Shimmer proc'd
					spells.scorch("Combust, Heat Shimmer")
					-- Fire Blast
					spells.fire_blast("Combust")
					-- Phoenix Flames
					spells.phoenix_flames("Combust")

					-- Scorch (Fireball at 104% Haste+)
					if UnitSpellHaste("player") >= 104 and not player:IsMoving() then
						spells.fireball("Combust")
					else
						spells.scorch("Combust")
					end
				end
			end
		else

			-- Decurse
			if player:FindDebuff(auras.devouring_rift):Active() then
				spells.remove_curse("devRift")
			end
			
			if toggles.dispels then spells.remove_curse("help") end
			
			-- Defensives to react to events

			-- Hyperthermia Active:
			if player:FindBuff(auras.hyperthermia):Active() then
				-- Heating Up active:
				if player:FindBuff(auras.heating_up):Active() then
					-- Fire Blast if it will be capped within 2 GCDs
					spells.fire_blast("HYP, Cap")
					-- Fire Blast if Feel the Burn will fall off within 2 GCDs
					spells.fire_blast("HYP, FTB")
				end

				-- Spam Spender
				if target:GetEnemies(9) >= 5 and settings.Flamestrike then
					spells.flamestrike("Hyperthermia")
				else
					spells.pyroblast("Hyperthermia")
				end
			else

				if (should_shift or not IsPlayerSpell(383860)) and StopTimer:GetTime() > 0.5 and spells.combustion:GetRemainingCD() > 8 then
					spells.shifting_power()
				end
				
				if player:GetCastSpellID() == spells.shifting_power.id then
					-- Fire Blast during Shifting Power if it will be capped next tick of SP
					spells.fire_blast("Shifting Power")
				end



				if not player:IsChanneling() then
					-- Spend Hot Streak
					if player:FindBuff(auras.hot_streak):Active()
					or (player:FindBuff(auras.heating_up):Active() and (HotStreaksFlying() > 0))
					or predicted_hot_streak then
						-- print(player:FindBuff(auras.hot_streak):Active() and "Hot Streak" or "", (player:FindBuff(auras.heating_up):Active() and (HotStreaksFlying() > 0)) and "Heating Up" or "", predicted_hot_streak and "Predicted Hot Streak" or "")
						-- Pyroblast
						if target:GetEnemies(9) >= 5 and settings.Flamestrike then
							spells.flamestrike("Hot Streak")
						else
							spells.pyroblast("Hot Streak")
						end
					else
						-- Fire Blast with Heating Up while casting Scorch/Fireball
						spells.fire_blast("MidCast")

						-- Scorch if target is < 30% HP and Imp. Scorch has < 4 seconds remaining
						spells.scorch("Execute, Refresh")
						-- Scorch if Heat Shimmer proc
						spells.scorch("Heat Shimmer, Refresh")
						-- Phoenix Flames
						spells.phoenix_flames()
						-- Scorch (Execute)
						spells.scorch("Execute")
						
						-- If we are not moving
						if not player:IsMoving() then
							-- Fireball
							spells.fireball()
						else
							-- Blazing Barrier
							spells.blazing_barrier()
							-- Scorch
							spells.scorch("Filler")
						end
					end
				end
			end
		end

		--------------------------
		-- Outside of Combustion
		--------------------------
		-- Hyperthermia
			-- Heating Up active:
				-- Fire Blast if it will be capped within 2 GCDs
			-- Pyroblast
		-- Pyroblast with Hot Streak
		-- Fire Blast with Heating Up while casting Scorch/Fireball
		-- Fire Blast during Shifting Power if it will be capped next tick of SP
		-- Shifting Power when Hyperthermia fades
			-- We want to send a phoenix flames or fire blast before perhaps?
		-- If Improved Scorch is not up/about to fall:
			-- Scorch if target is below 30% hp
			-- Scorch if we have Heat Shimmer proc
		-- Phoenix Flames
		-- Scorch if target is below 30%
		-- Fireball (if not moving)
	else -- Out of combat
		if not player:IsCastingOrChanneling() and not player:IsSitting() and not IsMounted() then
			spells.blazing_barrier()
		end
	end
end)

------------------------------
--- Sequences
------------------------------

local checkme = false
local CombustionSetup = {
	{
		-- The initial hardcast to set up the double pyro
		name = "Scorch/Fireball",
		func = function(self)
			if not target:GetExists() then return false end

			if not signet:HasCooldown() then
				signet:Use(player)
			end

			if not temp_pot:HasCooldown() then
				temp_pot:Use(none)
			end

			if not IsCurrentTargetGood() then
				SmartTarget:Acquire()
			end

			-- If we're casting one of these already, move on
			if precasts[player:GetCastSpellID()] then
				return true
			end

			-- We want to cast Fireball above 104% haste
			if UnitSpellHaste("player") >= 104 and not player:IsMoving() then
				spells.fireball:Cast(target)
			else
				spells.scorch:Cast(target)
			end

			return false
		end,
	},
	{
		-- Combust during the cast
		name = "Send Combustion",
		func = function(self)
			if not target:GetExists() then return false end
			checkme = false

			-- We want to send it near the end of the cast
			if player:TimeToCast() > 0.7 then
				return false
			end

			return spells.combustion:Cast(player)
		end,
	},
	{
		-- Fire blast if we don't have hot streak
		name = "Fire Blast",
		func = function(self)
			if not target:GetExists() then return false end

			if spells.fire_blast:TimeSinceLastAttempt() < 0.5 then
				return true
			end

			if player:FindBuff(auras.hot_streak):Active() then
				return true
			else
				return spells.fire_blast:Cast(target)
			end
		end,
	},
	{
		-- Queue the first pyroblast
		name = "Pyroblast 1",
		func = function(self)
			if not target:GetExists() then return false end

			-- We don't want to move on until we've casted the first pyro
			if self.cast_history[spells.pyroblast.id] then
				local last_cast = self.cast_history[spells.pyroblast.id]
				local time_since_cast = GetTime() - last_cast

				if time_since_cast < 1 then
					self.cast_history[spells.pyroblast.id] = nil
					return true
				end
			end

			spells.pyroblast:Cast(target)
			checkme = false

			return false
		end,
	},
	{
		-- Cast the second pyroblast
		name = "Pyroblast 2",
		func = function(self)
			if not target:GetExists() then return false end

			-- We don't want to move on until we've casted the first pyro
			if self.cast_history[spells.pyroblast.id] then
				local last_cast = self.cast_history[spells.pyroblast.id]
				local time_since_cast = GetTime() - last_cast

				if time_since_cast < 1 then
					return true
				end
			end

			spells.pyroblast:Cast(target)

			if spells.pyroblast:GetCastTime() > 0.5 then
				-- this means we probably fucked up
				if not self.counter then 
					self.counter = 0
				end
				self.counter = self.counter + 1
				if self.counter > 4 then
					self.counter = nil
					return true
				end
				return false
			end

			return false
		end,
	}
}

local function CombustReset()
	return false
end

local function CombustAbort()
	if not player:FindBuff(auras.combustion):Active()
	and not spells.combustion.ready then
		return true
	end
end

seqs.combustion_setup = mint.Sequence:New("CombustSetup", CombustionSetup, CombustReset, CombustAbort)

local TrackerFrame = _G.CreateFrame("Frame")
local FireFrame = _G.CreateFrame("Frame", "FireMageFrame", _G.UIParent, "DefaultPanelFlatTemplate")
FireFrame:SetSize(200, 50) -- Start with a minimal height that will grow
FireFrame:SetPoint("CENTER")
FireFrame.TitleContainer.TitleText:SetText("Fire Mage")

FireFrame:SetMovable(true)
FireFrame:EnableMouse(true)
FireFrame:RegisterForDrag("LeftButton")
FireFrame:SetScript("OnDragStart", FireFrame.StartMoving)
FireFrame:SetScript("OnDragStop", FireFrame.StopMovingOrSizing)

local data_row_count = 0
local data_rows = {}
local ROW_HEIGHT = 40
local PADDING = 20
local HEADER_HEIGHT = 10

-- Function to update the frame height based on rows
local function UpdateFrameHeight()
    local contentHeight = HEADER_HEIGHT + (data_row_count * ROW_HEIGHT) + PADDING
    FireFrame:SetHeight(contentHeight)
end

local function AddDataRow(title, callback)
    local yOffset = -HEADER_HEIGHT - (data_row_count * ROW_HEIGHT)
    
    -- Create the label with the provided title
    local label = FireFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    label:SetPoint("TOPLEFT", FireFrame.NineSlice.TopLeftCorner, "LEFT", 20, yOffset)
    label:SetText(title)
    
    -- Create the value text that will be updated by the callback
    local text = FireFrame:CreateFontString(nil, "OVERLAY", "WhiteNormalNumberFont")
    text:SetPoint("TOPLEFT", label, "BOTTOMLEFT", 5, -5)
    text:SetText("---") -- Default placeholder
    
    -- Store the information for this row
    data_row_count = data_row_count + 1
    data_rows[data_row_count] = {
        label = label,
        text = text,
        callback = callback
    }
    
    -- Update the frame height to accommodate the new row
    UpdateFrameHeight()
    
    -- Return the text object in case you want to do additional customization
    return text
end

-- Example usage for your existing indicators
-- AddDataRow("Fireball", function()
--     return tostring(GetFlying(spells.fireball.id))
-- end)

-- AddDataRow("Phoenix Flames", function()
--     return tostring(GetFlying(spells.phoenix_flames.id))
-- end)

AddDataRow("Pyroblast", function()
    return tostring(GetFlying(spells.pyroblast.id))
end)

-- AddDataRow("Scorch", function()
--     return tostring(GetFlying(spells.scorch.id))
-- end)

-- AddDataRow("IB Recharge", function()
--     return tostring(spells.fire_blast:GetFullRechargeTime())
-- end)

-- AddDataRow("PF Recharge", function()
--     return tostring(spells.phoenix_flames:GetFullRechargeTime())
-- end)

local ticker = 0
TrackerFrame:SetScript("OnUpdate", function(self, elapsed)
    ticker = ticker + elapsed
    
    -- Only update every 0.1 seconds to reduce performance impact
    if ticker < 0.1 then return end
    ticker = 0
    
    -- Update all the data rows with their respective callbacks
    for i, row in ipairs(data_rows) do
        local value = row.callback()
        row.text:SetText(value)
    end
end)

-- FireFrame:Hide()