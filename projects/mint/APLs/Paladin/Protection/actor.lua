local unlocker, ---@class mint
mint, addon = ...

-- ! Mint Locals !--
local UnitManager   = mint.UnitManager
local Constants     = mint.Constants
local SmartTarget   = mint.SmartTarget
local Events            = mint.EventManager.New()
local target        = UnitManager:Get("target")
local player        = UnitManager:Get("player")
local none          = UnitManager:Get("none")

-- ! Addon Locals !--
local prot      = addon.paladin.protection
local spells    = addon.paladin.data["Protection"].spells
local items     = addon.paladin.data["Protection"].items
local auras     = addon.paladin.data["Protection"].auras
local targets   = addon.paladin.data["Protection"].targets
local talents   = addon.paladin.data["Protection"].talents

-- local Draw = mint.Draw:New()

-- Draw:Sync(function(draw)
--     if targets.avengers_shield:GetExists() then
--         local pos = targets.avengers_shield:GetPosition()
--         if pos:IsValid() then
--             draw:SetColor(255, 255, 255)
--             draw:Text("Shield Tar", "GameFontNormal", pos.x, pos.y, pos.z + 2)
--         end
--     end
-- end)

-- Draw:Enable()

prot:Sync(function()
    if IsMounted() then return false end

    -- ! Combat APL !--
    if player:IsInCombat() or player:IsPartyInCombat() then

        -- Auto Targeting
        if not target:GetExists() or UnitCanAssist("player", target:GetPointer()) or UnitIsDeadOrGhost(target:GetPointer()) then
			SmartTarget:Acquire()
		end

        -- We want to remove BoP as soon as possible
        if player:FindBuff(auras.blessing_of_protection):Active() then
            -- C_Spell.CancelSpellByID()
            CancelSpellByName("Blessing of Protection")
        end

        -- # Off GCD Actions # --
        -- Healthstone when below the threshold
        if items.healthstone() then return end

        -- Healing Potion when below the threshold
        if items.healing_potion() then return end

        -- Tome of Light's Devotion (Keep Offensive)
        if items.tome_of_lights_devotion("Offensive") then return end

        -- Tome of Light's Devotion (Keep Defensive)

        -- Interrupt with Rebuke
        -- * Prioritize Avenger's Shield interrupts over Rebuke. 
        -- * Need to track when we send a shield so that we don't shield -> rebuke the same target.
        -- ? Should we track distance + time to cast so we don't send shield too late?
        -- * Track current GCD as well to make sure we will send the shield in time.
        if spells.rebuke("Interrupt") then return end

        -- Maintain Devotion Aura
        if spells.devotion_aura() then return end

        -- Taunt enemy units attacking allies
        if spells.hand_of_reckoning() then return end

        -- # Emergency Healing # --
        -- Lay on Hands when below the threshold
        if spells.lay_on_hands() then return end

        -- Word of Glory when below the threshold
        if spells.word_of_glory("Prevent Death") then return end

        -- Word of Glory with Shining Light below the threshold
        if spells.word_of_glory("Shining Light: Low HP") then return end

        -- # Cooldown Logic # --
        -- # Pop Avenging Wrath on cooldown.
        -- * TTD check required
        -- * Wait until grouped, likely just use manually?
        -- actions.cooldowns+=/avenging_wrath
        if spells.avenging_wrath() then return end

        -- # Use your potion inside Avenging Wrath for maximum value.
        -- actions.cooldowns+=/potion,if=buff.avenging_wrath.up
        if items.tempered_potion() then return end

        -- # Use Moment of Glory during Wings (while AW has <15s remaining),
        -- # or, if you haven’t used it yet, fire it after 10s into the fight.
        -- actions.cooldowns+=/moment_of_glory,if=(buff.avenging_wrath.remains<15|(time>10))

        -- # Use Divine Toll in AoE (when SotR would hit 3+ targets).
        -- * We use this with 0 Holy Power in AoE
        -- actions.cooldowns+=/divine_toll,if=spell_targets.shield_of_the_righteous>=3
        if spells.divine_toll("Multi Target") then return end

        -- * Send Consecration if we do not have the buff and we have enemies in melee range of us
        -- Consecration with no buff + enemies in melee
        if spells.consecration("Maintain Buff") then return end

        -- # Cast Judgment when the target’s Judgment debuff is about to fall off,
        -- # or when you have 2+ charges or the recharge will finish within a GCD.
        -- actions.standard=judgment,target_if=min:debuff.judgment.remains,if=charges>=2|full_recharge_time<=gcd.max
        if spells.judgment("Avoid Cap") then return end

        -- # Cast Hammer of Light if Blessing of Dawn is active OR fight is ending soon (<2s),
        -- # and if the target has Judgment, or Hammer of Light is about to fall off,
        -- # or you have multiple stacks/it's free, or Eye of Tyr is nearly ready.
        -- actions.standard+=/hammer_of_light,if=(buff.blessing_of_dawn.up|fight_remains<2)&(debuff.judgment.up|buff.hammer_of_light_ready.remains<2|buff.hammer_of_light_ready.stack>1|buff.hammer_of_light_free.up|(cooldown.eye_of_tyr.remains<3))

        -- # Use Eye of Tyr if you have the Lights Guidance talent.
        -- * Light's Guidance is the Templar root talent. This is Templar exclusive logic.
        -- actions.standard+=/eye_of_tyr,if=talent.lights_guidance.enabled

        -- # Without the S2 4pc, just spend Shield of the Righteous when Righteous Protector is available,
        -- # Hammer of Light is not ready, and ICD is free.
        -- * Righteous Protector has a 1 second ICD on providing CDR for cooldowns, so we want to make sure we take advantage of that.
        -- actions.standard+=/shield_of_the_righteous,if=!set_bonus.thewarwithin_season_2_4pc&(!talent.righteous_protector.enabled|cooldown.righteous_protector_icd.remains=0)&!buff.hammer_of_light_ready.up
        spells.shield_of_the_righteous("CDR")

        -- # Spend Holy Power at 5 if Blessing of Dawn isn’t up, or you don’t have Lights Guidance.
        -- * Dawn is generated by 3 generators, SoTR or WoG spends it (does 30% more dmg/heal), and provides Dusk, which is 4% Damage reduction
        -- actions.standard+=/shield_of_the_righteous,if=holy_power=5&(!buff.blessing_of_dawn.up|!talent.lights_guidance.enabled)
        spells.shield_of_the_righteous("Dump")

        -- # Use Avenger's Shield to interrupt casts.
        -- * This spawns an extra Blessed Hammer, so we want to snipe as much as possible.
        -- ! We likely want to have Avenger's Shield kick take priority over our Rebuke and HoJ kicks.
        if spells.avengers_shield("Snipe Interrupts") then return end

        -- # Use Hammer of Justice to interrupt casts.
        -- * This is a lower priority than other interrupts, but good to use.
        if spells.hammer_of_justice("Interrupt") then return end

        -- # Cast Judgment in AoE if 4+ targets, Bulwark buff stacked to 3+, and you’re low on Holy Power (<3).
        -- * We want to target the unit with lowest judgment debuff time. This is essentially trying to get us enough Holy Power to cast SoTR ASAP
        -- actions.standard+=/judgment,target_if=min:debuff.judgment.remains,if=spell_targets.shield_of_the_righteous>3&buff.bulwark_of_righteous_fury.stack>=3&holy_power<3
        if spells.judgment("Multi Target") then return end

        -- # Lightsmith with S3 4pc: don’t waste masterwork stacks when Holy Bulwark is next.
        -- * We want to only send Holy Bulwark with 0 stacks, basically
        -- * Ideally, we stack 2 armament charges with Weapon on top, then send weapon at 5 stacks and immediately send bulwark
        -- actions.standard+=/holy_armaments,if=next_armament=holy_bulwark&set_bonus.thewarwithin_season_3_4pc
        if spells.holy_bulwark() then return end

        -- # Lightsmith with 4pc: spam Blessed Hammer to trigger the 2pc effect often.
        -- actions.standard+=/blessed_hammer,if=set_bonus.thewarwithin_season_3_4pc&talent.hammer_and_anvil.enabled
        if spells.blessed_hammer() then return end

        -- # Use Avenger’s Shield in AoE (3+ targets) to trigger Bulwark buff if it’s not already up.
        -- actions.standard+=/avengers_shield,if=!buff.bulwark_of_righteous_fury.up&talent.bulwark_of_righteous_fury.enabled&spell_targets.shield_of_the_righteous>=3
        if spells.avengers_shield("Multi Target") then return end

        -- # Use Hammer of the Righteous if Blessed Assurance buff is active,
        -- # fewer than 3 AoE targets, and you’re not under Avenging Wrath.
        -- actions.standard+=/hammer_of_the_righteous,if=buff.blessed_assurance.up&spell_targets.shield_of_the_righteous<3&!buff.avenging_wrath.up

        -- # Use Blessed Hammer under the same conditions (Blessed Assurance active, <3 targets).
        -- actions.standard+=/blessed_hammer,if=buff.blessed_assurance.up&spell_targets.shield_of_the_righteous<3
        if spells.blessed_hammer("Low Targets") then return end

        -- # Drop Consecration at max Divine Guidance stacks.
        -- actions.standard+=/consecration,if=buff.divine_guidance.stack=5

        -- -- # Cast Sacred Weapon when it’s the next armament and:
        -- -- # you don’t have it up or it’s about to fall (<6s), AW not active, AW coming soon,
        -- -- # and (if 4pc S3) you’re at max Masterwork stacks.
        -- -- * Again, we send this at 5 MW stacks. Ideally, as soon as we get the second charge so we can send bulwark right after.
        -- -- * We can use this logic to check around wings as well.
        -- -- * We want to wait until Masterwork falls off before sending, as it will send 100% lesser 
        -- -- * weapons while at 5 stacks with weapon next
        -- -- actions.standard+=/holy_armaments,if=next_armament=sacred_weapon&((!buff.sacred_weapon.up|(buff.sacred_weapon.remains<6&!buff.avenging_wrath.up&cooldown.avenging_wrath.remains<=30))&(!set_bonus.thewarwithin_season_3_4pc|buff.masterwork.stack=5))
        if spells.sacred_weapon() then return end

        -- # Use Hammer of Wrath when available (execute or Wings).
        -- * We should be sniping nearby viable Hammer of Wrath targets.
        -- actions.standard+=/hammer_of_wrath
        if spells.hammer_of_wrath() then return end

        -- # Cast Divine Toll if no adds soon, or next adds wave is more than 10s away.
        -- * In M+ content, we're going to press this manually, or with <4 Holy Power in single target, or 0 Holy Power in multi target.
        -- actions.standard+=/divine_toll,if=(!raid_event.adds.exists|raid_event.adds.in>10)
        if spells.divine_toll("Single Target") then return end

        -- # Use Judgment during Avenging Wrath if Hammer and Anvil talent is active.
        -- * Judgment target should probably be within melee range (or like 12 yards) of the player to maximize Hammer & Anvil damage.
        -- actions.standard+=/judgment,target_if=min:debuff.judgment.remains,if=(buff.avenging_wrath.up&talent.hammer_and_anvil.enabled)
        if spells.judgment("Wings") then return end

        -- # Keep Judgment rolling normally.
        -- actions.standard+=/judgment,target_if=min:debuff.judgment.remains
        if spells.judgment() then return end

        -- # Use Hammer of the Righteous if Blessed Assurance or Shake the Heavens is active (<3 AoE).
        -- actions.standard+=/hammer_of_the_righteous,if=(buff.blessed_assurance.up&spell_targets.shield_of_the_righteous<3)|buff.shake_the_heavens.up

        -- # Same logic with Blessed Hammer.
        -- actions.standard+=/blessed_hammer,if=(buff.blessed_assurance.up&spell_targets.shield_of_the_righteous<3)|buff.shake_the_heavens.up
        if spells.blessed_hammer("Shake the Heavens") then return end

        -- # Use Avenger’s Shield if Lights Guidance isn’t talented.
        -- * Light's Guidance == Templar
        -- * Basically, this is Lightsmith exclusive logic.
        -- actions.standard+=/avengers_shield,if=!talent.lights_guidance.enabled
        if spells.avengers_shield("Lightsmith") then return end

        -- # Use Eye of Tyr if you have Inmost Light (adds in >=45s or 3+ targets) and no Lights Deliverance.
        -- * Light's Deliverance == Templar
        -- * Again, this is Lightsmith exclusive logic.
        -- actions.standard+=/eye_of_tyr,if=(talent.inmost_light.enabled&raid_event.adds.in>=45|spell_targets.shield_of_the_righteous>=3)&!talent.lights_deliverance.enabled
        if spells.eye_of_tyr("Lightsmith") then return end

        -- # Fire off Holy Bulwark if it’s the next armament.
        -- * We want to be using Holy Bulwark with zero stacks, ASAP
        -- actions.standard+=/holy_armaments,if=next_armament=holy_bulwark
        if spells.holy_bulwark() then return end

        -- # Spam filler Blessed Hammer.
        -- actions.standard+=/blessed_hammer
        if spells.blessed_hammer() then return end

        -- # Spam filler Hammer of the Righteous.
        -- actions.standard+=/hammer_of_the_righteous

        -- # Cast Word of Glory for free if Shining Light proc is up,
        -- # and either Blessed Assurance or Lights Guidance + Hammerfall ICD is free.
        -- * As Lightsmith, we only care about if Shining Light is active and we have Blessed Assurance
        -- actions.standard+=/word_of_glory,if=buff.shining_light_free.up&(talent.blessed_assurance.enabled|(talent.lights_guidance.enabled&cooldown.hammerfall_icd.remains=0))

        -- # Use Eye of Tyr if Lights Deliverance isn’t talented.
        -- * This is basically Eye of Tyr if you're Lightsmith.
        -- actions.standard+=/eye_of_tyr,if=!talent.lights_deliverance.enabled

        -- # Cast free Word of Glory procs.
        -- * We are likely not going to use this.
        -- actions.standard+=/word_of_glory,if=buff.shining_light_free.up
        if spells.word_of_glory("Shining Light") then return end

        -- # Use Arcane Torrent to generate Holy Power if not capped (<5).
        -- actions.standard+=/arcane_torrent,if=holy_power<5

        -- # Cast Avenger’s Shield as filler/priority damage.
        -- actions.standard+=/avengers_shield
        if spells.avengers_shield() then return end

        -- # Keep Consecration down as filler.
        -- actions.standard+=/consecration
        if spells.consecration("Filler") then return end

        -- ! Resting APL !--
    else

    end

end)