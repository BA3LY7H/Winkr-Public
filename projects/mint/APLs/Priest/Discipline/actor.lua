local unlocker, ---@class mint
mint, addon = ...

local UnitManager   = mint.UnitManager
local ObjectManager = mint.ObjectManager
local FriendManager = mint.FriendManager
local target        = UnitManager:Get("target")
local player        = UnitManager:Get("player")

local disc_data     = addon.priest.data["Discipline"]
local spells        = disc_data.spells
local auras         = disc_data.auras
local actor         = addon.priest.discipline

actor.lastCastTime = actor.lastCastTime or 0

actor:Sync(function()
    local ok, err = pcall(function()
        if not player.alive then return end

        ----------------------------------------------------------------------------
        -- TARGET MANAGEMENT
        ----------------------------------------------------------------------------
        if not target:GetExists() or target:IsDead() or target:IsFriend() then
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
        end

        ----------------------------------------------------------------------------
        -- 1. Casting Guard
        ----------------------------------------------------------------------------
        if UnitCastingInfo("player") or UnitChannelInfo("player") then return end

        local engage_only = true
        if mint.Settings and mint.Settings.profile and mint.Settings.profile.priest and mint.Settings.profile.priest.discipline then
            if mint.Settings.profile.priest.discipline.engage_only ~= nil then
                engage_only = mint.Settings.profile.priest.discipline.engage_only
            end
        end
        if engage_only and target:GetExists() and not target:IsEngaged() then
            return
        end

        if target:GetExists() and target:IsEnemy() and not C_Spell.IsCurrentSpell(6603) then
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

        if GetTime() - actor.lastCastTime < 0.3 then return end
        
        if player:IsMounted() or player:IsFlying() then return end

        ----------------------------------------------------------------------------
        -- Level 19 Healing Logic
        ----------------------------------------------------------------------------
        
        -- 1. Power Word: Shield if you are taking damage (or single player taking damage)
        -- Priest solo Priority implies PW:S on yourself if HP < 90%.
        if player:GetRealizedHP() < 90 and not player:FindBuffByID(auras.power_word_shield.id):Active() then
            if spells.power_word_shield:IsReady() then
                if spells.power_word_shield(player) then
                    actor.lastCastTime = GetTime()
                    return
                end
            end
        end

        local lowest_friend = FriendManager:GetLowest(90)
        if lowest_friend and lowest_friend:GetExists() and not lowest_friend:FindBuffByID(auras.power_word_shield.id):Active() then
            if spells.power_word_shield:IsReady() then
                if spells.power_word_shield(lowest_friend) then
                    actor.lastCastTime = GetTime()
                    return
                end
            end
        end

        -- 2. Power Word: Radiance when available and multiple people need Atonement (i.e., at least 2 without Atonement and some damage taking)
        if FriendManager:GetCountBelow(85) >= 2 and FriendManager:GetNumFriendsWithoutBuff(auras.atonement.id) >= 2 then
            if spells.power_word_radiance:IsReady() then
                if spells.power_word_radiance(player) then  -- Cast on self is generally fine for Radiance group hit
                    actor.lastCastTime = GetTime()
                    return
                end
            end
        end

        -- 3. High Damage Cooldown: Ultimate Penitence after applying Atonement to full group
        -- If 3+ people below 70%, and Atonement is on the full group (0 without atonement or <=1)
        if FriendManager:GetCountBelow(70) >= 3 and FriendManager:GetNumFriendsWithoutBuff(auras.atonement.id) <= 1 then
            if IsPlayerSpell(421453) and spells.ultimate_penitence:IsReady() and target:GetExists() and target:IsEnemy() then
                if spells.ultimate_penitence(target) then
                    actor.lastCastTime = GetTime()
                    return
                end
            end
        end

        -- 4. Flash Heal when direct healing is needed (Atonement not enough)
        local critical_friend = FriendManager:GetLowest(60)
        if critical_friend and critical_friend:GetExists() then
            if spells.flash_heal:IsReady() and (not player:IsMoving() or player:FindBuffByID(auras.surge_of_light.id):Active()) then
                if spells.flash_heal(critical_friend) then
                    actor.lastCastTime = GetTime()
                    return
                end
            end
        end

        ----------------------------------------------------------------------------
        -- Level 19 Damage Priorities (Atonement DPS)
        ----------------------------------------------------------------------------
        if not target:GetExists() or not target:IsEnemy() then return end

        -- 1. Power Infusion on CD
        if IsPlayerSpell(10060) and spells.power_infusion:IsReady() then
            if spells.power_infusion(player) then
                actor.lastCastTime = GetTime()
                return
            end
        end

        -- 2. Maintain Shadow Word: Pain
        local swpDebuff = target:FindDebuffByID(auras.shadow_word_pain.id, true)
        if not swpDebuff:Active() or swpDebuff:Remains() < 4 then
            if target:GetHealth() > 10 then -- Check target isn't dying instantly
                if spells.shadow_word_pain:IsReady() then
                    if spells.shadow_word_pain(target) then
                        actor.lastCastTime = GetTime()
                        return
                    end
                end
            end
        end
        
        -- Also try to spread SW:P
        if spells.shadow_word_pain:IsReady() then
            local swp_target = nil
            ObjectManager.enemies:loop(function(enemy)
                if enemy.guid == target.guid then return false end
                if enemy.is_dead or not enemy:GetExists() or not enemy.in_combat then return false end
                if not player:HasLos(enemy) then return false end
                if enemy:GetDistanceSquared(player) > (40 * 40) then return false end
                if enemy:GetHealth() < 10 then return false end -- don't spread to almost dead
                if not enemy:FindDebuffByID(auras.shadow_word_pain.id, true):Active() then
                    swp_target = enemy
                    return true -- break loop
                end
                return false
            end)
            if swp_target then 
                if spells.shadow_word_pain(swp_target) then
                    actor.lastCastTime = GetTime()
                    return
                end
            end
        end

        -- 3. Penance on cooldown (offensively)
        if spells.penance:IsReady() then
            if spells.penance(target) then
                actor.lastCastTime = GetTime()
                return
            end
        end

        -- 4. Mind Blast on cooldown
        if spells.mind_blast:IsReady() and not player:IsMoving() then
            if spells.mind_blast(target) then
                actor.lastCastTime = GetTime()
                return
            end
        end

        -- 5. Smite as filler
        if spells.smite:IsReady() and not player:IsMoving() then
            if spells.smite(target) then
                actor.lastCastTime = GetTime()
                return
            end
        end

    end)

    if not ok then
        mint.console.log("|cFFFF0000[Discipline Error]:|r " .. tostring(err))
    end
end)