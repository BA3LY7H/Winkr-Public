# Utilities

> Shared utility systems available to all specs: dispels, smart targeting, 3D drawing, constants, and cross-class automation.

---

## Table of Contents

1. [Shared Utility](#shared-utility)
2. [Dispel System](#dispel-system)
3. [Stop / Kick System](#stop--kick-system)
4. [SmartTarget](#smarttarget)
5. [Draw System](#draw-system)
6. [Notification System](#notification-system)
7. [Queue / Flight Tracking](#queue--flight-tracking)
8. [Keybind System](#keybind-system)
9. [Slash Commands](#slash-commands)
10. [Constants](#constants)
11. [Visions](#visions)

---

## Shared Utility

The `Utility` class (`Engine/Classes/Utility/Utility.lua`) provides shared helper functions used across the framework.

### Methods

| Method | Description |
|--------|-------------|
| `Utility:TableMerge(table1, table2)` | Deep-merges two tables, with `table2` values taking precedence over `table1` |

### Utility Namespace in APLs

`APLs/Utility/utility.lua` creates a shared namespace for cross-class modules:

```lua
addon.utility = {
    ["Visions"] = {
        settings = {},
        data = {}
    }
}
```

This is loaded for **all classes** (no `class` filter in `load-order.json`).

---

## Dispel System

The Dispel system (`Engine/Classes/Utility/Dispel.lua`) automatically removes harmful debuffs from party/raid members using class-appropriate dispel spells.

### Architecture

```
Constants.ClassDispelMap → Dispel:New() → per-class spell list
Constants.TWWS2.debuff_map → known dungeon debuffs with conditions
Settings.profile.dispels → per-debuff enable/disable toggles
Dispel:Scan() → FriendManager loop → match debuff → cast dispel
```

### Initialization

`Dispel:New()` is called during engine startup. It:

1. Reads the player's class and spec.
2. Looks up available dispel spells from `Constants.ClassDispelMap`.
3. Reads the initial dispel delay from `mint.data.vars.dispel_delay` (shared var).
4. Registers `PLAYER_TALENT_UPDATE` and `PLAYER_SPECIALIZATION_CHANGED` events to refresh the dispel list on spec changes.

### Scan Logic

`Dispel:Scan()` runs at a 250ms scan rate and:

1. Loops all friends via `FriendManager:Loop()`.
2. For each friend, iterates all `HARMFUL` auras using `C_UnitAuras.GetAuraDataByIndex()`.
3. Checks if the debuff ID exists in `Constants.TWWS2.debuff_map`.
4. Checks if the debuff is enabled in Settings (`IsDispelEnabled()`).
5. For each matching debuff, finds a player dispel spell that can remove that dispel type.
6. Evaluates the debuff's `condition` function (e.g., some debuffs should only be dispelled on non-tanks).
7. Applies a **randomized delay** before actually dispelling to appear human-like.
8. If all checks pass, casts the dispel on the friend.

### Delay System

The delay system prevents instant-dispels that look automated:

```lua
function Dispel:GetNewDelay()
    local new = math.random(8, 25) / 10  -- 0.8s to 2.5s
    if new == self.dispel_delay then
        return self:GetNewDelay()  -- Never repeat same delay
    end
    self.dispel_delay = new
    return self.dispel_delay
end
```

After each dispel cast, a new random delay is generated and stored in `mint.data.vars.dispel_delay`. The system checks:
- For timed debuffs: has enough time elapsed since application (`waited > delay`)?
- For permanent debuffs (duration 0): has enough time passed since first seen?

### Dispel Type Matching

Each dispel spell has a `CanDispelType(dispelType)` check. The system matches:
- `"Magic"`, `"Curse"`, `"Poison"`, `"Disease"`, `"Bleed"` debuff types
- Against the player's available dispels from `ClassDispelMap`

### Class Dispel Map

Defined in `Constants.lua`, maps each class/spec to their dispel spells:

| Class | Specs | Dispel Spells |
|-------|-------|---------------|
| Druid | Balance, Feral, Guardian | Remove Corruption (2782) |
| Druid | Restoration | Nature's Cure (88423), Remove Corruption (2782) |
| Evoker | Devastation, Augmentation | Cauterizing Flame (374251), Expunge (365585) |
| Evoker | Preservation | Cauterizing Flame (374251), Naturalize (360823) |
| Mage | All | Remove Curse (475) |
| Monk | All | Detox (115450) |
| Paladin | Holy | Cleanse (4987) |
| Paladin | Protection, Retribution | Cleanse Toxins (213644) |
| Priest | Discipline, Holy | Purify (527) |
| Priest | Shadow | Purify Disease (213634) |
| Shaman | Elemental, Enhancement | Cleanse Spirit (51886), Poison Cleansing Totem (383013) |
| Shaman | Restoration | Purify Spirit (77130), Poison Cleansing Totem (383013) |
| Death Knight | — | None |
| Demon Hunter | — | None |
| Hunter | — | None |
| Rogue | — | None |
| Warlock | — | None |
| Warrior | — | None |

### Per-Spec Inline Dispels

Some specs implement their own dispel logic directly in `actor.lua` instead of (or in addition to) the engine dispel system. For example, Devastation Evoker:

```lua
-- From APLs/Evoker/Devastation/actor.lua
if mint.data.toggles.dispels then
    local types = { ["Poison"] = true, ["Disease"] = true, ["Curse"] = true, ["Bleed"] = true }
    local dispel_target = nil
    local dispel_poison = false

    mint.FriendManager:Loop(function(friend)
        if friend:IsDead() then return false end
        if friend:GetDistance(player) > 30 then return false end
        if not friend:HasDebuffType(types, true) then return false end
        dispel_target = friend
        if friend:HasDebuffType({["Poison"] = true}, true) then
            dispel_poison = true
        end
        return true
    end)

    if dispel_target then
        -- Expunge prioritizes poisons
        if dispel_poison and spells.expunge:IsReady() then
            if spells.expunge(dispel_target) then return end
        end
        -- Cauterizing Flame as fallback omni-dispel
        if spells.cauterizing_flame:IsReady() then
            if spells.cauterizing_flame(dispel_target) then return end
        end
    end
end
```

---

## Stop / Kick System

The Stop system (`Engine/Classes/Utility/Stops.lua`) provides automated interrupt logic that finds the best kick target and interrupts at humanized timing.

### Architecture

```
Constants.ClassKickMap → Stop:New() → per-class kick spell
Constants.ClassStopMap → per-class CC stops (stuns, etc.)
Settings.profile.kicks → per-spell enable/disable (whitelist)
SmartUnit "smart_kick" → ObjectManager loop → best kickable target
Stop:Scan() → fires kick callback
```

### Smart Kick Target Selection

The system creates a `SmartUnit` that continuously evaluates:

```lua
self.kick_target = UnitManager:CreateSmartUnit("smart_kick", function()
    local best_kick = nil
    local lowest_ttc = math.huge

    if not mint.data.toggles.kicks then return UnitManager:Get("none") end

    ObjectManager.combat:loop(function(enemy)
        if enemy.dead then return false end
        if not enemy:IsCastingOrChanneling() then return false end
        if not enemy:IsKickable() then return false end
        if not IsKickEnabled(enemy:GetCastSpellID()) then return false end
        if not self.my_kick:IsInRange(enemy) then return false end
        if not UnitManager:Get("player"):HasLos(enemy) then return false end

        local TTC = enemy:TimeToCast()
        if TTC < lowest_ttc then
            lowest_ttc = TTC
            best_kick = enemy
        end
        return false
    end)

    return best_kick or UnitManager:Get("none")
end)
```

### Humanized Interrupt Timing

The kick callback uses randomized thresholds to avoid mechanical precision:

| State | Threshold | Range |
|-------|-----------|-------|
| **Casting** | Cast percent | Random 40%–80% (re-rolled after each kick) |
| **Channeling** | Time since start | Random 0.85–0.95s (absolute elapsed time, re-rolled after each kick) |

```lua
-- Randomized cast percentage for next kick
local function NewPercent()
    local new = math.random(40, 80)
    if new == cast_percent then return NewPercent() end
    cast_percent = new
    return cast_percent
end
```

### Kick Whitelist

`Settings.profile.kicks` contains a per-spell whitelist. Only enemy casts that are both:
1. Present in the whitelist, AND
2. Enabled by the user

...will be interrupted. This is managed through the Settings UI.

---

## SmartTarget

The SmartTarget system (`Engine/Classes/Utility/Targets.lua`) provides automatic target acquisition when the player has no valid target.

### How It Works

1. A `SmartUnit` named `"SmartTarget"` continuously evaluates combat enemies.
2. It picks the **highest absolute health** enemy within range and LoS.
3. When called via `SmartTarget:Acquire(range)`, it snaps the player's target if the current one is invalid.

### Selection Logic

```lua
local SmartTargetUnit = UnitManager:CreateSmartUnit("SmartTarget", function(max_range)
    local best_unit = none
    local highest_hp = 0
    local range = max_range or 40

    ObjectManager.combat:loop(function(enemy)
        enemy:Update()
        if enemy:IsDead() or not enemy:GetExists() then return false end
        if enemy:GetDistance(player) > range then return false end
        if not player:HasLos(enemy) then return false end

        if enemy.health > highest_hp then
            best_unit = enemy
            highest_hp = enemy.health
        end
        return false
    end)

    return best_unit
end)
```

### Acquire Method

```lua
function SmartTarget:Acquire(range)
    -- Respects Settings toggle
    if Settings.profile.general and Settings.profile.general.smart_target == false then return end

    -- Don't swap while casting
    if player:IsCasting() or player:IsChanneling() then return end

    -- Only acquire if current target is invalid
    local targetValid = target:GetExists() and not target:IsDead() and UnitCanAttack("player", target:GetPointer())
    if not targetValid then
        local found = SmartTargetUnit:Get(range)
        if found and found:GetExists() and not found:Is(target) then
            -- Unlocker-aware targeting
            if unlocker.name == "winkr" then
                winkr_SetNPC(found.guid)
                TargetUnit("npc")
            else
                TargetUnit(found:GetPointer())
            end
        end
    end
end
```

### Usage in Rotations

```lua
-- Simple usage (most specs)
if not target.exists or target.is_dead or not target.can_attack then
    SmartTarget:Acquire()
end

-- Range-limited
SmartTarget:Acquire(25)  -- Melee classes might use shorter range
```

> **Note:** For the full manager-level implementation, see `managers.md`. This page covers the utility-layer API that rotations interact with.

---

## Draw System

The core Draw class (`Engine/Classes/Draw.lua`) provides 3D world-space drawing with object pooling. Utility draw helpers (`Engine/Classes/Utility/Draws.lua`) build on top of it for common patterns like facing arrows and unit circles.

### Available Utility Functions

| Method | Description |
|--------|-------------|
| `Utility:DrawFacingArrow(draw, unit)` | Draws a directional arrow beneath a unit showing their facing direction |
| `Utility:DrawCircleByGUID(draw, guid)` | Draws a circle beneath a specific player (by GUID) |

### Draw Colors

Colors are configured through `Settings.profile.general.indicator_color`:

| Color | RGB |
|-------|-----|
| `cyan` | 0, 216, 255 |
| `gold` | 255, 210, 0 |
| `lime` | 0, 255, 18 |
| `white` | 255, 255, 255 |
| `red` | 255, 33, 20 |
| `orange` | 255, 128, 0 |
| `yellow` | 255, 248, 9 |
| `pink` | 255, 128, 255 |
| `purple` | 200, 69, 250 |

Opacity is controlled via `Settings.profile.general.indicator_opacity` (0–100%).

### Usage in APLs

The Draw system is used by creating a `Draw` instance, registering callbacks via `Sync`, then enabling:

```lua
-- From APLs/Utility/visions.lua
local Draw = mint.Draw:New()

Draw:Sync(function(draw)
    draw:SetColor(255, 0, 0, 255)  -- Red (0-255 range)
    draw:Text("Label", mint.Interface.mint_tiny, x, y, z)

    draw:SetColor(0, 255, 0, 255)  -- Green
    draw:Circle(x, y, z, 1)

    draw:SetWidth(2)
    draw:Line(sx, sy, sz, ex, ey, ez)
end)

Draw:Enable()
```

### Draw API

| Method | Description |
|--------|-------------|
| `Draw:New()` | Create a new Draw instance with its own canvas and object pools |
| `Draw:Sync(callback)` | Register a draw callback; receives the draw instance as argument |
| `Draw:Enable()` | Start rendering (runs `OnUpdate` each frame) |
| `Draw:Disable()` | Stop rendering and clear the canvas |
| `draw:SetColor(r, g, b, a)` | Set color for subsequent draw calls (0–255). Also accepts a table `{r,g,b[,a]}` as first arg with optional alpha override as second arg |
| `draw:SetWidth(w)` | Set line width in pixels |
| `draw:Line(x1, y1, z1, x2, y2, z2, maxD)` | Draw a 3D line. `maxD` (default 50) controls recursive subdivision distance for long lines |
| `draw:Line2D(sx, sy, ex, ey)` | Draw a 2D screen-space line |
| `draw:Circle(x, y, z, radius, steps)` | Draw a 3D circle. `steps` (default 40) controls segment count |
| `draw:Text(text, font, x, y, z)` | Draw 3D text at a world position |
| `draw:Arc(x, y, z, size, arc, rotation)` | Draw an arc (delegates to `Sector`) |
| `draw:Sector(x, y, z, rotation, radius, fov, precision)` | Draw a sector/cone shape. `fov` in degrees, `precision` default 120 |
| `draw:Array(vectors, x, y, z, rotation)` | Draw a vector shape from an array of `{sx,sy,sz,ex,ey,ez}` offsets |
| `draw:Texture(config, x, y, z, alphaOverride)` | Draw a texture at a world position. Config: `{texture, width, height, left?, right?, top?, bottom?, scale?, alpha?}` |
| `draw:WorldToScreen(wx, wy, wz)` | Convert world coordinates to screen pixel offsets |
| `draw:Distance(ax, ay, az, bx, by, bz)` | 3D distance between two points |
| `draw:ClearCanvas()` | Hide and recycle all drawn objects |

---

## Notification System

The Notification system (`Engine/Classes/Notification.lua`, `Engine/Classes/NotificationManager.lua`) displays timed on-screen notifications with icon and text.

### NotificationManager

| Method | Description |
|--------|-------------|
| `NotificationManager:New()` | Create the notification container frame (anchored at `TOP, 0, -300`). Starts a 0.1s ticker to auto-remove expired notifications |
| `NotificationManager:AddNotification(icon, text, duration, spam)` | Show a notification. `duration` defaults to 2s. If `spam` is falsy, duplicate icon+text combos are suppressed |
| `NotificationManager:RemoveNotification(notification)` | Remove a specific notification |
| `NotificationManager:RemoveAllNotifications()` | Remove all active notifications |
| `NotificationManager:Update()` | Reposition notifications vertically (42px spacing) |

### Notification

| Method | Description |
|--------|-------------|
| `Notification:New(list, icon, text, duration)` | Create a single notification frame with icon (40×40, circular mask) and text (24pt outline font). Default duration 2s |
| `Notification:Remove()` | Fade out (0.2s) then destroy the frame |

---

## Queue / Flight Tracking

The Queue system (`Engine/Classes/Queue/Queue.lua`) tracks timed events, primarily projectile flight times for spells.

### Built-in Projectile Data

| Spell ID | Velocity |
|----------|----------|
| 44425 (Arcane Barrage) | 24 |
| 133 (Fireball) | 40 |
| 257541 (Phoenix Flames) | 50 |
| 11366 (Pyroblast) | 35 |

### API

| Method | Description |
|--------|-------------|
| `Queue:New()` | Create a new event queue |
| `Queue:AddEvent(key, start, time, type, target)` | Add a timed event. For `PROJECTILE_IMPACT` type, `time` is auto-calculated from distance/velocity if not provided. Events are sorted by time |
| `Queue:RemoveEvent(key, type, reverse)` | Remove the first (or last if `reverse`) matching event. Returns `true` if found |
| `Queue:IsInFlight(spell_id)` | Returns `true` if a `PROJECTILE_IMPACT` event exists for this spell that has already started |
| `Queue:FlightRemains(spell_id)` | Returns remaining flight time in seconds (0 if none) |

---

## Keybind System

The Keybind system (`Engine/Classes/Keybinds.lua`) provides configurable spell keybinds with modifier support and cast targeting.

### Tick Loop

`Keybinds:Tick()` runs each frame and:
1. Skips if the player is mounted, the engine is off, or chat is focused.
2. For each enabled keybind, checks if the key combo is held.
3. Calls `HandleCast(data)` which casts the spell at the configured target.
4. Returns `not spell:IsOnCD()` to signal whether the rotation should yield.

### Supported Targets

| Target | Behavior |
|--------|----------|
| `"Self"` | `CastSpellByID(spellId, "player")` |
| `"Target"` | Cast on current target (if exists) |
| `"Mouseover"` | Cast on mouseover unit (if exists) |
| `"Focus"` | Cast on focus unit (if exists) |
| `"Cursor"` | `CastSpellByID(spellId, "cursor")` |

### Key Combinations

Keybinds support `SHIFT-`, `CTRL-`, `ALT-`, and `META-` modifiers (e.g., `"SHIFT-M"`). Bare keys must be a single character or match `F1`–`F12` / `M1`–`M9`.

### Rebinding UI

`Keybinds:StartListening(table, cell, row, rowIndex)` puts the UI into listen mode. The next key press is captured via `OnKeyDown` → `ProcessInput`, which builds a chord string via `CreateKeyChordStringUsingMetaKeyState`. Pressing `ESCAPE` unbinds the key.

---

## Slash Commands

The Command class (`Engine/Classes/Command.lua`) registers WoW slash commands.

### API

| Method | Description |
|--------|-------------|
| `Command:New(prefix)` | Register `/prefix` as a slash command |
| `Command:Register(command, helpmsg, cb)` | Add a subcommand with help text and callback `cb(args)` |
| `Command:Parse(msg)` | Split input into a whitespace-delimited args table |
| `Command:OnCommand(msg)` | Dispatch: parse args, run matching subcommand or print help |
| `Command:PrintHelp()` | Print all registered subcommands and their help text |

---

## Constants

The Constants system (`Engine/Constants/Constants.lua`) provides shared data tables used across the entire framework.

### UI Stylesheet

`Constants.Stylesheet` defines the visual theme for all MINT UI elements:
- Font family, sizes, colors
- Backdrop textures and colors (panels, sliders, buttons, dropdowns)
- Class-colored accent (slider drag handle matches player class)
- Highlight, tooltip, dialog, progress bar styles

### Class & Spec Maps

| Constant | Description |
|----------|-------------|
| `Constants.ClassIconMap` | Class name → WoW icon texture string |
| `Constants.SpecIconMap` | Spec ID → icon texture name |
| `Constants.SpecNameByID` | Spec ID → display name (e.g., `[250] = "Blood"`) |
| `Constants.ClassNameByID` | Class ID → display name |
| `Constants.SpecIDByClassSpec` | Class name + spec index → spec ID |

### Quickbar Icons

`Constants.QuickbarIconsByClass` maps class IDs to their quickbar button icons:

```lua
-- [classID] = { Cooldowns, Kick, Defensives, Dispel, Purge }
[6] = {  -- Death Knight
    "Ability_maldraxxus_deathknight",        -- Cooldowns
    "Spell_deathknight_mindfreeze",          -- Kick
    "Spell_deathknight_iceboundfortitude",   -- Defensives
    false,                                    -- No Dispel
    false,                                    -- No Purge
},
```

### Kick & Dispel Lists

| Constant | Description |
|----------|-------------|
| `Constants.ClassDispelMap` | Class → Spec ID → array of dispel Spell objects |
| `Constants.ClassKickMap` | Class → Spec ID → primary kick Spell |
| `Constants.ClassStopMap` | Class → Spec ID → array of stop entries `{type, cost, spell}` |
| `Constants.DispelList` | `List` of known debuffs/buffs with conditions (bleed, magic, enrage, poison, curse, disease) |

### Dungeon Data

| Constant | Description |
|----------|-------------|
| `Constants.DungeonKeyToIcon` | Dungeon key → icon texture string |
| `Constants.DungeonKeyToName` | Dungeon key → display name |
| `Constants.TWWS2.debuff_map` | Spell ID → debuff metadata (class, name, dungeon, condition) |
| `Constants.TWWS2.kicks` | Kick whitelist for current season |
| `Constants.TWWS2.spellsteal_ids` | Spellsteal-able buff IDs |
| `Constants.TWWS2.spellsteal_spells` | `List` of spellsteal Spell objects |
| `Constants.TWWS2.buff_map` | Purgeable buff data |

### CC & Ignore Lists

`Constants.IgnoreSpells` defines spell IDs that should be ignored by the kick system (crowd control that shouldn't be broken):

- Mind Soothe (Priest)
- All Polymorph variants (Sheep, Cat, Snake, Rabbit, Turkey, Turtle, Pig, Bee, Monkey, Direhorn, Penguin, Polar Bear, Porcupine, Peacock, Duck)
- Paralysis (Monk)
- Imprison (Demon Hunter)
- All Hex variants (Shaman)

### Movement Spells

`Constants.move_spells` lists spells that allow casting while moving:

```lua
Constants.move_spells = mint.List:New({
    mint.Spell.New(79206),   -- Spiritwalker's Grace
    mint.Spell.New(358267),  -- Hover
})
```

### Action Bar Mappings

| Constant | Description |
|----------|-------------|
| `Constants.ActionBarButtonNames` | All action bar button frame names |
| `Constants.MapActionBarToBinding` | Button frame name → keybind action name |
| `Constants.KeybindTargetDescriptions` | Target type → description text |

### Column Definitions

`Engine/Constants/Columns.lua` defines table column layouts for the UI whitelist tables:

```lua
Constants.WhitelistCols = {
    { name = 'Icon',    width = 40,  format = 'icon',         sortable = false },
    { name = 'Spell',   width = 170, format = 'string',       color = function(...) end },
    { name = 'Enabled', width = 60,  format = 'bindCheckbox', sortable = false },
}
```

---

## Visions

`APLs/Utility/visions.lua` is a specialized utility module that provides automation and visual overlays for **Horrific Visions** content (instance IDs 2827 and 2828).

### Features

- **Conditional Actor**: Only active inside Horrific Vision instances.
- **Object Scanner**: Scans world objects every 3 seconds to identify potions, caches, and interactables.
- **Bad Potion Detection**: Identifies the "bad" potion based on proximity to known positions, then derives the "good" potion via a rotation map.
- **3D World Overlays**: Draws color-coded labels on all vision objects:
  - 🔴 Red = bad potion
  - 🟢 Green = good potion
  - ⚪ White = neutral/other objects

### Object Categories

| Category | Objects |
|----------|---------|
| **Potions** | Blue (341338), Red (341341), Green (341339), Black (341337), Purple (341340) |
| **Interactables** | Void-Touched Skull (343698) |
| **Treasure** | Black Empire Cache (500098–500101, 500103–500104) |
| **Stormwind** | Searchable Mailboxes, Trash, Horseshoes, Bomb Location, Torment Cells, Summon Hogger, Cathedral Portal, Auction House Crate |

### Potion Rotation Map

The bad potion position is known per instance. Once identified, the good potion is derived:

```lua
local potion_map = {
    [341341] = 341338, -- Red → Blue
    [341337] = 341339, -- Black → Green
    [341338] = 341340, -- Blue → Purple
    [341339] = 341341, -- Green → Red
    [341340] = 341337, -- Purple → Black
}
```

### Event Handling

- `PLAYER_MAP_CHANGED` resets potion detection state when moving between vision areas.

### Implementation Pattern

The Visions module demonstrates a complete utility APL:

1. **Conditional Actor** with instance-based activation
2. **Periodic scan** (3s tick) for world objects
3. **Draw overlay** synced to render every frame
4. **Event-driven state reset**

This pattern can be adapted for any content-specific automation module.
