local unlocker, ---@class mint
mint, addon = ...

local UnitManager   = mint.UnitManager
local ObjectManager = mint.ObjectManager
local target        = UnitManager:Get("target")
local player        = UnitManager:Get("player")

local shadow_data   = addon.priest.data["Shadow"]
local spells        = shadow_data.spells
local actor         = addon.priest.shadow

-- Throttles to prevent spam on Winkr
actor.lastCastTime = actor.lastCastTime or 0

actor:Sync(function()
    local ok, err = pcall(function()
        if not player.alive then return end

        ----------------------------------------------------------------------------
        -- TARGET MANAGEMENT
        ----------------------------------------------------------------------------
        if not target:GetExists() or target:IsDead() or target:IsFriend() then
            -- Auto-target: find the highest HP mob we are in combat with
            local best_target = nil
            local highest_hp = 0

            ObjectManager.enemies:loop(function(enemy)
                enemy:Update()
                if enemy.is_dead or not enemy:GetExists() or not enemy.can_attack then return false end
                if not player:HasLos(enemy) then return false end
                if enemy:GetDistanceSquared(player) > (40 * 40) then return false end
                
                if enemy:IsEngaged() then
                    local hp = enemy:GetHealth()
                    if hp > highest_hp then
                        highest_hp = hp
                        best_target = enemy
                    end
                end
                
                return false
            end)

            if best_target then
                local guid = best_target.guid
                if guid and winkr_IsValidObject(guid) then
                    winkr_SetNPC(guid)
                    TargetUnit("npc")
                end
            end

            return
        end

        ----------------------------------------------------------------------------
        -- 1. Casting/Channeling Guard with Early Clip for Mind Flay
        ----------------------------------------------------------------------------
        if UnitCastingInfo("player") then return end
        
        local channelName, _, _, _, _, _, _, channelID = UnitChannelInfo("player")
        if channelName then
            -- 15407 is Mind Flay, 47758 is Mind Flay (Insanity) - checking both just in case
            if channelID == 15407 or channelID == 47758 then 
                -- Early clip for max DPS if a higher priority spell is ready
                local canClip = false
                if IsPlayerSpell(8092) and spells.mind_blast:IsReady() then
                    canClip = true
                elseif IsPlayerSpell(335467) and spells.shadow_word_madness:IsReady() and UnitPower("player", 13) >= 50 then
                    canClip = true
                elseif IsPlayerSpell(32379) and spells.shadow_word_death:IsReady() and target:GetHealth() < 20 then
                    canClip = true
                end
                
                if not canClip then
                    return 
                end
            else
                -- If channeling something else, do not interrupt
                return
            end
        end

        -- Combat engagement check
        local engage_only = true
        if mint.Settings and mint.Settings.profile and mint.Settings.profile.priest and mint.Settings.profile.priest.shadow then
            if mint.Settings.profile.priest.shadow.engage_only ~= nil then
                engage_only = mint.Settings.profile.priest.shadow.engage_only
            end
        end
        if engage_only and not target:IsEngaged() then
            return
        end

        if not C_Spell.IsCurrentSpell(6603) then
            StartAttack()
        end

        ----------------------------------------------------------------------------
        -- 2. GCD Guard
        ----------------------------------------------------------------------------
        local gcd = C_Spell.GetSpellCooldown(61304)
        if gcd and gcd.startTime > 0 and gcd.duration > 0 then
            local rem = gcd.startTime + gcd.duration - GetTime()
            if rem > 0.1 then return end
        end

        ----------------------------------------------------------------------------
        -- Throttling: Prevent action spam faster than 300ms
        ----------------------------------------------------------------------------
        if GetTime() - actor.lastCastTime < 0.3 then return end

        local insanity = UnitPower("player", 13) -- Enum.PowerType.Insanity is 13

        ----------------------------------------------------------------------------
        -- 3. Utility / Interrupt
        ----------------------------------------------------------------------------
        if IsPlayerSpell(15487) and target:IsCasting() and spells.silence:IsReady() then
            if spells.silence(target) then
                actor.lastCastTime = GetTime()
                return 
            end
        end

        ----------------------------------------------------------------------------
        -- 0. Buffs
        ----------------------------------------------------------------------------
        if not player:IsMounted() and not player:IsFlying() then
            -- Power Word: Fortitude
            if IsPlayerSpell(21562) and not player:FindBuffByID(21562):Active() then
                if spells.power_word_fortitude() then return end
            end
            
            -- Shadowform
            if IsPlayerSpell(232698) and not player:FindBuffByID(232698):Active() then
                if spells.shadowform() then return end
            end
        end

        local enemies = target:GetEnemies(10)

        ----------------------------------------------------------------------------
        -- 1. AOE / DOT SPREADING (Vampiric Touch & SW:P)
        ----------------------------------------------------------------------------
        if IsPlayerSpell(34914) then
            local primary_vt = target:FindDebuffByID(34914, true)
            
            -- Priority A: Maintain VT on primary target
            if not primary_vt:Active() or primary_vt:Remains() < 4 then
                if spells.vampiric_touch(target) then
                    actor.lastVTTarget = target.guid
                    actor.lastCastTime = GetTime()
                    return
                end
            end

            -- Priority B: Spread VT to secondary targets via explicit battlefield scan
            if IsPlayerSpell(238558) then
                local cast_attempted = false
                ObjectManager.combat:loop(function(enemy)
                    if enemy:GetExists() and not enemy.is_dead and enemy.guid ~= target.guid then
                        -- Check Distance & LoS
                        if enemy:GetDistanceSquared(player) <= (40 * 40) and player:HasLos(enemy) then
                            -- Check if needs VT
                            local vt = enemy:FindDebuffByID(34914, true)
                            if not vt:Active() or vt:Remains() < 4 then
                                if spells.vampiric_touch(enemy) then
                                    actor.lastVTTarget = enemy.guid
                                    actor.lastCastTime = GetTime()
                                    cast_attempted = true
                                    return true -- break loop
                                end
                            end
                        end
                    end
                end)
                if cast_attempted then return end
            end
        end

        -- Spread SW:P manually if moving OR not talented into Misery
        if IsPlayerSpell(589) and (not IsPlayerSpell(238558) or player:IsMoving()) then
            local swpDebuff = target:FindDebuffByID(589, true)
            if not swpDebuff:Active() or swpDebuff:Remains() < 4 then
                if spells.shadow_word_pain(target) then
                    actor.lastCastTime = GetTime()
                    return
                end
            end
            
            -- Manual spreading loop for SW:P if Misery is not present
            local swp_attempted = false
            ObjectManager.combat:loop(function(enemy)
                if enemy:GetExists() and not enemy.is_dead and enemy.guid ~= target.guid then
                    if enemy:GetDistanceSquared(player) <= (40 * 40) and player:HasLos(enemy) then
                        local swp = enemy:FindDebuffByID(589, true)
                        if not swp:Active() or swp:Remains() < 4 then
                            if spells.shadow_word_pain(enemy) then
                                actor.lastCastTime = GetTime()
                                swp_attempted = true
                                return true -- break loop
                            end
                        end
                    end
                end
            end)
            if swp_attempted then return end
        end

        ----------------------------------------------------------------------------
        -- 3. Power Infusion
        ----------------------------------------------------------------------------
        if IsPlayerSpell(10060) and target:IsBoss() and spells.power_infusion:IsReady() then
            if spells.power_infusion("player") then
                actor.lastCastTime = GetTime()
                return
            end
        end

        ----------------------------------------------------------------------------
        -- 4. Shadow Word: Madness (spend Insanity)
        ----------------------------------------------------------------------------
        if IsPlayerSpell(335467) and spells.shadow_word_madness:IsReady() and insanity >= 50 then
            if spells.shadow_word_madness() then
                actor.lastCastTime = GetTime()
                return
            end
        end

        ----------------------------------------------------------------------------
        -- 5. Mind Blast
        ----------------------------------------------------------------------------
        if IsPlayerSpell(8092) and spells.mind_blast:IsReady() then
            if spells.mind_blast() then
                actor.lastCastTime = GetTime()
                return
            end
        end

        ----------------------------------------------------------------------------
        -- 6. Mind Flay
        ----------------------------------------------------------------------------
        if IsPlayerSpell(15407) and not player:IsMoving() then
            if spells.mind_flay() then
                actor.lastCastTime = GetTime()
                return
            end
        end

        -- Smite fallback
        if IsPlayerSpell(585) and (not IsPlayerSpell(15407) or player:IsMoving()) then
            if spells.smite() then
                actor.lastCastTime = GetTime()
                return
            end
        end

    end)

    if not ok then
        mint.console.log("|cFFFF0000[Shadow Error]:|r " .. tostring(err))
    end
end)
