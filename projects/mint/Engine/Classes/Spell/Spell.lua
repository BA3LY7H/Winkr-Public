local unlocker, mint = ...

---@class Spell
---@field id number
---@field name string
---@field icon number
---@field castTime number
---@field lastCastAttempt number
---@field radius number
---@field beneficial boolean
---@field damage string | boolean
---@field heal boolean
---@field effect string | boolean
---@field cc boolean | string
---@field bleed boolean
---@field targeted boolean
---@field ranged boolean
---@field pet boolean
---@field kick boolean
---@field dispel_magic boolean
---@field dispel_curse boolean
---@field dispel_poison boolean
---@field dispel_disease boolean
---@field ignore_facing boolean
---@field ignore_los boolean
---@field ignore_control boolean
---@field ignore_moving boolean
---@field ignore_casting boolean
---@field ignore_channel boolean
---@field ignore_falling boolean
---@field ignore_range boolean
---@field ignore_stun boolean
---@field prevent_double boolean
---@field stupid_channel boolean
---@field cast_by_id boolean
---@field travel_time number
---@field required_buff boolean
---@field callbacks table
---@field keyless function
local Spell = {}
Spell.__index = Spell

-- Metamethod to make spell object callable
function Spell:__call(key, ...)
    -- Handle case: spell(unit) - If key is a Unit object, automatically fall back to Cast
    if type(key) == "table" and key.GetExists then
        return self:Cast(key, ...)
    end

    -- Handle case: spell(unit) - if key is a table/unit and we have a keyless callback, use it as an argument
    if self.keyless and (key == nil or type(key) == "table") then
        return self:Invoke(nil, key, ...)
    elseif type(key) == "function" and self.keyless then
        return self:Invoke(nil, ...)
    else
        return self:Invoke(key, ...)
    end
end


local spell_metatable = {
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
			["dispel_magic"] = function() return instance:GetAllDispelTypes()["magic"] end,
			["dispel_curse"] = function() return instance:GetAllDispelTypes()["curse"] end,
			["dispel_poison"] = function() return instance:GetAllDispelTypes()["poison"] end,
			["dispel_disease"] = function() return instance:GetAllDispelTypes()["disease"] end,
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
            return rawget(instance, k) or Spell[k]
        end
    end,
    __call = Spell.__call
}

function Spell.New(spell_id, traits)
    local instance = setmetatable({}, spell_metatable)

    instance.id = spell_id

    local info = C_Spell.GetSpellInfo(spell_id)

    if info then
        instance.name = info.name
        instance.icon = info.iconID
    else
        instance.name = "Unknown Spell (" .. tostring(spell_id) .. ")"
        instance.icon = 136243 -- Classic question mark icon
        mint.console.log("|cFFFF0000[Warn] Invalid Spell ID:|r " .. tostring(spell_id))
    end
    instance.callbacks = {}

	instance.lastCastAttempt = 0

    traits = traits or {}

    instance.radius         = traits.radius or false
    instance.beneficial     = traits.beneficial or false
    instance.damage         = traits.damage or false
    instance.heal           = traits.heal or false
    instance.effect         = traits.effect or false
    instance.cc             = traits.cc or false
    instance.bleed          = traits.bleed or false
    instance.ranged         = traits.ranged or false
    instance.pet            = traits.pet or false
    instance.kick           = traits.kick or false
    instance.targeted       = true
    instance.ignore_facing  = traits.ignore_facing or false
    instance.ignore_los     = traits.ignore_los or false
    instance.ignore_control = traits.ignore_control or false
    instance.ignore_moving  = traits.ignore_moving or false
    instance.ignore_casting = traits.ignore_casting or false
    instance.ignore_channel = traits.ignore_channel or false
    instance.ignore_falling = traits.ignore_falling or false
    instance.ignore_range   = traits.ignore_range or false
    instance.ignore_stun    = traits.ignore_stun or false
    instance.ignore_known   = traits.ignore_known or false
    instance.ignore_usable  = traits.ignore_usable or false
    instance.stupid_channel = traits.stupid_channel or false
    instance.cast_by_id     = traits.cast_by_id or false
    instance.required_buff  = traits.required_buff or false
    instance.prevent_double = traits.prevent_double or false

	instance.travel_time 	= traits.travel_time or 0

	instance.velocity 		= traits.velocity or false

	-- if instance.velocity then
	-- 	mint.FlightTracked[instance.id] = instance
	-- end

    if traits.targeted == false then
        instance.targeted = false
    end

    return instance
end

return Spell