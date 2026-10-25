/* dinkr_bridge_nav.c — Lua glue for the Detour navmesh (dll/nav/dinkr_nav.cpp).
 *
 * Registered globals:
 *   dinkr_GeneratePath(sx,sy,sz, gx,gy,gz, mapId) -> { {x=,y=,z=}, ... }, status
 *        Shaped to match what awful's util/nav.lua expects from
 *        GeneratePathWeighted: an array of points plus a PathType status whose
 *        bits are TrinityCore's (awful mirrors them at nav.lua:10-18).
 *   dinkr_NavNearest(x,y,z, mapId) -> x,y,z | nil     (snap to walkable ground)
 *   dinkr_NavStatus() -> statusText, tilesLoadedMap0, tilesLoadedMap1
 */
#include <string.h>
#include "dinkr_internal.h"
#include "dinkr_bridge.h"
#include "../nav/dinkr_nav.h"
#include "../nav/dinkr_livemesh.h"

#define NAV_MAX_PTS 256

int __fastcall dinkr_GeneratePath_lua(void* L) {
    const double sx = dinkr_read_stack_number(L, 1), sy = dinkr_read_stack_number(L, 2), sz = dinkr_read_stack_number(L, 3);
    const double gx = dinkr_read_stack_number(L, 4), gy = dinkr_read_stack_number(L, 5), gz = dinkr_read_stack_number(L, 6);
    const int mapId = (int)dinkr_read_stack_number(L, 7);

    static float pts[NAV_MAX_PTS * 3];
    int count = 0;
    const int status = DinkrNavFindPath(mapId,
                                        (float)sx, (float)sy, (float)sz,
                                        (float)gx, (float)gy, (float)gz,
                                        pts, NAV_MAX_PTS, &count);

    /* array of {x=,y=,z=} — the shape awful's Path wrapper consumes */
    s_pCreatetable(L, count, 0);
    for (int i = 0; i < count; ++i) {
        s_pCreatetable(L, 0, 3);
        s_pPushnumber(L, (double)pts[i * 3 + 0]); s_pSetField(L, -2, "x");
        s_pPushnumber(L, (double)pts[i * 3 + 1]); s_pSetField(L, -2, "y");
        s_pPushnumber(L, (double)pts[i * 3 + 2]); s_pSetField(L, -2, "z");
        s_pRawseti(L, -2, i + 1);
    }
    s_pPushnumber(L, (double)status);
    return 2;
}

/* dinkr_NavPolys(x, y, radius, mapId) -> { {  {x=,y=,z=,wall=}, ... }, ... }
 *
 * One inner table per polygon, one entry per vertex, in ring order. `wall` is 1
 * when the edge LEAVING that vertex is a mesh boundary, which is what lets a
 * viewer draw interior edges and walls differently.
 *
 * Caps are deliberate and generous rather than dynamic: a 100 yd radius in a
 * city is a few thousand polys, and a Lua table per poly is the expensive part,
 * not the C walk. Overrun truncates rather than failing, so a careless radius
 * degrades the picture instead of the frame. */
#define NAV_DUMP_MAX_POLYS 4096
#define NAV_DUMP_MAX_VERTS (NAV_DUMP_MAX_POLYS * 6)

int __fastcall dinkr_NavPolys_lua(void* L) {
    const double x = dinkr_read_stack_number(L, 1);
    const double y = dinkr_read_stack_number(L, 2);
    double radius  = dinkr_read_stack_number(L, 3);
    const int mapId = (int)dinkr_read_stack_number(L, 4);
    if (radius <= 0.0 || radius > 600.0) radius = 100.0;

    static float verts[NAV_DUMP_MAX_VERTS * 4];
    static int   counts[NAV_DUMP_MAX_POLYS];

    const int nPolys = DinkrNavDumpPolys(mapId, (float)x, (float)y, (float)radius,
                                         verts, NAV_DUMP_MAX_VERTS,
                                         counts, NAV_DUMP_MAX_POLYS);

    s_pCreatetable(L, nPolys, 0);
    int cursor = 0;
    for (int i = 0; i < nPolys; ++i) {
        const int n = counts[i];
        s_pCreatetable(L, n, 0);
        for (int k = 0; k < n; ++k) {
            const float* v = &verts[(cursor + k) * 4];
            s_pCreatetable(L, 0, 4);
            s_pPushnumber(L, (double)v[0]); s_pSetField(L, -2, "x");
            s_pPushnumber(L, (double)v[1]); s_pSetField(L, -2, "y");
            s_pPushnumber(L, (double)v[2]); s_pSetField(L, -2, "z");
            s_pPushnumber(L, (double)v[3]); s_pSetField(L, -2, "wall");
            s_pRawseti(L, -2, k + 1);
        }
        cursor += n;
        s_pRawseti(L, -2, i + 1);
    }
    return 1;
}

int __fastcall dinkr_NavNearest_lua(void* L) {
    const double x = dinkr_read_stack_number(L, 1), y = dinkr_read_stack_number(L, 2), z = dinkr_read_stack_number(L, 3);
    const int mapId = (int)dinkr_read_stack_number(L, 4);
    float out[3] = { 0, 0, 0 };
    if (!DinkrNavNearestPoint(mapId, (float)x, (float)y, (float)z, out)) {
        s_pPushnil(L);
        return 1;
    }
    s_pPushnumber(L, (double)out[0]);
    s_pPushnumber(L, (double)out[1]);
    s_pPushnumber(L, (double)out[2]);
    return 3;
}

int __fastcall dinkr_NavStatus_lua(void* L) {
    s_pPushstring(L, DinkrNavStatusText());
    s_pPushnumber(L, (double)DinkrNavTilesLoaded(0));
    s_pPushnumber(L, (double)DinkrNavTilesLoaded(1));
    return 3;
}

/* ========================================================================
** LiveMesh — runtime navmesh generation (dll/nav/dinkr_livemesh.cpp)
**
** The !projects/LiveMesh Lua project owns the policy: which tile to build,
** when, and how much frame time to spend. This is only the handle.
**
**   dinkr_LiveMeshBegin(mapId, tx, tz)     -> 1 started | 0 busy/failed
**   dinkr_LiveMeshStep(budgetMs)           -> phase, done, total
**   dinkr_LiveMeshStatus()                 -> text, phase, rakeMs, buildMs,
**                                             rays, spans, polys
**   dinkr_LiveMeshTileAt(wx, wy)           -> tx, tz
**   dinkr_LiveMeshHave(mapId, tx, tz)      -> 1 | 0     (already on disk)
**   dinkr_LiveMeshCancel()
** ======================================================================== */
int __fastcall dinkr_LiveMeshBegin_lua(void* L) {
    const int mapId = (int)dinkr_read_stack_number(L, 1);
    const int tx    = (int)dinkr_read_stack_number(L, 2);
    const int tz    = (int)dinkr_read_stack_number(L, 3);
    const float gd  = (float)dinkr_read_stack_number(L, 4);
    s_pPushnumber(L, (double)DinkrLiveMeshBegin(mapId, tx, tz, gd));
    return 1;
}

int __fastcall dinkr_LiveMeshStep_lua(void* L) {
    double budget = dinkr_read_stack_number(L, 1);
    if (budget <= 0) budget = 4.0;
    const int phase = DinkrLiveMeshStep(budget);
    int done = 0, total = 0;
    DinkrLiveMeshProgress(&done, &total);
    s_pPushnumber(L, (double)phase);
    s_pPushnumber(L, (double)done);
    s_pPushnumber(L, (double)total);
    return 3;
}

int __fastcall dinkr_LiveMeshStatus_lua(void* L) {
    double rake = 0, build = 0, wallMs = 0;
    int rays = 0, spans = 0, polys = 0, wallSpans = 0;
    DinkrLiveMeshLastStats(&rake, &build, &rays, &spans, &polys, &wallMs, &wallSpans);
    s_pPushstring(L, DinkrLiveMeshStatusText());
    s_pPushnumber(L, (double)DinkrLiveMeshPhase());
    s_pPushnumber(L, rake);
    s_pPushnumber(L, build);
    s_pPushnumber(L, (double)rays);
    s_pPushnumber(L, (double)spans);
    s_pPushnumber(L, (double)polys);
    s_pPushnumber(L, wallMs);
    s_pPushnumber(L, (double)wallSpans);
    s_pPushnumber(L, (double)DinkrLiveMeshGetWalls());
    return 10;
}

int __fastcall dinkr_LiveMeshTileAt_lua(void* L) {
    const float wx = (float)dinkr_read_stack_number(L, 1);
    const float wy = (float)dinkr_read_stack_number(L, 2);
    int tx = 0, tz = 0;
    DinkrLiveMeshTileIndex(wx, wy, &tx, &tz);
    s_pPushnumber(L, (double)tx);
    s_pPushnumber(L, (double)tz);
    return 2;
}

int __fastcall dinkr_LiveMeshHave_lua(void* L) {
    const int mapId = (int)dinkr_read_stack_number(L, 1);
    const int tx    = (int)dinkr_read_stack_number(L, 2);
    const int tz    = (int)dinkr_read_stack_number(L, 3);
    s_pPushnumber(L, (double)DinkrLiveMeshHaveTile(mapId, tx, tz));
    return 1;
}

int __fastcall dinkr_LiveMeshCancel_lua(void* L) {
    DinkrLiveMeshCancel();
    s_pPushnumber(L, 1.0);
    return 1;
}

/* dinkr_LiveMeshWalls(on) -> the setting after applying it.
 * Always sets; the Lua side passes an explicit 1 or 0, and reads the current
 * value out of dinkr_LiveMeshStatus() rather than calling this with no
 * argument. */
int __fastcall dinkr_LiveMeshWalls_lua(void* L) {
    DinkrLiveMeshSetWalls((int)dinkr_read_stack_number(L, 1));
    s_pPushnumber(L, (double)DinkrLiveMeshGetWalls());
    return 1;
}

/* dinkr_LiveMeshAgent(radius) -> the radius in effect. 0 just reads it. */
int __fastcall dinkr_LiveMeshAgent_lua(void* L) {
    const double r = dinkr_read_stack_number(L, 1);
    if (r > 0) DinkrLiveMeshSetAgentRadius((float)r);
    s_pPushnumber(L, (double)DinkrLiveMeshGetAgentRadius());
    return 1;
}

/* dinkr_LiveMeshClimb(yards) -> the step height in effect. 0 just reads it. */
int __fastcall dinkr_LiveMeshClimb_lua(void* L) {
    const double c = dinkr_read_stack_number(L, 1);
    if (c > 0) DinkrLiveMeshSetClimb((float)c);
    s_pPushnumber(L, (double)DinkrLiveMeshGetClimb());
    return 1;
}

/* dinkr_LiveMeshDiagonals(on) -> the setting after applying it. */
int __fastcall dinkr_LiveMeshDiagonals_lua(void* L) {
    DinkrLiveMeshSetDiagonals((int)dinkr_read_stack_number(L, 1));
    s_pPushnumber(L, (double)DinkrLiveMeshGetDiagonals());
    return 1;
}

/* dinkr_LiveMeshProbeSkip(on) -> the setting after applying it. */
int __fastcall dinkr_LiveMeshProbeSkip_lua(void* L) {
    DinkrLiveMeshSetProbeSkip((int)dinkr_read_stack_number(L, 1));
    s_pPushnumber(L, (double)DinkrLiveMeshGetProbeSkip());
    return 1;
}

/* dinkr_LiveMeshTileInfo(mapId, tx, tz) -> cx, cy, genDist
 * genDist is -1 when no tile is cached. The centre comes back too so the
 * scheduler never has to reimplement the tile grid. */
int __fastcall dinkr_LiveMeshTileInfo_lua(void* L) {
    const int mapId = (int)dinkr_read_stack_number(L, 1);
    const int tx    = (int)dinkr_read_stack_number(L, 2);
    const int tz    = (int)dinkr_read_stack_number(L, 3);
    float cx = 0, cy = 0;
    DinkrLiveMeshTileCenter(tx, tz, &cx, &cy);
    s_pPushnumber(L, (double)cx);
    s_pPushnumber(L, (double)cy);
    s_pPushnumber(L, (double)DinkrLiveMeshTileGenDist(mapId, tx, tz));
    return 3;
}

/* dinkr_NavLastRequest() -> sx,sy,sz, gx,gy,gz  |  nil
 * Whatever last asked for a path, succeeded or not. */
int __fastcall dinkr_NavLastRequest_lua(void* L) {
    float r[6];
    if (!DinkrNavLastRequest(r)) { s_pPushnil(L); return 1; }
    for (int i = 0; i < 6; ++i) s_pPushnumber(L, (double)r[i]);
    return 6;
}

/* dinkr_NavWallDist(x, y, z, mapId [, maxRadius]) -> dist, nx, ny, nz  |  nil
 * Distance to the nearest mesh edge and a unit normal pointing away from it. */
int __fastcall dinkr_NavWallDist_lua(void* L) {
    const float x = (float)dinkr_read_stack_number(L, 1);
    const float y = (float)dinkr_read_stack_number(L, 2);
    const float z = (float)dinkr_read_stack_number(L, 3);
    const int mapId = (int)dinkr_read_stack_number(L, 4);
    const float maxR = (float)dinkr_read_stack_number(L, 5);

    float d = 0.0f, n[3] = { 0, 0, 0 };
    if (!DinkrNavDistanceToWall(mapId, x, y, z, maxR, &d, n)) { s_pPushnil(L); return 1; }
    s_pPushnumber(L, (double)d);
    s_pPushnumber(L, (double)n[0]);
    s_pPushnumber(L, (double)n[1]);
    s_pPushnumber(L, (double)n[2]);
    return 4;
}
