local unlocker,
---@class mint
mint = ...

----------------------------
--- Locals
----------------------------

local Constants = mint.Constants
local Interface = mint.Interface
local Element 	= Interface.Element
local tinsert, tremove = table.insert, table.remove

---@class Row
---@field elements table
---@field margins table
---@field parent Page
local Row = {}
Row.__index = Row

-- Constructor
---@param parent Page
---@param margins table
---@return Row
function Row:New(parent, margins)
	local self = setmetatable({}, Row)

	self.elements = {}
	self.margins = margins
	self.parent = parent

	return self
end

---Add a checkbox
---@param config table
---@return Element
function Row:AddToggle(config)
	local settings = {
		type = "toggle",
		name = config.name,
		default = config.default or false,
		cols = config.cols or nil,
	}

	local element = Element:New(self.parent, settings)
	tinsert(self.elements, element)

	return element
end

---Add a dropdown menu
---@param config table
---@return Element
function Row:AddDropDown(config)
	if not config.options then
		error("Dropdown " .. config.name .. " is missing an options table.")
	end

	local settings = {
		type = "dropdown",
		name = config.name,
		width = config.width or 200,
		multi = config.multi or false,
		options = config.options or {},
		cols = config.cols or nil,
		placeholder = config.placeholder or " -- Select -- "
	}

	local element = Element:New(self.parent, settings)

	tinsert(self.elements, element)

	return element
end

---Add a slider
---@param config table
---@return Element
function Row:AddSlider(config)
	local settings = {
		type = "slider",
		name = config.name,
		width = config.width or 200,
		default = config.default or 0,
		min = config.min or 0,
		max = config.max or 100,
		cols = config.cols or nil,
	}

	local element = Element:New(self.parent, settings)
	tinsert(self.elements, element)

	return element
end

return Row