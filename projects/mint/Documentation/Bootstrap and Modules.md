# Bootstrap & Module System

This document covers MINT's startup sequence — from the WoW addon manifest to a fully loaded rotation framework.

---

## Boot Sequence Overview

```
retail.toc                        WoW addon manifest — declares files to load
    │
    ├── LibDraw.lua               3D drawing library (loaded by WoW)
    ├── json.lua                  JSON encoder/decoder (loaded by WoW)
    └── loader.lua                Framework entry — but NOT executed by WoW directly
         │
init.lua                          Winkr mod entry point (executed by Winkr DLL)
    │
    ├── Sets WINKR_MODS_DIR = "C:\\mods\\mint"
    ├── Reads loader.lua via winkr_ReadFile()
    ├── Compiles with loadstring()
    └── Executes: fn("retail", {}, nil)
         │
loader.lua                        Receives (name, mint, unlocker) as varargs
    │
    ├── Detects Winkr unlocker (via winkr_ReadFile global)
    ├── Initializes mint.data (toggles, actors, debug state)
    ├── Sets mint metatable (gcd, latency, class, specName)
    ├── Creates mint.console (debug UI frame)
    ├── Defines mint:Require() and mint:ProcessModule()
    ├── Reads + parses load-order.json
    └── Calls Load(parsed, "main")
         │
         └── Iterates load-order.json "order" array
             └── For each module: mint:ProcessModule(module)
```

---

## init.lua — The Entry Point

`init.lua` is the file Winkr's mod loader discovers and executes. It does exactly three things:

1. **Sets the base path**: `WINKR_MODS_DIR = "C:\\mods\\mint"`
2. **Reads `loader.lua`** from disk using `winkr_ReadFile()`
3. **Compiles and executes** it via `loadstring()`, passing `("retail", {}, nil)` as arguments

```lua
WINKR_MODS_DIR = "C:\\mods\\mint"
local content = winkr_ReadFile(WINKR_MODS_DIR .. "\\loader.lua")
if content then
    local fn, err = loadstring(content, "@loader.lua")
    if fn then
        fn("retail", {}, nil)
    end
end
```

The empty table `{}` becomes the `mint` global that the entire framework builds on.

---

## loader.lua — Framework Initialization

`loader.lua` receives three arguments via `...`:
- `name` — `"retail"` (the addon name)
- `mint` — the empty table from init.lua (becomes the global namespace)
- `unlocker` — `nil` initially; loader detects and constructs the Winkr unlocker object

### Unlocker Detection

If `unlocker` is nil and `winkr_ReadFile` exists as a global function, the loader constructs the unlocker table:

```lua
unlocker = { name = "winkr" }
unlocker.baseDir = WINKR_MODS_DIR or "C:\\mods\\retail-main"
unlocker.GetContents = function(path) return winkr_ReadFile(path) end
unlocker.GetBaseFolder = function() return unlocker.baseDir end
```

### mint.data — Runtime State

The loader initializes `mint.data` with the framework's runtime state:

```lua
mint.data = {
    actors = {},              -- Registered Actor instances
    dungeons = {},            -- Dungeon-specific data
    lastCastTimers = {},      -- spell_id → GetTime() of last cast
    debug_mode = true,        -- Toggle with /mintdebug
    toggles = {
        engine = false,       -- Master ON/OFF
        cooldowns = false,    -- Cooldown abilities
        kicks = false,        -- Auto-interrupt
        defensives = false,   -- Auto-defensives
        dispels = false,      -- Auto-dispel
        purges = false,       -- Auto-purge
    },
    vars = {
        debug_start_time = debugprofilestop(),
        dispel_delay = 0.5,
    },
    active_branch = "reactions"
}
```

### mint Metatable — Computed Properties

A metatable `__index` on `mint` provides live-computed properties that are read every tick:

| Property | Computation | Notes |
|----------|-------------|-------|
| `mint.gcd` | `startTime + duration - GetTime()` from spell 61304 | 0 when GCD is free |
| `mint.max_gcd` | `base / (1 + haste/100)` — base is 1.0 for Energy classes, 1.5 otherwise | Capped at 50% haste |
| `mint.latency` | `select(3, GetNetStats()) / 1000` | Home latency in seconds |
| `mint.class` | `string.lower(select(2, UnitClass("player")))` | e.g. `"paladin"` |
| `mint.specId` | `GetSpecializationInfo(GetSpecialization())` | Numeric spec ID |
| `mint.specName` | Lowercase spec name from `GetSpecializationInfo` | e.g. `"holy"` |

### mint.console — Debug Console

The loader creates a movable, scrollable `ScrollingMessageFrame` attached to `UIParent`. It provides:

- `mint.console.log(...)` — writes timestamped messages to the console frame and to `debug.log` on disk
- `mint:Log(...)` — writes to the chat box (player-visible)
- Color prefix support: if first arg is `|cFFRRGGBB` (10 chars), it's used as the timestamp color

### mint:Require(path, ...)

The core file loader. Reads a Lua file, compiles it, and executes it:

```lua
function mint:Require(path, ...)
    local contents = winkr_ReadFile(base .. "\\" .. path:gsub("/", "\\"))
    local fn, err = loadstring(contents, "@" .. name .. "/" .. path)
    if fn then
        local success, result = pcall(fn, unlocker, self, ...)
        return result
    end
end
```

Key details:
- Forward slashes in `path` are converted to backslashes for Windows
- The compiled chunk receives `(unlocker, mint, ...)` as arguments
- Errors are caught with `pcall` and routed to `geterrorhandler()` and `mint.console.log`
- The `@name/path` prefix in `loadstring` gives meaningful error stack traces

### mint:ProcessModule(module, ...)

Dispatches module loading based on the `type` field in `load-order.json`:

**`type: "require"`**
1. Calls `mint:Require(module.path)`
2. If `module.assignTo` exists, assigns the result to `mint[assignTo]`
   - Supports dot-separated paths: `"Interface.Element"` → `mint.Interface.Element`
3. If `module.postProcess` exists, executes it as a Lua code string

**`type: "instance"`**
1. Calls `mint:Require(module.path)` to get the class table
2. Calls `:New()` on the result to create an instance
3. If `module.postInit` exists, calls that method on the instance (e.g. `instance:Populate()`)
4. Assigns instance to `mint[assignTo]`

**`type: "classFile"`**
1. Checks `module.class` against `mint.class` — **skips if mismatch**
2. Checks `module.spec` against `mint.specName` — **skips if mismatch**
3. Calls `mint:Require(module.path, rotations)` where `rotations` is a shared table

This conditional loading is how MINT only loads the relevant class/spec APL at runtime.

---

## load-order.json — Module Manifest

A JSON file declaring every module to load, in order. Structure:

```json
{
  "order": [
    {
      "path": "Engine/Classes/List.lua",
      "type": "require",
      "assignTo": "List"
    },
    {
      "path": "Engine/Classes/ObjectManager.lua",
      "type": "instance",
      "assignTo": "ObjectManager"
    },
    {
      "path": "APLs/Paladin/Holy/actor.lua",
      "type": "classFile",
      "class": "paladin",
      "spec": "holy"
    }
  ]
}
```

### Module Properties

| Property | Type | Required | Description |
|----------|------|----------|-------------|
| `path` | string | ✅ | File path relative to `WINKR_MODS_DIR` |
| `type` | string | ✅ | `"require"`, `"instance"`, or `"classFile"` |
| `assignTo` | string | ❌ | Dot-separated path on `mint` table (e.g. `"Interface.Element"`) |
| `class` | string | ❌ | Required class for `classFile` (lowercase, e.g. `"paladin"`) |
| `spec` | string | ❌ | Required spec for `classFile` (lowercase, e.g. `"holy"`) |
| `postInit` | string | ❌ | Method name to call on instance after `:New()` |
| `postProcess` | string | ❌ | Lua code string to execute after module loads |

### Load Order Groups

The ~89 modules load in this conceptual order:

1. **Wrappers** — Winkr C-bridge abstraction (`Engine/Wrappers.lua`)
2. **Utility classes** — json, Command, List, Draw, Timer, Vector3, EventManager
3. **Data classes** — Database/Settings, Cache, DebugFrame, SmartObject
4. **Unit system** — Aura, AuraTable, Unit, Unit/Attributes
5. **Managers** — FriendManager, UnitManager, ObjectManager
6. **Spell system** — Spell, Spell/Attributes, Spell/Methods, Spell/Empower
7. **Constants** — Constants, Columns
8. **More managers** — TotemManager, Item, TimeToDie
9. **Interface** — StdUi core, config, layout, widgets (20 widget files), API, pages
10. **Notifications & Queue** — Notification, NotificationManager, Queue
11. **Automation** — Keybinds, Actor, RaidEvents, Reaction, Sequencer
12. **Utility systems** — Dispel, SmartTarget, Utility, Draws
13. **Engine Core** — `Engine/Core.lua` (the tick loop — loaded last among Engine modules)
14. **APL files** — Utility APLs first, then class files (conditional on player class/spec)

### The Load() Function

After parsing `load-order.json`, the `Load(data, branch)` function:

1. Sets `mint.data.active_branch`
2. Iterates `data.order` and calls `mint:ProcessModule(module)` for each
3. Fires `"BuildOptions"` and `"BuildQuickbar"` events to finalize the UI

---

## How Class Files Load Conditionally

When `ProcessModule` encounters a `classFile`:

```lua
if module.type == "classFile" then
    if module.class and module.class ~= mint.class then
        return nil  -- Wrong class, skip
    end
    if module.spec and module.spec ~= mint.specName then
        return nil  -- Wrong spec, skip
    end
    result = mint:Require(module.path, rotations, ...)
end
```

A Paladin player logging in loads only:
- `APLs/Utility/utility.lua` and `APLs/Utility/visions.lua` (no class filter)
- `APLs/Paladin/paladin.lua` (class matches)
- `APLs/Paladin/Holy/*.lua` (class + spec match, if Holy)

All other class files are silently skipped with a console log noting the mismatch.

---

## How to Add a New Module

### Adding an Engine module

1. Create your `.lua` file in `Engine/Classes/` or `Engine/` as appropriate
2. Add an entry to `load-order.json` in the correct position (after dependencies):

```json
{
    "path": "Engine/Classes/MyModule.lua",
    "type": "instance",
    "assignTo": "MyModule"
}
```

3. Your file should return a table with a `:New()` constructor (for `instance` type) or just return the module table (for `require` type)

### Adding a new class/spec

1. Create the class folder: `APLs/[ClassName]/`
2. Create the class root: `APLs/[ClassName]/[classname].lua`
3. Create the spec folder: `APLs/[ClassName]/[SpecName]/`
4. Create the spec files: `spells.lua`, `actor.lua`, `settings.lua`
5. Add entries to `load-order.json`:

```json
{
    "path": "APLs/ClassName/classname.lua",
    "type": "classFile",
    "class": "classname"
},
{
    "path": "APLs/ClassName/SpecName/spells.lua",
    "type": "classFile",
    "class": "classname",
    "spec": "specname"
},
{
    "path": "APLs/ClassName/SpecName/actor.lua",
    "type": "classFile",
    "class": "classname",
    "spec": "specname"
}
```

All class/spec strings must be **lowercase** and match exactly what `mint.class` / `mint.specName` returns.

---

## Slash Commands (Defined in loader.lua)

| Command | Description |
|---------|-------------|
| `/mintdebug` | Toggle `mint.data.debug_mode` on/off |
| `/winkrtest` | Test `winkr_NativeCast(172)` on mouseover/target |
| `/winkraura` | Dump all auras on target/mouseover |
| `/winkrdebug` | Full pipeline debug dump to `scan_log_debug.txt` |
| `/ghoulcheck` | Scan player buffs for ghoul-related auras |
| `/plaguecheck` | Scan target debuffs for plague/disease auras |
