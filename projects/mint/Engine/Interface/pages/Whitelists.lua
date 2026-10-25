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
Interface.Page:NewCustom("Lists", "lists", function(self)
	local lists = {
		{ name = "kicks", title = "Kicks" },
		{ name = "dispels", title = "Dispels" },
		{ name = "purges", title = "Purges" },
	}

	self.listTabs = self.factory:TabPanel(self.pages.lists, nil, nil, lists, false, 80, 25)
	self.factory:GlueAcross(self.listTabs, self.pages.lists, 10, -20, -10, 10)

	local function CreateListPage(data_src, name, key)
		local tab = self.listTabs:GetTabByName(key).frame

		self.factory:EasyLayout(tab, { padding = { top = 15 } });

		local columns = {
			{
				name     = 'Icon',
				width    = 40,
				align    = 'CENTER',
				index    = 'icon',
				format   = 'icon',
				sortable = false,
				events   = {
					OnEnter = function(table, cellFrame, rowFrame, rowData, columnData, rowIndex)
						ShowTooltip(cellFrame, true, rowData.spellId);
						return false;
					end,
					OnLeave = function(rowFrame, cellFrame)
						ShowTooltip(cellFrame, false);
						return false;
					end
				},
			},
			{
				name   = 'Spell',
				width  = 170,
				align  = 'LEFT',
				index  = 'name',
				format = 'string',
				sortable = true,
				defaultSort = 'asc',
				color  = function(table, value, rowData, columnData)
					local enabled = rowData.enabled

					if enabled then
						return { r = 1, g = 0.82, b = 0, a = 1 };
					else
						return { r = 1, g = 0.82, b = 0, a = 0.5 };
					end
				end
			},
			{
				name   = 'Enabled',
				width  = 60,
				align  = 'LEFT',
				index  = 'enabled',
				format = 'checkbox',
				sortable = false,
			},
			{
				name   = 'Instance',
				width  = 130,
				align  = 'LEFT',
				index  = 'instance',
				format = 'string',
				sortable = true,
				defaultSort = 'asc',
				color  = function(table, value, rowData, columnData)
					local enabled = rowData.enabled

					if enabled then
						return { r = 1, g = 0.82, b = 0, a = 1 };
					else
						return { r = 1, g = 0.82, b = 0, a = 0.5 };
					end
				end
			},
		}

		local defaults = {}

		for k, data in pairs(data_src) do
			local spell = data.spell
			local this = {
				icon = spell.icon,
				name = spell.name,
				spellId = spell.id,
				_key = spell.id,
				enabled = true,
				instance = Constants.DungeonKeyToName[data.dungeon],
			}

			local str_key = tostring(k)

			defaults[str_key] = this
		end

		settings:VerifyDefaults(key, defaults)
		local data = settings.profile[key]

		self.tables[key] = self.factory:ScrollDictionary(tab, columns, 12, 20, data)
		-- self.tables[key]:EnableSelection(true)
		self.tables[key]:SetData(data)


		local row_one = tab:AddRow({ margin = { top = 5 } });
		row_one:AddElement(self.tables[key], { column = 12 });

		--! Add Dispel Input Field !--
		local add_box = self.factory:SimpleEditBox(tab, 150, 24, "Spell ID");
		self.factory:GlueTop(add_box, tab, 10, -40, 'LEFT');

		--! Delete Button !--
		self.buttons["delete_" .. key] = self.factory:Button(tab, 100, 20, 'Delete')

		self.buttons["delete_" .. key]:SetScript('OnClick', function()
			local selected = self.tables[key]:GetSelection()
			if not selected then
				mint:Log("You must select a row to delete.")
				return
			end

			table.remove(data, selected)

			self.tables[key]:SetData(data)
		end)

		local row_two = tab:AddRow({ margin = { top = 18 } });
		row_two:AddElement(add_box, { column = 5 });
		row_two:AddElement(self.factory:Frame(tab, 0, 0), { column = 5 });
		row_two:AddElement(self.buttons["delete_" .. key], { column = 2 });

		--! New Button !--
		self.buttons["new_" .. key] = self.factory:Button(tab, 80, 20, 'Add Row')

		self.buttons["new_" .. key]:SetScript('OnClick', function()
			local spell_id = add_box:GetText()

			if not spell_id or spell_id == '' then
				mint:Log("You must enter a spell ID to add a new row.")
				return
			end


			local spellInfo = C_Spell.GetSpellInfo(spell_id)
			local spell = {
				icon = spellInfo.iconID or 134400,
				name = spellInfo.name or "Unknown",
				spellId = spellInfo.spellID or 0,
				_key = spellInfo.spellID or 0,
				instance = "Custom",
				enabled = false
			}

			local str_key = tostring(spell.spellId)

			if data[str_key] then
				mint:Log("This spell is already in the list.")
				return
			end

			data[str_key] = spell
			self.tables[key]:SetData(data)
		end)

		local row_three = tab:AddRow({ margin = { top = 5 } });
		row_three:AddElement(self.buttons["new_" .. key], { column = 4 });


		--! Actually populate the tab !--
		tab:DoLayout();
	end

	CreateListPage(Constants.TWWS2.kicks, "Kicks", "kicks")
	CreateListPage(Constants.TWWS2.debuff_map, "Dispels", "dispels")
	CreateListPage(Constants.TWWS2.buff_map, "Purges", "purges")
end)