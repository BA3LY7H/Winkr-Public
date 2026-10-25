-- Create an EventManager class
---@class EventManager
---@field frame Frame?
local EventManager = {
    events = {},
    eventHandlers = {},
    wowEventHandlers = {},
    frame = nil
}

EventManager.__index = EventManager

-- Constructor
---@return EventManager
function EventManager.New()
    local instance = setmetatable({}, EventManager)
    instance.events = {}
    instance.eventHandlers = {}
    instance.wowEventHandlers = {}

    -- Frame for wow events
    instance.frame = CreateFrame("Frame")

    instance.frame:SetScript('OnEvent', function(f, event, ...)
        if instance.wowEventHandlers[event] then
            for _, callback in ipairs(instance.wowEventHandlers[event]) do
                callback(...)
            end
        end
    end)

    return instance
end

-- Register an event
---@param event string
---@param handler fun(...)
---@return nil
function EventManager:RegisterEvent(event, handler)
    if not self.events[event] then
        self.events[event] = {}
    end

    table.insert(self.events[event], handler)
end

-- Register a wow event
---@param event string
---@param handler fun(...)
---@return nil
function EventManager:RegisterWoWEvent(event, handler)
    if not self.wowEventHandlers[event] then
        self.wowEventHandlers[event] = {}
        self.frame:RegisterEvent(event)
    end

    table.insert(self.wowEventHandlers[event], handler)
end

-- Trigger an event
---@param event string
---@param ... any
---@return nil
function EventManager:TriggerEvent(event, ...)
    if self.events[event] then
        for _, handler in pairs(self.events[event]) do
            handler(...)
        end
    end
end

return EventManager
