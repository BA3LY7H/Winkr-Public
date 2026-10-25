# Movement on WoW Classic Era 1.15.9 (build 68940)

Derived 2026-08-01 from the flat-mapped dump `build/classic/WowClassic_68940_full.exe`
(file offset == RVA). Image base at runtime 0x7FF620E60000.

## The problem

Calling `MoveForwardStart()` / `TurnLeftStart()` etc. from unlocked Lua does **not**
move the character. The navmesh, pathing and follower were all fine — only the final
"move" primitive failed.

## Root cause: one inline taint gate

Every movement keybind handler starts with a single check:

```
MoveForwardStart @ 0x015D8A00                    ; entry (0x015D8A70 is +0x50 inside)
  015D8A1F  cmp qword [rip -> 0x03BDDDB0], 0     ; g_taint_handler_ptr — the ONLY gate
  015D8A2C  je  0x015D8A37                       ; == 0 -> do the real work
  015D8A30  call 0x01AD1FA0                      ; else: blocked-action reporter, bail
  015D8A6A  mov  esi, dword [rip -> 0x03C3CC68]  ; event time
  015D8A70  lea  rcx, [rip -> 0x03A05BA0]        ; CInputControl singleton
  015D8A57  mov  edx, 0x10                       ; forward bit
  015D8A5C  call 0x015E8080                      ; set-bit
  015D8A89  ... call 0x015E78A0                  ; apply-to-player (emits movement)
```

`0x03BDDDB0` is the **same** `RVA_G_TAINT_HANDLER_PTR` this project already defines and
already zeroes for casting / health reads.

Gate confirmed present on: MoveBackwardStart 0x15D9240, StrafeLeftStart 0x15DAAC0,
TurnLeftStart 0x15D9A80, PitchUpStart 0x15DBB40, StartAutoRun 0x15D81B0,
StopAutoRun 0x15D85E0, TurnOrActionStart 0x15DCB80, CameraOrSelectOrMoveStart 0x15DDA40,
MoveAndSteerStart 0x15DE880.
Absent on unprotected APIs (UnitHealth, GetTime, GetSpellInfo, GetBindingKey...).
NOT confirmed on JumpOrAscendStart 0x15D5AE0 / ToggleAutoRun 0x15D7DA0.

## Fix 1 — route through `winkr_Call` (no DLL change)

`winkr_Call(fn, ...)` (dll/bridge/winkr_bridge_misc.c:167) saves, zeroes and restores
g_taint around a pcall. Calling the movement functions through it clears the gate.
This is the same technique the mainstream unlockers use (Tinkr `CallProtectedFunction`,
Daemonic `SecureCode`, Noname `Unlock`).

```lua
local wc = winkr_Call
local function sec(fn, ...) if fn then return wc and wc(fn, ...) or fn(...) end end
sec(MoveForwardStart)
```

Applied in `C:\cmods\awful2\!projects\walker\walker.lua` and `!projects\moveTest\movetest.lua`.

## Fix 2 — native CInputControl (fallback; no taint check in these functions)

```c
/* CInputControl singleton — .data, statically allocated. build 68940.
 * VERIFIED: lea at 0x015D8A70 resolves here; the Lua movement registration table
 * ({const char* name; lua_CFunction fn}, stride 0x10, 55 entries) spans
 * 0x03A057F0..0x03A05B5F and ends immediately before it; ctor 0x001529A0 writes
 * base+0xA8/+0xB4/+0x38/+0x40. */
#define RVA_INPUT_CONTROL          0x03A05BA0  // CInputControl singleton, 69547 (was 0x03A05B60 on 68940/69109)
#define OFF_INPUTCTL_FLAGS         0x04        // live movement-flag dword (abs 0x03A05BA4)
#define OFF_INPUTCTL_GATE          0xA8        // byte, checked by set/clear helpers
#define OFF_INPUTCTL_OVERRIDE      0xB4        // dword
#define OFF_INPUTCTL_MOVE_ENABLED  0xBC        // byte (SetMoveEnabled 0x015E6130)
#define OFF_INPUTCTL_TURN_ENABLED  0xBD        // byte (SetTurnEnabled 0x015E6520)

/* helpers — recon-derived, corroborated by the verified pass, NOT individually re-verified */
#define RVA_INPUTCTL_SET_BIT       0x015E8080  // bool(this, mask, ...) — returns "changed"
#define RVA_INPUTCTL_CLEAR_BIT     0x015E8A90  // (this, mask, srcId, bool, bool)
#define RVA_INPUTCTL_APPLY         0x015E78A0  // (this, eventTime, 1, 1) — pushes to player
#define RVA_INPUT_EVENT_TIME       0x03C3CC68  // dword, read into esi before the call

/* InputControl-LOCAL bits (NOT wire MOVEMENTFLAG values) */
#define INPUTCTL_FORWARD   0x0010   // matches `mov edx,0x10` in MoveForwardStart
#define INPUTCTL_BACKWARD  0x0020
#define INPUTCTL_STRAFE_L  0x0040
#define INPUTCTL_STRAFE_R  0x0080
#define INPUTCTL_TURN_L    0x0100
#define INPUTCTL_TURN_R    0x0200
#define INPUTCTL_PITCH_UP  0x0400
#define INPUTCTL_PITCH_DN  0x0800
#define INPUTCTL_AUTORUN   0x1000
#define INPUTCTL_ASCEND    0x2000
#define INPUTCTL_DESCEND   0x4000
```

Independent proof of the flags field: Lua `IsPlayerMoving` @0x00F886E0 is nothing but
`mov eax, dword [0x03A05BA4]; test eax, 0x1DE010F0 / test al,1 / test eax,0x302`.

Usage sketch (must run on the game thread):

```c
uintptr_t b   = (uintptr_t)g_modLoaderBase;
void*     ctl = (void*)(b + RVA_INPUT_CONTROL);
unsigned  t   = *(volatile unsigned*)(b + RVA_INPUT_EVENT_TIME);
if (((SetBit_t)(b + RVA_INPUTCTL_SET_BIT))(ctl, INPUTCTL_FORWARD, 1, 1))
    ((Apply_t)(b + RVA_INPUTCTL_APPLY))(ctl, t, 1, 1);
```

`RVA_INPUTCTL_APPLY` is what makes the client emit the movement packet — skipping it and
raw-writing the flag dword gets you rubber-banded on the next position sync.

## Other findings

- **ClickToMove does not exist on this build.** "ClickToMove", "clickToMove",
  "CLICK_TO_MOVE", "TerrainClick", "NavMesh", "Detour" are all absent (ASCII and UTF-16).
  A sweep of all 524 CVar registration sites (registrar 0x001D9290) found no CTM or
  pathfinding CVar. Only related facility: CVar `autoInteract` ("Toggles auto-move to
  interact target"). Do not pursue CTM here.
- `CGUnit_C::GetFacing` @0x001F1490 is **not** a plain field read — ECS component-descriptor
  lookup ending in a secret-value wrapper (0x02CD5B50).
- Active-player WOWGUID global 0x040F2008 (16 bytes); checked object getter
  0x0130FA60(WOWGUID*, typeMask, file, line); GameUI chain *(0x03C41C50)+0x4B0
  (+0x98 player GUID, +0xAC bit0 autoInteract).
- **PostMessage works on Classic** (fallback #3, zero RE): WowClassicGrindBot is fully
  external and drives 1.15 with `PostMessage(WM_KEYDOWN/WM_KEYUP)` using layout-translated
  VK codes and hand-built lParam — background-capable, no focus required.

---

# UPDATE: build 69109 (2026-08-08)

Re-derived from the 69109 runtime dump. The structure is unchanged — only
addresses moved. `MoveForwardStart` came straight from the dump's named-offset
table (15,133 entries), and everything else was read out of its disassembly.

| What | 68940 | **69109** | How |
|---|---|---|---|
| MoveForwardStart | 0x015D8A00 | **0x0167F9E0** | dump named-offset table |
| TurnLeftStart | 0x015D9A80 | **0x01680BA0** | dump named-offset table |
| JumpOrAscendStart | 0x015D5AE0 | **0x0167C640** | dump named-offset table |
| IsPlayerMoving | 0x00F886E0 | **0x01008F70** | dump named-offset table |
| **g_taint gate** | 0x03BDDDB0 | **0x03C96C70** | `cmp qword [rip+0x2617269], 0` @0x167F9FF |
| **CInputControl** | 0x03A05BA0 | **0x03ABEB20** | `lea rcx, [rip+0x243f0e9]` @0x167FA30 |
| InputControl flags dword | +0x04 | **+0x04 (0x03ABEB24)** | IsPlayerMoving reads it directly — independent confirmation |
| event-time dword | 0x03C3CC68 | **0x03CF5AF0** | `mov esi, dword [rip+0x26760c0]` @0x167FA2A |
| forward flag bit | 0x10 | **0x10 (unchanged)** | `mov edx, 0x10` @0x167FA37 |

The gate is still a single inline `cmp qword [g_taint], 0` at the top of the
handler, and it resolves to the SAME global the Lua secret gates use — so the
"clear taint, then call Blizzard's own function" approach carries over
unchanged. Movement should keep working with no code edit, only these values.

Set-bit / dispatch helper candidates from the call list at the new
MoveForwardStart: `0x005233E0, 0x01B7B810, 0x016904B0, 0x0184A4E0, 0x0193B750`
(0x01B7B810 is SPELL_STOP_TARGETING per the scorecard, i.e. the blocked-action
reporter, so the real set-bit/dispatch pair are among the others). Re-verify
before using the native path; the taint-cleared Lua path needs none of them.
