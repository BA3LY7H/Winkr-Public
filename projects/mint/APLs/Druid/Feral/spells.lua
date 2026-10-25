local unlocker,
---@class mint
mint,
addon = ...

--! Mint Locals !--
local ObjectManager = mint.ObjectManager
local Unit          = mint.Unit
local UnitManager   = mint.UnitManager
local Spell         = mint.Spell.New
local target        = UnitManager:Get("target")
local player        = UnitManager:Get("player")
local none          = UnitManager:Get("none")

--! Addon Locals !--
local feral                 = addon.druid.feral
local lastUnitScanTime      = 0
local unitScanCooldown      = 0.5
local isCurrentlyLooting    = false

local spells = {
    autoAttack          = Spell(6603),
    autoLoot            = Spell(3365),
    barkskin            = Spell(22812, { targeted = false, beneficial = true }),
    bearForm            = Spell(5487, { targeted = false, ignore_moving = true }),
    berserk             = Spell(106951, { targeted = false, beneficial = true }),
    brutalSlash         = Spell(202028, { targeted = false, ignore_facing = true, damage = "physical", radius = 8 }),
    catForm             = Spell(768, { targeted = false, ignore_moving = true }),
    convokeTheSpirits   = Spell(323764, { targeted = false, beneficial = true }),
    feralFrenzy         = Spell(274837, { ignore_facing = true, damage = "physical" }),
    ferociousBite       = Spell(22568, { damage = "physical" }),
    markOfTheWild       = Spell(1126, { targeted = false, beneficial = true }),
    moonfire 			= Spell(8921, { ignore_facing = true, damage = "magic" }),
    moonkinForm         = Spell(24858, { targeted = false, ignore_moving = true }),
    primalWrath         = Spell(285381, { targeted = false, ignore_facing = true, damage = "physical", radius = 8 }),
    prowl               = Spell(5215, { targeted = false, beneficial = true }),
    rake 				= Spell(1822, { damage = "physical" }),
    regrowth 			= Spell(8936, { beneficial = true }),
    rejuvenation 		= Spell(774, { beneficial = true }),
    removeCorruption    = Spell(2782, { beneficial = true }),
    renewal             = Spell(108238, { targeted = false, beneficial = true }),
    rip                 = Spell(1079, { damage = "physical" }),
    shadowmeld          = Spell(58984, { targeted = false, beneficial = true }),
    shred               = Spell(5221, { damage = "physical" }),
    skullBash           = Spell(106839, { kick = true }),
    survivalInstincts   = Spell(61336, { targeted = false, beneficial = true }),
    swipe               = Spell(106785, { targeted = false, ignore_facing = true, damage = "physical", radius = 8 }),
    thrash              = Spell(106830, { targeted = false, ignore_facing = true, damage = "physical", radius = 8 }),
    tigersFury          = Spell(5217, { targeted = false, beneficial = true }),
    travelForm          = Spell(783, { targeted = false, ignore_moving = true }),
    wrath 				= Spell(5176, { damage = "magic" }),
}

local auras = {
    barkskin            = Spell(22812),
    bearForm            = Spell(5487),
    berserk             = Spell(106951),
    catForm             = Spell(768),
    convokeTheSpirits   = Spell(323764),
    markOfTheWild       = Spell(1126),
    moonfire            = Spell(155625),
    moonkinForm         = Spell(24858),
    predatorySwiftness  = Spell(69369),
    prowl               = Spell(5215),
    rake                = Spell(155722),
	regrowth 			= Spell(8936),
    rejuvenation 		= Spell(774),
    rip                 = Spell(1079),
    shadowmeld          = Spell(58984),
    survivalInstincts   = Spell(61336),
    thrash              = Spell(405233),
    tigersFury          = Spell(5217),
    travelForm          = Spell(783),
}

-- Debug system
feral.debug = {
    enabled = true,                   -- Master toggle for debug messages
    throttle = mint.max_gcd,          -- Default throttle time in seconds
    color = "|cffFF7D0A",             -- Druid orange color
    prefix = "[Mint Feral]",           -- Prefix for all messages
    lastMsg = {},                     -- Table to store last message times
}

--#region targets

local targets = {}

targets.baseAttack = function(unit)
    if not unit then unit = target end
    if not unit:GetExists()
        or not unit:IsEnemy()
        or unit:IsDead()
        or not player:CanAttack(unit)
        or not unit:HasLos(player)
    then return false end
    return true
end

-- Extract the priority calculation logic into a helper function
targets.calculatePriority = function(unit)
    local priority = 100 - unit:GetAttackRange(player)

    -- Prioritize units based on form and situation
    if player:FindBuff(auras.catForm, true):Active() then
        -- In cat form, prioritize melee range enemies
        if unit:GetAttackRange(player) <= 5 then
            priority = priority + 50
        end

        -- Prioritize units with bleeds already on them
        if unit:FindDebuff(auras.rake, true):Active() then priority = priority + 10 end
        if unit:FindDebuff(auras.rip, true):Active() then priority = priority + 10 end

        -- Prioritize lower health enemies for better finishing
        if unit:GetRealizedHP() < 20 then priority = priority + 30 end
    else
        -- In caster form, prioritize enemies at range
        if unit:GetAttackRange(player) > 10 then
            priority = priority + 20
        end
    end

    return priority
end

-- Helper function for finding interruptable targets
targets.interruptable = function(unit, threshold)
    -- Default threshold if not specified (30%)
    threshold = threshold or 30

    -- Get cast info using framework API if possible, otherwise WoW API
    local castName, castStart, castEnd, notInterruptible, spellID

    -- Check if unit is casting or channeling
    if unit.casting then
        castName, _, _, castStart, castEnd, _, _, notInterruptible, spellID = UnitCastingInfo(unit:GetPointer())
    elseif unit.channeling then
        castName, _, _, castStart, castEnd, _, _, notInterruptible, spellID = UnitChannelInfo(unit:GetPointer())
    else
        return false -- Not casting or channeling
    end

    -- Return false if we couldn't get cast info or spell is not interruptible
    if not castName or notInterruptible then return false end

    -- Calculate cast progress as percent
    local castTimeTotal = (castEnd - castStart) / 1000
    local castTimeElapsed = (GetTime() * 1000 - castStart) / 1000
    local castPercent = castTimeElapsed / castTimeTotal * 100

    -- Add some randomness to the threshold (±5%)
    local randomVariation = math.random(-5, 5)
    local adjustedThreshold = threshold + randomVariation

    -- Don't let threshold go below 10% or above 90%
    adjustedThreshold = math.max(10, math.min(90, adjustedThreshold))

    -- Return true if we should interrupt based on threshold
    return castPercent >= adjustedThreshold, spellID
end

-- Helper to find the best target to interrupt within range
targets.getBestInterruptTarget = function(range)
    local bestTarget = nil
    local highestPriority = -1

    -- First check current target if it's valid
    if target:GetExists() and not target:IsDead() and target:GetAttackRange(player) <= range
        and targets.interruptable(target)
    then
        return target
    end

    -- Check if the spell ID is in the priority kicks list from the Constants table
    local spellPriority = function(spellID)
        -- if mint.Constants and mint.Constants.prio_kicks then
        --     for _, id in ipairs(mint.Constants.prio_kicks) do
        --         if id == spellID then
        --             return 100
        --         end
        --     end
        -- end
        return 0
    end

    -- Then check all enemies
    ObjectManager.enemies:loop(function(enemy)
        if enemy:IsDead() then return false end
        if enemy:GetAttackRange(player) > range then return false end
        if not enemy:HasLos(player) then return false end

        local interruptable, spellID = targets.interruptable(enemy)

        if interruptable then
            local priority = 100 - enemy:GetAttackRange(player)

            -- Prioritize enemies casting important spells
            priority = priority + spellPriority(spellID)

            if priority > highestPriority then
                highestPriority = priority
                bestTarget = enemy
            end
        end

        return false
    end)

    return bestTarget or none
end

-- Attempts to target the best unit based on the current situation
-- targets.dynamic = function(range)
--     -- Default range if not specified
--     local max_range = range or 5

--     -- Special handling for out of combat situations
--     if not player:IsInCombat() then
--         -- If not in combat and no target selected, return none
--         if not target:GetExists() or not targets.baseAttack(target) then
--             return none
--         end

--         -- If not in combat but have a target selected, return that target
--         -- regardless of other conditions (we're just targeting, not attacking yet)
--         return target
--     end

--     -- First check if current target is valid - this is very efficient
--     if targets.baseAttack(target) and target:GetAttackRange(player) <= max_range then
--         return target
--     end

--     -- If player is clearly running away, return none more often
--     if player:IsMoving()
--         and (not target:GetExists() or target:GetAttackRange(player) > max_range * 2)
--         and GetTime() % 2 < 1 -- Only try to find new targets every other second
--     then
--         return none
--     end

--     -- If current target isn't valid, find the best alternative
--     local best_unit = nil
--     local best_priority = -1

--     -- First try UnitManager.enemies (nameplated units that are already tracked)
--     -- This is much more efficient than scanning all objects
--     ObjectManager.enemies:loop(function(enemy)
--         if not targets.baseAttack(enemy) then return false end
--         if enemy:GetAttackRange(player) > max_range then return false end

--         local priority = targets.calculatePriority(enemy)

--         if priority > best_priority then
--             best_priority = priority
--             best_unit = enemy
--         end

--         return false
--     end)

--     -- Only if we didn't find any valid nameplated units, try the more expensive scan
--     if best_unit == nil then
--         -- Get all nearby enemies using the object manager
--         local nearby, count = feral.getNearbyEnemies(max_range)

--         -- Evaluate each nearby enemy
--         for i = 1, count do
--             local enemy = nearby[i]
--             if targets.baseAttack(enemy) then
--                 local priority = targets.calculatePriority(enemy)

--                 if priority > best_priority then
--                     best_priority = priority
--                     best_unit = enemy
--                 end
--             end
--         end
--     end

--     if best_unit == nil then
--         return none
--     end

--     -- If we found a new target, automatically target it
--     if player:IsInCombat() and (not target:GetExists() or not target:IsUnit(best_unit)) then
--         TargetUnit(best_unit:GetPointer())
--     end

--     return best_unit
-- end

-- targets.closest = UnitManager:CreateSmartUnit("auto_prowl_unit", function()
--     local closest_unit = nil
--     local least_dist = math.huge

--     ObjectManager.enemies:loop(function(enemy)
--         if enemy:IsDead() then return false end
--         if enemy:GetAttackRange(player) > 45 then return false end
--         if not enemy:HasLos(player) then return false end
--         if not enemy:IsEnemy() then return false end

--         local react = enemy:GetReaction()

--         local valid_react = (target:GetExists() and enemy:IsUnit(target) and react == 4)
--                             or react < 4
--                             or enemy:GetCastTarget():IsFriend() --UnitIsFriend(enemy:GetCastTarget(), player:GetPointer())

--         if not valid_react then return false end

--         local dist = enemy:GetAttackRange(player)

--         if dist < least_dist then
--             least_dist = dist
--             closest_unit = enemy
--         end
--     end)

--     if closest_unit == nil then
--         return none
--     end

--     return closest_unit
-- end)

-- Add to the targets section of your code
-- targets.lootable = UnitManager:CreateSmartUnit("feral_lootable", function()
--     local nearest_loot = nil
--     local min_distance = math.huge

--     -- Iterate through game objects to find lootable ones
--     mint.Objects("GameObject"):loop(function(object)
--         -- Skip if not lootable
--         if not mint.ObjectLootable(object) then return false end

--         -- Calculate distance
--         local dist = object.distance(player)
--         -- Only consider objects within interaction range
--         if dist <= 5 and dist < min_distance then
--             min_distance = dist
--             nearest_loot = object
--         end

--         return false
--     end)

--     if nearest_loot == nil then
--         return none
--     end

--     return nearest_loot
-- end)

targets.lowest_moonfire = UnitManager:CreateSmartUnit("feral_low_moonfire", function()
    local lowest_dur = math.huge
    local highest_hp = 0
    local lowest_unit = nil

    ObjectManager.combat:loop(function(enemy)
        if enemy:IsDead() then return false end
        if not spells.moonfire.inRange(enemy) then return false end
        if not enemy:HasLos() then return false end

        if enemy:FindDebuff(auras.moonfire, true):Remains() < lowest_dur then
            lowest_dur = enemy:FindDebuff(auras.moonfire, true):Remains()
            lowest_unit = enemy
        end
    end)

    if lowest_unit == nil then
        return none
    end

    return lowest_unit
end)

--#endregion

--#region feral

-- Timer utility (similar to br.timer:useTimer but simplified)
feral.debug.checkThrottle = function(msgId)
    local currentTime = GetTime()
    if not feral.debug.lastMsg[msgId] then
        feral.debug.lastMsg[msgId] = 0
    end

    if currentTime - feral.debug.lastMsg[msgId] >= feral.debug.throttle then
        feral.debug.lastMsg[msgId] = currentTime
        return true
    end
    return false
end

-- Main debug function
feral.debug.print = function(msg, msgId, noThrottle)
    -- Skip if disabled
    if not feral.debug.enabled then return end

    -- Generate a message ID if none provided
    msgId = msgId or tostring(msg):sub(1, 20)

    -- Check throttle unless explicitly bypassed
    if not noThrottle and not feral.debug.checkThrottle(msgId) then return end

    -- Format and print the message
    print(feral.debug.color .. feral.debug.prefix .. " |cffFFFFFF".. tostring(msg))
end

-- Shorthand for common debug scenarios
feral.debug.cast = function(spellObj, uniqueMsg, actionList)
    -- Skip if debugging is disabled
    if not feral.debug.enabled then return end

    -- Get the spell name - handle both string and spell object
    local spellName
    if type(spellObj) == "string" then
        spellName = spellObj
    else
        -- Try to get name from spell object
        spellName = spellObj.name or tostring(spellObj)
    end

    -- Build the message
    local msg = "Casting " .. spellName

    -- Add reason if provided
    if uniqueMsg and uniqueMsg ~= "" then
        msg = msg .. " - " .. uniqueMsg
    end

    -- Add callback type if provided
    if actionList then
        msg = msg .. " [" .. actionList .. "]"
    end

    -- Use the standard print function with throttling
    feral.debug.print(msg, "cast_" .. spellName)
end

-- Checks for free bag space
feral.hasBagSpace = function()
    local freeSlots = 0
    -- Check all regular bags (0-4 for backpack + 4 bags)
    for bag = 0, 4 do
        local free = C_Container.GetContainerNumFreeSlots(bag)
        freeSlots = freeSlots + free
    end
    return freeSlots > 0
end

---@param thisUnit Unit
feral.ferociousBiteExecute = function(thisUnit)
    local desc = C_Spell.GetSpellDescription(spells.ferociousBite.id)
    local damage
    local finishHim = false
    if player:GetPower(4) > 0 then
        local comboStart = desc:find(" " .. player:GetPower(4) .. " ", 1, true)
        if comboStart ~= nil then
            comboStart = comboStart + 2
            local damageList = desc:sub(comboStart, desc:len())
            comboStart = damageList:find(": ", 1, true) + 2
            damageList = damageList:sub(comboStart, desc:len())
            local comboEnd = damageList:find(" ", 1, true) - 1
            damageList = damageList:sub(1, comboEnd)
            damage = damageList:gsub(",", "")
        end
        finishHim = tonumber(damage) >= thisUnit:GetRealizedHealth()
    end
    return finishHim
end

feral.isShapeshifted = function()
    return player:FindBuff(auras.bearForm, true):Active()
        or player:FindBuff(auras.catForm, true):Active()
        or player:FindBuff(auras.moonkinForm, true):Active()
        or player:FindBuff(auras.travelForm, true):Active()
end

feral.isStealthed = function()
    return player:FindBuff(auras.prowl, true):Active()
        or player:FindBuff(auras.shadowmeld, true):Active()
end

-- Generic unit finder function that takes a filter function
feral.getNearbyUnits = function(range, filterFunc, firstOnly)
    local currentTime = GetTime()

    -- Otherwise do a fresh scan
    local nearby = {}
    local count = 0

    -- If player is running away from combat, use a more aggressive cooldown
    local isRunningAway = player:IsInCombat() and player:IsMoving() and
                         (not target:GetExists() or target:GetAttackRange(player) > range + 5)

    if isRunningAway then
        -- Return empty results more often when running away
        if currentTime - lastUnitScanTime < (unitScanCooldown * 3) then
            return nearby, count
        end
    end

    -- Get units using mint.Objects
    local units = mint.Objects("Unit")
    if not units then
        lastUnitScanTime = currentTime
        return nearby, count
    end

    -- Process in batches to reduce frame impact
    local batchSize = 10
    local processed = 0

    -- Standard table iteration
    for _, unit in pairs(units) do
        -- Skip processing this unit unless it's valid
        local process = true

        -- Skip if we can't get a pointer (quick check)
        if not unit then
            process = false
        end

        -- Apply the filter function first (can be more efficient than creating objects)
        if process and filterFunc then
            if not filterFunc(unit) then
                process = false
            end
        end

        -- Only proceed with more expensive operations if still valid
        if process then
            -- Get existing unit from UnitManager
            local unitObj = UnitManager:Get(unit)

            -- Create new unit object if needed
            if not unitObj then
                unitObj = Unit:Create(unit)
                -- Skip if object creation failed
                if not unitObj then
                    process = false
                end
            end

            -- Distance check and add to results
            if process and unitObj then
                local dist = unitObj:GetAttackRange(player)

                -- Add to results if in range
                if dist <= range then
                    count = count + 1
                    nearby[count] = unitObj

                    -- Early return optimization - if we only need one unit
                    if firstOnly then
                        lastUnitScanTime = currentTime
                        return nearby, count
                    end
                end
            end
        end

        -- Increment processed count
        processed = processed + 1

        -- If we've processed enough units in this frame, consider it done
        if isRunningAway and processed >= batchSize then
            break
        end
    end

    lastUnitScanTime = currentTime
    return nearby, count
end

-- Specialized function to get all nearby enemies using the generic function
-- feral.getNearbyEnemies = function(range)
--     -- Create a reusable filter function to avoid recreation
--     local enemyFilter = function(unit)
--         -- Quick initial check
--         if not unit then return false end

--         -- Use direct API calls which are faster
--         return unit:CanAttack("player") and not unit:IsDead()
--     end

--     return feral.getNearbyUnits(range, enemyFilter, false)
-- end

-- Specialized function for enemies that uses the generic function
feral.getFirstNearbyEnemy = function(range, additionalCheck)
    local filter
    filter = function(unit)
        return UnitCanAttack(unit,"player") and not UnitIsDeadOrGhost(unit) and (additionalCheck and additionalCheck(unit) or true)
    end

    local units, count = feral.getNearbyUnits(range, filter, true)
    if count > 0 then
        return units[1]
    end
    return nil
end

-- Get first lootable corpse
feral.getFirstNearbyLoot = function(range)
    local units, count = feral.getNearbyUnits(range, function(unit)
        return UnitIsDeadOrGhost(unit) and CanLootUnit(unit)
    end, true)

    if count > 0 then
        return units[1]
    end
    return nil
end

--#endregion

--#region Auto Attack
------------------------------
--- Auto Attack
------------------------------

---@param spell Spell
spells.autoAttack:AddCallback("precombat", function(spell)
    -- local attack_target = targets.dynamic(5)
    if C_Spell.IsAutoRepeatSpell(spell.id)
        or C_Spell.IsCurrentSpell(spell.id)
        or player:IsInCombat()
        or target == none
        or not targets.baseAttack(target)
        or feral.isStealthed()
    then return end

    if spell:Cast(target) then
        feral.debug.cast(spell, "", "Precombat")
        return true
    end
end)

---@param spell Spell
spells.autoAttack:AddCallback(function(spell)
    -- local attack_target = targets.dynamic(5)
    if C_Spell.IsAutoRepeatSpell(spell.id)
        or C_Spell.IsCurrentSpell(spell.id)
        or not player:IsInCombat()
        or target == none
        or not targets.baseAttack(target)
        or feral.isStealthed()
    then return end

    if spell:Cast(target) then
        feral.debug.cast(spell, "", "Combat")
        return true
    end
end)

--#endregion

--#region Auto Loot

------------------------------
--- Auto Loot
------------------------------

local lastLootAttempt = 0
local LOOT_COOLDOWN = 1.0  -- 1 second delay between loot attempts
local lastScanTime = 0
local SCAN_COOLDOWN = 2.5  -- Only scan every 2.5 seconds when idle
local recentCombat = false  -- Track if we recently left combat
local combatExitTime = 0    -- When we exited combat

-- For position tracking
local lastX, lastY, lastZ = 0, 0, 0
local MIN_MOVE_DISTANCE_SQUARED = 25 -- 5 yards squared, avoid sqrt calculation

-- Then modify your autoLoot callback:
---@param spell Spell
spells.autoLoot:AddCallback(function(spell)
    -- Skip if in combat or mounted or flying
    if player:IsInCombat() or player:IsMounted() or player:IsFlying() then
        -- Note when we enter combat for post-combat looting
        if player:IsInCombat() then
            recentCombat = true
        end
        return
    end

    -- Check if loot window is already open - this is quick and worth checking every frame
    if GetNumLootItems and GetNumLootItems() > 0 then
        isCurrentlyLooting = true
        -- Manually loot all items if auto-loot disabled
        if GetCVar("autoLootDefault") == "0" then
            local lootable = true
            -- Loop through each loot slot and loot it
            for i = 1, GetNumLootItems() do
                -- Skip if slot is already looted or empty
                if not LootSlotHasItem(i) then
                    lootable = false
                end

                -- Loot this slot
                if lootable then
                    LootSlot(i)
                end
            end

            -- Close loot window when done
            CloseLoot()
        end
        return true
    end

    -- Skip if no bag space
    if not feral.hasBagSpace() then return end

    -- Check if we're still on cooldown from previous loot attempt
    local currentTime = GetTime()
    if currentTime - lastLootAttempt < LOOT_COOLDOWN then
        return false
    end

    -- Track combat exit - this is when we're most likely to need to loot
    if recentCombat and not player:IsInCombat() then
        recentCombat = false
        combatExitTime = currentTime
    end

    -- Get current position directly - avoid creating tables
    local playerPos = player:GetPosition()
    local x, y, z = playerPos.x, playerPos.y, playerPos.z

    -- Calculate distance moved squared (avoid sqrt for performance)
    local distSquared = 0
    if x and lastX then
        distSquared = (x - lastX)^2 + (y - lastY)^2 + (z - lastZ)^2
    end

    -- Determine if we should scan based on conditions:
    -- 1. Recently exited combat (within 5 seconds)
    -- 2. Moved sufficient distance since last scan
    -- 3. Enough time has passed since last scan
    local shouldScan =
        (currentTime - combatExitTime < 5) or  -- Recently exited combat
        (distSquared > MIN_MOVE_DISTANCE_SQUARED) or     -- Moved enough
        (currentTime - lastScanTime > SCAN_COOLDOWN)  -- Scan cooldown expired

    if not shouldScan then
        return false
    end

    -- Update scan tracking
    lastScanTime = currentTime
    lastX, lastY, lastZ = x, y, z

    -- Get first lootable corpse in range
    local corpse = feral.getFirstNearbyLoot(7)

    -- If found a corpse, loot it
    if corpse then
        -- Set looting flag immediately before attempting to loot
        isCurrentlyLooting = true

        -- Store the corpse GUID to prevent it from triggering prowl
        -- recentlyLootedGUID = corpse:GetPointer()
        -- recentlyLootedTime = currentTime

        -- Update the last loot attempt time
        lastLootAttempt = currentTime

        -- Interact with the unit
        C_PlayerInteractionManager.InteractUnit(corpse:GetPointer())

        -- Reset looting flag after a very short delay (next frame)
        C_Timer.After(0.5, function() isCurrentlyLooting = false end)
        return true
    end

    -- If we got here, we're definitely not looting
    isCurrentlyLooting = false
    return false
end)

--#endregion

--#region Barkskin

------------------------------
--- Barkskin
------------------------------

---@param spell Spell
spells.barkskin:AddCallback(function(spell)
    if not player:IsInCombat()
        or spell:IsOnCD()
        or player:FindBuff(auras.barkskin, true):Active()
        or player:GetRealizedHP() > 50
    then return end

    if spell:Cast(player) then
        feral.debug.cast(spell, "", "Defensive")
        return true
    end
end)

--#endregion

--#region Berserk

------------------------------
--- Berserk
------------------------------

---@param spell Spell
spells.berserk:AddCallback(function(spell)
    if not player:IsInCombat()
        or spell:IsOnCD()
        or player:FindBuff(auras.berserk, true):Active()
        or not player:FindBuff(auras.catForm, true):Active()
        or not targets.baseAttack()
    then return end

    -- Use on boss fights
    if target:IsBoss() then
        if spell:Cast(player) then
            feral.debug.cast(spell, "", "Cooldown")
            return true
        end
    end

    return false
end)

--#endregion

--#region Brutal Slash

------------------------------
--- Brutal Slash
------------------------------

---@param spell Spell
spells.brutalSlash:AddCallback(function(spell)
    if not player:IsInCombat()
        or not targets.baseAttack(target)
        or not player:FindBuff(auras.catForm, true):Active()
        or feral.isStealthed()
        or spell:IsOnCD()
        or target:GetAttackRange(player) >= 8
        or spells.swipe:IsKnown()
        or player:GetPower(4) >= 5
        or player:GetPower() < 25
        or spell:GetCharges() == 0
    then return end

    -- High priority usage cases
    if player:GetPower(4) <= 3 and player:GetEnemies(8) >= 2 then
        if spell:Cast(target) then
            feral.debug.cast(spell, "AoE", "Combat")
            return true
        end
    end

    -- Maintain charge efficiency - don't cap charges
    if spell:GetChargesFractional() >= 2.8 then
        if spell:Cast(target) then
            feral.debug.cast(spell, "Max Charges Soon", "Combat")
            return true
        end
    end

    return false
end)

--#endregion

--#region Cat Form

------------------------------
--- Cat Form
------------------------------

local movementStartTime = 0
local isMovingTracked = false
local MOVEMENT_THRESHOLD = 1.0

---@param spell Spell
spells.catForm:AddCallback("moving", function(spell)
    -- Get current time once for this frame
    local currentTime = GetTime()

    -- Track movement state changes
    if player:IsMoving() and not isMovingTracked then
        -- Player just started moving
        movementStartTime = currentTime
        isMovingTracked = true
    elseif not player:IsMoving() and isMovingTracked then
        -- Player just stopped moving
        isMovingTracked = false
    end

    if player:GetLevel() < 5
        or player:FindBuff(auras.catForm, true):Active()
        or player:IsMounted()
        or player:IsFlying()
        or not player:IsMoving()
        or player:IsSwimming()
        or player:FindBuff(auras.travelForm, true):Active()
        or IsFalling()
    then return end

    -- Only cast if we've been moving for longer than the threshold
    local movementDuration = currentTime - movementStartTime
    if movementDuration < MOVEMENT_THRESHOLD then
        return false
    end

    if spell:Cast(player) then
        feral.debug.cast(spell, "Moving", "Extra")
        return true
    end
end)

---@param spell Spell
spells.catForm:AddCallback("target_near", function(spell)
    if player:GetLevel() < 5
        or player:FindBuff(auras.catForm, true):Active()
        or player:IsMounted()
        or player:IsFlying()
        or player:IsInCombat()
        or not target:GetExists()
        or not player:CanAttack(target)
    then return end

    -- Check distance conditions
    local inRange = false
    if not player:IsSwimming() and target:GetAttackRange(player) < 30 then
        inRange = true
    elseif player:IsSwimming() and target:GetAttackRange(player) < 10 then
        inRange = true
    end

    if not inRange then return end

    if spell:Cast(player) then
        feral.debug.cast(spell, "Target Near", "Extra")
        return true
    end
end)

spells.catForm:AddCallback("combat", function(spell)
    if player:GetLevel() < 5
        or player:FindBuff(auras.catForm, true):Active()
        or player:IsMounted()
        or player:IsFlying()
        or not player:IsInCombat()
    then return end

    -- Only shift if we have enemies in melee range and we're not in another useful form
    if player:FindBuff(auras.moonkinForm, true):Active()
        or player:FindBuff(auras.bearForm, true):Active()
    then
        return feral.switchToForm(spells.catForm)
    end

    -- Cast cat form directly if not in any form
    if spell:Cast(player) then
        feral.debug.cast(spell, "", "Combat")
        return true
    end
end)

local fallStartTime = 0
local isFalling = false

---@param spell Spell
spells.catForm:AddCallback("fall_protection", function(spell)
    if player:GetLevel() < 5
        or player:FindBuff(auras.catForm, true):Active()
        or player:IsMounted()
        or player:IsFlying()
        or player:IsSwimming()
        or player:FindBuff(auras.travelForm, true):Active()
        or not IsFalling() -- Skip if not falling - early fail case
        or not IsAdvancedFlyableArea()
    then
        -- Reset falling state when player stops falling
        if isFalling and not IsFalling() then
            isFalling = false
        end
    return end

    -- Track falling status
    local currentTime = GetTime()

    -- Started falling
    if not isFalling then
        fallStartTime = currentTime
        isFalling = true
    end

    -- Calculate fall duration
    local fallDuration = currentTime - fallStartTime
    -- If falling for more than 1 second, shift to cat form to reduce damage
    if fallDuration > 1.0 then
        if spell:Cast(player) then
            feral.debug.cast(spell, "Falling", "Extra")
            return true
        end
    end

    return false
end)

---@param spell Spell
spells.catForm:AddCallback("break_cc", function(spell)
    -- Skip if spell is on cooldown
    if spell:IsOnCD() then return end

    -- Check for specific CC types that shifting can break (mainly roots and snares)
    local hasBreakableCC = false

    -- Use modern API to check for roots and snares
    local function CheckAuraType(unit, auraType)
        local slots = C_UnitAuras.GetAuraSlots(unit, "HARMFUL")
        if not slots then return false end

        for i = 1, #slots do
            local auraData = C_UnitAuras.GetAuraDataBySlot(unit, slots[i])
            if auraData and auraData.dispelName == auraType then
                return true
            end
        end
        return false
    end

    -- Check for root or snare effects specifically
    if CheckAuraType("player", "ROOT") or CheckAuraType("player", "SLOW") then
        hasBreakableCC = true
    end

    -- If we have a breakable CC effect, try to shift to break it
    if hasBreakableCC then
        -- If not in form, shift to cat
        if not feral.isShapeshifted() then
            if spell:Cast(player) then
                feral.debug.cast(spell, "Break CC", "Defensive")
                return true
            end
        else
            -- If in form, shift out then in again (powershift)
            CancelShapeshiftForm()
            C_Timer.After(0.1, function()
                if not player:FindBuff(auras.catForm, true):Active() then
                    if spells.catForm:Cast(player) then
                        feral.debug.cast(spell, "Break CC", "Defensive")
                    end
                end
            end)
            return true
        end
    end

    return false
end)

--#endregion

--#region Convoke the Spirits

------------------------------
--- Convoke the Spirits
------------------------------

---@param spell Spell
spells.convokeTheSpirits:AddCallback(function(spell)
    if not player:IsInCombat()
        or spell:IsOnCD()
        or player:FindBuff(auras.convokeTheSpirits, true):Active()
        or not player:FindBuff(auras.catForm, true):Active()
        or not targets.baseAttack()
    then return end

    -- Use on boss fights
    if target:IsBoss() then
        if spell:Cast(player) then
            feral.debug.cast(spell, "", "Cooldown")
            return true
        end
    end

    return false
end)

--#endregion

--#region Feral Frenzy

------------------------------
--- Feral Frenzy
------------------------------

---@param spell Spell
spells.feralFrenzy:AddCallback(function(spell)
    -- local frenzy_target = targets.dynamic(8) -- 8 yard range
    if not player:IsInCombat()
        or target == none
        or not targets.baseAttack(target)
        or not player:FindBuff(auras.catForm, true):Active()
        or feral.isStealthed()
        or spell:IsOnCD()
    then return end

    -- Use on bosses/priority targets
    if target:IsBoss() then
        if spell:Cast(target) then
            feral.debug.cast(spell, "Boss Target", "Combat")
            return true
        end
    end

    -- Use when we're low on combo points and need to build quickly
    if player:GetPower(4) <= 1 and target:GetRealizedHP() > 20 then
        if spell:Cast(target) then
            feral.debug.cast(spell, "Low Combo Points", "Combat")
            return true
        end
    end

    -- Use on cooldown for sustained damage on higher health targets
    if target:GetRealizedHP() > 20 and player:GetPP() >= 25 then
        if spell:Cast(target) then
            feral.debug.cast(spell, "", "Combat")
            return true
        end
    end

    return false
end)

--#endregion

--#region Ferocious Bite

------------------------------
--- Ferocious Bite
------------------------------

---@param spell Spell
spells.ferociousBite:AddCallback(function(spell)
    -- local bite_target = targets.dynamic(5)
    if not player:IsInCombat()
        or not player:FindBuff(auras.catForm, true):Active()
        or target == none
        or not targets.baseAttack(target)
        or feral.isStealthed()
        or player:GetPower(4) < 5
        or player:GetPower() < 50
        or spell:IsOnCD()
    then return end

    if spell:Cast(target) then
        feral.debug.cast(spell, "", "Combat")
        return true
    end
end)

---@param spell Spell
spells.ferociousBite:AddCallback("execute", function(spell)
    -- local bite_target = targets.dynamic(5)
    if not player:IsInCombat()
        or target == none
        or not targets.baseAttack(target)
        or not player:FindBuff(auras.catForm, true):Active()
        or feral.isStealthed()
        or player:GetPower(4) == 0
        or spell:IsOnCD()
        or not feral.ferociousBiteExecute(target)
    then return end

    if spell:Cast(target) then
        feral.debug.cast(spell, "Execute", "Combat")
        return true
    end
end)

--#endregion

--#region Mark of the Wild

------------------------------
--- Mark of the Wild
------------------------------

---@param spell Spell
spells.markOfTheWild:AddCallback(function(spell)
    if not player:FindBuff(auras.markOfTheWild, true):Refresh()
        or player:FindBuff(auras.travelForm, true):Active()
    then return end

    if spell:Cast(player) then
        feral.debug.cast(spell, "", "Extra")
        return true
    end
end)

--#endregion

--#region Moonfire

------------------------------
--- Moonfire
------------------------------

---@param spell Spell
spells.moonfire:AddCallback(function(spell)
    -- local moonfire_target = targets.dynamic(40)
    if not player:IsInCombat()
        or target == none
        or not targets.baseAttack(target)
        or player:FindBuff(auras.catForm, true):Active()
        or player:FindBuff(auras.bearForm, true):Active()
        or player:FindBuff(auras.travelForm, true):Active()
        or not target:FindDebuff(auras.moonfire, true):Refresh()
    then return end

    if spell:Cast(target) then
        feral.debug.cast(spell, "", "Combat")
        return true
    end
end)

--#endregion

--#region Primal Wrath

------------------------------
--- Primal Wrath
------------------------------

---@param spell Spell
spells.primalWrath:AddCallback(function(spell)
    if not player:IsInCombat()
        or not targets.baseAttack(target)
        or not player:FindBuff(auras.catForm, true):Active()
        or feral.isStealthed()
        or player:GetPower(4) < 5
        or player:GetEnemies(8) <= 1
    then return end

    if spell:Cast(target) then
        feral.debug.cast(spell, "", "Combat")
        return true
    end
end)

--#endregion

--#region Prowl

------------------------------
--- Prowl
------------------------------

---@param spell Spell
spells.prowl:AddCallback(function(spell)
    if player:IsInCombat()
        or spell:IsOnCD()
        or player:FindBuff(auras.prowl, true):Active()
        or player:FindBuff(auras.shadowmeld, true):Active()
        or player:FindBuff(auras.berserk, true):Active()
        -- or player:FindBuff(auras.incranation, true):Active()
    then return end

    if spell:Cast(player) then
        feral.debug.cast(spell, "", "Combat")
        return true
    end
end)

local lastProwlScanTime = 0
local PROWL_SCAN_INTERVAL = 0.5

---@param spell Spell
spells.prowl:AddCallback("auto_prowl", function(spell)
    if player:IsInCombat()
        or spell:IsOnCD()
        -- or not targets.closest:GetExists()
        -- or targets.closest.distance(player) > (targets.closest:GetAggroRange() + 1.5)
        or player:FindBuff(auras.prowl, true):Active()
        or player:FindBuff(auras.shadowmeld, true):Active()
        or player:FindBuff(auras.berserk, true):Active()
        -- or player:FindBuff(auras.incranation, true):Active()
        -- or player.resting
        or isCurrentlyLooting  -- Don't prowl if currently looting
    then return false end

    -- Add throttling - only run expensive scans periodically
    local currentTime = GetTime()
    if currentTime - lastProwlScanTime < PROWL_SCAN_INTERVAL then
        return false
    end

    -- Update scan time
    lastProwlScanTime = currentTime

    -- Check for lootable corpses nearby
    local nearbyCorpse = feral.getFirstNearbyLoot(7)
    if nearbyCorpse then
        -- Don't prowl if there's a lootable corpse nearby
        return false
    end

    -- Special handling for when we have a target already selected
    if target:GetExists() and not target:IsDead()
        and player:CanAttack(target) and target:GetReaction() < 4
    then
        -- Use a larger buffer for selected targets to prowl early
        local safeDistance = (target:GetAggroRange() or 20)

        if target:GetAttackRange(player) <= safeDistance then
            if spell:Cast(player) then
                feral.debug.cast(spell, "Selected Target Near", "Precombat")
                return true
            end
        end
    end

    -- Only prowl if there's an actual hostile mob in aggro range
    local enemy = feral.getFirstNearbyEnemy(40, function(unit)
        local thisUnit = UnitManager:Get(unit)
        if not thisUnit then thisUnit = Unit:Create(unit) end

        -- Skip if not hostile
        if not thisUnit:IsEnemy() then return false end

        -- Skip if this is the unit we just looted
        -- if recentlyLootedGUID and thisUnit:GetPointer() == recentlyLootedGUID
        --     and (GetTime() - recentlyLootedTime) < LOOTED_IGNORE_TIME
        -- then
        --     return false
        -- end

        -- Skip if not hostile (reaction >= 4 means neutral or friendly)
        if thisUnit:GetReaction() >= 4 then return false end

        local aggro_range = thisUnit and thisUnit:GetAggroRange() or 20
        return thisUnit:GetAttackRange(player) <= (aggro_range + 1.5)
    end)

    -- Cast prowl if we found an enemy
    if enemy then
        if spell:Cast(player) then
            feral.debug.cast(spell, "Found Enemy Near", "Precombat")
            return true
        end
    end

    -- Don't prowl if there's no reason to
    return false
end)

--#endregion

--#region Rake

------------------------------
--- Rake
------------------------------

---@param spell Spell
spells.rake:AddCallback("precombat", function(spell)
    -- local rake_target = targets.dynamic(5)
    if player:IsInCombat()
        or target == none
        or not targets.baseAttack(target)
        or spell:IsOnCD()
        or not player:FindBuff(auras.catForm, true):Active()
        or (player:GetLevel() >= 12 and not feral.isStealthed())
    then return end

    if spell:Cast(target) then
        feral.debug.cast(spell, "", "Precombat")
        return true
    end
end)

---@param spell Spell
spells.rake:AddCallback("stealth", function(spell)
    -- local rake_target = targets.dynamic(5)
    if not player:IsInCombat()
        or target == none
        or not targets.baseAttack(target)
        or spell:IsOnCD()
        or not player:FindBuff(auras.catForm, true):Active()
        or not feral.isStealthed()
    then return end

    if spell:Cast(target) then
        feral.debug.cast(spell, "Stealth", "Combat")
        return true
    end
end)

spells.rake:AddCallback(function(spell)
    -- local rake_target = targets.dynamic(5)
    if not player:IsInCombat()
        or target == none
        or not targets.baseAttack(target)
        or spell:IsOnCD()
        or not player:FindBuff(auras.catForm, true):Active()
        or feral.isStealthed()
        or player:GetPower(4) >= 5
        or not target:FindDebuff(auras.rake, true):Refresh()
    then return end

    if spell:Cast(target) then
        feral.debug.cast(spell, "", "Combat")
        return true
    end
end)

--#endregion

--#region Regrowth

------------------------------
--- Regrowth
------------------------------

-- Default threshold values - adjust these as needed
local regrowthHealthThreshold = 40 -- In combat threshold
local regrowthOocHealthThreshold = 80 -- Out of combat threshold
local healOthers = true -- Set to false if you only want to heal yourself

---@param spell Spell
spells.regrowth:AddCallback(function(spell)
    -- Check for throttling using our timer utility (0.75 sec cooldown)
    if not feral.debug.checkThrottle("regrowth") then return false end

    -- Special handling for Predatory Swiftness
    local hasPredatorySwiftness = player:FindBuff(auras.predatorySwiftness, true):Active()

    -- If we have Predatory Swiftness, check if it's about to expire
    local buffIsExpiring = false
    if hasPredatorySwiftness then
        local buffTimeRemaining = player:FindBuff(auras.predatorySwiftness, true):Remains()
        local twoGCDs = mint.max_gcd * 2
        buffIsExpiring = buffTimeRemaining <= twoGCDs
    end

    -- Find lowest health friendly target (but only if we have Predatory Swiftness)
    local healTarget = player
    local lowestHealth = player:GetRealizedHP()
    local healRange = 40 -- Regrowth has a 40 yard range

    -- Only search for group members if we have an instant cast available
    if healOthers and hasPredatorySwiftness and (IsInGroup() or IsInRaid()) then
        -- Try using UnitManager.friends if available
        if ObjectManager.units then

            ---@param friend Unit
            ObjectManager.units:loop(function(friend)
                if not friend:IsFriend() then return false end
                if friend:IsDead() then return false end
                if friend:GetPlayerDistance() > healRange then return false end

                -- If this unit has lower health than our current lowest
                if friend:GetRealizedHP() < lowestHealth then
                    lowestHealth = friend:GetRealizedHP()
                    healTarget = friend
                end

                return false
            end)
        -- else
        --     -- Fallback to direct party/raid iteration
        --     local memberCount = IsInRaid() and GetNumGroupMembers() or GetNumSubgroupMembers()

        --     for i = 1, memberCount do
        --         local unit = IsInRaid() and ("raid"..i) or ("party"..i)

        --         if UnitExists(unit) and not unit:IsDead() then
        --             local hp = UnitHealth(unit) / UnitHealthMax(unit) * 100
        --             if hp < lowestHealth then
        --                 lowestHealth = hp
        --                 -- Try to get the unit through UnitManager if possible
        --                 local unitObj = UnitManager:Get(unit) or unit
        --                 healTarget = unitObj
        --             end
        --         end
        --     end
        end
    end

    -- Determine threshold based on combat state
    local hpThreshold = player:IsInCombat() and regrowthHealthThreshold or regrowthOocHealthThreshold

    -- Skip if health is high enough, and either:
    -- 1. We're out of combat (ignore expiring buff when out of combat)
    -- 2. OR we're in combat but buff isn't expiring
    if lowestHealth > hpThreshold and (not player:IsInCombat() or (player:IsInCombat() and not buffIsExpiring)) then
        return false
    end

    -- Skip if moving and don't have instant cast from Predatory Swiftness
    if player:IsMoving() and not hasPredatorySwiftness then return false end

    -- Handle form management more intelligently
    if feral.isShapeshifted() then
        -- If we have Predatory Swiftness, we can cast without leaving form
        if hasPredatorySwiftness then
            if spell:Cast(healTarget) then
                feral.debug.cast(spell, "On (Instant): " .. healTarget.name, "Defensive")
                return true
            end
        else
            -- Otherwise, cancel form to cast only if healing self
            -- (we don't want to leave form to hardcast on others)
            if healTarget == player and (not player:IsInCombat() or player:GetRealizedHP() < regrowthHealthThreshold) then
                CancelShapeshiftForm()
                if spell:Cast(healTarget) then
                    feral.debug.cast(spell, "On (Break Form): " .. healTarget.name, "Defensive")
                    return true
                end
            else
                -- In combat with health > critical threshold, stay in form
                return false
            end
        end
    end

    -- Cast if we're not shapeshifted
    if spell:Cast(healTarget) then
        feral.debug.cast(spell, "On: " .. healTarget.name, "Defensive")
        return true
    end
end)

-- Optional: Add a callback specifically for Bloodtalons support
-- Uncomment if you have the Bloodtalons talent
-- spells.regrowth:AddCallback("bloodtalons", function(spell)
--     local hasPredatorySwiftness = player:FindBuff(auras.predatorySwiftness, true):Active()
--     local hasBloodtalons = player:FindBuff(auras.bloodtalons, true):Active()
--
--     -- If we have Predatory Swiftness but not Bloodtalons
--     if hasPredatorySwiftness and not hasBloodtalons and player:IsInCombat() then
--         -- Cast Regrowth to proc Bloodtalons
--         return spell:Cast(player)
--     end
-- end)

--#endregion

--#region Rejuvenation

------------------------------
--- Rejuvenation
------------------------------

---@param spell Spell
spells.rejuvenation:AddCallback(function(spell)
    if player:GetRealizedHP() > 80
        or feral.isShapeshifted()
        or player:FindBuff(auras.rejuvenation, true):Active()
    then return end

    if spell:Cast(player) then
        feral.debug.cast(spell, "", "Defensive")
        return true
    end
end)

--#endregion

--#region Remove Corruption

------------------------------
--- Remove Corruption
------------------------------

-- ---@param spell Spell
-- spells.removeCorruption:AddCallback(function(spell)
--     if not spell:CanDispelType("poison")--player.dispelable(spell)
--         or spell:IsOnCD()
--     then return end

--     if spell:Cast(player) then
--         feral.debug.cast(spell, "", "Defensive")
--         return true
--     end
-- end)

--#endregion

--#region Renewal

------------------------------
--- Renewal
------------------------------

---@param spell Spell
spells.renewal:AddCallback(function(spell)
    -- Skip if not in combat
    if not player:IsInCombat() then return end

    -- Skip if spell is on cooldown
    if spell:IsOnCD() then return end

    -- Different health thresholds based on combat status
    local healthThreshold = 25

    -- Use if health is below the threshold
    if player:GetRealizedHP() > healthThreshold then return end

    -- Use the spell
    if spell:Cast(player) then
        feral.debug.cast(spell, "", "Defensive")
        return true
    end
end)

--#endregion

--#region Rip

------------------------------
--- Rip
------------------------------

---@param spell Spell
spells.rip:AddCallback(function(spell)
    -- local rip_target = targets.dynamic(5)
    if not player:IsInCombat()
        or target == none
        or not targets.baseAttack(target)
        or not player:FindBuff(auras.catForm, true):Active()
        or feral.isStealthed()
        or player:GetPower(4) < 5
        or not target:FindDebuff(auras.rip, true):Refresh()
        or (not target:IsBoss() and target:GetMaxHealth() <= (player:GetMaxHealth() * 5))
    then return end

    if spell:Cast(target) then
        feral.debug.cast(spell, "", "Combat")
        return true
    end
end)

--#endregion

--#region Shadowmeld

------------------------------
--- Shadowmeld
------------------------------

---@param spell Spell
spells.shadowmeld:AddCallback(function(spell)
    if not player:GetRace() == "NightElf"
        or player:FindBuff(auras.shadowmeld, true):Active()
        or spell:IsOnCD()
    then return end

    if spell:Cast(player) then
        feral.debug.cast(spell, "", "Defensive")
        return true
    end
end)

--#endregion

--#region Skull Bash

------------------------------
--- Skull Bash
------------------------------

---@param spell Spell
spells.skullBash:AddCallback(function(spell)
    -- Skip if not in combat
    if not player:IsInCombat() then return end

    -- Skip if on cooldown
    if spell:IsOnCD() then return end

    -- Skip if not in cat form (Skull Bash is available in cat or bear form)
    if not player:FindBuff(auras.catForm, true):Active()
        and not player:FindBuff(auras.bearForm, true):Active()
    then return end

    -- Get the best target to interrupt within 13 yards
    -- Note: Skull Bash has 13 yard range but only works in front of the player
    local interruptTarget = targets.getBestInterruptTarget(13)

    -- Cast if we found a valid target
    if interruptTarget and interruptTarget:GetExists() then
        if spell:Cast(interruptTarget) then
            feral.debug.cast(spell, "On: " .. interruptTarget.name, "Interrupt")
            return true
        end
    end

    return false
end)

--#endregion

--#region Shred

------------------------------
--- Shred
------------------------------

---@param spell Spell
spells.shred:AddCallback("precombat", function(spell)
    -- local shred_target = targets.dynamic(5)
    if player:IsInCombat()
        or target == none
        or not targets.baseAttack(target)
        or feral.isStealthed()
        or player:GetPower() < 40
        or spell:IsOnCD()
        or target:GetAttackRange(player) >= 5
    then return end

    if spell:Cast(target) then
        feral.debug.cast(spell, "", "Precombat")
        return true
    end
end)

spells.shred:AddCallback(function(spell)
    -- local shred_target = targets.dynamic(5)
    if not player:IsInCombat()
        or target == none
        or not targets.baseAttack(target)
        or not player:FindBuff(auras.catForm, true):Active()
        or feral.isStealthed()
        or (player:GetPower(4) >= 5 and player:GetLevel() >= 7)
        or (player:GetEnemies(8) > 1 and spells.swipe:IsKnown())
        or player:GetPower() < 40
        or spell:IsOnCD()
        or target:GetAttackRange(player) >= 5
    then return end

    if spell:Cast(target) then
        feral.debug.cast(spell, "", "Combat")
        return true
    end
end)

--#endregion

--#region Survival Instincts

------------------------------
--- Survival Instincts
------------------------------

---@param spell Spell
spells.survivalInstincts:AddCallback(function(spell)
    if not player:IsInCombat()
        or spell:IsOnCD()
        or player:FindBuff(auras.survivalInstincts, true):Active()
        or player:GetRealizedHP() > 40
    then return end

    if spell:Cast(player) then
        feral.debug.cast(spell, "", "Defensive")
        return true
    end
end)

--#endregion

--#region Swipe

------------------------------
--- Swipe
------------------------------

---@param spell Spell
spells.swipe:AddCallback(function(spell)
    if not player:IsInCombat()
        or not targets.baseAttack(target)
        or not player:FindBuff(auras.catForm, true):Active()
        or feral.isStealthed()
        or player:GetPower(4) >= 5
        or target:GetAttackRange(player) >= 5
        or player:GetEnemies(8) <= 1
        or spells.brutalSlash:IsKnown()
    then return end

    if spell:Cast(target) then
        feral.debug.cast(spell, "", "Combat")
        return true
    end
end)

--#endregion

--#region Thrash

------------------------------
--- Thrash
------------------------------

---@param spell Spell
spells.thrash:AddCallback(function(spell)
    if not player:IsInCombat()
        or not targets.baseAttack(target)
        or not player:FindBuff(auras.catForm, true):Active()
        or feral.isStealthed()
        or not target:FindDebuff(auras.thrash, true):Refresh()
        or player:GetEnemies(8) <= 1
    then return end

    if spell:Cast(target) then
        feral.debug.cast(spell, "", "Combat")
        return true
    end
end)

--#endregion

--#region Tigers Fury

------------------------------
--- Tiger's Fury
------------------------------

---@param spell Spell
spells.tigersFury:AddCallback(function(spell)
    if not player:IsInCombat()
        or spell:IsOnCD()
        or not targets.baseAttack()
        or not player:FindBuff(auras.catForm, true):Active()
        or target:GetAttackRange(player) >= 8
        or player:GetPP() >= 50
    then return end

    if spell:Cast(player) then
        feral.debug.cast(spell, "", "Combat")
        return true
    end
end)

--#endregion

--#region Travel Form

------------------------------
--- Travel Form
------------------------------

---@param spell Spell
spells.travelForm:AddCallback("swimming", function(spell)
    if player:GetLevel() < 16
        or player:FindBuff(auras.travelForm, true):Active()
        or not player:IsSwimming()
        or player:FindBuff(auras.prowl, true):Active()
        or player:IsInCombat()
    then return end

    if feral.isShapeshifted() then CancelShapeshiftForm() end
    if spell:Cast(player) then
        feral.debug.cast(spell, "Swimming", "Extra")
        return true
    end
end)

---@param spell Spell
spells.travelForm:AddCallback(function(spell)
    if player:FindBuff(auras.travelForm, true):Active()
    then return end

    if spell:Cast(player) then
        feral.debug.cast(spell, "", "Extra")
        return true
    end
end)

--#endregion

--#region Wrath

------------------------------
--- Wrath
------------------------------

---@param spell Spell
spells.wrath:AddCallback("precombat", function(spell)
    -- local wrath_target = targets.dynamic(40)
    if player:IsInCombat()
        or target == none
        or not targets.baseAttack(target)
        or player:IsMoving()
        or player:FindBuff(auras.catForm, true):Active()
        or player:FindBuff(auras.bearForm, true):Active()
        or player:FindBuff(auras.travelForm, true):Active()
    then return end

    if spell:Cast(target) then
        feral.debug.cast(spell, "", "Precombat")
        return true
    end
end)

---@param spell Spell
spells.wrath:AddCallback(function(spell)
    -- local wrath_target = targets.dynamic(40)
    if not player:IsInCombat()
        or target == none
        or not targets.baseAttack(target)
        or player:IsMoving()
        or player:FindBuff(auras.catForm, true):Active()
        or player:FindBuff(auras.bearForm, true):Active()
        or player:FindBuff(auras.travelForm, true):Active()
        or (player:GetLevel() >= 2
            and spells.wrath:WasLastCast()
            and spells.wrath:TimeSinceLastCast() <= mint.max_gcd + 0.5
            and target:FindDebuff(auras.moonfire, true):Refresh())
    then return end

    if spell:Cast(target) then
        feral.debug.cast(spell, "", "Combat")
        return true
    end
end)

--#endregion

addon.spells = spells
addon.auras = auras