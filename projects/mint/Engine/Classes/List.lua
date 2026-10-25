---@class List
local List = {
    -- Add overload
    ---@param self List
    ---@param value any
    ---@return List
    __add = function(self, value)
        self:push(value)
        return self
    end,

    -- Subtract overload
    ---@param self List
    ---@param value any
    ---@return List
    __sub = function(self, value)
        self:remove(value)
        return self
    end,
}
List.__index = List

---@param from table | nil
---@return List
function List:New(from)
    local self = setmetatable({}, List)
    self._items = from or {}
    return self
end

---@param value any
---@return nil
function List:push(value)
    table.insert(self._items, value)
end

---@return any
function List:pop()
    return table.remove(self._items)
end

---@return any
function List:peek()
    return self._items[#self._items]
end

---@return number
function List:count()
    return #self._items
end

---@return nil
function List:clear()
    self._items = {}
end

---@param value any
---@return boolean
function List:contains(value)
    for _, v in ipairs(self._items) do
        if v == value then
            return true
        end
    end
    return false
end

---@param value any
---@return boolean
function List:remove(value)
    for i, v in ipairs(self._items) do
        if v == value then
            table.remove(self._items, i)
            return true
        end
    end
    return false
end

---@param callback fun(value: any): boolean
---@return nil
function List:each(callback)
    for _, v in ipairs(self._items) do
        if callback(v) then
            break
        end
    end
end

---@param callback fun(value: any): boolean?
---@return nil
function List:loop(callback)
    for _, v in ipairs(self._items) do
        if callback(v) then
            break
        end
    end
end

---@param callback fun(value: any): boolean
---@return List
function List:map(callback)
    local newList = List:New()
    for _, v in ipairs(self._items) do
        newList:push(callback(v))
    end
    return newList
end

---@param callback fun(value: any): boolean
---@return List
function List:filter(callback)
    local newList = List:New()
    for _, v in ipairs(self._items) do
        if callback(v) then
            newList:push(v)
        end
    end
    return newList
end

---@param callback fun(result: any, value: any): any, boolean
---@param initialValue any
---@return any
function List:reduce(callback, initialValue)
    local result = initialValue
    local done = false
    for _, v in ipairs(self._items) do
        result, done = callback(result, v)
        if done then
            break
        end
    end
    return result
end

---@param callback fun(value: any): boolean
---@return any | nil
function List:find(callback)
    for _, v in ipairs(self._items) do
        if callback(v) then
            return v
        end
    end
    return nil
end

---@param callback fun(value: any): boolean
---@return number | nil
function List:findIndex(callback)
    for i, v in ipairs(self._items) do
        if callback(v) then
            return i
        end
    end
    return nil
end

---@param callback fun(...): boolean
---@return nil
function List:sort(callback)
    table.sort(self._items, callback)
end

---@return List
function List:reverse()
    local newList = List:New()
    for i = #self._items, 1, -1 do
        newList:push(self._items[i])
    end
    return newList
end

---@return List
function List:clone()
    local newList = List:New()
    for _, v in ipairs(self._items) do
        newList:push(v)
    end
    return newList
end

---@param list List
---@return List
function List:concat(list)
    local newList = List:New()
    for _, v in ipairs(self._items) do
        newList:push(v)
    end
    for _, v in ipairs(list._items) do
        newList:push(v)
    end
    return newList
end

---@param separator string
---@return string
function List:join(separator)
    local result = ""
    for i, v in ipairs(self._items) do
        result = result .. v
        if i < #self._items then
            result = result .. separator
        end
    end
    return result
end

---@return string
function List:toString()
    return self:join(", ")
end

---@return string
function List:__tostring()
    return self:toString()
end

return List