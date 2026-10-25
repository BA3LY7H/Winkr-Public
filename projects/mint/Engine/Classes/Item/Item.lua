---@class Item
---@field id number
---@field name string
---@field callbacks table
---@field keyless function
local Item = {}
Item.__index = Item

-- Metamethod to make Item object callable
function Item:__call(key, ...)
    if type(key) == "function" and self.keyless then
        self:Invoke(nil, ...)
    else
        self:Invoke(key, ...)
    end
end


local item_metatable = {
    __index = function(instance, k)

        local attributes = {
            ["base_cd"] = function() return instance:GetBaseCD() end,
            ["cast_time"] = function() return instance:GetCastTime() end,
            ["cd"] = function() return instance:GetRemainingCD() end,
            ["on_cd"] = function() return instance:IsOnCD() end,
            ["cooldown"] = function() return instance:GetRemainingCD() end,
            ["max_cd"] = function() return instance:GetBaseCooldown() end,
            ["count"] = function() return instance:GetCount() end,
            ["charges"] = function() return instance:GetCharges() end,
            ["charges_frac"] = function() return instance:GetChargesFractional() end,
            ["charges_max"] = function() return instance:GetMaxCharges() end,
            ["next_charge_cd"] = function() return instance:get_next_charge_cd() end,
            ["max_charge_cd"] = function() return instance:get_max_charge_cd() end,
            ["cost"] = function(power_type) return instance:get_cost(power_type) end,
            ["effect"] = function() return instance:get_effect() end,
            ["damage"] = function() return instance:get_effect() end,
            ["flying"] = function() return instance:get_flying() end,
            ["gcd"] = function() return instance:get_gcd() end,
            ["known"] = function() return instance:IsKnown() end,
            ["queued"] = function() return instance:get_queued() end,
            ["range"] = function() return instance:get_range() end,
            ["usable"] = function() return instance:get_usable() end,
            ["used"] = function(sec) return instance:get_used_within(sec) end,
            ["proc"] = function() return instance:get_is_procced() end,
            ["ready"] = function() return not instance:IsOnCD() end,
        }

        local methods = {
            ["inRange"] = function(spellTarget) return instance:IsInRange(spellTarget) end,
            ["iconString"] = function(size)
                local size = size or 16
                return "|T" .. instance.icon .. ":" .. size .. "|t"
            end,
		}

		-- add something to handle time_to_pct_x

        if attributes[k] then
            return attributes[k]()
        elseif methods[k] then
            return function(...)
                return methods[k](...)
            end
        else
            return rawget(instance, k) or Item[k]
        end
    end,
    __call = Item.__call
}

-- Create a new Item instance
---@param item_id number
---@param traits table?
---@return Item
function Item.New(item_id, traits)
    local instance = setmetatable({}, item_metatable)

    instance.icon = C_Item.GetItemIconByID(item_id)

    instance.id = item_id

	if traits and traits.use_name then
        instance.name = C_Item.GetItemNameByID(instance.id)
    else
        instance.name, instance.spell_id = C_Item.GetItemSpell(instance.id)
    end

    instance.callbacks = {}

    return instance
end

return Item