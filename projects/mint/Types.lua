--[[
    Types.lua
    This file contains class/type definitions for the addon framework
    to improve code organization and provide better IntelliSense support.
]]

-- Core Structs/Classes
---@class Vector3
---@field x number X coordinate
---@field y number Y coordinate
---@field z number Z coordinate
---@field Distance fun(self: Vector3, other: Vector3): number Calculate distance between two points
---@field IsWithinCone fun(self: Vector3, origin: Vector3, facing: number, angle: number, range: number): boolean Check if point is within a cone

---@class Unit
---@field name string Unit name
---@field id number Unit ID if available
---@field guid string GUID of the unit
---@field exists boolean Whether the unit exists
---@field hp number Health percentage (0-100)
---@field realized_hp number Realized health percentage accounting for incoming heals/damage
---@field is_dead boolean Whether the unit is dead
---@field is_enemy boolean Whether the unit is an enemy
---@field is_friend boolean Whether the unit is friendly
---@field dead boolean Whether the unit is dead (alias)
---@field role string Role of the unit (TANK, HEALER, DAMAGER, NONE)
---@field Update fun(self: Unit) Update unit's state
---@field GetExists fun(self: Unit): boolean Check if unit exists
---@field GetHP fun(self: Unit): number Get health percentage
---@field GetRealizedHP fun(self: Unit): number Get realized health percentage
---@field GetMaxHealth fun(self: Unit): number Get max health value
---@field GetHealth fun(self: Unit): number Get current health value
---@field GetPower fun(self: Unit, powerType?: number): number Get unit's power amount
---@field GetPP fun(self: Unit, powerType?: number): number Get unit's power percentage
---@field GetMaxPower fun(self: Unit, powerType?: number): number Get unit's max power
---@field GetPointer fun(self: Unit): string Get unit's WoW pointer/reference
---@field GetPosition fun(self: Unit): Vector3 Get unit's position
---@field GetFacing fun(self: Unit): number Get unit's facing angle
---@field GetDistance fun(self: Unit, other: Unit): number Get distance to another unit
---@field GetDistanceSquared fun(self: Unit, other: Unit): number Get squared distance (optimized check)
---@field GetAttackRange fun(self: Unit, other: Unit): number Get attack range distance
---@field GetAggroRange fun(self: Unit): number Get aggro radius for unit
---@field IsEnemy fun(self: Unit): boolean Check if unit is an enemy
---@field IsFriend fun(self: Unit): boolean Check if unit is friendly
---@field IsTank fun(self: Unit): boolean Check if unit is a tank
---@field IsHealer fun(self: Unit): boolean Check if unit is a healer
---@field IsDPS fun(self: Unit): boolean Check if unit is a dps
---@field HasLos fun(self: Unit, target?: Unit): boolean Check if unit has line of sight
---@field IsFacing fun(self: Unit, target: Unit, angle?: number): boolean Check if unit is facing target
---@field IsBehind fun(self: Unit, target: Unit, angle?: number): boolean Check if unit is behind target
---@field CanAttack fun(self: Unit, target: Unit): boolean Check if unit can attack target
---@field InMelee fun(self: Unit, target: Unit): boolean Check if unit is in melee range of target
---@field IsDead fun(self: Unit): boolean Check if unit is dead
---@field IsUnit fun(self: Unit, other: Unit): boolean Check if unit is same as another unit
---@field IsMounted fun(self: Unit): boolean Check if unit is mounted
---@field IsFlying fun(self: Unit): boolean Check if unit is flying
---@field IsMoving fun(self: Unit): boolean Check if unit is moving
---@field IsSwimming fun(self: Unit): boolean Check if unit is swimming
---@field IsChanneling fun(self: Unit): boolean Check if unit is channeling a spell
---@field IsCasting fun(self: Unit): boolean Check if unit is casting a spell
---@field IsCastingOrChanneling fun(self: Unit): boolean Check if unit is casting or channeling
---@field IsKickable fun(self: Unit): boolean Check if unit's cast can be interrupted
---@field GetCastSpellID fun(self: Unit): number Get spell ID being cast
---@field IsCastingSpell fun(self: Unit, spellId: number): boolean Check if casting specific spell
---@field GetCastPercent fun(self: Unit): number Get cast percentage
---@field GetTimeSinceStartedCast fun(self: Unit): number Get time since cast started
---@field GetEnemies fun(self: Unit, range: number): number Get number of enemies within range
---@field GetFriends fun(self: Unit, range: number): number Get number of friends within range
---@field IsFriendTanking fun(self: Unit, target: Unit): boolean Check if a friendly is tanking target
---@field FindBuff fun(self: Unit, spell: Spell, fromPlayer?: boolean): Aura Find buff by spell
---@field FindDebuff fun(self: Unit, spell: Spell, fromPlayer?: boolean): Aura Find debuff by spell
---@field FindAnyBuff fun(self: Unit, buffs: table): Aura Find any buff from a list
---@field HasDispellableAura fun(self: Unit, spell: Spell): boolean Check if unit has aura that can be dispelled
---@field HasSpellstealAura fun(self: Unit): boolean Check if unit has aura that can be stolen
---@field Create fun(pointer: string): Unit Create new unit from WoW pointer

---@class Aura
---@field id number Spell ID of the aura
---@field name string Name of the aura
---@field count number Stack count
---@field duration number Total duration
---@field expires number Expiration time
---@field caster string GUID of the caster
---@field isStealable boolean Whether the aura can be stolen
---@field dispelType string Type of aura for dispel purposes
---@field Active fun(self: Aura): boolean Check if aura is active
---@field Inactive fun(self: Aura): boolean Check if aura is not active
---@field Remains fun(self: Aura): number Get remaining time on aura
---@field Refresh fun(self: Aura): boolean Check if aura needs refreshing
---@field Count fun(self: Aura): number Get stack count

---@class Spell
---@field id number Spell ID
---@field name string Spell name
---@field charges number Current charges
---@field charges_frac number Fractional charges
---@field max_charges number Maximum charges 
---@field ready boolean Whether spell is ready to use
---@field on_cd boolean Whether spell is on cooldown
---@field known boolean Whether player knows this spell
---@field Cast fun(self: Spell, target: Unit): boolean Cast spell on target
---@field CastUnder fun(self: Spell, target: Unit): boolean Cast spell under target
---@field Castable fun(self: Spell, target: Unit): boolean Check if spell can be cast on target
---@field IsKnown fun(self: Spell): boolean Check if spell is known
---@field IsReady fun(self: Spell): boolean Check if spell is ready
---@field IsOnCD fun(self: Spell): boolean Check if spell is on cooldown
---@field IsInRange fun(self: Spell, target: Unit): boolean Check if target is in range
---@field GetCastTime fun(self: Spell): number Get cast time of spell
---@field GetTravelTime fun(self: Spell, target: Unit): number Get travel time to target
---@field GetCharges fun(self: Spell): number Get current charges
---@field GetChargesFractional fun(self: Spell): number Get fractional charges
---@field GetRechargeTime fun(self: Spell): number Get time until next charge
---@field GetFullRechargeTime fun(self: Spell): number Get time until fully recharged
---@field GetRemainingCD fun(self: Spell): number Get remaining cooldown
---@field AddCallback fun(self: Spell, name: string|function, callback?: function) Add callback function
---@field WasLastCast fun(self: Spell): boolean Check if this was the last spell cast
---@field WasMostRecentCast fun(self: Spell): boolean Check if this was most recent cast
---@field TimeSinceLastCast fun(self: Spell): number Get time since spell was last cast
---@field TimeSinceLastAttempt fun(self: Spell): number Get time since last cast attempt
---@field WasXOfYMostRecent fun(self: Spell, x: number, y: number): boolean Check if X of last Y spells was this one
---@field New fun(id: number, options?: table): Spell Create new spell object

---@class Item
---@field id number Item ID
---@field name string Item name
---@field ready boolean Whether item is ready to use
---@field has_cooldown boolean Whether item is on cooldown
---@field Use fun(self: Item, target: Unit): boolean Use item on target
---@field HasCooldown fun(self: Item): boolean Check if item is on cooldown
---@field GetRemainingCD fun(self: Item): number Get remaining cooldown
---@field AddCallback fun(self: Item, callback: function) Add callback function
---@field New fun(id: number, options?: table): Item Create new item object

---@class Sequence
---@field name string Name of the sequence
---@field is_running boolean Whether sequence is running
---@field current_step number Current step in sequence
---@field IsRunning fun(self: Sequence): boolean Check if sequence is running
---@field Execute fun(self: Sequence) Execute the sequence
---@field Reset fun(self: Sequence) Reset the sequence
---@field Abort fun(self: Sequence) Abort the sequence
---@field New fun(self: Sequence, name: string, steps: table, reset_func?: function, abort_func?: function): Sequence Create new sequence

-- Managers
---@class UnitManager
---@field Get fun(unit: string): Unit Get unit by reference
---@field GetLowestFriend fun(range?: number, hp?: number): Unit Get lowest health friendly unit
---@field GetLowest fun(hp_threshold?: number, filter?: function): Unit Get lowest health unit matching filter
---@field GetTanks fun(): table Get all tanks
---@field GetHealers fun(): table Get all healers
---@field GetDPS fun(): table Get all DPS
---@field GetCountBelow fun(hp: number): number Get count of friends below HP threshold
---@field GetPctFriendsWithBuff fun(aura: Aura): number Get percentage of friends with buff
---@field GetNumFriendsWithBuff fun(aura: Aura): number Get number of friends with buff
---@field CreateSmartUnit fun(name: string, func: function, interval?: number): Unit Create a smart unit target

---@class FriendManager
---@field GetLowest fun(hp_threshold?: number, filter?: function): Unit Get lowest health unit matching filter
---@field GetCountBelow fun(hp: number): number Get count of friends below HP threshold
---@field GetNumFriendsWithBuff fun(aura: Aura): number Get number of friends with buff
---@field GetTanks fun(): table Get all tanks
---@field GetHealers fun(): table Get all healers
---@field GetDPS fun(): table Get all DPS
---@field Loop fun(callback: function) Loop through all friends

---@class ObjectManager
---@field enemies table Collection of enemy units
---@field friends table Collection of friendly units
---@field units table Collection of all units
---@field combat table Collection of units in combat
---@field summons table Collection of units created by players

---@class EventManager
---@field RegisterWoWEvent fun(self: EventManager, event: string, callback: function) Register WoW event handler
---@field UnregisterWoWEvent fun(self: EventManager, event: string) Unregister WoW event handler
---@field New fun(): EventManager Create new event manager

---@class Actor
---@field Sync fun(self: Actor, callback: function) Synchronize actor with callback function
---@field GetUI fun(self: Actor): UIPage Get UI page for actor
---@field New fun(options: table): Actor Create new actor

---@class Dispel
---@field Scan fun(self: Dispel) Scan for dispellable effects
---@field ScanForDispel fun() Scan and attempt to dispel

---@class SmartTarget
---@field Acquire fun(self: SmartTarget) Acquire best target

---@class TotemManager
---@field IsActive fun(totemID: number): boolean Check if totem is active

---@class Queue
---@field IsInFlight fun(spellID: number): boolean Check if spell is in flight
---@field FlightRemains fun(spellID: number): number Get remaining flight time

---@class Cache
---@field Get fun(key: string): any Get cached value
---@field Set fun(key: string, value: any, duration?: number) Set cached value
---@field New fun(): Cache Create new cache

---@class Draw
---@field Text fun(self: Draw, text: string, font: string, x: number, y: number, z: number) Draw text in 3D space
---@field Line fun(self: Draw, startX: number, startY: number, startZ: number, endX: number, endY: number, endZ: number) Draw line in 3D space
---@field Circle fun(self: Draw, x: number, y: number, z: number, radius: number) Draw circle in 3D space
---@field Enable fun(self: Draw) Enable drawing
---@field Disable fun(self: Draw) Disable drawing
---@field Sync fun(self: Draw, callback: function) Synchronize drawing with callback
---@field New fun(): Draw Create new drawing object

---@class List
---@field Add fun(self: List, value: any) Add value to list
---@field Remove fun(self: List, value: any) Remove value from list
---@field Contains fun(self: List, value: any): boolean Check if list contains value
---@field Size fun(self: List): number Get size of list
---@field ForEach fun(self: List, callback: function) Apply function to each element
---@field ToTable fun(self: List): table Convert to standard table
---@field New fun(values?: table): List Create new list

---@class Interface
---@field AddQuickButton fun(texture: string, key: string, tooltip: string, callback: function) Add quick button to UI

---@class UIPage
---@field AddRow fun(margin?: number): UIRow Add row to page
---@field AddTabs fun(tabs: table): UITabs Add tabs to page

---@class UIRow
---@field AddToggle fun(options: table): UIToggle Add toggle control
---@field AddDropDown fun(options: table): UIDropDown Add dropdown control
---@field AddSlider fun(options: table): UISlider Add slider control
---@field AddTextInput fun(options: table): UITextInput Add text input control

---@class UIControl
---@field GetValue fun(): any Get control value
---@field SetValue fun(value: any) Set control value
---@field Show fun() Show control
---@field Hide fun() Hide control
---@field Enable fun() Enable control
---@field Disable fun() Disable control

---@class UIToggle : UIControl
---@field IsChecked fun(): boolean Check if toggle is checked

---@class UIDropDown : UIControl
---@field IsSelected fun(value: any): boolean Check if value is selected
---@field GetSelectedText fun(): string Get selected text

---@class UISlider : UIControl
---@field GetMin fun(): number Get minimum value
---@field GetMax fun(): number Get maximum value

---@class UITextInput : UIControl
---@field GetText fun(): string Get input text