local unlocker, ---@class mint
mint, addon = ...

local UnitManager   = mint.UnitManager
local ObjectManager = mint.ObjectManager
local target        = UnitManager:Get("target")
local player        = UnitManager:Get("player")

-- IDs for Shared Buffs
local HOVER_BUFF = 358267
local BURNOUT_BUFF = 375801

local evoker_data   = addon.evoker.data["devastation"]
local spells        = evoker_data.spells
local actor         = addon.evoker.devastation

-- Throttles to prevent spam on Winkr
actor.lastCastTime = actor.lastCastTime or 0
actor.last_dead_time = actor.last_dead_time or 0

local bronze_auras = {381732, 381741, 381746, 381748, 381749, 381750, 381751, 381752, 381753, 381754, 381756, 381757, 381758, 1271912}
local function HasBronze(unit)
    for i = 1, #bronze_auras do
        if unit:FindBuffByID(bronze_auras[i]):Active() then return true end
    end
    return false
end

-- DisintegrateTicks Exact Replication Event Bridge
if not actor.dt_bridge then
    actor.dt_bridge = CreateFrame("Frame")
    actor.dt_bridge:RegisterEvent("UNIT_SPELLCAST_SUCCEEDED")
    actor.dt_bridge:RegisterEvent("UNIT_SPELLCAST_EMPOWER_STOP")
    actor.dt_bridge:RegisterEvent("UNIT_SPELLCAST_CHANNEL_START")
    actor.dt_bridge:RegisterEvent("UNIT_SPELLCAST_CHANNEL_UPDATE")
    actor.dt_bridge:RegisterEvent("UNIT_SPELLCAST_CHANNEL_STOP")
    
    actor.massStacks = 0
    actor.isCurrentlyMass = false
    actor.nextIsMass = false
    
    actor.wasChained = false
    actor.firstTickOffset = 0
    actor.lastChanStart = 0
    actor.prevEndTime = nil
    actor.prevHastdTick = nil
    actor.isChanneling = false
    
    local function IsEmp(spellId)
        return spellId == 357208 or spellId == 382266 or spellId == 359073 or spellId == 382411
    end
    
    actor.dt_bridge:SetScript("OnEvent", function(self, event, unit, _, spellId)
        if unit ~= "player" then return end
        
        if event == "UNIT_SPELLCAST_SUCCEEDED" or event == "UNIT_SPELLCAST_EMPOWER_STOP" then
            if IsEmp(spellId) and C_SpellBook.IsSpellKnownOrInSpellBook(436335) then
                actor.massStacks = actor.massStacks + 1
                actor.nextIsMass = true
            end
        elseif event == "UNIT_SPELLCAST_CHANNEL_START" then
            if spellId ~= 356995 then return end
            
            -- Mass Disintegrate Tracker
            if actor.massStacks > 0 then
                actor.massStacks = actor.massStacks - 1
                actor.isCurrentlyMass = true
            else
                actor.isCurrentlyMass = false
            end
            actor.nextIsMass = (actor.massStacks > 0)
            
            local chn, _, _, sMS, eMS = UnitChannelInfo("player")
            if not sMS then return end
            
            local startTime = sMS / 1000
            
            actor.firstTickOffset = 0
            if (startTime - actor.lastChanStart) < 0.5 then return end -- ignore micro-restarts
            actor.lastChanStart = startTime
            
            local hastedTickInterval = (C_SpellBook.IsSpellKnown(1219723) and 0.75 or 1) * (C_SpellBook.IsSpellKnown(369913) and 0.8 or 1) / (1 + (UnitSpellHaste("player")/100))
            
            if actor.isChanneling and actor.prevEndTime and actor.prevHastdTick then
                local remaining = actor.prevEndTime - startTime
                actor.firstTickOffset = math.max(0, math.fmod(remaining, actor.prevHastdTick))
                actor.wasChained = true
            else
                actor.wasChained = false
            end
            
            actor.prevEndTime = eMS / 1000
            actor.prevHastdTick = hastedTickInterval
            actor.isChanneling = true
            
        elseif event == "UNIT_SPELLCAST_CHANNEL_UPDATE" then
            if spellId ~= 356995 then return end
            local chn, _, _, sMS, eMS = UnitChannelInfo("player")
            if eMS then
                actor.prevEndTime = eMS / 1000
            end
        elseif event == "UNIT_SPELLCAST_CHANNEL_STOP" then
            if spellId == 356995 then
                actor.isChanneling = false
            end
        end
    end)
end

actor:Sync(function()
    local ok, err = pcall(function()
        if not player.alive then 
            actor.last_dead_time = GetTime()
            return 
        end
        
        -- Hoisted Execution Diagnostic Logger (Placed here natively so it cannot be bypassed by a false 'return')
        local raw_essence = UnitPower("player", Enum.PowerType.Essence, true) or 0
        local display_mod = UnitPowerDisplayMod(Enum.PowerType.Essence) or 1
        if display_mod == 0 then display_mod = 1 end
        local essence = math.max(UnitPower("player", Enum.PowerType.Essence), raw_essence / display_mod)
        local hasEssenceBurst = player:FindBuffByID(359618, true):Active()
        local chanName, _, _, chanStartMS, chanEndMS, _, _, chanSpellID = UnitChannelInfo("player")
        
        if player.in_combat and (GetTime() - actor.lastCastTime > 0.70) then
            if not actor.lastPauseLog or (GetTime() - actor.lastPauseLog > 2) then
                local debug_msg = string.format("[Rotation Trace] PAUSE DETECTED! Reason: %s | Ess: %.1f | chnName: %s", tostring(actor.exitReason), essence, tostring(chanName))
                mint.console.log("|cFFFF0000" .. debug_msg .. "|r")
                actor.lastPauseLog = GetTime()
            end
        end
        actor.exitReason = "Evaluated fully, dropped out of bottom"
        
        local function TrackCast(spellName)
            if actor.lastSpellQueued ~= spellName or GetTime() - (actor.lastSpellQueuedTime or 0) > 0.70 then
                mint.console.log(string.format("|cFF00FF00[APL Trace]|r Execution Ping: %s", spellName))
                actor.lastSpellQueued = spellName
                actor.lastSpellQueuedTime = GetTime()
            end
            actor.lastCastTime = GetTime()
        end
        
        -- 1. Target Management & Acquisition
        local force_swap = false
        
        -- Validate strictly if the current target fails engine metric requirements 
        if not target.exists or target.is_dead or target:IsDead() then
            force_swap = true
        elseif target:GetDistance(player) > 25 or not player:HasLos(target) then
            force_swap = true
        end

        -- If starved and actively engaged in combat, rapidly loop combat array for optimal replacement
        if force_swap and (player:IsPartyInCombat() or player.in_combat) then
            local best_target = nil
            local highest_hp = 0

            mint.ObjectManager.combat:loop(function(enemy)
                -- Tinkr wrapper native fix: explicit `is_dead` instead of `enemy.dead`
                if enemy.is_dead or enemy:IsDead() then return false end
                
                if enemy:GetDistance(player) > 25 then return false end
                if not player:HasLos(enemy) then return false end
                
                -- Optimal sorting (HP maximization)
                if enemy.health > highest_hp then
                    highest_hp = enemy.health
                    best_target = enemy
                end
                return false
            end)

            if best_target then
                mint.console.log("|cFF00FFFF[Auto-Target]|r Acquiring Engaged Priority: " .. tostring(best_target.name))
                winkr_SetNPC(best_target.guid)
                TargetUnit("npc")
            end
        end

        ----------------------------------------------------------------------------
        -- 1.5. Out of Combat Buffing
        ----------------------------------------------------------------------------
        if not player.in_combat and not player:IsMoving() and not player:IsMounted() then
            local someone_is_dead = false
            if IsInGroup() then
                mint.FriendManager:Loop(function(member)
                    if member.is_dead or member:IsDead() then
                        someone_is_dead = true
                        return true
                    end
                    return false
                end)
            end

            if someone_is_dead then
                actor.last_dead_time = GetTime()
            end

            -- Implements an 3-second buffer after the last party member resurrects
            if GetTime() - actor.last_dead_time > 3 then
                -- Blessing of the Bronze (player & party)
                if spells.blessing_of_the_bronze:IsReady() then
                local missingBronze = not HasBronze(player)
                
                if not missingBronze and IsInGroup() then
                    mint.FriendManager:Loop(function(member)
                        -- Ignore dead and max range
                        if member:GetDistance(player) <= 40 and not member.is_dead then
                            if not HasBronze(member) then
                                missingBronze = true
                                return true
                            end
                        end
                        return false
                    end)
                end

                if missingBronze and spells.blessing_of_the_bronze() then 
                    actor.lastCastTime = GetTime()
                    return 
                end
            end

            -- Source of Magic (focus HEALER role automatically)
            if spells.source_of_magic:IsReady() and IsInGroup() then
                local healerUnit = nil
                mint.FriendManager:Loop(function(member)
                    if member.role == "HEALER" and member:GetDistance(player) <= 25 and not member.is_dead then
                        if member:FindBuffByID(369459):Inactive() then
                            healerUnit = member
                            return true
                        end
                    end
                    return false
                end)

                if healerUnit and spells.source_of_magic(healerUnit) then
                    actor.lastCastTime = GetTime()
                    return
                end
            end
        end -- End of 8-second OOC buff timer check
    end



        -- 2. Casting/Channeling Guard (Smart)
        -- Block during genuine casts. Don't block if this is just a "ghost" API remnant.
        if UnitCastingInfo("player") then 
            actor.exitReason = "Player Casting (Physical API Check passed)"
            return 
        end
        local chanName, _, _, chanStartMS, chanEndMS, _, _, chanSpellID = UnitChannelInfo("player")
        if chanName then
            if mint.EmpowerManager.active_spell then return end

            if chanSpellID ~= 356995 then return end -- Protect non-disintegrate channels

            local chanRemaining = (chanEndMS / 1000) - GetTime()

            if chanRemaining > 0 then
                local baseInterval = 1
                if C_SpellBook.IsSpellKnown(1219723) then baseInterval = baseInterval * 0.75 end
                if C_SpellBook.IsSpellKnown(369913) then baseInterval = baseInterval * 0.8 end

                local hastedTickInterval = baseInterval / (1 + (UnitSpellHaste("player") / 100))

                if chanRemaining > hastedTickInterval then
                    actor.exitReason = string.format("Pandemic Guard (Rem: %.2fs > hTI: %.2fs)", chanRemaining, hastedTickInterval)
                    return
                end

                -- Mass Disintegrate: let it exhaust all ticks
                if actor.isCurrentlyMass and not actor.nextIsMass then
                    actor.exitReason = "Mass Disintegrate (Awaiting full exhaustion)"
                    return
                end
            end
        end

        ----------------------------------------------------------------------------
        -- 2. GCD Guard (Spell Queue Window lock)
        -- Expanding to 300ms window seamlessly connects with WoW's native queue without destructive clipping.
        ----------------------------------------------------------------------------
        local gcd = C_Spell.GetSpellCooldown(61304)
        local rem = 0
        if gcd and gcd.startTime > 0 and gcd.duration > 0 then
            rem = gcd.startTime + gcd.duration - GetTime()
            if rem > 0.3 then 
                actor.exitReason = string.format("Global SQW Lock (rem = %.2fs)", rem)
                return 
            end
        end

        ----------------------------------------------------------------------------
        -- Throttling: Prevent action spam
        -- Set slightly below the 50ms tick rate (0.04) to prevent floating 
        -- point variance from skipping engine ticks.
        ----------------------------------------------------------------------------
        if GetTime() - actor.lastCastTime < 0.04 then 
            actor.exitReason = "Action Throttle 50ms Wall"
            return 
        end

        ----------------------------------------------------------------------------
        -- Dispels
        ----------------------------------------------------------------------------
        -- Utilizing the native whitelist toggles from Settings > Dispels
        if mint.data.toggles.dispels then
            local types = { ["Poison"] = true, ["Disease"] = true, ["Curse"] = true, ["Bleed"] = true }
            local dispel_target = nil
            local dispel_poison = false
            
            mint.FriendManager:Loop(function(friend)
                if friend:IsDead() then return false end
                if friend:GetDistance(player) > 30 then return false end
                if not friend:HasDebuffType(types, true) then return false end
                
                dispel_target = friend
                if friend:HasDebuffType({["Poison"] = true}, true) then
                    dispel_poison = true
                end
                
                return true
            end)

            if dispel_target then
                -- Expunge prioritizing poisons naturally
                if dispel_poison and spells.expunge:IsReady() then
                    if spells.expunge(dispel_target) then
                        actor.lastCastTime = GetTime()
                        return
                    end
                end
                
                -- Fallback to omni-dispel
                if spells.cauterizing_flame:IsReady() then
                    if spells.cauterizing_flame(dispel_target) then
                        actor.lastCastTime = GetTime()
                        return
                    end
                end
            end
        end

        ----------------------------------------------------------------------------
        -- Offensive Target Guards
        ----------------------------------------------------------------------------
        local engage_only = true
        if mint.Settings and mint.Settings.profile and mint.Settings.profile.evoker and mint.Settings.profile.evoker.devastation then
            if mint.Settings.profile.evoker.devastation.engage_only ~= nil then
                engage_only = mint.Settings.profile.evoker.devastation.engage_only
            end
        end

        if not target.exists or target:IsDead() or not target.can_attack then 
            actor.exitReason = "Target Invalid or Dead"
            return 
        end

        if engage_only and not target:IsEngaged() and not player.in_combat then
            actor.exitReason = "Target not Engaged"
            return
        end

        ----------------------------------------------------------------------------
        -- Detection & Talents
        ----------------------------------------------------------------------------
        local raw_essence = UnitPower("player", Enum.PowerType.Essence, true) or 0
        local display_mod = UnitPowerDisplayMod(Enum.PowerType.Essence) or 1
        if display_mod == 0 then display_mod = 1 end
        
        -- Fallback gracefully to integer API bounds if fractional metrics are unscaled
        local essence = math.max(UnitPower("player", Enum.PowerType.Essence), raw_essence / display_mod)
        local hasEssenceBurst = player:FindBuffByID(359618, true):Active()
        
        -- Secure individual ID checks (Arrays might fail silently in the API wrapper)
        local hasHover = player:FindBuffByID(358267, true):Active()
        local hasBurnout = player:FindBuffByID(375801, true):Active() or player:FindBuffByID(375802, true):Active()
        local hasSweepBuff = player:FindBuffByID(1265871, true):Active()
        
        -- Resolves physical motion delay by explicitly analyzing raw speed coordinate mapping natively
        local isActuallyMoving = (GetUnitSpeed("player") > 0)
        local isMoving         = isActuallyMoving and not hasHover
        local targetHP         = target:GetHP()
        
        local heroTalent = IsSpellKnown(443328) and "Flameshaper" or "Scalecommander"
        
        spells.fire_breath.ignore_moving   = true
        spells.eternity_surge.ignore_moving = true

        -- 1. Dragonrage (High Priority Cooldown)
        if spells.dragonrage:IsReady() then
            if spells.dragonrage() then
                TrackCast("Dragonrage")
                return
            end
        end

        -- 2. Fire Breath (Empower Rank 1, or Rank 4 for Execute)
        if not isActuallyMoving and spells.fire_breath:IsReady() and rem <= 0.05 then
            local rank = (targetHP < 25) and 4 or 1
            if spells.fire_breath(target, rank) then
                TrackCast("Fire Breath Rank " .. tostring(rank))
                return
            end
        end

        -- 3. Eternity Surge (Rank logic based on ENGAGED enemy count)
        if not isActuallyMoving and spells.eternity_surge:IsReady() and rem <= 0.05 then
            
            local rank = 1
            local count = 0

            -- Count only enemies in combat within 25yd
            -- Optimization: Units are already updated by ObjectManager. Skip redundant Update().
            mint.ObjectManager.enemies:loop(function(enemy)
                if enemy.is_dead or not enemy:GetExists() or not enemy.can_attack or not enemy.in_combat then 
                    return false 
                end
                
                if enemy:IsWithin(25, player) then
                    count = count + 1
                end
                return false
            end)

            if count >= 5 then rank = 3
            elseif count >= 3 then rank = 2
            else rank = 1 end

            if spells.eternity_surge(target, rank) then
                TrackCast("Eternity Surge Rank " .. tostring(rank))
                return
            end
        end

        -- 4. Disintegrate (Spend Essence and Essence Burst)
        if hasEssenceBurst or essence >= 2.8 then
            spells.disintegrate.ignore_moving = hasHover
            
            if not isMoving and spells.disintegrate() then
                TrackCast("Disintegrate")
                return
            end
        end

        -- High-Response Azure Sweep Detection (Buff-Based)
        local curAzureID = hasSweepBuff and 1265867 or 362969

        -- Detect Sweep Consumption (Log only on transition to prevent lag)
        actor.lastAzureID = actor.lastAzureID or 362969
        if actor.lastAzureID ~= 362969 and curAzureID == 362969 then
            mint.console.log("|cFFFF8000[Override]|r Azure Sweep Consumed!")
        end
        actor.lastAzureID = curAzureID

        -- 5. Azure Sweep (Priority over Living Flame ONLY when transformed)
        -- Logic: Cast if buff is active and not capped on Essence or missing Essence Burst proc
        if hasSweepBuff and (essence < 6 or not hasEssenceBurst) then
            if spells.azure_strike() then
                TrackCast("Azure Sweep (Buffed)")
                return
            end
        end

        -- 6. Living Flame (Main Filler - Proc Essence Burst while waiting)
        -- Sync spell object with burnout proc status for mobile-casting PreCheck
        spells.living_flame.ignore_moving = hasBurnout or hasHover 
        if hasBurnout or hasHover or not isActuallyMoving then
            if spells.living_flame() then
                TrackCast("Living Flame" .. (hasBurnout and " (Burnout)" or ""))
                return
            end
        end

        -- 7. Azure Strike (Fallback Movement/Resource Filler)
        if spells.azure_strike() then
            TrackCast("Azure Strike")
            return
        end
        
    end)

    if not ok then
        mint.console.log("|cFFFF0000[Devastation Error]:|r " .. tostring(err))
    end
end)
