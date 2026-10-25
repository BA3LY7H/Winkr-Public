local unlocker,
---@class mint
mint = ...

----------------------------
--- Locals
----------------------------

local Constants = mint.Constants
local Interface = mint.Interface
local Settings 	= mint.Settings
local Row 		= Interface.Row
local tinsert, tremove = table.insert, table.remove

---@class Page
---@field name string
---@field key string
---@field rows table
---@field is_from_api boolean
---@field callback function?
---@field title string
---@field frame Frame?
local Page = {}
Page.__index = Page

-- Constructor
---@param name string
---@param class string
---@param spec string
---@param is_custom_page boolean?
---@param cb function?
---@return Page
function Page:New(name, class, spec, is_custom_page, cb)
	local self = setmetatable({}, Page)

	local key = class .. "." .. string.lower(spec)
	self.title = name
	self.name = key
	
	self.key 	= key

	-- This is where we store rows to be built
	self.rows 	= {}

	if is_custom_page then
		self.is_from_api = false
		self.callback = cb
	else
		self.is_from_api = true
	end

	-- Put the page in the to-be-built table
	tinsert(Interface.builder.pages, self)
	return self
end

function Page:NewCustom(name, key, cb)
	local self = setmetatable({}, Page)

	self.title 	= name
	self.name 	= key
	self.key 	= key

	-- This is where we store rows to be built
	self.rows 	= {}

	if cb and type(cb) == "function" then
		self.callback = cb
	end

	-- Put the page in the to-be-built table
	tinsert(Interface.builder.pages, self)
	return self
end

function Page:AddLayout(layout)
	self.layout = layout
end

function Page:AddDefaults(defaults)
	-- This should verify the defaults for profile.db.key (which can be hunter.beastmastery or just utility)
	Settings:VerifyDefaults(self.key, defaults)
end

-- Add a row to be built
---@param mt number?
---@param mr number?
---@param mb number?
---@param ml number?
---@return Row
function Page:AddRow(mt, mr, mb, ml)
	mt = mt or 0
	mr = mr or 0
	mb = mb or 5
	ml = ml or 0

	local margins = {
		top    = mt,
		right  = mr,
		bottom = mb,
		left   = ml
	}

	local this = Row:New(self, margins)
	tinsert(self.rows, this)

	return this
end

return Page