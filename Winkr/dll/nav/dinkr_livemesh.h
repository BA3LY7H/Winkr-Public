/* dinkr_livemesh.h — generate navmesh tiles at runtime by raycasting the world.
 *
 * WHY: the shipped tile sets do not cover map 0/1 on this install, and baking a
 * full mmap set offline needs the client's map data extracted. Instead we ask
 * the running client what its own collision looks like — fire rays down through
 * a tile, record every surface each column crosses, hand the spans to Recast,
 * and emit a Detour tile. Measured live on 69109 before any of this was written:
 *
 *   2.5 us/ray outdoors, 4.5 us/ray in Stormwind (through Lua; C is faster)
 *   4.1 rays/column averaged over a full 133 yd tile on the Stormwind bridge
 *   collision streams to ~800 yd, tapering out by ~1200 yd
 *
 * That last number is the constraint: we can only mesh what the client has
 * loaded, so this follows the player and accumulates into a disk cache rather
 * than baking a zone up front.
 *
 * THREADING: rays touch live client state, so every phase runs on the main
 * thread, budget-sliced. Drive it by calling DinkrLiveMeshStep() once a frame.
 */
#ifndef DINKR_LIVEMESH_H
#define DINKR_LIVEMESH_H

#ifdef __cplusplus
extern "C" {
#endif

#define LM_IDLE    0
#define LM_PROBE   1   /* coarse pass to find the tile's Z bounds */
#define LM_RAKE    2   /* column sampling into the heightfield */
#define LM_WALLS   5   /* horizontal probes: walls, carts, fences, crates */
#define LM_BUILD   3   /* Recast pipeline + dtCreateNavMeshData */
#define LM_DONE    4
#define LM_FAILED (-1)

/* Queue one tile. Returns 0 if a job is already running or setup failed. */
/* genDist: how far the player is from this tile's centre right now. Stamped
 * into the tile so it can be refreshed later from closer up — a tile baked
 * while its far side was outside doodad streaming range is silently missing
 * props. */
int  DinkrLiveMeshBegin(int mapId, int tx, int tz, float genDist);

/* Advance the current job by at most budgetMs of wall clock. Returns the phase
 * after stepping. Safe to call when idle. */
int  DinkrLiveMeshStep(double budgetMs);

int  DinkrLiveMeshPhase(void);
void DinkrLiveMeshProgress(int* done, int* total);
void DinkrLiveMeshCancel(void);
const char* DinkrLiveMeshStatusText(void);

/* Timings and counters from the last completed tile, for tuning. */
void DinkrLiveMeshLastStats(double* rakeMs, double* buildMs,
                            int* rays, int* spans, int* polys,
                            double* wallMs, int* wallSpans);

/* The tile grid LiveMesh uses is the same quarter-ADT grid dinkr_nav.cpp uses
 * for non-mmap sources, so generated tiles drop straight into the existing
 * loader without a coordinate change. */
void DinkrLiveMeshTileIndex(float wx, float wy, int* tx, int* tz);

/* Horizontal wall/obstruction probing. On by default. Without it the mesh has
 * floors but no walls, and Detour paths straight through partitions and props —
 * downward rays never touch a vertical surface. */
/* Agent radius the mesh is eroded by — the hard clearance guarantee. Any point
 * on the finished mesh is at least this far from geometry, which is what stops a
 * shoulder catching a doorframe or a lamp post. Tiles must be regenerated after
 * changing it. */
/* Step height, in yards. Drives both what Recast treats as climbable and the
 * height the wall pass probes at, so obstacles you cannot step over are seen and
 * ones you can are ignored. Regenerate tiles after changing. */
void  DinkrLiveMeshSetClimb(float c);
float DinkrLiveMeshGetClimb(void);

/* Diagonal wall probes: catches thin posts sitting near a cell corner that the
 * axis-aligned pair can miss. Doubles the wall pass. */
/* Skip wall probes the heightfield already proves cannot hit anything (open
 * ground with nothing overhead). Correctness-preserving; on by default. Turn it
 * off to A/B the wall-span count. */
void  DinkrLiveMeshSetProbeSkip(int on);
int   DinkrLiveMeshGetProbeSkip(void);

void  DinkrLiveMeshSetDiagonals(int on);
int   DinkrLiveMeshGetDiagonals(void);

void  DinkrLiveMeshSetAgentRadius(float r);
float DinkrLiveMeshGetAgentRadius(void);

void DinkrLiveMeshSetWalls(int on);
int  DinkrLiveMeshGetWalls(void);

void        DinkrLiveMeshSetCacheDir(const char* dir);
const char* DinkrLiveMeshCacheDir(void);

/* 1 when a generated tile for this index is already on disk. */
int  DinkrLiveMeshHaveTile(int mapId, int tx, int tz);

/* Distance the cached tile was baked from, or -1 when there is no tile. */
float DinkrLiveMeshTileGenDist(int mapId, int tx, int tz);

/* World centre of a tile, so the scheduler does not duplicate the grid maths. */
void DinkrLiveMeshTileCenter(int tx, int tz, float* outWx, float* outWy);

#ifdef __cplusplus
}
#endif
#endif /* DINKR_LIVEMESH_H */
