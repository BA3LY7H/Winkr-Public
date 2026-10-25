local unlocker,
---@class mint
mint = ...

--! Mint Locals !--
local player = mint.UnitManager:Get("player")

-- Removed localized WoW APIs to ensure Winkr-hooked globals are used at runtime.

---@class Spell
local Spell = mint.Spell

--- Adding callbacks to a spell
---@param key string|function
---@param callback function?
function Spell:AddCallback(key, callback)
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

-- Invoking a spell with callback
---@param key string?
---@vararg any
function Spell:Invoke(key, ...)
    local callback
    if not key and self.keyless then
        callback = self.keyless
    else
        callback = self.callbacks[key]
    end

    if callback then
        -- Invoke the callback function with the spell object as the first argument
        -- * We want to check to make sure the ability is usable *before* hitting the callback
        -- * As callbacks often have iteration over the unit/friend managers
        -- * Castable is always a static check.
        if self:PreCheck() then
            return callback(self, ...)
        else
            return false
        end
    else
        if type(key) == "function" then
            error("Keyless callback not found for " .. self.name)
        else
            error("Callback '" .. (key or "none") .. "' not found for " .. self.name)
        end
    end
end

-- Cast the spell at given unit with a PreCast
---@param unit Unit?
---@param precast function
---@param key? string
---@return boolean
function Spell:CastWithPreCast(unit, precast, key)
    if not unit then return false end
    if not self:Castable(unit) then return false end

	-- Check for pre-cast function?
    if precast() then
        mint.console.log("Precast was successful for " .. self.name .. ".", "Key:", key and key or "N/A")

        -- if unlocker.name == "winkr" then
        --    winkr_NativeCast(spell_id)
        if self.cast_by_id then
            local spell_id = self.id
            if FindBaseSpellByID(spell_id) ~= spell_id then
                spell_id = FindBaseSpellByID(spell_id)
            end

            if unit and unit:GetExists() then
                local ptr = unit:GetPointer()
                if type(ptr) == "string" and ptr:find("-", 1, true) then
                    winkr_NativeCast(spell_id, ptr)
                else
                    CastSpellByID(spell_id, ptr)
                end
            else
                CastSpellByID(spell_id)
            end
        else
            if unit and unit:GetExists() then
                local ptr = unit:GetPointer()
                if type(ptr) == "string" and ptr:find("-", 1, true) then
                    CastSpellByName(self.name)
                else
                    CastSpellByName(self.name, ptr)
                end
            else
                CastSpellByName(self.name)
            end
        end

        mint.console.log("Casting " .. self.name .. " on " .. (unit and unit.name or "self") .. ".", "Key:", key and key or "N/A")
        self.lastCastAttempt = GetTime()
        return true
    end

    return false
end

-- Cast the spell at given unit
---@param unit Unit?
---@param key? string
---@return boolean
function Spell:CastEmpower(unit, level, key)
    if not unit then return false end
    if not self:Castable(unit) then return false end

    -- if unlocker.name == "winkr" then
    --    winkr_NativeCast(spell_id)
    if self.cast_by_id then
        local spell_id = self.id
        if FindBaseSpellByID(spell_id) ~= spell_id then
            spell_id = FindBaseSpellByID(spell_id)
        end

        if unit and unit:GetExists() then
            local ptr = unit:GetPointer()
            if type(ptr) == "string" and ptr:find("-", 1, true) then
                winkr_NativeCast(spell_id, ptr)
            else
                CastSpellByID(spell_id, ptr)
            end
        else
            CastSpellByID(spell_id)
		end
	else
		if unit and unit:GetExists() then
            local ptr = unit:GetPointer()
            if type(ptr) == "string" and ptr:find("-", 1, true) then
                CastSpellByName(self.name)
            else
                CastSpellByName(self.name, ptr)
            end
		else
            CastSpellByName(self.name)
		end
	end

    self.lastCastAttempt = GetTime()
	return true
end

-- Cast the spell at given unit
---@param unit Unit?
---@param rank? number | string
---@return boolean
function Spell:Cast(unit, rank)
    if not unit then return false end
    if not self:Castable(unit) then return false end

    local spell_id = self.id
    local ptr = unit and unit.guid
    
    -- If a numeric rank is provided, check if we need to track it as an empowered cast
    if type(rank) == "number" and rank >= 1 and rank <= 4 then
        -- Only track if it's an empowered spell. Pass the target pointer for better release accuracy.
        mint.EmpowerManager:Prepare(spell_id, rank, ptr)
    end

    if self.cast_by_id then
        if FindBaseSpellByID(spell_id) ~= spell_id then
            spell_id = FindBaseSpellByID(spell_id)
        end

        if unit and unit:GetExists() then
            if type(ptr) == "string" and ptr:find("-", 1, true) then
                mint.console.log("|cFF00FF00[NativeCast]|r", self.name, "on GUID:", ptr)
                winkr_NativeCast(spell_id, ptr)
            else
                CastSpellByID(spell_id, ptr)
            end
        else
             CastSpellByID(spell_id)
		end
	else
		if unit and unit:GetExists() then
            local ptr = unit:GetPointer()
            if type(ptr) == "string" and ptr:find("-", 1, true) then
                -- Winkr: GetPointer() returns a GUID, use NativeCast with target
                winkr_NativeCast(spell_id, ptr)
            else
                CastSpellByName(self.name, ptr)
            end
		else
            CastSpellByName(self.name)
		end
	end


    self.lastCastAttempt = GetTime()
	return true
end

--- Cast the spell; only notify if the cast succeeded.
--- Returns true if Spell:Cast(...) succeeded.
---@param unit Unit?              -- target unit (or nil for self)
---@param text string|nil         -- notification text (defaults to self.name)
---@param dur number|nil          -- notification duration (defaults to 3)
---@param icon number|nil         -- icon fileID (defaults to self.icon)
---@param key string|nil          -- optional cast key (passed to Spell:Cast)
---@return boolean
function Spell:CastNotify(unit, text, dur, icon, key)
    local ok = self:Cast(unit, key)
    if ok then
        mint.NotificationManager:AddNotification(icon or self.icon, text or self.name, dur or 3)
    end
    return ok
end


-- Determine if a spell is usable currently
-- * This is a pre-callback check to determine the ability is usable
-- * As the target unit is not fed into this, we cannot check that until 
-- * after the callback, unless we add a Castable check to the callback
function Spell:PreCheck()
    -- Check Falling
    if self:GetCastTime() > 0 and IsFalling() and not (self.ignore_falling or self.ignore_moving) then
        -- mint.console.log(self.name .. ": Falling")
        return false
    end

    -- Check if the spell is usable while moving
	if self:GetCastTime() > 0 then

        -- Will not be able to finish this cast, adding buffer for ms or knockback
        -- if mint.RaidEvents:TimeToNext("Cast Cancel") < self:GetCastTime() + 0.2 then
        --     return false
        -- end

        -- * Check if we can cast while moving
		if not self.ignore_moving and player:IsMoving() then
            mint.console.log(self.name .. ": Cast Time + Moving")
			if not player:CanCastMove() then
				return false
			end
		end
	end

    -- Prevent double casting a spell
    if self.prevent_double then
        if C_Spell.IsCurrentSpell(self.id) and not self.targeted then
                mint.console.log(self.name .. ": We are already casting this spell.")
            return false
        end
    end

    -- Check if the spell is on cooldown
    if self:IsOnCD() then
        -- mint.console.log(self.name .. ": On Cooldown")
        return false
    end

        -- Check if we can cast this while casting/channeling
    local can_cast_while_casting = self.ignore_casting or self.pet
	local can_cast_while_channeling = self.ignore_channel or self.pet

    -- * Check if player is casting and if spell can be cast while casting.
	if player:IsCasting() and not can_cast_while_casting then
		local sqw = C_CVar.GetCVar("SpellQueueWindow")
		local _, _, _, latency_world = GetNetStats()
		if mint.gcd > ((latency_world / 1000) + (sqw / 1000)) then
            mint.console.log("Not casting", self.name, "while casting")
            return false
		end
	end

    if player:IsChanneling() and not can_cast_while_channeling then
        mint.console.log("Not casting", self.name, "while channeling")
        return false
    end

    -- * Check if the spell is known
	if not self:IsKnown() and not self.ignore_known then
        mint.console.log(self.name .. ": Not Known (Castable)")
        return false
    end

    -- * Check if the spell is usable
	if not self:IsUsable() and not self.ignore_usable then
        mint.console.log(self.name .. ": Not Usable (Pre-Check)")
        return false
    end

    return true
end

-- Determine if the spell is castable based on spell traits
---@param unit Unit?
---@param options table?
---@return boolean
function Spell:Castable(unit, options)
    if self.targeted and not unit then
        mint.console.log(self.name .. ": No unit to cast on")
        return false
    end

    -- if cast_timers[self.id] and cast_timers[self.id] >= GetTime() then
    --     return false
    -- end

    -- Check for required_buff
    -- if self.required_buff then
    --     if not player.buff(self.required_buff) then
    --         return false
    --     end
    -- end

    -- Check if unit exists
    if self.targeted and unit and not unit:GetExists() then
        mint.console.log(self.name .. ": No target")
        return false
    end

    if self.prevent_double then
        if C_Spell.IsCurrentSpell(self.id) then
            if self.targeted and player:GetCastTarget() and self:GetCastTime() > 0 then
                if unit:IsUnit(player:GetCastTarget()) then
                    mint.console.log(self.name .. ": we are already casting this spell on this target.")
                    return false
                end
            else
                mint.console.log(self.name .. ": We are already casting this spell.")
                return false
            end
        end
    end

    -- Check if unit is dead
    if self.targeted and unit and unit.is_dead then
        mint.console.log(self.name .. ": Dead")
        return false
    end

    -- -- Check if unit is immune to effect type, if given
    -- if self.targeted and self.effect and unit then
    --     if unit:IsImmuneTo(self.effect) then return false end
    -- end

    -- -- Check if unit is immune to damage type, if given
    -- if self.targeted and self.damage and unit then
    --     if unit:IsImmuneTo(self.damage) then return false end
    -- end

    -- Check if the spell is a kick and unit is casting
    if self.targeted and self.kick and unit then
        if not unit:IsCasting() or not unit:IsKickable() then
            return false
        end
    end

    -- If out of range must have ignore_range
    if self.targeted and unit and not self:IsInRange(unit) and not self.ignore_range then
        mint.console.log(self.name .. ": Range")
        return false
    end

    -- If out of los, must have ignore_los
    if self.targeted and unit and not player:HasLos(unit) and not self.ignore_los then
        mint.console.log(self.name .. ": LoS")
        return false
    end

    if self.targeted and unit and not player:IsFacing(unit) and not self.ignore_facing and not self.pet and not self.beneficial then
        mint.console.log(self.name .. ": Not Facing")
        return false
    end

    return true
end

function Spell:CastUnder(unit, key)
    if not self:Castable(unit) then return false end

    -- Sync with Retail Tinkr: Movement Guard
    if player:IsMoving() then 
        return false 
    end

    if unit and unit.exists then
        local position = unit:GetPosition():Humanize()
        local mouse = false

        -- Initial Mouselook Stop
        if IsMouselooking() then
            mouse = true
            MouselookStop()
        end

        -- Trigger the spell
        if self.cast_by_id then
            CastSpellByID(self.id)
        else
            CastSpellByName(self.name)
        end

        -- Placement logic with Secondary Stop (Retail Style)
        if mint.IsSpellPending() == 64 then
            MouselookStop()
            mint.Click(position.x, position.y, position.z)
            mint.console.log("|cFF00FF00[CastUnder-1:1]|r", self.name, "under", unit.name or "target")
            
            if mouse then
                MouselookStart()
            end
            return true
        end

        -- Restore if failed
        if mouse then
            MouselookStart()
        end
        return false
    else
        return false
    end
end

local dispelSpellTypes = {
	["magic"] = {
		[88423] 		= true, -- nature's cure/druid
		[527] 			= true, -- purify/priest
		[4987] 			= true, -- cleanse/paladin
		[77130] 		= true, -- purge shaman
		[115450] 		= true, -- Detox, MW Monk
		[32375] 		= true, -- massdispel/priest
		[360823] 		= true -- Naturalize (Evoker)
	},
	["curse"] = {
		[77130]			= IsPlayerSpell(383016),	-- Shaman talented curse removal
		[88423] 		= IsPlayerSpell(392378), -- nature's cure/druid
		[374251] 		= true, -- Cauterizing Flame (Evoker)
		[51886]			= true,
		[475]			= true, -- Remove Curse (Mage)
		[2782] 			= true -- Remove Corruption (Druid)
	},
	["poison"] = {
		[115450]		= IsPlayerSpell(388874), -- Detox (MW Monk)
		[383013]		= true, -- Poison Cleansing Totem (talent)
		[218164]		= true, -- Detox (BM/WW Monk)
		[2782]          = true, -- Remove Corruption (Druid)
		[88423]         = IsPlayerSpell(392378), -- Nature's Cure (Druid)
		[213644]        = true, -- Cleanse Toxins (Paladin)
		[4987]          = IsPlayerSpell(393024), -- Cleanse (Holy Paladin)
		[365585]        = true, -- Expunge (Evoker)
		[360823]        = true, -- Naturalize (Evoker)
		[374251]        = true -- Cauterizing Flame (Evoker)
	},
	["disease"] = {
		[115450]		= IsPlayerSpell(388874), -- Detox (Monk)
		[218164]		= true, -- Detox (BM/WW Monk)
		[527]           = IsPlayerSpell(390632), -- Purify (Priest)
		[213634]		= true,	-- Purify Disease (Priest)
		[4987] 			= IsPlayerSpell(393024), -- cleanse/ Holy paladin
		[213644] 		= true, -- CleanseToxins/paladin
		[374251] 		= true -- Cauterizing Flame (Evoker)
	}
}

function Spell:GetAllDispelTypes()
	local myTypes = {}

	for k, v in pairs(dispelSpellTypes) do
		if v[self.id] then
			myTypes[k] = true
		end
	end

	return myTypes
end

function Spell:CanDispelType(thisType)
	return dispelSpellTypes[thisType] and dispelSpellTypes[thisType][self.id]
end

function Spell:GetDispelType()
	for k, v in pairs(dispelSpellTypes) do
		if v[self.id] then
			return k
		end
	end

	return nil
end

--------------------------
--- Last Cast Tracking ---
--------------------------

-- Get time since the last attempt to cast this spell
---@return number
function Spell:TimeSinceLastAttempt()
	if self.lastCastAttempt == 0 then
		return 999
	end
	
    return GetTime() - self.lastCastAttempt
end

-- Check if this spell was cast
---@return boolean
function Spell:WasMostRecentCast()
    local order = mint.data.lastCastOrder
    if order then
        return order[#order] == self.id
    end

    return false
end

-- Check if this spell was cast
---@return boolean
function Spell:WasLastCast()
    return mint.data.lastCastTimers[self.id] ~= nil
end

-- Get time since this spell was last cast
---@return number
function Spell:TimeSinceLastCast()
    if mint.data.lastCastTimers[self.id] then
        return GetTime() - mint.data.lastCastTimers[self.id]
    end
    return 999 -- A large number indicating "never cast"
end

-- Reset tracking for a specific spell
---@return nil
function Spell:ResetLastCastTracking()
    mint.data.lastCastTimers[self.id] = nil
end

-- Get the timestamp of when this spell was last cast
---@return number|nil
function Spell:LastCastTime()
    return mint.data.lastCastTimers[self.id]
end

-- if a spell was 2 of the last 3 casts, for example
function Spell:WasXOfYMostRecent(count, castDepth)

    local order = mint.data.lastCastOrder
    if not order then return false end

    local count = count
    local castDepth = castDepth

    local castCount = 0
    for i = 1, castDepth do
        if order[#order - i] == self.id then
            castCount = castCount + 1
        end
    end

    return castCount >= count
end

function Spell:IsCurrentCast()
    local spell_id = player:GetCastSpellID()

    return spell_id == self.id
end