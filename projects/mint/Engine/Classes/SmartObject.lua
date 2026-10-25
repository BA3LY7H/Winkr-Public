local unlocker,
---@class mint
mint = ...

-- This is a Bastion Cacheable/Refreshable combined
---@class SmartObject
---@field cache Cache?
---@field callback function?
---@field value any?
---@field useCache boolean?
---@field cacheTime number?
local SmartObject = {
    cache = nil,
    callback = nil,
    value = nil,
    useCache = false
}

-- Functional index
function SmartObject:__index(k)
    if SmartObject[k] then
        return SmartObject[k]
    end

    -- print("SmartObject:__index accessing key:", k)

    if self.useCache then
        if self.cache == nil then
            error("SmartObject: " .. k .. " Cache is nil")
        end

        if not self.cache:IsCached('self') then
            self.value = self.callback()
            self.cache:Set('self', self.value, self.cacheTime)
        end
    else
        self.value = self.callback()
        -- print("SmartObject:__index k: " .. k .. " updating value:", self.value)
    end

    if self.value == nil then
        error("SmartObject: " .. k .. " Value is nil")
    end

    -- print("SmartObject:__index k: " .. k .. " returning value:", self.value[k])
    return self.value[k]
end

-- ToString
---@return string
function SmartObject:__tostring()
    return tostring("SmartObject(" .. tostring(rawget(self, 'value')) .. ")")
end

-- Constructor
---@param value any
---@param callback function
---@param cacheTime number?
---@return Unit
function SmartObject:New(value, callback, cacheTime)
    local self = setmetatable({}, SmartObject)

    self.cache = mint.Cache.New()
    self.value = value
    self.callback = callback
    self.useCache = false

    if cacheTime then
        self.cacheTime = cacheTime
        self.useCache = true
        self.cache:Set('self', self.value, cacheTime)
    end

    return self
end

-- Update the value
---@return nil
function SmartObject:Update()
    self.value = self.callback()
end

-- Get the value of the smart object with optional parameters passed to the callback
---@return any
function SmartObject:Get(...)
    return self.callback(...)
end

return SmartObject