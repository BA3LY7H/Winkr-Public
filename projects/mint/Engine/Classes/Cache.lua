---@class Cache
local Cache = {}
Cache.__index = Cache

-- Constructor
---@return Cache
function Cache.New()
    local instance = setmetatable({}, Cache)
    instance.cache = {}
    return instance
end

---@param key any
---@param value any
---@param duration number
---@return nil
function Cache:Set(key, value, duration)
    self.cache = self.cache or {}
    self.cache[key] = {
        value = value,
        duration = duration,
        time = GetTime()
    }
end

---@param key any
---@return any
function Cache:Get(key)
    self.cache = self.cache or {}
    local cache = self.cache[key]
    if cache and cache.time + cache.duration > GetTime() then
        return cache.value
    end

    -- It's old or doesn't exist, so remove it
    self.cache[key] = nil

    return nil
end

---@param key any
---@return boolean
function Cache:IsCached(key)
    self.cache = self.cache or {}
    local cache = self.cache[key]
    if cache and cache.time + cache.duration > GetTime() then
        return true
    end

    -- It's old or doesn't exist, so remove it
    self.cache[key] = nil

    return false
end

return Cache
