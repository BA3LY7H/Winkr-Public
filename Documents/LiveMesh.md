# LiveMesh — runtime tile generation

Bakes navmesh tiles **while the game runs**, by asking the client's own collision where the
world is. Intended as a **supplement**: for installs with no staged bake, and for areas where
the staged one is wrong (the mmaps are a WotLK extract, so Classic-only geometry is missing
from them). It is far too slow to be the primary source — see the numbers below.

LiveMesh is **two halves**, and both are needed:

- **Policy — the awful2 Lua project** at `projects/awful2/!projects/LiveMesh/`
  (`core`, `gen`, `draw`, `mesh`, `verify`, `commands` — see `load.json`). It decides *which*
  tile to build and *when*, pumps generation one frame at a time, and implements the `/lm`
  commands and the grid overlay.
- **Mechanism — the injected C++ engine** in
  [`dll/nav/dinkr_livemesh.cpp`](../Winkr/dll/nav/dinkr_livemesh.cpp) (`DinkrLiveMesh*`). It does
  the expensive work — raycast rake → Recast → `dtCreateNavMeshData` → write the `.lmt` tile —
  because it must run inside the client process against live client state.

The two talk over the Lua C bridge (`dinkr_LiveMeshBegin/Step/Status/…`, implemented in
`dll/bridge/dinkr_bridge_nav.c` and registered as Lua globals in `dll/mods/dinkr_mods.c`).

## Tile source

Writes `.lmt` tiles to `C:\projects\livemesh\<mapId>\tile_<tx>_<tz>.lmt` — the same 20-byte
header as an mmtile with a native `dtMeshData` body, so it loads through the identical path.
Quarter-ADT tiles (133.33 yd).

> [!IMPORTANT]
> **LiveMesh and mmaps cannot mix on the same map, and that is structural rather than a
> preference.** mmaps index tiles on TrinityCore's full-ADT grid (533.33 yd); LiveMesh bakes
> quarter-ADT (133.33 yd). A `dtNavMesh` has exactly ONE tile grid, fixed at init from the
> `.mmap` header, and `addTile` places a tile by `header->x/y` — so a quarter-ADT tile handed
> to a full-ADT grid lands four tiles out of position.
>
> `ensureTile` therefore consults `.lmt` only when the map is **not** using mmaps
> (`m->useMmap == 0`, i.e. no `<map:04>.mmap` is staged). Removing that guard does not blend
> the two sources — it splices tiles kilometres from where they belong.
>
> The rule in practice: a map with a staged bake uses it for the whole map. A map without one
> falls back to LiveMesh. Staging `0000.mmap` silently switches map 0 away from LiveMesh.

## How it works

Fire rays straight down through a tile and record *every* surface each column
crosses — not just the first, or you get a heightmap that puts mesh on roofs and nothing inside
buildings. Feed those spans to Recast, then `dtCreateNavMeshData`, then write the tile.

Four phases, budget-sliced across frames (`DinkrLiveMeshStep`), all on the main thread because
`World_Intersect` reads live client state:

| Phase | What | Cost (open / city) |
|---|---|---|
| probe | coarse 16×16 pass for the tile's Z bounds | negligible |
| rake | column sampling into `rcHeightfield` | ~1.4 s / ~2.7 s |
| walls | horizontal probes for walls, carts, fences | ~0.2 s / ~4 s |
| build | Recast pipeline + `dtCreateNavMeshData` | 90–300 ms |

**Walls need their own pass.** A downward ray never touches a vertical surface, so a raked tile
has floors and no walls at all, and Detour will happily path through a partition or into the
cart outside the Stormwind auction house. For every surface with standing room, probe toward
the +x/+z neighbours (and the two diagonals — they found 2.4× more obstructions than the axis
pair alone), and where the probe is blocked, raise a solid `RC_NULL_AREA` span in the cell the
ray actually hit.

Two constants there are load-bearing:

- **Probe height is `AGENT_CLIMB + 0.2`.** It must clear the step height or every stair tread
  reads as a wall. The cost is that anything shorter than a step is invisible — correct, since
  you can walk over those anyway.
- **Obstructions are applied *after* raking, never during.** `rcAddSpan` merges overlapping
  spans and the *new* span's area wins unless the tops are within `flagMergeThreshold`. An
  obstruction added before the floor span in its cell merges back to `RC_WALKABLE_AREA` — the
  wall erases itself, and it looks exactly like the wall pass doing nothing.

**Probe skipping.** Open ground dominates a tile and costs a ray per neighbour to learn nothing.
A probe is skipped when the neighbour has a surface within climb of ours *and* nothing above it
*and* our own cell has nothing above it. That last clause matters: the obstruction can stand in
**our** cell, and each pair is only tested once, so checking the neighbour alone lost 1–7% of
wall spans. With it, the difference is 0.09% and open tiles are 13–18× faster.

**Measured on 69109** (Stormwind and Elwynn, `dinkr_TraceLine` and the C path both):

- **2.5–4.5 µs per ray**, and the C generator measures the same — `World_Intersect` dominates
  entirely, so Lua overhead was never the cost
- **2.1 rays/column** open, 3.6–4.1 in a city
- **~1.5 s/tile** open, **~8 s/tile** in Stormwind; a full zone is ~900 tiles, so **~2 hours**
- Collision streams to **~800 yd** for terrain, but doodads far closer — a tile baked from the
  next tile over measurably lacks props

**Provenance.** Because of that last point, each tile records how far the player was from its
centre when baked (in the header's `usesLiquids` slot, which nothing on our side reads as a
liquid flag). A cached tile is re-baked when it can be done from 40 yd closer, so passing near a
tile made from range quietly upgrades it. A tile written before this existed reports 0 and is
never refreshed.

**Commands** — probes first, generation second:

```
/lm                    status
/lm ray | col          one downward ray / walk the column under your feet
/lm bench [n]          us/ray + projected cost per tile
/lm radius [d]         how far out collision is actually streamed
/lm width              gap sizes around you; in a corner, your collision radius
/lm sample [n]         sample an n x n patch, sliced across frames

/lm gen                generate the tile you are standing in
/lm gen ring [n]       the n-ring around you, nearest first
/lm gen auto           follow the player and fill ahead (off by default)
/lm gen radius | climb agent radius / step height (regenerate after changing)
/lm gen walls | diag | skip     toggle the wall pass, diagonals, probe skipping
/lm draw [n]           show the tile grid in the world
```

`auto` scores candidate tiles by distance to a point 200 yd **ahead of your facing**, and takes
its targets from the ring, walker's live route, and `DinkrNavLastRequest()` — which records
every call into `DinkrNavFindPath`, succeeded or failed. Hooking the funnel rather than any one
consumer is deliberate: walker, the grind leash and `awful.path:Find` all feed it without
knowing LiveMesh exists, and a *failed* query is exactly when tiles are missing.

## Known limits

- **No worker thread.** The Recast build is one indivisible call and hitches 90–300 ms. Moving
  it off-thread crashed the client: referencing `CreateThread` drags in MinGW's CRT thread init,
  which runs at `DLL_PROCESS_ATTACH` and calls `GetModuleHandleA` — and `dinkr.dll` is manually
  mapped, so it is not in the loader's module list and that init faults inside ntdll. The code
  is kept behind `#define LM_BUILD_THREAD 0` with the full explanation. Fixing it needs a thread
  owned by something already loaded (the GUI over IPC), not `CreateThread` from this module.
- **Walls thinner than one cell (0.267 yd) between sample points** are invisible to the skip
  filter — neither cell records a span, so nothing suggests firing the ray. Railings and thin
  fence rails are the candidates. This is the 0.09% above.
- **Slope comes from neighbour height differences**, not triangle normals, since we have surface
  points rather than geometry. `markSteepSpans` handles it separately from `walkableClimb` so
  step height and hill steepness do not have to share one number.
