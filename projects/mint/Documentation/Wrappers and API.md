# Wrappers & API Bridge Layer

> How MINT bridges the Winkr unlocker's C-exported functions into a clean, safe Lua API.

**Source:** `Engine/Wrappers.lua` — the primary bridge between raw `winkr_*` globals and MINT's internal API.

---

## Architecture Overview

```
┌─────────────────┐     ┌──────────────────┐     ┌─────────────────┐
│  Winkr C Bridge  │────▶│  Engine/Wrappers  │────▶│  MINT Classes   │
│  winkr_* globals │     │  mint.* wrappers  │     │  Unit, Spell…   │
└─────────────────┘     └──────────────────┘     └─────────────────┘
```

All raw `winkr_*` functions are C-exported globals available in any Lua context. `Wrappers.lua` wraps them into `mint.*` methods that add:

- **GUID resolution** — unit tokens (`"target"`, `"player"`) are converted to GUIDs via `UnitGUID()` before passing to the C bridge.
- **Nil safety** — every wrapper checks for nil/invalid inputs and returns safe defaults.
- **Type coercion** — numeric types and string returns are normalized.
- **Path normalization** — file I/O wrappers convert `/` to `\` and prepend `unlocker.baseDir`.

---

## Token Resolution: `winkrGUID()`

All wrappers use this internal helper before calling any `winkr_*` function:

```lua
local function winkrGUID(input)
    if type(input) == "string" and not string.find(input, "-") then
        return UnitGUID(input)  -- token → GUID
    end
    return input  -- already a GUID
end
```

**Rule:** If the string contains a `-`, it's treated as a GUID. Otherwise it's a unit token that must be resolved.

---

## Winkr API Functions — Complete Reference

### Object Manager

| Function | Signature | Returns | Notes |
|----------|-----------|---------|-------|
| `winkr_GetObjectCount()` | `() → number` | Total objects in OM | Zero-indexed iteration: `0` to `count - 1` |
| `winkr_GetObjectWithIndex(i)` | `(number) → string` | GUID at index `i` | Index is **0-based** |
| `winkr_ObjectType(guid)` | `(string) → number` | Object type ID (0–13) | Returns **number**, not string. See `mint.ObjectTypes` enum |
| `winkr_ObjectPosition(guid)` | `(string) → number, number, number` | `x, y, z` world coordinates | |
| `winkr_ObjectFacing(guid)` | `(string) → number` | Facing angle in radians | Used by `mint.ObjectRotation()` |
| `winkr_ObjectRotation(guid)` | `(string) → number` | Model rotation | Distinct from facing |
| `winkr_ObjectID(guid)` | `(string) → number` | NPC/template ID | |
| `winkr_ObjectName(guid)` | `(string) → string` | Object name | |
| `winkr_ObjectCreator(guid)` | `(string) → string` | Creator's GUID | For totems, pets, etc. |
| `winkr_ObjectTarget(guid)` | `(string) → string` | Target's GUID | |
| `winkr_ObjectHeight(guid)` | `(string) → number` | Display height | Used for LoS eye-level calculations |
| `winkr_ObjectCombatReach(guid)` | `(string) → number` | Combat reach distance | |
| `winkr_ObjectBoundingRadius(guid)` | `(string) → number` | Bounding radius | |
| `winkr_ObjectMovementFlag(guid)` | `(string) → number` | Movement bitflags | |
| `winkr_ObjectCreatureType(guid)` | `(string) → number` | Creature type ID | |
| `winkr_ObjectSpecializationID(guid)` | `(string) → number` | Player spec index | |
| `winkr_ObjectLootable(guid)` | `(string) → boolean` | Is lootable | |
| `winkr_ObjectATInfo(guid)` | `(string) → table` | AreaTrigger info | |
| `winkr_IsValidObject(guid)` | `(string) → boolean` | Exists in OM | |
| `winkr_IsPlayerGuid(guid)` | `(string) → boolean` | Is player's GUID | |
| `winkr_IsTargetGuid(guid)` | `(string) → boolean` | Is current target | |
| `winkr_IsFocusGuid(guid)` | `(string) → boolean` | Is current focus | |
| `winkr_GetMapID()` | `() → number` | Current map ID | |
| `winkr_SetNPC(guid)` | `(string) → nil` | Sets "npc" token slot | |
| `winkr_ObjectInteract(guid)` | `(string) → nil` | Interact with object | |

#### ObjectTypes Enum

```lua
mint.ObjectTypes = {
    Object = 0, Item = 1, Container = 2,
    AzeriteEmpoweredItem = 3, AzeriteItem = 4,
    Unit = 5, Player = 6, ActivePlayer = 7,
    GameObject = 8, DynamicObject = 9, Corpse = 10,
    AreaTrigger = 11, SceneObject = 12, Conversation = 13,
}
```

> **Quirk:** The C bridge converts ActivePlayer (type 7) to Player (type 6) in `winkr_ObjectType()`. `mint.Objects()` handles this by matching ActivePlayer via `playerGuid == guid` comparison instead.

### Aura Memory Reads

| Function | Signature | Returns | Notes |
|----------|-----------|---------|-------|
| `winkr_UnitAuras(guid [, filter])` | `(string [, string]) → table` | Array of aura data tables | Filter: `"HELPFUL"`, `"HARMFUL"`, or `nil` for all |

Each aura entry in the returned table contains:

| Field | Type | Description |
|-------|------|-------------|
| `spellId` | number | The spell ID of the aura |
| `name` | string | Spell name (may be empty — fixup resolves via `C_Spell.GetSpellName`) |
| `auraInstanceID` | number | Unique instance ID |
| `isFromPlayerOrPlayerPet` | boolean | Whether player/pet is the source |
| `_remainingSec` | number | Seconds remaining (converted to `expirationTime` by fixup) |

> **Quirk:** Raw aura data has `_remainingSec` (relative) instead of `expirationTime` (absolute). The bridge fixup converts: `expirationTime = GetTime() + _remainingSec`.

### Casting

| Function | Signature | Returns | Notes |
|----------|-----------|---------|-------|
| `winkr_NativeCast(spellID [, guid])` | `(number [, string]) → nil` | Casts spell by ID | Bypasses standard taint. Always use **base spell IDs** |
| `winkr_ObjectCastingTarget(guid)` | `(string) → string` | GUID of cast target | |
| `winkr_SpellIsTargeting()` | `() → boolean` | True if a spell is awaiting target selection | |
| `winkr_SpellCancelTargeting()` | `() → nil` | Cancels pending target | |
| `winkr_SpellTargetingReady()` | `() → boolean` | True if targeting reticle is ready | |

### World / Camera

| Function | Signature | Returns | Notes |
|----------|-----------|---------|-------|
| `winkr_TraceLine(x1,y1,z1, x2,y2,z2 [,flags])` | `(6×number [,number]) → hit, hx, hy, hz` | Raycast collision test | Default flags: `0x11` (terrain + WMO). `hit ≠ 0` means collision |
| `winkr_WorldToScreen(x,y,z)` | `(3×number) → sx, sy, visible` | 3D → screen projection | `visible` is false if behind camera. Coords are normalized 0–1 |
| `winkr_ScreenToWorld(sx,sy)` | `(2×number) → x, y, z` | Screen → world ray | |
| `winkr_CameraPosition()` | `() → x, y, z` | Camera eye position | Returns `0, 0, 0` on failure |
| `winkr_CameraDiag()` | `() → string` | Diagnostic camera dump | Debug only |
| `winkr_FaceDirection(angle)` | `(number) → nil` | Set player facing (radians) | See taint note below |
| `winkr_ClickPosition(x,y,z)` | `(3×number) → nil` | Simulate left-click at world coords | For ground-targeted spells |

### System

| Function | Signature | Returns | Notes |
|----------|-----------|---------|-------|
| `winkr_GetKeyState(vk)` | `(number) → boolean` | Win32 virtual key pressed | e.g., `0x31` = '1' key |
| `winkr_IsWindowForeground()` | `() → boolean` | WoW window has focus | |
| `winkr_Call(fn, ...)` | `(function, ...) → any` | Call function in **clean taint context** | Critical for protected API calls |

### File I/O

| Function | Signature | Returns | Notes |
|----------|-----------|---------|-------|
| `winkr_ReadFile(path)` | `(string) → string\|nil` | File contents or nil | Absolute path required |
| `winkr_WriteFile(path, data, append)` | `(string, string, boolean) → nil` | Writes/appends data | Auto-creates parent directories |
| `winkr_ListFiles(dir)` | `(string) → table\|nil` | Array of filenames | Returns nil if dir doesn't exist |
| `winkr_ListDirectories(dir)` | `(string) → table\|nil` | Array of subdirectory names | |

### Missiles & Combat Log

| Function | Signature | Returns | Notes |
|----------|-----------|---------|-------|
| `winkr_Missiles()` | `() → table` | Active missile projectiles | |
| `winkr_CombatLogGetCurrentEventInfo()` | `() → table` | Current CLEU event data | |

---

## Wrappers.lua — Wrapper Functions

Every `mint.*` wrapper follows the same pattern:
1. Resolve token → GUID via `winkrGUID()`
2. Guard against nil
3. Call raw `winkr_*`
4. Return safe defaults on failure

### Object Manager Wrappers

| Wrapper | Raw Call | Added Value |
|---------|----------|-------------|
| `mint.Object(guid)` | identity | Returns the GUID directly (no-op, API consistency) |
| `mint.Objects(filter)` | `winkr_GetObjectCount`, `winkr_GetObjectWithIndex`, `winkr_ObjectType` | Iterates full OM, applies string→number filter conversion, handles ActivePlayer/Player type ambiguity |
| `mint.ObjectExists(guid)` | `winkr_IsValidObject` | Token resolution + nil guard |
| `mint.ObjectID(guid)` | `winkr_ObjectID` | Returns `0` on failure |
| `mint.ObjectGUID(pointer)` | `UnitGUID` | Returns `false` for `"none"` or nil; resolves tokens |
| `mint.ObjectCreator(object)` | `winkr_ObjectCreator` | Nil-safe |
| `mint.ObjectTarget(object)` | `winkr_ObjectTarget` | Nil-safe |
| `mint.ObjectPosition(guid)` | `winkr_ObjectPosition` | Returns `nil, nil, nil` on failure |
| `mint.ObjectHeight(object)` | `winkr_ObjectHeight` | Nil-safe |
| `mint.ObjectAttachmentPosition(pointer, flag)` | `winkr_ObjectPosition` + `winkr_ObjectHeight` | Computes eye-level Z: `z + (height * 0.7)`. Used for LoS checks |
| `mint.ObjectLootable(guid)` | `winkr_ObjectLootable` | Returns `false` on failure |
| `mint.ObjectName(guid)` | `winkr_ObjectName` | Nil-safe |
| `mint.ObjectRotation(guid)` | `winkr_ObjectFacing` | Token resolution |
| `mint.ObjectCombatReach(guid)` | `winkr_ObjectCombatReach` | Nil-safe |
| `mint.ObjectPointer(object)` | none | Returns `object.unit` (the Unit class token) |

### Facing / Movement Wrappers

| Wrapper | Notes |
|---------|-------|
| `mint.FaceDirection(angle, force)` | **Critical:** Checks `IsMouselooking()` before calling `winkr_FaceDirection()`. If the player is right-click turning and `force` is not true, returns `false` to prevent camera snapping |

### Casting Wrappers

| Wrapper | Notes |
|---------|-------|
| `mint.UnitCastTarget(guid)` | Wraps `winkr_ObjectCastingTarget`, returns empty string `""` on nil |
| `mint.IsSpellPending()` | Returns `64` if `winkr_SpellIsTargeting()` is true, else `0` |
| `mint.Click(x, y, z)` | Direct passthrough to `winkr_ClickPosition` |

### Distance Calculations (Pure Lua)

```lua
mint.Distance3D(x1, y1, z1, x2, y2, z2)  -- 3D Euclidean
mint.Distance2D(x1, y1, x2, y2)           -- 2D (horizontal plane)
```

> **Design decision:** Distance is computed in pure Lua, not via the unlocker. The comment in source reads: *"WE SHOULD USE LUA DISTANCE NOT UNLOCKER"*.

### TraceLine (Raycast)

```lua
mint.TraceLine(x1, y1, z1, x2, y2, z2, flags)
```

- Default flags: `0x11` (terrain + WMO collision)
- Returns `hx, hy, hz` if hit detected; `0, 0, 0` if clear line of sight
- The raw `winkr_TraceLine` returns `hit, hx, hy, hz` — the wrapper translates `hit ~= 0` into the collision point

### File System Wrappers

| Wrapper | Notes |
|---------|-------|
| `mint.DirectoryExists(dir)` | Tries `winkr_ListFiles` then `winkr_ListDirectories` on the full path |
| `mint.FileExists(path)` | Checks if `winkr_ReadFile` returns non-nil. **Note:** Takes raw paths (does NOT prepend baseDir, unlike `mint.ReadFile`) |
| `mint.CreateDirectory(dir)` | Writes a `.mint_init` sentinel file; `winkr_WriteFile` auto-creates parent dirs |
| `mint.ListFiles(dir)` | Passthrough with empty-table fallback |
| `mint.ReadFile(path)` | Prepends `unlocker.baseDir`, normalizes path separators |
| `mint.WriteFile(filePath, data, append)` | Detects absolute paths (e.g., `C:\...`) and skips baseDir prepend |
| `mint.DeleteFile(path)` | **Not implemented** — always returns `false` |

---

## Winkr Aura Hook System

The most complex piece of `Wrappers.lua`. This system **transparently hooks** WoW's `C_UnitAuras` API so that GUID-based aura queries route through the Winkr memory bridge.

### Why It Exists

Standard `C_UnitAuras` functions only accept unit tokens (`"target"`, `"player"`), not raw GUIDs. When MINT needs auras for an arbitrary GUID from the Object Manager, it has no matching token. The hook system intercepts calls and redirects GUID-based queries to `winkr_UnitAuras()`.

### Hooked Functions

| Original API | Hook Behavior |
|--------------|---------------|
| `C_UnitAuras.GetAuraDataByIndex(unit, index, filter)` | If `unit` is a GUID → fetches from bridge cache, supports `\|PLAYER` filtering |
| `C_UnitAuras.GetAuraDataBySpellName(unit, name, filter)` | If `unit` is a GUID → searches bridge auras by name |
| `C_UnitAuras.GetAuraDataByAuraInstanceID(unit, id)` | If `unit` is a GUID → searches bridge auras by instanceID |

For non-GUID inputs (standard tokens), the original functions are called unchanged.

### GUID Detection

```lua
local function IsGUID(str)
    return type(str) == "string" and str:find("-", 1, true) ~= nil
end
```

### Aura Data Fixup

Raw bridge auras undergo fixup before being returned:

1. **Name resolution:** Empty `name` → resolved via `C_Spell.GetSpellName(spellId)`, cached in `spellNameCache`
2. **Time conversion:** `_remainingSec` → `expirationTime = GetTime() + _remainingSec`

### Cache Strategy

- **Bridge aura cache** (`bridgeAuraCache`): keyed by `guid|HELPFUL`, `guid|HARMFUL`, `guid|ALL`
- **Spell name cache** (`spellNameCache`): keyed by spellId
- Bridge cache is **wiped every frame** via `C_Timer.NewTicker(0, ...)`
- Manual wipe available: `mint._wipeBridgeAuraCache()`

### The Dual-Read Aura Pattern

MINT uses two complementary systems for aura queries:

| Source | Use Case | API |
|--------|----------|-----|
| **Standard WoW API** | Token-based units (`"player"`, `"target"`) | `C_UnitAuras.GetAuraDataByIndex()` etc. |
| **Winkr Bridge** | GUID-based units from Object Manager | Same API, transparently hooked |

The hook makes this transparent — callers don't need to know whether they're querying via token or GUID. Both paths return the same `AuraData` structure.

For detecting hidden/memory-only buffs that WoW's API doesn't expose, `winkr_UnitAuras()` reads directly from memory, providing access to auras not normally visible through the standard API.

---

## WoW API Integration

### Key Standard APIs Used by MINT

| API | Usage in MINT | Protected? |
|-----|---------------|------------|
| `UnitGUID(token)` | Token → GUID resolution | No |
| `C_UnitAuras.*` | Aura queries (hooked for GUID support) | No |
| `C_Spell.GetSpellName(id)` | Spell name lookup for aura fixup | No |
| `C_Spell.GetSpellInfo(id)` | Spell metadata | No |
| `C_SpellBook.GetSpellBookSkillLineInfo()` | Spell enumeration for keybind UI | No |
| `GetTime()` | Time reference for aura expiration | No |
| `IsMouselooking()` | Guard against FaceDirection during mouse-turn | No |
| `UnitIsUnit(a, b)` | Unit identity comparison | No |
| `CastSpellByID()` | Standard spell casting | **Yes — Protected** |
| `TargetUnit()` | Targeting | **Yes — Protected** |
| `SpellTargetUnit()` | Spell targeting | **Yes — Protected** |

### Protected Execution via `winkr_Call()`

Protected WoW APIs cannot be called from addon code directly due to Blizzard's taint system. `winkr_Call(fn, ...)` calls a Lua function with its arguments in a clean (untainted) execution context, bypassing the taint check.

```lua
-- Example: releasing an empowered spell via protected UseAction
winkr_Call(UseAction, slot, false, false)

-- MINT's NativeCast wraps this internally
winkr_NativeCast(spellID, targetGUID)
```

### Taint Considerations

| Category | Examples | Approach |
|----------|----------|----------|
| **Unprotected** | Position reads, aura queries, distance checks | Direct Lua calls — no wrapping needed |
| **Protected** | `CastSpellByID`, `TargetUnit`, `UseAction` | Must go through `winkr_NativeCast()` or `winkr_Call()` |
| **Semi-protected** | `FaceDirection` | Winkr provides `winkr_FaceDirection()` which handles the protected call internally |

> **Important:** Always cast using **base spell IDs**, not override IDs. The game server resolves transformations (e.g., Azure Strike → Azure Sweep) automatically. Sending override IDs often fails because they aren't in the spellbook.

---

## Enums

### AttachFlags

Used by `mint.ObjectAttachmentPosition()` for bone attachment points:

```lua
mint.AttachFlags = {
    right_hand = 1, left_hand = 2,
    right_elbow = 3, left_elbow = 4,
    right_shoulder = 5, left_shoulder = 6,
    right_knee = 7, left_knee = 8,
    right_hip = 9, left_hip = 10,
    neck = 11, back = 12, center = 13,
    chest = 15, chin = 17,
    above = 18, below = 19, hat = 20,
    groin = 25, back_slot = 28, center_low = 34,
}
```

---

## Quick Reference: Wrapper Call Chain

```
Rotation Code
  └─▶ unit:IsWithin(range)
       └─▶ mint.Distance3D(...)
            └─▶ mint.ObjectPosition(guid)
                 └─▶ winkrGUID(guid)  -- token resolution
                 └─▶ winkr_ObjectPosition(resolvedGUID)

  └─▶ unit:FindBuffByID(spellID)
       └─▶ C_UnitAuras.GetAuraDataByIndex(guid, ...)
            └─▶ [HOOK] IsGUID? → GetBridgeAuras() → winkr_UnitAuras()
            └─▶ [FALLBACK] origGetByIndex(token, ...)
```
