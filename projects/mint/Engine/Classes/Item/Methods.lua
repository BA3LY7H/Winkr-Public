local unlocker,
---@class mint
mint = ...

---@class Item
local Item = mint.Item

--- Adding callbacks to an item
---@param key string|function
---@param callback function?
function Item:AddCallback(key, callback)
    if type(key) == "function" then
        if self.keyless then
            error("Keyless callback set twice for " .. self.name)
        else
            self.keyless = key
        end
    elseif key then
        self.callbacks[key] = callback
    end
end

-- Invoking an item with callback
---@param key string?
---@vararg any
function Item:Invoke(key, ...)
    local callback
    if not key and self.keyless then
        callback = self.keyless
    else
        callback = self.callbacks[key]
    end

    if callback then
        -- Invoke the callback function with the spell object as the first argument
        if callback(self, ...) then
            -- mint:Log("Invoking " .. self.name .. "'s " .. (key or "keyless") .. " callback")
        end
    else
        if type(key) == "function" then
            error("Keyless callback not found for " .. self.name)
        else
            error("Callback '" .. (key or "none") .. "' not found for " .. self.name)
        end
    end
end

-- Use the item on given unit
---@param unit Unit
---@return boolean
function Item:Use(unit, useItemName)
    if not self:Usable() then
        -- mint:CombatLog(self.name, "is not usable")
        return false
    end

    local name = C_Item.GetItemNameByID(self.id)
    if not name then return false end

    -- Use the Item
    C_Item.UseItemByName(name, unit:GetPointer())
    
    -- Set the last Use time
    self.lastUseAttempt = GetTime()
    
    -- mint:CombatLog("We have used", self.name, "on", unit.name)

    return true
end

function Item:GetCooldown()
	local start, duration = C_Item.GetItemCooldown(self.id)
	return duration
end

function Item:HasCooldown()
	return self:GetCooldown() > mint.max_gcd + 0.1
end

function Item:IsOnCooldown()
    return select(2, C_Item.GetItemCooldown(self.id)) > 0
end

function Item:IsUsable()
    local usable, noMana = C_Item.IsUsableItem(self.id)
    return usable
end

-- Check if the Item is known
---@return boolean
function Item:IsEquipped()
    return C_Item.IsEquippedItem(self.id)
end

-- Check if the Item is Usable
---@return boolean
function Item:IsEquippedAndUsable()
    return ((self:IsEquippable() and self:IsEquipped()) or
        (not self:IsEquippable() and self:IsUsable())) and not self:HasCooldown()
end

-- Is equippable
---@return boolean
function Item:IsEquippable()
    return C_Item.IsEquippableItem(self.id)
end

-- Check if the Item is Usable
---@return boolean
function Item:Usable()
    return self:IsEquippedAndUsable()
end

return Item