local unlocker,
---@class mint
mint = ...


------------------------------
--- Locals
------------------------------
local UnitManager 		= mint.UnitManager
local ObjectManager 	= mint.ObjectManager
local target  			= UnitManager:Get("target")
local player  			= UnitManager:Get("player")
mint.ttd_cache          = mint.Cache.New()

--- An attempt to integrate HeroLib TTD timers.

-- Reworked TimeToDie module with weighted regression, throttled sampling, and unified sentinels
local TimeToDie = {
    Settings = {
        Refresh = 0.5,          -- seconds between samples
        HistoryTime = 10.4,      -- seconds of history to keep
        HistoryCount = 100,      -- max samples per unit
    },
    Cache = mint.ttd_cache,       -- pooled {time, hp} tables
    Units = {},                   -- [guid] = { values={}, t0=now }
    ExistingUnits = {},           -- [guid] = true if seen this refresh
    Throttle = 0,                 -- last refresh time
    Constants = {
        INVALID = 11111,          -- sentinel for invalid/unknown
        EPS_SLOPE = 0.0005,       -- min downward %/sec to consider dying
        MIN_SAMPLES = 3,
        TAU = 4.0,                -- seconds; recency weighting constant
        MIN_DELTA = 0.1,          -- ignore jitter below 0.1% hp
    },
    _frameStamp = 0,
    _cacheByGuid = {},
}

---@enum (key) CompareThisTable
local compareThisTable = {
    [">"] = function(A, B) return A > B end,
    ["<"] = function(A, B) return A < B end,
    [">="] = function(A, B) return A >= B end,
    ["<="] = function(A, B) return A <= B end,
    ["=="] = function(A, B) return A == B end,
    ["min"] = function(A, B) return A < B end,
    ["max"] = function(A, B) return A > B end,
}

mint.ttd_util = {
    ---@generic A
    ---@param operator CompareThisTable
    ---@param a A
    ---@param b A
    CompareThis = function(operator, a, b)
        return compareThisTable[operator](a, b)
    end
}

function TimeToDie:IterableUnits()
    return ObjectManager.enemies
end

function TimeToDie:Refresh()
    local now = GetTime()
    if (now - (self.Throttle or 0)) < (self.Settings.Refresh or 0.5) then
        return
    end
    self.Throttle = now

    local historyCount = self.Settings.HistoryCount
    local historyTime = self.Settings.HistoryTime
    local ttdCache = self.Cache
    local iterableUnits = ObjectManager.enemies
    local units = self.Units
    local existingUnits = self.ExistingUnits

    wipe(existingUnits)

    iterableUnits:each(function(unit)
        if unit:GetExists() then
            local guid = unit.guid
            if guid and not existingUnits[guid] then
                existingUnits[guid] = true
                local hp = unit:GetHP()
                if hp < 100 then
                    local u = units[guid]
                    if not u or hp > (u[1][#(u[1] or {})] and u[1][#u[1]][2] or 0) then
                        u = { {}, now }
                        units[guid] = u
                    end
                    local values = u[1]
                    local tRel = now - u[2]
                    local last = values[#values]
                    if not last or math.abs(hp - last[2]) >= self.Constants.MIN_DELTA then
                        local v
                        local ncache = #ttdCache
                        if ncache == 0 then
                            v = { tRel, hp }
                        else
                            v = ttdCache[ncache]
                            ttdCache[ncache] = nil
                            v[1], v[2] = tRel, hp
                        end
                        values[#values + 1] = v
                        -- Trim obsolete samples (time) and cap count
                        while #values > 0 and ((tRel - values[1][1]) > historyTime or #values > historyCount) do
                            ttdCache[#ttdCache + 1] = table.remove(values, 1)
                        end
                    end
                end
            end
        end
        return false
    end)

    -- purge vanished units
    for guid in pairs(units) do
        if not existingUnits[guid] then
            units[guid] = nil
        end
    end
end

TimeToDie.specialTTDPercentageData = {
    --- Dragonflight
    ----- Dungeons -----
    --- Brackenhide Hollow
    -- Decatriarch Wratheye
    [186121] = 5,

    --- Shadowlands
    ----- Dungeons -----
    --- De Other Side
    -- Mueh'zala leaves the fight at 10%.
    [166608] = 10,
    --- Mists of Tirna Scithe
    -- Tirnenns leaves the fight at 20%.
    [164929] = 20, -- Tirnenn Villager
    [164804] = 20, -- Droman Oulfarran
    --- Sanguine Depths
    -- General Kaal leaves the fight at 50%.
    [162099] = 50,
    ----- Castle Nathria -----
    --- Stone Legion Generals
    -- General Kaal leaves the fight at 50% if General Grashaal has not fight yet. We ...nce it get -95% dmg reduction at 50% until intermission is over.
    [168112] = function(self) return (not self:CheckHPFromBossList(168113, 99) and 49) or 0 end,
    --- Sun King's Salvation
    -- Shade of Kael'thas fight is 60% -> 45% and then 10% -> 0%.
    [165805] = function(self) return (self:GetHP() > 20 and 45) or 0 end,
    ----- Sanctum of Domination -----
    --- Eye of the Jailer leaves at 66% and 33%
    [180018] = function(self)
        return (self:GetHP() > 66 and 66) or
            (self:GetHP() <= 66 and self:GetHP() > 33 and 33) or 0
    end,
    --- Painsmith Raznal leaves at 70% and 40%
    [176523] = function(self)
        return (self:GetHP() > 70 and 70) or
            (self:GetHP() <= 70 and self:GetHP() > 40 and 40) or 0
    end,
    --- Sylvanas Windrunner intermission at 83% and "dies" at 50% (45% in MM)
    [179390] = function(self)
        return (self:GetHP() > 70 and 70) or
            (self:GetHP() <= 70 and self:GetHP() > 40 and 40) or 0
    end,
    --- Sylvanas Windrunner intermission at 83% and "dies" at 50% (45% in MM)
    [180828] = function(self)
        local _, _, difficultyId = GetInstanceInfo()
        return (self:GetHP() > 83 and 83) or
            ((difficultyId == 16 and 45) or 50)
    end,

    --- Legion
    ----- Open World  -----
    --- Stormheim Invasion
    -- Lord Commander Alexius
    [118566] = 85,
    ----- Dungeons -----
    --- Halls of Valor
    -- Hymdall leaves the fight at 10%.
    [94960] = 10,
    -- Fenryr leaves the fight at 60%. We take 50% as check value since it doesn't get immune at 60%.
    [95674] = function(self) return (self:GetHP() > 50 and 60) or 0 end,
    -- Odyn leaves the fight at 80%.
    [95676] = 80,
    --- Maw of Souls
    -- Helya leaves the fight at 70%.
    [96759] = 70,
    ----- Trial of Valor -----
    --- Odyn
    -- Hyrja & Hymdall leaves the fight at 25% during first stage and 85%/90% during second stage (HM/MM).
    [114360] = function(self)
        local _, _, difficultyId = GetInstanceInfo()
        return (not self:CheckHPFromBossList(114263, 99) and 25) or
            (difficultyId == 16 and 85) or 90
    end,
    [114361] = function(self)
        local _, _, difficultyId = GetInstanceInfo()
        return (not self:CheckHPFromBossList(114263, 99) and 25) or
            (difficultyId == 16 and 85) or 90
    end,
    -- Odyn leaves the fight at 10%.
    [114263] = 10,
    ----- Nighthold -----
    --- Elisande leaves the fight two times at 10% then normally dies. She looses 50% power per stage (100 -> 50 -> 0).
    [106643] = function(self) return (self:GetPower() > 0 and 10) or 0 end,

    --- Warlord of Draenor (WoD)
    ----- Dungeons -----
    --- Shadowmoon Burial Grounds
    -- Carrion Worm doesn't die but leave the area at 10%.
    [88769] = 10,
    [76057] = 10,
    ----- HellFire Citadel -----
    --- Hellfire Assault
    -- Mar'Tak doesn't die and leave fight at 50% (blocked at 1hp anyway).
    [93023] = 50,

    --- Classic
    ----- Dungeons -----
    --- Uldaman
    -- Dwarves
    [184580] = 5,
    [184581] = 5,
    [184582] = 5,
}

-- Compute effective 'kill' percent for a unit (0 by default or special phase %)
function TimeToDie:EffectiveEndPercent(unit)
    if not unit then return 0 end
    local npcId = unit.npc_id
    local entry = npcId and self.specialTTDPercentageData[npcId]
    if not entry then return 0 end
    local t = type(entry)
    if t == "number" then
        return entry
    elseif t == "function" then
        local ok, result = pcall(entry, unit)
        if ok and type(result) == "number" then
            return result
        end
    end
    return 0
end

-- Get history buffer for guid
function TimeToDie:GetHistory(guid)
    local u = guid and self.Units[guid]
    if not u then return nil, nil end
    return u[1], u[2]
end

-- Weighted linear regression on {t, hp%} with exponential recency weight; returns seconds to endPct
function TimeToDie:Estimate(unit)
    local C = self.Constants
    if not unit or not unit:GetExists() then
        return C.INVALID
    end
    local guid = unit.guid
    local values, t0 = self:GetHistory(guid)
    if not values or #values < C.MIN_SAMPLES then
        return C.INVALID
    end

    local nowRel = GetTime() - t0
    local cutoff = nowRel - (self.Settings.HistoryTime or 10.4)

    local Sw, St, Sy, Stt, Sty = 0, 0, 0, 0, 0
    local lastY = 100
    local tau = self.Constants.TAU
    local iStart = 1
    local n = #values
    while iStart <= n and values[iStart][1] < cutoff do
        iStart = iStart + 1
    end
    for i = iStart, n do
        local ti = values[i][1]
        local yi = values[i][2]
        if yi > lastY then
            yi = lastY
        else
            lastY = yi
        end
        if i == iStart or math.abs(yi - values[i-1][2]) >= C.MIN_DELTA then
            local age = nowRel - ti
            local w = math.exp(-age / tau)
            Sw  = Sw  + w
            St  = St  + w * ti
            Sy  = Sy  + w * yi
            Stt = Stt + w * ti * ti
            Sty = Sty + w * ti * yi
        end
    end

    if Sw == 0 then return C.INVALID end
    local denom = (Sw * Stt - St * St)
    if math.abs(denom) < 1e-6 then return C.INVALID end
    local slope = (Sw * Sty - St * Sy) / denom
    local intercept = (Sy - slope * St) / Sw

    if slope >= -C.EPS_SLOPE then
        return C.INVALID
    end

    local endPct = self:EffectiveEndPercent(unit)
    local t_end_rel = (endPct - intercept) / slope
    local ttd = t_end_rel - nowRel
    if not ttd or ttd < 0 then
        return 0.1
    end
    if ttd > C.INVALID then
        return C.INVALID
    end
    return ttd
end

-- Per-frame cached TTD lookup
function TimeToDie:GetTTD(unit)
    local C = self.Constants
    local now = GetTime()
    if now ~= self._frameStamp then
        self._frameStamp = now
        wipe(self._cacheByGuid)
    end
    local guid = unit and unit.guid
    if not guid then return C.INVALID end
    local cached = self._cacheByGuid[guid]
    if cached ~= nil then return cached end
    local ttd = self:Estimate(unit)
    self._cacheByGuid[guid] = ttd
    return ttd
end

---@param enemies? List
---@param bossOnly? boolean
function TimeToDie.FightRemains(enemies, bossOnly)
    local C = TimeToDie.Constants
    local bossExists, maxTTD
    for i = 1, 4 do
        local bossUnit = UnitManager:Get(string.format("boss%d", i))
        if bossUnit:Exists() then
            bossExists = true
            local ttd = TimeToDie:GetTTD(bossUnit)
            if ttd < C.INVALID then
                maxTTD = math.max(maxTTD or 0, ttd)
            end
        end
    end

    if bossExists or bossOnly then
        return maxTTD or C.INVALID
    end

    if enemies then
        enemies:each(function(enemy)
            if (enemy:CombatConfidence() > 80 or enemy:IsDummy()) then
                local ttd = TimeToDie:GetTTD(enemy)
                if ttd < C.INVALID then
                    maxTTD = math.max(maxTTD or 0, ttd)
                end
            end
            return false
        end)
        if maxTTD then return maxTTD end
    end

    return TimeToDie:GetTTD(target)
end

function TimeToDie.ActiveFightRemains(only_track_bosses)
    local C = TimeToDie.Constants
    local bossExists, maxTTD
    if IsInRaid() or only_track_bosses then
        for i = 1, 4 do
            local bossUnit = UnitManager:Get(string.format("boss%d", i))
            if bossUnit:Exists() then
                bossExists = true
                local ttd = TimeToDie:GetTTD(bossUnit)
                if ttd < C.INVALID then
                    maxTTD = math.max(maxTTD or 0, ttd)
                end
            end
        end
    end
    if bossExists or only_track_bosses then
        return maxTTD or C.INVALID
    end

    if ObjectManager.combat then
        ObjectManager.combat:each(function(enemy)
            if (enemy:CombatConfidence() > 80 or enemy:IsDummy()) then
                local ttd = TimeToDie:GetTTD(enemy)
                if ttd < C.INVALID then
                    maxTTD = math.max(maxTTD or 0, ttd)
                end
            end
            return false
        end)
        if maxTTD then return maxTTD end
    end

    return TimeToDie:GetTTD(target)
end

-- Returns the max fight length of boss units, 11111 if not a boss fight
function TimeToDie.BossFightRemains()
    return TimeToDie.FightRemains(nil, true)
end

-- Get if the Time To Die is Valid for a boss fight remains
function TimeToDie.BossFightRemainsIsNotValid()
    return TimeToDie.BossFightRemains() >= TimeToDie.Constants.INVALID
end

-- Returns if the current fight length meets the requirements.
---@param enemies? List
---@param operator CompareThisTable
---@param value number
---@param checkIfValid boolean
---@param bossOnly boolean
function TimeToDie.FilteredFightRemains(enemies, operator, value, checkIfValid, bossOnly)
    local fightRemains = TimeToDie.FightRemains(enemies, bossOnly)
    if checkIfValid and fightRemains >= TimeToDie.Constants.INVALID then
        return false
    end
    return mint.ttd_util.CompareThis(operator, fightRemains, value) or false
end

-- Returns if the current boss fight length meets the requirements, 11111 if not a boss fight.
---@param operator CompareThisTable
---@param value number
---@param checkIfValid boolean
function TimeToDie.BossFilteredFightRemains(operator, value, checkIfValid)
    return TimeToDie.FilteredFightRemains(nil, operator, value, checkIfValid, true)
end

return TimeToDie
