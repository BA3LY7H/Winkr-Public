# Architecture Overview

> MINT is a high-precision Lua combat rotation framework for World of Warcraft, running on the Winkr unlocker/modloader.

---

## What MINT Does

MINT automates combat rotations (Action Priority Lists) for WoW classes. It reads the game state 20 times per second, evaluates priority-ordered ability checks, and fires the optimal spell via Winkr's native casting bridge. It supports PvP and PvE across 11 classes and 17+ specializations.

---

## High-Level Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                        BOOTSTRAP                            │
│  _init.lua → loader.lua → load-order.json                    │
│  Sets up: mint global, metatable, console, Require()        │
└──────────────────────────┬──────────────────────────────────┘
                           │ loads 145 modules in order
                           ▼
┌─────────────────────────────────────────────────────────────┐
│                         ENGINE                              │
│  ┌────────────┐  ┌──────────────┐  ┌─────────────────────┐ │
│  │ Wrappers   │  │  Classes     │  │   Interface (StdUi) │ │
│  │ (Winkr C   │  │  Unit, Spell │  │   Widgets, Pages    │ │
│  │  bridge)   │  │  Aura, List  │  │   Settings UI       │ │
│  └────────────┘  │  Item, Vec3  │  └─────────────────────┘ │
│                  └──────────────┘                           │
│  ┌────────────┐  ┌──────────────┐  ┌─────────────────────┐ │
│  │ Managers   │  │  Utilities   │  │   Core.lua          │ │
│  │ Object,    │  │  Dispel,     │  │   20Hz tick loop    │ │
│  │ Unit,      │  │  SmartTarget │  │   CLEU handler      │ │
│  │ Friend,    │  │  Queue,      │  │   Pause system      │ │
│  │ Totem      │  │  Keybinds    │  │   Projectile track  │ │
│  └────────────┘  └──────────────┘  └─────────────────────┘ │
└──────────────────────────┬──────────────────────────────────┘
                           │ provides API to
                           ▼
┌─────────────────────────────────────────────────────────────┐
│                    APLs (Rotations)                          │
│  APLs/[Class]/[class].lua          — class root, Actors     │
│  APLs/[Class]/[Spec]/spells.lua    — spell/aura definitions │
│  APLs/[Class]/[Spec]/actor.lua     — rotation logic (Sync)  │
│  APLs/[Class]/[Spec]/settings.lua  — UI settings page       │
│  APLs/[Class]/[Spec]/reactions.lua — dungeon reactions       │
└─────────────────────────────────────────────────────────────┘
```

---

## Key Architectural Concepts

### The Tick Loop

`Engine/Core.lua` runs an `OnUpdate` callback at **20 Hz** (every 0.05 seconds). Each tick:

1. Checks the engine toggle — skip if OFF
2. Updates FriendManager, ObjectManager, TimeToDie
3. Checks the pause window (manual input detected → pause 0.35s)
4. Iterates each registered **Actor** and calls `actor:Tick()` if conditions match

This is the heartbeat of the entire framework. All rotation logic executes inside this loop.

### GCD Gating

Most rotation decisions are gated on `mint.gcd == 0` — meaning the Global Cooldown has expired and a new ability can be cast. The `mint.gcd` property is computed dynamically via the `mint` metatable (querying spell 61304's cooldown).

Spells also check `IsReady()` (not on cooldown) and `Castable(target)` (range, LoS, facing) before firing.

### Latency Compensation

`mint.latency` returns current network latency in seconds (from `GetNetStats()`). The casting pipeline factors this into cooldown and flight time calculations so the framework can queue actions slightly ahead of the server's timeline.

### Domain Boundaries

MINT enforces clear separation between three domains:

| Domain | Responsibility | Knows About |
|--------|---------------|-------------|
| **Engine** | Core classes, managers, tick loop, UI framework | Everything — but never references specific spells |
| **APLs** | Class/spec rotation logic, spell definitions | Engine API only — never touches Engine internals |
| **Shared** | Cross-class data (kick lists, dispel maps, dungeon data) | Constants only |

Engine code never references a specific class or spell ID. APL code never modifies Engine internals. This keeps the system modular.

---

## The `mint` Global Table

The `mint` table is the central namespace. It's created as an empty table `{}` in `_init.lua` and passed to `loader.lua`, which attaches:

- **`mint.data`** — runtime state (toggles, actors, debug flags, cast timers)
- **`mint.console`** — debug console UI frame and logging functions
- **`mint:Require(path)`** — file loader (read → compile → execute)
- **`mint:ProcessModule(module)`** — module processor (handles type dispatch)

### Metatable Pattern

A metatable `__index` on `mint` provides computed properties:

| Property | Computation |
|----------|-------------|
| `mint.gcd` | Remaining GCD seconds (spell 61304 cooldown) |
| `mint.max_gcd` | Haste-adjusted max GCD: `base / (1 + haste/100)` |
| `mint.latency` | Network latency in seconds |
| `mint.class` | Lowercase player class string (e.g. `"paladin"`) |
| `mint.specId` | Numeric specialization ID |
| `mint.specName` | Lowercase spec name (e.g. `"holy"`) |

These are read every tick and used throughout the framework for conditional logic.

---

## Module Types

`load-order.json` declares 145 modules. Each has a `type` that determines how `ProcessModule()` handles it:

| Type | Behavior | Example |
|------|----------|---------|
| `require` | Load file, execute, optionally assign result to `mint[assignTo]` | `Engine/Classes/List.lua` → `mint.List` |
| `instance` | Load file, call `:New()` on result, assign instance to `mint[assignTo]` | `Engine/Classes/ObjectManager.lua` → `mint.ObjectManager` |
| `classFile` | **Conditional** — only loads if `module.class == mint.class` AND `module.spec == mint.specName`. Receives the shared `rotations` table. | `APLs/Paladin/Holy/actor.lua` |

Additional module options:
- **`assignTo`** — dot-separated path on `mint` (e.g. `"Interface.Element"`)
- **`postInit`** — method name called on instance after `:New()` (e.g. `"Populate"`)
- **`postProcess`** — Lua code string executed after module loads

---

## Engine ↔ APL Contract

### What Engine Provides (API surface for APLs)

| API | Purpose |
|-----|---------|
| `mint.Spell.New(id, traits)` | Create spell objects with casting/validation logic |
| `mint.Item.New(id, opts)` | Create item objects with use/cooldown logic |
| `mint.Actor.New(opts)` | Create rotation actors with `Sync()` callback |
| `mint.UnitManager:Get(token)` | Get auto-refreshing unit references |
| `mint.FriendManager:GetLowest(range)` | Find lowest-HP ally |
| `mint.ObjectManager.combat:loop(fn)` | Iterate enemies in combat |
| `mint.Dispel:GetTarget()` | Get highest-priority dispel target |
| `mint.Queue:IsInFlight(id)` | Check projectile flight status |
| `mint.Settings.profile[class][spec]` | Read/write user settings |
| `mint.Interface` | Build settings UI pages |

### What APLs Provide (contract back to Engine)

| Component | Purpose |
|-----------|---------|
| `[class].lua` | Creates Actors, initializes per-spec data tables |
| `spells.lua` | Registers all Spell/Aura/Item objects into `addon[class].data[Spec]` |
| `actor.lua` | Provides `actor:Sync(fn)` callback — the actual rotation logic |
| `settings.lua` | Builds the UI settings page for the spec |
| `reactions.lua` | *(Optional)* Registers dungeon-specific reactive behaviors |

---

## Supported Classes & Specs

| Class | Specializations |
|-------|----------------|
| Paladin | Holy, Protection |
| Priest | Discipline, Shadow |
| Evoker | Devastation, Preservation, Augmentation |
| Hunter | Beast Mastery |
| Mage | Fire |
| Monk | Mistweaver |
| Shaman | Enhancement |
| Death Knight | Blood, Unholy |
| Druid | Feral, Restoration |
| Warrior | Generic (all specs) |
| Warlock | Generic (all specs) |

---

## File Layout Summary

```
C:\mods\mint\
├── _init.lua             # Winkr bootstrap entry point (reads & executes loader.lua)
├── loader.lua            # Framework init, module loader, mint metatable
├── load-order.json       # 145 module declarations
├── retail.toc            # WoW addon manifest
├── Types.lua             # LuaDoc type annotations
├── Engine/               # Core framework
│   ├── Core.lua          # Tick loop, CLEU, pause system
│   ├── Wrappers.lua      # Winkr C-bridge abstraction
│   ├── Classes/          # Unit, Spell, Aura, List, Item, Managers...
│   ├── Constants/        # Kick lists, dispel maps, spec IDs
│   └── Interface/        # StdUi widgets, API, pages
├── APLs/                 # One folder per class, subfolders per spec
├── Profiles/             # JSON settings profiles
└── Documentation/        # You are here
```
