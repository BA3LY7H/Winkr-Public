# tools

Repo-level tooling. Two kinds of thing live here:

- **Repo plumbing** — the scripts that make a checkout runnable and keep the navmesh fresh.
- **Patch-day reverse-engineering helpers** — scripts that re-derive the hand-maintained RVAs in
  [`Winkr/shared/rva_defs.h`](../Winkr/shared/rva_defs.h) after a WoW build bump.

None of it is part of the build: `Winkr/build.bat` / `Winkr/build_dll.sh` compile `Winkr/dll/`
only. **Run everything from the repo root.**

## Repo plumbing

| Tool | What |
|---|---|
| `link.bat` | Junction the repo into place — `projects/` → `C:\projects`, plus each `Addons/<name>` into the WoW `Interface\AddOns`. Safe to re-run. |
| `unlink.bat` | Remove only the junctions `link.bat` made. Real folders are left completely alone. |
| `bake_mmaps.sh` | Rebuild the TrinityCore navmesh tiles (tuned parameters — see the header). Output stages over `projects/mmaps/`. |
| `trinitycore-patches/` | The patched TrinityCore sources used for the bake — see its own README. |

## Patch-day reverse-engineering

Runbook: [`Documents/PatchDay.md`](../Documents/PatchDay.md). The scripts expect a flat dump staged
in `Winkr/build/classic/`. They resolve paths from their own location, so they work from the repo
root.

| Tool | What |
|---|---|
| `flatmap.py` | Produce a **flat-mapped** image of a PE (file offset == RVA). This is the input every other offline tool wants. Encrypted live builds need a runtime dump instead. |
| `patch_day.py` | **Start here.** One-command offline scorecard — reproduces every `winkr_scanner.c` resolution mode and derives the secret-value taint gates. `python tools/patch_day.py`. |
| `secret_gates.py` | Print the 5 secret-value taint-propagation gate RVAs plus the veto check. Referenced from `dll/security/dinkr_security.c`. |
| `derive_69109.py` / `derive_69547.py` | Re-derive the **no-signature globals** by anchored disassembly, one per build. ⚠ Hardcodes its anchor addresses — running it unchanged on a new dump fails silently (see PatchDay.md). |
| `derive_validators.py` | Locate the two Eidolon anti-tamper validators (`retaddr_check`, `validate_cfunc_ptr`) by call-ordinal from known callers. |
| `derive_cfuncptr.py` | Locate `validate_cfunc_ptr` by body fingerprint near the old address. |
| `derive_worldframe.py` / `2` / `3` | Three takes on finding `g_pWorldFrame`, the collision/terrain root — by signature, by access pattern, and a fast targeted pass. |
| `resig.py` | Recover a function whose signature stopped matching — shortens a pattern until it is unique. |
| `apply_69109.py` / `apply_69547.py` | Write the derived values into `Winkr/shared/rva_defs.h`. Copy one per build, paste the values, run it. |

## Standalone

| Tool | What |
|---|---|
| `mmap_inspect.cpp` | The one non-RE tool: links the vendored Detour and mirrors the nav loader byte for byte, so it validates mmap tiles exactly as the DLL loads them. Documented in the [root README](../README.md). |
| `luacheck.c` | Lua syntax checker for the mods, against the vendored 5.1 VM (see the file header for the build line). |

## Notes

- The Python scripts drive IDA / Hex-Rays, and a live process, over local endpoints; they assume
  that tooling is running when invoked.
- `apply_*.py` is deliberately a **copy-per-build** file — you paste the freshly derived values
  in, so keep one per build rather than editing them in place.
