local unlocker,
---@class mint
mint = ...

-- Create a sequencer class that takes a table of actions and executes them in order

---@class Sequence
---@field name string
---@field running boolean
---@field cast_history table
---@field events EventManager
---@field resetCondition fun(arg): boolean
---@field abortCondition fun(arg): boolean
---@field index number
---@field actions table
local Sequence = {}
Sequence.__index = Sequence

-- Constructor
---@param actions table
---@return Sequence
function Sequence:New(name, actions, resetCondition, abortCondition)
    local self = setmetatable({}, Sequence)

	self.name = name
    self.actions = actions
    self.index = 1
	self.running = false

	self.cast_history = {}

	self.events = mint.EventManager:New()

	self.events:RegisterWoWEvent("UNIT_SPELLCAST_SUCCEEDED", function(...)
		local args = { ... }

		-- DevTools_Dump(args)

		local source_guid = args[1]
		local spell_id = args[3]

		if source_guid == "player" then
			self.cast_history[spell_id] = GetTime()
		end
	end)

    self.resetCondition = resetCondition
	self.abortCondition = abortCondition

    return self
end

-- Should we reset the sequencer
---@return boolean
function Sequence:ShouldReset()
    if self.resetCondition then
        return self.resetCondition(self)
    end

    return false
end

-- Should we abort the sequencer
---@return boolean
function Sequence:ShouldAbort()
    if self.abortCondition then
        return self.abortCondition(self)
    end

    return false
end

-- Execute the current action in the sequence and move on to next
---@return boolean
function Sequence:Execute()
	if self:IsFinished() then
		mint:Log(self, "has finished.")
		self:Reset()
		self.running = false
		return false
	end

	if self:ShouldAbort() then
		self:Abort()
		return false
	end

	self.running = true

	local name = self.actions[self.index].name
	local func = self.actions[self.index].func

	-- If the function returns true, we can move on to the next action
	if func(self) then
		mint.console.log("Action: " .. name .. " executed successfully")
		self.index = self.index + 1
		return true
	else
		mint.console.log("Action: " .. name .. " failed execution, repeating.")
		return false
	end
end

-- Check if the sequence is finished
---@return boolean
function Sequence:IsFinished()
    return self.index > #self.actions
end

-- Check if the sequence is running
---@return boolean
function Sequence:IsRunning()
    return self.running
end

-- Reset the sequencer
---@return nil
function Sequence:Reset(aborted)
    self.index = 1
	mint:Log(self, "has been reset" .. (aborted and " via Abort()." or "."))
	self.running = false
end

-- Abort the sequence
---@return nil
function Sequence:Abort()
    self.index = #self.actions + 1
	self:Reset(true)
	self.running = false
end

-- tostring
---@return string
function Sequence:__tostring()
    return "[Sequence] " .. self.name .. ""
end

return Sequence
