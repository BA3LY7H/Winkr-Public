-- local unlocker,
-- ---@class mint
-- mint = ...

-- ---@class Interface
-- ---@field config Config
-- ---@field ui_config Config
-- ---@field keybind_config Config
-- ---@field mint_tiny Font
-- ---@field mint_normal Font
-- ---@field mint_large Font
-- ---@field bind_data table
-- ---@field factory StdUi
-- ---@field keybinds Keybinds
-- ---@field tabs table
-- ---@field toggles table
-- ---@field dropdowns table
-- ---@field sliders table
-- ---@field quickbuttons table
-- ---@field labels table
-- ---@field tables table
-- ---@field buttons table
-- ---@field buttonfactory table
-- local Interface     = {}
-- Interface.__index   = Interface

-- ----------------------------
-- --- Constants/Locals
-- ----------------------------

-- local Constants     = mint.Constants or {}
-- local ProfileManager = mint.ProfileManager
-- local KBTDesc       = Constants.KeybindTargetDescriptions
-- local L             = mint.Localization
-- local _, _, ClassID = UnitClass("player")

-- local blank         = {
-- 	icon = 1505928, -- Blank piece of paper
-- 	name = "Add Keybinds to Start",
-- 	spellId = 0,
-- 	keybind = "None",
-- 	target = "Target",
-- 	enabled = "False"
-- }

-- ----------------------------
-- --- Interface
-- ----------------------------

-- function Interface:New()
-- 	local self = setmetatable({}, Interface)

-- 	self.config = ProfileManager:GetActiveConfig()
-- 	self.keybind_config = ProfileManager:GetActiveKeybinds()
-- 	self.ui_config = mint.Config:New("Mint UI")


-- 	self.mint_tiny = CreateFont("MintFontSmall")
-- 	self.mint_normal = CreateFont("MintFontNormal")
-- 	self.mint_large = CreateFont("MintFontLarge")

-- 	self.mint_tiny:SetFont("Fonts\\frizqt__.ttf", 8, "OUTLINE")
-- 	self.mint_normal:SetFont("Fonts\\frizqt__.ttf", 10, "OUTLINE")
-- 	self.mint_large:SetFont("Fonts\\frizqt__.ttf", 12, "OUTLINE")

-- 	self.bind_data = self.keybind_config:Read(ClassID .. "_KeyBinds", {})

-- 	self.factory = mint.StdUi:NewInstance()

-- 	self.factory.config = {
-- 		font        = {
-- 			family    = "MintFontNormal",
-- 			size      = 10,
-- 			titleSize = 14,
-- 			effect    = 'NONE',
-- 			strata    = 'OVERLAY',
-- 			color     = {
-- 				normal   = { r = 1, g = 0.82, b = 0, a = 1 },
-- 				disabled = { r = 1, g = 1, b = 1, a = 1 },
-- 				header   = { r = 1, g = 0.9, b = 0, a = 1 },
-- 				element  = { r = 1, g = 1, b = 1, a = 1 },
-- 				label    = { r = 1, g = 1, b = 1, a = 1 },
-- 			}
-- 		},

-- 		backdrop    = {
-- 			texture               = [[Interface\Buttons\WHITE8X8]],
-- 			panel                 = {
-- 				r = 0.054,
-- 				g = 0.054,
-- 				b = 0.054,
-- 				a = 0.8
-- 				-- r = 0.054901960784313725,
-- 				-- g = 0.050980392156862744,
-- 				-- b = 0.06666666666666667,
-- 				-- a = 0.9
-- 			},
-- 			slider                = { r = 0.15, g = 0.15, b = 0.15, a = 1 },

-- 			-- This is unknown atm
-- 			highlight             = { r = 1, g = 0, b = 0, a = 0.5 },
-- 			-- Button and checkbox background
-- 			button                = { r = 0.054, g = 0.054, b = 0.054, a = 0.85 },

-- 			dropdown              = { r = 0.1, g = 0.1, b = 0.1, a = 0.85 },

-- 			-- Selected button
-- 			buttonSelected        = {
-- 				r = 1,
-- 				g = 0.82,
-- 				b = 0,
-- 				a = 0.4
-- 			},
-- 			-- Disabled button, but this isn't used and buttonSelected is used instead
-- 			buttonDisabled        = { r = 1, g = 0, b = 0, a = 1 },

-- 			border                = { r = 0.00, g = 0.00, b = 0.00, a = 1 },
-- 			borderDisabled        = { r = 0.00, g = 0.00, b = 0.00, a = 1 }, -- not used
-- 			borderSelected        = { r = 1, g = 0.82, b = 0, a = 1 }, -- used for selected AND disabled

-- 			-- Used for Checkboxes
-- 			checkedBorderSelected = { r = 1, g = 0.82, b = 0, a = 1 },

-- 			-- Dropdowns
-- 			ddHover               = { r = 0.15, g = 0.15, b = 0.15, a = 0.85 },
-- 			ddBorderHover         = { r = 0.1, g = 0.1, b = 0.1, a = 1 },

-- 		},

-- 		progressBar = {
-- 			color = { r = 1, g = 0.9, b = 0, a = 0.5 },
-- 		},

-- 		-- This is the highlight when you hover over buttons
-- 		-- literally just always use alpha 0 this is cooked
-- 		highlight   = {
-- 			color = { r = 1, g = 0.82, b = 0, a = 0 },
-- 			blank = { r = 0, g = 0, b = 0, a = 0 }
-- 		},

-- 		tables      = {
-- 			hover = { r = 0.15, g = 0.15, b = 0.15, a = 0.85 },
-- 			select = { r = 0.15, g = 0.15, b = 0.15, a = 0.85 },
-- 		},

-- 		dialog      = {
-- 			width  = 400,
-- 			height = 100,
-- 			button = {
-- 				width  = 100,
-- 				height = 20,
-- 				margin = 5
-- 			}
-- 		},

-- 		tooltip     = {
-- 			padding = 10
-- 		}
-- 	};

-- 	self.tabs = {}
-- 	self.toggles = {}
-- 	self.dropdowns = {}
-- 	self.sliders = {}
-- 	self.quickbuttons = {}
-- 	self.tables = {}
-- 	self.buttons = {}
-- 	self.labels = {}

-- 	self.buttonfactory = {}

-- 	self:Init()

-- 	local _, _, ClassID = UnitClass("player")

-- 	self:AddQuickButton("Inv_misc_herb_jadetealeaf", "MintToggle", "Toggle", function()
-- 		mint.events:TriggerEvent("toggle")
-- 	end)

-- 	self:AddQuickButton(Constants.QuickbarIconsByClass[ClassID][1], "MintCooldowns", "CDs", function()
-- 		mint.events:TriggerEvent("cooldowns")
-- 	end)

-- 	self:AddQuickButton(Constants.QuickbarIconsByClass[ClassID][2], "MintKicks", "Kicks", function()
-- 		mint.events:TriggerEvent("kicks")
-- 	end)

-- 	self:AddQuickButton(Constants.QuickbarIconsByClass[ClassID][3], "MintDefensives", "Defs", function()
-- 		mint.events:TriggerEvent("defensives")
-- 	end)

-- 	-- self:InitQuickbar()

-- 	return self
-- end

-- ------------------------------
-- --- Hotbars
-- ------------------------------

-- function Interface:AddQuickButton(icon, name, label, cb)
-- 	table.insert(self.buttonfactory, { icon = icon, name = name, label = label, cb = cb })
-- end

-- function Interface:InitQuickbar()
-- 	local buttoncount = #self.buttonfactory

-- 	self.hotbar = self.factory:Panel(UIParent, 50 * buttoncount, 60)
-- 	self.hotbar:SetMovable(true)
-- 	self.hotbar:EnableMouse(true)
-- 	self.hotbar:RegisterForDrag("LeftButton")
-- 	self.hotbar:SetScript("OnDragStart", function(this, button)
-- 		this:StartMoving()
-- 	end)
-- 	self.hotbar:SetScript("OnDragStop", function(this)
-- 		this:StopMovingOrSizing()
-- 		local point, _, relativePoint, offsetX, offsetY = this:GetPoint()

-- 		local position = {
-- 			point = point,
-- 			relativePoint = relativePoint,
-- 			offsetX = offsetX,
-- 			offsetY = offsetY
-- 		}
-- 		self.ui_config:Write("hotbar_anchor", position)
-- 	end)

-- 	local position = self.ui_config:Read("hotbar_anchor", nil)

-- 	if position then
-- 		self.hotbar:SetPoint(position.point, position.offsetX, position.offsetY)
-- 	else
-- 		self.hotbar:SetPoint("CENTER", 0, 0)
-- 	end

-- 	for i, button in ipairs(self.buttonfactory) do
-- 		self.quickbuttons[button.name] = mint.QuickButton:New(self.hotbar, 50, 50, "Interface\\Icons\\" .. button.icon,
-- 			button.name, button.cb)

-- 		self.factory:GlueLeft(self.quickbuttons[button.name].button, self.hotbar, 50 * (i - 1), 5, true)

-- 		local toggle_string = self.factory:FontString(self.hotbar, button.label);
-- 		self.factory:GlueBottom(toggle_string, self.quickbuttons[button.name].button, 0, -10);
-- 	end
-- end

-- ------------------------------
-- --- Creating the Options UI
-- ------------------------------

-- local function showTooltip(frame, show, spellId)
-- 	if show then
-- 		GameTooltip:SetOwner(frame, "ANCHOR_RIGHT");
-- 		-- GameTooltip:SetPoint('RIGHT');
-- 		GameTooltip:SetSpellByID(spellId)
-- 	else
-- 		GameTooltip:Hide();
-- 	end
-- end

-- local function targetTooltip(frame, show, name)
-- 	if show then
-- 		GameTooltip:SetOwner(frame, "ANCHOR_RIGHT");
-- 		GameTooltip:SetText(KBTDesc[name])
-- 	else
-- 		GameTooltip:Hide();
-- 	end
-- end

-- -- Create a table of all of the user's known spells
-- local function GetAllSpellData()
-- 	local spells = {}

-- 	local num_tabs = C_SpellBook.GetNumSpellBookSkillLines()

-- 	for i = 2, num_tabs do
-- 		local info = C_SpellBook.GetSpellBookSkillLineInfo(i)
-- 		local offset = info.itemIndexOffset
-- 		local slots = info.numSpellBookItems

-- 		for j = offset + 1, offset + slots do
-- 			local spell_info = C_SpellBook.GetSpellBookItemInfo(j, 0)
-- 			local passive = spell_info.isPassive
-- 			local offspec = spell_info.isOffSpec
-- 			local isSpell = spell_info.itemType == Enum.SpellBookItemType.Spell or false

-- 			-- We don't want to see passive spells or off-spec spells
-- 			if not passive and not offspec and isSpell then
-- 				local name = spell_info.name
-- 				local id = spell_info.spellID
-- 				local icon = spell_info.iconID

-- 				local text = "|T" .. icon .. ":18|t " .. name

-- 				table.insert(spells, { text = text, value = id })
-- 			end
-- 		end
-- 	end

-- 	return spells
-- end

-- function Interface:InitPage(callback)
-- 	callback(self)
-- end

-- function Interface:Init()
-- 	--! Main Window !--
-- 	self.window = self.factory:Window(UIParent, 700, 500, "|TInterface\\Icons\\Inv_misc_herb_jadetealeaf:16|t |cFFFFFFFFMint|r")
-- 	self.window:SetPoint("CENTER")

-- 	-- Main window tabs
-- 	local tabs = {
-- 		{ name = "general_settings", title = "General Settings" },
-- 		{ name = "keybind_settings", title = "Keybinds" },
-- 		{ name = "lists_settings",   title = "Lists" },
-- 		{ name = "dungeons_settings",   title = "Dungeons" },
-- 		{ name = "profile_settings",   title = "Profiles" },
-- 	}

-- 	--! Creating the tabs !--
-- 	self.menu_panel = self.factory:TabPanel(self.window, nil, nil, tabs, true, nil, 25)
-- 	self.factory:GlueAcross(self.menu_panel, self.window, 10, -40, -10, 10)

-- 	local general      = self.menu_panel:GetTabByName("general_settings");
-- 	local keybinds     = self.menu_panel:GetTabByName("keybind_settings");
-- 	local lists        = self.menu_panel:GetTabByName("lists_settings");
-- 	local dungeons     = self.menu_panel:GetTabByName("dungeons_settings");
-- 	local profiles     = self.menu_panel:GetTabByName("profile_settings");

-- 	self.tabs.general  = general.frame
-- 	self.tabs.keybinds = keybinds.frame
-- 	self.tabs.lists    = lists.frame
-- 	self.tabs.dungeons = dungeons.frame
-- 	self.tabs.profiles = profiles.frame

-- 	------------------------------
-- 	--- General Settings
-- 	------------------------------
-- 	self.factory:EasyLayout(self.tabs.general, { padding = { top = 5 } });

-- 	--! Debug Toggle !--
-- 	self.toggles.debug = self.factory:Checkbox(self.tabs.general, 'Debug Mode');
-- 	local gen_row_1 = self.tabs.general:AddRow({ margin = { top = 5 } });
-- 	gen_row_1:AddElement(self.toggles.debug, { column = 12 });

-- 	local arrow_colors = {
-- 		{ text = '|cff00d8ff Cyan |r',   value = 'cyan' }, -- 00d8ff
-- 		{ text = '|cffffd200 Gold |r',   value = 'gold' }, -- ffd200
-- 		{ text = '|cff00ff12 Lime |r',   value = 'lime' }, -- 00ff12
-- 		{ text = '|cffffffff White |r',  value = 'white' }, -- ffffff
-- 		{ text = '|cffff2114 Red |r',    value = 'red' }, -- ff2114
-- 		{ text = '|cffff8000 Orange |r', value = 'orange' }, -- ff8000
-- 		{ text = '|cfffff809 Yellow |r', value = 'yellow' }, -- fff809
-- 		{ text = '|cffff80ff Pink |r',   value = 'pink' }, -- ff80ff
-- 		{ text = '|cffc845fa Purple |r', value = 'purple' }, -- c845fa
-- 	};

-- 	local arrows_persisted = self.config:Read("arrow_color", nil)

-- 	self.dropdowns.facing_arrow_color = self.factory:Dropdown(self.tabs.general, 200, 30, arrow_colors, arrows_persisted,
-- 		false);
-- 	self.dropdowns.facing_arrow_color:SetPlaceholder('-- Arrow Color --')
-- 	self.factory:AddLabel(self.tabs.general, self.dropdowns.facing_arrow_color, 'Facing Arrow Color', 'TOP')

-- 	self.dropdowns.facing_arrow_color.OnValueChanged = function(this, value)
-- 		self.config:Write("arrow_color", value)
-- 	end

-- 	local gen_row_2 = self.tabs.general:AddRow({ margin = { top = 45 } });
-- 	gen_row_2:AddElement(self.dropdowns.facing_arrow_color, { column = 5 });

-- 	--! Actually populate the tab !--
-- 	self.tabs.general:DoLayout();

-- 	------------------------------
-- 	--- Keybind Settings
-- 	------------------------------
-- 	self.factory:EasyLayout(self.tabs.keybinds, { padding = { top = 15 } });

-- 	-- local data = {
-- 	-- 	{ icon = 253400, name = C_Spell.GetSpellName(62618), spellId = 62618, keybind = "MB5", target = "Mouseover", enabled = "True" }
-- 	-- }


-- 	local columns = {
-- 		{
-- 			name     = 'Icon',
-- 			width    = 40,
-- 			align    = 'CENTER',
-- 			index    = 'icon',
-- 			format   = 'icon',
-- 			sortable = false,
-- 			events   = {
-- 				OnEnter = function(table, cellFrame, rowFrame, rowData, columnData, rowIndex)
-- 					showTooltip(cellFrame, true, rowData.spellId);
-- 					return false;
-- 				end,
-- 				OnLeave = function(rowFrame, cellFrame)
-- 					showTooltip(cellFrame, false);
-- 					return false;
-- 				end
-- 			},
-- 		},
-- 		{
-- 			name   = 'Spell',
-- 			width  = 170,
-- 			align  = 'LEFT',
-- 			index  = 'name',
-- 			format = 'string',
-- 			color  = function(table, value, rowData, columnData)
-- 				local enabled = rowData.enabled

-- 				if enabled then
-- 					return { r = 1, g = 0.82, b = 0, a = 1 };
-- 				else
-- 					return { r = 1, g = 0.82, b = 0, a = 0.5 };
-- 				end
-- 			end
-- 		},
-- 		{
-- 			name   = 'Keybind',
-- 			width  = 80,
-- 			align  = 'LEFT',
-- 			index  = 'keybind',
-- 			format = 'string',
-- 			events = {
-- 				OnDoubleClick = function(table, cellFrame, rowFrame, rowData, columnData, rowIndex)
-- 					local cellData = rowData[columnData.index];

-- 					if mint.Keybinds:IsListening() then
-- 						mint.Keybinds:StopListening()
-- 					else
-- 						mint.Keybinds:StartListening(table, cellFrame, rowData, rowIndex)
-- 					end
-- 				end,
-- 			},
-- 			color  = function(table, value, rowData, columnData)
-- 				local enabled = rowData.enabled

-- 				if enabled then
-- 					return { r = 1, g = 0.82, b = 0, a = 1 };
-- 				else
-- 					return { r = 1, g = 0.82, b = 0, a = 0.5 };
-- 				end
-- 			end
-- 		},
-- 		{
-- 			name   = 'Target',
-- 			width  = 100,
-- 			align  = 'LEFT',
-- 			index  = 'target',
-- 			format = 'dropdown',
-- 			options = {
-- 				{ text = 'Target', value = 'Target' },
-- 				{ text = 'Mouseover', value = 'Mouseover' },
-- 				{ text = 'Focus', value = 'Focus' },
-- 				{ text = 'Cursor', value = 'Cursor' },
-- 				{ text = 'Self', value = 'Self' },
-- 			},
-- 			events = {
-- 				OnEnter = function(table, cellFrame, rowFrame, rowData, columnData, rowIndex)
-- 					local cellData = rowData[columnData.index];
-- 					targetTooltip(cellFrame, true, rowData.target);
-- 					return false;
-- 				end,
-- 				OnLeave = function(rowFrame, cellFrame)
-- 					targetTooltip(cellFrame, false);
-- 					return false;
-- 				end
-- 			},
-- 			color  = function(table, value, rowData, columnData)
-- 				local enabled = rowData.enabled

-- 				if enabled then
-- 					return { r = 1, g = 0.82, b = 0, a = 1 };
-- 				else
-- 					return { r = 1, g = 0.82, b = 0, a = 0.5 };
-- 				end
-- 			end
-- 		},
-- 		{
-- 			name   = 'Enabled',
-- 			width  = 60,
-- 			align  = 'LEFT',
-- 			index  = 'enabled',
-- 			format = 'bindCheckbox',
-- 			sortable = false,
-- 		},
-- 	}

-- 	self.tables.keybinds = self.factory:ScrollTable(self.tabs.keybinds, columns, 15, 20, self.keybind_config,
-- 		ClassID .. "_KeyBinds")
-- 	self.tables.keybinds:EnableSelection(true)
-- 	self.tables.keybinds:SetData(self.bind_data)


-- 	local keybinds_row_1 = self.tabs.keybinds:AddRow({ margin = { top = 5 } });
-- 	keybinds_row_1:AddElement(self.tables.keybinds, { column = 12 });

-- 	--! Dropdown for Spells !--
-- 	self.dropdowns.spells = self.factory:Dropdown(self.tabs.keybinds, 150, 30, GetAllSpellData(), nil, false);
-- 	self.dropdowns.spells:SetPlaceholder('-- Select Spell --')
-- 	self.factory:AddLabel(self.tabs.keybinds, self.dropdowns.spells, 'Add New Keybind', 'TOP')

-- 	--! Delete Keybind Button !--
-- 	self.buttons.del_keybind = self.factory:Button(self.tabs.keybinds, 100, 20, 'Delete')

-- 	self.buttons.del_keybind:SetScript('OnClick', function()
-- 		local selected = self.tables.keybinds:GetSelection()
-- 		if not selected then
-- 			mint:Log("You must select a keybind to delete.")
-- 			return
-- 		end

-- 		table.remove(self.bind_data, selected)

-- 		self.tables.keybinds:SetData(self.bind_data)
-- 		mint.Keybinds:Update()
-- 	end)

-- 	local keybinds_row_2 = self.tabs.keybinds:AddRow({ margin = { top = 18 } });
-- 	keybinds_row_2:AddElement(self.dropdowns.spells, { column = 5 });
-- 	keybinds_row_2:AddElement(self.factory:Frame(self.tabs.keybinds, 0, 0), { column = 5 });
-- 	keybinds_row_2:AddElement(self.buttons.del_keybind, { column = 2 });

-- 	--! New Keybind Button !--
-- 	self.buttons.new_keybind = self.factory:Button(self.tabs.keybinds, 80, 20, 'New Keybind')

-- 	local function AddNewRow()
-- 		if not self.dropdowns.spells:GetValue() then
-- 			mint:Log("You must select a spell to add a new keybind.")
-- 			return
-- 		end

-- 		local spellInfo = C_Spell.GetSpellInfo(self.dropdowns.spells:GetValue())
-- 		local spell = {
-- 			icon = spellInfo.iconID or 134400,
-- 			name = spellInfo.name or "Unknown",
-- 			spellId = spellInfo.spellID or 0,
-- 			keybind = "None",
-- 			target = "Target",
-- 			enabled = false
-- 		}

-- 		tinsert(self.bind_data, spell)
-- 		self.tables.keybinds:SetData(self.bind_data)
-- 		mint.Keybinds:Update()
-- 	end

-- 	self.buttons.new_keybind:SetScript('OnClick', AddNewRow)

-- 	local keybinds_row_3 = self.tabs.keybinds:AddRow({ margin = { top = 5 } });
-- 	keybinds_row_3:AddElement(self.buttons.new_keybind, { column = 4 });
-- 	-- keybinds_row_3:AddElements(self.buttons.new_keybind, self.buttons.del_keybind, { column = 'even' });


-- 	--! Actually populate the tab !--
-- 	self.tabs.keybinds:DoLayout();

-- 	------------------------------
-- 	--- Whitelist Settings
-- 	------------------------------

-- 	-- local whitelists = {
-- 	-- 	{ name = "kicks", title = "Kicks" },
-- 	-- 	{ name = "dispels", title = "Dispels" },
-- 	-- 	{ name = "purges", title = "Purges" },
-- 	-- }

-- 	-- self.whitelistTabs = self.factory:TabPanel(self.tabs.lists, nil, nil, whitelists, false, 100, 20)
-- 	-- self.factory:GlueAcross(self.whitelistTabs, self.tabs.lists, 10, -20, -10, 10)

-- 	-- self.whitelistTabs:EnumerateTabs(function(tab)

-- 	-- 	local name = tab.name

-- 	-- 	self.factory:EasyLayout(tab, { padding = { top = 15 } });

-- 	-- 	self.tables[name] = self.factory:ScrollTable(tab.frame, Constants.WhitelistCols, 15, 20, self.config, name .. "_Whitelist")
-- 	-- 	self.tables[name]:EnableSelection(true)
-- 	-- 	self.tables[name]:SetData(self.bind_data)


-- 	-- 	local this_row_1 = tab.frame:AddRow({ margin = { top = 5 } });
-- 	-- 	keybinds_row_1:AddElement(self.tables[name], { column = 12 });

-- 	-- 	--! Dropdown for Spells !--
-- 	-- 	self.dropdowns.spells = self.factory:Dropdown(tab.frame, 150, 30, GetAllSpellData(), nil, false);
-- 	-- 	self.dropdowns.spells:SetPlaceholder('-- Select Spell --')
-- 	-- 	self.factory:AddLabel(tab.frame, self.dropdowns.spells, 'Add New Keybind', 'TOP')

-- 	-- 	--! Delete Keybind Button !--
-- 	-- 	self.buttons.del_keybind = self.factory:Button(tab.frame, 100, 20, 'Delete')

-- 	-- 	self.buttons.del_keybind:SetScript('OnClick', function()
-- 	-- 		local selected = self.tables[name]:GetSelection()
-- 	-- 		if not selected then
-- 	-- 			mint:Log("You must select a keybind to delete.")
-- 	-- 			return
-- 	-- 		end

-- 	-- 		table.remove(self.bind_data, selected)

-- 	-- 		self.tables[name]:SetData(self.bind_data)
-- 	-- 	end)

-- 	-- 	local this_row_2 = tab.frame:AddRow({ margin = { top = 18 } });
-- 	-- 	keybinds_row_2:AddElement(self.dropdowns.spells, { column = 5 });
-- 	-- 	keybinds_row_2:AddElement(self.factory:Frame(tab.frame, 0, 0), { column = 5 });
-- 	-- 	keybinds_row_2:AddElement(self.buttons.del_keybind, { column = 2 });

-- 	-- 	--! New Keybind Button !--
-- 	-- 	self.buttons.new_keybind = self.factory:Button(tab.frame, 80, 20, 'New Keybind')

-- 	-- 	local function AddNewRow()
-- 	-- 		if not self.dropdowns.spells:GetValue() then
-- 	-- 			mint:Log("You must select a spell to add a new keybind.")
-- 	-- 			return
-- 	-- 		end

-- 	-- 		local spellInfo = C_Spell.GetSpellInfo(self.dropdowns.spells:GetValue())
-- 	-- 		local spell = {
-- 	-- 			icon = spellInfo.iconID or 134400,
-- 	-- 			name = spellInfo.name or "Unknown",
-- 	-- 			spellId = spellInfo.spellID or 0,
-- 	-- 			keybind = "None",
-- 	-- 			target = "Target",
-- 	-- 			enabled = false
-- 	-- 		}

-- 	-- 		tinsert(self.bind_data, spell)
-- 	-- 		self.tables.keybinds:SetData(self.bind_data)
-- 	-- 		mint.Keybinds:Update()
-- 	-- 	end

-- 	-- 	self.buttons.new_keybind:SetScript('OnClick', AddNewRow)

-- 	-- 	local keybinds_row_3 = tab.frame:AddRow({ margin = { top = 5 } });
-- 	-- 	keybinds_row_3:AddElement(self.buttons.new_keybind, { column = 4 });
-- 	-- 	-- keybinds_row_3:AddElements(self.buttons.new_keybind, self.buttons.del_keybind, { column = 'even' });


-- 	-- 	--! Actually populate the tab !--
-- 	-- 	tab.frame:DoLayout();

-- 	-- end);

-- 	------------------------------
-- 	--- Dungeon Settings
-- 	------------------------------

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

-- 	self.dungeonTabs = self.factory:TabPanel(self.tabs.dungeons, nil, nil, dungeonTabData, false, 32, 32)
-- 	self.factory:GlueAcross(self.dungeonTabs, self.tabs.dungeons, 10, -20, -10, 10)

-- 	self.dungeonTabs:EnumerateTabs(function(tab)
-- 		-- local l = self.factory:Label(tab.frame, tab.title .. " " .. Constants.DungeonKeyToName[tab.name], nil, nil, nil, nil, 'label');
-- 		-- self.factory:GlueTop(l, tab.frame, 10, -10, 'LEFT');
--         -- self.factory:AddLabel(tab.frame, l, "This label is here for a sanity check.", 'BOTTOM')

-- 		local subTabs = {
-- 			{ name = "defensives", title = "Defensives" },
-- 			{ name = "stops", title = "Stops" },
-- 			{ name = "dispels", title = "Dispels" },
-- 			{ name = "reactions", title = "Reactions" },
-- 		}

-- 		tab.subTabs = self.factory:TabPanel(tab.frame, nil, nil, subTabs, false, 100, 20)

-- 		self.factory:GlueAcross(tab.subTabs, tab.frame, 15, -20, -10, 10)

-- 	end);

-- 	------------------------------
-- 	--- Profile Management
-- 	------------------------------

-- 	self.factory:EasyLayout(self.tabs.profiles, { padding = { top = 5 } });

-- 	local profile_list = {}

-- 	for k, v in pairs(ProfileManager:GetAllProfileNames()) do
-- 		table.insert(profiles, { text = v, value = v })
-- 	end

-- 	local active_name = ProfileManager:GetActiveProfileName()

-- 	self.dropdowns.profile_select = self.factory:Dropdown(self.tabs.profiles, 200, 30, profile_list, active_name, false);

-- 	self.dropdowns.profile_select:SetPlaceholder('-- Select Profile --')
-- 	self.labels.current_profile = self.factory:AddLabel(self.tabs.profiles, self.dropdowns.profile_select, 'Current: ' .. active_name, 'TOP')

-- 	-- self.dropdowns.profile_select.OnValueChanged = function(this, value)
-- 	-- 	ProfileManager:UpdateActiveProfile(value)
-- 	-- 	self:UpdateProfile()
-- 	-- end

-- 		--! Import Profile Button !--
-- 		self.buttons.import_profile = self.factory:Button(self.tabs.profiles, 100, 20, 'Import')

-- 		-- self.buttons.import_profile:SetScript('OnClick', function()
-- 		-- 	local selected = self.dropdowns.profile_select:GetValue()
	
-- 		-- 	if selected == ProfileManager:GetActiveProfileName() then
-- 		-- 		return
-- 		-- 	end
	
-- 		-- 	if not selected then
-- 		-- 		mint:Log("You must select a profile to activate.")
-- 		-- 		return
-- 		-- 	end
	
-- 		-- 	ProfileManager:UpdateActiveProfile(selected)
-- 		-- 	self:UpdateProfile()
-- 		-- end)
	
-- 		--! Export Profile Button !--
-- 		self.buttons.export_profile = self.factory:Button(self.tabs.profiles, 100, 20, 'Export')
	
-- 		-- self.buttons.export_profile:SetScript('OnClick', function()
-- 		-- 	local selected = self.dropdowns.profile_select:GetValue()
	
-- 		-- 	if selected == ProfileManager:GetActiveProfileName() then
-- 		-- 		mint:Log("You cannot delete the active profile.")
-- 		-- 		return
-- 		-- 	end
	
-- 		-- 	if not selected then
-- 		-- 		mint:Log("You must select a profile to delete.")
-- 		-- 		return
-- 		-- 	end
	
-- 		-- 	ProfileManager:DeleteProfileByName(selected)
-- 		-- end)


-- 	local profiles_row_1 = self.tabs.profiles:AddRow({ margin = { top = 20 } });
-- 	profiles_row_1:AddElement(self.dropdowns.profile_select, { column = 5 });
-- 	profiles_row_1:AddElement(self.factory:Frame(self.tabs.keybinds, 0, 0), { column = 3 });
-- 	profiles_row_1:AddElement(self.buttons.import_profile, { column = 2 });
-- 	profiles_row_1:AddElement(self.buttons.export_profile, { column = 2 });

-- 	--! Select Profile Button !--
-- 	self.buttons.select_profile = self.factory:Button(self.tabs.profiles, 100, 20, 'Load Selected')

-- 	self.buttons.select_profile:SetScript('OnClick', function()
-- 		local selected = self.dropdowns.profile_select:GetValue()

-- 		if selected == ProfileManager:GetActiveProfileName() then
-- 			return
-- 		end

-- 		if not selected then
-- 			mint:Log("You must select a profile to activate.")
-- 			return
-- 		end

-- 		ProfileManager:UpdateActiveProfile(selected)
-- 		self:UpdateProfile()
-- 	end)

-- 	--! Delete Profile Button !--
-- 	self.buttons.del_profile = self.factory:Button(self.tabs.profiles, 100, 20, 'Delete')

-- 	self.buttons.del_profile:SetScript('OnClick', function()
-- 		local selected = self.dropdowns.profile_select:GetValue()

-- 		if selected == ProfileManager:GetActiveProfileName() then
-- 			mint:Log("You cannot delete the active profile.")
-- 			return
-- 		end

-- 		if not selected then
-- 			mint:Log("You must select a profile to delete.")
-- 			return
-- 		end

-- 		ProfileManager:DeleteProfileByName(selected)
-- 	end)

-- 	local profiles_row_2 = self.tabs.profiles:AddRow({ margin = { top = 5 } });
-- 	profiles_row_2:AddElement(self.buttons.select_profile, { column = 4 });
-- 	profiles_row_2:AddElement(self.buttons.del_profile, { column = 2 });


-- 	--! Create Profile Name !--
-- 	local new_profile_name = self.factory:SimpleEditBox(self.tabs.profiles, 150, 24, 'Create New Profile');
-- 	self.factory:GlueTop(new_profile_name, self.tabs.profiles, 10, -40, 'LEFT');

-- 	--! Create Profile Button !--
-- 	self.buttons.new_profile = self.factory:Button(self.tabs.profiles, 100, 20, 'Create')

-- 	self.buttons.new_profile:SetScript('OnClick', function()
-- 		local name = new_profile_name:GetText()

-- 		if not name or name == '' or name == 'Create New Profile' then
-- 			mint:Log("You must enter a name for the new profile.")
-- 			return
-- 		end

-- 		ProfileManager:CreateNewProfile(name)
-- 		self:UpdateProfile()
-- 	end)

-- 	local profiles_row_3 = self.tabs.profiles:AddRow({ margin = { top = 25 } });
-- 	profiles_row_3:AddElement(new_profile_name, { column = 5 });

-- 	local profiles_row_4 = self.tabs.profiles:AddRow({ margin = { top = 5 } });
-- 	profiles_row_4:AddElement(self.buttons.new_profile, { column = 2 });

-- 	--! Duplicate Profile Name !--
-- 	local copy_profile_name = self.factory:SimpleEditBox(self.tabs.profiles, 150, 24, 'Copy Active Profile');
-- 	self.factory:GlueTop(copy_profile_name, self.tabs.profiles, 10, -40, 'LEFT');

-- 	--! Duplicate Profile Button !--
-- 	self.buttons.dupe_profile = self.factory:Button(self.tabs.profiles, 100, 20, 'Duplicate')

-- 	self.buttons.dupe_profile:SetScript('OnClick', function()
-- 		local name = copy_profile_name:GetText()

-- 		if not name or name == '' or name == 'Copy Active Profile' then
-- 			mint:Log("You must enter a name for the new profile.")
-- 			return
-- 		end

-- 		ProfileManager:DuplicateProfile(name, ProfileManager:GetActiveProfileName())
-- 		self:UpdateProfile()
-- 	end)

-- 	local profiles_row_5 = self.tabs.profiles:AddRow({ margin = { top = 25 } });
-- 	profiles_row_5:AddElement(copy_profile_name, { column = 5 });


-- 	local profiles_row_6 = self.tabs.profiles:AddRow({ margin = { top = 5 } });
-- 	profiles_row_6:AddElement(self.buttons.dupe_profile, { column = 2 });

-- 	--! Actually populate the tab !--
-- 	self.tabs.profiles:DoLayout();
-- end

-- function Interface:UpdateProfile()
-- 	self.config = ProfileManager:GetActiveConfig()
-- 	self.keybind_config = ProfileManager:GetActiveKeybinds()

-- 	-- Reset current profile label
-- 	self.labels.current_profile:Hide()
-- 	self.labels.current_profile = self.factory:AddLabel(self.tabs.profiles, self.dropdowns.profile_select, 'Current: ' .. ProfileManager:GetActiveProfileName(), 'TOP')
-- end

-- return Interface
