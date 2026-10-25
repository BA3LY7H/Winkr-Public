local unlocker,
---@class mint
mint = ...

local RaidEvents    = mint.RaidEvents
local settings 	 	= mint.Settings

---@class Reaction
---@field history table
---@field defaults table
---@field reactions table
---@field events EventManager
local Reaction = {}
Reaction.__index = Reaction

function Reaction:New()
    local self = setmetatable({}, Reaction)

    self.history = {}
    self.reactions = {}
	self.defaults = {}
    self.events = mint.EventManager:New()

    self.events:RegisterWoWEvent("UNIT_SPELLCAST_SUCCEEDED", function(...)
        local args = { ... }
    
        local source = args[1]
		local spell_id = args[3]

		if source == "player" then
			self.history[spell_id] = GetTime()
		end
    end)

    return self
end

function Reaction:Sync()
    for i = 1, #self.reactions do
        local obj = self.reactions[i]

        local key = obj.trigger_spell.id .. "-" .. obj.react_spell.id
		local enabled = settings.profile.reactions[key].enabled
        if enabled and GetTime() - obj.last_tick > 0.25 then
            obj.func()
            obj.last_tick = GetTime()
        end
    end
end

function Reaction:PreCast(class, dungeon, trigger_spell, react_spell, time, unit_cb, description)
    local func = function()
        local unit = unit_cb()
        if not unit then return end
    
        local trigger_time = RaidEvents:TimeToSpell(trigger_spell.id)
    
        if trigger_time <= time then
            local last_cast = self.history[react_spell.id]
    
            if (last_cast and (GetTime() - last_cast) < 5) or C_Spell.IsCurrentSpell(react_spell.id) then
                return false
            end
    
            react_spell:Cast(unit)
        end
    end

    local trig_display = "|T" .. trigger_spell.icon .. ":16|t " .. trigger_spell.name
	local react_display = "|T" .. react_spell.icon .. ":16|t " .. react_spell.name
	local key = trigger_spell.id .. "-" .. react_spell.id

    local react_data = {
        key = key,
        class = class,
        dungeon = dungeon,
        trigger_spell = trigger_spell,
        react_spell = react_spell,
        timer = time,
        unit_cb = unit_cb,
        last_tick = 0,
        func = func,
        desc = description
    }

    self.reactions[key] = react_data
    -- table.insert(self.reactions, react_data)

	local default = {
		trigger_name = trig_display,
		react_name = react_display,
		key = key,
		trigger_id = trigger_spell.id,
		react_id = react_spell.id,
		description = description,
		class = class,
        dungeon = dungeon,
		enabled = false,
	}

    self.defaults[key] = default
	-- table.insert(self.defaults, default)
end

function Reaction:OnCast(class, trigger_spell, react_spell, unit_cb)

end

function Reaction:PostCast(class, trigger_spell, react_spell, time, unit_cb)

end

return Reaction