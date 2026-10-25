local unlocker,
---@class mint
---@field max_gcd number
---@field gcd number
---@field class string
---@field specId number
---@field specName string
mint = ...

------------------------------
--- Localize Variables
------------------------------
local Constants 		= mint.Constants
local Command           = mint.Command
local Interface 		= mint.Interface
local UnitManager 		= mint.UnitManager
local FriendManager 	= mint.FriendManager
local ObjectManager 	= mint.ObjectManager
local Keybinds 			= mint.Keybinds
local Events 			= mint.EventManager.New()
local Queue 			= mint.Queue
local Utility 			= mint.Utility
local settings 			= mint.Settings
local FlightTracked 	= {}
mint.events = Events

mint.combatStartTime = 0
------------------------------
--- Main mint metatable
------------------------------

function mint.bin(arg)
	return arg and 1 or 0
end

------------------------------
--- Custom Events (Toggles)
------------------------------

Events:RegisterEvent("toggle", function()
	mint.data.toggles.engine = not mint.data.toggles.engine

	mint:Log((mint.data.toggles.engine and "Enabled." or "Disabled."))
end)

Events:RegisterEvent("cooldowns", function()
	mint.data.toggles.cooldowns = not mint.data.toggles.cooldowns

	mint:Log((mint.data.toggles.cooldowns and "CDs Enabled." or "CDs Disabled."))
end)

Events:RegisterEvent("kicks", function()
	mint.data.toggles.kicks = not mint.data.toggles.kicks

	mint:Log((mint.data.toggles.kicks and "Kicks Enabled." or "Kicks Disabled."))
end)

Events:RegisterEvent("dispels", function()
	mint.data.toggles.dispels = not mint.data.toggles.dispels

	mint:Log((mint.data.toggles.dispels and "Dispels Enabled." or "Dispels Disabled."))
end)

Events:RegisterEvent("purges", function()
	mint.data.toggles.purges = not mint.data.toggles.purges

	mint:Log((mint.data.toggles.purges and "Purges Enabled." or "Purges Disabled."))
end)

Events:RegisterEvent("defensives", function()
	mint.data.toggles.defensives = not mint.data.toggles.defensives

	mint:Log((mint.data.toggles.defensives and "Defensives Enabled." or "Defensives Disabled."))
end)

Events:RegisterEvent("optionsToggle", function()
	local window = Interface.window

	if window:IsVisible() then
		window:Hide()
		-- mint:Log("Options hidden.")
	else
		window:Show()
		-- mint:Log("Options opened.")
	end
end)

Events:RegisterEvent("quickbarToggle", function()
	local quickbar = Interface.quickbar

	if quickbar:IsVisible() then
		quickbar:Hide()
		-- mint:Log("Options hidden.")
	else
		quickbar:Show()
		-- mint:Log("Options opened.")
	end
end)

Events:RegisterEvent("BuildOptions", function()
	mint.console.log("Attempting to build interface options.")
	mint.Interface:BuildOptions()
end)

Events:RegisterEvent("BuildQuickbar", function()
	mint.console.log("Attempting to build quickbar.")
	mint.Interface:BuildQuickbar()
end)

Events:RegisterEvent("consoleToggle", function()
	local console = mint.console

	if console:IsVisible() then
		console:Hide()
		-- mint:Log("Console hidden.")
	else
		console:Show()
		-- mint:Log("Console opened.")
	end
end)

------------------------------
--- /mint Commands
------------------------------

local Commands = mint.Command:New("mint")

Commands:Register("options", "Toggle visibility of the Options panel.", function()
	Events:TriggerEvent("optionsToggle")
end)

Commands:Register("qb", "Toggle visibility of the Quick Bar.", function()
	Events:TriggerEvent("quickbarToggle")
end)

Commands:Register("console", "Toggle visibility of the dev console.", function()
	Events:TriggerEvent("consoleToggle")
end)

-- Generates MDT data for stunnable etc mobs
Commands:Register("mdt", "Dump seasonal MDT data", function()
	for _, dungeon in pairs(_G.MDT.dungeonEnemies) do
		for _, unit in pairs(dungeon) do
			if unit.characteristics then
				local Disorient = unit.characteristics["Disorient"] or false
				local Grip = unit.characteristics["Grip"] or false
				local Fear = unit.characteristics["Fear"] or false
				local Root = unit.characteristics["Root"] or false
				local Silence = unit.characteristics["Silence"] or false
				local Slow = unit.characteristics["Slow"] or false
				local Stun = unit.characteristics["Stun"] or false
				local Taunt = unit.characteristics["Taunt"] or false
				local Incapacitate = unit.characteristics["Incapacitate"] or false

				-- check spells for interruptible
				local Interruptible = false
				if unit.spells then
					for _, spell in pairs(unit.spells) do
						if spell.interruptible then
							Interruptible = true
							break
						end
					end
				end

				local out = "[" .. unit.id .. "] = {"
					.. "['Disorient'] = " .. tostring(Disorient) .. ", "
					.. "['Grip'] = " .. tostring(Grip) .. ", "
					.. "['Fear'] = " .. tostring(Fear) .. ", "
					.. "['Root'] = " .. tostring(Root) .. ", "
					.. "['Silence'] = " .. tostring(Silence) .. ", "
					.. "['Slow'] = " .. tostring(Slow) .. ", "
					.. "['Stun'] = " .. tostring(Stun) .. ", "
					.. "['Taunt'] = " .. tostring(Taunt) .. ", "
					.. "['Incapacitate'] = " .. tostring(Incapacitate) .. ", "
					.. "['Interruptible'] = " .. tostring(Interruptible)
					.. "},\n"

				mint.WriteFile("MDT.lua", out, true)
			end
		end
	end
end)

Commands:Register("spells", "Dumps all known spells to file in a usable format.", function()
     local spells = {}
     local rand = math.random(100000, 999999)
     local num_tabs = C_SpellBook.GetNumSpellBookSkillLines()
     local filename = 'spells-' .. UnitClass("player") .. '-' .. rand .. '.lua'
     mint.WriteFile(filename, "local spells = {", true)
     for i = 2, num_tabs do
         local info = C_SpellBook.GetSpellBookSkillLineInfo(i)
         local offset = info.itemIndexOffset
         local slots = info.numSpellBookItems
         for j = offset + 1, offset + slots do
             local spell_info = C_SpellBook.GetSpellBookItemInfo(j, 0)
             -- We don't want to track passive spells
             if not spell_info.isPassive then
                 local name = spell_info.name
                 local id = spell_info.spellID
                 local snake_case_name = string.lower(name):gsub("[%p]", ""):gsub("[%s']", "_")
                 if not spells[snake_case_name] then
                     spells[snake_case_name] = id
                 end
             end
         end
     end -- Sort the spell names alphabetically
     local sorted_spell_names = {}
     for spell_name in pairs(spells) do
         table.insert(sorted_spell_names, spell_name)
     end
     table.sort(sorted_spell_names) -- Write the sorted spells to the file
     for _, spell_name in ipairs(sorted_spell_names) do
         mint.WriteFile(filename, "\n\t" .. spell_name .. " = Spell(" .. spells[spell_name] .. "),", true)
     end
     mint.WriteFile(filename, "\n}", true)
end)


Commands:PrintHelp()

mint.CommandMe = Commands

------------------------------
--- Utility Indicators
------------------------------

local Draw = mint.Draw:New()

Draw:Sync(function(draw)

	local player = UnitManager:Get("player")
	if not player then return end

	if settings.profile.general.player_indicator then
		Utility:DrawFacingArrow(draw, player)
	end

end)

Draw:Enable()

local DrawPlayerTracking = mint.Draw:New()

DrawPlayerTracking:Sync(function(draw)
	if not settings.profile.general.track_players then return false end

	for i = 1, #settings.profile.general.tracked_players do
		local guid = settings.profile.general.tracked_players[i]
		Utility:DrawCircleByGUID(draw, guid)
	end
end)

DrawPlayerTracking:Enable()

------------------------------
--- Game Object Indicators
------------------------------

-- Tracked game objects: [entryID] = { name, color {r,g,b} }
local TRACKED_OBJECTS = {
	[584752] = { name = "Mislaid Curiosity", color = {255, 215, 0}, no_loot_check = true },
	[618277] = { name = "Sturdy Chest",      color = {0, 200, 255}, no_loot_check = true },
	[618289] = { name = "Sturdy Chest",      color = {0, 200, 255}, no_loot_check = true },
	[618276] = { name = "Sturdy Chest",      color = {0, 200, 255}, no_loot_check = true },
	[516932] = { name = "Tranquility Bloom", color = {0, 255, 0},   no_loot_check = true },
	[516967] = { name = "Lightfused Tranquility Bloom", color = {0, 255, 0},   no_loot_check = true },
	[516934] = { name = "Sanguithorn",      color = {0, 255, 0},   no_loot_check = true },
	[516935] = { name = "Azeroot",          color = {0, 255, 0},   no_loot_check = true },
	[516965] = { name = "Lightfused Azeroot", color = {0, 255, 0},   no_loot_check = true },
	[516936] = { name = "Argentleaf",       color = {0, 255, 0},   no_loot_check = true },
	[516964] = { name = "Lightfused Argentleaf", color = {0, 255, 0},   no_loot_check = true },
	[516937] = { name = "Mana Lily",        color = {0, 255, 0},   no_loot_check = true },
	[524808] = { name = "Rich Soil",        color = {0, 255, 0},   no_loot_check = true },
	[523281] = { name = "Refulgent Copper", color = {255, 0, 0},   no_loot_check = true },
	[523284] = { name = "Lightfused Refulgent Copper", color = {255, 0, 0},   no_loot_check = true },
	[523295] = { name = "Brilliant Silver", color = {255, 0, 0},   no_loot_check = true },
	[523288] = { name = "Umbral Tin",      color = {255, 0, 0},   no_loot_check = true },
	[523283] = { name = "Refulgent Copper Seam", color = {255, 0, 0}, no_loot_check = true },
	[523300] = { name = "Wild Brilliant Silver", color = {255, 0, 0}, no_loot_check = true },
	[516970] = { name = "Wild Azeroot",          color = {0, 255, 0},   no_loot_check = true },
	[523286] = { name = "Wild Refulgent Copper", color = {255, 0, 0},   no_loot_check = true },
	[523292] = { name = "Wild Umbral Tin",      color = {255, 0, 0},   no_loot_check = true },
	[516968] = { name = "Wild Tranquility Bloom", color = {0, 255, 0},   no_loot_check = true },
	[516971] = { name = "Wild Argentleaf",       color = {0, 255, 0},   no_loot_check = true },
	[523282] = { name = "Rich Refulgent Copper", color = {255, 0, 0},   no_loot_check = true },
	[516987] = { name = "Lush Sanguithorn",     color = {0, 255, 0},   no_loot_check = true },
	[516969] = { name = "Wild Sanguithorn",     color = {0, 255, 0},   no_loot_check = true },
	[523298] = { name = "Brilliant Silver Seam", color = {255, 0, 0},   no_loot_check = true },
	[516985] = { name = "Lush Argentleaf",       color = {0, 255, 0},   no_loot_check = true },
	[516986] = { name = "Lush Azeroot",          color = {0, 255, 0},   no_loot_check = true },
	[523301] = { name = "Voidbound Brilliant Silver", color = {255, 0, 0},   no_loot_check = true },
	[516972] = { name = "Wild Mana Lilly",        color = {0, 255, 0},   no_loot_check = true },
}

local DrawGameObjects = mint.Draw:New()

DrawGameObjects:Sync(function(draw)
	local count = winkr_GetObjectCount()
	for i = 0, count - 1 do
		local guid = winkr_GetObjectWithIndex(i)
		if guid then
			local ok, objType = pcall(winkr_ObjectType, guid)
			if ok and objType == 8 then -- GameObject
				-- Skip invalid/despawned objects
				local valid, isValid = pcall(winkr_IsValidObject, guid)

				if valid and isValid then
					local ok2, objId = pcall(winkr_ObjectID, guid)
					if ok2 and TRACKED_OBJECTS[objId] then
						local info = TRACKED_OBJECTS[objId]
						
						-- Conditional Lootable Check:
						-- Chests/Curiosities need to disappear after looting.
						-- Gathering nodes (Herbs/Ores) skip this check to remain visible.
						local loot, isLootable = pcall(winkr_ObjectLootable, guid)
						
						if info.no_loot_check or (loot and isLootable) then
							local ok3, x, y, z = pcall(winkr_ObjectPosition, guid)
							if ok3 and x and y and z then
								local c = info.color
								-- Circle at object
								draw:SetColor(c[1], c[2], c[3], 255)
								draw:SetWidth(2)
								draw:Circle(x, y, z, 1.5, 32)
								-- Label above
								draw:Text(info.name, GameFontNormalLarge, x, y, z + 2)
							end
						end
					end
				end
			end
		end
	end
end)

DrawGameObjects:Enable()


-- Diagnostic: /mint scan — logs all nearby GameObjects with ID, name, distance
Commands:Register("scan", "Scan and list all nearby GameObjects.", function()
	mint.console.log("|cFFFFD700[Scan]|r Scanning GameObjects...")
	local px, py, pz = UnitPosition("player")
	local count = winkr_GetObjectCount()
	local found = 0

	for i = 0, count - 1 do
		local guid = winkr_GetObjectWithIndex(i)
		if guid then
			local ok, objType = pcall(winkr_ObjectType, guid)
			if ok and objType == 8 then
				local ok2, objId = pcall(winkr_ObjectID, guid)
				local ok3, x, y, z = pcall(winkr_ObjectPosition, guid)
				local ok4, name = pcall(winkr_ObjectName, guid)

				local dist = "?"
				if ok3 and x and px then
					local dx, dy, dz = x - px, y - py, z - pz
					dist = string.format("%.1f", math.sqrt(dx*dx + dy*dy + dz*dz))
				end

				mint.console.log("|cFF00BFFF[GO]|r ID=" .. tostring(ok2 and objId or "?")
					.. "  Name=" .. tostring(ok4 and name or "?")
					.. "  Dist=" .. dist .. "yd"
					.. "  GUID=" .. tostring(guid))
				found = found + 1
			end
		end
	end

	mint.console.log("|cFFFFD700[Scan]|r Found " .. found .. " GameObjects.")
end)


------------------------------
--- WoW API Events
------------------------------

-- Track combat time to accurately determine in-combat units.
Events:RegisterWoWEvent("COMBAT_LOG_EVENT_UNFILTERED", function()
	if not CombatLogGetCurrentEventInfo then return end
	local args = { CombatLogGetCurrentEventInfo()}

	local timestamp = args[1]
	local event = args[2]
	local source_guid = args[4]
	local dest_guid = args[8]
	local dest_name = args[9]
	local spell_id = args[12]
	local spell_name = args[13]

	local source = UnitManager[source_guid]
	local dest = UnitManager[dest_guid]

	local time = GetTime()

	if source then
		source:UpdateCombatTimer(time)
	end

	if dest then
		-- Make sure this spell isn't an out of combat spell to skip a mob
		if spell_id and Constants.IgnoreSpells[spell_id] then return end
		dest:UpdateCombatTimer(time)
	end

	if event == "SPELL_AURA_REMOVED" and UnitExists(args[9]) then
		if UnitCanAssist("player", args[9]) then
			local unit = UnitManager:GetUnitByGUID(dest_guid)
			if unit then
				-- print("Removed", spell_name, "from", dest_name, GetTime(), timestamp)
				if unit.auras[spell_name] then
					unit.auras[spell_name] = nil
				end

				if unit.auras[spell_id] then
					unit.auras[spell_id] = nil
				end
			end

			for i = 1, #FriendManager.units do
				local unit = FriendManager.units[i]

				if unit.guid == dest_guid then
					-- print("Removed", spell_name, "from FRIEND", dest_name, GetTime(), timestamp)
					if unit.auras[spell_name] then
						unit.auras[spell_name] = nil
					end
					if unit.auras[spell_id] then
						unit.auras[spell_id] = nil
					end
					break
				end
			end
		else
			local unit = UnitManager:GetUnitByGUID(dest_guid)
			if unit then
				if unit.auras[spell_name] then
					unit.auras[spell_name] = nil
				end

				if unit.auras[spell_id] then
					unit.auras[spell_id] = nil
				end
			end
		end
	end

	-- If player is the source
	if source_guid == UnitGUID("player") then
		local ability = FlightTracked[spell_id]
		if ability then
			if event == "SPELL_CAST_START" then
				local _, _, _, start, finish = UnitCastingInfo("player")

				if start and finish and ability.velocity and ability.velocity > 0 then
					local player = UnitManager:Get("player")
					if player and player:GetExists() then
						local travel = start + 0.05 + (player:GetDistance(dest) / ability.velocity)
						-- "Start" of projectile is cast finish
						Queue:AddEvent(ability.impactSpell or ability.id, finish / 1000, travel, "PROJECTILE_IMPACT", dest_guid)
					end
				end
			elseif event == "SPELL_CAST_FAILED" then
				-- Remove the event if it was added
				Queue:RemoveEvent(ability.impactSpell or ability.id, "PROJECTILE_IMPACT", true)
			elseif event == "SPELL_CAST_SUCCESS" then
				if not Queue:IsInFlight(ability.impactSpell or ability.id) then
					if ability.velocity and ability.velocity > 0 then
						local player = UnitManager:Get("player")
						if player and player:GetExists() then
							local travel = 0.05 + (player:GetDistance(dest) / ability.velocity)
							-- "Start" of projectile is cast finish
							Queue:AddEvent(ability.impactSpell or ability.id, GetTime(), travel, "PROJECTILE_IMPACT", dest_guid)
						end
					end
				end

			elseif event == "SPELL_DAMAGE" then
				-- Remove the event if it was added
				Queue:RemoveEvent(ability.impactSpell or ability.id, "PROJECTILE_IMPACT", true)
			end
		end
	end
end)

Events:RegisterWoWEvent("UNIT_SPELLCAST_DELAYED", function(unitID, castGUID, spellID)
	if unitID == "player" then
		local ability = FlightTracked[spellID]

		if ability then
			Queue:RemoveEvent(ability.impactSpell or ability.id, "PROJECTILE_IMPACT", true)
			local _, _, _, start, finish = UnitCastingInfo("player")
			local player = UnitManager:Get("player")
			local target = UnitManager:Get("target")

			if start and finish and player and target and target:GetExists() and ability.velocity and ability.velocity > 0 then
				local travel = start + 0.05 + (player:GetDistance(target) / ability.velocity)
				Queue:AddEvent(ability.impactSpell or ability.id, finish / 1000, travel, "PROJECTILE_IMPACT", target.guid)
			end
		end
	end
end)

-- Timer for movement
mint.data.StopTimer = mint.Timer:New()
mint.data.MoveTimer = mint.Timer:New()

local StopTimer = mint.data.StopTimer
local MoveTimer = mint.data.MoveTimer

-- Movement start for tracking movement timers
Events:RegisterWoWEvent("PLAYER_STARTED_MOVING", function(...)
	if StopTimer:IsRunning() then
		StopTimer:Reset()
	end

	if not MoveTimer:IsRunning() then
		MoveTimer:Start()
	end
end)

-- Movement stop for tracking movement timers
Events:RegisterWoWEvent("PLAYER_STOPPED_MOVING", function(...)
	if MoveTimer:IsRunning() then
		MoveTimer:Reset()
	end

	if not StopTimer:IsRunning() then
		StopTimer:Start()
	end
end)

-- Combat start for tracking combat log timers
Events:RegisterWoWEvent("PLAYER_REGEN_DISABLED", function(...)
	local time = GetTime()
	mint.combatStartTime = time
end)

-- Combat stop for tracking combat log timers
Events:RegisterWoWEvent("PLAYER_REGEN_ENABLED", function(...)
	local time = GetTime()
	mint.combatStartTime = 0
end)

-- Register event handler for successful spell casts
Events:RegisterWoWEvent("UNIT_SPELLCAST_SUCCEEDED", function(unitID, castGUID, spellID)
    -- Only track player spells
    if unitID == "player" then
        mint.data.lastCastTimers[spellID] = GetTime()
		if not mint.data.lastCastOrder then
			mint.data.lastCastOrder = {}
		end
		table.insert(mint.data.lastCastOrder, spellID)
    end
end)

function mint:CombatLog(...)
    local args = {...}

	local skip_first = false
	local color = "|cFF00FF00"

	-- Check if args[1] starts with |cFF and is 10 chars
	if args[1] and args[1]:sub(1, 4) == "|cFF" and #args[1] == 10 then
		color = args[1]
		skip_first = true
	end

    local str = "|TInterface\\Icons\\inv_g_fishingbobber_05:16|t"
	local current = GetTime()
	local time = current - mint.combatStartTime

	-- Add a timestamp that is MM:SS:MS
	local minutes = math.floor(time / 60)
	local seconds = math.floor(time % 60)
	local milliseconds = math.floor((time - seconds) * 1000)
	local formatted_time = string.format("%02d:%02d:%03d", minutes, seconds, milliseconds)
    str = str .. "[" .. color  .. formatted_time .. "|r]: "
	local console_str = "[" .. formatted_time .. "]: "

	local ix = skip_first and 2 or 1
    for i = ix, #args do
        str = str .. tostring(args[i]) .. " "
		console_str = console_str .. tostring(args[i]) .. " "
    end

    print(str)
end

------------------------------
--- Mint Engine
------------------------------

-- local pauseTimer = 0

-- -- Hook into action button presses
-- hooksecurefunc("ActionButtonDown", function(id)
--     pauseTimer = GetTime() + 0.2
-- 	print("Pausing!")
-- end)

-- local MintFrame = CreateFrame("Frame")
-- local MintTicker = 0

-- MintFrame:SetScript("OnUpdate", function(self, elapsed)
-- 	-- local keybinding = mint.data.vars.keybind_down
-- 	MintTicker = MintTicker + elapsed

--     if not mint.data.toggles.engine then return true end
--     if MintTicker < 0.1 then return true end

--     MintTicker = 0

-- 	-- Update unit management prior to actors
--     FriendManager:Update()
--     ObjectManager:Update()

-- 	-- Don't run the actor when we are paused for manual play.
-- 	if GetTime() < pauseTimer then
-- 		print("Paused!")
--         return
--     end

-- 	print("Not paused!")

-- 	-- Run actors
--     for i = 1, #mint.data.actors do
--         local actor = mint.data.actors[i]
--         if actor:ShouldRun() then
--             actor:Tick()
--         end
--     end
-- end)

local pauseTimer = 0
local PAUSE_SECS = 0.35

local function PauseFor(sec)
    pauseTimer = GetTime() + (sec or PAUSE_SECS)
    -- print("Pausing for", sec or PAUSE_SECS)
end

-- Build a chord like "SHIFT-CTRL-1", "ALT-BUTTON4", etc.
local function MakeChord(key)
    local pre = ""
    if IsShiftKeyDown()   then pre = pre .. "SHIFT-" end
    if IsControlKeyDown() then pre = pre .. "CTRL-"  end
    if IsAltKeyDown()     then pre = pre .. "ALT-"   end
    return pre .. key
end

-- Returns true if the binding resolves to an actionbar press or a click on an action button
local function ShouldPauseForBinding(chord)
    local action = GetBindingAction(chord)
    if not action or action == "" then return false end

    -- Common actionbar command families
    if action:find("^ACTIONBUTTON")          then return true end      -- ACTIONBUTTON1..12
    if action:find("^MULTIACTIONBAR")        then return true end      -- MULTIACTIONBAR1BUTTON1..12 etc.
    if action:find("^BONUSACTIONBUTTON")     then return true end
    if action:find("^EXTRAACTIONBUTTON")     then return true end
    if action:find("^PETACTIONBUTTON")       then return true end

    return false
end

-- Keyboard listener that keeps input flowing to the game
local InputListener = CreateFrame("Frame", nil, UIParent)
InputListener:EnableKeyboard(true)
InputListener:SetPropagateKeyboardInput(true)
InputListener:SetScript("OnKeyDown", function(_, key)
    -- Ignore pure modifier notifications
    if key == "LSHIFT" or key == "RSHIFT" or key == "LCTRL" or key == "RCTRL" or key == "LALT" or key == "RALT" then
        return
    end

    local chord = MakeChord(key)
    if ShouldPauseForBinding(chord) then
        PauseFor()
    end
end)

-- Optional: also catch BUTTON4/BUTTON5 keys (some setups bind these directly)
-- This still flows through the normal binding path, but in case the binding is empty you can poll:
local MousePoll = CreateFrame("Frame")
MousePoll:SetScript("OnUpdate", function(self, elapsed)
    -- No need to poll if we’re already paused
    if GetTime() < pauseTimer then return end

    -- If you want polling for raw mouse buttons, uncomment:
    if IsMouseButtonDown("BUTTON4") or IsMouseButtonDown("BUTTON5") then
        PauseFor()
    end
end)

-- ==== Your engine ticker (unchanged except for the pause check) ====
local MintFrame = CreateFrame("Frame")
local MintTicker = 0

MintFrame:SetScript("OnUpdate", function(self, elapsed)
    MintTicker = MintTicker + elapsed

    if not mint.data.toggles.engine then return true end
    if MintTicker < 0.05 then return true end
    MintTicker = 0

    -- Update unit management prior to actors
    FriendManager:Update()
    ObjectManager:Update()
	mint.TimeToDie:Refresh()

    -- Don't run actors when paused for manual play.
    if GetTime() < pauseTimer then
        -- print("Paused!")
        return
    end

	-- print("Not paused!")

    -- Run actors
    for i = 1, #mint.data.actors do
        local actor = mint.data.actors[i]
        if actor:ShouldRun() then
            actor:Tick()
        end
    end
end)
