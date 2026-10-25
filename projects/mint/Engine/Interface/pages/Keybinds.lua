local unlocker,
---@class mint
mint = ...

---@class Interface
local Interface     = mint.Interface
local settings = mint.Settings

----------------------------
--- Constants/Locals
----------------------------
local Constants     = mint.Constants or {}
local KBTDesc       = Constants.KeybindTargetDescriptions
local _, _, ClassID = UnitClass("player")

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

local function showTooltip(frame, show, spellId)
	if show then
		GameTooltip:SetOwner(frame, "ANCHOR_RIGHT");
		GameTooltip:SetSpellByID(spellId)
	else
		GameTooltip:Hide();
	end
end

local function targetTooltip(frame, show, name)
	if show then
		GameTooltip:SetOwner(frame, "ANCHOR_RIGHT");
		GameTooltip:SetText(KBTDesc[name])
	else
		GameTooltip:Hide();
	end
end

-- Create a table of all of the user's known spells
local function GetAllSpellData()
	local spells = {}

	local num_tabs = C_SpellBook.GetNumSpellBookSkillLines()

	for i = 2, num_tabs do
		local info = C_SpellBook.GetSpellBookSkillLineInfo(i)
		local offset = info.itemIndexOffset
		local slots = info.numSpellBookItems

		for j = offset + 1, offset + slots do
			local spell_info = C_SpellBook.GetSpellBookItemInfo(j, 0)
			local passive = spell_info.isPassive
			local offspec = spell_info.isOffSpec
			local isSpell = spell_info.itemType == Enum.SpellBookItemType.Spell or false

			-- We don't want to see passive spells or off-spec spells
			if not passive and not offspec and isSpell then
				local name = spell_info.name
				local id = spell_info.spellID
				local icon = spell_info.iconID

				local text = "|T" .. icon .. ":18|t " .. name

				table.insert(spells, { text = text, value = id })
			end
		end
	end

	return spells
end

----------------------------
--- Page Creation
----------------------------
Interface.Page:NewCustom("Keybinds", "keybinds", function(self)
	self.factory:EasyLayout(self.pages.keybinds, { padding = { top = 15 } });

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
					showTooltip(cellFrame, true, rowData.spellId);
					return false;
				end,
				OnLeave = function(rowFrame, cellFrame)
					showTooltip(cellFrame, false);
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
			name   = 'Keybind',
			width  = 80,
			align  = 'LEFT',
			index  = 'keybind',
			format = 'string',
			events = {
				OnDoubleClick = function(table, cellFrame, rowFrame, rowData, columnData, rowIndex)
					if mint.Keybinds:IsListening() then
						mint.Keybinds:StopListening()
					else
						mint.Keybinds:StartListening(table, cellFrame, rowData, rowIndex)
					end
				end,
				OnEnter = function(table, cellFrame, rowFrame, rowData, columnData, rowIndex)
					ShowTooltip(cellFrame, true, "Double click to start listener.");
					return false;
				end,
				OnLeave = function(rowFrame, cellFrame)
					ShowTooltip(cellFrame, false);
					return false;
				end
				
			},
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
			name   = 'Target',
			width  = 100,
			align  = 'LEFT',
			index  = 'target',
			format = 'dropdown',
			options = {
				{ text = 'Target', value = 'Target' },
				{ text = 'Mouseover', value = 'Mouseover' },
				{ text = 'Focus', value = 'Focus' },
				{ text = 'Cursor', value = 'Cursor' },
				{ text = 'Self', value = 'Self' },
			},
			events = {
				OnEnter = function(table, cellFrame, rowFrame, rowData, columnData, rowIndex)
					local cellData = rowData[columnData.index];
					targetTooltip(cellFrame, true, rowData.target);
					return false;
				end,
				OnLeave = function(rowFrame, cellFrame)
					targetTooltip(cellFrame, false);
					return false;
				end
			},
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
			format = 'bindCheckbox',
			sortable = false,
		},
	}

	local bind_data = settings.keybinds[mint.class]

	self.tables.keybinds = self.factory:ScrollTable(self.pages.keybinds, columns, 15, 20, settings.keybinds[mint.class])
	self.tables.keybinds:EnableSelection(true)
	self.tables.keybinds:SetData(bind_data)


	local keybinds_row_1 = self.pages.keybinds:AddRow({ margin = { top = 5 } });
	keybinds_row_1:AddElement(self.tables.keybinds, { column = 12 });

	--! Dropdown for Spells !--
	self.dropdowns.spells = self.factory:Dropdown(self.pages.keybinds, 150, 30, GetAllSpellData(), nil, false);
	self.dropdowns.spells:SetPlaceholder('-- Select Spell --')
	self.factory:AddLabel(self.pages.keybinds, self.dropdowns.spells, 'Add New Keybind', 'TOP')

	--! Delete Keybind Button !--
	self.buttons.del_keybind = self.factory:Button(self.pages.keybinds, 100, 20, 'Delete')

	self.buttons.del_keybind:SetScript('OnClick', function()
		local selected = self.tables.keybinds:GetSelection()
		if not selected then
			mint:Log("You must select a keybind to delete.")
			return
		end

		table.remove(bind_data, selected)

		self.tables.keybinds:SetData(bind_data)
	end)

	local keybinds_row_2 = self.pages.keybinds:AddRow({ margin = { top = 18 } });
	keybinds_row_2:AddElement(self.dropdowns.spells, { column = 5 });
	keybinds_row_2:AddElement(self.factory:Frame(self.pages.keybinds, 0, 0), { column = 5 });
	keybinds_row_2:AddElement(self.buttons.del_keybind, { column = 2 });

	--! New Keybind Button !--
	self.buttons.new_keybind = self.factory:Button(self.pages.keybinds, 80, 20, 'New Keybind')

	local function AddNewRow()
		if not self.dropdowns.spells:GetValue() then
			mint:Log("You must select a spell to add a new keybind.")
			return
		end

		local spellInfo = C_Spell.GetSpellInfo(self.dropdowns.spells:GetValue())
		local spell = {
			icon = spellInfo.iconID or 134400,
			name = spellInfo.name or "Unknown",
			spellId = spellInfo.spellID or 0,
			keybind = "None",
			target = "Target",
			enabled = false
		}

		tinsert(bind_data, spell)
		self.tables.keybinds:SetData(bind_data)
	end

	self.buttons.new_keybind:SetScript('OnClick', AddNewRow)

	local keybinds_row_3 = self.pages.keybinds:AddRow({ margin = { top = 5 } });
	keybinds_row_3:AddElement(self.buttons.new_keybind, { column = 4 });
	-- keybinds_row_3:AddElements(self.buttons.new_keybind, self.buttons.del_keybind, { column = 'even' });


	--! Actually populate the tab !--
	self.pages.keybinds:DoLayout();
end)