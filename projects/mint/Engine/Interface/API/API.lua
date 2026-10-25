local unlocker,
---@class mint
mint = ...

----------------------------
--- Locals
----------------------------

local Constants 			= mint.Constants
local Settings 		= mint.Settings
local tinsert, tremove 		= table.insert, table.remove

---@class Interface
---@field config table
---@field ui_config table
---@field keybind_config table
---@field mint_tiny Font
---@field mint_normal Font
---@field mint_large Font
---@field bind_data table
---@field factory StdUi
---@field keybinds Keybinds
---@field builder table
---@field pages table
---@field toggles table
---@field dropdowns table
---@field sliders table
---@field quickbuttons table
---@field labels table
---@field tables table
---@field buttons table
---@field refresh_funcs table
local Interface = {}
Interface.__index = Interface

-- Constructor
---@return Interface
function Interface:New()
	local self = setmetatable({}, Interface)
	local _, _, ClassID = UnitClass("player")

	-- self.config = ProfileManager:GetActiveConfig()
	-- self.keybind_config = ProfileManager:GetActiveKeybinds()
	-- self.ui_config = mint.Config:New("Mint UI")

	self.ui_config = Settings.global.ui

	self.refresh_funcs = {}


	self.mint_tiny = CreateFont("MintFontSmall")
	self.mint_normal = CreateFont("MintFontNormal")
	self.mint_large = CreateFont("MintFontLarge")

	self.mint_tiny:SetFont("Fonts\\frizqt__.ttf", 8, "OUTLINE")
	self.mint_normal:SetFont("Fonts\\frizqt__.ttf", 10, "OUTLINE")
	self.mint_large:SetFont("Fonts\\frizqt__.ttf", 12, "OUTLINE")

	-- Data for keybinds
	-- self.bind_data = self.keybind_config:Read(ClassID .. "_KeyBinds", {})

	-- StdUI instance and stylesheet
	self.factory = mint.StdUi:NewInstance()
	self.factory.config = Constants.Stylesheet

	-- Place to store elements to build on init
	self.builder = {
		pages = {},
		quickbuttons = {},
	}

	-- Active elements
	self.pages = {}
	self.toggles = {}
	self.dropdowns = {}
	self.sliders = {}
	self.quickbuttons = {}
	self.labels = {}
	self.tables = {}
	self.buttons = {}

	self:AddQuickButton("Inv_misc_herb_jadetealeaf", "MintToggle", "Toggle", function()
		mint.events:TriggerEvent("toggle")
	end)

	self:AddQuickButton(Constants.QuickbarIconsByClass[ClassID][1], "MintCooldowns", "CDs", function()
		mint.events:TriggerEvent("cooldowns")
	end)

	self:AddQuickButton(Constants.QuickbarIconsByClass[ClassID][2], "MintKicks", "Kicks", function()
		mint.events:TriggerEvent("kicks")
	end)

	self:AddQuickButton(Constants.QuickbarIconsByClass[ClassID][3], "MintDefensives", "Defs", function()
		mint.events:TriggerEvent("defensives")
	end)

	if Constants.QuickbarIconsByClass[ClassID][4] then
		self:AddQuickButton(Constants.QuickbarIconsByClass[ClassID][4], "MintDispels", "Dispels", function()
			mint.events:TriggerEvent("dispels")
		end)
	end

	if Constants.QuickbarIconsByClass[ClassID][5] then
		self:AddQuickButton(Constants.QuickbarIconsByClass[ClassID][5], "MintPurges", "Purge", function()
			mint.events:TriggerEvent("purges")
		end)
	end

	return self
end

function Interface:AddQuickButton(icon, name, label, cb)
	table.insert(self.builder.quickbuttons, { icon = icon, name = name, label = label, cb = cb })
end


function Interface:InitPage(callback)
	callback(self)
end

-- Create the Quickbar Frame
function Interface:BuildQuickbar()
	local buttoncount = #self.builder.quickbuttons

	self.quickbar = self.factory:Panel(UIParent, 50 * buttoncount, 60)
	self.quickbar:SetMovable(true)
	self.quickbar:EnableMouse(true)
	self.quickbar:RegisterForDrag("LeftButton")
	self.quickbar:SetScript("OnDragStart", function(this, button)
		this:StartMoving()
	end)
	self.quickbar:SetScript("OnDragStop", function(this)
		this:StopMovingOrSizing()
		local point, _, relativePoint, offsetX, offsetY = this:GetPoint()

		local position = {
			point = point,
			relativePoint = relativePoint,
			offsetX = offsetX,
			offsetY = offsetY
		}

		self.ui_config.quickbar_anchor = position
		Settings:SaveGlobal()
	end)

	local position = self.ui_config.quickbar_anchor

	if position then
		self.quickbar:ClearAllPoints()
		self.quickbar:SetPoint(position.point, UIParent, position.relativePoint, position.offsetX, position.offsetY)
	else
		self.quickbar:SetPoint("CENTER", 0, 0)
	end

	for i, button in ipairs(self.builder.quickbuttons) do
		self.quickbuttons[button.name] = mint.QuickButton:New(self.quickbar, 50, 50, "Interface\\Icons\\" .. button.icon,
			button.name, button.cb)

		self.factory:GlueLeft(self.quickbuttons[button.name].button, self.quickbar, 50 * (i - 1), 5, true)

		local toggle_string = self.factory:FontString(self.quickbar, button.label);
		self.factory:GlueBottom(toggle_string, self.quickbuttons[button.name].button, 0, -10);

		-- Restore saved toggle state
		local saved_states = self.ui_config.button_states
		if saved_states and saved_states[button.name] then
			self.quickbuttons[button.name].state.active = true
			self.quickbuttons[button.name].icon:SetVertexColor(1.0, 1.0, 1.0, 1.0)
			-- Fire the callback to apply the toggle (e.g., enable CDs)
			button.cb()
		end
	end

	-- Hook toggle persistence: save state on every click
	for name, qb in pairs(self.quickbuttons) do
		local original_toggle = qb.ToggleState
		qb.ToggleState = function(btn)
			original_toggle(btn)
			-- Save all button states
			if not self.ui_config.button_states then
				self.ui_config.button_states = {}
			end
			self.ui_config.button_states[name] = btn.state.active or false
			Settings:SaveGlobal()
		end
	end
end

function Interface:BuildOptions()
	--! Main Window !--
	self.window = self.factory:Window(UIParent, 700, 500, "|TInterface\\Icons\\Inv_misc_herb_jadetealeaf:16|t |cFFFFFFFFMint|r")
	self.window:SetPoint("CENTER")

	self.window:Hide()

	--! Creating the pages !--
	self.menu_panel = self.factory:TabPanel(self.window, nil, nil, self.builder.pages, true, nil, 25)
	self.factory:GlueAcross(self.menu_panel, self.window, 10, -40, -10, 10)

	self.scroll_frames = self.factory:ScrollFrame(self.window, self.menu_panel.container:GetWidth(), self.menu_panel.container:GetHeight(), self.menu_panel.container)
	self.factory:GlueTop(self.scroll_frames, self.window, -10, -35, 'RIGHT')

	-- Add the new pages to the pages table
	for _, page in ipairs(self.builder.pages) do
		mint.console.log("Building " .. page.key)
		local this = self.menu_panel:GetTabByName(page.key)

		-- We really want the frame, but maybe better to have it all here?
		self.pages[page.key] = this.frame

		if page.callback then
			local success, result = pcall(page.callback, self)
			
			if not success then
				mint.console.log("Error building page " .. page.key .. ": " .. result)
			end
		end
	end

	-- self.window:Show()
end

function Interface:TriggerRefresh()
	-- self.config = ProfileManager:GetActiveConfig()
	-- self.keybind_config = ProfileManager:GetActiveKeybinds()

	-- Reset current profile label
	-- self.labels.current_profile:Hide()
	-- self.labels.current_profile = self.factory:AddLabel(self.pages.profiles, self.dropdowns.profile_select, 'Current: ' .. ProfileManager:GetActiveProfileName(), 'TOP')

	-- for k, v in pairs(self.toggles) do
	-- 	v:SetChecked(self.config:Read(k, false))
	-- 	v.OnValueChanged = function(this, value)
	-- 		self.config:Write(k, value)
	-- 	end
	-- end

	-- for _, v in ipairs(self.refresh_funcs) do
	-- 	if type(v) == "function" then
	-- 		v(self)
	-- 	end
	-- end
end

function Interface:RegisterRefreshCallback(cb)
	if type(cb) ~= "function" then
		error("Refresh callback must be a function")
	end

	tinsert(self.refresh_funcs, cb)
end

return Interface