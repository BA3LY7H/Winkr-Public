local unlocker,
---@class mint
mint = ...

------------------------------
--- Enums
------------------------------

---@enum AttachFlags
mint.AttachFlags = {
	right_hand = 1,
	left_hand = 2,
	right_elbow = 3,
	left_elbow = 4,
	right_shoulder = 5,
	left_shoulder = 6,
	right_knee = 7,
	left_knee = 8,
	right_hip = 9,
	left_hip = 10,
	neck = 11,
	back = 12, -- Center of the back
	center = 13, -- Center of the body
	chest = 15, -- Front of chest
	chin = 17,
	above = 18,
	below = 19,
	hat = 20,
	groin = 25,
	back_slot = 28,
	center_low = 34,

}

---@enum ObjectTypes
mint.ObjectTypes = {
	["Object"] = 0,
    ["Item"] = 1,
    ["Container"] = 2,
    ["AzeriteEmpoweredItem"] = 3,
    ["AzeriteItem"] = 4,
    ["Unit"] = 5,
    ["Player"] = 6,
    ["ActivePlayer"] = 7,
    ["GameObject"] = 8,
    ["DynamicObject"] = 9,
    ["Corpse"] = 10,
    ["AreaTrigger"] = 11,
    ["SceneObject"] = 12,
    ["Conversation"] = 13,
}

-- Helper: resolve tokens to GUIDs for Winkr C-bridge
local function winkrGUID(input)
	if type(input) == "string" and not string.find(input, "-") then
		return UnitGUID(input)
	end
	return input
end

------------------------------
--- Winkr Aura Hook System
--- Transparently redirects C_UnitAuras calls for GUID-based units
--- to winkr_UnitAuras bridge data, following awful2's proven approach.
------------------------------
if unlocker.name == "winkr" and type(winkr_UnitAuras) == "function" then
	local spellNameCache = {}
	local bridgeAuraCache = {}
	local wipeTable = table.wipe or function(t) for k in pairs(t) do t[k] = nil end end

	local function IsGUID(str)
		return type(str) == "string" and str:find("-", 1, true) ~= nil
	end

	local function FixupBridgeAura(aura)
		if not aura or not aura.spellId then return aura end
		-- Resolve empty name from spell database
		if not aura.name or aura.name == "" then
			local cached = spellNameCache[aura.spellId]
			if cached == nil then
				cached = (C_Spell and C_Spell.GetSpellName and C_Spell.GetSpellName(aura.spellId)) or false
				spellNameCache[aura.spellId] = cached
			end
			aura.name = cached or ""
		end
		-- Fix expirationTime from remaining seconds
		if aura._remainingSec then
			aura.expirationTime = aura._remainingSec > 0 and (GetTime() + aura._remainingSec) or 0
			aura._remainingSec = nil
		end
		return aura
	end

	local function GetBridgeAuras(guid, filter)
		-- Extract base filter for bridge call (strip |PLAYER etc)
		local baseFilter = nil
		if type(filter) == "string" then
			if filter:find("HELPFUL") then baseFilter = "HELPFUL"
			elseif filter:find("HARMFUL") then baseFilter = "HARMFUL"
			end
		end
		local key = guid .. "|" .. (baseFilter or "ALL")
		local cached = bridgeAuraCache[key]
		if cached ~= nil then
			return cached ~= false and cached or nil
		end
		local auras = winkr_UnitAuras(guid, baseFilter)
		if auras and type(auras) == "table" then
			bridgeAuraCache[key] = auras
			return auras
		end
		bridgeAuraCache[key] = false
		return nil
	end

	local function MatchesPlayerFilter(aura, filter)
		if not filter or not filter:find("|PLAYER") then return true end
		return aura.isFromPlayerOrPlayerPet
	end

	-- Hook C_UnitAuras.GetAuraDataByIndex
	if C_UnitAuras and C_UnitAuras.GetAuraDataByIndex then
		local origGetByIndex = C_UnitAuras.GetAuraDataByIndex
		C_UnitAuras.GetAuraDataByIndex = function(unit, index, filter)
			if IsGUID(unit) then
				local auras = GetBridgeAuras(unit, filter)
				if auras then
					if filter and filter:find("|PLAYER") then
						-- Index into only player-sourced auras
						local count = 0
						for i = 1, #auras do
							if auras[i].isFromPlayerOrPlayerPet then
								count = count + 1
								if count == index then
									return FixupBridgeAura(auras[i])
								end
							end
						end
						return nil
					end
					if auras[index] then
						return FixupBridgeAura(auras[index])
					end
				end
				return nil
			end
			return origGetByIndex(unit, index, filter)
		end
	end

	-- Hook C_UnitAuras.GetAuraDataBySpellName
	if C_UnitAuras and C_UnitAuras.GetAuraDataBySpellName then
		local origGetBySpellName = C_UnitAuras.GetAuraDataBySpellName
		C_UnitAuras.GetAuraDataBySpellName = function(unit, spellName, filter)
			if IsGUID(unit) then
				local auras = GetBridgeAuras(unit, filter)
				if auras then
					for i = 1, #auras do
						local a = FixupBridgeAura(auras[i])
						if a.name == spellName and MatchesPlayerFilter(a, filter) then
							return a
						end
					end
				end
				return nil
			end
			return origGetBySpellName(unit, spellName, filter)
		end
	end

	-- Hook C_UnitAuras.GetAuraDataByAuraInstanceID
	if C_UnitAuras and C_UnitAuras.GetAuraDataByAuraInstanceID then
		local origGetByInstanceID = C_UnitAuras.GetAuraDataByAuraInstanceID
		C_UnitAuras.GetAuraDataByAuraInstanceID = function(unit, auraInstanceID)
			if IsGUID(unit) then
				local auras = GetBridgeAuras(unit, nil)
				if auras then
					for i = 1, #auras do
						if auras[i].auraInstanceID == auraInstanceID then
							return FixupBridgeAura(auras[i])
						end
					end
				end
				return nil
			end
			return origGetByInstanceID(unit, auraInstanceID)
		end
	end

	-- Clear caches every frame (same approach as awful2)
	if C_Timer and C_Timer.NewTicker then
		C_Timer.NewTicker(0, function()
			wipeTable(bridgeAuraCache)
		end)
	end

	-- Expose cache wipe for manual use
	mint._wipeBridgeAuraCache = function()
		wipeTable(bridgeAuraCache)
		wipeTable(spellNameCache)
	end
end


------------------------------
--- Object Manager
------------------------------

-- Return the ObjectManager Object of a GUID
---@param guid string
---@return string
function mint.Object(guid)
	return guid
end

-- Return the ObjectManager table
---@param filter string|number
function mint.Objects(filter)
	local objects = {}
	-- winkr_ObjectType returns a NUMBER (0-15), compare numerically
	local filterNum = filter
	if type(filter) == "string" then
		filterNum = mint.ObjectTypes[filter]
	end

	local playerGuid = UnitGUID("player")
	local count = winkr_GetObjectCount()
	for i = 0, count - 1 do
		local guid = winkr_GetObjectWithIndex(i)
		if guid then
			local success, objType = pcall(winkr_ObjectType, guid)
			if success and objType then
				if filterNum == 7 then
					-- ActivePlayer: C bridge converts type 7→6, match by GUID
					if guid == playerGuid then
						table.insert(objects, guid)
					end
				elseif filterNum == 6 then
					-- Player: type 6 but exclude self (self is ActivePlayer)
					if objType == 6 and guid ~= playerGuid then
						table.insert(objects, guid)
					end
				else
					-- All other types: direct numeric match
					if objType == filterNum then
						table.insert(objects, guid)
					end
				end
			end
		end
	end
	return objects
end

------------------------------
--- Object Methods
------------------------------

-- Return the "pointer" of an object, which is just the OM token usually
---@param object Unit
---@return string
function mint.ObjectPointer(object)
	return object.unit
end

-- Check if an object "exists" in the game world
---@param guid string
---@return boolean
function mint.ObjectExists(guid)
	local resolved = winkrGUID(guid)
	if not resolved then return false end
	return winkr_IsValidObject(resolved)
end

-- Return an object's ID
---@param guid string
---@return number
function mint.ObjectID(guid)
	local resolved = winkrGUID(guid)
	if not resolved then return 0 end
	return winkr_ObjectID(resolved)
end

-- Return the GUID for an object's pointer
---@param pointer string
---@return string | boolean?
function mint.ObjectGUID(pointer)
	if pointer == "none" or not pointer then return false end
	if type(pointer) == "string" and not string.find(pointer, "-") then
		local guid = UnitGUID(pointer)
		if guid then return guid end
	end
	return pointer
end

-- Get the creator of an object, for things like totems
---@param object Unit
---@return string
function mint.ObjectCreator(object)
	local resolved = winkrGUID(object)
	if not resolved then return nil end
	return winkr_ObjectCreator(resolved)
end

-- Get the target of an object
---@param object Unit
---@return string?
function mint.ObjectTarget(object)
	local resolved = winkrGUID(object)
	if not resolved then return nil end
	return winkr_ObjectTarget(resolved)
end

-- Get the position of an object
---@param guid string
---@return number, number, number
function mint.ObjectPosition(guid)
	local resolved = winkrGUID(guid)
	if not resolved then return nil, nil, nil end
	return winkr_ObjectPosition(resolved)
end

-- Get the height of an object
---@param object Unit
---@return number?
function mint.ObjectHeight(object)
	local resolved = winkrGUID(object)
	if not resolved then return nil end
	return winkr_ObjectHeight(resolved)
end

-- Returns an object attachment's position
---@param pointer string
---@param flag AttachFlags
function mint.ObjectAttachmentPosition(pointer, flag)
	local resolved = winkrGUID(pointer)
	if not resolved then return nil end
	local x, y, z = winkr_ObjectPosition(resolved)
	if not x or (x == 0 and y == 0 and z == 0) then return nil end
	local h = winkr_ObjectHeight(resolved) or 2.0
	
        -- Verifying standardized height logic with debug
        local finalZ = z + (h * 0.7)
        if UnitIsUnit(pointer, "player") then
            -- Optional: Add debug log for player's virtual eye position
            -- print(string.format("[LoS DEBUG]: Player Pos: %.2f, %.2f, %.2f (Height: %.2f)", x, y, finalZ, h))
        end
	return x, y, finalZ
end

---@param guid string
---@return boolean
function mint.ObjectLootable(guid)
	local resolved = winkrGUID(guid)
	if not resolved then return false end
	return winkr_ObjectLootable(resolved)
end

---@param guid string
---@return string?
function mint.ObjectName(guid)
	local resolved = winkrGUID(guid)
	if not resolved then return nil end
	return winkr_ObjectName(resolved)
end

-- Face the given direction
function mint.FaceDirection(angle, force)
    -- If the user is manually turning with Right Click, DO NOT auto-face.
    -- This is the critical fix for the camera 'snapping' issue.
    if IsMouselooking() and not force then 
        return false 
    end
	return winkr_FaceDirection(angle)
end

-- Return the object's rotation
---@param guid string
---@return number?
function mint.ObjectRotation(guid)
	local resolved = winkrGUID(guid)
	if not resolved then return nil end
	return winkr_ObjectFacing(resolved)
end

-- Returns object combat reach
---@param guid string
---@return number?
function mint.ObjectCombatReach(guid)
	local resolved = winkrGUID(guid)
	if not resolved then return nil end
	return winkr_ObjectCombatReach(resolved)
end

------------------------------
--- Distance Calculations
--- WE SHOULD USE LUA DISTANCE NOT UNLOCKER
------------------------------

-- Returns the distance between two objects
---@param x1 number
---@param y1 number
---@param z1 number
---@param x2 number
---@param y2 number
---@param z2 number
---@return number
function mint.Distance3D(x1, y1, z1, x2, y2, z2)
	local xDiff = x1 - x2
	local yDiff = y1 - y2
	local zDiff = z1 - z2
	return math.sqrt((xDiff * xDiff) + (yDiff * yDiff) + (zDiff * zDiff))
end

function mint.Distance2D(x1, y1, x2, y2)
	local xDiff = x1 - x2
	local yDiff = y1 - y2
	return math.sqrt((xDiff * xDiff) + (yDiff * yDiff))
end

-- Returns object casting target
---@param guid string
---@return string
function mint.UnitCastTarget(guid)
	local resolved = winkrGUID(guid)
	if not resolved then return "" end
	return tostring(winkr_ObjectCastingTarget(resolved))
end

-- Returns if a spell is pending
function mint.IsSpellPending()
	if winkr_SpellIsTargeting and winkr_SpellIsTargeting() then
		return 64
	end
	return 0
end

-- Simulate a left click at the given coordinates
function mint.Click(x, y, z)
	winkr_ClickPosition(x, y, z)
end

-- Traceline
function mint.TraceLine(x1, y1, z1, x2, y2, z2, flags)
	local hit, hx, hy, hz = winkr_TraceLine(x1, y1, z1, x2, y2, z2, flags or 0x11)
	
        if hit and hit ~= 0 then 
            return hx or 0.1, hy or 0, hz or 0 
        end
	return 0, 0, 0
end

------------------------------
--- FileSystem
------------------------------

-- Check if a directory exists
---@param dir string
---@return boolean
function mint.DirectoryExists(dir)
	local fullpath = unlocker.baseDir .. "\\" .. dir:gsub("/", "\\")
	local files = winkr_ListFiles and winkr_ListFiles(fullpath)
	-- If ListFiles returns a table (even empty), the directory exists
	if files then return true end
	local dirs = winkr_ListDirectories and winkr_ListDirectories(fullpath)
	return dirs ~= nil
end

function mint.FileExists(path)
	local content = winkr_ReadFile(path)
	return content ~= nil
end

-- Create a directory by writing a sentinel file into it
-- winkr_WriteFile auto-creates parent directories
---@param dir string
function mint.CreateDirectory(dir)
	local sentinel = unlocker.baseDir .. "\\" .. dir:gsub("/", "\\") .. "\\.mint_init"
	winkr_WriteFile(sentinel, "1", false)
	return true
end

-- Get all files in a directory
---@param dir string
function mint.ListFiles(dir)
	return winkr_ListFiles and winkr_ListFiles(dir) or {}
end

-- Read a file
---@param path string
---@return string
function mint.ReadFile(path)
	if not path then return "" end
	return winkr_ReadFile(unlocker.baseDir .. "\\" .. path:gsub("/", "\\"))
end

-- Delete a file
function mint.DeleteFile(path)
	return false
end

-- Write to a file
function mint.WriteFile(filePath, dataToSave, append)
	if not filePath then return false end
        if filePath:match("^[A-Za-z]:[\\/]") then
            return winkr_WriteFile(filePath:gsub("/", "\\"), dataToSave, append)
        end
	return winkr_WriteFile(unlocker.baseDir .. "\\" .. filePath:gsub("/", "\\"), dataToSave, append)
end

-- Check if the unit is sitting
function mint.UnitIsSitting(unit)
	return false
end