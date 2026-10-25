local name,
---@class mint
mint,
unlocker = ...

if unlocker == nil and type(winkr_ReadFile) == "function" then
    unlocker = { name = "winkr" }
    
    unlocker.baseDir = WINKR_MODS_DIR or "C:\\mods\\retail-main"
    
    unlocker.GetContents = function(path) return winkr_ReadFile(path) end
    unlocker.GetBaseFolder = function() return unlocker.baseDir end
    unlocker.stdout = print
    unlocker.stderr = print
end

if not unlocker.name then
    unlocker.name = "winkr"
end
mint.data = {
    actors = {},
    dungeons = {},
    lastCastTimers = {},
    debug_mode = true,  -- Toggle with /mintdebug
    toggles = {
        engine = false,
        cooldowns = false,
        kicks = false,
        defensives = false,
        dispels = false,
        purges = false
    },
    vars = {
        debug_start_time = debugprofilestop(),
        dispel_delay = 0.5,
    },
    active_branch = "reactions" -- Default branch
}

------------------------------
--- Metatable for mint attributes
------------------------------

setmetatable(mint, {
	__index = function(instance, k)
		if k == "max_gcd" then
			local haste = UnitSpellHaste("player")
			if haste > 50 then haste = 50 end
			local powerType = UnitPowerType("player")

			local base = powerType == 3 and 1 or 1.5

			return base / (1 + haste / 100)
		end

		if k == "gcd" then
			local info = C_Spell.GetSpellCooldown(61304)
			if not info or not info.startTime then return 0 end

			if info.startTime == 0 then
				return 0
			end

			return info.startTime + info.duration - GetTime()
		end

		if k == "latency" then
			return select(3, GetNetStats()) / 1000
		end

		if k == "class" then
			return string.lower(select(2, UnitClass("player")))
		end

		if k == "specId" then 
			return select(1, GetSpecializationInfo(GetSpecialization()))
		end

		if k == "specName" then
			return string.lower(select(2, GetSpecializationInfo(GetSpecialization())))
		end

		return rawget(mint, k)
	end,
})

------------------------------
--- Debug Console
------------------------------

mint.console = CreateFrame("Frame", nil, UIParent)

local console = mint.console
local inset = 3

-- Create the base frame
local typeFormat = {}
console.typeFormat = typeFormat
console:Hide()
console:SetWidth(UIParent:GetWidth() * 0.35)
console:SetHeight(200)
console:SetPoint("TOPLEFT", 0, 0)
console:SetFrameStrata("DIALOG")
console.texture = console:CreateTexture()
console.texture:SetAllPoints(console)
console.texture:SetColorTexture(0, 0, 0, 0.8) -- semi-transparent black

-- Allow moving the console
console:EnableMouse(true)
console:RegisterForDrag("LeftButton")
console:SetMovable(true)
console:SetScript("OnDragStart", console.StartMoving)
console:SetScript("OnDragStop", console.StopMovingOrSizing)

-- Title
local titleText = console:CreateFontString()
titleText:SetFontObject(ChatFontNormal)
titleText:SetPoint("TOPRIGHT", -inset, -inset)
titleText:SetText("|TInterface\\Icons\\inv_g_fishingbobber_05:16|t|cFF00FF00[Mint]|r |cFFFFFFFFConsole")

-- This is how we display the text
local outputFrame = CreateFrame("ScrollingMessageFrame", nil, console)
outputFrame:SetPoint("TOPLEFT", inset, -inset)
outputFrame:SetPoint("BOTTOMRIGHT", 2, 2)
outputFrame:SetFontObject(ChatFontNormal)
outputFrame:SetJustifyH("LEFT")
outputFrame:SetFading(false)
outputFrame:SetHyperlinksEnabled(true)
outputFrame:SetMaxLines(1000) -- max of 1000 lines in history
outputFrame:EnableMouseWheel(true)

-- Scrolling the text, hold shift to go all the way to the top or bottom
outputFrame:SetScript("OnMouseWheel", function(self, dir)
	if(dir > 0) then
		if(IsShiftKeyDown()) then
			self:ScrollToTop()
		else
			self:ScrollUp()
		end
	elseif(dir < 0) then
		if(IsShiftKeyDown()) then
			self:ScrollToBottom()
		else
			self:ScrollDown()
		end
	end
end)

-- mint.console:Show()

------------------------------
--- Console Log 
------------------------------

-- Logs to debug console
mint.console.log = function(...)
	-- return true
	local args = {...}

	local skip_first = false
	local color = "|cFF00FF00"
	
	-- Check if args[1] starts with |cFF and is 10 chars
	if args[1] and args[1]:sub(1, 4) == "|cFF" and #args[1] == 10 then
		color = args[1]
		skip_first = true
	end
	
	local str = "|TInterface\\Icons\\inv_g_fishingbobber_05:16|t"
	local current = debugprofilestop()
	local time = current - mint.data.vars.debug_start_time
	
	-- Add a timestamp that is MM:SS:MS
	local minutes = math.floor(time / 60)
	local seconds = math.floor(time % 60)
	local formatted_time = string.format("%02d:%02d", minutes, seconds)
	str = str .. "[" .. color  .. formatted_time .. "|r]: "
	local console_str = "[" .. formatted_time .. "]: "
	
	local ix = skip_first and 2 or 1
	for i = ix, #args do
		str = str .. tostring(args[i]) .. " "
		console_str = console_str .. tostring(args[i]) .. " "
	end
	outputFrame:AddMessage(console_str)

    if mint.data.debug_mode then
        mint.data._log_buffer = mint.data._log_buffer or {}
        table.insert(mint.data._log_buffer, console_str)
        if #mint.data._log_buffer > 300 then
            table.remove(mint.data._log_buffer, 1)
        end
        local full_output = table.concat(mint.data._log_buffer, "\n")
        pcall(winkr_WriteFile, unlocker.baseDir .. "\\debug.log", full_output .. "\n", 0)
    end
end

-- Clear the debug log on startup
if mint.data.debug_mode then
    mint.data._log_buffer = { "-- STARTING MINT DEBUG LOG --" }
    pcall(winkr_WriteFile, unlocker.baseDir .. "\\debug.log", "-- STARTING MINT DEBUG LOG --\n", 0)
end

------------------------------
--- Log
------------------------------

-- Logs to chat box
function mint:Log(...)
    local args = {...}
    local str = "[Mint]: "
    for i = 1, #args do
        str = str .. tostring(args[i]) .. " "
    end
    print(str)
end

------------------------------
--- Require Function
------------------------------

local base = unlocker.baseDir
function mint:Require(path, ...)
    local contents = winkr_ReadFile(base .. "\\" .. path:gsub("/", "\\"))
    if not contents then
        local errMsg = "[Mint Loader Error]: Could not read " .. tostring(path)
        if type(geterrorhandler) == "function" then geterrorhandler()(errMsg) else error(errMsg) end
        return nil
    end
    local fn, err = loadstring(contents, "@"..name.."/"..path)
    if err then
        if type(geterrorhandler) == "function" then geterrorhandler()("[Mint Loader Error]: " .. tostring(err)) else error(err) end
    elseif fn then
		local success, result = pcall(fn, unlocker, self, ...)

		if not success then
            if type(geterrorhandler) == "function" then geterrorhandler()("[Mint Runtime Error]: " .. tostring(result)) else error(result) end
			mint.console.log(result)
		end

		return result
    end
end

------------------------------
--- Dynamic Module Loading
------------------------------
local rotations = {}
-- Process a module based on its configuration
function mint:ProcessModule(module, ...)
    if not module or not module.path then
        mint.console.log("Invalid module configuration")
        return nil
    end
    
    local result

	if module.type == "classFile" then
		if module.class and module.class ~= mint.class then
			mint.console.log("Module class '" .. module.class .. "' does not match mint.class '" .. mint.class .. "'")
			return nil
		end

		if module.spec and module.spec ~= mint.specName then
			mint.console.log("Module spec '" .. module.spec .. "' does not match mint.specName '" .. mint.specName .. "'")
			return nil
		end

		result = mint:Require(module.path, rotations, ...)
		return result
	else
		-- Load the module
		result = mint:Require(module.path, ...)
			
		-- Process based on type
		if module.type == "instance" and result then
			-- Handle error handling if specified
			local success, instance = pcall(function()
				return result:New()
			end)
			
			if success then
				result = instance
				mint.console.log("Successfully initialized " .. (module.assignTo or "module"))
			else
				mint.console.log("|cFFFF0000Error initializing " .. (module.assignTo or "module") .. ":|r ", instance)
                if type(geterrorhandler) == "function" then geterrorhandler()("[Mint Init Error] " .. (module.assignTo or "module") .. ": " .. tostring(instance)) else error(instance) end
				return nil
			end

			-- Run post initialization if specified
			if module.postInit and result[module.postInit] then
				result[module.postInit](result)
			end
		end

		-- If it should be assigned to mint
		if module.assignTo then
			-- Handle nested assignments (e.g. "Interface.Element")
			local parts = {}
			for part in module.assignTo:gmatch("[^.]+") do
				table.insert(parts, part)
			end
			
			if #parts > 1 then
				local parent = mint
				for i = 1, #parts - 1 do
					if not parent[parts[i]] then
						parent[parts[i]] = {}
					end
					parent = parent[parts[i]]
				end
				parent[parts[#parts]] = result
			else
				-- mint.console.log("Assigning result to mint." .. module.assignTo)
				mint[module.assignTo] = result
			end
		end

		-- Execute any additional post-processing
		if module.postProcess and type(module.postProcess) == "string" then
			local success, err = pcall(loadstring("return function(mint) " .. module.postProcess .. " end")(), mint)
			if not success then
				mint.console.log("|cFFFF0000Error in post-processing:|r ", err)
                if type(geterrorhandler) == "function" then geterrorhandler()("[Mint Post-Process Error]: " .. tostring(err)) end
			end
		end

		return result
	end
end


------------------------------
--- Loading Files with Branch Support
------------------------------
local function Load(data, branch)
    mint.data.active_branch = branch or "main"
    mint.console.log("Loading Mint Files (Branch: " .. mint.data.active_branch .. ")")
    
    -- Check if the data contains an enhanced load order with module configurations
    if data.order and type(data.order) == "table" then
        mint.console.log("Using enhanced module configuration")
        
        -- Process each module according to its configuration
        for _, module in ipairs(data.order) do
            mint:ProcessModule(module)
        end
    end
	
	mint.events:TriggerEvent("BuildOptions")
	mint.events:TriggerEvent("BuildQuickbar")
end

local data = unlocker.GetContents(base .. "/load-order.json")
if not mint.json then
    mint.json = mint:Require("Engine/json.lua")
end
if not data then
    mint.console.log("|cFFFF0000[Mint]|r Could not read load-order.json")
    return
end
local parsed = mint.json.decode(data)
if not parsed then
    mint.console.log("|cFFFF0000[Mint]|r Failed to parse load-order.json")
    return
end

-- Execute immediately. Winkr handles its own Lua lifecycle injections.
Load(parsed, "main")

-- Add Winkr NativeCast isolated test macro
SLASH_WINKRTEST1 = "/winkrtest"
SlashCmdList["WINKRTEST"] = function(msg)
    local mGuid = UnitGUID("mouseover")
    local tGuid = UnitGUID("target")
    
    if mGuid then
        mint.console.log("|cFFFF8000[Winkr Test]|r Testing NativeCast(172) on Mouseover GUID: " .. tostring(mGuid))
        winkr_NativeCast(172, mGuid)
    end
    
    if tGuid then
        mint.console.log("|cFF00FF00[Winkr Test]|r Testing NativeCast(172) on Target GUID: " .. tostring(tGuid))
        winkr_NativeCast(172, tGuid)
    end
    
    if not mGuid and not tGuid then
        mint.console.log("|cFFFF0000[Winkr Test]|r Error: You must have a mouseover or Target to test.")
    end
end

-- Debug: find ghoul-related buff IDs on the player
SLASH_GHOULCHECK1 = "/ghoulcheck"
SlashCmdList["GHOULCHECK"] = function(msg)
    local pGuid = UnitGUID("player")
    mint.console.log("---- GHOUL BUFF CHECK ----")
    
    -- Method 1: WoW standard API scan
    mint.console.log(">> Standard API Buffs:")
    for i = 1, 40 do
        local aura = C_UnitAuras.GetAuraDataByIndex("player", i, "HELPFUL")
        if not aura then break end
        local nameLower = (aura.name or ""):lower()
        if nameLower:find("ghoul") or nameLower:find("festering") or nameLower:find("lesser") or nameLower:find("scythe") then
            mint.console.log("  [" .. tostring(aura.spellId) .. "] " .. tostring(aura.name) .. " x" .. tostring(aura.applications or 0))
        end
    end
    
    -- Method 2: Winkr memory scan (catches hidden buffs)
    if winkr_UnitAuras then
        mint.console.log(">> Winkr Memory Buffs:")
        local auras = winkr_UnitAuras(pGuid)
        if auras and type(auras) == "table" then
            for i = 1, #auras do
                local nameLower = (auras[i].name or ""):lower()
                if nameLower:find("ghoul") or nameLower:find("festering") or nameLower:find("lesser") or nameLower:find("scythe") then
                    mint.console.log("  [" .. tostring(auras[i].spellId) .. "] " .. tostring(auras[i].name) .. " x" .. tostring(auras[i].applications or 0))
                end
            end
        end
    end
    
    mint.console.log("--------------------------")
end

-- Debug: find plague/disease debuff IDs on the target
SLASH_PLAGUECHECK1 = "/plaguecheck"
SlashCmdList["PLAGUECHECK"] = function(msg)
    local tGuid = UnitGUID("target")
    if not tGuid then
        mint.console.log("No target selected!")
        return
    end
    mint.console.log("---- TARGET DEBUFF CHECK ----")
    
    -- Method 1: Standard API
    mint.console.log(">> Standard API Debuffs:")
    for i = 1, 40 do
        local aura = C_UnitAuras.GetAuraDataByIndex("target", i, "HARMFUL")
        if not aura then break end
        mint.console.log("  [" .. tostring(aura.spellId) .. "] " .. tostring(aura.name) .. " dur=" .. tostring(aura.duration) .. " exp=" .. tostring(aura.expirationTime))
    end
    
    -- Method 2: Winkr memory scan
    if winkr_UnitAuras then
        mint.console.log(">> Winkr Memory Debuffs (harmful-looking):")
        local auras = winkr_UnitAuras(tGuid)
        if auras and type(auras) == "table" then
            local count = 0
            for i = 1, #auras do
                local nameLower = (auras[i].name or ""):lower()
                if nameLower:find("plague") or nameLower:find("virulent") or nameLower:find("dread") or nameLower:find("disease") or nameLower:find("wound") then
                    mint.console.log("  [" .. tostring(auras[i].spellId) .. "] " .. tostring(auras[i].name) .. " dur=" .. tostring(auras[i].duration) .. " exp=" .. tostring(auras[i].expirationTime))
                    count = count + 1
                end
            end
            if count == 0 then
                mint.console.log("  No plague/disease debuffs found in winkr scan!")
                mint.console.log("  Total auras returned: " .. #auras)
            end
        else
            mint.console.log("  winkr_UnitAuras returned nil or non-table!")
        end
    end
    
    mint.console.log("-----------------------------")
end

-- Add Winkr Aura reading isolated test script
SLASH_WINKRAURA1 = "/winkraura"
SlashCmdList["WINKRAURA"] = function(msg)
    local tGuid = UnitGUID("target")
    local mGuid = UnitGUID("mouseover")
    
    if not tGuid and not mGuid then 
        mint.console.log("Need a Target or Mouseover.")
        return 
    end
    
    mint.console.log("---- AURA TEST ----")
    if tGuid then
        local a1 = winkr_UnitAuras(tGuid)
        mint.console.log("TARGET Auras (" .. tostring(tGuid) .. "):")
        if a1 and type(a1) == "table" then
            for i=1, #a1 do
                mint.console.log("  - " .. tostring(a1[i].name) .. " (ID: " .. tostring(a1[i].spellId) .. ")")
            end
        else
            mint.console.log("  (nil or empty)")
        end
    end
    
    if mGuid then
        local a2 = winkr_UnitAuras(mGuid)
        mint.console.log("MOUSEOVER Auras (" .. tostring(mGuid) .. "):")
        if a2 and type(a2) == "table" then
            for i=1, #a2 do
                mint.console.log("  - " .. tostring(a2[i].name) .. " (ID: " .. tostring(a2[i].spellId) .. ")")
            end
        else
            mint.console.log("  (nil or empty)")
        end
        
        -- winkr_SetNPC is known-broken for aura queries; removed debug block
    end
    mint.console.log("-------------------")
end

-- Add framework pipeline evaluation dump macro
SLASH_WINKRDEBUG1 = "/winkrdebug"
SlashCmdList["WINKRDEBUG"] = function(msg)
    local out = "---- WINKR DEBUG ----\n"
    local player = mint.UnitManager:Get("player")
    out = out .. "OM Combat Units: " .. tostring(mint.ObjectManager.combat:count()) .. "\n"
    
    out = out .. "\n>> COMBAT AURAS <<\n"
    mint.ObjectManager.combat:loop(function(enemy)
        out = out .. "Enemy GUID: " .. tostring(enemy.guid) .. "\n"
        out = out .. " - IsTarget: " .. tostring(enemy:IsUnit("target")) .. "\n"
        
        local auras = winkr_UnitAuras(enemy.guid)
        out = out .. " - Auras Type: " .. type(auras) .. "\n"
        
        if type(auras) == "table" then
            out = out .. " - Auras Length: " .. tostring(#auras) .. "\n"
            for i = 1, #auras do
                if type(auras[i]) == "table" then
                    out = out .. "   ["..i.."] Name: " .. tostring(auras[i].name) .. " ID: " .. tostring(auras[i].spellId) .. " Caster: " .. tostring(auras[i].sourceUnit) .. "\n"
                end
            end
        else
            out = out .. " - Auras Value: " .. tostring(auras) .. "\n"
        end
        return false
    end)
    out = out .. "---------------------\n"
    
    winkr_WriteFile("c:\\mods\\scan_log_debug.txt", out, false)
    mint.console.log("Winkr debug dumped to scan_log_debug.txt!")
end

-- Toggle verbose debug logging for spell checks and casting pipeline
SLASH_MINTDEBUG1 = "/mintdebug"
SlashCmdList["MINTDEBUG"] = function(msg)
    mint.data.debug_mode = not mint.data.debug_mode
    mint.console.log("|cFF00FF00[Mint]|r Debug mode: " .. (mint.data.debug_mode and "|cFF00FF00ON|r" or "|cFFFF0000OFF|r"))
end
