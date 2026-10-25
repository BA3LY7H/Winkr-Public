/* dinkr_nav.h — Detour navmesh pathfinding (C-callable facade over C++ Detour).
 *
 * Tiles are WowClassicGrindBot/DotRecast ".dnm" files staged as
 *   <root>/<mapId>/tile_<tx>_<tz>.dnm      (default root: C:\projects\navmesh)
 * They are DotRecast's PACKED serialization, not raw dtMeshData, so each tile is
 * translated to Detour's in-memory layout before dtNavMesh::addTile.
 *
 * COORDINATES: these tiles use a pure cyclic swap with NO negation
 *   rc = (wow.y, wow.z, wow.x)   /   wow = (rc.z, rc.x, rc.y)
 * This is NOT the TrinityCore mmap convention (-wow.y, wow.z, -wow.x).
 * All functions here take and return WOW coordinates; the swap is internal.
 */
#ifndef DINKR_NAV_H
#define DINKR_NAV_H

#ifdef __cplusplus
extern "C" {
#endif

/* Status bits — mirrors TrinityCore PathType, which awful's util/nav.lua
 * already mirrors (PathTypes at nav.lua:10-18), so values pass straight through. */
#define WK_PATH_BLANK          0x00
#define WK_PATH_NORMAL         0x01
#define WK_PATH_SHORTCUT       0x02
#define WK_PATH_INCOMPLETE     0x04
#define WK_PATH_NOPATH         0x08
#define WK_PATH_NOT_USING_PATH 0x10
#define WK_PATH_SHORT          0x20
#define WK_PATH_FARFROMPOLY    0x40

/* Find a walkable path between two WOW-space points on mapId.
 * Writes up to maxPts (x,y,z) triples into outXYZ (WOW coords, 3 floats each).
 * Returns a WK_PATH_* status; *outCount receives the number of points written. */
int DinkrNavFindPath(int mapId,
                     float sx, float sy, float sz,
                     float gx, float gy, float gz,
                     float* outXYZ, int maxPts, int* outCount);

/* Snap a WOW point to the nearest walkable position (height correction / reachability).
 * Returns 1 on success and fills out[3] with WOW coords. */
int DinkrNavNearestPoint(int mapId, float x, float y, float z, float* out3);

/* Corner clearance: how far interior path corners are pushed off walls, in
 * yards (default 1.5). The baked tiles are eroded only 0.5333 yd — TrinityCore's
 * exact value, tight for keyboard steering — so this is what stops the follower
 * hugging fences and clipping doorframes. 0 disables. */
void  DinkrNavSetEdgeMargin(float yards);
float DinkrNavGetEdgeMargin(void);

/* Diagnostics -------------------------------------------------------------- */
/* The most recent path request (start xyz, goal xyz), whether it succeeded or
 * not. Every nav consumer funnels through DinkrNavFindPath, so this is how
 * LiveMesh learns where to generate for ALL of them. 0 when nothing asked yet. */
/* Distance from a WOW-space point to the nearest mesh edge, plus a unit normal
 * pointing away from it. The edge margin applies this to findStraightPath corners
 * only; exposing it lets the path builder clear the densified points it actually
 * drives. Returns 0 when no poly is near. */
int         DinkrNavDistanceToWall(int mapId, float x, float y, float z,
                                   float maxRadius, float* outDist, float* outNormal3);

int         DinkrNavLastRequest(float* out6);

int         DinkrNavTilesLoaded(int mapId); /* tiles currently resident, -1 if map unknown */

/* Dump the walkable polygons near a point so the mesh can be DRAWN.
 *
 * Nothing in the stack could show what the mesh actually looks like -- every
 * judgement about it came from numbers. This walks the resident tiles and emits
 * each polygon as a vertex ring, flagging which edges are mesh BOUNDARY (a wall
 * or a hole) so a viewer can paint interior and boundary differently.
 *
 * out layout, 4 floats per vertex: x, y, z, wall
 *   wall = 1.0 on the edge LEAVING this vertex if that edge has no neighbour.
 * outCounts receives the vertex count of each polygon, in order.
 * Returns the number of polygons written; 0 if the map has no resident tiles.
 * Tiles are loaded on demand for the requested area, exactly as a path query
 * would, so calling this does not show a different mesh from the one used. */
int         DinkrNavDumpPolys(int mapId, float cx, float cy, float radius,
                              float* out, int maxVerts,
                              int* outCounts, int maxPolys);
const char* DinkrNavStatusText(void);       /* last operation detail (never NULL) */
void        DinkrNavSetRoot(const char* dir);
void        DinkrNavShutdown(void);

#ifdef __cplusplus
}
#endif
#endif /* DINKR_NAV_H */
