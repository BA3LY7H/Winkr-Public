# RXP-driven questing — plan (revised: follow the addon, don't re-parse it)

Goal: awfulbot follows the **RestedXP guide you already have loaded**, executing whatever
step you're currently on. Zygor out of scope. No guide content copied into the repo.

**Revision note.** The first draft proposed parser → IR → adapter. That was wrong — it
rebuilt work the addon already does. Checking the addon's runtime state first (per
[[check-dev-corpus-before-building]]) removed roughly two thirds of the design.

---

## 1. The key finding: RXP is already a parsed, live, per-character step machine

`RXPGuides.lua:2350` does `RXP = addon` — the entire addon table is a **global**.
`RXPCData` is a per-character SavedVariable. So from our code:

```lua
local guide = RXP.currentGuide                       -- loaded guide
local idx   = RXPCData.currentStep                   -- where the user is
local step  = guide.steps[idx]                       -- current step
for _, e in ipairs(step.elements) do ... end         -- ALREADY PARSED elements
```

(`Communications.lua:501` does exactly this internally.)

What RXP has **already done** for us, verified in `functions.lua` / `GuideLoader.lua`:

| Work | Where | Result |
|---|---|---|
| Tokenise `.directive args` | `GuideLoader.lua:845` | `element.tag` + typed fields |
| Zone **name** → map id | `addon.GetMapInfo` | `element.zone` (numeric map id) |
| Zone % → **world coords** | HereBeDragons `GetWorldCoordinatesFromZone` | **`element.wx`, `element.wy`, `element.instance`** |
| `<<` conditionals vs **this character** | `applies()` `GuideLoader.lua:31` | non-applicable lines already removed |
| `>>` display text | `GuideLoader.lua:840` | `element.text` |
| Quest ids | e.g. `functions.accept` | `element.questId` |
| Step advance as quests complete | RXP's own tracker | `RXPCData.currentStep` moves on its own |

So **we need no parser, no directive coverage table, no step IR, and no resumability logic** —
RXP persists `currentStep` per character across reload and death, and advances it from quest
log state itself. The earlier `.goto`-count/coverage analysis is obsolete; what matters now
is only *which tags we act on*.

This also fully settles the redistribution constraint: we never read guide files, only live
in-memory tables.

---

## 2. Architecture

```
Bot/guides/rxp.lua      read-only view of RXP state -> a tiny normalized "intent"
Bot/guides/runner.lua   act on the current intent; hand combat to the routine
Bot/guides/hud.lua      debug overlay: step, intent, target coord, distance, block reason
```

Three files. `rxp.lua` is the only RXP-aware one, so a second guide source later is a new
file, not a rewrite — the original format-agnostic goal, met far more cheaply.

**Intent** (replaces the IR — deliberately thin, built per frame, never persisted):

```lua
{ kind = "travel"|"accept"|"turnin"|"kill"|"collect"|"interact"|"use"|"vendor"|"trainer"|"hearth"|"idle",
  wx, wy, instance, radius,   -- from element.wx/wy/instance/radius, already world-space
  questId, itemId, count, names, entryId,
  text,                       -- element.text, for the HUD
  blocked }                   -- why we can't act, for the HUD
```

**Tags we act on** (everything else is cosmetic or RXP-internal — ignore, never hard-fail):
`goto` → travel · `accept`/`turnin` → quest verbs · `complete` → the objective to work ·
`mob`/`target` → kill/target (semicolon-separated names, `addon.separators`) ·
`collect`/`use` → item verbs · `fp`/`hs`/`vendor`/`trainer`/`train` → service stops.

Hard-fail list from the previous draft is dropped: `.deathskip`, `.zoneskip`, `.loop` etc. are
RXP's own control flow and it applies them when moving `currentStep`. We just follow.

---

## 3. What we reuse (nothing reinvented)

| Need | Use | Where |
|---|---|---|
| Step execution / auto-advance | **RXP's `currentStep`** | the addon |
| Pathing to `wx,wy` | `awful.path` / `bot.Mesh` + `bot.astar` | `util/nav.lua`, `Bot/nav/*` |
| Movement, smooth turn, stuck, LoS | `Atlas:*` | `util/atlas.lua` |
| Path following | `bot.Pather` | `Bot/nav/pather.lua` |
| Quest log truth | `bot:IsCurrentQuest/ReadyForTurnin/IsQuestComplete` | `Bot/profile/step.lua:248` |
| Interact / approach | `bot.Interaction`, `actions/questing.lua` | `Bot/*` |
| Object lookup by entry | OM, entry id from **GUID field 6** | [[dinkr-objid-is-not-entry-id]] |
| Drawing | `draw:*`, `awful.SmoothLine` | `module/draw.lua`, `util/smoothline.lua` |

**Reference implementation — `C:\Users\<user>\Downloads\agent_quest.lua` (2142 lines).** Not
RXP-based, but solves several of the same problems and is worth porting from rather than
re-deriving:

- `_best_reward_index()` / `_item_score(link)` — **quest reward selection** (this answers the
  open question from the previous draft; adopt its scoring rather than inventing one)
- `_quest_finisher_entry(qid)` / `_resolve_turnin_nav(qid)` — turn-in NPC resolution
- `_poi_world(qid)` — quest POI → world coords (fallback when a step has no `.goto`)
- `_approach(entry, dist)` / `_interact(rec, intent)` — approach-and-interact
- `_find_entry` / `_find_name` / `_find_service` — OM lookups
- `_gaz_learn_npc` — NPC gazetteer, learns locations as it sees them
- `_quest_log_full`, `_gear_upgrade_check`, phase machine (`_setphase`)
- Companions: `agent_move.lua` (1163) — obstacle handling worth folding into our walker;
  `agent_path.lua` (156), `agent_questbot_hud.lua` (212) — HUD layout reference

**Combat boundary (unchanged, explicit):** awfulbot picks *what to fight and where to stand*
and hands off; the Awful routine decides *how to fight*. awfulbot never casts, the routine
never reads guide state.

---

## 4. Build order

1. `rxp.lua` — read-only. `/rxp status` prints guide name, step index, step text, and the
   decoded intent. **Zero movement.** Proves we're reading the right step before anything acts.
2. `hud.lua` — draw the intent: target coord, distance, current/next step, block reason.
3. `runner.lua` — travel only. `goto` → path to `wx,wy`. Stop there and evaluate.
4. Quest verbs: accept / turnin (with `agent_quest`'s reward scoring) / complete.
5. Kill / collect / interact / service stops.

Steps 1-2 are inert and safe to land immediately. Step 3 is the first one that moves the
character.

---

## 5. Open questions

1. `.dungeon` (3690 uses) — skip these steps outright, or stop and hand back to you?
2. When RXP's `currentStep` disagrees with the quest log (user manually did something) —
   trust RXP, or force-resync? Leaning trust RXP, since it owns advancement.
3. Home: inside `the bot project`, or a sibling project that depends on it?
