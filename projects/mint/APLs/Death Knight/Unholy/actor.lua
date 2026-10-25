local unlocker,
---@class mint
mint,
addon = ...

------------------------------
--- Locals
------------------------------
local RaidEvents 		= mint.RaidEvents
local UnitManager 		= mint.UnitManager
local FriendManager 	= mint.FriendManager
local ObjectManager 	= mint.ObjectManager
local Events 			= mint.EventManager
local Constants 		= mint.Constants
local Totems 			= mint.TotemManager
local SmartTarget 		= mint.SmartTarget
local Queue 			= mint.Queue
local Dispel 			= mint.Dispel
local Spell 			= mint.Spell.New
local bin 				= mint.bin
local StopTimer 		= mint.data.StopTimer
local MoveTimer 		= mint.data.MoveTimer
local max_gcd 			= mint.max_gcd
local gcd 				= mint.gcd
local toggles           = mint.data.toggles
local target 			= UnitManager:Get("target")
local player 			= UnitManager:Get("player")

--! Addon Locals !--
local unholy 			= addon.deathknight.unholy
local spells 			= addon.deathknight.data["Unholy"].spells
local auras 			= addon.deathknight.data["Unholy"].auras
local targets 			= addon.deathknight.data["Unholy"].targets
local vars 				= addon.deathknight.data["Unholy"].vars
local profile           = mint.Settings.profile.deathknight.unholy

local function CombatTime()
    return GetTime() - (mint.combatStartTime or GetTime())
end

-- Helper to safely count AoE epidemic targets using Winkr OM
local function GetEpidemicCount()
    local count = 0
    ObjectManager.enemies:each(function(enemy)
        enemy:Update()
        if not enemy.dead and enemy:IsInCombat() and player:GetDistanceSquared(enemy) <= (40*40) and player:HasLos(enemy) then
            count = count + 1
        end
        return false
    end)
    return count
end

unholy:Sync(function()
	if player:IsChanneling() or UnitCastingInfo("player") then return end
    if IsMounted() then return end
    if mint.gcd > 0.1 then return end

    ------------------------------
	--- Combat Rotation
	------------------------------
	if player:IsPartyInCombat() or player:IsInCombat() then
        local hasTarget = UnitExists("target") and UnitCanAttack("player", "target") and not UnitIsDeadOrGhost("target")
        
        if hasTarget and not C_Spell.IsCurrentSpell(6603) then
            StartAttack()
        end

		if not hasTarget then
			SmartTarget:Acquire()
            return
		end
        
        -- Smart Kick
        if spells.mind_freeze:IsKnown() and spells.mind_freeze:IsReady() then spells.mind_freeze() end
        -- Auto Asphyxiate
        if spells.asphyxiate:IsKnown() and spells.asphyxiate:IsReady() then spells.asphyxiate() end
        -- Death strike if below the threshold
        if spells.death_strike:IsKnown() and spells.death_strike:IsUsable() and player.hp <= profile.ds_pct then spells.death_strike() end

        -- Variable Setup
        local isSanlayn = vars.IsSanlayn()
        local isRider = vars.IsRider()
        local hasHeroSpec = isSanlayn or isRider
        local aotd_ready = spells.army_of_the_dead:IsKnown() and spells.army_of_the_dead:IsReady()
        local dt_ready = spells.dark_transformation:IsKnown() and spells.dark_transformation:IsReady()
        local epidemic_count = GetEpidemicCount()
        local isAoE = epidemic_count >= 3
        local runes = player:GetRunes()
        local rp = player:GetPower()
        
        -- Aura Tracking (Midnight: Lesser Ghoul stacks on PLAYER, no Festering Wounds)
        local lesser_ghoul_buff = player:FindBuff(auras.lesser_ghoul_ready)
        local ghoul_stacks = 0
        if lesser_ghoul_buff and lesser_ghoul_buff:Active() then
            ghoul_stacks = math.max(1, lesser_ghoul_buff:Count())
        end
        
        local has_vp = target:FindDebuff(auras.virulent_plague):Active()
        local vp_remains = target:FindDebuff(auras.virulent_plague):Remains()
        local has_dp = target:FindDebuff(auras.dread_plague):Active()
        local dp_remains = target:FindDebuff(auras.dread_plague):Remains()
        local target_hp = target.hp

        -- Cooldowns block
        if toggles.cooldowns then
            if profile.auto_aotd and aotd_ready and target_hp > 35 then
                if spells.army_of_the_dead:Cast(player) then mint.console.log("Army of the Dead") return true end
            end
            if profile.auto_dt and dt_ready then
                if spells.dark_transformation:Cast(player) then mint.console.log("Dark Transformation") return true end
            end
            if profile.abom_toggle and spells.abomination_limb:IsKnown() and spells.abomination_limb:IsReady() then
                if spells.abomination_limb:Cast(player) then return true end
            end
        end

        -------------------------------------------------------------
        -- Universal Priority (always runs first)
        -------------------------------------------------------------
        -- 1. Disease Maintenance — Outbreak applies Virulent Plague + Dread Plague
        if spells.outbreak:IsKnown() and (not has_vp or vp_remains < 3 or not has_dp or dp_remains < 3) then
            if spells.outbreak:Cast(target) then mint.console.log("Outbreak Refresh") return true end
        end

        -- 2. Execute Priority — Soul Reaper below 35%
        if spells.soul_reaper:IsKnown() and target_hp <= 35 and spells.soul_reaper:IsReady() then
            if not isSanlayn or not player:FindBuff(auras.reaping):Active() then
                if spells.soul_reaper:Cast(target) then mint.console.log("Soul Reaper Execute") return true end
            end
        end

        -------------------------------------------------------------
        -- Baseline / Leveling Rotation (No Hero Talents)
        -- Midnight: Lesser Ghoul stacks are the core mechanic.
        -- All checks use :IsKnown() so abilities auto-enable as you level.
        -------------------------------------------------------------
        if not hasHeroSpec then

            -- 1. Putrefy — sacrifice a Lesser Ghoul for AoE damage + RP
            if ghoul_stacks >= 1 and spells.putrefy:IsKnown() and spells.putrefy:IsReady() then
                if spells.putrefy:Cast(player) then mint.console.log("Putrefy") return true end
            end

            -- 2. Death and Decay for AoE
            if isAoE and spells.death_and_decay:IsKnown() and spells.death_and_decay:IsReady() and not player:FindBuff(auras.death_and_decay):Active() then
                if spells.death_and_decay:Cast(player) then mint.console.log("Death and Decay") return true end
            end

            -- 3. Runic Power Spenders — Epidemic at 3+ targets, Death Coil otherwise
            -- 3. Runic Power Spenders
            if rp >= 30 then
                local casted = false
                if isAoE and spells.epidemic:IsKnown() and spells.epidemic:IsReady() then
                    if spells.epidemic:Cast(player) then mint.console.log("Epidemic (AoE)") casted = true end
                end
                
                if not casted then
                    if spells.death_coil:IsKnown() and spells.death_coil:IsReady() then
                        if spells.death_coil:Cast(target) then mint.console.log("Death Coil") casted = true end
                    elseif spells.necrotic_coil:IsKnown() and spells.necrotic_coil:IsReady() then
                        if spells.necrotic_coil:Cast(target) then mint.console.log("Necrotic Coil") casted = true end
                    end
                end
                
                if casted then return true end
            end

            -- 4. Festering Strike — build Lesser Ghoul stacks (use when < 3 stacks)
            if spells.festering_strike:IsKnown() and spells.festering_strike:IsReady() and ghoul_stacks < 3 and runes >= 2 then
                if spells.festering_strike:Cast(target) then mint.console.log("Festering Strike (Build)") return true end
            end

            -- 5. Scourge Strike — spend Lesser Ghoul stacks (use when >= 1 stack)
            if spells.scourge_strike:IsKnown() and spells.scourge_strike:IsReady() and ghoul_stacks >= 1 then
                if spells.scourge_strike:Cast(target) then mint.console.log("Scourge Strike (Spend)") return true end
            end

            -- 6. Filler: dump excess runes on Festering Strike to prevent capping
            if spells.festering_strike:IsKnown() and spells.festering_strike:IsReady() and runes >= 4 then
                if spells.festering_strike:Cast(target) then mint.console.log("Festering Strike (Filler)") return true end
            end

            -- 7. Filler: dump RP on Death Coil
            if rp >= 30 and (spells.death_coil:IsKnown() and spells.death_coil:IsReady() or spells.necrotic_coil:IsKnown() and spells.necrotic_coil:IsReady()) then
                if spells.death_coil:IsKnown() and spells.death_coil:IsReady() then
                    if spells.death_coil:Cast(target) then mint.console.log("Death Coil (Dump)") return true end
                elseif spells.necrotic_coil:IsKnown() and spells.necrotic_coil:IsReady() then
                    if spells.necrotic_coil:Cast(target) then mint.console.log("Necrotic Coil (Dump)") return true end
                end
            end

        -------------------------------------------------------------
        -- San'layn Priority (Hero Talent Active)
        -------------------------------------------------------------
        elseif isSanlayn then
            local isGiftActive = player:FindBuff(auras.gift_of_the_sanlayn):Active()
            local scythe_ready_buff = player:FindBuff(auras.festering_scythe_ready)
            local scythe_ready = scythe_ready_buff and scythe_ready_buff:Active() and scythe_ready_buff:Count() >= 20
            
            if isGiftActive then
                if spells.vampiric_strike:IsKnown() and spells.vampiric_strike:IsReady() then
                    if isAoE and spells.death_and_decay:IsKnown() and spells.death_and_decay:IsReady() and not player:FindBuff(auras.death_and_decay):Active() then
                        spells.death_and_decay:Cast(player)
                    end
                    if spells.vampiric_strike:Cast(target) then mint.console.log("Vampiric Strike (Gift)") return true end
                end
                if spells.soul_reaper:IsKnown() and spells.soul_reaper:IsReady() and target_hp <= 35 then
                    if spells.soul_reaper:Cast(target) then mint.console.log("Soul Reaper (Gift)") return true end
                end
            end

            -- Festering Scythe Debuff maintenance
            if spells.festering_strike:IsKnown() and scythe_ready and target:FindDebuff(auras.festering_scythe_debuff):Remains() <= 3 then
                if spells.festering_strike:Cast(target) then mint.console.log("Festering Scythe Debuff") return true end
            end

            -- Putrefy
            if toggles.cooldowns and profile.auto_putrefy and spells.putrefy:IsKnown() and spells.putrefy:IsReady() then
                if spells.dark_transformation:GetRemainingCD() > 15 or spells.putrefy:GetCharges() == 2 then
                    if spells.putrefy:Cast(player) then mint.console.log("Putrefy") return true end
                end
            end

            -- Ghoul Management Loop (Builder / Spender)
            if ghoul_stacks < 3 and runes >= 2 then
                if spells.festering_strike:IsKnown() and spells.festering_strike:Cast(target) then 
                    mint.console.log("Festering (Sanlayn Build)") return true 
                end
            elseif ghoul_stacks >= 1 or runes >= 4 then
                if isAoE and spells.death_and_decay:IsKnown() and spells.death_and_decay:IsReady() and not player:FindBuff(auras.death_and_decay):Active() then
                    spells.death_and_decay:Cast(player)
                end
                if spells.vampiric_strike:IsKnown() then
                   if spells.vampiric_strike:Cast(target) then mint.console.log("Vampiric Strike") return true end
                elseif spells.scourge_strike:IsKnown() then
                   if spells.scourge_strike:Cast(target) then mint.console.log("Scourge Strike") return true end
                end
            end

            -- Runic Power Spenders
            if isAoE and spells.epidemic:IsKnown() then
                if rp >= 30 and (player:FindBuff(auras.sudden_doom):Active() or runes < 2 or rp > 80) then
                    if spells.epidemic:Cast(player) then mint.console.log("Epidemic (Sanlayn AoE)") return true end
                end
            else
                if rp >= 30 and (player:FindBuff(auras.sudden_doom):Active() or runes < 2 or rp > 80) and spells.death_coil:IsKnown() then
                    if spells.death_coil:Cast(target) then mint.console.log("Death Coil (Sanlayn ST)") return true end
                end
            end

        -------------------------------------------------------------
        -- Rider of the Apocalypse Priority (Hero Talent Active)
        -------------------------------------------------------------
        else
            local forbiddenActive = player:FindBuff(auras.forbidden_knowledge):Active()
            local scythe_ready_buff = player:FindBuff(auras.festering_scythe_ready)
            local scythe_ready = scythe_ready_buff and scythe_ready_buff:Active() and scythe_ready_buff:Count() >= 20

            -- Festering Scythe Debuff maintenance
            if spells.festering_strike:IsKnown() and scythe_ready and target:FindDebuff(auras.festering_scythe_debuff):Remains() <= 3 then
                if spells.festering_strike:Cast(target) then mint.console.log("Festering Scythe Debuff") return true end
            end

            -- Forbidden Knowledge Window
            if forbiddenActive then
                if rp >= 30 and (not isAoE or epidemic_count < 6 or not spells.epidemic:IsKnown()) then
                    if spells.necrotic_coil:IsKnown() then
                        -- Necrotic Coil handles its own ID (1242174) in spells.lua
                        if spells.necrotic_coil:Cast(target) then mint.console.log("Necrotic Coil (FK)") return true end
                    else
                        if spells.death_coil:IsKnown() and spells.death_coil:Cast(target) then mint.console.log("Death Coil (FK)") return true end
                    end
                elseif isAoE and epidemic_count >= 6 and rp >= 30 and spells.epidemic:IsKnown() then
                    if spells.epidemic:Cast(player) then mint.console.log("Epidemic (FK AoE)") return true end
                end
            end

            -- Ghoul Management Loop
            if ghoul_stacks < 3 and runes >= 2 then
                if spells.festering_strike:IsKnown() and spells.festering_strike:Cast(target) then 
                    mint.console.log("Festering (RotA Build)") return true 
                end
            elseif ghoul_stacks >= 1 or runes >= 4 then
                if isAoE and spells.death_and_decay:IsKnown() and spells.death_and_decay:IsReady() and not player:FindBuff(auras.death_and_decay):Active() then
                    spells.death_and_decay:Cast(player)
                end
                if spells.scourge_strike:IsKnown() then 
                    if spells.scourge_strike:Cast(target) then mint.console.log("Scourge Strike (RotA Spend)") return true end
                end
            end

            -- Runic Power Spenders
            if not forbiddenActive then
                if isAoE and spells.epidemic:IsKnown() then
                    if rp >= 30 and (player:FindBuff(auras.sudden_doom):Active() or runes < 2 or rp > 80) then
                        if spells.epidemic:Cast(player) then mint.console.log("Epidemic (RotA AoE)") return true end
                    end
                else
                    if rp >= 30 and (player:FindBuff(auras.sudden_doom):Active() or runes < 2 or rp > 80) and spells.death_coil:IsKnown() then
                        if spells.death_coil:Cast(target) then mint.console.log("Death Coil (RotA ST)") return true end
                    end
                end
            end
        end

	end
end)
