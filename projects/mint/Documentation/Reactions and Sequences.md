# Reactions & Sequences

> Reactions handle pre-emptive defensive responses to boss/dungeon mechanics. Sequences handle multi-step burst combos that must execute in strict order. Both systems extend the core APL rotation.

---

## Table of Contents

1. [Reaction System](#reaction-system)
2. [Defining Reactions](#defining-reactions)
3. [Reaction Sync & Execution](#reaction-sync--execution)
4. [Existing Reaction Examples](#existing-reaction-examples)
5. [Sequence System](#sequence-system)
6. [Defining Sequences](#defining-sequences)
7. [Sequence Execution Flow](#sequence-execution-flow)
8. [Reactions vs Sequences vs Actor:Sync](#reactions-vs-sequences-vs-actorsync)

---

## Reaction System

Reactions are **pre-emptive defensive/utility responses** to specific enemy spell casts. Unlike the main APL rotation (which fires every tick), reactions are event-aware: they watch for incoming boss/dungeon abilities via `RaidEvents` and fire protective spells *before* the damage lands.

### Core Concepts

| Concept | Description |
|---------|-------------|
| **Trigger Spell** | The enemy ability being watched for (e.g., Thunderclap) |
| **React Spell** | The defensive/utility to cast in response (e.g., Blessing of Freedom) |
| **Time Window** | How many seconds before the trigger hits to begin casting the reaction |
| **Unit Callback** | A function that returns the best friendly target for the react spell |
| **History Tracking** | Prevents double-casting via `UNIT_SPELLCAST_SUCCEEDED` event tracking |

### Architecture

The Reaction class (`Engine/Classes/Reaction.lua`) is instantiated as a singleton: `mint.Reactions`. It:

1. Listens to `UNIT_SPELLCAST_SUCCEEDED` to track player cast history.
2. Maintains a keyed table of registered reactions.
3. Each reaction has its own enable/disable toggle in the Settings UI.
4. `Reaction:Sync()` is called by the engine, iterating all enabled reactions at a 250ms tick rate.

---

## Defining Reactions

Reactions are defined in `reactions.lua` files inside spec folders. The primary method is:

```lua
Reaction:PreCast(class, dungeon, trigger_spell, react_spell, time, unit_cb, description)
```

### Parameters

| Parameter | Type | Description |
|-----------|------|-------------|
| `class` | `string` | Class name for filtering (e.g., `"paladin"`) |
| `dungeon` | `string` | Dungeon key for context (e.g., `"priory"`) |
| `trigger_spell` | `Spell` | The enemy spell to watch for |
| `react_spell` | `Spell` | The defensive spell to cast in response |
| `time` | `number` | Seconds before trigger lands to start reacting |
| `unit_cb` | `function` | Returns the best friendly unit to protect |
| `description` | `string` | Human-readable description for the UI |

### Real Example: Holy Paladin Reactions (`APLs/Paladin/Holy/reactions.lua`)

```lua
local unlocker, mint, addon = ...

local RaidEvents    = mint.RaidEvents
local Reaction      = mint.Reactions
local UnitManager   = mint.UnitManager
local FriendManager = mint.FriendManager
local Spell         = mint.Spell.New

local spells  = addon.paladin.data["Holy"].spells

-- Define the trigger spell (enemy ability)
local thunderclap = Spell(448492)

-- React to Thunderclap with Blessing of Freedom
Reaction:PreCast("paladin", "priory", thunderclap, spells.blessing_of_freedom, 2, function(unit)
    -- Find the lowest-HP non-tank ally
    local best_unit = FriendManager:GetLowest(false, function(friend)
        if friend.role == "TANK" then
            return false
        end
        return true
    end)
    return best_unit
end, "Casts Blessing of Freedom on an ally to make them immune to Thunderclap damage.")

-- React to Thunderclap with Blessing of Sacrifice
Reaction:PreCast("paladin", "priory", thunderclap, spells.blessing_of_sacrifice, 2, function(unit)
    local best_unit = FriendManager:GetLowest(60, function(friend)
        if friend.role == "TANK" then
            return false
        end
        return true
    end)
    return best_unit
end, "Casts Blessing of Sacrifice on an ally under 60% HP to help them survive Thunderclap.")

-- React to Sacred Toll with Blessing of Sacrifice
local sacred_toll = Spell(448791)
Reaction:PreCast("paladin", "priory", sacred_toll, spells.blessing_of_sacrifice, 1.5, function(unit)
    local best_unit = FriendManager:GetLowest(60, function(friend)
        if friend.role == "TANK" then
            return false
        end
        return true
    end)
    return best_unit
end, "Casts Blessing of Sacrifice on an ally under 60% HP to help them survive Sacred Toll.")
```

### Key Design Patterns

- **Trigger spells** are created as local `Spell` objects with the enemy spell ID.
- **Unit callbacks** use `FriendManager:GetLowest()` to find the best target, often filtering by role.
- **Time windows** are typically 1.5–2 seconds — enough for the reaction to land before the mechanic hits.
- **Multiple reactions** can share the same trigger spell with different react spells.

---

## Reaction Sync & Execution

### Internal Flow

```lua
-- From Engine/Classes/Reaction.lua
function Reaction:Sync()
    for i = 1, #self.reactions do
        local obj = self.reactions[i]
        local key = obj.trigger_spell.id .. "-" .. obj.react_spell.id
        local enabled = settings.profile.reactions[key].enabled
        
        if enabled and GetTime() - obj.last_tick > 0.25 then
            obj.func()
            obj.last_tick = GetTime()
        end
    end
end
```

Each reaction's internal function:

1. Calls the `unit_cb` to get the target unit.
2. Queries `RaidEvents:TimeToSpell(trigger_spell.id)` to see how soon the trigger will hit.
3. If within the time window, checks cast history to avoid double-casting.
4. Casts the react spell on the target unit.

### Enable/Disable

Every reaction generates a unique key (`trigger_id-react_id`) and creates a default entry with `enabled = false`. Users toggle reactions on/off through the Settings UI (Reactions page). The UI displays:

- Trigger spell icon + name
- React spell icon + name
- Description text
- Enable/disable checkbox

### Cast History

The system tracks player casts via `UNIT_SPELLCAST_SUCCEEDED`:

```lua
self.events:RegisterWoWEvent("UNIT_SPELLCAST_SUCCEEDED", function(...)
    local args = { ... }
    local source = args[1]
    local spell_id = args[3]
    if source == "player" then
        self.history[spell_id] = GetTime()
    end
end)
```

This prevents re-casting the same react spell within 5 seconds, and checks `C_Spell.IsCurrentSpell()` to avoid interrupting an already-casting reaction.

### Other Reaction Types

The Reaction class defines stubs for additional patterns:

| Method | Status | Purpose |
|--------|--------|---------|
| `Reaction:PreCast(class, dungeon, trigger_spell, react_spell, time, unit_cb, description)` | ✅ Implemented | Cast react spell *before* trigger lands |
| `Reaction:OnCast(class, trigger_spell, react_spell, unit_cb)` | 🚧 Stub | Cast react spell *at the moment* trigger fires |
| `Reaction:PostCast(class, trigger_spell, react_spell, time, unit_cb)` | 🚧 Stub | Cast react spell *after* trigger completes |

> **Note:** `OnCast` and `PostCast` have different parameter lists than `PreCast` — neither accepts `dungeon` or `description`.

---

## Existing Reaction Examples

### Reaction Files in the Codebase

| File | Contents |
|------|----------|
| `APLs/Paladin/Holy/reactions.lua` | Thunderclap → BoF, BoSac; Sacred Toll → BoSac |
| `APLs/Paladin/Protection/reactions.lua` | Same reactions (commented out — handled in actor instead) |
| `APLs/Hunter/BeastMastery/reactions.lua` | Empty (placeholder) |

### Best Practices for Reactions

- Define trigger spells as local `Spell` objects using the **enemy** spell ID.
- Use `FriendManager:GetLowest()` with role filters to intelligently target.
- Set time windows based on the react spell's cast time + a small buffer.
- Keep reaction logic simple — complex conditions belong in the actor.

---

## Sequence System

Sequences (`Engine/Classes/Sequencer.lua`) handle **multi-step burst combos** — ordered chains of actions that must execute in strict succession. Unlike the APL's priority-based flow where any spell can fire, a sequence advances step-by-step.

### Core Concepts

| Concept | Description |
|---------|-------------|
| **Actions** | Ordered table of `{ name, func }` pairs |
| **Index** | Current step in the sequence (starts at 1) |
| **Running** | Whether the sequence is actively executing |
| **Reset Condition** | Function that returns `true` to restart from step 1 |
| **Abort Condition** | Function that returns `true` to cancel the sequence entirely |
| **Cast History** | Tracks player casts via events for step advancement |

### API

| Method | Returns | Description |
|--------|---------|-------------|
| `Sequence:New(name, actions, resetCondition, abortCondition)` | `Sequence` | Create a new sequence |
| `Sequence:Execute()` | `boolean` | Run the current step; advance on success |
| `Sequence:IsRunning()` | `boolean` | Is the sequence actively executing? |
| `Sequence:IsFinished()` | `boolean` | Have all steps completed? |
| `Sequence:Reset(aborted)` | `nil` | Reset to step 1. Optional `aborted` flag controls the log message. |
| `Sequence:Abort()` | `nil` | Cancel and reset the sequence |
| `Sequence:ShouldReset()` | `boolean` | Check the reset condition |
| `Sequence:ShouldAbort()` | `boolean` | Check the abort condition |

---

## Defining Sequences

```lua
local Sequence = mint.Sequence

local burst_sequence = Sequence:New(
    "Devastation Burst",       -- Name
    {                          -- Actions (ordered)
        {
            name = "Pop Dragonrage",
            func = function(seq)
                if spells.dragonrage:IsReady() then
                    return spells.dragonrage:Cast(player)
                end
                return false
            end
        },
        {
            name = "Fire Breath Rank 4",
            func = function(seq)
                if spells.fire_breath:IsReady() then
                    return spells.fire_breath(target, 4)
                end
                return false
            end
        },
        {
            name = "Eternity Surge",
            func = function(seq)
                if spells.eternity_surge:IsReady() then
                    return spells.eternity_surge(target, 3)
                end
                return false
            end
        },
    },
    function(seq) -- Reset condition
        return false  -- Never auto-reset
    end,
    function(seq) -- Abort condition
        return not player.in_combat  -- Abort if combat ends
    end
)
```

### Action Function Contract

Each action's `func` receives the `Sequence` object (`self`) and must:
- Return `true` if the step completed successfully (advances to next step)
- Return `false` if the step failed (will retry next tick)

---

## Sequence Execution Flow

```
Tick 1: Execute() → Step 1 func → returns true → index = 2
Tick 2: Execute() → Step 2 func → returns false → stays at 2 (retry)
Tick 3: Execute() → Step 2 func → returns true → index = 3
Tick 4: Execute() → Step 3 func → returns true → index = 4
Tick 5: Execute() → IsFinished() → Reset() → running = false
```

### Integration with Actor:Sync

Sequences are called from within the Actor rotation, typically taking priority over normal rotation when active:

```lua
actor:Sync(function()
    -- ... guards ...

    -- If burst sequence is running, let it drive the rotation
    if burst_sequence:IsRunning() then
        burst_sequence:Execute()
        return
    end

    -- Trigger burst on conditions
    if should_burst() then
        burst_sequence:Execute()  -- Starts the sequence
        return
    end

    -- Normal rotation below...
end)
```

### Event Tracking

Like Reactions, Sequences track player casts via `UNIT_SPELLCAST_SUCCEEDED`:

```lua
self.events:RegisterWoWEvent("UNIT_SPELLCAST_SUCCEEDED", function(...)
    local args = { ... }
    local source_guid = args[1]
    local spell_id = args[3]
    if source_guid == "player" then
        self.cast_history[spell_id] = GetTime()
    end
end)
```

This allows action functions to verify that a spell actually landed before advancing.

### Logging

The Sequence system logs execution progress:
- `"Action: <name> executed successfully"` — step advanced
- `"Action: <name> failed execution, repeating."` — step retrying
- `"[Sequence] <name> has finished."` — all steps complete
- `"[Sequence] <name> has been reset."` / `"...reset via Abort()."` — reset/abort

---

## Reactions vs Sequences vs Actor:Sync

| Feature | Actor:Sync (APL) | Reactions | Sequences |
|---------|-------------------|-----------|-----------|
| **Purpose** | Main rotation | Pre-emptive defense | Ordered burst combos |
| **Execution** | Every tick | Every 250ms (enabled only) | Every tick (when running) |
| **Priority** | Top-down, highest first | Independent of rotation | Takes over rotation |
| **Triggered by** | Engine tick | `RaidEvents` time-to-spell | Manual or conditional start |
| **Ordering** | Flexible (any spell can fire) | Single trigger→react pair | Strict sequential |
| **User control** | Engine toggle | Per-reaction enable/disable | Start/abort conditions |
| **File location** | `actor.lua` | `reactions.lua` | Typically `actor.lua` |
| **State tracking** | Stateless per tick | Cast history (5s window) | Cast history + step index |
