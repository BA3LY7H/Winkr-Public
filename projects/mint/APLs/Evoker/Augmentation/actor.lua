local unlocker, ---@class mint
mint, addon = ...

local UnitManager   = mint.UnitManager
local ObjectManager = mint.ObjectManager
local target        = UnitManager:Get("target")
local player        = UnitManager:Get("player")

local evoker_data   = addon.evoker.data["augmentation"]
local spells        = evoker_data.spells
local actor         = addon.evoker.augmentation

-- Throttles to prevent spam on Winkr
actor.lastCastTime = actor.lastCastTime or 0

actor:Sync(function()
    local ok, err = pcall(function()
        if not player.alive then return end
        
        -- 1. Casting/Channeling Guard
        if UnitCastingInfo("player") or UnitChannelInfo("player") then return end

        if not UnitExists("target") then return end
        if not UnitCanAttack("player", "target") then return end
        if UnitIsDeadOrGhost("target") then return end

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

        ----------------------------------------------------------------------------
        -- Detection & Variables
        ----------------------------------------------------------------------------
        local essence = UnitPower("player", Enum.PowerType.Essence)
        local isMoving = player:IsMoving()
        local ebonMightRemains = player:FindBuffByID(spells.ebon_might_aura, true):Remains()
        local hasEssenceBurst = player:FindBuffByID(spells.essence_burst, true):Active()

        ----------------------------------------------------------------------------
        -- 3. Utility / Interrupt
        ----------------------------------------------------------------------------
        local kickTarget = addon.evoker.GetKickTarget()
        if kickTarget and spells.quell:IsReady() then
            if spells.quell(kickTarget) then
                actor.lastCastTime = GetTime()
                return 
            end
        end

        ----------------------------------------------------------------------------
        -- 4. Buff Maintenance (Augmentation Special)
        ----------------------------------------------------------------------------
        
        -- Blistering Scales on Tank
        local tank = addon.evoker.GetAugmentationTankTarget()
        if tank:GetExists() and spells.blistering_scales:IsReady() then
            -- 360827 is Blistering Scales
            if not tank:FindBuffByID(360827, false):Active() then
                if spells.blistering_scales(tank) then
                    actor.lastCastTime = GetTime()
                    return
                end
            end
        end

        -- Prescience on DPS
        local presTarget = addon.evoker.GetPrescienceTarget()
        if presTarget:GetExists() and spells.prescience:IsReady() then
            if spells.prescience(presTarget) then
                actor.lastCastTime = GetTime()
                return
            end
        end

        -- Ebon Might (Core maintenance)
        if spells.ebon_might:IsReady() and ebonMightRemains < 3.0 then
            if spells.ebon_might() then
                actor.lastCastTime = GetTime()
                return
            end
        end

        ----------------------------------------------------------------------------
        -- 5. Combat Rotation (Maximizing Ebon Might Extension)
        ----------------------------------------------------------------------------
        
        -- Breath of Eons (Priority Window)
        if spells.breath_of_eons:IsReady() and ebonMightRemains > 5 then
            if spells.breath_of_eons() then
                actor.lastCastTime = GetTime()
                return
            end
        end

        -- Empowers (For Ebon Might Extension/Animosity)
        if spells.fire_breath:IsReady() and (ebonMightRemains > 0 and ebonMightRemains < 20) then
            if spells.fire_breath() then
                actor.lastCastTime = GetTime()
                return
            end
        end

        if spells.upheaval:IsReady() and (ebonMightRemains > 0 and ebonMightRemains < 20) then
            -- Logic check: If Tip the Scales is ready, use it with Upheaval
            if spells.tip_the_scales:IsReady() then
                spells.tip_the_scales()
            end
            if spells.upheaval() then
                actor.lastCastTime = GetTime()
                return
            end
        end

        -- Essence Spend: Eruption (Maximum extension)
        if (hasEssenceBurst or essence >= 3) and ebonMightRemains > 0 and ebonMightRemains < 22 then
            if spells.eruption() then
                actor.lastCastTime = GetTime()
                return
            end
        end

        -- Fillers
        if isMoving then
            if spells.azure_strike() then
                actor.lastCastTime = GetTime()
                return
            end
        else
            -- Check for Chrono Flame replacement if Chronowarden talented (437022)
            if IsSpellKnown(437022) then
                -- Chrono Flame cast
                if spells.living_flame() then -- It uses the same ID or name replacement
                    actor.lastCastTime = GetTime()
                    return
                end
            else
                if spells.living_flame() then
                    actor.lastCastTime = GetTime()
                    return
                end
            end
        end

    end)

    if not ok then
        mint.console.log("|cFFFF0000[Augmentation Error]:|r " .. tostring(err))
    end
end)
