# DINKR — Winkr Classic

WoW **Private Classic Era** unlocker + memory dumper, with a full Detour navmesh stack on top.
Patches the taint/security gates at the machine-code level, exposes a Lua C bridge for mod
execution, and ships world pathfinding — shift+click the map and the character walks there.
https://discord.gg/CEDAxVvGRd
---

> [!CAUTION]
> **DO NOT SHARE THIS PROJECT — WITH ANYONE, EVER.**
>
> - Sharing the source, binaries, or even a **screenshot of the GUI** will not be good for anyone.
> - Even a GUI screenshot can reveal how the tool works — patch names, menu layout, and options give away enough for detection.
> - No exceptions. No "just my one friend." No Discord clips. Nothing.
> - **DO NOT LOAD OTHER UNLOCKERS/FW's WHILE THIS IS DOWNLOADED AND PRESENT ON YOUR COMPUTER**
> - Some providers like WardenGG and other platforms verified through reversal will download source code like this to steal it (not uncommon in paid cheats)
>
> **Don't be that guy.**

---

## Repo Layout

| Folder | What | Goes to |
|--------|------|---------|
| [`Winkr/`](Winkr/) | The unlocker itself — GUI, injected DLL, Detour nav, dump tool | build in place |
| [`projects/`](projects/) | Everything the mod loader reads — junctioned wholesale | `C:\projects` |
| [`projects/mmaps/`](projects/mmaps/) | Navmesh tiles (TrinityCore mmaps), ~2.7 GB | `C:\projects\mmaps` |
| [`Winkr/vendor/recast/`](Winkr/vendor/recast/) | Recast (navmesh generation) — upstream `9f4ce64`, version-matched to the vendored Detour | built into the DLL |
| [`Addons/`](Addons/) | `TacoArt` — texture assets for the in-game UI | `Interface\AddOns\` |
| [`Documents/`](Documents/) | Documentation library — reverse-engineering notes and deep dives | reference only |
| [`tools/`](tools/README.md) | Repo plumbing (`link.bat` / `unlink.bat`, mmap bake) + patch-day reverse-engineering helpers | run in place |

---

## Linking (do this once, instead of copying)

`projects/` and `Addons/` have to live where the loader and the game expect them, not in the repo.
Rather than drag-and-dropping after every pull, **junction** them. A junction is not a copy — it
is the same folder on disk seen from a second path, so editing a file in the repo *is* editing
the live tree, and `git pull` or a branch switch lands instantly.

```bat
link.bat
```

That is the whole thing. It works out the repo path from where the script sits. The WoW path
defaults to `E:\Games\World of Warcraft`; if yours is elsewhere, pass it:

```bat
link.bat "C:\Program Files (x86)\World of Warcraft"
```

### The two shapes, and why they differ

| Repo | Linked to | Shape |
|------|-----------|-------|
| `projects\` | `C:\projects` | **one junction at the root** |
| `Addons\<name>` | `<WoW>\_classic_era_\Interface\AddOns\<name>` | one junction per folder |

`C:\projects` belongs entirely to this project, so the whole folder is linked at the root. Add a
new mod folder to `projects/` and it is already live — nothing to re-run. It also means the DLL's
runtime output lands *inside* `projects/`, which is why `.gitignore` covers `projects/navmesh/`,
`projects/dinkr_*.txt` and `projects/taco_settings.lua`. Routes are deliberately not
ignored: `walker` writes them to `C:/projects/routes/` and they are worth versioning.

`AddOns` is **not** ours — Questie, Prat-3.0, BugSack and `!BugGrabber` sit alongside our folders.
Root-linking it would delete them, so only our own addons are linked, one junction each.

`Winkr/` needs no link — it builds in place.

### Re-running

`link.bat` is safe to run again: an existing junction is torn down and remade, so a link left
pointing at the wrong target fixes itself. A **real folder** already sitting at a destination is
reported as `SKIP` and left completely alone — move or delete it yourself, then run again. The
script will not delete data it did not create.

Coming from an older per-folder layout (`C:\projects\mmaps` linked separately), `C:\projects` is a
real folder and will be skipped. Remove the inner junction with `rmdir`, move anything else in
`C:\projects` into the repo's `projects\`, `rmdir C:\projects`, then run `link.bat`.

### Verifying

```powershell
Get-Item "C:\projects" | Select-Object FullName, LinkType, Target
Get-ChildItem "C:\Program Files (x86)\World of Warcraft\_classic_era_\Interface\AddOns" |
    Where-Object LinkType | Select-Object FullName, LinkType, Target
```

`LinkType` should read `Junction`, with `Target` pointing back into the repo.

### Unlinking

```bat
unlink.bat
```

Removes only the junctions `link.bat` made. Real folders are reported as `KEEP` and untouched.
Note that the DLL writes to `C:\projects` unconditionally and will recreate it as a plain folder on
the next injection.

> [!WARNING]
> A junction is a real view of the folder, so **deleting through it deletes the repo files.**
> Plain `rmdir` — which is all `unlink.bat` uses — removes the link and leaves the target alone.
> Never use `rmdir /s` or PowerShell's `Remove-Item -Recurse` on a junction: they follow the link
> and wipe the repo copy.

---

## Compiling

Requires GCC (MinGW-w64) via [MSYS2](https://www.msys2.org/).
(dont forget to set your path)

```bash
cd Winkr
build.bat            # produces build\dinkr.exe, build\dinkr.dll, build\dinkr_dump.dll
build.bat clean      # wipe objs + binaries
```

`build.bat` is LF — the wrapper in [`Documents/PatchDay.md`](Documents/PatchDay.md) converts it to CRLF for `cmd`.

Detour compiles with `-DDT_POLYREF64 -fno-exceptions -fno-rtti` so the injected DLL never pulls
in the C++ unwinder. Don't remove those flags.

Recast is vendored alongside it (`vendor/recast/`) and builds under the same flags. Detour alone
is enough to *load* tiles.

---

## Setup

1. Run `link.bat` — junctions `projects\` onto `C:\projects` and our addons into place:
   - the loader scans `C:\projects\*.lua` plus `C:\projects\<dir>\_*.lua` entry points
   - `projects\mmaps` holds the navmesh tiles (layout under [Navigation](#navigation))
2. Run `Winkr\build\dinkr.exe` as admin
3. Start WoW Classic Era

Step 1 is a one-time thing — details under
[Linking](#linking-do-this-once-instead-of-copying). Copying works too, but then every pull has
to be redone by hand.

Mods load on entering the world and flush/reload automatically on `/reload`.

### Integrated Dump (via GUI)

1. Run `dinkr.exe` as admin, start WoW
2. Wait for the GUI to attach (status bar shows connection)
3. Click **Dump** in the status bar (available before DLL injection)
4. The button changes to **Stop (N)** during Warden module scanning — click to finish
5. Output goes to `build\dump\`

**The on-disk `WowClassic.exe` is encrypted** — an offline flat-map scores 0 signatures, which
looks like "everything moved" but means you're reading ciphertext. Patch day always needs a
runtime dump. See [`Documents/PatchDay.md`](Documents/PatchDay.md).

---

## Navigation

The headline feature of this build. Detour (Recast) navmesh loaded straight into the injected
DLL, driving real keyboard movement.

**Tile sources** — two supported, tried in this order by `ensureTile()` in
`dll/nav/dinkr_nav.cpp`:

| Source | Layout | Notes |
|---|---|---|
| **TrinityCore mmaps** | `C:\projects\mmaps\<map:04>.mmap` + `<map:04>_<row:02>_<col:02>.mmtile` | Bodies are **native `dtMeshData`** — skip a 20-byte header, hand the rest straight to `addTile`. Full ADT tiles (533.33 yd). Both tile layouts load: packed `00002337.mmtile` (3.3.5) and underscored `0000_23_37.mmtile` (master). Staged set: **2299 tiles across all 58 Classic maps, 2.7 GB**, zero rejects |
| **DotRecast `.dnm`** (fallback) | `C:\projects\navmesh\<mapId>\tile_<tx>_<tz>.dnm` | Quarter-ADT tiles (133.33 yd) — 16 per mmtile. Needs full body translation: polys 28→32B, links rebuilt, detailMeshes 10→12B, bvTree 28→16B |

> [!NOTE]
> **The staged mmaps are baked locally from the Classic Era client**, by the patched
> TrinityCore tools in `C:\tc`. They replaced an inherited WotLK 3.3.5 extract, which
> mostly worked outdoors — Blizzard barely touched Azeroth before *Cataclysm* — but
> carried WotLK's Stormwind Harbour and TBC's rebuilt Dark Portal as geometry the
> Classic world does not have, and 59 Outland/Northrend maps Classic can never load.
>
> Rebuild with [`tools/bake_mmaps.sh`](tools/bake_mmaps.sh), which carries the tuned
> parameters and the reason for each. **They are not the generator's defaults and are
> not recoverable from a baked tile** — they were lost once and had to be reconstructed
> by md5-matching a staged tile against every candidate output directory.
>
> `projects/mmaps/` **is committed**, so a fresh clone is ready to path without a bake.
> It is 2.7 GB, which is why the history was purged of the two older tile sets first
> (`projects/mmaps` and the long-dead `projects/maps`) -- that took `.git` from 1.7 GB to
> 16 MB before the current tiles went in. Re-baking rewrites every tile, so avoid
> committing more than one bake.
>
> Verify a set with `tools/mmap_inspect.cpp` — it links the vendored Detour and
> mirrors the DLL's loader exactly, so a tile that fails there fails in game:
>
> ```
> mmap_inspect 0                                 coverage report + ASCII map
> mmap_inspect 0 -8900 -160 82                   which tile, is the point on mesh
> mmap_inspect 0 -8900 -160 82 -9040 -360 88     can Detour path between them
> ```

Fallback is detected **per map**, so a partially-staged mmap set can't strand a map that only
has `.dnm` coverage.

**Coordinates.** These tiles use a pure cyclic swap with **no negation**:

```
rc  = (wow.y, wow.z, wow.x)
wow = (rc.z,  rc.x,  rc.y)
```

That is *not* the TrinityCore mmap convention (`-wow.y, wow.z, -wow.x`). Every function in
`dinkr_nav.h` takes and returns **WoW** coords; the swap is internal. Don't swap twice.

**Edge margin.** Baked tiles are eroded only 0.5333 yd — TrinityCore's exact value, tight for
keyboard steering. `DinkrNavSetEdgeMargin()` pushes interior path corners off walls (default
1.5 yd); this is what stops the follower hugging fences and clipping doorframes.

**Movement.** Every movement keybind handler (`MoveForwardStart`, `TurnLeftStart`, …) opens with
a single inline taint gate on `g_taint_handler_ptr`. Route through `dinkr_Call`, which saves,
zeroes and restores it. Full derivation in [`Documents/Movement.md`](Documents/Movement.md).

**Lua surface** — the dinkr Lua adapter sets `awful.hasNavmesh`:

```lua
GeneratePath(sx,sy,sz, gx,gy,gz, mapId)  --> { {x=,y=,z=}, ... }, status
NavNearest(mapId, x,y,z)                 --> snapped walkable point
NavStatus()                              --> last operation detail
```

`status` uses TrinityCore `PathType` bits, which `awful/util/nav.lua` already mirrors, so values
pass straight through to `awful.path:Find`. Area costs are baked into the mesh
(ground 1.0 / water 1.3 / magma 4.0) — the weight fn on `GeneratePathWeighted` is ignored.

---

## Source of Truth

| What | File |
|------|------|
| Per-build RVAs and verification gates | [`shared/rva_defs.h`](Winkr/shared/rva_defs.h) |
| Signature definitions | [`shared/sig_defs.h`](Winkr/shared/sig_defs.h) |
| Guarded field constants | [`shared/om_types.h`](Winkr/shared/om_types.h) |
| IPC protocol | [`shared/ipc_protocol.h`](Winkr/shared/ipc_protocol.h) |
| Dump protocol | [`shared/dump_protocol.h`](Winkr/shared/dump_protocol.h) |
| GUID utilities | [`shared/wow_guid_format.h`](Winkr/shared/wow_guid_format.h) |
| Raw World_Intersect, no Lua stack | [`dll/nav/dinkr_ray.h`](Winkr/dll/nav/dinkr_ray.h) |
| Navmesh facade — tile loading, coord swap | [`dll/nav/dinkr_nav.h`](Winkr/dll/nav/dinkr_nav.h) · [`.cpp`](Winkr/dll/nav/dinkr_nav.cpp) |
| C bridge functions | [`dll/bridge/`](Winkr/dll/bridge/) |
| Mod loader | [`dll/mods/dinkr_mods.c`](Winkr/dll/mods/dinkr_mods.c) |
| Patch-day self-heal scanner | [`dll/core/dinkr_selfheal.c`](Winkr/dll/core/dinkr_selfheal.c) |

### Bridge modules

| File | Surface |
|---|---|
| `dinkr_bridge_core.c` | File I/O, key state, `dinkr_Call`, map id |
| `dinkr_bridge_nav.c` | `GeneratePath`, `NavNearest`, `NavStatus`, `NavLastRequest` |
| `dinkr_bridge_objects.c` | Object manager — position, name, type, ID, facing, lootable, creator, descriptor |
| `dinkr_bridge_combat.c` | Auras, missiles, combat log, native cast |
| `dinkr_bridge_camera.c` | World↔screen projection, `ScreenToWorld`, `ClickPosition`, camera diag |
| `dinkr_bridge_actions.c` | `FaceDirection`, interact, movement heartbeat, spell targeting |
| `dinkr_bridge_misc.c` | TraceLine, NPC slots, debug |

---

## Documentation

Reverse-engineering documentation lives in [`Documents/`](Documents/).

| Document | Contents |
|----------|----------|
| [PatchDay](Documents/PatchDay.md) | **Run this whole file after every build bump.** Safe mode, runtime dump, RVA re-derivation. ~15 min |
| [Movement](Documents/Movement.md) | The inline taint gate on every movement keybind, and the two ways past it |
| [RXP Questing Plan](Documents/RXP_Questing_Plan.md) | Following the loaded RestedXP guide via its live step machine — no parser needed |
| [Big Warden Reversal](Documents/Big%20Warden%20Reversal/reversing-warden.md) | Warden module analysis — selector-by-selector reversal notes and captured structures |

---

## Requirements

- Windows 10/11 x64
- Administrator privileges
- GCC (MinGW-w64) via [MSYS2](https://www.msys2.org/)
