local unlocker, ---@class mint
mint, addon = ...

local UnitManager   = mint.UnitManager
local FriendManager = mint.FriendManager
local target        = UnitManager:Get("target")
local player        = UnitManager:Get("player")

local evoker_data   = addon.evoker.data["preservation"]
local spells        = evoker_data.spells
local auras         = evoker_data.auras
local actor         = addon.evoker.preservation
local profile       = mint.Settings.profile.evoker.preservation

--! Throttles !--
actor.lastCastTime = actor.lastCastTime or 0

actor:Sync(function()
    local ok, err = pcall(function()
        if not player or not player.alive then
            return
        end

        if IsMounted() then 
            return 
        end
        
        -- 1. Casting/Channeling/Empowering Guard
        -- Robust check for Empowering stage to prevent interrupting Fire Breath
        local isEmpowering = false
        if C_Spell and C_Spell.GetUnitEmpowerStage then
            isEmpowering = (C_Spell.GetUnitEmpowerStage("player") or -1) > -1
        elseif _G.GetUnitEmpowerStage then
            isEmpowering = (_G.GetUnitEmpowerStage("player") or -1) > -1
        end
        -- Fallback: check 9th return of ChannelInfo
        if not isEmpowering then
            isEmpowering = select(9, UnitChannelInfo("player"))
        end

        if player:IsCasting() or player:IsChanneling() or isEmpowering then 
            return 
        end
        
        -- 2. GCD Guard
        if mint.gcd > 0.1 then 
            return 
        end

        -- Main Throttling (250ms)
        if GetTime() - actor.lastCastTime < 0.25 then return end

        FriendManager:Update()
        
        local essence = UnitPower("player", Enum.PowerType.Essence)
        local hasHover = player:FindBuffByID(358267, true):Active()
        local isMoving = player:IsMoving() and not hasHover
        local lowest = FriendManager:GetLowest()
        local inCombat = player:IsInCombat()

        local function Cast(spell, unit_or_key)
            if not spell:IsKnown() and not spell.ignore_known then 
                return false 
            end
            if not spell:IsReady() then 
                return false 
            end
            
            -- Use the provided unit or default to target
            local castTarget = unit_or_key
            if type(unit_or_key) == "string" or not unit_or_key then
                castTarget = target
            end

            if spell(castTarget) then
                mint.console.log("CAST ORDER: " .. spell.name)
                actor.lastCastTime = GetTime()
                return true
            end
            return false
        end

        -- 3. Utility
        if inCombat then
            Cast(spells.quell, "Smart")
        end

        ----------------------------------------------------------------------------
        -- 4. Healing Rotation
        ----------------------------------------------------------------------------
        if lowest and lowest:GetExists() and lowest.realized_hp < 95 then
            if essence >= 2 then
                if Cast(spells.echo, lowest) then return end
            end
            if Cast(spells.emerald_blossom, lowest) then return end
            if Cast(spells.reversion, lowest) then return end
            
            if lowest.realized_hp < profile.verdant_embrace_threshold then
                if Cast(spells.verdant_embrace, lowest) then return end
            end
            
            if not isMoving then
                if Cast(spells.dream_breath, lowest) then return end
            end
            
            if not isMoving and lowest.realized_hp < profile.living_flame_threshold then
                if Cast(spells.living_flame, lowest) then return end
            end
        end

        ----------------------------------------------------------------------------
        -- 5. DPS Rotation
        ----------------------------------------------------------------------------
        target:Update()
        local t_exists = target and target:GetExists()
        local t_enemy = target and target:IsEnemy()
        local t_dead = target and target:IsDead()
        
        if t_exists and t_enemy and not t_dead then
            -- 1. Deep Breath (IsKnown check)
            if player:GetEnemies(15) >= 3 then
                if Cast(spells.deep_breath, target) then return end
            end

            -- 2. Azure Strike
            if isMoving or player:GetEnemies(10) >= 2 then
                if Cast(spells.azure_strike, target) then return end
            end

            -- 3. Fire Breath
            if not isMoving then
                if Cast(spells.fire_breath, target) then return end
            end

            -- 4. Disintegrate
            if essence >= 3 and not isMoving then
                if Cast(spells.disintegrate, target) then return end
            end

            -- 5. Living Flame
            if not isMoving then
                if Cast(spells.living_flame, target) then return end
            end
        end
    end)
    if not ok then
        mint.console.log("ACTOR CRASH: " .. tostring(err))
    end
end)
