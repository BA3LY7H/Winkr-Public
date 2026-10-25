local unlocker,
---@class mint
mint = ...

----------------------------
--- Locals
----------------------------

local Constants = mint.Constants
local Interface = mint.Interface
local tinsert, tremove = table.insert, table.remove

---@class Element
---@field type string
---@field config table
---@field parent Page
---@field key string
local Element = {}
Element.__index = Element

-- Constructor
---@param parent Page
---@param config table
---@return Element
function Element:New(parent, config)
	local self = setmetatable({}, Element)

	self.type = config.type
	self.config = config
	self.parent = parent
	self.key = parent.key .. "_" .. self.config.name

	return self
end

-- Determines if the element is checked
---@return boolean
function Element:IsChecked()
	if not Interface.toggles[self.key] then
		return false
	end

	return Interface.toggles[self.key]:GetChecked()
end

-- Returns the value of the slider
---@return number
function Element:GetValue()
	if not Interface.sliders[self.key] then
		return self.config.default
	end

	return Interface.sliders[self.key]:GetValue()
end

-- Returns if a value is selected on a dropdown
function Element:IsSelected(value)
	if not Interface.dropdowns[self.key] then
		return false
	end

	return Interface.dropdowns[self.key]:IsSelected(value)
end

-- Returns the value selected on a dropdown
function Element:GetSelected()
	if not Interface.dropdowns[self.key] then
		return false
	end

	return Interface.dropdowns[self.key]:GetValue()
end

return Element