local unlocker,
---@class mint
mint = ...

---@class Interface
local Interface     = mint.Interface
local settings 		= mint.Settings

----------------------------
--- Constants/Locals
----------------------------
local Constants     	= mint.Constants or {}
local ProfileManager 	= mint.ProfileManager

----------------------------
--- Local Functions
----------------------------

local function ShowTooltip(frame, show, content)
	if show then
		GameTooltip:SetOwner(frame, "ANCHOR_RIGHT");
		if type(content) == "string" then
			GameTooltip:SetText(content)
		elseif type(content) == "number" then
			GameTooltip:SetSpellByID(content)
		end
	else
		GameTooltip:Hide();
	end
end

----------------------------
--- Page Creation
----------------------------
Interface.Page:NewCustom("Reactions", "reactions", function(self)

	local reactions = mint.Reactions
	local defaults = reactions.defaults

	self.factory:EasyLayout(self.pages.reactions, { padding = { top = 15 } });

	-- -- Create a dictionary of data 
	-- local myDict = {
	-- 	[12345] = { name = "Item One", value = 100 },
	-- 	[67890] = { name = "Item Two", value = 200 },
	-- 	[54321] = { name = "Item Three", value = 300 }
	-- }

	-- -- Define columns with a key column and other data columns
	-- -- local columns = {
	-- -- 	{ name = "ID", width = 80, index = "_key", format = "key" },
	-- -- 	{ name = "Name", width = 120, index = "name" },
	-- -- 	{ name = "Value", width = 80, index = "value", format = "number" },
	-- -- 	{ name = "Enabled", width = 60, index = "enabled", format = "checkbox" }
	-- -- }

	-- -- Create the scroll dictionary
	-- local dictTable = StdUi:ScrollDictionary(parent, columns, 10, 20, myDict)

	-- -- Set the data
	-- dictTable:SetData(myDict)

	-- -- You can now use dictionary-specific methods
	-- dictTable:GetValueByKey(12345)           -- Get a value by key
	-- dictTable:SetValueByKey(12345, newValue) -- Set a value by key
	-- dictTable:RemoveKey(67890)               -- Remove a key
	-- dictTable:ScrollToKey(54321)             -- Scroll to display a specific key

	local reaction_columns = {
		{
			name   = 'Trigger',
			width  = 150,
			align  = 'LEFT',
			index  = 'trigger_name',
			format = 'string',
			color  = function(table, value, rowData, columnData)
				local disabled = rowData.disabled

				if disabled then 
					return { r = 0.82, g = 0.82, b = 0.82, a = 0.5 };
				end

				local enabled = rowData.enabled

				if enabled then
					return { r = 1, g = 0.82, b = 0, a = 1 };
				else
					return { r = 1, g = 0.82, b = 0, a = 0.5 };
				end
			end,
			events   = {
				OnEnter = function(table, cellFrame, rowFrame, rowData, columnData, rowIndex)
					ShowTooltip(cellFrame, true, rowData.trigger_id);
					return false;
				end,
				OnLeave = function(rowFrame, cellFrame)
					ShowTooltip(cellFrame, false);
					return false;
				end
			},
		},
		{
			name   = 'Reaction',
			width  = 150,
			align  = 'LEFT',
			index  = 'react_name',
			format = 'string',
			color  = function(table, value, rowData, columnData)
				local disabled = rowData.disabled

				if disabled then 
					return { r = 0.82, g = 0.82, b = 0.82, a = 0.5 };
				end

				local enabled = rowData.enabled

				if enabled then
					return { r = 1, g = 0.82, b = 0, a = 1 };
				else
					return { r = 1, g = 0.82, b = 0, a = 0.5 };
				end
			end,
			events   = {
				OnEnter = function(table, cellFrame, rowFrame, rowData, columnData, rowIndex)
					ShowTooltip(cellFrame, true, rowData.description);
					return false;
				end,
				OnLeave = function(rowFrame, cellFrame)
					ShowTooltip(cellFrame, false);
					return false;
				end
			},
		},
		{
			name   = 'Dungeon',
			width  = 60,
			align  = 'LEFT',
			index  = 'dungeon',
			format = 'string',
			sortable = true,
		},
		{
			name   = 'Enabled',
			width  = 60,
			align  = 'LEFT',
			index  = 'enabled',
			format = 'checkbox',
			sortable = false,
		}
	}

	-- Data from the defaults/existing settings
	settings:VerifyDefaults("reactions", defaults)
	local data = settings.profile.reactions

	local class_data = {}
	for k, v in pairs(settings.profile.reactions) do
		if string.lower(v.class) == mint.class then
			class_data[k] = v
		end
	end

	-- Creating the dictionary
	self.tables.reactions = self.factory:ScrollDictionary(self.pages.reactions, reaction_columns, 12, 20, data)
	self.tables.reactions:SetData(class_data)

	-- You can now use dictionary-specific methods
	-- dictTable:GetValueByKey(12345)           -- Get a value by key
	-- dictTable:SetValueByKey(12345, newValue) -- Set a value by key
	-- dictTable:RemoveKey(67890)               -- Remove a key
	-- dictTable:ScrollToKey(54321)             -- Scroll to display a specific key

	-- settings:VerifyDefaults("reactions", defaults)
	-- local data = settings.profile.reactions

	-- local class_data = {}
	-- for _, v in ipairs(settings.profile.reactions) do
	-- 	if string.lower(v.class) == mint.class then
	-- 		table.insert(class_data, v)
	-- 	end
	-- end

	-- self.tables.reactions = self.factory:ScrollTable(self.pages.reactions, reaction_columns, 12, 20, data)
	-- self.tables.reactions:EnableSelection(true)
	-- self.tables.reactions:SetData(class_data)

	local row_one = self.pages.reactions:AddRow({ margin = { top = 5 } });
	row_one:AddElement(self.tables.reactions, { column = 12 });

	self.pages.reactions:DoLayout()
end)