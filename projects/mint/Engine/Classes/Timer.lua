local unlocker, mint = ...

-- Create a new Timer class
---@class Timer
local Timer = {
    startTime = nil,
	endTime = nil,
	remaining = nil,
	duration = nil,
    resetAfterCombat = false,
}
Timer.__index = Timer

-- Constructor
---@param type string
---@return Timer
function Timer:New(duration)
    local self = setmetatable({}, Timer)
    self.startTime = nil
	self.duration = duration or 0
	self.endTime = 0

    return self
end

function Timer:GetRemainingTime()
	return self.endTime - GetTime()
end

function Timer:GetTimeSinceEnded()
	return GetTime() - self.endTime
end

-- Start the timer
---@return nil
function Timer:Start()
    self.startTime = GetTime()
end

-- Get the time since the timer was started
---@return number
function Timer:GetTime()
    if not self:IsRunning() then
        return 0
    end
    return GetTime() - self.startTime
end

-- Check if the timer is running
---@return boolean
function Timer:IsRunning()
    return self.startTime ~= nil
end

-- Reset the timer
---@return nil
function Timer:Reset()
    self.startTime = nil
end

return Timer
