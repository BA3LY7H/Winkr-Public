-- local unlocker,
-- ---@class mint
-- mint = ...

-- ---@class Interface
-- local Interface     = mint.Interface
-- local settings = mint.Settings

-- ----------------------------
-- --- Constants/Locals
-- ----------------------------
-- local Constants     = mint.Constants or {}

-- local function ShowTooltip(frame, show, content)
-- 	if show then
-- 		GameTooltip:SetOwner(frame, "ANCHOR_RIGHT");
-- 		if type(content) == "string" then
-- 			GameTooltip:SetText(content)
-- 		elseif type(content) == "number" then
-- 			GameTooltip:SetSpellByID(content)
-- 		end
-- 	else
-- 		GameTooltip:Hide();
-- 	end
-- end

-- local className 		= select(2, UnitClass("player"))

-- Interface.Page:NewCustom("Dungeon", "dungeons", function(self)
-- 	local specIndex = GetSpecialization()
-- 	local specID = GetSpecializationInfo(specIndex)

-- 	local dungeonTabData = {
-- 		{ name = "cinderbrew_meadery", title = Constants.DungeonKeyToIcon["cinderbrew_meadery"] },
-- 		{ name = "darkflame", title = Constants.DungeonKeyToIcon["darkflame"] },
-- 		{ name = "the_rookery", title = Constants.DungeonKeyToIcon["the_rookery"] },
-- 		{ name = "priory", title = Constants.DungeonKeyToIcon["priory"] },
-- 		{ name = "motherlode", title = Constants.DungeonKeyToIcon["motherlode"] },
-- 		{ name = "operation_floodgate", title = Constants.DungeonKeyToIcon["operation_floodgate"] },
-- 		{ name = "theater_of_pain", title = Constants.DungeonKeyToIcon["theater_of_pain"] },
-- 		{ name = "mechagon", title = Constants.DungeonKeyToIcon["mechagon"] },
-- 	}

-- 	self.dungeonTabs = self.factory:TabPanel(self.pages.dungeons, nil, nil, dungeonTabData, false, 32, 32)
-- 	self.factory:GlueAcross(self.dungeonTabs, self.pages.dungeons, 10, -20, -10, 10)

-- 	-- I know we don't need this many enum functions but this makes it cleaner to separate
-- 	self.dungeonTabs:EnumerateTabs(function(tab)
-- 		local subTabs = {
-- 			{ name = "defensives", title = "Defensives" },
-- 			{ name = "stops", title = "Stops" },
-- 			{ name = "dispels", title = "Dispels" },
-- 			{ name = "reactions", title = "Reactions" },
-- 		}

-- 		tab.subTabs = self.factory:TabPanel(tab.frame, nil, nil, subTabs, false, 100, 20)

-- 		self.factory:GlueAcross(tab.subTabs, tab.frame, 15, -20, -10, 10)
-- 	end)

-- 	-- Adding Defensives
-- 	self.dungeonTabs:EnumerateTabs(function(tab)
-- 		local defensives_tab = tab.subTabs:GetTabByName("defensives")

-- 		local fs = self.factory:FontString(defensives_tab.frame, 'Defensives Coming Soon');
-- 		self.factory:GlueTop(fs, defensives_tab.frame, 0, -40);
-- 	end)

-- 	-- Adding Dispels
-- 	self.dungeonTabs:EnumerateTabs(function(tab)
-- 		local dispels_tab = tab.subTabs:GetTabByName("dispels")
-- 		self.factory:EasyLayout(dispels_tab.frame, { padding = { top = 20, right = 1, left = 1 } });

-- 		-- Filter the dispel defaults for this specific dungeon
-- 		local dispel_defaults = {}
		
-- 		-- Inject Debuffs from the dispel map into the defaults, filtered by dungeon
-- 		for spell_id, debuff_data in pairs(Constants.TWWS2.debuff_map) do
-- 			if debuff_data.dungeon == tab.name then
-- 				local icon = C_Spell.GetSpellTexture(spell_id)
-- 				local display = "|T" .. icon .. ":16|t " .. debuff_data.name

-- 				-- Build with just the danger info
-- 				local this = {
-- 					name = display,
-- 					key = debuff_data.name .. " (Dispel)",
-- 					spellId = spell_id,
-- 					class = debuff_data.class,
-- 					dungeon = debuff_data.dungeon,
-- 					enabled = true,
-- 					disabled = false
-- 				}

-- 				table.insert(dispel_defaults, this)
-- 			end
-- 		end

-- 		local dispel_columns = {
-- 			{
-- 				name   = 'Spell',
-- 				width  = 170,
-- 				align  = 'LEFT',
-- 				index  = 'name',
-- 				format = 'string',
-- 				color  = function(table, value, rowData, columnData)
-- 					local disabled = rowData.disabled
	
-- 					if disabled then 
-- 						return { r = 0.82, g = 0.82, b = 0.82, a = 0.5 };
-- 					end
	
-- 					local enabled = rowData.enabled
	
-- 					if enabled then
-- 						return { r = 1, g = 0.82, b = 0, a = 1 };
-- 					else
-- 						return { r = 1, g = 0.82, b = 0, a = 0.5 };
-- 					end
-- 				end,
-- 				events   = {
-- 					OnEnter = function(table, cellFrame, rowFrame, rowData, columnData, rowIndex)
-- 						ShowTooltip(cellFrame, true, rowData.spellId);
-- 						return false;
-- 					end,
-- 					OnLeave = function(rowFrame, cellFrame)
-- 						ShowTooltip(cellFrame, false);
-- 						return false;
-- 					end
-- 				},
-- 			},
-- 		}

-- 		local class_dispels = Constants.ClassDispelMap[className][specID]
		
-- 		-- If we cannot dispel, disable all values.
-- 		if not class_dispels then
-- 			for _, v in pairs(dispel_defaults) do
-- 				v.disabled = true
-- 				v.enabled = false
-- 			end
-- 		else
-- 			-- Add the checkboxes for each class dispel to the debuffs
-- 			for _, dispel in ipairs(class_dispels) do
-- 				-- Create a dispel id field in each debuff row
-- 				for _, v in pairs(dispel_defaults) do
-- 					v[dispel.id] = false

-- 					-- Make spells that a class cannot dispel "disabled"
-- 					if not dispel:CanDispelType(v.class) then
-- 						v.enabled = false
-- 						v.disabled = true
-- 					end
-- 				end

-- 				-- Insert the column for the dispel
-- 				table.insert(dispel_columns, {
-- 					name = "|T" .. dispel.icon .. ":18|t",
-- 					icon = dispel.icon,
-- 					width = 35,
-- 					align = 'LEFT',
-- 					index = dispel.id,
-- 					format = 'iconCheckbox',
-- 					storedValues = {
-- 						spellId = dispel.id,
-- 						name = dispel.name,
-- 						icon = dispel.icon,
-- 					},
-- 					sortable = false,
-- 				})
-- 			end
-- 		end

-- 		-- Insert the Enable checkbox at the end of the row
-- 		table.insert(dispel_columns,{
-- 			name   = 'Enabled',
-- 			width  = 60,
-- 			align  = 'LEFT',
-- 			index  = 'enabled',
-- 			format = 'checkbox',
-- 			sortable = false,
-- 		})

-- 		-- Make sure the settings profile exists
-- 		if not settings.profile[mint.class] then
-- 			settings.profile[mint.class] = {}
-- 		end
		
-- 		if not settings.profile[mint.class].dispels then
-- 			settings.profile[mint.class].dispels = {}
-- 		end
		
-- 		-- Verify defaults for this specific dungeon's dispels
-- 		settings:VerifyDefaults("dispels." .. tab.name, dispel_defaults)

-- 		-- Get the dungeon-specific dispels from the profile
-- 		local dungeon_dispels = {}
-- 		for _, dispel in ipairs(settings.profile[mint.class].dispels) do
-- 			if dispel.dungeon == tab.name then
-- 				table.insert(dungeon_dispels, dispel)
-- 			end
-- 		end

-- 		-- If we don't have any dispels for this dungeon yet, use the defaults
-- 		if #dungeon_dispels == 0 then
-- 			dungeon_dispels = dispel_defaults
			
-- 			-- Add these defaults to the profile
-- 			for _, dispel in ipairs(dispel_defaults) do
-- 				table.insert(settings.profile[mint.class].dispels, dispel)
-- 			end
-- 		end

-- 		-- Create or retrieve the table for dispels
-- 		if not self.tables then
-- 			self.tables = {}
-- 		end
		
-- 		-- Create the scroll table for this dungeon's dispels
-- 		self.tables["dispels_" .. tab.name] = self.factory:ScrollTable(dispels_tab.frame, dispel_columns, 13, 20, settings.profile[mint.class].dispels[tab.name])
-- 		local dispel_table = self.tables["dispels_" .. tab.name]
-- 		dispel_table:EnableSelection(true)
-- 		dispel_table:SetData(dungeon_dispels)

-- 		-- Set up header tooltip events
-- 		dispel_table.headerEvents = dispel_table.headerEvents or {}
-- 		dispel_table.headerEvents["OnEnter"] = function(table, columnFrame, columnHeadFrame, columnIndex, columnData)
-- 			-- Ignore first and last columns
-- 			if columnIndex == 1 or columnIndex == #table.head.columns or columnIndex == (#table.head.columns - 1) then
-- 				return false;
-- 			end

-- 			local values = table.head.columns[columnIndex].storedValues

-- 			ShowTooltip(columnHeadFrame, true, values.spellId);
-- 			return false;
-- 		end

-- 		dispel_table.headerEvents["OnLeave"] = function(table, columnFrame, columnHeadFrame, columnIndex, columnData)
-- 			-- Ignore first and last columns
-- 			if columnIndex == 1 or columnIndex == #table.head.columns then
-- 				return false;
-- 			end

-- 			ShowTooltip(columnHeadFrame, false);
-- 			return false;
-- 		end

-- 		dispel_table:RegisterEvents(dispel_table.cellEvents, dispel_table.headerEvents)

-- 		local dispel_row_1 = dispels_tab.frame:AddRow({ margin = { top = 5 } });
-- 		dispel_row_1:AddElement(dispel_table, { column = 12 });
		
-- 		dispels_tab.frame:DoLayout();
-- 	end)
-- end)