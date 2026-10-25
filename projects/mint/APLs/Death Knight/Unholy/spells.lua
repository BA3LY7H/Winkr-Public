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
local Events  			= mint.EventManager
local Constants  		= mint.Constants
local Totems 			= mint.TotemManager
local SmartTarget 		= mint.SmartTarget
local Settings          = mint.Settings
local TimeToDie         = mint.TimeToDie
local profile           = Settings.profile.deathknight.unholy
local Queue 			= mint.Queue
local Dispel 			= mint.Dispel
local Spell 			= mint.Spell.New
local Item 			    = mint.Item.New
local bin 				= mint.bin
local StopTimer 		= mint.data.StopTimer
local MoveTimer 		= mint.data.MoveTimer
local max_gcd 			= mint.max_gcd
local gcd 				= mint.gcd
local toggles           = mint.data.toggles
local target  			= UnitManager:Get("target")
local player  			= UnitManager:Get("player")
local pet  			    = UnitManager:Get("pet")
local none   			= UnitManager:Get("none")

addon.deathknight.data["Unholy"].vars = {
    IsRider = function()
        return C_ClassTalents.GetActiveHeroTalentSpec() == 51 -- Rider of the Apocalypse
    end,
    IsSanlayn = function()
        return C_ClassTalents.GetActiveHeroTalentSpec() == 52 -- San'layn
    end,
    HasBlightburst = function()
        return IsPlayerSpell(433984) and true or false -- Blightburst talent
    end,
}
local vars = addon.deathknight.data["Unholy"].vars

local spells = {
	auto_attack 				= Spell(6603),
    abomination_limb      = Spell(383269, { targeted = false }),
    antimagic_shell       = Spell(48707, { targeted = false }),
    antimagic_zone        = Spell(51052, { targeted = false }),
    -- apocalypse            = Spell(275699), -- Removed in Midnight
    army_of_the_dead      = Spell(42650, { targeted = false }),
    asphyxiate            = Spell(221562),
    blinding_sleet        = Spell(207167, { targeted = false }),
    chains_of_ice         = Spell(45524),
    dark_command          = Spell(56222),
    dark_transformation   = Spell(63560, { targeted = false }),
    death_and_decay       = Spell(43265, { radius = 12, targeted = false }),
    death_coil            = Spell(47541),
    necrotic_coil         = Spell(1242174), -- Midnight: Replaces Death Coil
    death_strike          = Spell(49998),
    deaths_advance        = Spell(48265, { targeted = false }),
    defile                = Spell(152280, { radius = 12, targeted = false }),
    epidemic              = Spell(207317, { targeted = false }),
    festering_strike      = Spell(85948),
    festering_scythe      = Spell(458128), -- Midnight: Festering Strike override
    icebound_fortitude    = Spell(48792, { targeted = false }),
    lichborne             = Spell(49039, { targeted = false }),
    mind_freeze           = Spell(47528),
    outbreak              = Spell(77575),
    putrefy               = Spell(1247378, { targeted = false }), -- Midnight core AoE
    scourge_strike        = Spell(55090),
    vampiric_strike       = Spell(433895), -- Replaces Scourge Strike (San'layn)
    soul_reaper           = Spell(343294),
    unholy_assault        = Spell(207289),
    vile_contagion        = Spell(390279),
}
addon.deathknight.data["Unholy"].spells = spells

local auras = {
    abomination_limb            = Spell(383269),
    antimagic_shell             = Spell(48707),
    army_of_the_dead            = Spell(42650),
    blood_plague                = Spell(55078),
    dark_transformation         = Spell(63560),
    death_and_decay             = Spell(188290),
    deaths_advance              = Spell(48265),
    defile                      = Spell(152280),
    epidemic                    = Spell(207317),
    festering_scythe_ready      = Spell(458123), -- Stacks up to 20
    festering_scythe_debuff     = Spell(460083), -- Actually applies to enemy
    festering_wound             = Spell(194310),
    frost_fever                 = Spell(55095),
    icebound_fortitude          = Spell(48792),
    lichborne                   = Spell(49039),
    sudden_doom                 = Spell(81340),
    unholy_assault              = Spell(207289),
    virulent_plague             = Spell(191587),
    dread_plague                = Spell(1240996), -- Midnight new disease
    
    -- Hero Talent Auras
    lesser_ghoul_ready          = Spell(1254252), -- Midnight: Lesser Ghoul stacks on player
    forbidden_knowledge         = Spell(1242158), -- Midnight: Necrotic Coil window
    gift_of_the_sanlayn         = Spell(434153), -- San'layn Vampiric Strike window
    infliction_of_sorrow        = Spell(460049), -- Soul Reaper buff in San'layn
    reaping                     = Spell(444505), -- Reaping buff for Soul Reaper
    essence_of_the_blood_queen  = Spell(433925), -- San'layn haste/haste buff
}
addon.deathknight.data["Unholy"].auras = auras


------------------------------
--- Targets
------------------------------
local targets = {}
addon.deathknight.data["Unholy"].targets = targets

-- Melee Enemy (For "auto target" when player target is bad)
targets.melee = UnitManager:CreateSmartUnit("uhdk_melee", function()
    if target:GetExists() and target:IsEnemy() and not target:IsDead() and player:InMelee(target)
    and player:IsFacing(target, 120) then
        return target
    end

	local melee_tar = nil
    local highest_hp = 0

    ObjectManager.enemies:each(function(enemy)
        enemy:Update()
        if enemy.dead then return false end
        if not player:InMelee(enemy) then return false end
        if not player:IsFacing(enemy) then return false end

        if enemy.health > highest_hp then
            highest_hp = enemy.health
            melee_tar = enemy
        end
        return false
    end)

	if melee_tar == nil then return none end
	return melee_tar
end)

-- Mind Freeze
targets.kick = UnitManager:CreateSmartUnit("uhdk_kick", function()
	local closest = nil
	local closest_dist = math.huge

	if not toggles.kicks then return none end

	ObjectManager.combat:loop(function(enemy)
		if enemy.dead then return false end
		if not enemy:IsCastingOrChanneling() then return false end
		if not enemy:IsKickable() then return false end
		if not spells.mind_freeze:IsInRange(enemy) then return false end
        if not player:IsFacing(enemy, 120) then return false end
		local str_key = tostring(enemy:GetCastSpellID())
		if not Settings.profile.kicks[str_key] then return false end
		if not Settings.profile.kicks[str_key].enabled then return false end

		local dist = player:GetDistanceSquared(enemy)
		if dist < closest_dist then
			closest_dist = dist
			closest = enemy
		end
		return false
	end)

	if closest == nil then return none end
	return closest
end)

-- Asphyxiate
targets.stun = UnitManager:CreateSmartUnit("uhdk_stun", function()
	local closest = nil
	local closest_dist = math.huge

	if not toggles.kicks or not profile.stun_toggle then return none end

	ObjectManager.combat:loop(function(enemy)
		if enemy.dead then return false end
		if not enemy:IsCastingOrChanneling() then return false end
		if not enemy:CanStun() then return false end
		if spells.mind_freeze:IsInRange(enemy) and not spells.mind_freeze:IsOnCD() then return false end
		if not spells.asphyxiate:IsInRange(enemy) then return false end
        if not player:IsFacing(enemy, 120) then return false end
		local str_key = tostring(enemy:GetCastSpellID())
		if not Settings.profile.kicks[str_key] then return false end
		if not Settings.profile.kicks[str_key].enabled then return false end

		local dist = player:GetDistanceSquared(enemy)
		if dist < closest_dist then
			closest_dist = dist
			closest = enemy
		end
		return false
	end)

	if closest == nil then return none end
	return closest
end)


-- Return a target without Virulent Plague active
targets.outbreak = UnitManager:CreateSmartUnit("uhdk_outbreak", function()
	local best_tar = nil
    if target and target:GetExists() and not target:FindDebuff(auras.virulent_plague):Active() and player:IsFacing(target) then
        return target
    end

	ObjectManager.combat:loop(function(enemy)
		if enemy.dead then return false end
        if not spells.outbreak:IsInRange(enemy) then return false end
        if not player:IsFacing(enemy, 120) then return false end
        if enemy:FindDebuff(auras.virulent_plague, true):Active() then return false end

        best_tar = enemy
        return true
	end)

	if best_tar == nil then return none end
	return best_tar
end)

-- Festering Wounds highest stack for bursting
targets.aoe_wounds = UnitManager:CreateSmartUnit("uhdk_wounds", function()
	local most_wounds = nil
	local count = 0

	ObjectManager.combat:loop(function(enemy)
		if enemy.dead then return false end
        if not spells.scourge_strike:IsInRange(enemy) then return false end
        if not player:IsFacing(enemy, 120) then return false end
        if not enemy:FindDebuff(auras.festering_wound):Active() then return false end

        local woundCount = enemy:FindDebuff(auras.festering_wound):Count()
        if woundCount > count then
            count = woundCount
            most_wounds = enemy
        end
		return false
	end)

	if most_wounds == nil then return none end
	return most_wounds
end)

------------------------------
--- Spell Callbacks
------------------------------

spells.auto_attack:AddCallback(function(spell)
    if C_Spell.IsCurrentSpell(spell.id) then return false end
    if not target:GetExists() or target:IsFriend() then return false end
    return spell:Cast(target)
end)

spells.mind_freeze:AddCallback(function(spell)
    if not toggles.kicks then return false end
    local kickTarget = targets.kick
    if kickTarget and kickTarget:GetExists() then
        if kickTarget:IsCasting() and kickTarget:GetCastPercent() >= 30 then
            return spell:Cast(kickTarget)
        elseif kickTarget:IsChanneling() and kickTarget:GetTimeSinceStartedCast() >= 0.45 then
            return spell:Cast(kickTarget)
        end
    end
    return false
end)

spells.asphyxiate:AddCallback(function(spell)
    if not toggles.kicks or not profile.stun_toggle then return false end
    local stunTarget = targets.stun
    if stunTarget and stunTarget:GetExists() then
        if stunTarget:IsCasting() and stunTarget:GetCastPercent() >= 30 then
            return spell:Cast(stunTarget)
        elseif stunTarget:IsChanneling() and stunTarget:GetTimeSinceStartedCast() >= 0.45 then
            return spell:Cast(stunTarget)
        end
    end
    return false
end)

spells.death_strike:AddCallback(function(spell)
    if not profile.death_strike then return false end
    if player.hp <= profile.ds_pct then
        local t = target:GetExists() and spells.death_strike:IsInRange(target) and target or targets.melee
        if t and t:GetExists() then
            return spell:Cast(t)
        end
    end
    return false
end)
