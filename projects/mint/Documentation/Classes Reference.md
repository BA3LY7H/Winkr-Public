# Classes Reference

> API-style reference for every class in `Engine/Classes/`.

---

## Table of Contents

- [Unit](#unit)
- [Spell](#spell)
- [Aura](#aura)
- [AuraTable](#auratable)
- [Item](#item)
- [Actor](#actor)
- [List](#list)
- [Vector3](#vector3)
- [Timer](#timer)
- [Cache](#cache)
- [Draw](#draw)
- [EventManager](#eventmanager)
- [Keybinds](#keybinds)
- [SmartObject](#smartobject)
- [Command](#command)
- [Notification & NotificationManager](#notification--notificationmanager)
- [Queue](#queue)
- [EmpowerManager](#empowermanager)
- [TimeToDie](#timetodie)
- [Subdirectories (not detailed)](#subdirectories)

---

## Unit

> `Engine/Classes/Unit/Unit.lua` + `Engine/Classes/Unit/Attributes.lua`

A Unit wraps a WoW unit token or GUID with cached health, aura, distance, casting, and combat data.

### Constructor

```lua
local unit = Unit:Create(token, isOMUnit?)
-- token: string (unit token like "player" or a GUID)
-- isOMUnit: boolean (true if created by ObjectManager)
```

### Key Properties

| Property | Type | Description |
|----------|------|-------------|
| `guid` | string | GUID of the unit |
| `name` | string | Unit name |
| `class` | string | Localized class name |
| `health` | number | Current health |
| `max_health` | number | Maximum health |
| `hp` | number | Health percentage (0–100) |
| `realized_hp` | number | `(health + absorbs - heal_absorbs) / max_health * 100` |
| `heal_absorbs` | number | Total heal absorbs |
| `absorbs` | number | Total damage absorbs |
| `heal_prediction` | number | Incoming heals |
| `role` | string | `"TANK"`, `"HEALER"`, `"DAMAGER"`, `"NONE"` |
| `is_dead` / `dead` | boolean | Dead or ghost |
| `in_range` | boolean | UnitInRange result |
| `can_assist` | boolean | Friendly |
| `can_attack` | boolean | Hostile/attackable |
| `in_combat` | boolean | OM-detected combat state |
| `id` | number | NPC/creature ID |
| `level` | number | Unit level |
| `reaction` | number | UnitReaction value |
| `race` | string | Non-localized race |
| `exists` | boolean | Cached GetExists() |
| `alive` | boolean | Inverse of is_dead |

### Key Methods

| Method | Signature | Returns | Description |
|--------|-----------|---------|-------------|
| `Update()` | `() → nil` | — | Refresh all cached properties |
| `GetPointer()` | `() → string` | token/GUID | Resolve best pointer (prefers standard tokens) |
| `GetExists()` | `() → boolean` | — | Validates via winkr or WoW API |
| `IsUnit(other)` | `(Unit\|string) → boolean` | — | UnitIsUnit comparison |
| `GetPosition()` | `() → Vector3` | position | 3D world position |
| `GetDistance(other?)` | `(Unit?) → number` | yards | Distance to another unit (defaults to player) |
| `GetDistanceSquared(other)` | `(Unit) → number` | — | Squared distance |
| `IsWithin(limit, other?)` | `(number, Unit?) → boolean` | — | Distance check |
| `IsFacing(unit, bound?)` | `(Unit, number?) → boolean` | — | Facing within ±bound degrees (default 90) |
| `InMelee(unit)` | `(Unit) → boolean` | — | Melee range check using combat reach |
| `HasLos(unit?)` | `(Unit?) → boolean` | — | Line-of-sight via TraceLine (cached 0.4s) |
| `GetAttackRange(other?)` | `(Unit?) → number` | yards | Distance minus combat reach |
| `GetCombatReach()` | `() → number` | — | Object combat reach |

#### Health

| Method | Returns | Description |
|--------|---------|-------------|
| `GetHealth()` | number | Current HP |
| `GetMaxHealth()` | number | Max HP |
| `GetHP()` | number | HP percentage |
| `GetAbsorbs()` | number | Damage absorb shields |
| `GetHealAbsorbs()` | number | Heal absorbs |
| `GetRealizedHealth()` | number | `health - heal_absorbs` |
| `GetRealizedHP()` | number | Realized HP percentage |
| `GetPredictedHP(from?)` | number | Realized HP + incoming heals |
| `GetIncomingHealing(from?)` | number | Incoming heals (optionally filtered by source) |

#### Power

| Method | Returns | Description |
|--------|---------|-------------|
| `GetPowerType()` | number | Power type enum |
| `GetPower(powerType?)` | number | Current power |
| `GetMaxPower(powerType?)` | number | Max power |
| `GetPP(powerType?)` | number | Power percentage |
| `GetRunes()` | number | Active rune count (DK) |
| `TimeToMaxPower(powerType?)` | number | Seconds to cap (cached 0.25s) |
| `TimeToMaxEnergy()` | number | Shortcut for energy |
| `TimeToMaxFocus()` | number | Shortcut for focus |

#### Casting

| Method | Returns | Description |
|--------|---------|-------------|
| `IsCasting()` | boolean | Currently casting |
| `IsChanneling()` | boolean | Currently channeling |
| `IsCastingOrChanneling()` | boolean | Either |
| `IsCastingSpell(spell_id)` | boolean | Casting specific spell |
| `GetCastSpellID()` | number\|nil | Spell ID being cast/channeled |
| `GetCastSpell()` | Spell\|nil | Spell object for current cast |
| `GetCastEndTime()` | number | End time (seconds) |
| `TimeToCast()` | number | Remaining cast time |
| `GetCastPercent()` | number | Cast completion percentage |
| `IsWithinCastWindow(min, max)` | boolean | Cast % within [min, max] |
| `IsKickable()` | boolean | Current cast is interruptible |
| `GetCastTarget()` | string | GUID of cast target |

#### Aura Queries

| Method | Returns | Description |
|--------|---------|-------------|
| `FindBuff(spell_id, playerOnly?)` | Aura | By spell name |
| `FindDebuff(spell_id, playerOnly?)` | Aura | By spell name |
| `FindBuffByID(spell_id, playerOnly?)` | Aura | By index scan (spell ID) |
| `FindDebuffByID(spell_id, playerOnly?)` | Aura | By index scan (spell ID) |
| `FindOwnBuffByID(spell_id)` | Aura | Player-only buff (optimized) |
| `FindAnyBuff(spell_list, playerOnly?)` | Aura | First active from List |
| `FindAnyDebuff(spell_list, playerOnly?)` | Aura | First active from List |
| `FindAnyBuffByID(spell_list)` | Aura | First active by ID from List |
| `FindLongestBuffFromList(list, playerOnly?)` | Aura | Longest-remaining active buff |
| `FindLongestDebuffFromList(list, playerOnly?)` | Aura | Longest-remaining active debuff |
| `HasDebuffType(types, checkWhitelist?)` | boolean | Has debuff of dispel type |
| `HasDispellableAura(spell)` | boolean, Aura | Dispellable aura with delay |
| `HasSpellstealAura()` | boolean | Spellstealable buff active |
| `HasPurgeAura()` | boolean | Purgeable buff active |
| `HasSootheAura()` | boolean | Sootheable buff active |

#### Status & Classification

| Method | Returns | Description |
|--------|---------|-------------|
| `IsBoss()` | boolean | Boss classification (multi-heuristic) |
| `IsDummy()` | boolean | Training dummy (NPC ID lookup) |
| `IsFriend()` / `IsEnemy()` | boolean | Faction check |
| `IsDead()` | boolean | Dead or ghost |
| `IsMoving()` | boolean | GetUnitSpeed > 0 |
| `IsFlying()` / `IsMounted()` / `IsSwimming()` | boolean | State checks |
| `IsInCombat()` | boolean | UnitAffectingCombat |
| `IsPartyInCombat()` | boolean | Any friend in combat |
| `IsTank()` | boolean | Role is TANK |
| `IsTanking(enemy)` | boolean | Has threat on enemy |
| `CanCastMove()` | boolean | Has a movement-casting buff |

#### CC Immunity (MDT data)

`CanDisorient()`, `CanGrip()`, `CanFear()`, `CanRoot()`, `CanSilence()`, `CanSlow()`, `CanStun()`, `CanTaunt()`, `CanIncapacitate()`, `CanInterrupt()` — all return `boolean` based on `Constants.TWWS3.mdt_data[unit.id]`.

#### Counting

| Method | Returns | Description |
|--------|---------|-------------|
| `GetEnemies(radius)` | number | Enemies within radius (cached 0.25s) |
| `GetMeleeCount()` | number | Enemies in melee range (cached 0.25s) |
| `IsWithinCone(tar, halfAngle, dist, rotation?)` | boolean | Target within cone |

#### Combat Tracking

| Method | Returns | Description |
|--------|---------|-------------|
| `TimeSinceLastCombatEvent()` | number | Seconds since last CLEU event |
| `UpdateCombatTimer(time)` | nil | Set last combat event time |
| `CombatConfidence()` | number | 0–100 combat likelihood score |
| `GetDanger()` / `SetDanger(id, exp)` | number/nil | Track dangerous timers on unit |

---

## Spell

> `Engine/Classes/Spell/Spell.lua` + `Attributes.lua` + `Methods.lua`

Represents a WoW spell with metadata, cooldown tracking, castability checks, and a callback system.

### Constructor

```lua
local spell = Spell.New(spell_id, traits?)
```

**Traits table (all optional):**

| Key | Type | Description |
|-----|------|-------------|
| `radius` | number | AoE radius |
| `beneficial` | boolean | Friendly spell (skips facing check) |
| `damage` / `heal` | string/boolean | Damage/heal type |
| `effect` | string/boolean | Effect type |
| `cc` | string/boolean | CC type |
| `bleed` | boolean | Bleed effect |
| `kick` | boolean | Interrupt spell |
| `ranged` | boolean | Ranged spell |
| `pet` | boolean | Pet ability |
| `cast_by_id` | boolean | Use CastSpellByID instead of ByName |
| `velocity` | number | Projectile speed (yd/s) |
| `travel_time` | number | Fixed travel time |
| `targeted` | boolean | Requires a target (default true) |
| `ignore_facing` | boolean | Skip facing check |
| `ignore_los` | boolean | Skip LoS check |
| `ignore_control` | boolean | Skip loss-of-control check |
| `ignore_moving` | boolean | Skip movement check |
| `ignore_casting` | boolean | Cast while casting |
| `ignore_channel` | boolean | Cast while channeling |
| `ignore_falling` | boolean | Skip falling check |
| `ignore_range` | boolean | Skip range check |
| `ignore_stun` | boolean | Skip stun check |
| `ignore_known` | boolean | Skip IsKnown check |
| `ignore_usable` | boolean | Skip IsUsable check |
| `prevent_double` | boolean | Don't double-cast |
| `required_buff` | boolean | Requires a buff to cast |
| `stupid_channel` | boolean | Channel with special handling |

### Callable Spell Pattern

Spells are callable. `spell(unit)` calls `spell:Cast(unit)`. `spell("key")` calls `spell:Invoke("key")`.

### Key Computed Properties (via metatable)

| Property | Type | Description |
|----------|------|-------------|
| `cd` / `cooldown` | number | Remaining cooldown |
| `base_cd` | number | Base cooldown (unmodified) |
| `max_cd` | number | Base cooldown duration |
| `on_cd` | boolean | On real cooldown (> max_gcd + 0.2s) |
| `ready` | boolean | Not on CD |
| `charges` | number | Current charges |
| `charges_frac` | number | Fractional charges |
| `charges_max` | number | Max charges |
| `next_charge_cd` | number | Time until next charge |
| `max_charge_cd` | number | Full recharge cooldown |
| `cast_time` | number | Cast time in seconds |
| `known` | boolean | IsKnown |
| `usable` | boolean | IsUsable |
| `cost` | number | Power cost |
| `count` | number | SpellCastCount |
| `range` | number | Max spell range |
| `gcd` | number | GCD duration |
| `effect` / `damage` | any | Spell effect value |
| `flying` | boolean | Projectile in flight |
| `queued` | boolean | Queued for cast |
| `used` | boolean | Used recently (pass seconds) |
| `proc` | boolean | Currently procced |
| `dispel_magic` / `dispel_curse` / `dispel_poison` / `dispel_disease` | boolean | Can dispel type |

### Key Methods

| Method | Returns | Description |
|--------|---------|-------------|
| `Cast(unit, rank?)` | boolean | Full castability check + cast; rank triggers EmpowerManager |
| `CastEmpower(unit, level)` | boolean | Empowered cast |
| `CastUnder(unit)` | boolean | Ground-targeted AoE at unit position |
| `CastWithPreCast(unit, precast, key?)` | boolean | Cast with a pre-condition function |
| `CastNotify(unit, text?, dur?, icon?, key?)` | boolean | Cast + show notification |
| `Castable(unit, options?)` | boolean | Full target validation |
| `PreCheck()` | boolean | Pre-callback checks (CD, usable, known, moving, casting) |
| `AddCallback(key, callback)` | nil | Register a rotation callback |
| `Invoke(key, ...)` | any | Execute callback (runs PreCheck first) |
| `IsOnCD()` | boolean | `GetCD() > max_gcd + 0.2` |
| `IsReady()` | boolean | Not on CD |
| `IsKnown()` | boolean | Known/player spell/override |
| `IsUsable()` | boolean | Usable and has resources |
| `IsInRange(unit)` | boolean | Range check with fallback |
| `GetChargesFractional()` | number | Partial charge recovery |
| `GetFullRechargeTime()` | number | Time until all charges available |
| `TimeSinceLastCast()` | number | Seconds since UNIT_SPELLCAST_SUCCEEDED |
| `TimeSinceLastAttempt()` | number | Seconds since last Cast() call |
| `WasMostRecentCast()` | boolean | Was the last spell cast |
| `WasLastCast()` | boolean | Has ever been cast this session |
| `WasXOfYMostRecent(count, depth)` | boolean | Cast X times in last Y casts |
| `IsCurrentCast()` | boolean | Currently being cast by player |
| `CanAfford()` | boolean | Has enough resources |
| `GetTravelTime()` | number | Fixed travel time from traits |
| `GetDispelType()` | string\|nil | First dispel type this spell can do |
| `CanDispelType(type)` | boolean | Can dispel the given type |
| `GetAllDispelTypes()` | table | All dispel types keyed by type name |

---

## Aura

> `Engine/Classes/Aura.lua`

Wraps WoW `AuraData` with convenience accessors.

### Constructors

```lua
Aura.CreateFromAuraData(aura_data)   -- from C_UnitAuras result
Aura.CreateBlank()                   -- "no aura" sentinel
```

### Key Methods

| Method | Returns | Description |
|--------|---------|-------------|
| `IsValid()` | boolean | Has a name |
| `Active()` | boolean | Valid + has remaining duration (or infinite) |
| `Inactive()` | boolean | Not active |
| `Remains()` | number | Remaining seconds |
| `Refresh()` | boolean | Below 30% pandemic threshold |
| `Count()` | number | Stack count (applications) |
| `Value()` | number[] | Aura points array |
| `GetDuration()` | number | Total duration |
| `GetSpellID()` | number | Spell ID |
| `GetName()` | string | Aura name |
| `GetType()` | string | `"HARMFUL"` or `"HELPFUL"` |
| `GetDispelClass()` | string | `"Magic"`, `"Curse"`, `"Poison"`, `"Disease"` |
| `GetSource()` | Unit\|nil | Source unit |
| `GetCastByPlayer()` | boolean | From player or player's pet |
| `IsDispelableBySpell(spell)` | boolean | Checks dispel type compatibility |
| `IsBuff()` / `IsDebuff()` | boolean | Buff or debuff |
| `GetSpell()` | Spell | Spell object for this aura |

---

## AuraTable

> `Engine/Classes/AuraTable.lua`

**Currently commented out / disabled.** Was an event-driven aura tracking system using `UNIT_AURA` updates with instance-ID-based incremental tracking. Not in active use — the Unit class queries auras directly via `C_UnitAuras` each time.

---

## Item

> `Engine/Classes/Item/Item.lua` + `Item/Methods.lua`

Wraps a WoW item with cooldown tracking, usability checks, and a callback system mirroring Spell.

### Constructor

```lua
local item = Item.New(item_id, traits?)
-- traits.use_name: boolean -- use item name instead of item spell
```

### Key Computed Properties (via metatable)

Same pattern as Spell: `cd`, `on_cd`, `ready`, `charges`, `known`, `usable`, etc.

### Key Methods

| Method | Returns | Description |
|--------|---------|-------------|
| `Use(unit)` | boolean | Use item on unit via C_Item.UseItemByName |
| `AddCallback(key, callback)` | nil | Register callback |
| `Invoke(key, ...)` | any | Execute callback |
| `IsEquipped()` | boolean | Item equipped |
| `IsUsable()` | boolean | C_Item.IsUsableItem |
| `IsEquippedAndUsable()` | boolean | Equipped (or non-equippable + usable) + not on CD |
| `Usable()` | boolean | Alias for IsEquippedAndUsable |
| `HasCooldown()` | boolean | CD > max_gcd + 0.1 |
| `GetCooldown()` | number | Item cooldown duration |

---

## Actor

> `Engine/Classes/Actor.lua`

A rotation actor — owns a set of synced callback functions and runs them each tick if class/spec/condition match.

### Constructor

```lua
local actor = Actor.New({ class = "warrior", spec = 1, condition = fn? })
-- spec: number (1–4 spec INDEX from GetSpecialization(), not a spec ID)
```

Automatically inserts itself into `mint.data.actors[]`.

### Key Methods

| Method | Description |
|--------|-------------|
| `Sync(func, rate?)` | Register a callback (default 50ms rate) |
| `ShouldRun()` | Check class + spec + optional condition |
| `Tick()` | Run all synced callbacks that are past their rate |
| `GetUI()` | Create an Interface Page for this actor's spec |

---

## List

> `Engine/Classes/List.lua`

A generic ordered list with functional iteration (JS Array-style API).

### Constructor

```lua
local list = List:New(from?)   -- from: optional initial table
```

### Methods

| Method | Signature | Returns |
|--------|-----------|---------|
| `push(value)` | `(any) → nil` | — |
| `pop()` | `() → any` | Last element |
| `peek()` | `() → any` | Last element (no remove) |
| `count()` | `() → number` | Length |
| `clear()` | `() → nil` | Empty the list |
| `contains(value)` | `(any) → boolean` | — |
| `remove(value)` | `(any) → boolean` | Remove first match |
| `each(cb)` / `loop(cb)` | `(fn) → nil` | Iterate; break on `true` |
| `map(cb)` | `(fn) → List` | Transform |
| `filter(cb)` | `(fn) → List` | Filter |
| `reduce(cb, init)` | `(fn, any) → any` | Accumulate; break on second return `true` |
| `find(cb)` | `(fn) → any\|nil` | First match |
| `findIndex(cb)` | `(fn) → number\|nil` | Index of first match |
| `sort(cb)` | `(fn) → nil` | In-place sort |
| `reverse()` | `() → List` | New reversed list |
| `clone()` | `() → List` | Shallow copy |
| `concat(list)` | `(List) → List` | New concatenated list |
| `join(sep)` | `(string) → string` | String join |

**Operator overloads:** `+` (push), `-` (remove).

---

## Vector3

> `Engine/Classes/Vector3.lua`

3D vector class with full arithmetic, stored as `{ x, y, z }` (array indices 1, 2, 3). Properties `x`, `y`, `z` are aliased via `__index`/`__newindex`.

### Constructor

```lua
local v = Vector3:New(x, y, z)
```

### Computed Properties

`length`, `magnitude`, `sqrMagnitude`, `normalized` — via `__index`.

Static constants: `zero`, `one`, `up`, `down`, `left`, `right`, `forward`, `back`.

### Key Methods

| Method | Returns | Description |
|--------|---------|-------------|
| `Distance(b)` | number | Euclidean distance |
| `DistanceSquared(b)` | number | Squared distance |
| `Dot(rhs)` | number | Dot product |
| `Cross(rhs)` | Vector3 | Cross product |
| `Angle(to)` | number | Angle in radians |
| `Angle2D(to)` | number | atan2 angle |
| `Lerp(b, t)` | Vector3 | Linear interpolation |
| `MoveTowards(target, delta)` | Vector3 | Step towards target |
| `Normalize()` | Vector3 | Unit vector |
| `Project(onNormal)` | Vector3 | Vector projection |
| `Reflect(inNormal)` | Vector3 | Reflection |
| `Pitch(to)` | number | Vertical angle |
| `GroundZ()` | Vector3 | TraceLine to ground |
| `IsNearGround()` | boolean | Within 5yd of ground |
| `IsAbove(other, range)` | boolean | Z comparison |
| `IsVisibleTo(other)` | boolean | TraceLine LoS |
| `GetCentroid(vectors)` | Vector3 | Average position |
| `Humanize()` | Vector3 | Add small random offset (±2yd) |
| `IsValid()` | boolean | Non-nil, non-zero |

**Operator overloads:** `+`, `-`, `*`, `/`, `==`, `<`, `<=`, `#` (length), unary `-`.

---

## Timer

> `Engine/Classes/Timer.lua`

Simple stopwatch timer.

### Constructor

```lua
local timer = Timer:New(duration?)
```

### Methods

| Method | Returns | Description |
|--------|---------|-------------|
| `Start()` | nil | Set startTime to now |
| `GetTime()` | number | Seconds since start (0 if not running) |
| `IsRunning()` | boolean | Started and not reset |
| `Reset()` | nil | Clear startTime |
| `GetRemainingTime()` | number | `endTime - GetTime()` |
| `GetTimeSinceEnded()` | number | `GetTime() - endTime` |

---

## Cache

> `Engine/Classes/Cache.lua`

Time-based key/value cache. Expired entries auto-purge on access.

### Constructor

```lua
local cache = Cache.New()
```

### Methods

| Method | Signature | Returns | Description |
|--------|-----------|---------|-------------|
| `Set(key, value, duration)` | `(any, any, number) → nil` | — | Store for `duration` seconds |
| `Get(key)` | `(any) → any\|nil` | value | Returns nil if expired |
| `IsCached(key)` | `(any) → boolean` | — | Check without removing |

---

## Draw

> `Engine/Classes/Draw.lua`

Immediate-mode 3D drawing system using WoW line/texture/fontstring pools on a canvas frame overlaying WorldFrame.

### Constructor

```lua
local draw = Draw:New()
```

### Key Methods

| Method | Signature | Description |
|--------|-----------|-------------|
| `Sync(callback)` | `(fn) → nil` | Register a draw callback |
| `Enable()` / `Disable()` | `() → nil` | Start/stop the OnUpdate loop |
| `SetColor(r, g, b, a)` | `(0–255) → nil` | Set draw color |
| `SetWidth(w)` | `(number) → nil` | Set line width |
| `Line(x1,y1,z1, x2,y2,z2)` | world coords | 3D line (auto-subdivides long lines) |
| `Line2D(sx,sy, ex,ey)` | screen coords | 2D screen-space line |
| `Circle(x,y,z, radius, steps?)` | world coords | Circle on ground (default 40 segments) |
| `Text(text, font, x,y,z)` | world coords | Floating text |
| `Arc(x,y,z, size, arc, rotation)` | world coords | Arc/sector |
| `Sector(x,y,z, rotation, radius, fov)` | world coords | Cone sector |
| `Array(vectors, x,y,z, rotation?)` | world coords | Shape from vector offsets |
| `Texture(config, x,y,z, alpha?)` | world coords | Textured billboard |
| `WorldToScreen(wx,wy,wz)` | `→ sx,sy\|false` | Convert world to screen |

---

## EventManager

> `Engine/Classes/EventManager.lua`

Dual event bus — handles both custom events and WoW frame events.

### Constructor

```lua
local events = EventManager.New()
```

### Methods

| Method | Description |
|--------|-------------|
| `RegisterEvent(event, handler)` | Register custom event callback |
| `RegisterWoWEvent(event, handler)` | Register WoW frame event (auto-registers on internal frame) |
| `TriggerEvent(event, ...)` | Fire custom event to all handlers |

WoW events fire through the internal frame's `OnEvent` script. Custom events fire through `TriggerEvent()`.

---

## Keybinds

> `Engine/Classes/Keybinds.lua`

Manages rotation keybind overrides — custom key combos that trigger specific spells.

### Constructor

```lua
local keybinds = Keybinds:New()
```

### Key Methods

| Method | Description |
|--------|-------------|
| `Tick()` | Poll all keybinds each tick; returns true if a keybind was consumed |
| `ParseKeyCombination(key)` | Split `"SHIFT-M"` → `"M"`, `"SHIFT"` |
| `HandleCast(data)` | Cast spell by ID to configured target (Self/Target/Mouseover/Focus/Cursor) |
| `StartListening(table, cell, row, idx)` | Enter keybind recording mode for UI |
| `StopListening()` | Exit recording mode |
| `BindKey(pending, newKey)` | Assign a new keybind |
| `UnbindKey(pending)` | Remove a keybind |

---

## SmartObject

> `Engine/Classes/SmartObject.lua`

A lazy-evaluated proxy. Wraps a callback that produces a value; optionally caches the result for a duration. Access any key on the SmartObject and it transparently refreshes via the callback.

### Constructor

```lua
local smart = SmartObject:New(initialValue, callback, cacheTime?)
```

### Methods

| Method | Returns | Description |
|--------|---------|-------------|
| `Update()` | nil | Force refresh |
| `Get(...)` | any | Call callback with args |

**`__index`:** Any unknown key triggers the callback (or cache lookup), then returns `self.value[k]`. This is how `UnitManager:Get("player")` returns a SmartObject that behaves like a Unit.

---

## Command

> `Engine/Classes/Command.lua`

Slash command framework. Creates `/prefix` commands with subcommands.

### Constructor

```lua
local cmd = Command:New("mint")   -- creates /mint
```

### Methods

| Method | Description |
|--------|-------------|
| `Register(command, helpmsg, cb)` | Register a subcommand |
| `OnCommand(msg)` | Parse and dispatch |
| `PrintHelp()` | Print all commands to chat |

---

## Notification & NotificationManager

> `Engine/Classes/Notification.lua` + `NotificationManager.lua`

On-screen notification system with icon + text, auto-fade, and duplicate prevention.

### NotificationManager

```lua
local mgr = NotificationManager:New()
mgr:AddNotification(icon, text, duration, spam?)
mgr:RemoveNotification(notification)
mgr:RemoveAllNotifications()
```

### Notification

Created internally by `NotificationManager:AddNotification`. Auto-removes after `duration` seconds. Fade-out animation via `UIFrameFadeOut`.

---

## Queue

> `Engine/Classes/Queue/Queue.lua`

Event queue for projectile tracking and timed events.

### Constructor

```lua
local queue = Queue:New()
```

### Methods

| Method | Signature | Description |
|--------|-----------|-------------|
| `AddEvent(key, start, time, type, target)` | `(number, number, number, string, string?) → nil` | Add timed event |
| `RemoveEvent(key, type, reverse?)` | `(number, string, boolean?) → boolean` | Remove event by key+type |
| `IsInFlight(spell_id)` | `(number) → boolean` | Projectile currently in flight |
| `FlightRemains(spell_id)` | `(number) → number` | Seconds until impact (0 if not in flight) |

Built-in `ProjectileInfo` table: Arcane Blast (44425), Fireball (133), Phoenix Flames (257541), Pyroblast (11366).

---

## EmpowerManager

> `Engine/Classes/Spell/Empower.lua`

Manages Evoker empowered spell releases. When `Spell:Cast(unit, rank)` is called with a numeric rank, EmpowerManager schedules a timed release.

### Key Methods

| Method | Description |
|--------|-------------|
| `Prepare(spell_id, rank, guid?)` | Set up for incoming empowered cast |
| `ScheduleRelease(event_spell_id)` | Calculate stage durations and schedule `UseAction` via `C_Timer` |
| `Reset()` | Cancel pending timer and clear state |

Listens for `UNIT_SPELLCAST_EMPOWER_START`, `UNIT_SPELLCAST_EMPOWER_STOP`, `UNIT_SPELLCAST_INTERRUPTED`.

---

## TimeToDie

> `Engine/Classes/TimeToDie.lua`

HP regression-based time-to-die estimator with weighted linear regression and boss-specific phase thresholds.

### Key Methods

| Method | Returns | Description |
|--------|---------|-------------|
| `Refresh()` | nil | Sample HP for all enemies (throttled to 0.5s) |
| `GetTTD(unit)` | number | Per-frame cached TTD estimate |
| `Estimate(unit)` | number | Weighted linear regression |
| `FightRemains(enemies?, bossOnly?)` | number | Max TTD across fight |
| `ActiveFightRemains(only_bosses?)` | number | Max TTD for active combat |
| `BossFightRemains()` | number | Boss-only TTD |
| `FilteredFightRemains(enemies, op, value, checkValid, bossOnly)` | boolean | Compare fight remains |
| `EffectiveEndPercent(unit)` | number | Boss phase-specific kill % |

**Constants:** `INVALID = 11111` (unknown/immortal), `MIN_SAMPLES = 3`, `TAU = 4.0` (recency weight), `HistoryTime = 10.4s`.

---

## Subdirectories

These subdirectories exist under `Engine/Classes/` but are not detailed here:

| Directory | Contents |
|-----------|----------|
| `Database/` | Static data tables |
| `Item/` | Item.lua, Methods.lua (covered above) |
| `Queue/` | Queue.lua (covered above) |
| `RaidEvents/` | Raid event tracking |
| `Spell/` | Spell.lua, Attributes.lua, Methods.lua, Empower.lua (covered above) |
| `Unit/` | Unit.lua, Attributes.lua (covered above) |
| `Utility/` | Utility helpers including SmartTarget (Targets.lua) |

Additional files in Classes root: `DebugFrame.lua`, `Reaction.lua`, `Sequencer.lua`, `TotemManager.lua`.
