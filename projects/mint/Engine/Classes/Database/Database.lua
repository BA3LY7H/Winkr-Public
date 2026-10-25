local unlocker,
---@class mint
mint = ...

local AS 			= mint.Serializer
local Base64 		= mint.Base64
local LC 			= mint.Compress
local EventManager 	= mint.EventManager

---@class Database
---@field global table
---@field path string
---@field profiles table
---@field profile table
---@field keybinds table
---@field events EventManager
local Database = {}
Database.__index = Database

local function create_nested_accessor(profile_data, onChanged)
    -- Cache for real tables we've created
    local table_cache = {}
    
    local function get_or_create_nested_table(data, path_parts)
        local current = data
        local current_path = ""
        
        -- Create tables along the path if they don't exist
        for i, part in ipairs(path_parts) do
            current_path = current_path .. (i > 1 and "." or "") .. part
            
            if current[part] == nil then
                current[part] = {}
            elseif type(current[part]) ~= "table" then
                -- If there's a non-table value blocking our path, replace it with a table
                current[part] = {}
            end
            
            current = current[part]
        end
        
        return current
    end
    
    local function create_subtable(data, path)
        -- If we already created a real table for this path, return it
        if path and table_cache[path] then
            return table_cache[path]
        end
        
        local mt = {}
        mt.__index = function(t, k)
            local full_path = path and (path .. "." .. k) or k
            
            -- Split the path into parts
            local parts = {}
            for part in string.gmatch(full_path, "[^%.]+") do
                table.insert(parts, part)
            end
            
            -- Try to get the value from the data
            local value = data
            for _, part in ipairs(parts) do
                if type(value) ~= "table" then
                    return nil
                end
                value = value[part]
                if value == nil then
                    break
                end
            end

            -- If the found value is NOT a table, return it directly.
            -- This prevents primitives (strings, numbers) from being converted to proxy tables.
            if value ~= nil and type(value) ~= "table" then
                return value
            end
            
            -- If it's a table (or nil), create/get the proxy
            local real_table = get_or_create_nested_table(data, parts)
            
            -- Cache this real table for future lookups
            table_cache[full_path] = real_table
            
            return real_table
        end
        
        -- Allow write operations
        mt.__newindex = function(t, k, v)
            local full_path = path and (path .. "." .. k) or k
            
            -- Split the path into parts
            local parts = {}
            for part in string.gmatch(full_path, "[^%.]+") do
                table.insert(parts, part)
            end
            
            -- Get the parent table and set the value
            if #parts > 1 then
                local parent_parts = {}
                for i = 1, #parts - 1 do
                    table.insert(parent_parts, parts[i])
                end
                
                local parent = get_or_create_nested_table(data, parent_parts)
                parent[parts[#parts]] = v
            else
                data[k] = v
            end

            -- Trigger auto-save if callback is provided
            if onChanged then
                onChanged()
            end
        end
        
        return setmetatable({}, mt)
    end
    
    return create_subtable(profile_data, nil)
end

local pm_mt = {
	__index = function(t, k, ...)
		local values = {
            ["global"] = function()
                return create_nested_accessor(rawget(t, "_global_data"), function() t:SaveGlobal() end)
            end,
			["profile"] = function()
                local active_profile = Database.GetActiveProfile(t)
                if active_profile then
                    return create_nested_accessor(active_profile.db, function() t:SaveProfile(active_profile.name) end)
                end
                return nil
            end,
			["keybinds"] = function()
                local active_profile = Database.GetActiveProfile(t)
                if active_profile then
                    return create_nested_accessor(active_profile.kb, function() t:SaveProfile(active_profile.name) end)
                end
                return nil
            end,
		}

		if values[k] then
			return values[k]()
		end

		local value = Database[k]
        if value then
            return value
        end

		return rawget(t, k)
	end
}

-- Constructor
---@return Database
function Database:New()
    local self = setmetatable({}, Database)

	-- Create the folders if they do not exist
    if not mint.DirectoryExists("Mint") then mint.CreateDirectory("Mint") end
    if not mint.DirectoryExists("Mint/Profiles") then mint.CreateDirectory("Mint/Profiles") end

	self.path = "Mint/Profiles/"

	local profile_files = mint.ListFiles("Mint/Profiles")

	self.profiles = {}

	for _, file in ipairs(profile_files) do
		local contents = mint.ReadFile(self.path .. file)
		if contents then
			local data = mint.json.decode(contents)

			if data and file ~= "Global.json" then
				local profile = {
					name = data.name,
					db = data.db,
					kb = data.kb
				}

				self.profiles[data.name] = profile
			end
		end
	end

	local global_defaults = {
		current_profile = "Default",
		ui = {
			quickbar_anchor = {
				point = "CENTER",
				relativePoint = "CENTER",
				offsetX = 0,
				offsetY = 0
			},
			button_states = {}
		}
	}

    -- Grab the global data to determine existing settings
    local data = mint.ReadFile("Mint/Profiles/Global.json")
	self._global_data = data and mint.json.decode(data) or {}
	self:MergeDefaults(self._global_data, global_defaults)

	if not self.profiles["Default"] then
		self.profiles["Default"] = {
			name = "Default",
			db = {
				reactions = {}
			},
			kb = {}
		}
	end

	-- Handle saving on logout
	self.events = EventManager:New()
	self.events:RegisterWoWEvent("PLAYER_LOGOUT", function()
		-- self:VerifyProfileDefaults()
		mint.WriteFile(self.path .. "Global.json", mint.json.encode(self._global_data), false)
		for _, profile in pairs(self.profiles) do
			mint.WriteFile(self.path .. profile.name .. ".json", mint.json.encode(profile), false)
		end
	end)

    self.stored_defaults = {}

    return setmetatable(self, pm_mt)
end

-- Function to split a key path and navigate to the proper level
function Database:NavigateToKey(tbl, key)
    local parts = {}
    for part in string.gmatch(key, "[^%.]+") do
        table.insert(parts, part)
    end
    
    local current = tbl
    for i = 1, #parts - 1 do
        if not current[parts[i]] then
            current[parts[i]] = {}
        end
        current = current[parts[i]]
    end
    
    return current, parts[#parts]
end

-- Verify and merge defaults for a specific key path
---@param key string The key path (e.g., "hunter.bm" or "paladin.protection.tanking")
---@param defaults table The default values to merge
function Database:VerifyDefaults(key, defaults)
	defaults = defaults or {}
    -- Apply defaults to all existing profiles
    for profile_name, profile in pairs(self.profiles) do
        -- Navigate to the correct level in the profile
        local parent_table, final_key = self:NavigateToKey(profile.db, key)
        -- Create the final table if it doesn't exist
        if not parent_table[final_key] then
            parent_table[final_key] = {}
		end

        -- Merge defaults with existing values
        self:MergeDefaults(parent_table[final_key], defaults)
        
        -- Save the updated profile
        mint.WriteFile(self.path .. profile_name .. ".json", mint.json.encode(profile), false)
    end
    
    -- Store these defaults for future profile creation
    if not self.stored_defaults then
        self.stored_defaults = {}
    end

    self.stored_defaults[key] = defaults
end

-- Verify and merge defaults for a specific key path
---@param key string The key path (e.g., "hunter.bm" or "paladin.protection.tanking")
---@param defaults table The default values to merge
function Database:VerifyDefaultReactions(key, defaults)
	defaults = defaults or {}
    -- Apply defaults to all existing profiles
    for profile_name, profile in pairs(self.profiles) do
        -- Navigate to the correct level in the profile
        local parent_table, final_key = self:NavigateToKey(profile.db, key)
        -- Create the final table if it doesn't exist
        if not parent_table[final_key] then
            parent_table[final_key] = {}
		end

        -- Merge defaults with existing values
        self:MergeDefaults(parent_table[final_key], defaults)
        
        -- Save the updated profile
        mint.WriteFile(self.path .. profile_name .. ".json", mint.json.encode(profile), false)
    end
    
    -- Store these defaults for future profile creation
    if not self.stored_defaults then
        self.stored_defaults = {}
    end

    self.stored_defaults[key] = defaults
end

-- Verify all profiles have all default keys
function Database:VerifyProfileDefaults(start, defaults)
	defaults = defaults or {}
    for _, profile in pairs(self.profiles) do
        self:MergeDefaults(profile.db[start], defaults)
    end
end

-- Recursive function to merge defaults with existing profile data
function Database:MergeDefaults(target, defaults)
	defaults = defaults or {}
    for key, value in pairs(defaults) do
        if target[key] == nil then
            target[key] = value
        elseif type(value) == "table" and type(target[key]) == "table" then
            self:MergeDefaults(target[key], value)
        end
    end
end

-- Create a new profile
---@param name string
---@param defaults table
---@return boolean
-- Update CreateNewProfile to use stored defaults
function Database:CreateNewProfile(name, defaults)
    if not name or name == "" then
        mint:Log("You must provide a name for the profile")
        return false
    end

    if mint.ReadFile(self.path .. name .. ".json") then
        mint:Log("A profile with that name already exists")
        return false
    end
    
    -- Create new profile with base defaults
    local new_profile = {
        name = name,
        db = defaults or {},
        kb = {}
    }
    
    -- Apply any stored defaults
    if self.stored_defaults then
        for key, default in pairs(self.stored_defaults) do
            local parent_table, final_key = self:NavigateToKey(new_profile.db, key)
            
            if not parent_table[final_key] then
                parent_table[final_key] = {}
            end
            
            self:MergeDefaults(parent_table[final_key], default)
        end
    end
    
    self.profiles[name] = new_profile
    
    -- Save the new profile
    mint.WriteFile(self.path .. name .. ".json", mint.json.encode(new_profile), false)

    return true
end

-- Get the active profile
function Database:GetActiveProfile()
    return self.profiles[self.global.current_profile]
end

-- Set the active profile
function Database:SetActiveProfile(name)
    if self.profiles[name] then
        self.global.current_profile = name

        -- Save global settings
        mint.WriteFile(self.path .. "Global.json", mint.json.encode(self._global_data), false)
        return true
    end

    return false
end

-- Save global settings to disk immediately
function Database:SaveGlobal()
    mint.WriteFile(self.path .. "Global.json", mint.json.encode(self._global_data), false)
end

-- Save a specific profile to disk immediately
function Database:SaveProfile(name)
    local profile = self.profiles[name]
    if profile then
        mint.WriteFile(self.path .. profile.name .. ".json", mint.json.encode(profile), false)
    end
end

-- Create a new profile from an existing profile
---@param name string
---@param dupe string
---@return boolean
function Database:DuplicateProfile(name, dupe)
	return self:CreateNewProfile(name, self.profiles[dupe].db)
end

-- Delete a profile by name
---@param name string
function Database:DeleteProfileByName(name)
	if not self.profiles[name] then
		error("No profile with that name exists")
		return
	end

	self.profiles[name] = nil
	mint.DeleteFile(self.path .. name .. ".json")
end

-- Import a profile
---@param data string
function Database:Import(data)
	local decoded = Base64:Decode(data)
	local decompressed = LC:Decompress(decoded)
	local deserialized = AS:Deserialize(decompressed)

	-- TODO: Make the imported data actually do stuff and things
	return deserialized
end

-- Export a profile
function Database:Export(data)
	local serialized = AS:Serialize(data)
	local compressed = LC:Compress(serialized)
	return Base64:Encode(compressed)
end


return Database