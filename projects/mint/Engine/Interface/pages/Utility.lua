local unlocker,
---@class mint
mint = ...

----------------------------
--- Constants/Locals
----------------------------
local Constants     = mint.Constants or {}
local settings 		= mint.Settings
---@class Interface
local Interface     = mint.Interface

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
--- Defaults
----------------------------

local defaults = {
    general = {

    },
    visions = {
        vision_helper = true,
        draw_potions = true,
        draw_objectives = true,
        draw_caches = true,
        draw_trash = true,
        draw_horseshoes = true,
    },
}

----------------------------
--- Page Creation
----------------------------

local utility = Interface.Page:NewCustom("Utility", "utility", false)

utility:AddDefaults(defaults)

local layout = {
	layoutConfig = { padding = { top = 15 } },
	database = settings.profile.utility.general,
	rows = {
		{
			header = {
				type = 'header',
				label = 'Utility Settings'
			}
		},
		{
			margins = {
				margin = { top = 10 }
			},
			utility_tabs = {
				type = 'tab',
                column = 12,
				key = 'utility_tabs',
                tabs = {
                    { title = 'Visions', name = 'visions' },
                    { title = 'Other', name = 'other' },
                },
                buttonWidth = 120,
                buttonHeight = 20,
				order = 1,
                children = {
                    layoutConfig = { padding = { top = 10 } },
                    database = settings.profile.utility.visions,
                    rows = {
                        {
                            margins = {
                                margin = { top = 25 },
                                order = 0,
                            },
                            vision_helper = {
                                key = 'vision_helper',
                                type = 'checkbox',
                                label = 'Enable Vision Helper',
                                tooltip = 'Provide drawings and information while doing Horrific Visions.',
                                order = 1
                            },
                        },
                        {
                            margins = {
                                margin = { top = 15 },
                                order = 0,
                            },
                            draw_potions = {
                                key = 'draw_potions',
                                type = 'checkbox',
                                label = 'Draw Potions',
                                tooltip = 'Draw the location of potions.',
                                column = 4,
                                order = 1
                            },
                            draw_objectives = {
                                key = 'draw_objectives',
                                type = 'checkbox',
                                label = 'Draw Objectives',
                                tooltip = 'Draw the location of objectives.',
                                column = 4,
                                order = 2
                            },
                            draw_caches = {
                                key = 'draw_caches',
                                type = 'checkbox',
                                label = 'Draw Caches',
                                tooltip = 'Draw the location of Black Empire Caches.',
                                column = 4,
                                order = 3
                            },
                        },
                        {
                            margins = {
                                margin = { top = 15 },
                                order = 0,
                            },
                            draw_trash = {
                                key = 'draw_trash',
                                type = 'checkbox',
                                label = 'Draw Trash',
                                tooltip = 'Draw the location of trash piles.',
                                column = 4,
                                order = 1
                            },
                            draw_horseshoes = {
                                key = 'draw_horseshoes',
                                type = 'checkbox',
                                label = 'Draw Horseshoes',
                                tooltip = 'Draw the location of Cursed Horseshoes.',
                                column = 4,
                                order = 2
                            },
                        },
                    },
                }
			},
		}
	},
}

utility:AddLayout(layout)

-- Interface.Page:NewCustom("Utility", "utility", function(self)
-- 	local categories = {
-- 		{ name = "visions", title = "Visions" },
-- 		{ name = "dispels", title = "Dispels" },
-- 		{ name = "purges", title = "Purges" },
-- 	}

-- 	self.utility_tabs = self.factory:TabPanel(self.pages.utility, nil, nil, categories, false, 80, 25)
-- 	self.factory:GlueAcross(self.utility_tabs, self.pages.utility, 10, -20, -10, 10)

-- 	local function CreateDictionaryPage(data_src, name, key)
-- 		local tab = self.utility_tabs:GetTabByName(key).frame

-- 		self.factory:EasyLayout(tab, { padding = { top = 15 } });

-- 		local columns = {
-- 			{
-- 				name   = 'Name',
-- 				width  = 170,
-- 				align  = 'LEFT',
-- 				index  = 'name',
-- 				format = 'string',
-- 				sortable = true,
-- 				defaultSort = 'asc',
-- 				color  = function(table, value, rowData, columnData)
-- 					local enabled = rowData.enabled

-- 					if enabled then
-- 						return { r = 1, g = 0.82, b = 0, a = 1 };
-- 					else
-- 						return { r = 1, g = 0.82, b = 0, a = 0.5 };
-- 					end
-- 				end,
--                 events   = {
--                     OnEnter = function(table, cellFrame, rowFrame, rowData, columnData, rowIndex)
--                         ShowTooltip(cellFrame, true, rowData.description);
--                         return false;
--                     end,
--                     OnLeave = function(rowFrame, cellFrame)
--                         ShowTooltip(cellFrame, false);
--                         return false;
--                     end
--                 },
-- 			},
-- 			{
-- 				name   = 'Instance',
-- 				width  = 100,
-- 				align  = 'LEFT',
-- 				index  = 'instance',
-- 				format = 'string',
-- 				sortable = true,
-- 				defaultSort = 'asc',
-- 				color  = function(table, value, rowData, columnData)
-- 					local enabled = rowData.enabled

-- 					if enabled then
-- 						return { r = 1, g = 0.82, b = 0, a = 1 };
-- 					else
-- 						return { r = 1, g = 0.82, b = 0, a = 0.5 };
-- 					end
-- 				end
-- 			},
-- 			{
-- 				name   = 'Type',
-- 				width  = 130,
-- 				align  = 'LEFT',
-- 				index  = 'item_type',
-- 				format = 'string',
-- 				sortable = true,
-- 				defaultSort = 'asc',
-- 				color  = function(table, value, rowData, columnData)
-- 					local enabled = rowData.enabled

-- 					if enabled then
-- 						return { r = 1, g = 0.82, b = 0, a = 1 };
-- 					else
-- 						return { r = 1, g = 0.82, b = 0, a = 0.5 };
-- 					end
-- 				end
-- 			},
-- 			{
-- 				name   = 'Enabled',
-- 				width  = 60,
-- 				align  = 'LEFT',
-- 				index  = 'enabled',
-- 				format = 'checkbox',
-- 				sortable = false,
-- 			},
-- 		}

-- 		settings:VerifyDefaults(key, defaults)
-- 		local data = settings.profile[key]

-- 		self.tables[key] = self.factory:ScrollDictionary(tab, columns, 12, 20, data)
-- 		-- self.tables[key]:EnableSelection(true)
-- 		self.tables[key]:SetData(data)


-- 		local row_one = tab:AddRow({ margin = { top = 5 } });
-- 		row_one:AddElement(self.tables[key], { column = 12 });

-- 		--! Add Dispel Input Field !--
-- 		local add_box = self.factory:SimpleEditBox(tab, 150, 24, "Spell ID");
-- 		self.factory:GlueTop(add_box, tab, 10, -40, 'LEFT');

-- 		--! Delete Button !--
-- 		self.buttons["delete_" .. key] = self.factory:Button(tab, 100, 20, 'Delete')

-- 		self.buttons["delete_" .. key]:SetScript('OnClick', function()
-- 			local selected = self.tables[key]:GetSelection()
-- 			if not selected then
-- 				mint:Log("You must select a row to delete.")
-- 				return
-- 			end

-- 			table.remove(data, selected)

-- 			self.tables[key]:SetData(data)
-- 		end)

-- 		local row_two = tab:AddRow({ margin = { top = 18 } });
-- 		row_two:AddElement(add_box, { column = 5 });
-- 		row_two:AddElement(self.factory:Frame(tab, 0, 0), { column = 5 });
-- 		row_two:AddElement(self.buttons["delete_" .. key], { column = 2 });

-- 		--! New Button !--
-- 		self.buttons["new_" .. key] = self.factory:Button(tab, 80, 20, 'Add Row')

-- 		self.buttons["new_" .. key]:SetScript('OnClick', function()
-- 			local spell_id = add_box:GetText()

-- 			if not spell_id or spell_id == '' then
-- 				mint:Log("You must enter a spell ID to add a new row.")
-- 				return
-- 			end


-- 			local spellInfo = C_Spell.GetSpellInfo(spell_id)
-- 			local spell = {
-- 				icon = spellInfo.iconID or 134400,
-- 				name = spellInfo.name or "Unknown",
-- 				spellId = spellInfo.spellID or 0,
-- 				_key = spellInfo.spellID or 0,
-- 				instance = "Custom",
-- 				enabled = false
-- 			}

-- 			local str_key = tostring(spell.spellId)

-- 			if data[str_key] then
-- 				mint:Log("This spell is already in the list.")
-- 				return
-- 			end

-- 			data[str_key] = spell
-- 			self.tables[key]:SetData(data)
-- 		end)

-- 		local row_three = tab:AddRow({ margin = { top = 5 } });
-- 		row_three:AddElement(self.buttons["new_" .. key], { column = 4 });


-- 		--! Actually populate the tab !--
-- 		tab:DoLayout();
-- 	end

-- 	CreateListPage(Constants.TWWS2.kicks, "Kicks", "kicks")
-- 	CreateListPage(Constants.TWWS2.debuff_map, "Dispels", "dispels")
-- 	CreateListPage(Constants.TWWS2.buff_map, "Purges", "purges")
-- end)