# APL System

> The Action Priority List (APL) system is MINT's core rotation framework. Every combat rotation — DPS, healing, or tanking — is built as an APL: a prioritized list of spell checks that runs every engine tick.

---

## Table of Contents

1. [What is an APL?](#what-is-an-apl)
2. [APL File Structure](#apl-file-structure)
3. [Class Base Files](#class-base-files)
4. [Actor System](#actor-system)
5. [Spell Definitions](#spell-definitions)
6. [Writing a Rotation (actor.lua)](#writing-a-rotation-actorlua)
7. [Settings Definitions](#settings-definitions)
8. [The classFile Module Type](#the-classfile-module-type)
9. [Supported Classes & Specs](#supported-classes--specs)
10. [How to Add a New Spec](#how-to-add-a-new-spec)

---

## What is an APL?

An **Action Priority List** is a top-down list of spell checks. Each tick (default: 50ms), the engine calls your Actor's `Sync` callback, which evaluates spells in priority order. The **first** spell that passes all checks (ready, in range, conditions met) gets cast, then the callback returns. This produces optimal play by always choosing the highest-priority available action.

```
Tick → Actor:Sync callback fires
  → Guard checks (dead? mounted? casting? GCD?)
  → Priority 1: Defensive cooldown → not ready, skip
  → Priority 2: Interrupt → target not casting, skip
  → Priority 3: Core ability → READY → Cast → return
  → Priority 4+: never reached this tick
```

---

## APL File Structure

Every spec rotation follows a **3-file pattern** inside `APLs/`, with an optional fourth file:

```
APLs/
└── <ClassName>/
    ├── <classname>.lua              ← Class base (shared namespace, Actor creation)
    └── <SpecName>/
        ├── settings.lua             ← UI options & defaults for this spec
        ├── spells.lua               ← Spell definitions, auras, smart targets, callbacks
        ├── actor.lua                ← The rotation logic (priority list)
        └── reactions.lua            ← (Optional) Pre-cast reactions for dungeon mechanics
```

| File | Purpose |
|------|---------|
| `<classname>.lua` | Creates the shared `addon.<class>` namespace, initializes data tables, creates Actor instances for each spec |
| `settings.lua` | Defines default setting values and builds the UI page (sliders, checkboxes) for user configuration |
| `spells.lua` | Defines all spells via `mint.Spell.New()`, aura IDs, item definitions, smart target units, and spell callbacks |
| `actor.lua` | Contains the `Actor:Sync()` callback — the actual rotation priority list that runs every tick |
| `reactions.lua` | (Optional) Pre-cast reactions for dungeon/raid mechanics. Only some specs use this (e.g., Paladin Protection/Holy) |

**Load order matters.** Files are loaded in the order specified per-entry in `load-order.json`. The class base always loads first, but the order of settings/spells/reactions/actor **varies per spec** — check `load-order.json` for the authoritative sequence.

---

## Class Base Files

The class base file (`APLs/<ClassName>/<classname>.lua`) creates the shared data namespace and Actor instances for all specs of that class.

### Real Example: Death Knight (`APLs/Death Knight/deathknight.lua`)

```lua
local unlocker, mint, addon = ...

addon.deathknight = {}
addon.deathknight.settings = {
    ["Blood"] = {},
    ["Frost"] = {},
    ["Unholy"] = {},
}
addon.deathknight.data = {
    vars = {},
    sequences = {},
    ["Blood"] = { vars = {} },
    ["Frost"] = { vars = {} },
    ["Unholy"] = { vars = {} },
}

-- Create one Actor per spec (spec index matches GetSpecialization())
addon.deathknight.blood  = mint.Actor.New({ spec = 1, class = "deathknight" })
addon.deathknight.frost  = mint.Actor.New({ spec = 2, class = "deathknight" })
addon.deathknight.unholy = mint.Actor.New({ spec = 3, class = "deathknight" })
```

### Key Points

- `addon.<class>` is the shared namespace — all spec files read/write through it.
- `addon.<class>.data["<SpecName>"]` stores spells, auras, items, targets, and variables for each spec.
- `addon.<class>.settings["<SpecName>"]` stores UI layout definitions.
- Each spec gets its own `mint.Actor.New()` instance, keyed by **spec index** (1, 2, 3) and **class name** (lowercase).

### Real Example: Evoker (`APLs/Evoker/evoker.lua`)

The Evoker base file also demonstrates **shared utility functions**. Note the local `Actor` alias and lowercase data/settings keys (contrast with DK's title-case keys):

```lua
local Actor = mint.Actor

addon.evoker = {}
addon.evoker.settings = {
    devastation = {},
    augmentation = {},
    preservation = {},
}
addon.evoker.data = {
    vars = {},
    devastation = {},
    augmentation = {},
    preservation = {},
}

-- Actors
addon.evoker.devastation  = Actor.New({ spec = 1, class = "evoker" })
addon.evoker.augmentation = Actor.New({ spec = 3, class = "evoker" })
addon.evoker.preservation = Actor.New({ spec = 2, class = "evoker" })

-- Shared kick-target logic reused by all Evoker specs
addon.evoker.GetKickTarget = function()
    local best = mint.UnitManager:Get("none")
    local lowest_pct = 100
    mint.ObjectManager.combat:loop(function(enemy)
        if enemy.is_dead then return false end
        if enemy:IsCastingOrChanneling() and enemy:IsKickable() then
            if enemy:IsWithin(25) then
                local pct = enemy:GetCastPercent()
                if pct > 30 and pct < lowest_pct then
                    best = enemy
                    lowest_pct = pct
                end
            end
        end
        return false
    end)
    return best
end
```

> **Key naming difference:** DK uses title-case string keys (`["Blood"]`, `["Frost"]`) for data/settings sub-tables, while Evoker uses lowercase identifiers (`devastation`, `augmentation`). Either convention works — just be consistent within a class.

---

## Actor System

The `Actor` class (`Engine/Classes/Actor.lua`) is the execution backbone. Each Actor is bound to a class/spec pair and only ticks when that class and spec are active.

### API

| Method | Description |
|--------|-------------|
| `Actor.New(details)` | Creates a new Actor. `details` = `{ class = "string", spec = number, condition = function\|false }` |
| `Actor:Sync(func, rate)` | Registers a function to run every `rate` seconds (default `0.05` = 50ms). This IS your rotation. |
| `Actor:GetUI()` | Returns a `Page` object for building the spec's settings UI. |
| `Actor:ShouldRun()` | Internal — returns `true` only if the player's current class and spec match this Actor. |
| `Actor:Tick()` | Internal — called by the engine core. Iterates all synced functions respecting their tick rates. |

### How It Works

1. `Actor.New()` creates an instance and inserts it into `mint.data.actors`.
2. The engine core loops all actors every frame. For each actor, `Actor:ShouldRun()` checks class/spec match (and optional `condition` function).
3. If the actor should run, `Actor:Tick()` fires each synced function at its configured rate (comparing `GetTime()` against `last_tick`).
4. Each synced function is wrapped in `pcall` — errors are logged to `mint.console` but don't crash the engine.

### Conditional Actors

Actors can use a `condition` function instead of (or in addition to) class/spec:

```lua
-- Visions actor: only runs inside specific instance IDs
local actor = mint.Actor.New({
    condition = function()
        local _, _, _, _, _, _, _, instanceID = GetInstanceInfo()
        return instanceID == 2827 or instanceID == 2828
    end
})
```

---

## Spell Definitions

Spells are defined in `spells.lua` using `mint.Spell.New(spellID, options)`.

### Basic Syntax

```lua
local Spell = mint.Spell.New

local spells = {
    heart_strike = Spell(206930, { damage = "physical", cast_by_id = true, ignore_facing = true }),
    blood_boil   = Spell(50842,  { damage = "magic", targeted = false, cast_by_id = true }),
    mind_freeze  = Spell(47528,  { kick = true, ignore_casting = true, cast_by_id = true }),
}
```

### Spell Traits Reference

Traits are passed as the second argument to `Spell.New(id, traits)`. All default to `false` (or `0` for numeric) unless specified.

| Trait | Type | Purpose |
|-------|------|---------|
| `targeted` | `boolean` | `false` for self-cast/ground-targeted spells (default: `true`) |
| `cast_by_id` | `boolean` | Cast via spell ID directly (recommended for Winkr) |
| `beneficial` | `boolean` | Spell targets friendly units (skips facing check) |
| `kick` | `boolean` | Only castable if target is casting an interruptible spell |
| `pet` | `boolean` | Pet ability (bypasses casting/channeling/facing checks) |
| `damage` | `string` | Damage school: `"physical"`, `"magic"` |
| `heal` | `boolean` | Marks spell as a healing ability |
| `effect` | `string` | Effect type (e.g., for immunity checks) |
| `cc` | `string\|boolean` | Crowd control type |
| `bleed` | `boolean` | Marks spell as a bleed |
| `ranged` | `boolean` | Marks spell as ranged |
| `radius` | `number` | AoE radius |
| `velocity` | `number` | Projectile speed in yards/sec |
| `travel_time` | `number` | Fixed travel time in seconds (default `0`) |
| `ignore_facing` | `boolean` | Skip facing check (instants, interrupts) |
| `ignore_moving` | `boolean` | Allow casting while moving |
| `ignore_channel` | `boolean` | Skip channel protection (essential for Smart Channeling Guard) |
| `ignore_casting` | `boolean` | Allow casting during other casts (off-GCD abilities) |
| `ignore_usable` | `boolean` | Skip `IsUsable()` check — fixes delays on proc-based cost reductions |
| `ignore_los` | `boolean` | Skip line-of-sight check |
| `ignore_range` | `boolean` | Skip range check |
| `ignore_falling` | `boolean` | Allow casting while falling |
| `ignore_control` | `boolean` | Skip loss-of-control check |
| `ignore_stun` | `boolean` | Allow casting while stunned |
| `ignore_known` | `boolean` | Skip `IsKnown()` check |
| `prevent_double` | `boolean` | Prevent casting same spell twice in a row |
| `stupid_channel` | `boolean` | Special channel handling |
| `required_buff` | `boolean` | Reserved — requires a specific buff to cast (currently unused) |

### Spell Callbacks

Callbacks define **how** a spell is cast. When you call `spells.spell_name()` or `spells.spell_name("key")`, the registered callback executes.

**Important:** Before a callback fires, `Spell:PreCheck()` runs automatically. PreCheck verifies the spell is not on cooldown, is known, is usable, and the player isn't falling/moving/casting inappropriately. If PreCheck fails, the callback never runs and `false` is returned. After the callback calls `spell:Cast(unit)`, an additional `Spell:Castable(unit)` check runs against the target (existence, range, LoS, facing, kick validity, etc.).

**Calling a spell with a Unit object** (e.g., `spells.fire_breath(unit)`) bypasses the callback entirely and routes directly to `Spell:Cast(unit)`.

```lua
-- Standard target-based callback (keyless)
spells.mind_freeze:AddCallback(function(spell)
    local u = targets.kick
    if u:GetExists() then
        if u:GetCastPercent() >= 25 or u:IsChanneling() then
            return spell:Cast(u)
        end
    end
    return false
end)
```

**Callback return values:**
- `true` — spell was cast successfully (rotation returns, skipping lower priorities)
- `false` — spell was not cast (rotation continues to next priority)

### Callback with Arguments

`AddCallback` has two forms:

1. **Keyless** — `spell:AddCallback(function(spell, ...) end)` — invoked when calling `spell()` with no string key. Only one keyless callback per spell.
2. **Named** — `spell:AddCallback("key", function(spell, ...) end)` — invoked when calling `spell("key")`.

Callbacks can accept arguments passed when the spell is invoked:

```lua
-- Evoker: Standard callback forwarding target and empower rank
spells.fire_breath:AddCallback(function(s, target, rank)
    local unit = target
    if type(unit) ~= "table" then
        unit = mint.UnitManager:Get(target or "target")
    end
    if unit:GetExists() and not unit:IsDead() then
        return s:Cast(unit, rank)
    end
    return false
end)

-- Usage in actor.lua:
spells.fire_breath(target, 1)  -- Cast at rank 1
spells.fire_breath(target, 4)  -- Cast at rank 4 (execute)
```

### Named Callbacks

Protection Paladin uses named callback arguments to select different cast conditions for the same spell:

```lua
-- In actor.lua, spells are invoked with context strings:
if spells.judgment("Avoid Cap") then return end
if spells.judgment("Multi Target") then return end
if spells.judgment("Wings") then return end
if spells.judgment() then return end  -- default
```

### Batch Callback Registration

For specs with many similarly-behaving spells, use a loop:

```lua
-- Disc Priest: All spells get the same simple callback
for k, spell in pairs(spells) do
    spell:AddCallback(function(spell, unit)
        unit = unit or target
        if not unit or not unit:GetExists() then return false end
        return spell:Cast(unit)
    end)
end
```

### Spell Cast Methods

| Method | Description |
|--------|-------------|
| `Spell:Cast(unit, rank)` | Primary cast method. Runs `Castable(unit)` check, then casts. If `rank` is 1-4, prepares an empowered cast via `EmpowerManager`. Returns `true` on success. |
| `Spell:CastUnder(unit)` | Ground-targeted cast under `unit`'s position. Handles mouselook stop/start and click placement. Player must be stationary. |
| `Spell:CastEmpower(unit, level)` | Direct empower cast (legacy). Runs `Castable`, then casts without EmpowerManager tracking. |
| `Spell:CastWithPreCast(unit, precast, key)` | Casts only if `precast()` returns true. Used for conditional pre-actions before the actual cast. |
| `Spell:CastNotify(unit, text, dur, icon)` | Wraps `Cast()` — if successful, shows a notification via `NotificationManager`. |
| `Spell:PreCheck()` | Checks spell readiness without a target: cooldown, known, usable, casting/channeling state, movement. Called automatically before callbacks. |
| `Spell:Castable(unit)` | Full target-aware check: existence, dead, range, LoS, facing, kick validity, prevent_double. Called automatically by `Cast()`. |

### Spell Attribute Accessors

Spells expose computed attributes via metatable. Access them as properties (not method calls):

```lua
spell.cd          -- Remaining cooldown (seconds)
spell.on_cd       -- true if on cooldown (duration > max_gcd + 0.2)
spell.ready       -- true if not on CD
spell.charges      -- Current charges
spell.charges_frac -- Fractional charges (e.g., 1.7)
spell.charges_max  -- Max charges
spell.known       -- true if spell is known
spell.usable      -- true if spell is usable (has resources)
spell.cast_time   -- Cast time in seconds
spell.cost        -- Resource cost
spell.range       -- Max range in yards
spell.count       -- Spell cast count (e.g., for stacking spells)
```

### Auras

Aura definitions are simple ID tables used for buff/debuff tracking:

```lua
local auras = {
    bone_shield       = { id = 195181 },
    crimson_scourge   = { id = 81136 },
    blood_plague      = { id = 55078 },
}

-- Usage in actor/callbacks:
local shield = player:FindBuffByID(auras.bone_shield)
if shield:Remains() < 3 or shield:Count() < 6 then
    -- refresh bone shield
end
```

### Smart Units

Smart Units are dynamically-evaluated targeting functions that auto-select the best unit:

```lua
targets.kick = mint.UnitManager:CreateSmartUnit("bdk_kick", function()
    if not mint.data.toggles.kicks then return mint.UnitManager:Get("none") end
    local best = nil
    local best_pct = -1

    mint.ObjectManager.combat:loop(function(enemy)
        if enemy.dead or not enemy:GetExists() or not enemy:IsKickable() then return end
        if player:GetDistance(enemy) <= 15 and player:HasLos(enemy) then
            local pct = enemy:GetCastPercent()
            if pct > best_pct then
                best_pct = pct
                best = enemy
            end
        end
        return false
    end)
    return best or mint.UnitManager:Get("none")
end)
```

### Items

Items follow a similar pattern to spells:

```lua
local Item = mint.Item.New
local items = {
    healthstone = Item(5512),
}
```

---

## Writing a Rotation (actor.lua)

The actor file is where all rotation logic lives. It registers a `Sync` callback on the spec's Actor.

### Anatomy of an Actor File

```lua
local unlocker, mint, addon = ...

-- 1. Pull references from the shared namespace
local blood   = addon.deathknight.blood           -- The Actor
local data    = addon.deathknight.data["Blood"]    -- Spec data
local spells  = data.spells
local auras   = data.auras
local targets = data.targets

local player  = mint.UnitManager:Get("player")
local target  = mint.UnitManager:Get("target")

-- 2. Register the rotation callback
blood:Sync(function()
    -- Guards
    if player:IsDead() or IsMounted() then return end
    if player:IsCasting() or player:IsChanneling() then return end
    if mint.gcd > 0.05 then return end
    if not mint.data.toggles.engine then return end

    -- Priority list (highest priority first)
    if spells.vampiric_blood() then return end
    if spells.death_strike() then return end
    if spells.marrowrend:Cast(target) then return end
    if spells.heart_strike:Cast(target) then return end
end, 0.1)  -- Optional: custom tick rate (default 0.05)
```

### Guard Pattern

Every rotation starts with guards that prevent casting in invalid states:

| Guard | Purpose |
|-------|---------|
| Dead/Mounted check | Don't cast while dead or mounted |
| Casting/Channeling check | Don't interrupt genuine casts |
| GCD check | Wait until GCD is within spell queue window |
| Engine toggle | Respect the global engine on/off toggle |
| Throttle (`lastCastTime`) | Prevent multi-cast spam within a single engine tick |

### Smart Channeling Guard (Advanced)

For specs with channeled abilities (e.g., Evoker Disintegrate), the rotation implements a more sophisticated guard:

```lua
-- From Devastation Evoker actor.lua
if UnitCastingInfo("player") then return end  -- Block during hard casts

local chanName, _, _, _, chanEndMS = UnitChannelInfo("player")
if chanName then
    if mint.EmpowerManager.active_spell then return end  -- Never clip empowers
    
    local chanRemaining = (chanEndMS / 1000) - GetTime()
    if chanRemaining > 0 then
        -- Wait until within one tick interval of channel end
        if chanRemaining > hastedTickInterval then return end
        isChaining = true  -- Flag: we're in pandemic window
    else
        actor.isPhantom = true  -- Channel physically done, API lagging
    end
end

-- Bypass channel blocks for fillers during chain/phantom
local bypass = isChaining or actor.isPhantom
spells.disintegrate.ignore_channel = bypass
spells.azure_strike.ignore_channel = bypass
```

### Casting Spells

There are two patterns for casting:

**1. Callback invocation** (recommended for complex logic):
```lua
-- Calls the spell's registered callback
if spells.death_and_decay() then return end
if spells.dark_command() then return end
```

**2. Direct cast** (simple cases):
```lua
-- Bypasses callback, casts directly on target
if spells.heart_strike:Cast(target) then return end
if spells.marrowrend:Cast(target) then return end
```

### Priority Structure

The `if ... then return end` pattern creates natural priority ordering:

```lua
-- From Blood DK actor.lua:

-- HIGH PRIORITY: Defensives (survival)
if mint.data.toggles.defensives then
    if spells.vampiric_blood() then return end
    if spells.icebound_fortitude() then return end
end

-- MID PRIORITY: Maintenance
if spells.death_and_decay() then return end
if spells.death_strike() then return end

-- Bone Shield maintenance
local shield = player:FindBuffByID(auras.bone_shield)
if (not shield or shield:Remains() < 3 or shield:Count() < 6) then
    if spells.marrowrend:Cast(target) then return end
end

-- LOW PRIORITY: Fillers
if spells.heart_strike:Cast(target) then return end
if spells.blood_boil:Cast(player) then return end
```

### Target Management

Most rotations include automatic target acquisition:

```lua
-- Blood DK: Switch to taunt target if in melee
local taunt_unit = targets.taunt
if taunt_unit:GetExists() and taunt_unit:IsWithin(8) then
    if not target:IsUnit(taunt_unit) then
        winkr_SetNPC(taunt_unit.guid)
    end
end

-- Fallback to SmartTarget
if not target.exists or target.is_dead or not target.can_attack then
    SmartTarget:Acquire()
end
```

### Healer Rotation Pattern (Disc Priest)

Healer rotations blend friend-healing with enemy-DPS:

```lua
-- 1. Shield low-HP players
local lowest_friend = FriendManager:GetLowest(90)
if lowest_friend and not lowest_friend:FindBuffByID(auras.power_word_shield.id):Active() then
    if spells.power_word_shield(lowest_friend) then return end
end

-- 2. Group healing if needed
if FriendManager:GetCountBelow(85) >= 2 then
    if spells.power_word_radiance(player) then return end
end

-- 3. DPS for Atonement healing
if spells.shadow_word_pain(target) then return end
if spells.penance(target) then return end
if spells.smite(target) then return end
```

---

## Settings Definitions

Settings files define user-configurable options and build UI pages.

### Pattern

```lua
local unlocker, mint, addon = ...
local settings = mint.Settings

-- 1. Get the UI page from the Actor
local ui = addon.deathknight.blood:GetUI()

-- 2. Define defaults
local defaults = {
    death_strike_hp   = 70,
    death_strike_rp   = 75,
    vampiric_blood_hp = 40,
    icebound_hp       = 30,
    auto_ghoul        = true,
    maintain_cleave   = true,
    bone_shield_min   = 6,
}
ui:AddDefaults(defaults)

-- 3. Define the layout
addon.deathknight.settings["Blood"] = {
    page = {
        layoutConfig = { padding = { top = 15 } },
        database = settings.profile.deathknight.blood,
        rows = {
            {
                header = {
                    type = 'header',
                    label = '|TInterface\\Icons\\spell_deathknight_bloodpresence:18:18|t Blood Death Knight'
                }
            },
            {
                death_strike_hp = {
                    key = 'death_strike_hp',
                    type = 'slider',
                    label = 'Death Strike HP %',
                    min = 10, max = 100, column = 6, order = 1
                },
                death_strike_rp = {
                    key = 'death_strike_rp',
                    type = 'slider',
                    label = 'Death Strike RP Trigger',
                    min = 40, max = 95, column = 6, order = 2
                },
            },
            {
                auto_ghoul = {
                    key = 'auto_ghoul',
                    type = 'checkbox',
                    label = 'Auto-Ghoul (Raise Dead)',
                    column = 6, order = 1
                },
            },
        }
    }
}

-- 4. Apply layout to UI
ui:AddLayout(addon.deathknight.settings["Blood"].page)
```

### UI Element Types

| Type | Properties |
|------|-----------|
| `header` | `label` — section header text |
| `label` | `label`, `size` — descriptive text |
| `slider` | `key`, `label`, `min`, `max`, `column`, `order`, `precision` |
| `checkbox` | `key`, `label`, `tooltip`, `column`, `order` |

### Quick Buttons

For simple toggles that don't need the full page system:

```lua
-- From Protection Paladin settings.lua
mint.Interface:AddQuickButton("Inv_ability_paladin_divinetoll", "DivineToll", "Toll", function()
    addon.paladin.settings["Protection"].DivineToll = not addon.paladin.settings["Protection"].DivineToll
end)
```

### Accessing Settings in actor.lua

```lua
local profile = mint.Settings.profile.deathknight.blood
-- or link it through the addon namespace:
blood.settings = profile

-- Usage:
if player:GetHP() < profile.vampiric_blood_hp then
    spells.vampiric_blood:Cast(player)
end
```

---

## The classFile Module Type

In `load-order.json`, APL files use the `"classFile"` type, which tells the loader to only load the file if the player's class (and optionally spec) matches.

```json
{
    "path": "APLs/Death Knight/deathknight.lua",
    "type": "classFile",
    "class": "deathknight"
},
{
    "path": "APLs/Death Knight/Blood/spells.lua",
    "type": "classFile",
    "class": "deathknight",
    "spec": "blood"
}
```

| Property | Description |
|----------|-------------|
| `type` | `"classFile"` — conditional loading based on player class/spec |
| `class` | Lowercase class name (e.g., `"deathknight"`, `"paladin"`, `"evoker"`) |
| `spec` | (Optional) Lowercase spec name. If omitted, loads for all specs of that class |

Files without a `class` property (like `APLs/Utility/utility.lua`) load for **all** classes.

**Load order within a spec is defined per-entry in `load-order.json`.** The class base always loads first. The remaining files (settings, spells, reactions, actor) vary per spec — consult `load-order.json` for the authoritative order.

---

## Supported Classes & Specs

| Class | Spec | Path |
|-------|------|------|
| Death Knight | Blood | `APLs/Death Knight/Blood/` |
| Death Knight | Unholy | `APLs/Death Knight/Unholy/` |
| Druid | Feral | `APLs/Druid/Feral/` |
| Druid | Restoration | `APLs/Druid/Restoration/` |
| Evoker | Devastation | `APLs/Evoker/Devastation/` |
| Evoker | Augmentation | `APLs/Evoker/Augmentation/` |
| Evoker | Preservation | `APLs/Evoker/Preservation/` |
| Hunter | Beast Mastery | `APLs/Hunter/BeastMastery/` |
| Mage | Fire | `APLs/Mage/Fire/` |
| Monk | Mistweaver | `APLs/Monk/Mistweaver/` |
| Paladin | Protection | `APLs/Paladin/Protection/` |
| Paladin | Holy | `APLs/Paladin/Holy/` |
| Priest | Discipline | `APLs/Priest/Discipline/` |
| Priest | Shadow | `APLs/Priest/Shadow/` |
| Shaman | Enhancement | `APLs/Shaman/Enhancement/` |
| Warlock | Generic | `APLs/Warlock/Generic/` |
| Warrior | Generic | `APLs/Warrior/Generic/` |

**Utility modules** (loaded for all classes):
- `APLs/Utility/utility.lua` — shared utility namespace
- `APLs/Utility/visions.lua` — Horrific Visions automation

---

## How to Add a New Spec

### Step 1: Create the Class Base (if new class)

Create `APLs/<ClassName>/<classname>.lua`:

```lua
local unlocker, mint, addon = ...

addon.<classname> = {}
addon.<classname>.settings = {
    ["<SpecName>"] = {},
}
addon.<classname>.data = {
    vars = {},
    ["<SpecName>"] = { vars = {} },
}

-- Create Actor (spec index from GetSpecialization())
addon.<classname>.<specname> = mint.Actor.New({ spec = <N>, class = "<classname>" })
```

If the class already exists, just add the new spec's data table and Actor to the existing base file.

### Step 2: Create settings.lua

```lua
local unlocker, mint, addon = ...
local settings = mint.Settings
local ui = addon.<classname>.<specname>:GetUI()

local defaults = {
    -- your defaults here
}
ui:AddDefaults(defaults)

addon.<classname>.settings["<SpecName>"] = {
    page = {
        layoutConfig = { padding = { top = 15 } },
        database = settings.profile.<classname>.<specname>,
        rows = {
            -- your UI rows here
        }
    }
}
ui:AddLayout(addon.<classname>.settings["<SpecName>"].page)
```

### Step 3: Create spells.lua

```lua
local unlocker, mint, addon = ...
local Spell = mint.Spell.New
local player = mint.UnitManager:Get("player")
local target = mint.UnitManager:Get("target")

local spells = {
    ability_one = Spell(<id>, { cast_by_id = true }),
    ability_two = Spell(<id>, { targeted = false }),
    kick        = Spell(<id>, { kick = true, ignore_casting = true }),
}

local auras = {
    my_buff   = { id = <buff_id> },
    my_debuff = { id = <debuff_id> },
}

-- Add callbacks
spells.ability_one:AddCallback(function(spell)
    if target:GetExists() and not target:IsDead() then
        return spell:Cast(target)
    end
    return false
end)

-- Register to addon namespace
addon.<classname>.data["<SpecName>"].spells = spells
addon.<classname>.data["<SpecName>"].auras  = auras
```

### Step 4: Create actor.lua

```lua
local unlocker, mint, addon = ...

local actor   = addon.<classname>.<specname>
local spells  = addon.<classname>.data["<SpecName>"].spells
local auras   = addon.<classname>.data["<SpecName>"].auras
local player  = mint.UnitManager:Get("player")
local target  = mint.UnitManager:Get("target")

actor:Sync(function()
    -- Guards
    if player:IsDead() or IsMounted() then return end
    if player:IsCasting() or player:IsChanneling() then return end
    if mint.gcd > 0.05 then return end
    if not mint.data.toggles.engine then return end

    -- Target acquisition
    if not target.exists or target.is_dead then
        mint.SmartTarget:Acquire()
    end
    if not target.exists or not target.can_attack then return end

    -- Rotation priority
    if spells.ability_one() then return end
    if spells.ability_two() then return end
end)
```

### Step 5: Register in load-order.json

Add entries **after** the engine core but respecting load order:

```json
{
    "path": "APLs/<ClassName>/<classname>.lua",
    "type": "classFile",
    "class": "<classname>"
},
{
    "path": "APLs/<ClassName>/<SpecName>/settings.lua",
    "type": "classFile",
    "class": "<classname>",
    "spec": "<specname>"
},
{
    "path": "APLs/<ClassName>/<SpecName>/spells.lua",
    "type": "classFile",
    "class": "<classname>",
    "spec": "<specname>"
},
{
    "path": "APLs/<ClassName>/<SpecName>/actor.lua",
    "type": "classFile",
    "class": "<classname>",
    "spec": "<specname>"
}
```

### Performance Tips

| Tip | Detail |
|-----|--------|
| Use `ignore_channel = true` on rotational spells | Lets your Smart Channeling Guard handle protection instead of the framework's PreCheck |
| Use `ignore_usable = true` on proc-dependent spells | The `IsUsable()` API lags after proc consumption — handle resource checks manually |
| Use `GetUnitSpeed("player") > 0` for movement | `player:IsMoving()` has ~300ms latency from coordinate-based velocity calculation |
| Set `ignore_moving = true` on empowers | Handle movement gating in the actor for zero-latency empower stops |
| Add `lastCastTime` throttle | Prevent multiple casts within a single engine tick due to 50ms tick rate |
| Don't queue empowers | Add `rem <= 0.05` check before empower spells to avoid Press & Tap UI glitches |
