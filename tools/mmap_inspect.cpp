// =============================================================================
// mmap_inspect — offline health check for the TrinityCore mmaps the DLL loads
// -----------------------------------------------------------------------------
// WHY THIS AND NOT RecastDemo:
//   RecastDemo reads Recast's own solo/tile format. A TrinityCore .mmtile is a
//   20-byte MmapTileHeader followed by NATIVE dtMeshData, and .mmap is a bare
//   28-byte dtNavMeshParams — so RecastDemo cannot open these without a custom
//   loader anyway, and it drags in SDL2 for a 3D view we do not need to answer
//   "are the meshes broken".
//
//   This links the SAME vendored Detour the injected DLL links, and mirrors
//   dll/nav/dinkr_nav.cpp's loader byte for byte. So a tile that fails here is a
//   tile that fails in game, and a path that fails here fails in game. That
//   equivalence is the whole point — a separate tool that loads them DIFFERENTLY
//   would just tell us about itself.
//
// Build (from the repo root):
//   g++ -O2 -DDT_POLYREF64 -std=c++17 -fno-exceptions -fno-rtti \
//       -IWinkr/vendor/detour/Include -o build/mmap_inspect.exe \
//       tools/mmap_inspect.cpp Winkr/vendor/detour/Source/*.cpp
//
// Use:
//   mmap_inspect 0                          coverage report for map 0
//   mmap_inspect 0 -8900 -160               which tile holds this point, is it on mesh
//   mmap_inspect 0 -8900 -160 76 -9040 -360 84    can Detour path between them
//
// Coordinates are WoW world coords (x y z), same order the Lua API uses.
// =============================================================================
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <cmath>
#include <vector>
#include <algorithm>
#include "DetourNavMesh.h"
#include "DetourNavMeshQuery.h"
#include "DetourCommon.h"

// Mirrors dinkr_nav.cpp. Do not "tidy" these to differ.
static const float MMAP_TILE_SIZE = 533.33333f;
static const int   NAV_MAX_TILES  = 4096;
static const int   NAV_MAX_POLYS  = 1 << 16;
static char        g_root[512]    = "C:\\projects\\mmaps";

static void tileIndex(float wx, float wy, int* row, int* col) {
    *row = (int)floorf(32.0f - wx / MMAP_TILE_SIZE);
    *col = (int)floorf(32.0f - wy / MMAP_TILE_SIZE);
}

static unsigned char* slurp(const char* path, long* outLen) {
    FILE* f = fopen(path, "rb");
    if (!f) return NULL;
    fseek(f, 0, SEEK_END); long len = ftell(f); fseek(f, 0, SEEK_SET);
    if (len <= 0 || len > (32 << 20)) { fclose(f); return NULL; }
    unsigned char* buf = (unsigned char*)malloc((size_t)len);
    if (!buf) { fclose(f); return NULL; }
    size_t rd = fread(buf, 1, (size_t)len, f);
    fclose(f);
    if (rd != (size_t)len) { free(buf); return NULL; }
    *outLen = len;
    return buf;
}

struct Stats {
    int found = 0, loaded = 0, badMagic = 0, badVersion = 0, addFailed = 0;
    int minRow = 99, maxRow = -1, minCol = 99, maxCol = -1;
    long long bytes = 0;
};

int main(int argc, char** argv) {
    if (argc < 2) {
        printf("usage: mmap_inspect <mapId> [x y [z]] [x2 y2 [z2]]  [--root <dir>]\n");
        return 2;
    }
    int mapId = atoi(argv[1]);

    // optional --root override
    for (int i = 2; i < argc - 1; ++i)
        if (!strcmp(argv[i], "--root")) { snprintf(g_root, sizeof(g_root), "%s", argv[i + 1]); }

    // ---- header ------------------------------------------------------------
    char hdrPath[600];
    snprintf(hdrPath, sizeof(hdrPath), "%s\\%04d.mmap", g_root, mapId);
    long hlen = 0;
    unsigned char* hraw = slurp(hdrPath, &hlen);
    if (!hraw) {
        printf("FAIL  no %04d.mmap in %s\n", mapId, g_root);
        printf("      the DLL reports this as \"nav: no mmaps for map %d\"\n", mapId);
        return 1;
    }
    dtNavMeshParams fp; memset(&fp, 0, sizeof(fp));
    memcpy(&fp, hraw, std::min((size_t)hlen, sizeof(fp)));
    free(hraw);

    printf("map %d   root %s\n", mapId, g_root);
    printf("header: orig(%.1f, %.1f, %.1f)  tile %.2f x %.2f  maxTiles %d  maxPolys %d\n",
           fp.orig[0], fp.orig[1], fp.orig[2], fp.tileWidth, fp.tileHeight,
           fp.maxTiles, fp.maxPolys);
    if (fp.maxPolys < 0)
        printf("  note: maxPolys is negative as a signed int — the DLL deliberately\n"
               "        ignores the file's maxTiles/maxPolys for exactly this reason\n");

    dtNavMeshParams p; memset(&p, 0, sizeof(p));
    p.orig[0] = fp.orig[0]; p.orig[1] = fp.orig[1]; p.orig[2] = fp.orig[2];
    p.tileWidth  = (fp.tileWidth  > 1.0f) ? fp.tileWidth  : MMAP_TILE_SIZE;
    p.tileHeight = (fp.tileHeight > 1.0f) ? fp.tileHeight : MMAP_TILE_SIZE;
    p.maxTiles = NAV_MAX_TILES; p.maxPolys = NAV_MAX_POLYS;

    dtNavMesh* mesh = dtAllocNavMesh();
    if (!mesh || dtStatusFailed(mesh->init(&p))) { printf("FAIL  navmesh init\n"); return 1; }

    // ---- load every tile on the 64x64 ADT grid -----------------------------
    Stats st;
    bool grid[64][64] = {};
    for (int row = 0; row < 64; ++row) {
        for (int col = 0; col < 64; ++col) {
            char tp[600];
            snprintf(tp, sizeof(tp), "%s\\%04d%02d%02d.mmtile", g_root, mapId, row, col);
            long len = 0;
            unsigned char* raw = slurp(tp, &len);
            if (!raw) continue;
            st.found++; st.bytes += len;

            if (len <= 20) { st.badMagic++; free(raw); continue; }
            const unsigned int magic = *(const unsigned int*)raw;
            const unsigned int dtver = *(const unsigned int*)(raw + 4);
            // 'M','M','A','P' little-endian is 0x4D4D4150. The byte-swapped
            // constant rejects every tile — that bug cost a full debugging round.
            if (magic != 0x4D4D4150u) { st.badMagic++; free(raw); continue; }
            if (dtver != DT_NAVMESH_VERSION) { st.badVersion++; free(raw); continue; }

            const int bodyLen = (int)len - 20;
            unsigned char* body = (unsigned char*)dtAlloc(bodyLen, DT_ALLOC_PERM);
            memcpy(body, raw + 20, (size_t)bodyLen);
            free(raw);

            dtTileRef ref = 0;
            if (dtStatusFailed(mesh->addTile(body, bodyLen, DT_TILE_FREE_DATA, 0, &ref))) {
                dtFree(body); st.addFailed++; continue;
            }
            st.loaded++; grid[row][col] = true;
            st.minRow = std::min(st.minRow, row); st.maxRow = std::max(st.maxRow, row);
            st.minCol = std::min(st.minCol, col); st.maxCol = std::max(st.maxCol, col);
        }
    }

    printf("\ntiles: %d on disk | %d loaded | %d bad magic | %d wrong dtVersion | %d addTile failed\n",
           st.found, st.loaded, st.badMagic, st.badVersion, st.addFailed);
    printf("size:  %.1f MB\n", st.bytes / 1048576.0);
    if (st.loaded == 0) { printf("\nno tiles loaded — this map is unusable\n"); return 1; }

    printf("extent: rows %d..%d, cols %d..%d\n", st.minRow, st.maxRow, st.minCol, st.maxCol);
    int span = (st.maxRow - st.minRow + 1) * (st.maxCol - st.minCol + 1);
    printf("fill:   %d of %d cells inside that box (%.0f%%) — holes are normal\n",
           st.loaded, span, 100.0 * st.loaded / (span ? span : 1));

    // ---- ASCII coverage map -------------------------------------------------
    printf("\ncoverage (# = tile present, . = hole)   cols %d..%d left to right\n",
           st.minCol, st.maxCol);
    for (int row = st.minRow; row <= st.maxRow; ++row) {
        printf("  row %2d ", row);
        for (int col = st.minCol; col <= st.maxCol; ++col) putchar(grid[row][col] ? '#' : '.');
        putchar('\n');
    }

    // ---- point / path queries ----------------------------------------------
    if (argc >= 5) {
        dtNavMeshQuery* q = dtAllocNavMeshQuery();
        if (dtStatusFailed(q->init(mesh, 2048))) { printf("\nFAIL query init\n"); return 1; }
        const float ext[3] = { 6.0f, 40.0f, 6.0f };
        dtQueryFilter filter;

        auto describe = [&](const char* label, float wx, float wy, float wz,
                            dtPolyRef* outRef, float* outPt) {
            int row, col; tileIndex(wx, wy, &row, &col);
            // Detour axes are (x, z, y) against WoW's (x, y, z)
            float pt[3] = { wy, wz, wx };
            dtStatus s = q->findNearestPoly(pt, ext, &filter, outRef, outPt);
            printf("\n%s (%.1f, %.1f, %.1f)\n", label, wx, wy, wz);
            printf("  tile %04d%02d%02d.mmtile  %s\n", mapId, row, col,
                   (row >= 0 && row < 64 && col >= 0 && col < 64 && grid[row][col])
                       ? "present" : "MISSING — no mesh here");
            if (dtStatusFailed(s) || !*outRef) {
                printf("  findNearestPoly: NO POLY within %.0f/%.0f yd\n", ext[0], ext[1]);
            } else {
                printf("  findNearestPoly: ok, snapped %.2f yd away\n",
                       dtVdist(pt, outPt));
            }
        };

        float ax = (float)atof(argv[2]), ay = (float)atof(argv[3]);
        float az = (argc >= 6 && argv[5][0] != '-') ? (float)atof(argv[4]) : (float)atof(argv[4]);
        dtPolyRef aRef = 0; float aPt[3] = {};
        describe("START", ax, ay, az, &aRef, aPt);

        if (argc >= 8) {
            float bx = (float)atof(argv[5]), by = (float)atof(argv[6]), bz = (float)atof(argv[7]);
            dtPolyRef bRef = 0; float bPt[3] = {};
            describe("GOAL ", bx, by, bz, &bRef, bPt);

            if (aRef && bRef) {
                dtPolyRef path[512]; int n = 0;
                dtStatus s = q->findPath(aRef, bRef, aPt, bPt, &filter, path, &n, 512);
                printf("\nfindPath: %s, %d polys%s\n",
                       dtStatusFailed(s) ? "FAILED" : "ok", n,
                       (n > 0 && path[n - 1] != bRef) ? "  (PARTIAL — goal not reached)" : "");
                if (!dtStatusFailed(s) && n > 0) {
                    float straight[512 * 3]; int sn = 0;
                    q->findStraightPath(aPt, bPt, path, n, straight, NULL, NULL, &sn, 512, 0);
                    printf("straight path: %d points\n", sn);
                    if (n > 0 && path[n - 1] != bRef)
                        printf("  -> the two points are NOT connected on this mesh.\n"
                               "     Usually a coverage hole between them, not corrupt tiles.\n");
                }
            } else {
                printf("\nfindPath skipped: one endpoint has no poly\n");
            }
        }
    }
    return 0;
}
