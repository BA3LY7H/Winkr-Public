# Patch Day — WINKR Classic update procedure

Run this whole file after every WoW Classic build bump. It took ~15 minutes on
68940 → 69109 once the tooling existed.

**Symptom that starts it:** `winkr.exe` logs
`BUILD MISMATCH: expected <old>, got <new>` and refuses to attach.

---

## The one thing that trips everyone up

**The on-disk `WowClassic.exe` is ENCRYPTED.** You cannot analyse it offline.

Proof (re-run any time with the entropy check in step 2): sampling `.text` in the
on-disk PE gives **entropy 7.96 with zero x64 prologues**; the same RVAs in a
runtime dump give **5.7–6.7 with hundreds**. An offline flat-map therefore scores
**0 signatures**, which looks like "everything moved" but actually means "you are
reading ciphertext."

The client decrypts itself in memory, so **patch day always needs a runtime dump.**
(`tools/flatmap.py` exists for hypothetical unencrypted builds. Don't be fooled
by it producing a plausible-looking 100 MB file — check entropy before trusting it.)

---

## Step 1 — arm safe mode (2 min)

Set `EXPECTED_BUILD` in `Winkr/shared/rva_defs.h` to the new build. **Change nothing
else yet.** Every gate (`RVA_SET_IS_VERIFIED`, `RVA_G_TAINT_IS_VERIFIED`,
`RVA_OM_STRUCT_IS_VERIFIED`) compares against it, so this single edit puts the
DLL in SAFE MODE: no taint writes, no mod execution, no stale-pointer derefs.

```
build.bat            # build.bat is LF; the wrapper below converts to CRLF for cmd
```

Now `winkr.exe` accepts the client (`build <new> verified`) and can attach.

## Step 2 — take a runtime dump (3 min)

1. Launch WoW, log a character **in-world** (not the character screen).
2. Open `winkr.exe`, attach.
3. Click **Dump**. Do **not** Inject first — the dump button is deliberately
   disabled once injected, because it runs as a standalone utility
   (`winkr_dump.dll`, reflective + thread hijack).

Watch for `Finding Eidolon gadget... Copying and decrypting sections...` — that
is the decryption doing its job.

Output lands in `Winkr\build\dump\`:

| File | What it is |
|---|---|
| `dump.bin` | flat image, **file offset == RVA**, decrypted. This is the analysis input. |
| `wow_offsets.txt` | ~15,000 **named** function offsets. Enormous shortcut — check here first. |
| `wowclassic_loader_functions.txt` | loader exports |

Stage them:
```bash
cp Winkr/build/dump/dump.bin        Winkr/build/classic/WowClassic_<build>_full.exe
cp Winkr/build/dump/wow_offsets.txt Winkr/build/classic/classic_<build>_offsets.txt
```

Sanity-check before analysing (catches a bad dump immediately):
```python
d = open("Winkr/build/classic/WowClassic_<build>_full.exe","rb").read()
d[:2] == b"MZ"                      # flat image
d.find(b"<build>")                  # build string present
# entropy at 0x2000000 should be ~6.2 with x64 patterns, NOT ~8.0
```

## Step 3 — scorecard (1 min)

```bash
python tools/patch_day.py Winkr/build/classic/WowClassic_<build>_full.exe
```

Buckets:
- **STALE** — signature matched at a new address. Paste-ready `#define` lines; take them.
- **RIPREL MISMATCH** — self-healing recipe disagrees with the hardcoded RVA.
  Take it **if the vote count is healthy** (43/43 is certain, 1/1 is a guess).
- **BROKEN** — no unique signature. Needs hand-derivation; check `wow_offsets.txt` first.
- **UNVERIFIED** — no signature exists (indirect globals, struct offsets). Step 4.

Region shifts are **not uniform** — on 69109 the Lua region moved +0xB9C50 while
other regions moved +0xA6960 and +0xABA20. **Never extrapolate one delta.**

## Step 4 — derive the no-signature globals (5 min)

```bash
python tools/derive_69109.py Winkr/build/classic/WowClassic_<build>_full.exe \
                             Winkr/build/classic/classic_<build>_offsets.txt
```

Anchored disassembly, each cross-validated:

| Global | Anchor | Cross-check |
|---|---|---|
| `RVA_DUMMYNODE` | `luaH_new` → first `lea rax,[rip+X]` | — (but a wrong value = the empty-table crash) |
| `RVA_G_TAINT_HANDLER_PTR` | `cmp qword [rip+X], 0` in the secret gates | **must equal** the gate inside `MoveForwardStart` |
| `RVA_INPUT_CONTROL` | `lea rcx,[rip+X]` in `MoveForwardStart` | `IsPlayerMoving` reads `base+0x4` |
| `RVA_INPUT_EVENT_TIME` | `mov esi, dword [rip+X]` in `MoveForwardStart` | — |

**Insist on the cross-checks.** g_taint agreeing across the Lua secret gates and
an unrelated movement keybind is what makes it safe to write through — writing
`0` through a wrong g_taint corrupts a live global.

## Step 5 — apply + rebuild (2 min)

Edit `tools/apply_69109.py` (copy it per build), paste the derived values, run it.
It rewrites `Winkr/shared/rva_defs.h` preserving history in the comments.

Then open the two verification gates **only for what you actually derived**:
- `RVA_VERIFIED_BUILD` → new build (exits SAFE MODE, enables mods)
- `RVA_G_TAINT_VERIFIED_BUILD` → new build (enables taint-clear)
- `RVA_OM_STRUCT_VERIFIED_BUILD` → leave `0` unless you re-derived aura/missile offsets

Rebuild. **Watch out:** appending to a `/* */` block that already closed produces
`invalid digit '8' in octal constant` — the comment text became code.

## Step 6 — live confirmation

Inject and read `winkr_dll_debug.txt`:
- `[scorecard]` — live PASS/STALE per signature
- `[selfheal] camera=OK` — camera chain intact
- In-game with a target + `/focus`: `/run winkr_PatchDay()` writes a report
  verifying the struct offsets that have no signature (target/focus GUID,
  camera eye/fov/VP-matrix). Paste any STALE into `Winkr/shared/om_types.h`.

---

## What a patch does NOT break

Don't waste time re-checking these:

- **The navmesh** — 26,071 `.dnm` tiles are baked *geometry*. Azeroth/Kalimdor
  terrain doesn't change on a build bump. Zero action needed.
- **All Lua** — walker, gatherESP, winkrPaladin, the quest bot. Build-independent.
- **Vendored Detour / Lua** — our code, not theirs.

Only compiled-in addresses move.

---

## 69109 result (reference)

12 STALE sigs, 4 RIPREL updates, DUMMYNODE + g_taint + 3 movement globals
re-derived. 21 defines changed. Full values in `Documents/Movement.md` and the
comments in `Winkr/shared/rva_defs.h`. Backup of the previous header kept at
`Winkr/shared/rva_defs.h.68940.bak`.

---

## Step 4b — the two Eidolon validators (THE CRASH CAUSE, do not skip)

`RVA_RETADDR_CHECK` and `RVA_VALIDATE_CFUNC_PTR` are obfuscated anti-tamper
guards with **no usable signature**, so `patch_day.py` always reports them
BROKEN. If they are stale the DLL cannot patch them, and the **first Lua C-API
call it makes (`luaL_loadbuffer` in the setup script) hits a deliberate
NULL-deref and crashes the client.** That is exactly what happened on 69109.

The DLL now **aborts** instead of continuing when either fails to apply
(`[worker] ABORT: a REQUIRED Eidolon validator did not apply`), so a stale RVA
costs you a non-working inject rather than a crash. Look for that line first.

```bash
python tools/derive_validators.py   # retaddr_check, by call-ordinal from known callers
python tools/derive_cfuncptr.py     # both, by body fingerprint near the old address
```

Two independent methods, and they should agree:

- **Call-ordinal** — `retaddr_check` is called from `luaL_loadbuffer` (call #1),
  `lua_pcall` (call #2) and `lua_newstate` (call #0). Find the ordinal that hits
  it in the OLD dump, read the same ordinal in the NEW one. All three voting the
  same address is a strong result.
- **Body fingerprint** — mask out `call`/`jmp` rel32 displacements (they shift),
  then slide the old 48-byte body over a ±0x40000 window around the old address
  and take the best match. Expect 75–85%; anything near 12% is a miss.

**Always confirm the entry byte is `0x48`** (`sub rsp,0x28`) — the DLL's prologue
guard refuses to patch anything else, which is what stops a bad RVA stomping
random code.

69109 result: `RETADDR_CHECK 0x001D0580 -> 0x001D0590` (+0x10, 3 callers agree,
fp 79%), `VALIDATE_CFUNC_PTR 0x0030EB70 -> 0x0030EB50` (-0x20, fp 81%). Note both
moved by tiny amounts while the Lua region moved +0xB9C50 — more proof that
per-region extrapolation is worthless.

`RVA_LUA_SETSECRET` did not fingerprint (12%) and is **not needed** — global
secret patches are disabled by design; the scorecard lists it under
"known-handled".


---

## 69547 — what this build cost, and how to not repeat it

12 STALE sigs, 6 RIPREL updates, 20 defines changed. But the time went almost
entirely into three traps, none of which were the actual RVAs.

### KEEP EVERY DUMP

`Winkr/build/classic/WowClassic_<build>_full.exe` is ~144 MB. **Do not delete it.**

`tools/derive_validators.py` recovers the Eidolon validators by diffing CALL
ORDINALS between the old and new dumps -- the one tool built for functions with
no usable signature. On 69547 only the new dump survived, so it was unusable and
both validators had to be re-derived by hand. The same loss blocked all four
BROKEN sigs.

### `derive_*.py` HARDCODES ITS ANCHORS, AND FAILS SILENTLY

`derive_69109.py` has 69109 addresses baked in. Run unchanged on a new dump it
anchors on stale code and reports plausible nonsense: DUMMYNODE echoed the
previous value, and the g_taint gates scored ZERO votes with no error.

Copy it per build and re-point the anchors from the scorecard first --
`tools/derive_69547.py` shows the four that matter (luaH_new plus the three
secret gates).

### A "STALE" RVA CAN BE A MID-INSTRUCTION ADDRESS

Both required validators aborted mod execution with `prologue guard FAIL`:

    retaddr_check      0x1D0590 -> real entry 0x001D0580  (+0x10 into the body)
    validate_cfunc_ptr 0x30EB50 -> real entry 0x0030EB70  (-0x20, prev epilogue)

The guard only patches when the entry byte is 0x48 (`sub rsp,0x28`), which is
what stopped a stale address stomping garbage. Recovered without the old dump by:

  * retaddr_check -- the ONLY common callee of luaL_loadbuffer and lua_pcall
    whose entry byte is 0x48 (`tools/resig.py` shortens a pattern until it
    matches, then checks each hit is a real entry)
  * validate_cfunc_ptr -- confirmed by disassembly: `mov r8,[rax]` /
    `mov rcx,[rax+8]` / `add rcx,r8` / `cmp rdx,rcx` / `cmp rdx,r8` is the
    [base,base+size) range check, then `xor eax,eax; movzx eax,[rax]` is the
    deliberate NULL deref

### THE SCAN MUST REPORT EVIDENCE, NOT A VERDICT

`CGOBJ_TARGET_LO` burned EIGHT in-game runs because the scan printed
"STALE or no target set" -- one message for three unrelated causes, and the
sweep itself could only see part of the object:

  * range was 0x800..0x2A00; CGActivePlayer_C is 0x8A88, so two thirds of the
    object was never looked at
  * it only searched upward from 0x800
  * the OM cache dump truncated at 24 of 127 entries, which made "not cached"
    look like a finding
  * nothing verified that `pcg` was a player object at all

It now sweeps 0x8..0x8A80, dumps the whole cache, prints raw bytes at the
candidate offsets, checks the object holds its OWN GUID (`SANITY:` line), and
falls through to the GUID globals and a module-data sweep. **Change the scan
before changing a header** -- an offset written on one observation cost a revert.

Result: the target GUID is provably NOT in the player object, NOT in any GUID
global, and NOT in module static data. See Winkr/shared/om_types.h. Use
`UnitGUID("target")` for the player's own target rather than chasing it.

### THE DLL LOG NOW LANDS ON DISK

`DebugLog` mirrors every `[dll]` line to `C:\cmods\dinkr_dll_debug.log`, and
`dinkr_PatchDay()` writes `C:\cmods\dinkr_patchday.txt`. Before this the whole
stream existed only in the GUI window, so diagnosing anything meant a human
copying text out by hand.

### BUILD.BAT IS LF -- USE THE CRLF WRAPPER

Running `build.bat` directly under cmd misparses it and silently falls into the
CLEAN branch, deleting the binaries. Use `build_crlf.bat`.
