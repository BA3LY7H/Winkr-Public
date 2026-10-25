# State & Data

> How MINT manages global state, caching, timers, events, and the per-tick data flow.

---

## Table of Contents

- [mint.data Structure](#mintdata-structure)
- [mint Global Metatable](#mint-global-metatable)
- [Toggle System](#toggle-system)
- [Cache System](#cache-system)
- [Timer System](#timer-system)
- [EventManager](#eventmanager)
- [State Flow Through a Tick](#state-flow-through-a-tick)

---

## mint.data Structure

Defined in `loader.lua`. This is the shared mutable state bag accessible as `mint.data` everywhere.

```lua
mint.data = {
    actors = {},              -- Actor[] — registered rotation actors
    dungeons = {},            -- Dungeon-specific data tables
    lastCastTimers = {},      -- [spellID] = GetTime() — last UNIT_SPELLCAST_SUCCEEDED
    debug_mode = true,        -- Toggle with /mintdebug
    toggles = {               -- Boolean engine toggles
        engine = false,       -- Master on/off
        cooldowns = false,    -- Allow major cooldowns
        kicks = false,        -- Allow interrupts
        defensives = false,   -- Allow defensive abilities
        dispels = false,      -- Allow dispels
        purges = false,       -- Allow purges/spellsteals
    },
    vars = {
        debug_start_time = debugprofilestop(),  -- Timestamp for console log
        dispel_delay = 0.5,                     -- Seconds to wait before dispelling
    },
    active_branch = "reactions",  -- Load-order branch (default "reactions")
    _log_buffer = {},             -- Ring buffer for debug.log file (max 300 lines)
}
```

### Runtime additions (set by various subsystems)

| Key | Set by | Type | Description |
|-----|--------|------|-------------|
| `mint.combatStartTime` | Core.lua CLEU | number | `GetTime()` when combat begins |
| `mint.data.lastCastOrder` | Core.lua events | table | `spellID[]` — ordered history of recent casts (lazy-created) |
| `mint.data.MoveTimer` | Core.lua events | Timer | Tracks time player has been moving |
| `mint.data.StopTimer` | Core.lua events | Timer | Tracks time player has been stopped |
| `mint.Queue` | Loader | Queue | Projectile tracking queue |
| `mint.events` | Core.lua init | EventManager | Global event bus |
| `mint.ObjectManager` | Loader | ObjectManager | Enemy/friendly object lists |
| `mint.UnitManager` | Loader | UnitManager | Unit cache and smart units |
| `mint.FriendManager` | Loader | FriendManager | Party/raid tracking |
| `mint.TimeToDie` | Loader | TimeToDie | HP regression estimator |
| `mint.EmpowerManager` | Empower.lua | EmpowerManager | Evoker empower release |
| `mint.Settings` | Loader | table | Saved keybinds, profile settings |
| `mint.Constants` | Loader | table | Spell lists, NPC data, dispel maps |
| `mint.Interface` | Loader | table | UI framework |
| `mint.Draw` | Loader | Draw | Draw class (world-space drawing) |
| `mint.json` | Loader | table | JSON encoder/decoder |

---

## mint Global Metatable

Set in `loader.lua` via `setmetatable(mint, { __index = ... })`. Provides lazy-computed properties that are recalculated on every access — no caching, always fresh values.

```lua
setmetatable(mint, {
    __index = function(instance, k)
        if k == "max_gcd" then ... end
        if k == "gcd" then ... end
        if k == "latency" then ... end
        if k == "class" then ... end
        if k == "specId" then ... end
        if k == "specName" then ... end
        return rawget(mint, k)
    end,
})
```

| Property | Computation | Type | Notes |
|----------|-------------|------|-------|
| `mint.max_gcd` | `base / (1 + haste/100)` | number (sec) | Base is 1.0 for energy classes (powerType 3), 1.5 otherwise. Haste capped at 50%. |
| `mint.gcd` | Remaining GCD from `C_Spell.GetSpellCooldown(61304)` | number (sec) | Returns 0 if GCD is not active. |
| `mint.latency` | `select(3, GetNetStats()) / 1000` | number (sec) | Home latency. |
| `mint.class` | `string.lower(select(2, UnitClass("player")))` | string | Lowercase English class token, e.g. `"warrior"` |
| `mint.specId` | `GetSpecializationInfo(GetSpecialization())` | number | Specialization ID |
| `mint.specName` | `string.lower(...)` | string | Lowercase spec name, e.g. `"devastation"` |

**Important:** These are **not** cached — every access runs the computation. This ensures freshness but means hot loops should capture the value in a local.

---

## Toggle System

Toggles live in `mint.data.toggles` and are flipped by custom events registered in `Core.lua`:

```lua
Events:RegisterEvent("toggle", function()
    toggles.engine = not toggles.engine
end)

Events:RegisterEvent("cooldowns", function()
    toggles.cooldowns = not toggles.cooldowns
end)
```

### Toggle Table

| Toggle Key | Default | Controls |
|------------|---------|----------|
| `engine` | `false` | Master enable — tick loop early-exits when false |
| `cooldowns` | `false` | Rotation checks this before using major CDs |
| `kicks` | `false` | Rotation checks this before interrupting |
| `defensives` | `false` | Rotation checks this before using defensives |
| `dispels` | `false` | Rotation checks this before dispelling |
| `purges` | `false` | Rotation checks this before purging |

### How rotations consume toggles

Rotations read toggles directly:

```lua
if not mint.data.toggles.kicks then return false end
if not mint.data.toggles.cooldowns then return false end
```

The Quick Bar UI fires `Events:TriggerEvent("toggle")` when the user clicks. The engine toggle (`toggles.engine`) gates the main tick loop — nothing else runs when it's off.

---

## Cache System

> `Engine/Classes/Cache.lua`

A time-based key/value store. Every entry has a TTL (duration in seconds). Expired entries are cleaned up lazily on access.

### API

```lua
local cache = Cache.New()

cache:Set("key", value, 0.5)    -- store for 500ms
local val = cache:Get("key")    -- returns value or nil if expired
local ok  = cache:IsCached("key")  -- boolean check without clearing
```

### Internal structure

```lua
cache = {
    ["key"] = { value = <any>, duration = <number>, time = <GetTime()> }
}
```

### Usage patterns across the codebase

| User | Key Pattern | Duration | Purpose |
|------|-------------|----------|---------|
| `UnitManager.__index` | smart unit token | 0.2s | Avoid rebuilding SmartObjects |
| `UnitManager:GetNumEnemiesWithDebuff` | `"num_enemies_"..name` | 0.5s | Expensive combat iteration |
| `UnitManager:GetInterruptibleUnits` | `"interruptible_enemies"` | 1.0s | Interruptible count |
| `Unit:HasLos` | `"can_see_"..guid` | 0.4s | TraceLine is expensive |
| `Unit:GetEnemies` | `"enemies_"..radius` | 0.25s | AoE counting |
| `Unit:GetMeleeCount` | `"enemies_melee"` | 0.25s | Melee counting |
| `Unit:TimeToMaxPower` | `"ttmp_"..powerType` | 0.2s | Regen calc |
| `TimeToDie` | Pool of `{time, hp}` tables | — | Object pooling for sample data |

---

## Timer System

> `Engine/Classes/Timer.lua`

A simple stopwatch — not a scheduling timer.

### API

```lua
local timer = Timer:New(duration?)  -- optional duration field
timer:Start()                       -- sets startTime = GetTime()
timer:GetTime()                     -- seconds since start (0 if not running)
timer:IsRunning()                   -- startTime ~= nil
timer:Reset()                       -- clears startTime
timer:GetRemainingTime()            -- endTime - GetTime()
timer:GetTimeSinceEnded()           -- GetTime() - endTime
```

### Usage in Core.lua

| Timer | Purpose |
|-------|---------|
| `mint.data.MoveTimer` | Tracks how long the player has been moving. Started on `PLAYER_STARTED_MOVING`, reset on stop. |
| `mint.data.StopTimer` | Tracks how long the player has been stationary. Started on `PLAYER_STOPPED_MOVING`, reset on move. |

---

## EventManager

> `Engine/Classes/EventManager.lua`

Dual-purpose event bus supporting both custom MINT events and native WoW frame events.

### Custom Events

```lua
-- Register
mint.events:RegisterEvent("toggle", function() ... end)

-- Fire
mint.events:TriggerEvent("toggle")
mint.events:TriggerEvent("BuildOptions")
```

Custom events are stored in `events[name] = { handler1, handler2, ... }` and fired synchronously.

### WoW Events

```lua
-- Register
mint.events:RegisterWoWEvent("COMBAT_LOG_EVENT_UNFILTERED", function(...)
    ...
end)
```

WoW events are registered on an internal `CreateFrame("Frame")` and dispatched via its `OnEvent` script. Multiple handlers per event are supported.

### Key events used in the framework

| Event Type | Event Name | Registered In |
|------------|------------|---------------|
| Custom | `"toggle"` | Core.lua |
| Custom | `"cooldowns"`, `"kicks"`, `"dispels"`, `"purges"`, `"defensives"` | Core.lua |
| Custom | `"BuildOptions"` | Core.lua |
| Custom | `"BuildQuickbar"` | Core.lua |
| Custom | `"optionsToggle"`, `"quickbarToggle"`, `"consoleToggle"` | Core.lua |
| WoW | `COMBAT_LOG_EVENT_UNFILTERED` | Core.lua |
| WoW | `UNIT_SPELLCAST_SUCCEEDED` | Core.lua |
| WoW | `UNIT_SPELLCAST_DELAYED` | Core.lua |
| WoW | `PLAYER_STARTED_MOVING`, `PLAYER_STOPPED_MOVING` | Core.lua |
| WoW | `PLAYER_REGEN_DISABLED`, `PLAYER_REGEN_ENABLED` | Core.lua |
| WoW | `GROUP_ROSTER_UPDATE`, `PLAYER_ENTERING_WORLD` | FriendManager |
| WoW | `PLAYER_TOTEM_UPDATE` | TotemManager |
| WoW | `UNIT_SPELLCAST_EMPOWER_START/STOP` | EmpowerManager |

---

## State Flow Through a Tick

Here's what happens on each 50ms tick when the engine is enabled:

```
Frame OnUpdate fires (every WoW frame, ~16ms)
  │
  ├─ Accumulate elapsed into MintTicker
  │
  ├─ if toggles.engine == false → return (no-op)
  │
  ├─ if MintTicker < 0.05 → return (rate limit to ~20 tps)
  │
  ├─ MintTicker = 0
  │
  ├─ FriendManager:Update()
  │   ├─ Each unit calls Unit:Update() → refresh health, status, power
  │   └─ Sort by realized_hp ascending (lowest-HP first)
  │
  ├─ ObjectManager:Update()
  │   ├─ Clear all lists (units, enemies, combat, summons)
  │   ├─ mint.Objects(5) → iterate NPC objects
  │   ├─ mint.Objects(6) → iterate player objects
  │   ├─ mint.Objects(7) → iterate local player
  │   ├─ For each: get or create Unit, call Update()
  │   └─ Categorize into enemies, combat (CombatConfidence>80), summons
  │
  ├─ TimeToDie:Refresh()
  │   ├─ Throttled to 0.5s intervals
  │   ├─ Sample HP% for each enemy with < 100% HP
  │   ├─ Trim old samples beyond HistoryTime (10.4s)
  │   └─ Purge data for vanished units
  │
  ├─ if GetTime() < pauseTimer → return (manual input pause)
  │
  └─ For each Actor in mint.data.actors:
      ├─ actor:ShouldRun() → check class/spec/condition
      └─ actor:Tick()
          └─ For each synced callback:
              ├─ Check individual rate limit
              └─ pcall(callback) → runs rotation logic
                  ├─ Reads toggles (cooldowns, kicks, etc.)
                  ├─ Queries managers (ObjectManager, FriendManager)
                  ├─ Checks Spell:PreCheck() → GCD gating, usability
                  ├─ Calls Spell:Castable(unit) → range, LoS, facing
                  └─ Calls Spell:Cast(unit) → winkr_NativeCast or CastSpellByName
```
