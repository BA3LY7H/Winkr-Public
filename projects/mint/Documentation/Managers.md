# Managers

> ObjectManager, UnitManager, FriendManager, TotemManager, and SmartTarget — how MINT discovers, caches, and selects units.

---

## Table of Contents

- [Architecture Overview](#architecture-overview)
- [ObjectManager](#objectmanager)
- [UnitManager](#unitmanager)
- [FriendManager](#friendmanager)
- [TotemManager](#totemmanager)
- [SmartTarget](#smarttarget)
- [Manager Interaction Flow](#manager-interaction-flow)

---

## Architecture Overview

```
winkr_Objects() API
       │
       ▼
 ┌─────────────┐     registers units     ┌─────────────┐
 │ObjectManager │ ───────────────────────▶│ UnitManager  │
 │  .enemies    │                         │  .units{}    │
 │  .combat     │                         │  .smartUnits │
 │  .summons    │                         └──────┬───────┘
 │  .units      │                                │
 └──────────────┘                                │ provides Get("player")
                                                 │ provides GetUnitByGUID()
                                                 ▼
                                          ┌─────────────┐
     GROUP_ROSTER_UPDATE ───────────────▶ │FriendManager │
     PLAYER_ENTERING_WORLD ─────────────▶ │  .units[]    │
                                          └──────┬───────┘
                                                 │ sorted by realized_hp
                                                 ▼
                                          ┌─────────────┐
                                          │ SmartTarget  │
                                          │  :Acquire()  │
                                          └─────────────┘

     PLAYER_TOTEM_UPDATE ──────────────▶ ┌──────────────┐
                                         │ TotemManager  │
                                         │  .totems{}    │
                                         └──────────────┘
```

---

## ObjectManager

> `Engine/Classes/ObjectManager.lua`

Rebuilds every tick. Iterates raw winkr object pointers and categorizes them into typed `List` instances.

### Constructor

```lua
local om = Objects:New()
```

### Lists

| List | Type | Contents |
|------|------|----------|
| `om.units` | `List<Unit>` | All discovered units (NPCs + players + self) |
| `om.enemies` | `List<Unit>` | Units where `unit.can_attack == true` |
| `om.combat` | `List<Unit>` | Enemies with `CombatConfidence() > 80`, `in_combat == true`, or `IsUnit("target")` |
| `om.summons` | `List<Unit>` | Units whose NPC ID is in the summons table (e.g., Lightspawn 224241, Efflorescence 182892) |

### Update Cycle

Called every tick from the main loop (`ObjectManager:Update()`):

```lua
function Objects:Update()
    -- 1. Clear all lists
    self.units:clear()
    self.enemies:clear()
    self.combat:clear()
    self.summons:clear()

    -- 2. Iterate winkr objects by type
    local units   = mint.Objects(5)    -- NPCs
    local players = mint.Objects(6)    -- Other players
    local player  = mint.Objects(7)    -- Local player

    -- 3. For each object GUID:
    --    a. Look up in UnitManager (by GUID)
    --    b. If not found, create Unit:Create(guid, true) and register
    --    c. If found, call unit:Update()
    --    d. Push into appropriate lists

    -- 4. Combat classification:
    --    enemy goes to combat list if:
    --    CombatConfidence() > 80 OR in_combat OR IsUnit("target")
end
```

### Key behaviors

- **All lists are rebuilt from scratch each tick.** No incremental tracking.
- **Object types:** `5` = NPC/creature, `6` = other player, `7` = local player.
- **Summon tracking:** Only specific NPC IDs in the `summons` table are tracked.
- **New units** are created with `isOMUnit = true`, which enables GUID-based operations and winkr `SetNPC` fallback.

---

## UnitManager

> `Engine/Classes/UnitManager.lua`

Central unit registry and SmartObject factory. Stores units by GUID and provides lazy-resolving smart units.

### Constructor

```lua
local um = UnitManager:New()
```

### Storage

| Field | Type | Description |
|-------|------|-------------|
| `units` | `table<string, Unit>` | GUID → Unit map |
| `smartUnits` | `table<string, {unit, cb}>` | Token → SmartObject entries |
| `cache` | `Cache` | SmartUnit refresh cache |

### Key Methods

#### `Get(token) → SmartObject<Unit>`

The primary way to obtain a unit reference. Returns a `SmartObject` that transparently refreshes the underlying Unit when accessed.

```lua
local player = UnitManager:Get("player")
local target = UnitManager:Get("target")
-- These look/act like Unit objects but auto-refresh
```

**Implementation:**
1. Resolve token → GUID via `mint.ObjectGUID(token)`
2. If GUID not in `self.units`, create the Unit
3. Wrap in `SmartObject:New(unit, refreshCallback)` — no cache time, refreshes every access
4. The SmartObject's `__index` calls the callback on every property access, which re-resolves the GUID (handles target swaps)

#### `CreateSmartUnit(token, cb, cacheTime?) → SmartObject<Unit>`

Create a named smart unit with a custom callback and optional cache time (default 0.2s).

```lua
UnitManager:CreateSmartUnit("SmartTarget", function(max_range)
    -- find best target logic
    return best_unit
end)
```

Cached smart units only re-evaluate when their cache expires.

#### `GetUnitByGUID(guid) → Unit|nil`

Direct GUID lookup in the units table. Used by ObjectManager during its update loop.

#### `SetUnit(unit)`

Register a unit by GUID. Called by ObjectManager when creating new units.

### `__index` metamethod

Accessing `UnitManager.some_token` triggers:
1. Check `smartUnits[token]` → refresh + return cached unit
2. Check `units[ObjectGUID(token)]` → return if found
3. Create from `mint.Object(token)` → register + return
4. Fallback → `units['none']`

### Aggregate queries

| Method | Returns | Description |
|--------|---------|-------------|
| `GetNumEnemiesWithDebuff(aura, playerOnly?)` | number | Count combat enemies with a specific debuff (cached 0.5s) |
| `GetInterruptibleUnits()` | number | Count interruptible enemies (cached 1.0s) |

---

## FriendManager

> `Engine/Classes/FriendManager.lua`

Tracks party/raid members. Keeps units sorted by realized HP (lowest first) for efficient healing target selection.

### Constructor

```lua
local fm = FriendManager:New()
```

Registers `PLAYER_ENTERING_WORLD` and `GROUP_ROSTER_UPDATE` to auto-reset.

### Population

On reset (group change, zone in):
1. Determine `"party"` vs `"raid"` group type
2. For party: add `"player"` first
3. Iterate group members: `Unit:Create("party1")`, `Unit:Create("raid5")`, etc.
4. Skip duplicates (player in raid)

### Update Cycle

Called every tick from the main loop (`FriendManager:Update()`):

```lua
function FriendManager:Update()
    -- 1. Update each unit
    for i = 1, #self.units do
        self.units[i]:Update()
    end

    -- 2. Sort by realized_hp ascending (lowest first)
    --    Tie-break: in_range units first, then lower max_health
    tsort(self.units, function(a, b)
        local a_range = a.in_range and 1 or 0
        local b_range = b.in_range and 1 or 0
        if a_range == b_range then
            if a.realized_hp == b.realized_hp then
                return a.max_health < b.max_health
            end
            return a.realized_hp < b.realized_hp
        end
        return a_range > b_range
    end)
end
```

**Sort priority:** In-range units first → lowest realized HP first → lower max health breaks ties.

### Key Methods

#### Lowest-HP Queries

| Method | Signature | Returns | Description |
|--------|-----------|---------|-------------|
| `GetLowest(hp?, callback?)` | `(number?, fn?) → Unit` | First in-range, alive, assistable unit below HP% | Most-used healing target selector |
| `GetCountBelow(hp, filter?)` | `(number, fn?) → number` | Count of units below HP% | AoE heal threshold |
| `GetPctBelow(hp, filter?)` | `(number, fn?) → number` | Percentage of group below HP% | Group damage assessment |

#### Buff/Debuff Queries

| Method | Returns | Description |
|--------|---------|-------------|
| `GetPctFriendsWithBuff(aura)` | number | % of living in-range friends with buff |
| `GetNumFriendsWithBuff(aura)` | number | Count with buff |
| `GetNumFriendsWithoutBuff(aura)` | number | Count without buff |

#### Dispel

```lua
local unit, spell = FriendManager:GetBestDispel(spells)
```

Iterates sorted friends (lowest HP first). For each alive, in-range, assistable unit: checks each spell for `IsKnown()`, `IsInRange()`, then `unit:HasDispellableAura(spell)`. Returns the first match. Stops early if a dead unit is encountered.

#### Role Queries

| Method | Returns | Description |
|--------|---------|-------------|
| `GetTanks()` | Unit[] | All units with TANK role |
| `GetFirstTank()` | Unit | First alive, in-range tank |
| `GetCount()` | number | Total tracked friends |

#### Iteration

| Method | Description |
|--------|-------------|
| `Loop(callback)` | Iterate in-range, assistable friends; break on `true` |
| `LoopRaw(callback)` | Iterate ALL friends (no range/assist filter) |

#### Roster Management

| Method | Description |
|--------|-------------|
| `Add(unit)` | Add a unit token (deduplicates by GUID) |
| `Remove(unit)` | Remove by GUID |
| `Reset()` | Clear and re-populate |
| `GetFriendByGUID(guid)` | Find by GUID |

---

## TotemManager

> `Engine/Classes/TotemManager.lua`

Tracks active totems and summon-style pets (Shaman totems, Monk celestials, Druid guardians) via `PLAYER_TOTEM_UPDATE`. Maps icon IDs to `Spell` instances so rotation code can query totem state by spell ID.

### Constructor

```lua
local tm = TotemManager:New()
```

Registers `PLAYER_TOTEM_UPDATE` on its own internal `EventManager` frame. When a totem slot updates, calls `GetTotemInfo(slotIndex)` and stores/clears the slot.

### Totem Slot Data

Each active totem is stored as:

```lua
{
    spell_id   = number,  -- resolved from icon → Spell mapping
    icon       = number,  -- WoW icon texture ID
    start_time = number,  -- GetTime() when placed
    duration   = number,  -- total duration in seconds
}
```

### Key Methods

| Method | Signature | Returns | Description |
|--------|-----------|---------|-------------|
| `IsActive(spell_id)` | `(number) → boolean` | `true` if the totem is placed and not expired | Checks `start_time + duration > GetTime()` |
| `ActiveCount(spell_id)` | `(number) → number` | Count of active totems matching this spell ID | Useful for multi-charge totems (e.g. Grove Guardians) |
| `TimeRemaining(spell_id)` | `(number) → number` | Seconds until expiry (0 if not found) | `start_time + duration - GetTime()` |
| `GetTotemInfo(slotIndex)` | `(number) → table\|nil` | Parsed totem data or nil | Reads WoW `GetTotemInfo()`, matches icon to `totem_spells` map |

### Tracked Totem Spells

The `totem_spells` table maps WoW icon texture IDs to `Spell` instances:

- **Shaman:** Capacitor, Earthbind, Earthen Wall, Healing Stream, Healing Tide, Liquid Magma, Mana Tide, Poison Cleansing, Spirit Link, Stone Bulwark, Surging, Tremor, Wind Rush
- **Monk:** Yu'lon, Chi-Ji, Jade Serpent Statue, Xuen
- **Druid:** Grove Guardians

---

## SmartTarget

> `Engine/Classes/Utility/Targets.lua`

Automatic target acquisition system. Snaps the player's target to the best available enemy when the current target is invalid.

### Constructor

```lua
local st = SmartTarget:New()
```

### Acquire Logic

```lua
function SmartTarget:Acquire(range)
```

1. **Setting check:** Skips if `Settings.profile.general.smart_target == false`
2. **Safety guards:** Skips if player is casting or channeling
3. **Target validation:** Is current target alive, existing, and attackable?
4. **If invalid:** Queries `SmartTargetUnit:Get(range)` for the best enemy
5. **If found:** Targets via `winkr_SetNPC(guid)` + `TargetUnit("npc")`

### Selection Criteria

The `SmartTargetUnit` is a `CreateSmartUnit` with this logic:

```
For each enemy in ObjectManager.combat:
  ├─ Skip if dead or non-existent
  ├─ Skip if distance > range (default 40yd)
  ├─ Skip if no LoS to player
  └─ Pick enemy with highest absolute health
```

Priority is simple: **highest raw health wins.** This biases toward bosses and high-priority targets. The system does not yet consult a priority list, though the code has a comment placeholder for it.

---

## Manager Interaction Flow

### Per-Tick Data Flow

```
1. FriendManager:Update()
   └─ Refreshes party/raid units, sorts by HP

2. ObjectManager:Update()
   ├─ Iterates winkr objects
   ├─ Creates/updates Units in UnitManager
   └─ Builds enemies/combat/summons lists

3. TimeToDie:Refresh()
   └─ Samples HP from ObjectManager.enemies

4. Actor:Tick() → rotation callbacks
   ├─ Read ObjectManager.combat for AoE counts
   ├─ Read FriendManager for healing targets
   ├─ Read UnitManager:Get("target") for primary target
   └─ Optionally call SmartTarget:Acquire()
```

### Unit Lifecycle

```
winkr object GUID appears
        │
        ▼
ObjectManager:Update() sees new GUID
        │
        ├─ UnitManager:GetUnitByGUID(guid) → nil (not found)
        │
        ├─ Unit:Create(guid, true) → new OM unit
        │   ├─ Sets isOMUnit = true
        │   ├─ Resolves name, class, health via winkr_SetNPC hack
        │   └─ Caches initial state
        │
        ├─ UnitManager:SetUnit(unit) → stored by GUID
        │
        └─ Pushed into ObjectManager lists
        
Next tick:
        │
        ├─ UnitManager:GetUnitByGUID(guid) → found
        ├─ unit:Update() → refresh all fields
        └─ Re-categorized into lists
        
GUID disappears from winkr:
        │
        └─ ObjectManager doesn't push it → lists are rebuilt clean
           (UnitManager still holds the Unit by GUID until GC)
```

### SmartObject Resolution

When rotation code accesses `player:GetHP()`:

```
player is a SmartObject wrapping a Unit
        │
        ▼
SmartObject.__index("GetHP")
        │
        ├─ If cacheTime: check Cache → return if fresh
        │
        ├─ Else: call callback()
        │   └─ UnitManager resolves token → GUID → Unit
        │       └─ If GUID changed (target swap), returns new Unit
        │
        ├─ self.value = returned Unit
        │
        └─ return self.value.GetHP → Unit method
```

This is what makes `UnitManager:Get("target")` always return the current target even if the player switches targets — the SmartObject re-resolves the GUID on each access.
