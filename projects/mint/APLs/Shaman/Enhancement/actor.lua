local unlocker, ---@class mint
mint, addon = ...

local UnitManager   = mint.UnitManager
local ObjectManager = mint.ObjectManager
local target        = UnitManager:Get("target")
local player        = UnitManager:Get("player")

local enh_data      = addon.shaman.data["Enhancement"]
local spells        = enh_data.spells
local actor         = addon.shaman.enhancement

-- Throttles to prevent spam on Winkr
actor.lastCastTime = actor.lastCastTime or 0

local function MaelstromStacks()
    -- Maelstrom Weapon Buff ID: 187881 (Midnight)
    local buff = player:FindBuffByID(187881)
    return buff and buff:Active() and buff:Count() or 0
end

local function GetStrategy()
    local profile = mint.Settings.profile.shaman.enhancement
    if profile.strategy_override ~= "Auto" then
        return profile.strategy_override
    end
    
    local inInstance, instanceType = IsInInstance()
    if instanceType == "party" or instanceType == "raid" then
        -- Count enemies nearby for basic AoE detection if we're in a group
        if target:GetExists() and target:GetEnemies(10) >= 3 then
            return "Mythic+"
        end
    end
    return "Raid"
end

actor:Sync(function()
    local ok, err = pcall(function()
        -- Safety: Ensure settings are loaded
        if not mint.Settings.profile.shaman or not mint.Settings.profile.shaman.enhancement then return end
        if not player.alive then return end

        ----------------------------------------------------------------------------
        -- TARGET MANAGEMENT (Snappy Auto-Targeting)
        ----------------------------------------------------------------------------
        if not target:GetExists() or target:IsDead() or target:IsFriend() then
            -- Find the highest HP mob we are in combat with
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
        -- GUARDS & THROTTLES
        ----------------------------------------------------------------------------
        if UnitCastingInfo("player") or UnitChannelInfo("player") then return end

        -- GCD Guard (61304 is the global GCD spell ID)
        local gcd = C_Spell.GetSpellCooldown(61304)
        if gcd and gcd.startTime > 0 and gcd.duration > 0 then
            local rem = gcd.startTime + gcd.duration - GetTime()
            if rem > 0.1 then return end
        end

        -- Action Throttle (300ms) to prevent Winkr-related input lag/spam
        if GetTime() - actor.lastCastTime < 0.3 then return end

        ----------------------------------------------------------------------------
        -- OUT OF COMBAT / BUFFING (Midnight Leveling Logic)
        ----------------------------------------------------------------------------
        if not player:IsInCombat() then
            -- Recuperate: Baseline OOC heal for all classes in Midnight
            if player:GetHP() < 70 and IsPlayerSpell(439709) then
                if spells.recuperate:Cast(player) then
                    actor.lastCastTime = GetTime()
                    return
                end
            end

            -- Buffs & Imbues (Only when stationary and safe)
            if not player:IsMoving() and not player:IsMounted() and not player:IsFlying() then
                -- Skyfury: Periodic Raid/Party Buff
                if IsPlayerSpell(462854) and not player:FindBuffByID(462854):Active() then
                    if spells.skyfury:Cast(player) then return end
                end

                -- Weapon Imbues
                local hasMainHandEnchant, _, _, _, hasOffHandEnchant = GetWeaponEnchantInfo()
                
                -- Windfury (Main Hand)
                if IsPlayerSpell(33757) and not hasMainHandEnchant then
                    if spells.windfury_weapon:Cast(player) then return end
                end
                
                -- Flametongue (Off Hand)
                if IsPlayerSpell(318038) and not hasOffHandEnchant then
                    if spells.flametongue_weapon:Cast(player) then return end
                end

                -- Shields
                if IsPlayerSpell(192106) and not player:FindBuffByID(192106):Active() then
                    if spells.lightning_shield:Cast(player) then return end
                end
                
                -- Earth Shield (Leveling survivability)
                if IsPlayerSpell(974) and not player:FindBuffByID(974):Active() then
                    if spells.earth_shield:Cast(player) then return end
                end
            end
        end

        ----------------------------------------------------------------------------
        -- COMBAT ROTATION
        ----------------------------------------------------------------------------
        -- Engagement check
        local engage_only = mint.Settings.profile.shaman.enhancement.engage_only
        if engage_only and not target:IsEngaged() then
            return
        end

        -- Auto-Attack Snap
        if not C_Spell.IsCurrentSpell(6603) and player:GetDistance(target) < 8 then
            StartAttack()
        end

        -- Utility: Auto-Interrupt (Wind Shear)
        local kickTarget = enh_data.targets.kick
        if kickTarget and kickTarget:GetExists() and spells.wind_shear:IsReady() then
            if spells.wind_shear:Cast(kickTarget) then
                actor.lastCastTime = GetTime()
                return
            end
        end

        local mw = MaelstromStacks()
        local strategy = GetStrategy()

        -- 1. Surging Totem (Totemic Hero Talent - High Priority)
        if IsPlayerSpell(444995) and spells.surging_totem:IsReady() then
            if spells.surging_totem:Cast(player) then
                actor.lastCastTime = GetTime()
                return
            end
        end

        -- 2. Flame Shock / Voltaic Blaze (DoT management)
        -- Voltaic Blaze (ID 470057) is a new proc-based way to apply FS in Midnight
        if IsPlayerSpell(470057) and spells.voltaic_blaze:IsReady() then
            if spells.voltaic_blaze:Cast(target) then
                actor.lastCastTime = GetTime()
                return
            end
        end

        if IsPlayerSpell(470411) then
            local fs = target:FindDebuffByID(188389, true)
            if not fs:Active() or fs:Remains() < 4 then
                if spells.flame_shock:Cast(target) then
                    actor.lastCastTime = GetTime()
                    return
                end
            end
        end

        -- 3. Crash Lightning (Maintain Cleave/Stormstrike buff)
        if IsPlayerSpell(187874) and spells.crash_lightning:IsReady() then
            if spells.crash_lightning:Cast(target) then
                actor.lastCastTime = GetTime()
                return
            end
        end

        -- 4. Stormstrike / Primal Strike (Core Builder)
        if IsPlayerSpell(17364) and spells.stormstrike:IsReady() then
            if spells.stormstrike:Cast(target) then
                actor.lastCastTime = GetTime()
                return
            end
        elseif IsPlayerSpell(6603) and spells.primal_strike:IsReady() then
            if spells.primal_strike:Cast(target) then
                actor.lastCastTime = GetTime()
                return
            end
        end

        -- 5. Lava Lash (Secondary Builder)
        if IsPlayerSpell(408507) then
            if spells.lava_lash:IsReady() then
                if spells.lava_lash:Cast(target) then
                    actor.lastCastTime = GetTime()
                    return
                end
            end
        end

        -- 6. Maelstrom Spender (Tempest > LB/CL)
        -- We spend MW when at high stacks (>= 5) but after our builders
        local mw_threshold = mint.Settings.profile.shaman.enhancement.maelstrom_threshold or 5
        if mw >= mw_threshold then
            -- Tempest (ID 454009) is the new super-spender in Midnight
            if IsPlayerSpell(454009) and spells.tempest:IsReady() then
                if spells.tempest:Cast(target) then
                    actor.lastCastTime = GetTime()
                    return
                end
            end

            if strategy == "Mythic+" and IsPlayerSpell(188443) then
                if spells.chain_lightning:Cast(target) then
                    actor.lastCastTime = GetTime()
                    return
                end
            elseif IsPlayerSpell(188196) then
                if spells.lightning_bolt:Cast(target) then
                    actor.lastCastTime = GetTime()
                    return
                end
            end
        end

        -- 7. Emergency Maelstrom spend (Prevent overcap if everything else is on CD)
        if mw >= 8 then
             if spells.lightning_bolt:Cast(target) then 
                actor.lastCastTime = GetTime()
                return 
             end
        end

    end)


    if not ok then
        mint.console.log("|cFFFF0000[Enhancement Error]:|r " .. tostring(err))
        if mint.data.debug_mode then
            mint.WriteFile("Enhancement_Errors.log", tostring(err) .. "\n", true)
        end
    end
end)
