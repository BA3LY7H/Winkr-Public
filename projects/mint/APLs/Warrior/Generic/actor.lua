local unlocker, ---@class mint
mint, addon = ...

local UnitManager   = mint.UnitManager
local Constants     = mint.Constants
local target        = UnitManager:Get("target")
local player        = UnitManager:Get("player")

local gen       = addon.warrior.generic
local spells    = addon.warrior.data["generic"].spells
local auras     = addon.warrior.data["generic"].auras
local targets   = addon.warrior.data["generic"].targets
local settings  = mint.Settings and mint.Settings.profile and mint.Settings.profile.warrior and mint.Settings.profile.warrior.generic

-- Count nearby attackable enemies in melee range using nameplate tokens
local function GetMeleeEnemyCount()
    local count = 0
    for i = 1, 40 do
        local unit = "nameplate" .. i
        if UnitExists(unit)
            and UnitCanAttack("player", unit)
            and not UnitIsDeadOrGhost(unit)
            and (UnitAffectingCombat(unit) or UnitThreatSituation("player", unit))
        then
            local inRange = C_Spell.IsSpellInRange(1464, unit)
            if inRange == true or inRange == 1 then
                count = count + 1
            end
        end
    end
    return count
end

gen:Sync(function()
    if not player.alive then return end

    -- Target validation using direct WoW APIs (tokens always work)
    if not UnitExists("target") then return end
    if not UnitCanAttack("player", "target") then return end
    if UnitIsDeadOrGhost("target") then return end

    -- Start auto-attack using StartAttack() (same pattern as Hunter rotation)
    if not C_Spell.IsCurrentSpell(6603) then
        StartAttack()
    end

    -- Current actual settings structure from DB may be missing if not initialized, so fallback.
    local autoChargeEnabled = true
    if settings and settings.autoCharge ~= nil then
        autoChargeEnabled = settings.autoCharge
    end

    -- 1. Engage with Charge (use WoW's native range check for charge distance)
    if autoChargeEnabled then
        local chargeInRange = C_Spell.IsSpellInRange(100, "target")
        local slamInRange = C_Spell.IsSpellInRange(1464, "target")
        -- Charge if target is in Charge range but NOT in melee range
        if (chargeInRange == true or chargeInRange == 1) and not (slamInRange == true or slamInRange == 1) then
            if spells.charge() then return end
        end
    end

    -- 2. Shield Strike / Shield Slam (High Priority - always use on CD)
    if spells.shield_strike() then return end

    -- 3. AoE vs Single Target decision
    local enemyCount = GetMeleeEnemyCount()

    if enemyCount >= 2 then
        -- AoE Priority: Whirlwind over Slam when 2+ enemies in melee
        if spells.whirlwind() then return end
        if spells.slam() then return end
    else
        -- Single Target: Slam
        if spells.slam() then return end
    end
end)
