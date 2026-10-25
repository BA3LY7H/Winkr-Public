local unlocker,
---@class mint
mint = ...

local QuickButton = {}
QuickButton.__index = QuickButton

function QuickButton:New(parent, width, height, icon, name, cb)
	local self = setmetatable({}, QuickButton)

	self.state = {}
	self.callback = cb

	self.button = CreateFrame("Frame", nil, parent)
	self.button:SetSize(width, height)
	self.button:EnableMouse(true)
	self.button:SetFrameStrata("MEDIUM")

	self.bg = self.button:CreateTexture(nil, "BACKGROUND", nil, 1)
	self.bg:SetParent(self.button)
	self.bg:SetPoint("TOPLEFT", 0, 0)
	self.bg:SetPoint("BOTTOMRIGHT", 0, 0)

	self.icon_texture = icon

	self.icon = self.button:CreateTexture(nil, "BACKGROUND", nil, 2)
	self.icon:SetParent(self.button)
	self.icon:SetAllPoints()

	self.icon:SetTexture(self.icon_texture)
	self.icon:SetVertexColor(0.330, 0.343, 0.352, 1.0)

	self.button:SetScript("OnMouseDown", function(this)
		self:ToggleState()
		self.callback()
	end)

	return self
end

function QuickButton:ToggleState()
	if self.state.active then
		self.state.active = false
		self.icon:SetTexture(self.icon_texture)
		self.icon:SetVertexColor(0.330, 0.343, 0.352, 1.0)
	else
		self.state.active = true
		self.icon:SetTexture(self.icon_texture)
		self.icon:SetVertexColor(1.0, 1.0, 1.0, 1.0)
	end
end

mint.QuickButton = QuickButton