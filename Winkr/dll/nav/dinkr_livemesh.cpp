/* dinkr_livemesh.cpp — runtime navmesh generation from raycast sampling.
 * See dinkr_livemesh.h for what this is and the measurements that justify it.
 */
#include "dinkr_livemesh.h"
#include "dinkr_ray.h"

/* See the long note by stepBuild: enabling this crashes a manually mapped DLL
 * at entry, because referencing CreateThread drags in MinGW CRT thread init. */
#define LM_BUILD_THREAD 0

#include <windows.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <math.h>

#include "Recast.h"
#include "DetourNavMesh.h"
#include "DetourNavMeshBuilder.h"
#include "DetourAlloc.h"

/* ---- grid ----------------------------------------------------------------
 * These MUST match dinkr_nav.cpp's non-mmap grid or generated tiles will land
 * in the wrong place: NAV_ORIGIN/NAV_TILE_SIZE there, wowTileIndex() there.
 * Coordinates convert with the same pure cyclic swap, no negation:
 *     rc = (wow.y, wow.z, wow.x)
 */
static const float NAV_ORIGIN    = -32.0f * 533.33333f;
static const float NAV_TILE_SIZE = 133.33333f;

/* CELL SIZE. 500 cells across a 133.33 yd tile gives 0.26667 yd, which is
 * exactly TrinityCore's BASE_UNIT_DIM. Matching it matters beyond tidiness: the
 * walker's steering and DinkrNavSetEdgeMargin's 1.5 yd default were tuned
 * against TC-eroded meshes, and a different cell size changes how far the mesh
 * sits off a wall, which is precisely what that tuning compensates for.
 * It also has to divide the tile evenly — Recast needs an integer cell count. */
static const int   TILE_CELLS = 500;
static const float CELL_SIZE  = NAV_TILE_SIZE / (float)TILE_CELLS;   /* 0.266666 */
static const float CELL_HEIGHT = 0.26666f;

/* Agent. Radius 0.6 yd is a WoW character; 2 cells of erosion reproduces the
 * 0.5333 yd the baked tiles use. */
static const float AGENT_HEIGHT = 2.0f;
/* Settable so the true capsule half-width can be A/B'd in game without a
 * rebuild. Raising it is NOT free: erosion is global and destructive, and at
 * radius r every gap narrower than 2r disappears from the mesh entirely. Tiles
 * must be regenerated for a change to take effect. */
static float AGENT_RADIUS = 0.6f;
/* Step height. This single number decides BOTH what Recast will smooth into
 * walkable ground and what the wall pass bothers to look at, so the two can
 * never disagree — see wallProbeHeight(). Too high and knee-high boulders,
 * flower beds and curbs are assumed steppable, get no obstruction, and the
 * follower walks into them. Too low and stair treads read as walls. */
static float AGENT_CLIMB = 1.0f;
static const float MAX_SLOPE_DEG = 50.0f;

/* Wall probing. The probe must sit just ABOVE the step height: a ray at that
 * height sails over anything climbable (stair treads, curbs, gentle slopes) and
 * stops against anything that is not (walls, carts, lamp posts, boulders).
 * Deriving it from AGENT_CLIMB rather than hard-coding it keeps the two in step
 * when the climb is retuned. */
static const float WALL_PROBE_LIFT = 0.2f;
static inline float wallProbeHeight(void) { return AGENT_CLIMB + WALL_PROBE_LIFT; }

/* Diagonal probes in addition to the axis pair. A thin pole sitting close to a
 * cell corner can slip between two axis-aligned probe lines and never enter the
 * mesh at all; the diagonals close that gap. Costs another two rays per
 * standable span, so it roughly doubles the wall pass. */
static int s_diagProbe = 1;

/* Skip probes that cannot possibly find a wall. Open ground dominates a world
 * tile and costs a ray per neighbour to learn nothing; this reads the
 * heightfield we already built instead, which is ~100x cheaper than a trace. */
static int s_probeSkip = 1;
static const int   OBS_CAP      = 400000;

/* Column raking */
static const int   MAX_LAYERS = 20;    /* measured: Stormwind reaches 13 */
static const float LAYER_EPS  = 0.1f;
static const float PROBE_MARGIN = 15.0f;
static const int   PROBE_GRID = 16;

/* ---- state ---------------------------------------------------------------- */
/* Obstructions are collected during the pass and applied after it, so they are
 * buffered rather than written into the heightfield as they are found. */
struct Obstruction { int cell; float z; };

struct Job {
    int    mapId, tx, tz;
    int    phase;
    float  genDist;      /* player distance to tile centre when baked */
    /* expanded (bordered) grid */
    int    w, h, borderSize;
    float  bmin[3], bmax[3];          /* rc space, includes border */
    /* rake cursor */
    int    cursor, total;
    /* probe */
    int    probeI;
    float  probeLo, probeHi;
    /* accumulated */
    rcHeightfield* hf;
    int    rays, spans, badRays;
    /* wall pass */
    int    wallRays, wallSpans, obsOverflow, wallSkipped;
    double wallMs;
    struct Obstruction* obs;
    int    obsCount, obsCap;
    double rakeMs, buildMs;
    int    polys;
};

struct LmTileHeader {
    unsigned int magic;
    unsigned int dtVersion;
    unsigned int lmVersion;      /* mmapVersion slot */
    unsigned int size;
    unsigned int usesLiquids;    /* unused, but the field EXISTS in the format */
};
/* This must be exactly 20 bytes. ensureTile() skips a fixed 20 and hands the
 * rest to addTile, so a 16-byte header starts the body 4 bytes late: the
 * dtMeshHeader's magic lands where nothing expects it, every field shifts by
 * one int, and addTile rejects the tile. That is not a loud failure — it looks
 * exactly like "the tile did not load". */
typedef char LmTileHeader_is_20_bytes[(sizeof(LmTileHeader) == 20) ? 1 : -1];

/* Recast's context is NOT optional. rcBuildRegions, rcBuildContours,
 * rcBuildPolyMesh, rcBuildPolyMeshDetail and rcBuildDistanceField all call
 * ctx->log()/startTimer() unconditionally, so passing NULL crashes the client
 * rather than skipping the logging. Constructed with state=false, which disables
 * both logging and the perf timers inside rcContext itself. */
static rcContext s_rcCtx(false);

static Job  s_job;
static int  s_busy = 0;
#if defined(LM_BUILD_THREAD) && LM_BUILD_THREAD
/* Declared up here because DinkrLiveMeshCancel, defined above the build
 * section, has to join the worker before tearing the job down. */
static HANDLE s_buildThread = NULL;
#endif
static int  s_wallProbe = 1;
static char s_status[256] = "livemesh: idle";
static char s_cacheDir[260] = "C:\\projects\\livemesh";
static double s_lastRake = 0, s_lastBuild = 0;
static int    s_lastRays = 0, s_lastSpans = 0, s_lastPolys = 0;
static double s_lastWallMs = 0;
static int    s_lastWallSpans = 0;

static void setStatus(const char* fmt, ...) {
    va_list ap; va_start(ap, fmt);
    vsnprintf(s_status, sizeof(s_status), fmt, ap);
    va_end(ap);
}

static double nowMs(void) {
    static LARGE_INTEGER freq = {0};
    LARGE_INTEGER c;
    if (!freq.QuadPart) QueryPerformanceFrequency(&freq);
    QueryPerformanceCounter(&c);
    return (double)c.QuadPart * 1000.0 / (double)freq.QuadPart;
}

/* ---- coordinates ---------------------------------------------------------- */
void DinkrLiveMeshTileIndex(float wx, float wy, int* tx, int* tz) {
    if (tx) *tx = (int)floorf((wy - NAV_ORIGIN) / NAV_TILE_SIZE);
    if (tz) *tz = (int)floorf((wx - NAV_ORIGIN) / NAV_TILE_SIZE);
}

void DinkrLiveMeshTileCenter(int tx, int tz, float* outWx, float* outWy) {
    /* rc.x is wow.y and rc.z is wow.x, so tx addresses wow.y and tz wow.x. */
    if (outWy) *outWy = NAV_ORIGIN + ((float)tx + 0.5f) * NAV_TILE_SIZE;
    if (outWx) *outWx = NAV_ORIGIN + ((float)tz + 0.5f) * NAV_TILE_SIZE;
}

/* rc.x indexes with tx, rc.z with tz — same as wowTileIndex in dinkr_nav.cpp. */
static void tileBounds(int tx, int tz, float* rcMinX, float* rcMinZ) {
    *rcMinX = NAV_ORIGIN + (float)tx * NAV_TILE_SIZE;
    *rcMinZ = NAV_ORIGIN + (float)tz * NAV_TILE_SIZE;
}

/* ---- one column ----------------------------------------------------------
 * Walk (wx, wy) top-down and return every surface Z. This is the C twin of
 * LiveMesh's Lua LM.column, including the fail-safe check: dinkr_RayCastRaw
 * returns -1 when the world frame will not resolve, and a caller that treated
 * that as a hit would carpet the tile in fake geometry at the ray origin. */
static int rakeColumn(float wx, float wy, float top, float bottom,
                      float* out, int maxOut, int* raysOut, int* badOut) {
    int n = 0, rays = 0, bad = 0;
    float from = top;
    for (int i = 0; i < maxOut && i < MAX_LAYERS; ++i) {
        if (from <= bottom) break;
        float hit[3];
        rays++;
        int rc = dinkr_RayCastRaw(wx, wy, from, wx, wy, bottom, 0, hit);
        if (rc == 0) break;                       /* clear: nothing below */
        if (rc < 0) { bad++; break; }             /* unresolvable: stop, do not invent */
        if (n < maxOut) out[n++] = hit[2];
        from = hit[2] - LAYER_EPS;                /* strictly descending: cannot spin */
    }
    if (raysOut) *raysOut += rays;
    if (badOut)  *badOut  += bad;
    return n;
}

/* ---- setup ---------------------------------------------------------------- */
int DinkrLiveMeshBegin(int mapId, int tx, int tz, float genDist) {
    if (s_busy) { setStatus("livemesh: busy (%d_%d)", s_job.tx, s_job.tz); return 0; }
    if (tx < 0 || tz < 0) { setStatus("livemesh: bad tile %d_%d", tx, tz); return 0; }

    memset(&s_job, 0, sizeof(s_job));
    s_job.mapId = mapId; s_job.tx = tx; s_job.tz = tz;
    s_job.genDist = genDist;

    /* Recast needs a border around a tile so features crossing the edge are
     * resolved consistently with the neighbouring tile. We must SAMPLE that
     * border too, so the raked area is larger than the tile itself. */
    s_job.borderSize = (int)ceilf(AGENT_RADIUS / CELL_SIZE) + 3;
    s_job.w = TILE_CELLS + s_job.borderSize * 2;
    s_job.h = TILE_CELLS + s_job.borderSize * 2;

    float rcMinX, rcMinZ;
    tileBounds(tx, tz, &rcMinX, &rcMinZ);
    s_job.bmin[0] = rcMinX - s_job.borderSize * CELL_SIZE;
    s_job.bmin[2] = rcMinZ - s_job.borderSize * CELL_SIZE;
    s_job.bmax[0] = rcMinX + NAV_TILE_SIZE + s_job.borderSize * CELL_SIZE;
    s_job.bmax[2] = rcMinZ + NAV_TILE_SIZE + s_job.borderSize * CELL_SIZE;

    s_job.probeLo =  1e30f;
    s_job.probeHi = -1e30f;
    s_job.total   = s_job.w * s_job.h;
    s_job.phase   = LM_PROBE;
    s_busy = 1;
    setStatus("livemesh: probing %d_%d", tx, tz);
    return 1;
}

void DinkrLiveMeshCancel(void) {
    /* Join before touching anything the worker owns. It frees the heightfield
     * itself, so freeing it here while the thread runs is a use-after-free. The
     * wait is bounded by one Recast build (~300 ms) and only happens if a cancel
     * lands inside that window. */
#if defined(LM_BUILD_THREAD) && LM_BUILD_THREAD
    if (s_buildThread) {
        WaitForSingleObject(s_buildThread, INFINITE);
        CloseHandle(s_buildThread);
        s_buildThread = NULL;
    }
#endif
    if (s_job.hf) { rcFreeHeightField(s_job.hf); s_job.hf = NULL; }
    if (s_job.obs) { free(s_job.obs); s_job.obs = NULL; }
    memset(&s_job, 0, sizeof(s_job));
    s_busy = 0;
    setStatus("livemesh: cancelled");
}

int  DinkrLiveMeshPhase(void) { return s_busy ? s_job.phase : LM_IDLE; }
const char* DinkrLiveMeshStatusText(void) { return s_status; }
void DinkrLiveMeshSetCacheDir(const char* dir) {
    if (dir && *dir) { strncpy(s_cacheDir, dir, sizeof(s_cacheDir) - 1); s_cacheDir[sizeof(s_cacheDir)-1] = 0; }
}
const char* DinkrLiveMeshCacheDir(void) { return s_cacheDir; }
void  DinkrLiveMeshSetAgentRadius(float r) {
    if (r >= 0.1f && r <= 3.0f) AGENT_RADIUS = r;
}
float DinkrLiveMeshGetAgentRadius(void) { return AGENT_RADIUS; }
void  DinkrLiveMeshSetClimb(float c) { if (c >= 0.1f && c <= 2.0f) AGENT_CLIMB = c; }
float DinkrLiveMeshGetClimb(void) { return AGENT_CLIMB; }
void  DinkrLiveMeshSetDiagonals(int on) { s_diagProbe = on ? 1 : 0; }
void  DinkrLiveMeshSetProbeSkip(int on) { s_probeSkip = on ? 1 : 0; }
int   DinkrLiveMeshGetProbeSkip(void) { return s_probeSkip; }
int   DinkrLiveMeshGetDiagonals(void) { return s_diagProbe; }
void DinkrLiveMeshSetWalls(int on) { s_wallProbe = on ? 1 : 0; }
int  DinkrLiveMeshGetWalls(void) { return s_wallProbe; }
void DinkrLiveMeshProgress(int* done, int* total) {
    if (done)  *done  = s_busy ? s_job.cursor : 0;
    if (total) *total = s_busy ? s_job.total  : 0;
}
void DinkrLiveMeshLastStats(double* rakeMs, double* buildMs, int* rays, int* spans,
                            int* polys, double* wallMs, int* wallSpans) {
    if (rakeMs)    *rakeMs    = s_lastRake;
    if (buildMs)   *buildMs   = s_lastBuild;
    if (rays)      *rays      = s_lastRays;
    if (spans)     *spans     = s_lastSpans;
    if (polys)     *polys     = s_lastPolys;
    if (wallMs)    *wallMs    = s_lastWallMs;
    if (wallSpans) *wallSpans = s_lastWallSpans;
}

static void tilePath(char* out, size_t cap, int mapId, int tx, int tz) {
    snprintf(out, cap, "%s\\%d\\tile_%d_%d.lmt", s_cacheDir, mapId, tx, tz);
}

/* -1 when there is no tile; otherwise the distance it was baked from. A tile
 * written before provenance existed reports 0, which reads as "baked from right
 * on top of it" and so is never refreshed — deliberate, since we cannot know
 * better and a spurious rebuild loop is worse than a stale tile. */
float DinkrLiveMeshTileGenDist(int mapId, int tx, int tz) {
    char p[300];
    tilePath(p, sizeof(p), mapId, tx, tz);
    FILE* f = fopen(p, "rb");
    if (!f) return -1.0f;
    LmTileHeader h;
    size_t rd = fread(&h, 1, sizeof(h), f);
    fclose(f);
    if (rd != sizeof(h) || h.magic != 0x4D4D4150u) return -1.0f;
    return (float)h.usesLiquids / 100.0f;
}

int DinkrLiveMeshHaveTile(int mapId, int tx, int tz) {
    char p[300];
    tilePath(p, sizeof(p), mapId, tx, tz);
    FILE* f = fopen(p, "rb");
    if (!f) return 0;
    fclose(f);
    return 1;
}

/* ---- phase: probe --------------------------------------------------------
 * Sample a coarse grid to find the tile's real Z extent. A player-relative
 * window is not good enough: a full tile on the Stormwind bridge measured 91 yd
 * of relief, and geometry outside the window is not an error — the column just
 * comes back short and the tile silently loses its high ground. */
static void stepProbe(double budgetMs) {
    double t0 = nowMs();
    const int N = PROBE_GRID * PROBE_GRID;
    while (s_job.probeI < N) {
        int i = s_job.probeI++;
        float fx = ((i % PROBE_GRID) + 0.5f) / (float)PROBE_GRID;
        float fz = ((i / PROBE_GRID) + 0.5f) / (float)PROBE_GRID;
        float rcx = s_job.bmin[0] + fx * (s_job.bmax[0] - s_job.bmin[0]);
        float rcz = s_job.bmin[2] + fz * (s_job.bmax[2] - s_job.bmin[2]);
        float wx = rcz, wy = rcx;      /* rc -> wow */

        float zs[MAX_LAYERS];
        int n = rakeColumn(wx, wy, 2000.0f, -2000.0f, zs, MAX_LAYERS,
                           &s_job.rays, &s_job.badRays);
        for (int k = 0; k < n; ++k) {
            if (zs[k] < s_job.probeLo) s_job.probeLo = zs[k];
            if (zs[k] > s_job.probeHi) s_job.probeHi = zs[k];
        }
        if (nowMs() - t0 >= budgetMs) return;
    }

    if (s_job.probeLo > s_job.probeHi) {
        setStatus("livemesh: tile %d_%d has no geometry (not streamed?)", s_job.tx, s_job.tz);
        s_job.phase = LM_FAILED;
        return;
    }
    s_job.bmin[1] = s_job.probeLo - PROBE_MARGIN;
    s_job.bmax[1] = s_job.probeHi + PROBE_MARGIN;

    s_job.hf = rcAllocHeightfield();
    if (!s_job.hf) { setStatus("livemesh: heightfield alloc failed"); s_job.phase = LM_FAILED; return; }
    /* rcCreateHeightfield wants a context for logging; we have none and it is
     * optional throughout Recast, so NULL is the intended "no logging" value. */
    if (!rcCreateHeightfield(&s_rcCtx, *s_job.hf, s_job.w, s_job.h,
                             s_job.bmin, s_job.bmax, CELL_SIZE, CELL_HEIGHT)) {
        setStatus("livemesh: rcCreateHeightfield failed");
        s_job.phase = LM_FAILED;
        return;
    }
    if (s_wallProbe) {
        s_job.obs = (Obstruction*)malloc(sizeof(Obstruction) * OBS_CAP);
        s_job.obsCap = s_job.obs ? OBS_CAP : 0;
    }
    s_job.phase = LM_RAKE;
    setStatus("livemesh: raking %d_%d (z %.0f..%.0f)", s_job.tx, s_job.tz,
              s_job.bmin[1], s_job.bmax[1]);
}

/* ---- phase: rake ---------------------------------------------------------- */
static void stepRake(double budgetMs) {
    double t0 = nowMs();
    const int maxSpanH = 0x1fff;     /* RC_SPAN_MAX_HEIGHT */

    while (s_job.cursor < s_job.total) {
        int i  = s_job.cursor++;
        int ix = i % s_job.w;
        int iz = i / s_job.w;

        float rcx = s_job.bmin[0] + ((float)ix + 0.5f) * CELL_SIZE;
        float rcz = s_job.bmin[2] + ((float)iz + 0.5f) * CELL_SIZE;
        float wx = rcz, wy = rcx;

        float zs[MAX_LAYERS];
        int n = rakeColumn(wx, wy, s_job.bmax[1], s_job.bmin[1], zs, MAX_LAYERS,
                           &s_job.rays, &s_job.badRays);

        for (int k = 0; k < n; ++k) {
            /* One surface becomes one cell-tall span — the same thing
             * rasterizing a flat triangle would produce. We do not try to pair
             * hits into solid slabs: the live probes could not reliably tell a
             * slab underside from a separate surface, and it turns out not to
             * matter, because rcFilterWalkableLowHeightSpans culls anything
             * without AGENT_HEIGHT of clearance above it — which is every
             * parasitic underside, since floor slabs measured 0.44-1.82 yd. */
            int smin = (int)floorf((zs[k] - s_job.bmin[1]) / CELL_HEIGHT);
            if (smin < 0) continue;
            if (smin >= maxSpanH) continue;
            int smax = smin + 1;
            if (smax > maxSpanH) smax = maxSpanH;
            if (rcAddSpan(&s_rcCtx, *s_job.hf, ix, iz,
                          (unsigned short)smin, (unsigned short)smax,
                          RC_WALKABLE_AREA, 1))
                s_job.spans++;
        }

        if (nowMs() - t0 >= budgetMs) break;
    }
    s_job.rakeMs += nowMs() - t0;

    if (s_job.cursor >= s_job.total) {
        if (s_wallProbe) {
            s_job.cursor = 0;
            s_job.phase = LM_WALLS;
            setStatus("livemesh: probing walls %d_%d", s_job.tx, s_job.tz);
        } else {
            s_job.phase = LM_BUILD;
            setStatus("livemesh: building %d_%d (%d spans, %d rays)",
                      s_job.tx, s_job.tz, s_job.spans, s_job.rays);
        }
    }
}

/* ---- phase: walls --------------------------------------------------------
 * Downward rays only ever report SURFACES, so a raked tile has floors and no
 * walls whatsoever. Detour then happily joins two rooms through the partition
 * between them, and a route runs into the cart outside the Stormwind auction
 * house because nothing in the mesh says the cart is there.
 *
 * The fix is the one thing a downward ray cannot do: cast sideways. For every
 * surface with enough headroom to stand on, probe toward the +x and +z
 * neighbour; a blocked probe means something vertical is in between, and the
 * ray's own hit point says exactly which cell it occupies. That cell gets a
 * solid, non-walkable span AGENT_HEIGHT tall, which Recast then refuses to
 * connect across.
 *
 * Only +x and +z, so each pair of neighbours is tested once rather than twice.
 *
 * PROBE HEIGHT is the delicate number. It must sit ABOVE AGENT_CLIMB, or every
 * stair tread reads as a wall and staircases become impassable. It therefore
 * cannot see anything shorter than a step, which is the right trade: obstacles
 * you can walk over should not be in the mesh.
 */
static void queueObstruction(int ix, int iz, float baseZ) {
    if (ix < 0 || iz < 0 || ix >= s_job.w || iz >= s_job.h) return;
    if (s_job.obsCount >= s_job.obsCap) { s_job.obsOverflow++; return; }
    Obstruction* o = &s_job.obs[s_job.obsCount++];
    o->cell = ix + iz * s_job.w;
    o->z = baseZ;
}

/* Is a probe toward this neighbour worth firing?
 *
 * The tempting test — "the neighbour has ground at our height, so it is
 * continuous, skip" — is WRONG on its own, and wrong in exactly the case this
 * whole pass exists for: a thin wall's cell usually ALSO carries a floor span,
 * because the rake sees the wall top and then the floor continuing underneath
 * it. Skipping on matching ground alone would blind us to every interior wall.
 *
 * So a probe is also required whenever the neighbour has anything ABOVE our
 * surface. A wall, fence, lamp post or cart always does — that is its own
 * geometry standing in that cell. Open terrain has neither a discontinuity nor
 * anything overhead, and only then is a ray provably wasted.
 *
 * Interiors have ceilings over every cell, so they keep full coverage. That is
 * the right bias: interiors are where the walls are.
 *
 * NOT ENOUGH ON ITS OWN, and this cost a measured 1-7% of wall spans before it
 * was caught: the obstruction can stand in OUR cell rather than the neighbour's.
 * Each cell pair is probed exactly once, from the +x/+z side, so nothing else
 * covers that case. The caller therefore ORs in whether our own cell has
 * anything overhead — see selfAbove in stepWalls. */
static int needProbe(const rcHeightfield& hf, int nx, int nz, int smax, int climbCells) {
    if (nx < 0 || nz < 0 || nx >= hf.width || nz >= hf.height) return 1;  /* off-grid: be safe */
    int hasNear = 0, hasAbove = 0;
    for (const rcSpan* s = hf.spans[nx + nz * hf.width]; s; s = s->next) {
        int d = (int)s->smax - smax;
        if (d < 0) d = -d;
        if (d <= climbCells) hasNear = 1;
        if ((int)s->smax > smax + climbCells) hasAbove = 1;
    }
    return (!hasNear) || hasAbove;
}

static void probeWall(float wx, float wy, float z, int dCellX, int dCellZ) {
    /* rc.x is wow.y and rc.z is wow.x, so a +x cell step moves wow.y. */
    const float nwy = wy + (float)dCellX * CELL_SIZE;
    const float nwx = wx + (float)dCellZ * CELL_SIZE;
    const float pz  = z + wallProbeHeight();

    float hit[3];
    s_job.wallRays++;
    if (dinkr_RayCastRaw(wx, wy, pz, nwx, nwy, pz, 0, hit) != 1) return;

    /* Use the HIT POINT to pick the cell, not the origin or the neighbour: a
     * wall lying anywhere between the two centres lands in whichever cell
     * actually contains it. */
    const int hx = (int)floorf((hit[1] - s_job.bmin[0]) / CELL_SIZE);
    const int hz = (int)floorf((hit[0] - s_job.bmin[2]) / CELL_SIZE);
    queueObstruction(hx, hz, z);
}

static void stepWalls(double budgetMs) {
    double t0 = nowMs();
    rcHeightfield& hf = *s_job.hf;
    const int walkableHeightCells = (int)ceilf(AGENT_HEIGHT / CELL_HEIGHT);
    const int climbCells = (int)floorf(AGENT_CLIMB / CELL_HEIGHT);

    while (s_job.cursor < s_job.total) {
        int i  = s_job.cursor++;
        int ix = i % s_job.w;
        int iz = i / s_job.w;

        float rcx = s_job.bmin[0] + ((float)ix + 0.5f) * CELL_SIZE;
        float rcz = s_job.bmin[2] + ((float)iz + 0.5f) * CELL_SIZE;
        float wx = rcz, wy = rcx;

        for (rcSpan* s = hf.spans[ix + iz * hf.width]; s; s = s->next) {
            /* Headroom decides whether this surface is worth probing at all.
             * Roofs, ceilings and slab undersides are the bulk of the spans and
             * none of them can be stood on, so skipping them roughly halves the
             * probe count. The topmost span has open sky above it. */
            int headroom = s->next ? ((int)s->next->smin - (int)s->smax) : 0x7fff;
            if (headroom < walkableHeightCells) continue;

            float z = s_job.bmin[1] + (float)s->smax * CELL_HEIGHT;
            /* Only these four: together they cover every neighbour of every cell
             * exactly once across the grid, rather than testing each pair twice. */
            static const int DX[4] = { 1, 0, 1,  1 };
            static const int DZ[4] = { 0, 1, 1, -1 };
            const int dirs = s_diagProbe ? 4 : 2;

            /* Does THIS cell have geometry above the surface we are standing on?
             * If so the obstruction may be on our side of the boundary, and no
             * amount of looking at the neighbour will reveal it. */
            int selfAbove = 0;
            for (const rcSpan* o = hf.spans[ix + iz * hf.width]; o; o = o->next) {
                if ((int)o->smax > (int)s->smax + climbCells) { selfAbove = 1; break; }
            }

            for (int d = 0; d < dirs; ++d) {
                if (s_probeSkip && !selfAbove &&
                    !needProbe(hf, ix + DX[d], iz + DZ[d], (int)s->smax, climbCells)) {
                    s_job.wallSkipped++;
                    continue;
                }
                probeWall(wx, wy, z, DX[d], DZ[d]);
            }
        }

        if (nowMs() - t0 >= budgetMs) break;
    }
    s_job.wallMs += nowMs() - t0;

    if (s_job.cursor < s_job.total) return;

    /* Apply the obstructions only now that raking is finished.
     * ORDER IS LOAD-BEARING. addSpan merges overlapping spans and keeps the NEW
     * span's area unless the two tops are within flagMergeThreshold. An
     * obstruction added BEFORE the floor span in its cell would merge and come
     * back RC_WALKABLE_AREA — the wall would erase itself and the bug would look
     * exactly like the wall pass doing nothing. */
    for (int i = 0; i < s_job.obsCount; ++i) {
        const Obstruction* o = &s_job.obs[i];
        int ix = o->cell % s_job.w, iz = o->cell / s_job.w;
        int smin = (int)floorf((o->z - s_job.bmin[1]) / CELL_HEIGHT);
        int smax = (int)ceilf((o->z + AGENT_HEIGHT - s_job.bmin[1]) / CELL_HEIGHT);
        if (smin < 0) smin = 0;
        if (smax > 0x1fff) smax = 0x1fff;
        if (smax <= smin) continue;
        if (rcAddSpan(&s_rcCtx, hf, ix, iz, (unsigned short)smin, (unsigned short)smax,
                      RC_NULL_AREA, 1))
            s_job.wallSpans++;
    }
    free(s_job.obs); s_job.obs = NULL; s_job.obsCount = 0; s_job.obsCap = 0;

    s_job.phase = LM_BUILD;
    setStatus("livemesh: building %d_%d (%d spans, %d walls, %d rays, %d probes skipped)",
              s_job.tx, s_job.tz, s_job.spans, s_job.wallSpans,
              s_job.rays + s_job.wallRays, s_job.wallSkipped);
}

/* ---- slope ---------------------------------------------------------------
 * Recast normally gets walkability from triangle normals (rcMarkWalkableTriangles).
 * We have no triangles — only surface points — so slope has to come from the
 * height difference to neighbouring columns.
 *
 * rcFilterLedgeSpans does something similar and would catch the worst of it,
 * but it is governed by walkableClimb, which also has to stay large enough for
 * stairs (1 yd). Sharing one number between "how tall a step can I take" and
 * "how steep a hill can I walk" makes both wrong, so slope gets its own pass. */
static void markSteepSpans(rcHeightfield& hf, float maxSlopeDeg) {
    const float maxDz = tanf(maxSlopeDeg * 3.14159265f / 180.0f) * CELL_SIZE;
    const int   maxDzCells = (int)ceilf(maxDz / CELL_HEIGHT);
    const int dx[4] = { -1, 1, 0, 0 };
    const int dz[4] = { 0, 0, -1, 1 };

    for (int z = 0; z < hf.height; ++z) {
        for (int x = 0; x < hf.width; ++x) {
            for (rcSpan* s = hf.spans[x + z * hf.width]; s; s = s->next) {
                if (s->area == RC_NULL_AREA) continue;
                int top = (int)s->smax;
                int worst = 0;
                for (int d = 0; d < 4; ++d) {
                    int nx = x + dx[d], nz = z + dz[d];
                    if (nx < 0 || nz < 0 || nx >= hf.width || nz >= hf.height) continue;
                    /* Compare against the neighbour span CLOSEST in height, not
                     * the topmost: on a bridge over a road, the topmost neighbour
                     * span belongs to a different surface entirely. */
                    int best = -1;
                    for (rcSpan* ns = hf.spans[nx + nz * hf.width]; ns; ns = ns->next) {
                        int d2 = (int)ns->smax - top;
                        if (d2 < 0) d2 = -d2;
                        if (best < 0 || d2 < best) best = d2;
                    }
                    if (best > worst) worst = best;
                }
                /* No neighbour at all means an isolated speck, which is not
                 * something we want to walk on either. */
                if (worst > maxDzCells) s->area = RC_NULL_AREA;
            }
        }
    }
}

/* ---- phase: build --------------------------------------------------------- */
static int writeTileFile(int mapId, int tx, int tz, const unsigned char* data, int len);

/* ---- the Recast build, on a worker thread ---------------------------------
 * Raking has to stay on the main thread because World_Intersect reads live
 * client state. The Recast pipeline does not: from here on we only touch our own
 * heightfield, so it can run off-thread while the game keeps rendering.
 *
 * That matters because this phase cannot be sliced — Recast has no resumable
 * entry points — and it measured 91-304 ms per tile, which is a visible stutter
 * every time a tile finishes.
 *
 * Win32 threads rather than std::thread: the DLL is built -fno-exceptions, and
 * std::thread's constructor throws on failure, which would abort instead.
 */
struct BuildResult {
    volatile LONG done;      /* 0 running, 1 finished — the only cross-thread flag */
    int  ok;
    char msg[256];
};
static BuildResult s_build;

/* The worker must not write s_status: the main thread reads it every frame for
 * /lm gen status. It gets its own buffer, copied across after the join. */
static void buildStatus(const char* fmt, ...) {
    va_list ap; va_start(ap, fmt);
    vsnprintf(s_build.msg, sizeof(s_build.msg), fmt, ap);
    va_end(ap);
}

static void runBuild(void) {
    double t0 = nowMs();
    rcHeightfield& hf = *s_job.hf;

    const int walkableHeightCells = (int)ceilf(AGENT_HEIGHT / CELL_HEIGHT);
    const int walkableClimbCells  = (int)floorf(AGENT_CLIMB  / CELL_HEIGHT);
    const int walkableRadiusCells = (int)ceilf(AGENT_RADIUS / CELL_SIZE);

    markSteepSpans(hf, MAX_SLOPE_DEG);
    rcFilterLowHangingWalkableObstacles(&s_rcCtx, walkableClimbCells, hf);
    rcFilterLedgeSpans(&s_rcCtx, walkableHeightCells, walkableClimbCells, hf);
    rcFilterWalkableLowHeightSpans(&s_rcCtx, walkableHeightCells, hf);

    rcCompactHeightfield* chf = rcAllocCompactHeightfield();
    if (!chf || !rcBuildCompactHeightfield(&s_rcCtx, walkableHeightCells,
                                           walkableClimbCells, hf, *chf)) {
        buildStatus("livemesh: compact heightfield failed");
        if (chf) rcFreeCompactHeightfield(chf);
        s_build.ok = 0; return;
    }
    rcFreeHeightField(s_job.hf); s_job.hf = NULL;

    if (!rcErodeWalkableArea(&s_rcCtx, walkableRadiusCells, *chf) ||
        !rcBuildDistanceField(&s_rcCtx, *chf) ||
        !rcBuildRegions(&s_rcCtx, *chf, s_job.borderSize, 8 * 8, 20 * 20)) {
        buildStatus("livemesh: region build failed");
        rcFreeCompactHeightfield(chf);
        s_build.ok = 0; return;
    }

    rcContourSet* cset = rcAllocContourSet();
    if (!cset || !rcBuildContours(&s_rcCtx, *chf, 1.3f, (int)(12.0f / CELL_SIZE), *cset)) {
        buildStatus("livemesh: contours failed");
        if (cset) rcFreeContourSet(cset);
        rcFreeCompactHeightfield(chf);
        s_build.ok = 0; return;
    }
    if (cset->nconts == 0) {
        /* Not an error: a tile can legitimately hold no walkable ground (open
         * water, sheer cliff). Emit nothing and record it so the scheduler does
         * not keep retrying the same empty tile. */
        buildStatus("livemesh: tile %d_%d has no walkable area", s_job.tx, s_job.tz);
        rcFreeContourSet(cset); rcFreeCompactHeightfield(chf);
        s_job.buildMs += nowMs() - t0;
        s_build.ok = 1;
        return;
    }

    rcPolyMesh* pmesh = rcAllocPolyMesh();
    if (!pmesh || !rcBuildPolyMesh(&s_rcCtx, *cset, 6, *pmesh)) {
        buildStatus("livemesh: poly mesh failed");
        if (pmesh) rcFreePolyMesh(pmesh);
        rcFreeContourSet(cset); rcFreeCompactHeightfield(chf);
        s_build.ok = 0; return;
    }
    rcPolyMeshDetail* dmesh = rcAllocPolyMeshDetail();
    if (!dmesh || !rcBuildPolyMeshDetail(&s_rcCtx, *pmesh, *chf,
                                         6.0f * CELL_SIZE, 1.0f * CELL_HEIGHT, *dmesh)) {
        buildStatus("livemesh: detail mesh failed");
        if (dmesh) rcFreePolyMeshDetail(dmesh);
        rcFreePolyMesh(pmesh); rcFreeContourSet(cset); rcFreeCompactHeightfield(chf);
        s_build.ok = 0; return;
    }
    rcFreeContourSet(cset);
    rcFreeCompactHeightfield(chf);

    /* Detour refuses a poly whose area is 0, and every walkable poly needs a
     * non-zero flag or findPath's filter rejects it. */
    for (int i = 0; i < pmesh->npolys; ++i) {
        if (pmesh->areas[i] == RC_WALKABLE_AREA) pmesh->flags[i] = 1;
    }

    dtNavMeshCreateParams p;
    memset(&p, 0, sizeof(p));
    p.verts = pmesh->verts;   p.vertCount = pmesh->nverts;
    p.polys = pmesh->polys;   p.polyCount = pmesh->npolys;
    p.polyAreas = pmesh->areas; p.polyFlags = pmesh->flags;
    p.nvp = pmesh->nvp;
    p.detailMeshes = dmesh->meshes; p.detailVerts = dmesh->verts;
    p.detailVertsCount = dmesh->nverts;
    p.detailTris = dmesh->tris; p.detailTriCount = dmesh->ntris;
    p.walkableHeight = AGENT_HEIGHT;
    p.walkableRadius = AGENT_RADIUS;
    p.walkableClimb  = AGENT_CLIMB;
    p.tileX = s_job.tx; p.tileY = s_job.tz; p.tileLayer = 0;
    rcVcopy(p.bmin, pmesh->bmin);
    rcVcopy(p.bmax, pmesh->bmax);
    p.cs = CELL_SIZE; p.ch = CELL_HEIGHT;
    p.buildBvTree = true;

    unsigned char* navData = NULL; int navSize = 0;
    bool ok = dtCreateNavMeshData(&p, &navData, &navSize);
    s_job.polys = pmesh->npolys;
    rcFreePolyMesh(pmesh);
    rcFreePolyMeshDetail(dmesh);

    if (!ok || !navData) {
        buildStatus("livemesh: dtCreateNavMeshData failed (%d polys)", s_job.polys);
        s_build.ok = 0; return;
    }

    int wrote = writeTileFile(s_job.mapId, s_job.tx, s_job.tz, navData, navSize);
    dtFree(navData);
    s_job.buildMs += nowMs() - t0;

    if (!wrote) {
        buildStatus("livemesh: could not write tile %d_%d to %s", s_job.tx, s_job.tz, s_cacheDir);
        s_build.ok = 0; return;
    }
    buildStatus("livemesh: tile %d_%d done — %d polys, rake %.0f ms, build %.0f ms",
              s_job.tx, s_job.tz, s_job.polys, s_job.rakeMs, s_job.buildMs);
    s_build.ok = 1;
}


/* THREADING IS OFF, and this is not caution — it crashed the client.
 *
 * Referencing CreateThread makes the linker pull in MinGW's CRT thread-support
 * initialisation. That runs at DLL_PROCESS_ATTACH and does
 *     GetModuleHandleA("kernel32.dll")
 *     GetProcAddress(h, "GetHandleInformation" / "GetTickCount64" /
 *                       "SetThreadDescription")
 * dinkr.dll is MANUALLY MAPPED, so it is not in the loader's module list, and
 * that init faults inside ntdll before our entry point can return:
 *     [gui] FAIL: CallDllEntryPoint failed (all threads)
 *     ACCESS_VIOLATION reading 0xffffffffffffffff
 *     ntdll <- ntdll <- KERNELBASE <- dinkr.dll+0x70E77
 * Disassembly at that RVA is exactly the GetModuleHandleA/GetProcAddress pair
 * above, so there is no ambiguity about the cause.
 *
 * Getting the Recast build off the main thread therefore needs a thread owned by
 * something already in the loader's list — the GUI process over the IPC channel,
 * or a game thread we borrow — not CreateThread from inside this module. That is
 * a bigger change than the 91-304 ms it buys.
 *
 * Flip to 1 ONLY once that is solved; the code below is kept so the work is not
 * lost, but it must not ship enabled. */
#if LM_BUILD_THREAD
static DWORD WINAPI buildThreadMain(LPVOID) {
    runBuild();
    /* InterlockedExchange is a full barrier on x86, so everything runBuild wrote
     * is visible to the main thread before it can observe done == 1. */
    InterlockedExchange(&s_build.done, 1);
    return 0;
}

static void stepBuild(void) {
    if (!s_buildThread) {
        s_build.done = 0; s_build.ok = 0; s_build.msg[0] = 0;
        s_buildThread = CreateThread(NULL, 0, buildThreadMain, NULL, 0, NULL);
        if (s_buildThread) return;              /* poll on later frames */
        runBuild();
        InterlockedExchange(&s_build.done, 1);
    }
    if (InterlockedCompareExchange(&s_build.done, 1, 1) == 0) return;   /* still working */

    if (s_buildThread) {
        WaitForSingleObject(s_buildThread, INFINITE);
        CloseHandle(s_buildThread);
        s_buildThread = NULL;
    }
    strncpy(s_status, s_build.msg, sizeof(s_status) - 1);
    s_status[sizeof(s_status) - 1] = 0;
    s_job.phase = s_build.ok ? LM_DONE : LM_FAILED;
}
#else
/* Inline: one indivisible Recast run on the main thread. Costs a 91-304 ms hitch
 * per finished tile — visible, but survivable, unlike a client that will not
 * start at all. */
static void stepBuild(void) {
    runBuild();
    strncpy(s_status, s_build.msg, sizeof(s_status) - 1);
    s_status[sizeof(s_status) - 1] = 0;
    s_job.phase = s_build.ok ? LM_DONE : LM_FAILED;
}
#endif /* LM_BUILD_THREAD */

/* ---- tile file -----------------------------------------------------------
 * Written with the SAME 20-byte header the mmtile path already parses (magic
 * 'MMAP', dtVersion, then native dtMeshData), so ensureTile loads a generated
 * tile through the identical code path — no second parser, no translation. */

static void ensureDir(const char* path) { CreateDirectoryA(path, NULL); }

/* PROVENANCE. A tile baked while its far side was outside doodad streaming
 * range is quietly incomplete — props, fences and carts that were never loaded
 * simply are not in it — and it would otherwise sit in the cache forever looking
 * perfectly valid. Recording how far the player was lets the generator refresh a
 * tile later when it can do a better job.
 *
 * It goes in the usesLiquids slot: the field exists so the header stays the
 * 20 bytes ensureTile skips, but nothing on our side reads it as a liquid flag. */
static int writeTileFile(int mapId, int tx, int tz, const unsigned char* data, int len) {
    char dir[300], path[300];
    ensureDir(s_cacheDir);
    snprintf(dir, sizeof(dir), "%s\\%d", s_cacheDir, mapId);
    ensureDir(dir);
    tilePath(path, sizeof(path), mapId, tx, tz);

    FILE* f = fopen(path, "wb");
    if (!f) return 0;
    LmTileHeader h;
    h.magic = 0x4D4D4150u;             /* 'MMAP' little-endian, as ensureTile reads it */
    h.dtVersion = DT_NAVMESH_VERSION;
    h.lmVersion = 1;
    h.size = (unsigned int)len;
    {
        float d = s_job.genDist;
        if (!(d >= 0.0f)) d = 0.0f;          /* also catches NaN */
        if (d > 40000.0f) d = 40000.0f;
        h.usesLiquids = (unsigned int)(d * 100.0f);   /* hundredths of a yard */
    }
    int ok = (fwrite(&h, sizeof(h), 1, f) == 1) &&
             (fwrite(data, 1, (size_t)len, f) == (size_t)len);
    fclose(f);
    if (!ok) remove(path);
    return ok;
}

/* ---- driver --------------------------------------------------------------- */
int DinkrLiveMeshStep(double budgetMs) {
    if (!s_busy) return LM_IDLE;
    if (budgetMs < 0.5) budgetMs = 0.5;

    switch (s_job.phase) {
        case LM_PROBE: stepProbe(budgetMs); break;
        case LM_RAKE:  stepRake(budgetMs);  break;
        case LM_WALLS: stepWalls(budgetMs); break;
        /* BUILD is one indivisible Recast run. It cannot honour the budget —
         * Recast has no resumable entry points — so this is the one place that
         * can hitch the client. Measure it with DinkrLiveMeshLastStats before
         * deciding whether it needs to move to a worker thread; Recast touches
         * only our own buffers, so that move is safe when the time says so. */
        case LM_BUILD: stepBuild(); break;
        default: break;
    }

    if (s_job.phase == LM_DONE || s_job.phase == LM_FAILED) {
        s_lastRake = s_job.rakeMs; s_lastBuild = s_job.buildMs;
        s_lastRays = s_job.rays + s_job.wallRays; s_lastSpans = s_job.spans;
        s_lastPolys = s_job.polys;
        s_lastWallMs = s_job.wallMs; s_lastWallSpans = s_job.wallSpans;
        if (s_job.obs) { free(s_job.obs); s_job.obs = NULL; }
        int phase = s_job.phase;
        if (s_job.hf) { rcFreeHeightField(s_job.hf); s_job.hf = NULL; }
        s_busy = 0;
        return phase;
    }
    return s_job.phase;
}
