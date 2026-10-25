# Engine Core

> Source: `Engine/Core.lua`

The engine core is the heartbeat of MINT. It owns the main tick loop, the CLEU (Combat Log Event Unfiltered) handler, projectile tracking, movement/combat timers, the pause-on-manual-input system, and all `/mint` slash commands.

---

## Table of Contents

- [Main Tick Loop](#main-tick-loop)
- [GCD Gating & Latency Compensation](#gcd-gating--latency-compensation)
- [Frame Budget](#frame-budget)
- [Pause-on-Manual-Input](#pause-on-manual-input)
- [CLEU Handler](#cleu-handler)
- [Projectile Tracking](#projectile-tracking)
- [Toggle Events](#toggle-events)
- [Slash Commands](#slash-commands)
- [Draw Indicators](#draw-indicators)
- [Key Functions](#key-functions)

---

## Main Tick Loop

The engine runs inside a WoW `OnUpdate` frame script on `MintFrame`:

```lua
MintFrame:SetScript("OnUpdate", function(self, elapsed)
    MintTicker = MintTicker + elapsed

    if not mint.data.toggles.engine then return true end
    if MintTicker < 0.05 then return true end    -- 50ms minimum tick
    MintTicker = 0

    FriendManager:Update()
    ObjectManager:Update()
    mint.TimeToDie:Refresh()

    if GetTime() < pauseTimer then return end     -- manual-input pause

    for i = 1, #mint.data.actors do
        local actor = mint.data.actors[i]
        if actor:ShouldRun() then
            actor:Tick()
        end
    end
end)
```

### Tick sequence (each frame that passes the 50ms gate):

| Step | What happens |
|------|-------------|
| 1 | Accumulate `elapsed` into `MintTicker` |
| 2 | Early-out if engine toggle is off |
| 3 | Early-out if < 50ms since last tick |
| 4 | Reset `MintTicker` to 0 |
| 5 | `FriendManager:Update()` — refresh party/raid unit data, sort by realized HP |
| 6 | `ObjectManager:Update()` — iterate winkr objects, rebuild enemies/combat/summons lists |
| 7 | `mint.TimeToDie:Refresh()` — sample HP regression data for TTD estimates |
| 8 | Check pause timer — skip actors if player pressed a manual keybind recently |
| 9 | Iterate `mint.data.actors[]` — call `actor:ShouldRun()` then `actor:Tick()` for each |

Each `Actor:Tick()` iterates its synced callbacks, each with its own sub-rate (default 50ms). Callbacks that fail are caught by `pcall` and logged to the debug console.

---

## GCD Gating & Latency Compensation

GCD gating is handled at the **Spell:PreCheck()** level (in `Spell/Methods.lua`), not in the core loop itself.

```lua
-- Spell:PreCheck() excerpt:
if player:IsCasting() and not can_cast_while_casting then
    local sqw = C_CVar.GetCVar("SpellQueueWindow")
    local _, _, _, latency_world = GetNetStats()
    if mint.gcd > ((latency_world / 1000) + (sqw / 1000)) then
        return false
    end
end
```

- **`mint.gcd`** — remaining GCD time (computed lazily via metatable `__index` on `mint`; reads `C_Spell.GetSpellCooldown(61304)`)
- **`mint.max_gcd`** — haste-adjusted maximum GCD (`1.5 / (1 + haste/100)`, capped at 50% haste; energy classes use base 1.0)
- **`mint.latency`** — home latency in seconds (`select(3, GetNetStats()) / 1000`)

A spell won't queue if the remaining GCD exceeds `latency + SpellQueueWindow`. This means casts are only attempted when the GCD is about to expire, preventing early-queue rejections.

**`Spell:IsOnCD()`** uses a `max_gcd + 0.2` threshold — spells on the GCD alone are considered "ready"; only real cooldowns exceeding this dynamic threshold block.

---

## Frame Budget

- The tick gate of **50ms** (`MintTicker < 0.05`) limits the engine to ~20 ticks/second maximum.
- Each actor callback has its own `tick` rate (default 50ms), providing per-callback throttling.
- `Cache` objects are used throughout (Unit, UnitManager, TimeToDie) to avoid redundant API calls within a tick window.
- `ObjectManager:Update()` clears and rebuilds all lists each tick (simple but bounded by winkr object count).
- `FriendManager:Update()` sorts units by realized HP each tick (bounded by party/raid size ≤40).

---

## Pause-on-Manual-Input

The engine pauses for **350ms** (`PAUSE_SECS = 0.35`) when the player presses an actionbar keybind or a mouse button (BUTTON4/BUTTON5). This prevents the bot from fighting with manual play.

| Component | Purpose |
|-----------|---------|
| `PauseFor(sec)` | Sets `pauseTimer = GetTime() + sec` |
| `InputListener` (OnKeyDown) | Builds key chord, checks if it maps to an action bar binding |
| `ShouldPauseForBinding(chord)` | Returns true for `ACTIONBUTTON*`, `MULTIACTIONBAR*`, `BONUSACTIONBUTTON*`, `EXTRAACTIONBUTTON*`, `PETACTIONBUTTON*` |
| `MousePoll` (OnUpdate) | Polls `BUTTON4`/`BUTTON5` each frame |

The tick loop checks `GetTime() < pauseTimer` after updating managers but before running actors.

---

## CLEU Handler

Registered via `Events:RegisterWoWEvent("COMBAT_LOG_EVENT_UNFILTERED", ...)`.

### Events processed:

| CLEU Sub-Event | Action |
|----------------|--------|
| *(any event)* | Updates `source` and `dest` combat timers via `unit:UpdateCombatTimer(time)`. Skips `Constants.IgnoreSpells`. |
| `SPELL_AURA_REMOVED` | Clears the aura from `unit.auras[]` by both name and spell ID. Handles friendly units via FriendManager scan. |
| `SPELL_CAST_START` | If source is player and spell is flight-tracked: calculates projectile travel time from cast start + distance/velocity, adds `PROJECTILE_IMPACT` event to Queue. |
| `SPELL_CAST_SUCCESS` | Same as above but uses `GetTime()` as start if not already in flight. |
| `SPELL_CAST_FAILED` | Removes the queued projectile event. |
| `SPELL_DAMAGE` | Removes the projectile event (impact occurred). |

### Additional WoW events:

| Event | Handler |
|-------|---------|
| `UNIT_SPELLCAST_DELAYED` | Re-calculates projectile timing if the player's cast was pushed back. |
| `PLAYER_STARTED_MOVING` | Starts `MoveTimer`, resets `StopTimer`. |
| `PLAYER_STOPPED_MOVING` | Starts `StopTimer`, resets `MoveTimer`. |
| `PLAYER_REGEN_DISABLED` | Sets `mint.combatStartTime`. |
| `PLAYER_REGEN_ENABLED` | Clears `mint.combatStartTime`. |
| `UNIT_SPELLCAST_SUCCEEDED` | Records `mint.data.lastCastTimers[spellID]` and appends to `mint.data.lastCastOrder`. |

---

## Projectile Tracking

The `FlightTracked` table maps spell IDs to projectile definitions with `velocity` and optional `impactSpell` fields. Spells registered here get automatic in-flight tracking:

```
FlightTracked[spellID] = { id, velocity, impactSpell? }
```

**Flow:**
1. On `SPELL_CAST_START` or `SPELL_CAST_SUCCESS` — `Queue:AddEvent(spellID, startTime, travelTime, "PROJECTILE_IMPACT", destGUID)`
2. Travel time = `distance / velocity` (+ 50ms buffer)
3. On `SPELL_DAMAGE` or `SPELL_CAST_FAILED` — `Queue:RemoveEvent(...)` cleans up
4. `Queue:IsInFlight(spellID)` and `Queue:FlightRemains(spellID)` are available for rotation logic

---

## Toggle Events

Core.lua registers custom events on the local `Events` bus for each toggle:

| Event Name | Toggle Field | Default |
|------------|-------------|---------|
| `"toggle"` | `mint.data.toggles.engine` | `false` |
| `"cooldowns"` | `mint.data.toggles.cooldowns` | `false` |
| `"kicks"` | `mint.data.toggles.kicks` | `false` |
| `"dispels"` | `mint.data.toggles.dispels` | `false` |
| `"purges"` | `mint.data.toggles.purges` | `false` |
| `"defensives"` | `mint.data.toggles.defensives` | `false` |
| `"optionsToggle"` | *(UI visibility)* | — |
| `"quickbarToggle"` | *(UI visibility)* | — |
| `"consoleToggle"` | *(UI visibility)* | — |
| `"BuildOptions"` | *(triggers interface rebuild)* | — |
| `"BuildQuickbar"` | *(triggers quickbar rebuild)* | — |

---

## Slash Commands

Registered under `/mint` via `Command:New("mint")`:

| Command | Description |
|---------|-------------|
| `/mint options` | Toggle Options panel |
| `/mint qb` | Toggle Quick Bar |
| `/mint console` | Toggle debug console |
| `/mint mdt` | Dump seasonal MDT mob data to file |
| `/mint spells` | Dump all known non-passive spells to file |
| `/mint scan` | List all nearby GameObjects with ID, name, distance |

---

## Draw Indicators

Core.lua creates three `Draw` instances:

| Draw Instance | Purpose |
|---------------|---------|
| `Draw` (main) | Player facing arrow indicator (gated by `settings.profile.general.player_indicator`) |
| `DrawPlayerTracking` | Circles around tracked player GUIDs from settings |
| `DrawGameObjects` | Highlights tracked world objects (herbs, ores, chests) defined in `TRACKED_OBJECTS` table |

---

## Key Functions

| Function | Signature | Purpose |
|----------|-----------|---------|
| `mint.bin(arg)` | `(any) → 0\|1` | Boolean-to-number conversion |
| `mint:CombatLog(...)` | `(...) → nil` | Print timestamped combat log to chat (relative to combat start) |
| `mint.console.log(...)` | `(...) → nil` | Print to debug console + write to `debug.log` file |
| `mint:Log(...)` | `(...) → nil` | Print `[Mint]: ...` to chat |
| `PauseFor(sec)` | `(number?) → nil` | Set pause timer (default 0.35s) |
| `MakeChord(key)` | `(string) → string` | Build modifier chord string like `"SHIFT-CTRL-1"` |
| `ShouldPauseForBinding(chord)` | `(string) → boolean` | Check if a key chord maps to an action bar slot |
