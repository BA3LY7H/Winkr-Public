local unlocker,
---@class mint
mint = ...


--[[ 
    This is a folder class instead of a file, as the intention is to replace these large tables with 
    functions to allow users to decide what they want to make a priority damage event, etc
]]--

--! Mint Locals !--
local Interface = mint.Interface

---@class RaidEvents
local RaidEvents = {}
RaidEvents.__index = RaidEvents

local dungeon_events = {
    ["Party Damage Old"] = {
        427404, 430812, 430805, 1214523, 1214628, 1214324, 444123, 424958, 425048, 423393, 423305, 429029, 291973,
        427609, 448492, 427897, 464240, 448791, 435156, 444743, 435156, 451763, 424419, 446368, 423051,
        423015, 423539, 428169, 423665, 428066, 424322, 430171, 1218117, 422541, 428268, 443835, 425394,
        423099, 420665, 421146, 426943, 427176, 428266, 463218, 463206, 441434, 448619, 442995, 440687,
        442525, 439365, 440104, 439524, 435789, 435622, 1214468, 468680, 465827, 471736, 469721, 1216611,
        1214780, 469981, 460156, 460867, 470038, 473070, 465456, 267354, 263628, 473168, 268702, 269429,
        262347, 256493, 257597, 258622, 271456, 301088, 1215409, 1215412, 473436, 1216443, 1215103,
        294929, 292022, 291946, 291626, 292290, 292264, 283551, 333241, 1215850, 342135, 342135, 333839,
        333827, 330716, 341969, 345245, 1215600, 333292, 1215741, 320050, 473959, 323825, 324449, 339573,
        465833, -- Colossal Clash (CoC raid)
        464149, -- stix bunkjunker flame circles
        464399, -- stix bunkjunker sorting
        465232, -- sprocketmaster lockenstock sonic ba boom
    },
	["Targeted"] = {
		-- Cinderbrew Meadery
		[432229] = { name = "Keg Smash", 		channel = false, travel = false }, -- Boss Ability
		[434706] = { name = "Cinderbrew Toss", 	channel = false, travel = false },
		[434756] = { name = "Throw Chair", 		channel = false, travel = false },
		[434773] = { name = "Mean Mug", 		channel = false, travel = false },
		[436637] = { name = "Burning Ricochet", channel = false, travel = false }, -- Boss Ability
		[437721] = { name = "Boiling Flames", 	channel = false, travel = false },
		[437956] = { name = "Erupting Inferno", channel = false, travel = false },
		[439031] = { name = "Bottoms Uppercut", channel = false, travel = false }, -- Boss Ability
		[440134] = { name = "Honey Marinade", 	channel = false, travel = false }, -- Boss Ability
		[441119] = { name = "Bee-Zooka", 		channel = false, travel = false },
		[441242] = { name = "Free Samples", 	channel = false, travel = false },
		[441410] = { name = "Shredding Sting", 	channel = false, travel = false },
		[443487] = { name = "Final Sting", 		channel = false, travel = false },
		[448619] = { name = "Reckless Delivery",channel = false, travel = false },
		[453909] = { name = "Boiling Flames", 	channel = false, travel = false },
		[453989] = { name = "Boiling Flames", 	channel = false, travel = false },
		[456891] = { name = "Shoot", 			channel = false, travel = false },

		-- Priory of the Sacred Flame
		[423015] = { name = "Castigator's Shield", channel = false, travel = false }, -- Boss Ability
		[423536] = { name = "Holy Smite", channel = false, travel = false }, -- Boss Ability
		[424414] = { name = "Pierce Armor", channel = false, travel = false }, -- Boss Ability
		[424420] = { name = "Cinderblast", channel = false, travel = false },
		[424421] = { name = "Fireball", channel = false, travel = false },
		[427357] = { name = "Holy Smite", channel = false, travel = false },
		[427469] = { name = "Fireball", channel = false, travel = false },
		[427629] = { name = "Shoot", channel = false, travel = false },
		[435165] = { name = "Blazing Strike", channel = false, travel = false },
		[444296] = { name = "Impale", channel = false, travel = false },
		[444449] = { name = "Shoot", channel = false, travel = false },
		[446776] = { name = "Pounce", channel = false, travel = false },
		[447270] = { name = "Hurl Spear", channel = false, travel = false }, -- Boss Ability
		[448485] = { name = "Shield Slam", channel = false, travel = false },
		[448787] = { name = "Purification", channel = false, travel = false },
		[451605] = { name = "Holy Flame", channel = false, travel = false }, -- Boss Ability
		[462859] = { name = "Pot Shot", channel = false, travel = false },

		-- Darkflame Cleft
		[421277] = { name = "Darkflame Pickaxe", channel = false, travel = false }, -- Boss Ability
		[422245] = { name = "Rock Buster", channel = false, travel = false }, -- Boss Ability
		[423479] = { name = "Wicklighter Bolt", channel = false, travel = false },
		[426295] = { name = "Flaming Tether", channel = false, travel = false },
		[426619] = { name = "One-Hand Headlock", channel = false, travel = false },
		[426677] = { name = "Candleflame Bolt", channel = false, travel = false },
		[426883] = { name = "Bonk!", channel = false, travel = false },
		[427011] = { name = "Shadowblast", channel = false, travel = false }, -- Boss Ability
		[428089] = { name = "Throw Rock", channel = false, travel = false },
		[428563] = { name = "Flame Bolt", channel = false, travel = false },

		-- The Rookery
		[424958] = { name = "Crush Reality", channel = false, travel = false }, -- Boss Ability
		[426893] = { name = "Bounding Void", channel = false, travel = false },
		[427616] = { name = "Energized Barrage", channel = false, travel = false },
		[430109] = { name = "Lightning Bolt", channel = false, travel = false },
		[430179] = { name = "Seeping Corruption", channel = false, travel = false },
		[430238] = { name = "Void Bolt", channel = false, travel = false },
		[430805] = { name = "Arcing Void", channel = false, travel = false },
		[451843] = { name = "Crush Reality", channel = false, travel = false }, -- Boss Ability
		[474031] = { name = "Void Crush", channel = false, travel = false },
		[1214523] = { name = "Feasting Void", channel = false, travel = false },

		-- Operation: Floodgate
		[459779] = { name = "Barreling Charge", channel = false, travel = false }, -- Boss Ability
		[459799] = { name = "Wallop", channel = false, travel = false }, -- Boss Ability
		[460393] = { name = "Shoot", channel = false, travel = false }, -- Boss Ability
		[460602] = { name = "Quick Shot", channel = false, travel = false }, -- Boss Ability
		[462771] = { name = "Surveying Beam", channel = false, travel = false },
		[463169] = { name = "EZ-Thro Dynamite III", channel = false, travel = false },
		[464655] = { name = "Snipe", channel = false, travel = false },
		[465120] = { name = "Wind up", channel = false, travel = false },
		[465595] = { name = "Lightning Bolt", channel = false, travel = false },
		[465666] = { name = "Sparkslam", channel = false, travel = false },
		[465682] = { name = "Surprise Inspection", channel = false, travel = false },
		[465813] = { name = "Lethargic Venom", channel = false, travel = false },
		[465820] = { name = "Vicious Chomp", channel = false, travel = false },
		[465871] = { name = "Blood Blast", channel = false, travel = false },
		[466190] = { name = "Thunder Punch", channel = false, travel = false }, -- Boss Ability
		[468631] = { name = "Harpoon", channel = false, travel = false },
		[468672] = { name = "Pinch", channel = false, travel = false },
		[468932] = { name = "Wrench Wallop", channel = false, travel = false },
		[469478] = { name = "Sludge Claws", channel = false, travel = false }, -- Boss Ability
		[472452] = { name = "Doom Storm", channel = false, travel = false }, -- Boss Ability
		[473220] = { name = "Sonic Boom", channel = false, travel = false }, -- Boss Ability
		[473351] = { name = "Electrocrush", channel = false, travel = false }, -- Boss Ability
		[473690] = { name = "Kinetic Explosive Gel", channel = false, travel = false }, -- Boss Ability
		[1213805] = { name = "Nailgun", channel = false, travel = false },
		[1214468] = { name = "Trickshot", channel = false, travel = false },

		-- The MOTHERLODE!!!
		[257478] = { name = "Crippling Bite", channel = false, travel = false },
		[257582] = { name = "Raging Gaze", channel = false, travel = false },
		[258674] = { name = "Throw Wrench", channel = false, travel = false },
		[259940] = { name = "Propellant Blast", channel = false, travel = false }, -- Boss Ability
		[260202] = { name = "Drill Smash", channel = false, travel = false }, -- Boss Ability
		[260372] = { name = "Buster Shot", channel = false, travel = false },
		[260811] = { name = "Homing Missile", channel = false, travel = false }, -- Boss Ability
		[262268] = { name = "Caustic Compound", channel = false, travel = false },
		[262377] = { name = "Seek and Destroy", channel = false, travel = false },
		[262515] = { name = "Azerite Heartseeker", channel = false, travel = false },
		[263202] = { name = "Rock Lance", channel = false, travel = false },
		[263209] = { name = "Throw Rock", channel = false, travel = false },
		[263262] = { name = "Shale Spit", channel = false, travel = false },
		[263628] = { name = "Charged Shield", channel = false, travel = false },
		[268797] = { name = "Transmute: Enemy to Goo", channel = false, travel = false },
		[268846] = { name = "Echo Blade", channel = false, travel = false },
		[269429] = { name = "Charged Shot", channel = false, travel = false },
		[270042] = { name = "Azerite Catalyst", channel = false, travel = false }, -- Boss Ability
		[271456] = { name = "Drill Smash", channel = false, travel = false }, -- Boss Ability
		[271579] = { name = "Rock Lance", channel = false, travel = false },
		[280604] = { name = "Iced Spritzer", channel = false, travel = false },
		[1214754] = { name = "Massive Slam", channel = false, travel = false },
		[1217279] = { name = "Uppercut", channel = false, travel = false },
		[1217280] = { name = "Uppercut", channel = false, travel = false },
		[2622794] = { name = "Mind Lash", channel = false, travel = false },

		-- Theater of Pain
		[319997] = { name = "Shoot", channel = false, travel = false },
		[320069] = { name = "Mortal Strike", channel = false, travel = false }, -- Boss Ability
		[320120] = { name = "Plague Bolt", channel = false, travel = false }, -- Boss Ability
		[323515] = { name = "Hateful Strike", channel = false, travel = false }, -- Boss Ability
		[324079] = { name = "Reaping Scythe", channel = false, travel = false }, -- Boss Ability
		[330532] = { name = "Jagged Quarrel", channel = false, travel = false },
		[330565] = { name = "Shield Bash", channel = false, travel = false },
		[330586] = { name = "Devour Flesh", channel = false, travel = false },
		[330697] = { name = "Decaying Strike", channel = false, travel = false },
		[330703] = { name = "Decaying Filth", channel = false, travel = false },
		[330784] = { name = "Necrotic Bolt", channel = false, travel = false },
		[330810] = { name = "Bind Soul", channel = false, travel = false },
		[330875] = { name = "Spirit Frost", channel = false, travel = false },
		[331288] = { name = "Colossus Smash", channel = false, travel = false },
		[331316] = { name = "Savage Flurry", channel = false, travel = false },
		[333845] = { name = "Unbalancing Blow", channel = false, travel = false },
		[333861] = { name = "Ricocheting Blade", channel = false, travel = false },
		[341771] = { name = "Grave Spike", channel = false, travel = false },
		[342675] = { name = "Bone Spear", channel = false, travel = false },
		[1215600] = { name = "Withering Touch", channel = false, travel = false }, -- Boss Ability
		[1216475] = { name = "Necrotic Bolt", channel = false, travel = false },
		[1217138] = { name = "Necrotic Bolt", channel = false, travel = false }, -- Boss Ability

		-- Operation: Mechagon Workshop
		[283421] = { name = "Maximum Thrust", channel = false, travel = false }, -- Boss Ability
		[283422] = { name = "Maximum Thrust", channel = false, travel = false }, -- Boss Ability
		[285152] = { name = "Foe Flipper", channel = false, travel = false }, -- Boss Ability
		[285454] = { name = "Discom-BOMB-ulator", channel = false, travel = false }, -- Boss Ability
		[291928] = { name = "Mega-Zap", channel = false, travel = false }, -- Boss Ability
		[291973] = { name = "Explosive Leap", channel = false, travel = false }, -- Boss Ability
		[292264] = { name = "Mega-Zap", channel = false, travel = false }, -- Boss Ability
		[293827] = { name = "Giga-Wallop", channel = false, travel = false },
		[293986] = { name = "Sonic Pulse", channel = false, travel = false },
		[294195] = { name = "Arcing Zap", channel = false, travel = false },
		[294855] = { name = "Blossom Blast", channel = false, travel = false }, -- Boss Ability
		[1216431] = { name = "B.4.T.T.L.3. Mine", channel = false, travel = false },	
	},
	["Party Damage"] = {
		[427404] = { travel = false, name = "Localized Storm", channel = true }, -- Voidrider, Rookery - Channeled AoE nature hits, ticks every 1s for 5s
		[430812] = { travel = false, name = "Attracting Shadows" }, -- Coalescing Void Diffuser, Rookery - Creates a 7yd void zone on the ground that constantly pulls players towards it, dealing AoE shadow damage every 1s for 6s before exploding
		[430805] = { travel = false, name = "Arcing Void" }, -- Coalescing Void Diffuser, Rookery - Random target shadow hit that jumps to up to 4 targets, dealing less damage with each jump
		[1214523] = { travel = false, name = "Feasting Void" }, -- Void Ascendant, Rookery - 18s Magic DoT and healing absorb applied to all players within 60yds
		[1214628] = { travel = false, name = "Unleash Darkness", channel = true }, -- Consuming Voidstone, Rookery - Channeled AoE shadow hits which spawn 6yd circles that deal shadow damage to anyone hit, ticks every 4s for 20s
		[1214324] = { travel = false, name = "Crashing Thunder" }, -- Kyrioss, Rookery - Nature hit on every player that cleaves anyone within 8yds
		[444123] = { travel = false, name = "Lightning Torrent", channel = true }, -- Kyrioss, Rookery - At 100 energy the boss rotates lethal beams in a random direction around the room while channeling AoE nature hits that spawn 5yd AoE circles under all players, ticks every 3s for 15s
		[424958] = { travel = false, name = "Crush Reality" }, -- Stormguard Gorren, Rookery - Random ranged leap that does a party hit and leaves behind a puddle for 2mins that shoots out several beams on impact which deal shadow damage to players hit
		[425048] = { travel = false, name = "Dark Gravity", channel = true }, --Stormguard Gorren , Rookery - Channel that pulls players in, dealing AoE shadow damage every 2s for 6s before exploding and knocking back players within 10yds
		[423393] = { travel = false, name = "Entropy" }, -- Voidstone Monstrosity, Rookery - AoE shadow hit if no players are in melee range
		[423305] = { travel = false, name = "Null Upheaval" }, --Voidstone Monstrosity , Rookery - AoE shadow hit and knockback that creates many 7yd swirlies and 3 dormant Voidstone mobs that awaken after 15s, cast at full energy
		[429029] = { travel = false, name = "Corruption Overload" }, -- Voidstone Overload, Rookery - Awakened Voidstones deal pulsing AoE shadow damage every 3s, gaining 20% increased damage with each pulse
		[427609] = { travel = false, name = "Disrupting Shout" }, -- Arathi Knight, Priory - 40yd AoE phys hit that interrupts spellcasting for 4s
		[448492] = { travel = false, name = "Thunderclap" }, -- Guard Captain Suleyman, Priory - 50yd AoE nature hit that slows by 50% for 6s
		[427897] = { travel = false, name = "Heat Wave" }, -- Forge Master Damian, Priory - 50yd AoE fire hit and 70% Magic slow for 4s
		[464240] = { travel = false, name = "Reflective Shield" }, -- High Priest Aemya, Priory - Absorb shield that reflects 40% of incoming damage back at attacks as holy damage
		[448791] = { travel = false, name = "Sacred Toll", }, -- Ardent Paladin, Priory - 50yd AoE holy hit	
		[435156] = { travel = false, name = "Light Expulsion" }, -- Risen Mage/Risen Footman/Sir Braunpyke, Priory - 60yd AoE holy hit on death
		[444743] = { travel = false, name = "Fireball Volley" }, -- Risen Mage, Priory - 50yd AoE fire hit
		[451763] = { travel = false, name = "Radiant Flame" }, -- Sir Braunpyke, Priory - Aura that deals holy damage to all players within 45yds every 0.5s
		[424419] = { travel = false, name = "Battle Cry" }, -- Captain Dailcry, Priory - AoE phys hit that grants Trusted Guards 50 energy and applies a 50% damage increase Enrage to them for 30s
		[446368] = { travel = false, name = "Sacrificial Pyre" }, -- Baron Braunpyke, Priory - Creates a pyre with 3 charges that explodes after 30s, touching it removes a charge but applies a stacking 15s holy DoT, knocks that player back and does an AoE holy hit
		[423051] = { travel = false, name = "Burning Light" }, -- Unknown Mob, Priory - AoE holy hit that applies a 12s holy DoT and heals the boss for 40% health
		[423015] = { travel = false, name = "Castigator's Shield" }, -- Unknown Mob, Priory - Holy hit and 50% slow for 5s on 3 random players, creating a 12yd AoE underneath them that deals holy damage to anyone hit
		[423539] = { travel = false, name = "Inner Fire" }, -- Unknown Mob, Priory - Buff that increases holy damage by 50% for 12s and pulses for AoE holy damage every 3s
		[428169] = { travel = false, name = "Blinding Light" }, -- Unknown Mob, Priory - AoE holy hit that deals additional damage and disorients for 4s to anyone looking at the boss
		[423665] = { travel = false, name = "Embrace the Light", channel = true }, -- Unknown Mob, Priory - At 50% health the boss gains a shield, runs to the upper platform, spawns several Neophyte mobs and channels ramping AoE holy damage until interrupted
		[428066] = { travel = false, name = "Overpowering Roar" }, -- Unknown Mob, Darkflame - 50yd AoE phys hit that increases the haste and damage done of allies by 10% for 15s
		[424322] = { travel = false, name = "Explosive Flame" }, -- Blazing Fiend, Darkflame - 100yd AoE fire hit that applies a stacking 10% fire damage taken increase for 20s
		[430171] = { travel = false, name = "Quenching Blast" }, -- Wandering Candle, Darkflame - 60yd AoE fire hit
		[1218117] = { travel = false, name = "Massive Stomp" }, -- Unknown Mob, Darkflame - 50yd AoE nature hit and knockback
		[422541] = { travel = false, name = "Drain Light", channel = true }, -- Shuffling Horror, Darkflame - Channeled AoE shadow hits that drain energy from the mine cart, ticks every 1s for 10s
		[428268] = { travel = false, name = "Underhanded Track-tics" }, -- Unknown Mob, Darkflame - Spawns a cart full of dynamite that must be destroyed within 20s, otherwise it explodes for heavy fire damae and applies a 20s fire DoT to the party
		[443835] = { travel = false, name = "Blazing Storms" }, -- Blazikon, Darkflame - AoE fire hit if no players are in melee range
		[425394] = { travel = false, name = "Dousing Breath" }, -- Unknown Mob, Darkflame - AoE nature hit that extinguishes all candles
		[423099] = { travel = false, name = "Enkindling Inferno" }, -- Unknown Mob, Darkflame - Shoots flames towards all extinguished candles, dealing fire damage to players hit and applying a stacking 8s fire DoT for each candle ignited, cast at full energy
		[420665] = { travel = false, name = "Eerie Molds" }, -- The Candle King, Darkflame - Creates a wax figure of each player which deal AoE fire damage to all players every 2s and stun players who come within 2yds for 5s
		[421146] = { travel = false, name = "Throw Darkflame" }, -- Unknown Mob, Darkflame - 5yd AoE around 3 random players that deals shadow damage and applies a healing absorb to players hit, wax figures hit are destroyed and turn into a puddle for 45s
		[426943] = { travel = false, name = "Rising Gloom" }, -- Unknown Mob, Darkflame - If the candle is depleted players take a shadow hit, are feared for 1s, and debuffed with a stacking 10% damage taken and 5% haste reduction for 10min
		[427176] = { travel = false, name = "Drain Light", channel = true }, -- Unknown Mob, Darkflame - Channel that drains heat from the candle and deals AoE shadow damage, ticks every 1s for 10s
		[428266] = { travel = false, name = "Eternal Darkness", channel = true }, -- Unknown Mob, Darkflame - Channeled AoE shadow hits that reduce candle heat, ticks every 1s for 4s
		[463218] = { travel = false, name = "Volatile Keg" }, -- Hired Muscle, Cinderbrew - 50yd AoE fire hit and 6s fire DoT
		[463206] = { travel = false, name = "Tenderize" }, -- Unknown Mob, Cinderbrew - 50yd AoE phys hit and knockback
		[441434] = { travel = false, name = "Failed Batch" }, -- Flavor Scientist, Cinderbrew - Spawns a keg that explodes after 10s unless killed, doing a 100yd AoE fire hit and 8s DoT
		[448619] = { travel = false, name = "Reckless Delivery" }, -- Careless Hopgoblin, Cinderbrew - Random target line attack that deals phys dam and knocks back players hit, in addition does AoE phys dam, spawns several Brew Drop adds and is stunned for 3s on hitting wall
		[442995] = { travel = false, name = "Swarming Surprise" }, -- Unknown Mob, Cinderbrew - 60yd AoE phys hit that increases damage taken from this ability by 10% for 30s
		[440687] = { travel = false, name = "Honey Volley" }, -- Royal Jelly Purveyor, Cinderbrew - 60yd AoE nature hit that slows players by 70% for 8s
		[442525] = { travel = false, name = "Happy Hour" }, -- Unknown Mob, Cinderbrew - Boss gains a 99% DR and you have to serve 5 Thirsty Patrons a mug of Cinderbrew to remove it, all while taking AoE phys dam every 2s, cast at 66% and 33% health
		[439365] = { travel = false, name = "Spouting Stout", channel = true }, -- I'pa, Cinderbrew - Channeled AoE fire hits that creates many 3yd circles and spawns 3 Brew Drop adds that attempt to run at the boss
		[440104] = { travel = false, name = "Fill 'Er Up" }, -- Unknown Mob, Cinderbrew - I'pa consumes Brew Drops it touches, dealing AoE fire dmaage and gaining a 10% health shield
		[439524] = { travel = false, name = "Fluttering Wing", channel = true }, -- Unknown Mob, Cinderbrew - Channeled AoE nature hits that constantly push players away, ticks every 0.5s for 2s
		[435789] = { travel = false, name = "Cindering Wounds" }, -- Unknown Mob, Cinderbrew - Stacking 6s fire DoT that applies to the party upon destroying 1 of the 4 Volatile Barrels each phase
		[435622] = { travel = false, name = "Let it Hail", channel = true }, -- Unknown Mob, Cinderbrew - Channeled AoE fire hits that detonate any remaining barrels, ticks every 1s for 5s, cast at full energy
		[1214468] = { travel = false, name = "Trickshot" }, -- Unknown Mob, Floodgate - Random target shadow hit that bounces to nearby players
		[468680] = { travel = false, name = "Crabsplosion" }, -- Unknown Mob, Floodgate - 50yd AoE fire hit and stacking 5s DoT on death
		[465827] = { travel = false, name = "Warp Blood", channel = true }, -- Unknown Mob, Floodgate - Channeled AoE shadow hits and healing absorb, ticks every 1s for 6s
		[471736] = { travel = false, name = "Jettison Kelp", channel = true }, -- Disturbed Kelp, Floodgate - Channeled random target nature hits, ticks every 0.5s for 5s
		[469721] = { travel = false, name = "Backwash", channel = true }, -- Unknown Mob, Floodgate - Channeled AoE frost hits and stacking 6s frost DoT, ticks every 1s for 3s
		[1216611] = { travel = false, name = "Battery Discharge" }, -- Darkfuse Jumpstarter, Floodgate - Spawns 4yd circles and does a 60yd AoE nature hit to all players every 5s
		[1214780] = { travel = false, name = "Maximum Distortion", channel = true }, -- Unknown Mob, Floodgate - Channeled AoE sonic hits and knockback, ticks every 2s for 16s, cast by Mechadrone
		[469981] = { travel = false, name = "Kill-o-Block Barrier" }, -- Unknown Mob, Floodgate - 80% Damage Reduction and pulsing AoE nature hits every 2.5s, cast at full energy
		[460156] = { travel = false, name = "Jumpstart", channel = true }, -- Unknown Mob, Floodgate - 200% damage amp on the boss while it does channeled AoE nature hits, ticks every 1.5s for 12s, cast after Mechadrones are defeated and resets energy, creates a growing puddle of electricity under the boss after the cast finishes
		[460867] = { travel = false, name = "Big Bada Boom" }, -- Unknown Mob, Floodgate - 6 Bombs spawn in the arena, detonating after 30s applying a stacking 10s DoT to the group, if hit by Barreling Charge of Kinetic Explosive Gel these are launched into safely out of the arena and only spawn 5yd circles to avoid
		[470038] = { travel = false, name = "Razorchoke Vines" }, -- Swampface, Floodgate - Binds 2 players together (prefers non-tanks), dealing Nature damage for 24s and pulling them together if they ever move more than 14yds apart
		[473070] = { travel = false, name = "Awaken the Swamp", channel = true }, -- Unknown Mob, Floodgate - Spawns 5 circles on that ground then Channels AoE Nature hits for 4s, causing a circle to detonate each second and spawn waves to dodge
		[465456] = { travel = false, name = "Turbo Charge" }, -- Geezle Gigazap, Floodgate - Chanelled AoE nature damage every 1s for 10s that shoots random target lines every 2s which stun players hit, cast at 0 Electricity, triggers Dam! when complete
		[267354] = { travel = false, name = "Fan of Knives", channel = true }, -- Unknown Mob, Motherlode - Channeled AoE phys hits, ticks every 1s for 4s
		[263628] = { travel = false, name = "Charged Shield" }, -- Unknown Mob, Motherlode - Tank targeted nature hit that buffs the mech, causing melees to chain lightning to 5 nearby targets
		[473168] = { travel = false, name = "Rapid Extraction", channel = true }, -- Unknown Mob, Motherlode - Channeled AoE phys hits that spawn 6yd circles, ticks every 1s for 5s
		[268702] = { travel = false, name = "Furious Quake" }, -- Unknown Mob, Motherlode - 60yd AoE nature hit and 6s slow
		[269429] = { travel = false, name = "Charged Shot", channel = true }, -- Unknown Mob, Motherlode - Channeled AoE arcane damage, ticks every 1s for 3s
		[262347] = { travel = false, name = "Static Pulse" }, -- Coin-Operated Crowd Pummeler, Motherlode - AoE nature hit that knocks players back and applies an 8s nature DoT
		[256493] = { travel = false, name = "Footbomb Launcher" }, -- Unknown Mob, Motherlode - Spawns 6 footbombs around the boss that detonate for AoE fire damage after 15s. Players can kick these into the boss to remove Pay to Win stacks and apply a stacking 25% damage amp
		[257597] = { travel = false, name = "Azerite Infusion" }, -- Unknown Mob, Motherlode - Empowers and earthrager, healing it to full health, breaking any CC, increasing its damage by 50%, damage taken by 150%, and making it pulse for AoE arcane damage every 2s. Prefers non CC'd targets
		[258622] = { travel = false, name = "Resonant Quake" }, -- Unknown Mob, Motherlode - AoE nature hit that slows by 30% for 6s and leaves a puddle under the boss. AoE damage increased for each Earthrager and is lethal if the empowered Earthrager is alive
		[271456] = { travel = false, name = "Drill Smash" }, -- Unknown Mob, Motherlode - Razdunk flys above a random player after a delay and does an 8yd AoE on them, dealing AoE phys dam and extra to anyone hit, removes a stack of Configuration: Drill if it hits a Big Red Rocket
		[301088] = { travel = false, name = "Detonate" }, -- Bomb Tonk, Workshop - 200yd AoE fire hit
		[1215409] = { travel = false, name = "Mega Drill", channel = true }, -- Unknown Mob, Workshop - Channeled AoE nature hits, ticks every 1s for 5s
		[1215412] = { travel = false, name = "Corrosive Gunk" }, -- Metal Gunk, Workshop - Nature hit on 3 random targets that applies a healing absorb to players hit
		[473436] = { travel = false, name = "High-Explosive Rockets" }, -- Blastatron X-80, Workshop - Aura that deals fire damage to all players within 100yds every 4s
		[1216443] = { travel = false, name = "Electrical Storm" }, -- Tussle Tonks, Workshop - When one of the Tonks die they pulse for AoE nature dam and apply a stacking 20% nature dam taken increase every 2s
		[1215103] = { travel = false, name = "Ground Pound", channel = true }, -- Unknown Mob, Workshop - Channeled AoE phys hits, ticks every 0.5s for 4s
		[294929] = { travel = false, name = "Blazing Chomp" }, -- Unknown Mob, Workshop - Tank targeted Magic DoT that deals fire damage every 1s for 3mins, explodes for AoE fire dam on dispel
		[292022] = { travel = false, name = "Explosive Leap" }, -- Unknown Mob, Workshop - Leaps to 3 players starting with the furthest, dealing 8yd AoE fire dam around them which heats Junk Cubes hit
		[291946] = { travel = false, name = "Venting Flames", channel = true }, -- Unknown Mob, Workshop - Channeled AoE fire hits that heat all Junk Cubes, ticks every 1s for 5s, is likely lethal to anyone not hiding behind a Junk Cube
		[291626] = { travel = false, name = "Take Off!", channel = true }, -- Unknown Mob, Workshop - 8yd AoE followed by the boss fixating a random player with a Cutting Beam, dealing heavy nature damage to players under him and channeled AoE nature hits every 0.5s for 6s
		[292290] = { travel = false, name = "Protocol: Ninety-Nine" }, -- Unknown Mob, Workshop - After defeating Aerial Unit R-21/X the boss stuns all players and hops into the stationary Omega Buster which will do an AoE nature hit if no players are in melee
		[292264] = { travel = false, name = "Mega-Zap (P2)" }, -- Unknown Mob, Workshop - Random target line attack that targets 3 players in a row, dealing nature damage and applying a 12s DoT that increases Mega-Zap damage by 100%
		[283551] = { travel = false, name = "Magneto-Arm", channel = true }, -- Unknown Mob, Workshop - Channeled AoE nature hits that pull players and Plasma Orbs towards the far side of the room, damage reduced by distance, ticks every 1s for 9s
		[333241] = { travel = false, name = "Raging Tantrum", channel = true }, -- Raging Bloodhorn, Theatre of Pain - Channeled AoE phys hits tied to an Enrage, ticks every 2s for 4s
		[1215850] = { travel = false, name = "Earthcrusher" }, -- Unknown Mob, Theatre of Pain - 100yd AoE phys hit that creates many 4yd circles which deal nature damage to players hit
		[342135] = { travel = false, name = "Interrupting Roar" }, -- Nekthara the Mangler, Theatre of Pain - 100yd AoE phys hit that interrupts spellcasting
		[333839] = { travel = false, name = "Swift Strikes" }, -- Rek the Hardened, Theatre of Pain - Buff that increases attack speed by 50% and causes melees to hit 2 nearby players for 45% damage for 12s
		[333827] = { travel = false, name = "Seismic Stomp" }, -- Unknown Mob, Theatre of Pain - 60yd AoE phys hit
		[330716] = { travel = false, name = "Soulstorm", channel = true }, -- Unknown Mob, Theatre of Pain - Channeled AoE shadow hits, ticks every 2s for 8s
		[341969] = { travel = false, name = "Withering Discharge" }, -- Unknown Mob, Theatre of Pain - 50yd AoE plague hit that applies a 30s Disease DoT which reduces damage and healing done by 20%
		[345245] = { travel = false, name = "Disease Cloud" }, -- Rancid Gasbag, Theatre of Pain - Aura that deals Plague damage to all players every 2s
		[1215600] = { travel = false, name = "Withering Touch" }, -- Unknown Mob, Theatre of Pain - 12s Magic DoT on 2 random players
		[333292] = { travel = false, name = "Searing Death" }, -- Unknown Mob, Theatre of Pain - 8s shadow DoT on all players that cleaves anyone within 3yds, cast when Sathel reaches 100 energy
		[1215741] = { travel = false, name = "Mighty Smash" }, -- Unknown Mob, Theatre of Pain - AoE nature hit and 30% slow for 10s, cast when Dessia reaches 100 energy
		[320050] = { travel = false, name = "Might of Maldraxxus" }, -- Unknown Mob, Theatre of Pain - AoE phys hit followed by a combo of 3 abilities in a random order. Abilities are a random target line attack, random target 180 degree frontal, and 12yd AoE
		[473959] = { travel = false, name = "Draw Soul" }, -- Unknown Mob, Theatre of Pain - 8s shadow DoT on all players that spawns a Lost Soul on expiration. If these mobs reach the boss they do an AoE shadow hit
		[323825] = { travel = false, name = "Grasping Rift" }, -- Unknown Mob, Theatre of Pain - Opens a rift that deals AoE shadow damage every 1s for 6s and pulls players towards it, applying an 8s Curse DoT and stun to anyone who touches it
		[324449] = { travel = false, name = "Manifest Death" }, -- Unknown Mob, Theatre of Pain - 6s shadow DoT on all players that does a 6yd AoE on expiration and spawns a Deathwalker
		-- Unknown Mob, Theatre of Pain - A large shadow hit followed by pulsing shadow damage for the remainder of the fight, intermittently causes 8yd AoEs and charges through the arena to happen, cast at 50% health
		[339573] = { travel = false, name = "Echoes of Carnage" },
	},
    ["Tank Busters"] = {
        427950, 424420, 425536, 422628, 441351, 432229, 439031, 436624, 459799, 466190, 263628
    },
    ["Cast Cancel"] = { 
        427609, -- https://www.wowhead.com/ptr-2/spell=427609/disrupting-shout
        342135, -- https://www.wowhead.com/ptr-2/spell=342135/interrupting-roar
    }
}

local party_damage = {
    427404, 430812, 430805, 1214523, 1214628, 1214324, 444123, 424958, 425048, 423393, 423305, 429029,
    427609, 448492, 427897, 464240, 448791, 435156, 444743, 435156, 451763, 424419, 446368, 423051,
    423015, 423539, 428169, 423665, 428066, 424322, 430171, 1218117, 422541, 428268, 443835, 425394,
    423099, 420665, 421146, 426943, 427176, 428266, 463218, 463206, 441434, 448619, 442995, 440687,
    442525, 439365, 440104, 439524, 435789, 435622, 1214468, 468680, 465827, 471736, 469721, 1216611,
    1214780, 469981, 460156, 460867, 470038, 473070, 465456, 267354, 263628, 473168, 268702, 269429,
    262347, 256493, 257597, 258622, 271456, 301088, 1215409, 1215412, 473436, 1216443, 1215103,
    294929, 292022, 291946, 291626, 292290, 292264, 283551, 333241, 1215850, 342135, 342135, 333839,
    333827, 330716, 341969, 345245, 1215600, 333292, 1215741, 320050, 473959, 323825, 324449, 339573
}

local prio_party_damage = {
    427404, 430812, 444123, 425048, 423305, 464240, 448791, 444743, 451763, 446368, 323825, 339573,
    423015, 428169, 424322, 422541, 420665, 426943, 463218, 441434, 448619, 440687, 439524, 320050,
    465827, 471736, 469721, 470038, 465456, 267354, 263628, 473168, 268702, 269429, 341969, 330716,
    262347, 301088, 473436, 473436, 283551, 333241, 1214523,
    1214628, 1216611, 1214780, 1214468, 1215409
}

local tank_busters = {
    467908, 472549, 445457, 427629, 448485, 427950, 448515, 424420, 427596, 444728, 435165, 424414,
    422969, 425565, 428066, 425536, 427929, 469610, 422628, 422245, 434773, 443487, 456891, 441351,
    441397, 432229, 439031, 440134, 436624, 462735, 469766, 468672, 465820, 455588, 470005, 465666,
    473351, 459799, 469478, 466190, 263628, 263601, 268810, 259474, 320069, 320644, 330586, 330697,
    260318, 294073, 320300, 294929, 291878, 330565, 331316, 331288, 333845, 330875, 474087, 323515,
    324079, 1215411, 1213141, 1213139, 1215065
}

local prio_tank_busters = {
    427950, 424420, 425536, 422628, 441351, 432229, 439031, 436624, 459799, 466190, 263628
}

local magic_tank_busters = {
    472549, 445457, 448515, 424420, 435165, 469610, 443487, 441397, 440134, 462735, 455588, 465666,
    473351, 263628, 259474, 260318, 294929, 291878, 330875, 320300, 474087
}

local prio_magic_busters = {
    424420, 263628
}

local phys_tank_busters = {
    330565, 331316, 331288, 333845, 330586, 320069, 320644, 323515, 294073, 1215411, 1215065, 422969,
    1213141, 263601, 268810, 469766, 468672, 465820, 470005, 459799, 434773, 456891, 432229, 439031,
    436624, 425565, 425536, 427929, 422245, 427629, 448485, 424414
}

local prio_phys_busters = {
    459799, 432229, 439031, 436624, 425536
}

local mixed_tank_busters = {
    330697, 324079, 469478, 466190, 427950, 427596
}

local prio_mixed_busters = {
    466190, 427950
}

-- These are buffs applied to enemies that cause them to deal more damage or have an effect
local indirect_tank_busters = {
    1213139, 441351, 428066, 422628, 444728, 467908
}

-- Constructor
---@return RaidEvents
function RaidEvents.New()
    local instance = setmetatable({}, RaidEvents)

    return instance
end

-- Return time until the next event of the specified type
---@param event_type string
---@return number
function RaidEvents:TimeToNext(event_type)
    if not dungeon_events[event_type] then
        return 999
    end

    return 999
end

-- Return time until the next event of the specified type
---@param spell_id number|string
---@return number
function RaidEvents:TimeToSpell(spell_id)
    return 999
end

-- Return time until the next event of the specified type
---@param event_type string
---@return number
function RaidEvents:TimeSinceLast(event_type)
    if not dungeon_events[event_type] then
        return 999
    end

    return 999
end

-- Return time since a specific spell id was cast
---@param spell_id number | string
---@return number
function RaidEvents:TimeSinceSpell(spell_id)
    return 999
end

-- We will eventually need to make these registered functions, so we can have settings for users to turn on/off what they want to react to.

return RaidEvents