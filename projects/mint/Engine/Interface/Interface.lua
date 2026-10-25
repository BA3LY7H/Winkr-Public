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

-- 	if Constants.QuickbarIconsByClass[ClassID][4] then
-- 		self:AddQuickButton(Constants.QuickbarIconsByClass[ClassID][4], "MintDispels", "Dispels", function()
-- 			mint.events:TriggerEvent("dispels")
-- 		end)
-- 	end

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
-- 		{ name = "dev_settings",   title = "Developer" },
-- 	}

-- 	--! Creating the tabs !--
-- 	self.menu_panel = self.factory:TabPanel(self.window, nil, nil, tabs, true, nil, 25)
-- 	self.factory:GlueAcross(self.menu_panel, self.window, 10, -40, -10, 10)

-- 	local general      = self.menu_panel:GetTabByName("general_settings");
-- 	local keybinds     = self.menu_panel:GetTabByName("keybind_settings");
-- 	local lists        = self.menu_panel:GetTabByName("lists_settings");
-- 	local dungeons     = self.menu_panel:GetTabByName("dungeons_settings");
-- 	local profiles     = self.menu_panel:GetTabByName("profile_settings");
-- 	local developer     = self.menu_panel:GetTabByName("dev_settings");

-- 	self.tabs.general  = general.frame
-- 	self.tabs.keybinds = keybinds.frame
-- 	self.tabs.lists    = lists.frame
-- 	self.tabs.dungeons = dungeons.frame
-- 	self.tabs.profiles = profiles.frame
-- 	self.tabs.developer = developer.frame
-- end

-- function Interface:RefreshConfigs()
-- 	self.config = ProfileManager:GetActiveConfig()
-- 	self.keybind_config = ProfileManager:GetActiveKeybinds()

-- 	-- Reset current profile label
-- 	self.labels.current_profile:Hide()
-- 	self.labels.current_profile = self.factory:AddLabel(self.tabs.profiles, self.dropdowns.profile_select, 'Current: ' .. ProfileManager:GetActiveProfileName(), 'TOP')

-- 	for k, v in pairs(self.toggles) do
-- 		v:SetChecked(self.config:Read(k, false))
-- 		v.OnValueChanged = function(this, value)
-- 			self.config:Write(k, value)
-- 		end
-- 	end
-- end

-- return Interface
