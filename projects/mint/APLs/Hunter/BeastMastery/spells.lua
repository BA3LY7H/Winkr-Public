local unlocker, mint, addon = ...

-- ! Mint Locals !--
local UnitManager       = mint.UnitManager
local ObjectManager     = mint.ObjectManager
local FriendManager     = mint.FriendManager
local Events            = mint.EventManager.New()
local Constants         = mint.Constants
local Spell             = mint.Spell.New
local Item              = mint.Item.New
local Notifications     = mint.NotificationManager
local Cache             = mint.Cache.New()
local target            = UnitManager:Get("target")
local player            = UnitManager:Get("player")
local pet        	    = UnitManager:Get("pet")
local pettarget        	= UnitManager:Get("pettarget")
local none              = UnitManager:Get("none")
local bin 			    = mint.bin
local toggles           = mint.data.toggles
local settings          = mint.Settings
local profile           = settings.profile.hunter.beastmastery
local S3				= mint.Constants.TWWS3

local StopTimer = mint.data.StopTimer
local MoveTimer = mint.data.MoveTimer

local function CombatTime()
    local startTime = mint.combatStartTime or 0
    return GetTime() - startTime
end

local spells = {
	auto_shot 					= Spell(75, { ignore_known = true, ignore_range = true }),
	bleak_arrows 				= Spell(467718, { ignore_known = true, ignore_range = true }),
	aspect_of_the_cheetah 		= Spell(186257),
	aspect_of_the_turtle 		= Spell(186265),
	barbed_shot 				= Spell(217200),
	bestial_wrath 				= Spell(19574, { targeted = false }),
	binding_shot 				= Spell(109248),
	bite						= Spell(17253, { pet = true }),
	black_arrow 				= Spell(466930, { ignore_usable = true }), 
	bloodshed 					= Spell(321530),
	bursting_shot 				= Spell(186387),
	camouflage 					= Spell(199483),
	cobra_shot 					= Spell(193455),
	counter_shot 				= Spell(147362),
	call_of_the_wild 			= Spell(359844, { targeted = false }),
	claw 						= Spell(16827, { pet = true }),
	dash 						= Spell(61684, { pet = true }),
	dire_beast 					= Spell(120679),
	disengage 					= Spell(781),
	exhilaration 				= Spell(109304, { targeted = false }),
	explosive_shot 				= Spell(212431),
	feign_death 				= Spell(5384),
	fortitude_of_the_bear		= Spell(272679, { targeted = false }),
	freezing_trap 				= Spell(187650),
	hunters_mark 				= Spell(257284),
	implosive_trap 				= Spell(462031),
	intimidation 				= Spell(19577, { pet = true }),
	kill_command 				= Spell(34026, { pet = true }),
	kill_shot 					= Spell(53351), 
	mend_pet					= Spell(136, { beneficial = true }),
	misdirection				= Spell(34477),
	multishot 					= Spell(2643),
	revive_pet					= Spell(982),
	primal_rage 				= Spell(272678),
	smack						= Spell(49966, { pet = true }),
	survival_of_the_fittest 	= Spell(264735),
	tar_trap 					= Spell(187698),
	tranquilizing_shot 			= Spell(19801),
	wing_clip 					= Spell(195645),
}

local auras = {
    alter_time          = Spell(342246),
	howl_boar 			= Spell(472324),
	howl_bear			= Spell(472325),
	howl_wyvern 		= Spell(471878),
    howl_cd             = Spell(471877),
	huntmasters_call 	= Spell(459731),
	hogstrider 			= Spell(472640),
	beast_cleave 		= Spell(268877),
	barbed_shot 		= Spell(217200),
	blighted_quiver		= Spell(1236975),
	latent_energy 		= Spell(1239675),
    lead_from_the_front = Spell(472743),
	hunters_mark		= Spell(257284),
	bestial_wrath		= Spell(19574),
	deathblow			= Spell(378770),
	call_of_the_wild 	= Spell(359844),
	thrill_of_the_hunt	= Spell(257946),
	withering_fire		= Spell(466991),
}

local HowlReady = mint.List:New({
	auras.howl_boar,
	auras.howl_bear,
	auras.howl_wyvern,
})

local talents = {
	huntmasters_call 	= Spell(459730),
	thundering_hooves 	= Spell(459693),
	dire_cleave 		= Spell(1217524),
	bloody_frenzy 		= Spell(407412),
	bloodshed			= Spell(321530),
	beast_cleave 		= Spell(115939),
	killer_instinct 	= Spell(273887),
    multishot           = Spell(2643),
	emergency_salve		= Spell(459517),
	call_of_the_wild	= Spell(359844),
}


local items = {
	house_of_cards 				= Item(230027),
	signet 						= Item(219308, { use_name = true }),
    healing_potion              = Item(244838),
    healthstone                 = Item(5512),
    tempered_potion             = Item(212264),
}

-- * Kick blacklist
local blacklist = {
    -- Ara'kara
    [215968] = "Black Blood",
    [215826] = "Black Blood"
}

local targets = {}

-- * ================================ *
-- * Auto Shot Tracking
-- * ================================ *

local auto_shot_active = false
Events:RegisterWoWEvent("START_AUTOREPEAT_SPELL", function()
	auto_shot_active = true
end)

Events:RegisterWoWEvent("STOP_AUTOREPEAT_SPELL", function()
	auto_shot_active = false
end)

-- * ================================ *
-- * Helper Functions
-- * ================================ *

local function isDarkRanger()
	if UnitLevel("player") <= 70 then return false end
	return C_ClassTalents.GetActiveHeroTalentSpec() == 44
end

local function isPackLeader()
	if UnitLevel("player") <= 70 then return false end
	return C_ClassTalents.GetActiveHeroTalentSpec() == 43
end

local function shouldCleave()
    if not target:GetExists() then
        return false
    end

    return IsPlayerSpell(talents.beast_cleave.id) and target:GetEnemies(10) > 1 or target:GetEnemies(10) > 2
end

local function CanUseBlackArrow()
	if not targets.black_arrow:GetExists() then
		return false
	end
	
	if spells.black_arrow:IsOnCD() then
		return false
	end

	if spells.kill_shot:IsOnCD() then
		return false
	end

	if player:FindBuff(auras.deathblow):Active() then
		return true
	end

	if targets.black_arrow:GetExists() then
		return true
	end

	return false
end

local function wfTickTime()
	local buff = player:FindBuff(auras.withering_fire)

	-- If we don't have the buff, return a big number (irrelevant).
	if not buff:Active() then
		return 6666
	end

	local rem = buff:Remains()

	-- Tick breakpoints in seconds.
	local ticks = { 16, 12, 8, 4, 0 }

	for i = 1, #ticks do
		-- If remaining time is above this tick mark,
		-- the next tick will happen when rem crosses down to it.
		if rem > ticks[i] then
			return rem - ticks[i]
		end
	end

	return 0
end

local function hasNetherprism()
	for _, slot in ipairs({13, 14}) do
		local item = GetInventoryItemID("player", slot)

		if item and item == 242396 then
			return true
		end
	end

	return false
end

local function getPrismSlot()
	for _, slot in ipairs({13, 14}) do
		local item = GetInventoryItemID("player", slot)

		if item and item == 242396 then
			return slot
		end
	end

	return false
end

local helpers = {
    shouldCleave = shouldCleave,
	isDarkRanger = isDarkRanger,
	isPackLeader = isPackLeader,
	blackArrow = CanUseBlackArrow,
	wfTick = wfTickTime,
	hasPrism = hasNetherprism,
	prismSlot = getPrismSlot,
}

-- * ================================ *
-- * Interrupt Helpers
-- * ================================ *
local cast_percent
local channel_time

local function NewPercent()
	local new = math.random(27, 55)

	if new == cast_percent then
		return NewPercent()
	end

	cast_percent = new
	return cast_percent
end

local function NewChannelTime()
	local new = math.random(70, 90)

	new = new / 100

	if new == channel_time then
		return NewChannelTime()
	end

	channel_time = new
	return channel_time
end

cast_percent = NewPercent()
channel_time = NewChannelTime()


-- * ================================ *
-- * Smart Units
-- * ================================ *

-- ================================
-- Black Arrow AoE “Bleak Powder” Smart Unit (uses your IsInCone)
-- ================================

local BA_CONE_RADIUS = 8          -- yards (Bleak Powder radius)
local BA_CONE_FULL_ANGLE = 45     -- degrees (tweak if in-game arc is wider/narrower)
local function atan2(y, x) return math.atan2 and math.atan2(y, x) or math.atan(y / x) end

-- rotation (radians) for cone pointing "away from player" from candidate position
local function behindRotationFrom(cpos, ppos)
    -- dir away from player = (candidate - player)
    local dx, dy = (cpos.x - ppos.x), (cpos.y - ppos.y)
    return math.atan2(dy, dx)   -- rotation for your cone struct
end

local scores = {}

local function bleakPowderScore(candidate)
    local hits, hpSum = 0, 0

    local cpos = candidate:GetPosition()
    local rot  = behindRotationFrom(cpos, player:GetPosition())

    local cone = {
        origin   = cpos,                 -- your IsInCone expects origin, rotation, angle, radius
        rotation = rot,                  -- radians
        angle    = BA_CONE_FULL_ANGLE,   -- degrees
        radius   = BA_CONE_RADIUS,       -- yards
    }

    ObjectManager.combat:loop(function(other)
        if other.guid == candidate.guid then return false end
        if other.dead or (not other.can_attack) then return false end
        if not player:HasLos(other) then return false end

        -- Count if inside the cone behind candidate
        if other:IsInCone(cone) then
            hits  = hits + 1
            hpSum = hpSum + (other.health or 0)
        end
        return false
    end)

	scores[candidate.guid] = { hits, hpSum }

    return hits, hpSum
end

-- Prefer: most hits → greater HP sum behind → candidate HP
targets.black_arrow_aoe = UnitManager:CreateSmartUnit("bm_black_arrow_aoe", function()
    local best, bestHits, bestHpSum, bestSelfHp = nil, -1, -1, -1

    ObjectManager.combat:loop(function(enemy)
        enemy:Update()
        if enemy.dead or not enemy:IsEnemy() then return false end
        if not spells.black_arrow:IsInRange(enemy) then return false end
        if not player:HasLos(enemy) then return false end

        local hits, hpSum = bleakPowderScore(enemy)
        local eHp = enemy:GetHealth() or 0

        if (hits > bestHits)
        or (hits == bestHits and hpSum > bestHpSum)
        or (hits == bestHits and hpSum == bestHpSum and eHp > bestSelfHp)
        then
            best, bestHits, bestHpSum, bestSelfHp = enemy, hits, hpSum, eHp
        end

        return false
    end)

    -- Sensible fallback: keep current target if BA is usable
    if best then return best end

    -- if target:GetExists() and spells.black_arrow:IsUsable() then return target end

    return none
end)

-- local Draw = mint.Draw:New()

-- Draw:Sync(function(draw)
-- 	ObjectManager.combat:loop(function(enemy)
-- 		if scores[enemy.guid] then
-- 			local pos = enemy:GetPosition()
-- 			if pos:IsValid() then
-- 				draw:SetColor(255, 255, 255)
-- 				local hits = scores[enemy.guid][1] 
-- 				local hpSum = scores[enemy.guid][2] 
-- 				draw:Text(hits .. " | " .. hpSum, "GameFontNormal", pos.x, pos.y, pos.z + 2)
-- 			end
-- 		end
-- 	end)
-- end)

-- Draw:Enable()


-- $ ================================ $
-- $ Barbed Shot Target
-- $ ================================ $
targets.barbed_shot = UnitManager:CreateSmartUnit("bm_barbed_shot", function()
	-- Always maintain the buff on our primary target before spreading
	if target:GetExists() and target:IsEnemy() and target:FindDebuff(auras.barbed_shot, true):Inactive() then
		return target
	end

	local highest_hp = 0
	local highest = nil
	local lowest_dur = math.huge
	local lowest = nil
	
	ObjectManager.combat:loop(function(enemy)
        enemy:Update()
		if (not IsInRaid()) and enemy:GetHP() > 99 then return false end
		if enemy.dead then return false end
		-- if not player:IsFriendTanking(enemy) and not player:IsTanking(enemy) then return false end
		if not player:IsFacing(enemy) then return false end
		if not spells.barbed_shot:IsInRange(enemy) then return false end
		if not player:HasLos(enemy) then return false end

		local debuff = enemy:FindDebuff(auras.barbed_shot, true)

		if not debuff:Active() then
			local health = enemy:GetHealth()

			if health > highest_hp then
				highest_hp = health
				highest = enemy
				return false
			end
		end

		if debuff:Active() then
			local remains = debuff:Remains()

			if remains < lowest_dur then
				lowest_dur = remains
				lowest = enemy
			end
		end

		return false
	end)

	if highest then
		return highest
	elseif lowest then
		return lowest
	else
		return none
	end
end)

-- $ ================================ $
-- $ Bloodshed Target
-- $ ================================ $
-- Target our current target unless it has a TTD < 12, in which case target the unit with highest HP.
-- It is important to prioritize a unit in melee range with our pet if we're not using our target.
targets.bloodshed = UnitManager:CreateSmartUnit("bm_bloodshed", function()
    if not pet:GetExists() then return none end

	-- If target is fine (TTD > 12) and we can actually cast it, use target.
	if target:IsEnemy() and target:TimeToDie() > 12 then
		return target
	end

	-- Otherwise, look for a better spread target:
	local best_melee, best_melee_hp = nil, 0
	local best_any,   best_any_hp   = nil, 0

	ObjectManager.combat:loop(function(enemy)
		enemy:Update()
		if enemy.dead then return false end
		if not enemy:IsEnemy() then return false end
		if not spells.bloodshed:IsInRange(enemy) then return false end
		if not player:HasLos(enemy) then return false end

		local hp = enemy:GetHealth()

		-- Prefer a unit in pet melee if possible (≈ 8yds)
		if pet:InMelee(enemy)then
			if hp > best_melee_hp then
				best_melee_hp = hp
				best_melee = enemy
			end
		else
			if hp > best_any_hp then
				best_any_hp = hp
				best_any = enemy
			end
		end

		return false
	end)

	-- Priority: pet-melee highest HP → any highest HP → fallback to target if usable → none
	if best_melee then
		return best_melee
	elseif best_any then
		return best_any
	elseif target:IsEnemy() then
		return target
	end

	return none
end)

-- $ ================================ $
-- $ Black Arrow Target
-- $ ================================ $
targets.black_arrow = UnitManager:CreateSmartUnit("bmBlackArrow", function()
	-- Always maintain the buff on our primary target before spreading
	if target:GetExists() and target:IsEnemy() then
		if spells.black_arrow:IsUsable() then
			return target
		end
		-- if player:FindBuff(auras.deathblow):Active() then return target end
		-- local hp = target:GetHP()
		-- if hp < 20 then return target end
		-- if hp > 80 then return target end
	end

	local arrowTar = nil
	
	ObjectManager.combat:loop(function(enemy)
        enemy:Update()
		if enemy.dead then return false end
		local hp = enemy:GetHP()
		if hp > 99.5 then return false end -- paranoid about pulling ooc mobs
		if not player:IsFacing(enemy) then return false end
		if not spells.black_arrow:IsInRange(enemy) then return false end
		if not player:HasLos(enemy) then return false end

		if hp > 80 then
			arrowTar = enemy
			return true
		end

		if hp < 20 then
			arrowTar = enemy
			return true
		end

		return false
	end)

	return arrowTar or none
end)

-- $ ================================ $
-- $ Interrupt Target
-- $ ================================ $
targets.counter_shot = UnitManager:CreateSmartUnit("bm_counterShot", function()
	local kickTarget = nil
	local distance = -1

	if not toggles.kicks then
		return none
	end

	ObjectManager.combat:loop(function(enemy)
		if enemy.dead then return false end
		if not enemy:IsCastingOrChanneling() then return false end
		if not enemy:IsKickable() then return false end
		if not spells.counter_shot:IsInRange(enemy) then return false end
        if not player:IsFacing(enemy) then return false end

		-- Check user settings
		local str_key = tostring(enemy:GetCastSpellID())
		if not settings.profile.kicks[str_key] then return false end
		if not settings.profile.kicks[str_key].enabled then return false end

		if enemy:IsCasting() then
			if enemy:GetCastPercent() >= cast_percent then
				local dist = player:GetDistanceSquared(enemy)
				if dist > distance then
					distance = dist
					kickTarget = enemy
				end
			end
		end

		if enemy:IsChanneling() then
			if enemy:GetTimeSinceStartedCast() >= channel_time then
				local dist = player:GetDistanceSquared(enemy)
				if dist > distance then
					distance = dist
					kickTarget = enemy
				end
			end
		end

		return false
	end)

	return kickTarget or none
end)

-- $ ================================ $
-- $ Purge Target
-- $ ================================ $
local dispels = S3.sootheList:concat(S3.purgeList)
targets.tranq_shot = UnitManager:CreateSmartUnit("bm_tranqShot", function()
    if not toggles.purges then return none end

	local tranqTarget = nil
	local remains = -1

	ObjectManager.combat:loop(function(enemy)
        enemy:Update()
		if enemy.dead then return false end
		if not spells.tranquilizing_shot:IsInRange(enemy) then return false end
		if not player:HasLos(enemy) then return false end

		local aura = enemy:FindLongestBuffFromList(dispels)

		if aura:Inactive() then
			return false
		end

		local dur = aura:Remains()
		if dur > remains then
			remains = dur
			tranqTarget = enemy
		end
		
		return false
	end)

	return tranqTarget or none
end)

-- $ ================================ $
-- $ Misdirect Target
-- $ ================================ $
targets.misdirect = UnitManager:CreateSmartUnit("bm_misdirect", function()
	if IsInRaid() then return none end
	local mdTarget = nil

	FriendManager:Loop(function(friend)
		if friend:IsTank() and spells.misdirection:IsInRange(friend) then
			mdTarget = friend
			return true
		end

		return false
	end)

	return mdTarget or none
end)

-- $ ================================ $
-- $ Hunter's Mark Target
-- $ ================================ $
targets.hunters_mark = UnitManager:CreateSmartUnit("bm_huntersMark", function()
	if IsInRaid() then return none end
	local markTarget = nil

	ObjectManager.combat:loop(function(enemy)
		if enemy.dead then return false end
		if enemy:GetHP() <= 80 then return false end

	end)

	return markTarget or none
end)

-- * ================================ *
-- * Item Callbacks
-- * ================================ *

------------------------------
--- Healing Potion
------------------------------
items.healing_potion:AddCallback(function(item)
    if not item:IsEquippedAndUsable() then return false end

	if not profile.potionToggle then
		return false
	end

    if player:GetHP() > profile.potionPct then
        return false
    end

    return item:Use(none)
end)

------------------------------
--- Healthstone
------------------------------
items.healthstone:AddCallback(function(item)
    if not item:IsEquippedAndUsable() then return false end

	if not profile.stoneToggle then
		return false
	end

    if player:GetHP() > profile.stonePct then
        return false
    end

    return item:Use(none)
end)

------------------------------
--- Tempered Potion
------------------------------
-- # Use your potion during Call of the Wild, or (without CotW) during Bestial Wrath, or if the fight ends soon (<31s).
-- actions.cds+=/potion,if=buff.call_of_the_wild.up|!talent.call_of_the_wild&buff.bestial_wrath.up|fight_remains<31
items.tempered_potion:AddCallback(function(item)
    if not item:IsEquippedAndUsable() then return false end

	if IsInRaid() and mint.TimeToDie:ActiveFightRemains() < 31 then
		return item:Use(none)
	end

	if player:FindBuff(auras.call_of_the_wild):Active() then
		return item:Use(none)
	end

	if (not IsPlayerSpell(talents.call_of_the_wild.id)) and player:FindBuff(auras.bestial_wrath):Active() then
		return item:Use(none)
	end 

    return false
end)

------------------------------
--- House of Cards
------------------------------

-- talent.call_of_the_wild&(prev_gcd.1.call_of_the_wild)|talent.bloodshed&(prev_gcd.1.bloodshed)|(!talent.call_of_the_wild&!talent.bloodshed)&(buff.bestial_wrath.up|cooldown.bestial_wrath.remains_guess<5)
items.house_of_cards:AddCallback(function(item)
	if not target:GetExists() or target:IsFriend() then
		return false
	end

	if IsPlayerSpell(spells.call_of_the_wild.id) and spells.call_of_the_wild:TimeSinceLastCast() < 2 then
		return item:Use(player)
	end

	-- if IsPlayerSpell(spells.bloodshed.id) and spells.bloodshed:TimeSinceLastCast() < 2 then
	-- 	return item:Use(player)
	-- end

	if not IsPlayerSpell(spells.call_of_the_wild.id) and not IsPlayerSpell(spells.bloodshed.id) then
		if player:FindBuff(spells.bestial_wrath):Active() or spells.bestial_wrath:GetRemainingCD() < 5 then
			return item:Use(player)
		end
	end

	return false
end)


items.signet:AddCallback(function(item)
	if not target:GetExists() or target:IsFriend() then
		return false
	end

	if IsPlayerSpell(spells.call_of_the_wild.id) and spells.call_of_the_wild:TimeSinceLastCast() < 2 then
		return item:Use(player)
	end

	-- if IsPlayerSpell(spells.bloodshed.id) and spells.bloodshed:TimeSinceLastCast() < 2 then
	-- 	return item:Use(player)
	-- end

	-- if not IsPlayerSpell(spells.call_of_the_wild.id) and not IsPlayerSpell(spells.bloodshed.id) then
	-- 	if player:FindBuff(spells.bestial_wrath):Active() or spells.bestial_wrath:GetRemainingCD() < 5 then
	-- 		return item:Use(player)
	-- 	end
	-- end

	if player:FindBuff(spells.bestial_wrath):Active() or spells.bestial_wrath:GetRemainingCD() < 5 then
		return item:Use(player)
	end

	return false
end)

-- * ================================ *
-- * Pet Abilities
-- * ================================ *
spells.bite:AddCallback(function(spell)
	if not GetPetActionsUsable() then return end
	if not pet:GetExists() then return false end
	if pet:IsDead() then return false end
	if not target:GetExists() or target:IsFriend() then return false end
	if not spells.bite:IsInRange(target) then return false end

	return spell:CastNotify(target, "Bite (Pet)", 3)
end)

spells.claw:AddCallback(function(spell)
	if not GetPetActionsUsable() then return end
	if not pet:GetExists() then return false end
	if pet:IsDead() then return false end
	if not target:GetExists() or target:IsFriend() then return false end
	if not spells.claw:IsInRange(target) then return false end

	return spell:CastNotify(target, "Claw (Pet)", 3)
end)

spells.smack:AddCallback(function(spell)
	if not GetPetActionsUsable() then return end
	if not pet:GetExists() then return false end
	if pet:IsDead() then return false end
	if not target:GetExists() or target:IsFriend() then return false end
	if not spells.smack:IsInRange(target) then return false end

	return spell:CastNotify(target, "Smack (Pet)", 3)
end)

spells.dash:AddCallback(function(spell)
	if not GetPetActionsUsable() then return end
	if not pet:GetExists() then return false end
	if pet:IsDead() then return false end
	if not pettarget:GetExists() or pettarget:IsFriend() then return false end
	if pet:IsWithin(10, pettarget) then return false end

	return spell:CastNotify(pet, "Dash (Pet out of range)", 3)
end)

-- * ================================ *
-- * Spell Callbacks
-- * ================================ *
------------------------------
--- Auto Shot
------------------------------
spells.auto_shot:AddCallback(function(spell)
	if auto_shot_active then
		return false
	end
	
	if not target:GetExists() or target:IsFriend() then
		return false
	end

	StartAttack()
	return true
end)

------------------------------
--- Aspect of the Turtle
------------------------------
spells.aspect_of_the_turtle:AddCallback(function(spell)

end)

------------------------------
--- Barbed Shot
------------------------------

-- # PL #2. Barbed Shot (spread) if near cap OR (in AoE) have as many charges as Kill Command, CotW is ready, or Howl summon soon with quick recharge.
-- barbed_shot,if=full_recharge_time<gcd|charges_fractional>=cooldown.kill_command.charges_fractional|talent.call_of_the_wild&cooldown.call_of_the_wild.ready|howl_summon.ready&full_recharge_time<8
spells.barbed_shot:AddCallback(function(spell)
	if not target:GetExists() or target:IsFriend()
	or not targets.barbed_shot:GetExists() then
		return false
	end

    -- full_recharge_time<gcd
    if spell:GetFullRechargeTime() < (mint.max_gcd * 1.5) then
		return spell:Cast(targets.barbed_shot)
	end

    -- charges_fractional>=cooldown.kill_command.charges_fractional
    if spell:GetChargesFractional() >= spells.kill_command:GetChargesFractional() then
		return spell:Cast(targets.barbed_shot)
	end

    -- talent.call_of_the_wild&cooldown.call_of_the_wild.ready
    if IsPlayerSpell(spells.call_of_the_wild.id) and spells.call_of_the_wild.ready then
		return spell:Cast(targets.barbed_shot)
	end
    
    -- howl_summon.ready&full_recharge_time<8
    if player:FindAnyBuff(HowlReady):Active() and spell:GetFullRechargeTime() < 8 then
		return spell:Cast(targets.barbed_shot)
	end

    return false
end)

-- # PL & DR #10. ST: Keep Barbed Shot rolling on target (reapply/extend as needed).
-- barbed_shot,if=buff.withering_fire.tick_time_remains>0.5&cooldown.black_arrow.remains>0.5
spells.barbed_shot:AddCallback("ST Fallback", function(spell)
	if not target:GetExists() or target:IsFriend()
	or not targets.barbed_shot:GetExists() then
		return false
	end

    if shouldCleave() then
        return false
    end

	if isDarkRanger() then
		if player:FindBuff(auras.withering_fire):Inactive() then
			return spell:CastNotify(targets.barbed_shot, "ST Fallback (No WF)", 3)
		end

		if helpers.wfTick() <= 0.5 then
			return false
		end

		if targets.black_arrow:GetExists() and spells.black_arrow:IsOnCD() and spells.black_arrow:GetRemainingCD() <= 0.5 then
			return false
		end

		return spell:CastNotify(targets.barbed_shot, "ST Fallback", 3)
	end

    return spell:Cast(targets.barbed_shot)
end)


-- # DR #3. Barbed shot to spread, avoiding withering fire tick overlap.
-- barbed_shot,if=buff.withering_fire.tick_time_remains>0.5
-- &cooldown.black_arrow.remains>0.5
-- &(full_recharge_time<gcd|cooldown.bestial_wrath.remains<12&buff.withering_fire.up)
spells.barbed_shot:AddCallback("DR: Cleave", function(spell)
	if not target:GetExists() or target:IsFriend()
	or not targets.barbed_shot:GetExists() then
		return false
	end

	-- We don't use this at this priority when in single target I suppose
	if not shouldCleave() then
		return false
	end

	if player:FindBuff(auras.thrill_of_the_hunt):Remains() <= (1.5 * mint.max_gcd) then
		return spell:CastNotify(targets.barbed_shot, "Maintain ToTH", 3)
	end

	if shouldCleave() and spell:GetFullRechargeTime() < (mint.max_gcd * 1.15) then
		return spell:CastNotify(targets.barbed_shot, "Avoid Cap (Cleave)", 3)
	end

    return spell:CastNotify(targets.barbed_shot, "Spread Bleed", 3)
end)

-- # DR #8. Cleave: Barbed shot if you have charges >= kill command charges
-- barbed_shot,if=buff.withering_fire.tick_time_remains>0.5&cooldown.black_arrow.remains>0.5|buff.withering_fire.down
spells.barbed_shot:AddCallback("Dark Ranger", function(spell)
	if not target:GetExists() or target:IsFriend()
	or not targets.barbed_shot:GetExists() then
		return false
	end

	if player:FindBuff(auras.withering_fire):Inactive() then
		return spell:CastNotify(targets.barbed_shot, "Dark Ranger (No WF)", 3)
	end

	if helpers.wfTick() <= 0.5 then
		return false
	end

	if targets.black_arrow:GetExists() and spells.black_arrow:IsOnCD() and spells.black_arrow:GetRemainingCD() <= 0.5 then
		return false
	end

	return spell:CastNotify(targets.barbed_shot, "ST Fallback", 3)
end)

------------------------------
--- Bestial Wrath
------------------------------
-- # PL #1. Beastial Wrath when aligning with Lead from the Front/Howl, or without TWW S3 4P, or with Multishot in AoE
-- mt=buff.howl_of_the_pack_leader_cooldown.remains-buff.lead_from_the_front.duration<buff.lead_from_the_front.duration%gcd*0.5|!set_bonus.tww3_4pc|talent.multishot (and AoE)
spells.bestial_wrath:AddCallback(function(spell)
    if not toggles.cooldowns then return false end
	if not target:GetExists() or target:IsFriend() then return false end

    -- Need to add TTD
    if mint.TimeToDie.ActiveFightRemains() < 10 then
        return false
    end

    if IsPlayerSpell(talents.multishot.id) and shouldCleave() then
		return spell:CastNotify(player, "Bestial Wrath (Cleave)", 3)
    end

	if not player:Has4p() then
		return spell:CastNotify(player, "Bestial Wrath (No 4p)", 3)
    end

	-- If we have no HoTP buff, return false (we aren't in combat yet?)
	if not player:FindBuff(auras.howl_cd):Active() then
		return false
	end

	local howlRemains = player:FindAnyBuffByID(HowlReady):Active() and 0 or (player:FindOwnBuffByID(auras.howl_cd.id):Remains())
	if howlRemains - 12 < 12 / mint.max_gcd * 0.45 then
		return spell:CastNotify(player, "Bestial Wrath (Double Stampede)", 3)
	end

	return false
end)


-- # DR #2. Bestial Wrath unless Call of the Wild is coming very soon, or if you don’t have CotW.
-- bestial_wrath,if=cooldown.call_of_the_wild.remains>25|!talent.call_of_the_wild
spells.bestial_wrath:AddCallback("Dark Ranger", function(spell)
    if not toggles.cooldowns then return false end
	if not target:GetExists() or target:IsFriend() then return false end

    -- We still send CDs with low TTD in raid
    if (not IsInRaid()) and mint.TimeToDie.ActiveFightRemains() < 10 then
        return false
    end

	if not IsPlayerSpell(talents.call_of_the_wild.id) then
		return spell:CastNotify(player, "Bestial Wrath", 3)
	end

	if spells.call_of_the_wild:GetRemainingCD() > 30 then
		return spell:CastNotify(player, "Bestial Wrath", 3)
	end

	return false
end)

------------------------------
--- Bloodshed
------------------------------
-- # 4. Use bloodshed on cooldown.
spells.bloodshed:AddCallback(function(spell)
    if not target:GetExists() or target:IsFriend() then return false end
    if not targets.bloodshed:GetExists() then return false end

	-- We still send CDs with low TTD in raid
	if isDarkRanger() then
		if not toggles.cooldowns then
			return false
		end

		if (not IsInRaid()) and mint.TimeToDie.ActiveFightRemains() < 15 then
			return false
		end
	end

	return spell:CastNotify(targets.bloodshed, "Bloodshed", 3)
end)

------------------------------
--- Bursting Shot
------------------------------
spells.bursting_shot:AddCallback(function(spell)

end)

------------------------------
--- Call of the Wild
------------------------------
spells.call_of_the_wild:AddCallback("ST", function(spell)
    if not toggles.cooldowns then
        return false
    end

    if shouldCleave() then 
        return false 
    end

	if not target:GetExists() or target:IsFriend() then
		return false
    end

    -- Need to add TTD
    if mint.TimeToDie.ActiveFightRemains() < 15 then
        return false
    end

	return spell:CastNotify(target, "Call of the Wild", 3)
end)

spells.call_of_the_wild:AddCallback("Cleave", function(spell)
    if not toggles.cooldowns then
        return false
    end

    if not shouldCleave() then 
        return false 
    end

	if not target:GetExists() or target:IsFriend() then
		return false
    end

    -- Need to add TTD
    if mint.TimeToDie.ActiveFightRemains() < 15 then
        return false
    end

	return spell:CastNotify(target, "Call of the Wild", 3)
end)

spells.call_of_the_wild:AddCallback(function(spell)
    if not toggles.cooldowns then
        return false
    end

	if not target:GetExists() or target:IsFriend() then
		return false
    end

    -- Need to add TTD
    if mint.TimeToDie.ActiveFightRemains() < 15 then
        return false
    end

	return spell:CastNotify(target, "Call of the Wild", 3)
end)

------------------------------
--- Cobra Shot
------------------------------
-- # 11. Cobra Shot (ST just dump). In Cleave: Dump with Cobra Shot if you’re about to cap focus, have high Hogstrider stacks, or Multishot isn’t talented.
-- ST: Just send
-- Cleave: cobra_shot,if=focus.time_to_max<gcd*2|buff.hogstrider.stack>3|!talent.multishot
spells.cobra_shot:AddCallback(function(spell)
	if not target:GetExists() or target:IsFriend() then
		return false
	end

	if isDarkRanger() then
		if player:FindBuff(auras.withering_fire):Active() then
			return false
		end
	end

    if not shouldCleave() then
		return spell:CastNotify(target, "Filler (ST)", 3)
    end

    if player:TimeToMaxFocus() < (mint.max_gcd * 2) then
        return spell:CastNotify(target, "Filler (Cleave)", 3)
    end

    if player:FindBuff(auras.hogstrider):Count() > 3 then
		return spell:CastNotify(target, "Filler (Hogstrider)", 3)
	end

    if isPackLeader() and not IsPlayerSpell(talents.multishot.id) then
        return spell:CastNotify(target, "Filler (Cleave)", 3)
    end

	return false
end)

------------------------------
--- Counter Shot
------------------------------
spells.counter_shot:AddCallback(function(spell)
	if not mint.data.toggles.kicks then return false end
	if not targets.counter_shot:GetExists() then return false end

	if spell:CastNotify(targets.counter_shot, "Interrupting", 3) then
		cast_percent = NewPercent()
		channel_time = NewChannelTime()
		return true
	end
end)

------------------------------
--- Exhilaration
------------------------------
spells.exhilaration:AddCallback(function(spell)
	if not toggles.defensives then return false end

	if not profile.exhilToggle then
		return false
	end

	if player:GetHP() > profile.exhilPct then
		return false
	end

	return spell:CastNotify(player, "Self Healing", 3)
end)

spells.exhilaration:AddCallback("Emergency", function(spell)
	if not toggles.defensives then return false end

	if not profile.exhilToggle then
		return false
	end

	if player:GetHP() > (profile.exhilPct / 2) then
		return false
	end

	return spell:CastNotify(player, "Self Healing (Emergency)", 3)
end)

------------------------------
--- Explosive Shot
------------------------------
-- # 7. In cleave: Use Explosive Shot when Thundering Hooves is talented.
-- explosive_shot,if=talent.thundering_hooves
spells.explosive_shot:AddCallback(function(spell)
	if not target:GetExists() or target:IsFriend() then
		return false
	end

    if not shouldCleave() then
        return false
    end

	if not IsPlayerSpell(talents.thundering_hooves.id) then
		return false
	end

	return spell:CastNotify(target, "Explosive Shot", 3)
end)

-- # DR #12. In Cleave: Explosive Shot if literally nothing else available.
-- explosive_shot,if=talent.thundering_hooves
spells.explosive_shot:AddCallback("DR: Filler", function(spell)
	if not target:GetExists() or target:IsFriend() then
		return false
	end

    if not shouldCleave() then
        return false
    end

	return spell:CastNotify(target, "Explosive Shot (Filler)", 3)
end)


------------------------------
--- Feign Death
------------------------------
-- affix debuff
local affixDebuff = Spell(440313)
local randRemains = math.random(3, 18)
spells.feign_death:AddCallback("Affix", function(spell)
	if not IsPlayerSpell(talents.emergency_salve.id) then return false end

	local debuff = player:FindDebuff(affixDebuff)
	if debuff:Active() and debuff:Remains() <= randRemains then
		if spell:CastNotify(player, "Cleanse Affix") then
			randRemains = math.random(3, 18)
			return true
		end
	end
end)

------------------------------
--- Fortitude of the Bear
------------------------------
spells.fortitude_of_the_bear:AddCallback(function(spell)
	if not toggles.defensives then return false end

	if not profile.fotbToggle then
		return false
	end

    if player:GetHP() > profile.fotbPct then
        return false
    end

	return spell:CastNotify(player, "Self Healing", 3)
end)

spells.fortitude_of_the_bear:AddCallback("Emergency", function(spell)
	if not toggles.defensives then return false end

	if player:GetHP() > profile.fortDanger then
		return false
	end

	return spell:CastNotify(player, "Self Healing (Emergency)", 3)
end)


------------------------------
--- Freezing Trap
------------------------------
spells.freezing_trap:AddCallback(function(spell)

end)

------------------------------
--- Hunter's Mark
------------------------------
-- spells.hunters_mark:CastableIf(function (self)
--     return self:IsReady() and not Player:IsCastingOrChanneling() and SmartTarget:Exists()
-- end):SetTarget(SmartTarget)

-- utilAPL:AddSpell(spells.hunters_mark, function(self)
--     return SmartTarget:GetAuras():FindMy(self):IsDown() and SmartTarget:GetHP() > 80 and SmartTarget:GetMaxHealth() > 5000000
-- end)

spells.hunters_mark:AddCallback(function(spell)

end)

------------------------------
--- Implosive Trap
------------------------------
spells.implosive_trap:AddCallback(function(spell)

end)

------------------------------
--- Intimidation
------------------------------
spells.intimidation:AddCallback(function(spell)

end)

------------------------------
--- Kill Command
------------------------------
-- # PL #8. In cleave: Use Kill Command on cooldown.
-- # PL #9. ST: Use Kill Command, but delay slightly if it would desync with Barbed Shot windows or Lead from the Front micro-timing.
-- kill_command,if=charges_fractional>=cooldown.barbed_shot.charges_fractional&!(buff.lead_from_the_front.remains>gcd&buff.lead_from_the_front.remains<gcd*2&!howl_summon.ready&full_recharge_time>gcd)
-- aoe: on cd
spells.kill_command:AddCallback(function(spell)
	if not target:GetExists() or target:IsFriend() then
		return false
	end

    -- Use on CD in AoE
    if shouldCleave() then
		return spell:CastNotify(target, "Kill Command (Cleave)", 3)
    end

    -- * Below is all single target logic.

    -- charges_fractional>=cooldown.barbed_shot.charges_fractional
    if spell:GetChargesFractional() < spells.barbed_shot:GetChargesFractional() then
        return false
    end

    -- (buff.lead_from_the_front.remains>gcd&buff.lead_from_the_front.remains<gcd*2&!howl_summon.ready&full_recharge_time>gcd)
    if player:FindBuff(auras.lead_from_the_front):Remains() > mint.max_gcd
    and player:FindBuff(auras.lead_from_the_front):Remains() < (mint.max_gcd * 2)
    and not player:FindAnyBuff(HowlReady):Active()
    and spell:GetFullRechargeTime() > mint.max_gcd then
        return false
    end

	return spell:CastNotify(target, "Kill Command (ST)", 3)
end)

-- # DR #10. Use kill command.
-- kill_command
spells.kill_command:AddCallback("Dark Ranger", function(spell)
	if not target:GetExists() or target:IsFriend() then
		return false
	end

	if player:FindBuff(auras.withering_fire):Inactive() then
		return spell:CastNotify(target, "Kill Command", 3)
	end

	if helpers.wfTick() <= mint.max_gcd then
		return false
	end

	if targets.black_arrow:GetExists() and spells.black_arrow:IsOnCD() and spells.black_arrow:GetRemainingCD() <= 0.5 then
		return false
	end

	return spell:CastNotify(target, "Kill Command", 3)
end)


------------------------------
--- Kill Shot
------------------------------
-- # DR #1. Kill Shot (Black Arrow) if available (snipe off targets)
-- kill_shot
spells.kill_shot:AddCallback(function(spell)
	if not target:GetExists() or target:IsFriend() then
		return false
	end

	if not helpers.blackArrow() then
		return false
	end

	SpellCancelQueuedSpell()

	return spell:CastNotify(target, "Black Arrow")
end)

spells.black_arrow:AddCallback(function(spell)
	if not target:GetExists() or target:IsFriend() then
		return false
	end

	if not targets.black_arrow:GetExists() then
		return false
	end

	if not helpers.blackArrow() then
		return false
	end

	SpellCancelQueuedSpell()

	return spell:CastNotify(targets.black_arrow, "Black Arrow")
end)

------------------------------
--- Misdirection
------------------------------
spells.misdirection:AddCallback(function(spell)
	if IsInRaid() then return false end

	if not targets.misdirect:GetExists() then
		return false
	end

	return spell:CastNotify(targets.misdirect, "Misdirecting " .. targets.misdirect.name, 3)
end)
------------------------------
--- Multishot
------------------------------
-- # 5. In cleave: Keep Beast Cleave active with Multishot if it’s fallen off (and either you don’t have Bloody Frenzy, or CotW isn’t about to come up).
-- multishot,if=pet.main.buff.beast_cleave.down&(!talent.bloody_frenzy|cooldown.call_of_the_wild.remains)
spells.multishot:AddCallback(function(spell)
	if not target:GetExists() or target:IsFriend() then
        return false
	end

    if not shouldCleave() then 
        return false
    end

	if player:FindBuff(auras.beast_cleave):Remains() > 0.4 then
		return false
	end

	if ((not IsPlayerSpell(talents.bloody_frenzy.id)) or spells.call_of_the_wild:IsOnCD()) then
		return spell:CastNotify(target, "Beast Cleave", 3)
	end

	return false
end)

------------------------------
--- Survival of the Fittest
------------------------------
spells.survival_of_the_fittest:AddCallback(function(spell)

end)

------------------------------
--- Tar Trap
------------------------------
spells.tar_trap:AddCallback(function(spell)

end)

------------------------------
--- Tranquilizing Shot
------------------------------

spells.tranquilizing_shot:AddCallback(function(spell)
	if not targets.tranq_shot:GetExists() then
		return false
	end

	return spell:CastNotify(targets.tranq_shot, "Tranq " .. targets.tranq_shot.name, 3)
end)

addon.hunter.data.bm.spells 	= spells
addon.hunter.data.bm.items 	    = items
addon.hunter.data.bm.auras 	    = auras
addon.hunter.data.bm.targets 	= targets
addon.hunter.data.bm.talents 	= talents
addon.hunter.data.bm.helpers 	= helpers