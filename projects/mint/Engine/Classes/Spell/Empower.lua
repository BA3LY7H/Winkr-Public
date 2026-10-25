local unlocker, mint = ...

---@class EmpowerManager
---@field active_spell number|nil
---@field target_rank number|nil
---@field target_guid string|nil
---@field active_timer any|nil
local EmpowerManager = {
    active_spell = nil,
    target_rank = nil,
    target_guid = nil,
    active_timer = nil
}

mint.EmpowerManager = EmpowerManager

--- Find the action bar slot for a given spell ID (slots 1-120)
---@param spellID number
---@return number|nil
local function FindActionSlot(spellID)
    for slot = 1, 120 do
        local actionType, id = GetActionInfo(slot)
        if actionType == "spell" and id == spellID then
            return slot
        end
    end
    return nil
end

-- Event listener for empowerment lifecycle
local listener = CreateFrame("Frame")
listener:RegisterEvent("UNIT_SPELLCAST_EMPOWER_START")
listener:RegisterEvent("UNIT_SPELLCAST_EMPOWER_STOP")
listener:RegisterEvent("UNIT_SPELLCAST_INTERRUPTED")

listener:SetScript("OnEvent", function(self, event, unit, _, spell_id)
    if unit ~= "player" then return end

    if event == "UNIT_SPELLCAST_EMPOWER_START" then
        if EmpowerManager.active_spell and EmpowerManager.target_rank then
            EmpowerManager:ScheduleRelease(spell_id)
        end
    elseif event == "UNIT_SPELLCAST_EMPOWER_STOP" or event == "UNIT_SPELLCAST_INTERRUPTED" then
        EmpowerManager:Reset()
    end
end)

--- Prepare the manager for an incoming empowered cast.
--- Called by Spell:Cast when a numeric rank is provided.
---@param spell_id number
---@param rank number Target empower rank (1-4)
---@param guid? string Target creature GUID
function EmpowerManager:Prepare(spell_id, rank, guid)
    self:Reset()
    self.active_spell = spell_id
    self.target_rank = rank
    self.target_guid = guid
end

--- Calculate the total stage duration and schedule a timed release.
--- Release is performed via winkr_Call(UseAction, slot) which simulates
--- pressing the action bar button — the only method that reliably
--- triggers the "Press and Tap" empowerment release.
---@param event_spell_id number The spell ID from the empower event
function EmpowerManager:ScheduleRelease(event_spell_id)
    if not self.target_rank then return end

    local total_duration = 0

    for i = 1, self.target_rank do
        local duration = GetUnitEmpowerStageDuration("player", i - 1)
        if duration and duration > 0 then
            total_duration = total_duration + (duration / 1000)
        else
            break
        end
    end

    if total_duration > 0 then
        -- Subtract 50ms to compensate for C_Timer frame delay (~16ms)
        local release_time = math.max(0.05, total_duration - 0.05)

        -- Pre-find the action bar slot so the release is instantaneous
        local slot = FindActionSlot(event_spell_id)

        if self.active_timer then
            self.active_timer:Cancel()
        end

        self.active_timer = C_Timer.NewTimer(release_time, function()
            local name = UnitChannelInfo("player")

            if name and slot then
                -- Simulate pressing the action bar button in a clean taint context
                winkr_Call(UseAction, slot, false, false)
            end
            self:Reset()
        end)
    end
end

--- Reset the manager state and cancel any pending timer
function EmpowerManager:Reset()
    if self.active_timer then
        self.active_timer:Cancel()
        self.active_timer = nil
    end
    self.active_spell = nil
    self.target_rank = nil
    self.target_guid = nil
end

-- Compatibility stub
function EmpowerManager:Update() end

return EmpowerManager
