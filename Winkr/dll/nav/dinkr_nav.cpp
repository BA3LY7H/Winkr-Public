/* dinkr_nav.cpp — Detour navmesh pathfinding for WoW Classic (build 68940).
 *
 * Tile source: WowClassicGrindBot prebuilt "precata" mesh (covers 1.13-1.15),
 * staged as <root>/<mapId>/tile_<tx>_<tz>.dnm.
 *
 * The .dnm container is DotRecast's DtMeshDataWriter output with
 * cCompatibility=false (version 0x8809). It matches Detour's dtMeshHeader
 * exactly, but four body sections diverge and must be translated:
 *    polys        28B packed  -> 32B dtPoly       (prepend firstLink)
 *    links        absent      -> zeroed array     (Detour rebuilds in addTile)
 *    detailMeshes 10B packed  -> 12B dtPolyDetail (append 2 pad bytes)
 *    bvTree       28B int32   -> 16B dtBVNode     (narrow bounds to u16)
 * Layout independently verified byte-exact on all 10590 Azeroth tiles.
 */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdarg.h>
#include <math.h>
#include <stdint.h>

#include "DetourNavMesh.h"
#include "DetourNavMeshQuery.h"
#include "DetourCommon.h"
#include "DetourAlloc.h"
#include "dinkr_nav.h"
#include "dinkr_livemesh.h"

/* maxTiles=4096 / maxPolys=1<<20 underflows the 32-bit salt-bit budget in
 * dtNavMesh::init; DT_POLYREF64 also makes poly refs bit-compatible with the
 * DotRecast bake (SALT 16 / TILE 28 / POLY 20). Must match the Detour objects. */
#ifndef DT_POLYREF64
#error "dinkr_nav.cpp and vendor/detour must both be compiled with -DDT_POLYREF64"
#endif

/* ---- constants from the bake (PPather/Navmesh/NavmeshSettings.cs) ---------- */
static const float NAV_ORIGIN     = -32.0f * 533.33333f;   /* -17066.666015625 */
static const float NAV_TILE_SIZE  = 133.33333f;            /* quarter ADT */
static const int   NAV_MAX_TILES  = 4096;                  /* resident cap (array size) */
static const int   NAV_MAX_POLYS  = 1 << 20;
static const int   NAV_MAX_NODES  = 65535;

/* Area ids + poly flags (PPather WowQueryFilter.cs) */
static const int   AREA_MAGMA  = 8;
static const int   AREA_WATER  = 9;
static const int   AREA_GROUND = 11;
static const unsigned short FLAGS_INCLUDE = 0x0D;  /* ground | water | magma */

/* DotRecast serialization strides */
static const int   SRC_HDR   = 100;
static const int   SRC_POLY  = 28;
static const int   SRC_DMESH = 10;
static const int   SRC_BVN   = 28;
static const int   DNM_VERSION = 0x8809;

static char  s_status[256] = "nav: idle";
static char  s_root[260]   = "C:\\projects\\navmesh";

/* ---- TrinityCore mmaps -----------------------------------------------------
 * Second supported tile source, preferred when present.
 *
 * WHY IT IS BETTER THAN THE .dnm PATH: mmtile bodies are NATIVE dtMeshData.
 * The whole convertDnmTile translation above (4 body sections repacked:
 * polys 28->32B, links rebuilt, detailMeshes 10->12B, bvTree 28->16B) exists
 * only because DotRecast serialises differently. mmaps need none of it —
 * skip a 20-byte header and hand the rest straight to dtNavMesh::addTile.
 *
 * Layout, verified against the staged set:
 *   <root>\<map:04>.mmap                 = dtNavMeshParams (28 bytes exactly)
 *   <root>\<map:04><row:02><col:02>.mmtile
 *       MmapTileHeader { u32 magic 'MMAP', u32 dtVersion=7, u32 mmapVersion=9,
 *                        u32 size, u32 usesLiquids }   (20 bytes)
 *       then raw dtMeshData beginning dtMeshHeader magic 'DNAV' version 7.
 *
 * Grid indices are TrinityCore's, NOT the quarter-ADT grid the .dnm bake uses:
 *   row = 32 - wowX / 533.33333      col = 32 - wowY / 533.33333
 * Verified live: Northshire (-8900,-160) -> 00004832.mmtile, which exists.
 * Note the tile is a FULL ADT here (533.33) vs a quarter ADT (133.33) for .dnm,
 * so one mmtile replaces 16 .dnm tiles. */
static const float MMAP_TILE_SIZE = 533.33333f;
static char  s_mmapRoot[260] = "C:\\projects\\mmaps";
static int   s_mmapForce = 1;       /* MMAPS ONLY. -1 auto, 0 force .dnm, 1 force mmaps */

static inline void mmapTileIndex(float wx, float wy, int* row, int* col) {
    *row = (int)floorf(32.0f - wx / MMAP_TILE_SIZE);
    *col = (int)floorf(32.0f - wy / MMAP_TILE_SIZE);
}

static void setStatus(const char* fmt, ...) {
    va_list ap; va_start(ap, fmt);
    vsnprintf(s_status, sizeof(s_status), fmt, ap);
    va_end(ap);
}

/* ---- coordinate conversion (pure cyclic swap, NO negation) ---------------- */
static inline void wowToRc(float wx, float wy, float wz, float* rc) {
    rc[0] = wy; rc[1] = wz; rc[2] = wx;
}
static inline void rcToWow(const float* rc, float* w) {
    w[0] = rc[2]; w[1] = rc[0]; w[2] = rc[1];
}
static inline void wowTileIndex(float wx, float wy, int* tx, int* tz) {
    *tx = (int)floorf((wy - NAV_ORIGIN) / NAV_TILE_SIZE);
    *tz = (int)floorf((wx - NAV_ORIGIN) / NAV_TILE_SIZE);
}

/* ---- .dnm -> dtMeshData translation --------------------------------------- */
struct DnmHeader {                 /* mirrors dtMeshHeader field order */
    int magic, version, x, y, layer;
    unsigned int userId;
    int polyCount, vertCount, maxLinkCount;
    int detailMeshCount, detailVertCount, detailTriCount;
    int bvNodeCount, offMeshConCount, offMeshBase;
    float walkableHeight, walkableRadius, walkableClimb;
    float bmin[3], bmax[3];
    float bvQuantFactor;
};

/* Convert one .dnm blob into a Detour tile blob allocated with dtAlloc.
 * Returns 1 on success (*out / *outLen set; caller passes DT_TILE_FREE_DATA). */
static int convertDnmTile(const unsigned char* src, int srcLen,
                          unsigned char** out, int* outLen) {
    if (!src || srcLen < SRC_HDR) return 0;
    DnmHeader h;
    memcpy(&h, src, sizeof(DnmHeader));
    if (h.magic != DT_NAVMESH_MAGIC) return 0;
    if (h.version != DNM_VERSION)    return 0;   /* 0x8807/0x8808 use older layouts */
    if (h.polyCount <= 0 || h.vertCount <= 0)    return 0;

    /* validate the source length against the packed layout */
    const int need = SRC_HDR
        + 12 * h.vertCount
        + SRC_POLY * h.polyCount
        + SRC_DMESH * h.detailMeshCount
        + 12 * h.detailVertCount
        + 4 * h.detailTriCount
        + SRC_BVN * h.bvNodeCount
        + 36 * h.offMeshConCount;
    if (need != srcLen) return 0;

    const int headerSize   = dtAlign4(sizeof(dtMeshHeader));
    const int vertsSize    = dtAlign4(sizeof(float) * 3 * h.vertCount);
    const int polysSize    = dtAlign4(sizeof(dtPoly) * h.polyCount);
    const int linksSize    = dtAlign4(sizeof(dtLink) * h.maxLinkCount);
    const int dmeshSize    = dtAlign4(sizeof(dtPolyDetail) * h.detailMeshCount);
    const int dvertsSize   = dtAlign4(sizeof(float) * 3 * h.detailVertCount);
    const int dtrisSize    = dtAlign4(sizeof(unsigned char) * 4 * h.detailTriCount);
    const int bvSize       = dtAlign4(sizeof(dtBVNode) * h.bvNodeCount);
    const int omSize       = dtAlign4(sizeof(dtOffMeshConnection) * h.offMeshConCount);
    const int total = headerSize + vertsSize + polysSize + linksSize + dmeshSize
                    + dvertsSize + dtrisSize + bvSize + omSize;

    unsigned char* data = (unsigned char*)dtAlloc(total, DT_ALLOC_PERM);
    if (!data) return 0;
    memset(data, 0, total);

    unsigned char* d = data;
    const unsigned char* s = src;

    /* header: copy verbatim, then force Detour's version so addTile accepts it */
    memcpy(d, s, SRC_HDR);
    ((dtMeshHeader*)d)->version = DT_NAVMESH_VERSION;
    d += headerSize; s += SRC_HDR;

    /* verts: identical */
    memcpy(d, s, 12 * h.vertCount);
    d += vertsSize; s += 12 * h.vertCount;

    /* polys: 28 -> 32, prepend firstLink */
    {
        dtPoly* dp = (dtPoly*)d;
        for (int i = 0; i < h.polyCount; ++i) {
            dp[i].firstLink = DT_NULL_LINK;
            memcpy(((unsigned char*)&dp[i]) + sizeof(unsigned int),
                   s + (size_t)i * SRC_POLY, SRC_POLY);
        }
    }
    d += polysSize; s += (size_t)SRC_POLY * h.polyCount;

    /* links: not serialized — leave zeroed, Detour rebuilds them in addTile */
    d += linksSize;

    /* detailMeshes: 10 -> 12 (trailing pad already zeroed) */
    {
        dtPolyDetail* dm = (dtPolyDetail*)d;
        for (int i = 0; i < h.detailMeshCount; ++i)
            memcpy(&dm[i], s + (size_t)i * SRC_DMESH, SRC_DMESH);
    }
    d += dmeshSize; s += (size_t)SRC_DMESH * h.detailMeshCount;

    /* detail verts / tris: identical */
    memcpy(d, s, 12 * h.detailVertCount);
    d += dvertsSize; s += 12 * h.detailVertCount;
    memcpy(d, s, 4 * h.detailTriCount);
    d += dtrisSize;  s += 4 * h.detailTriCount;

    /* bvTree: int32 bounds -> u16 bounds (range-checked) */
    {
        dtBVNode* bn = (dtBVNode*)d;
        for (int i = 0; i < h.bvNodeCount; ++i) {
            const int32_t* q = (const int32_t*)(s + (size_t)i * SRC_BVN);
            for (int k = 0; k < 3; ++k) {
                int32_t lo = q[k];
                int32_t hi = q[k + 3];
                if (lo < 0)      lo = 0;
                if (lo > 0xffff) lo = 0xffff;
                if (hi < 0)      hi = 0;
                if (hi > 0xffff) hi = 0xffff;
                bn[i].bmin[k] = (unsigned short)lo;
                bn[i].bmax[k] = (unsigned short)hi;
            }
            memcpy(&bn[i].i, q + 6, sizeof(int));
        }
    }
    d += bvSize; s += (size_t)SRC_BVN * h.bvNodeCount;

    /* off-mesh connections: identical layout (normally none) */
    if (h.offMeshConCount > 0)
        memcpy(d, s, 36 * h.offMeshConCount);

    *out = data; *outLen = total;
    return 1;
}

/* ---- per-map mesh with LRU tile streaming --------------------------------- */
struct LoadedTile { int tx, tz; dtTileRef ref; unsigned int touch; };

struct MapMesh {
    int            mapId;
    dtNavMesh*     mesh;
    dtNavMeshQuery* query;
    LoadedTile     tiles[NAV_MAX_TILES];
    int            tileCount;
    unsigned int   touch;
    int            missCount;      /* tiles absent on disk (ocean/void) */
    int            useMmap;        /* 1 = TrinityCore mmaps, 0 = DotRecast .dnm */
};

static MapMesh* s_maps[8];
static int      s_mapCount = 0;

/* Tile indices differ per source: the .dnm bake is a quarter-ADT grid measured
 * from NAV_ORIGIN, mmaps are TrinityCore's full-ADT 32-minus grid. Dispatch on
 * the map's format so a mixed staging area cannot mix the two up. */
static inline void mapTileIndex(const MapMesh* m, float wx, float wy, int* tx, int* tz) {
    if (m && m->useMmap) mmapTileIndex(wx, wy, tx, tz);
    else                 wowTileIndex(wx, wy, tx, tz);
}

static MapMesh* getMap(int mapId) {
    for (int i = 0; i < s_mapCount; ++i)
        if (s_maps[i]->mapId == mapId) return s_maps[i];
    if (s_mapCount >= (int)(sizeof(s_maps) / sizeof(s_maps[0]))) return NULL;

    MapMesh* m = (MapMesh*)calloc(1, sizeof(MapMesh));
    if (!m) return NULL;
    m->mapId = mapId;
    m->mesh = dtAllocNavMesh();
    if (!m->mesh) { free(m); return NULL; }

    /* Prefer mmaps when a <map:04>.mmap header is present, else fall back to the
     * .dnm bake. Detected per map so a partially-staged mmap set cannot strand a
     * map that only has .dnm coverage. */
    m->useMmap = 0;
    if (s_mmapForce != 0) {
        char hdr[300];
        snprintf(hdr, sizeof(hdr), "%s\\%04d.mmap", s_mmapRoot, mapId);
        FILE* hf = fopen(hdr, "rb");
        if (hf) { m->useMmap = 1; fclose(hf); }
    }

    dtNavMeshParams p;
    memset(&p, 0, sizeof(p));
    p.orig[0] = NAV_ORIGIN; p.orig[1] = 0.0f; p.orig[2] = NAV_ORIGIN;
    p.tileWidth = NAV_TILE_SIZE; p.tileHeight = NAV_TILE_SIZE;
    p.maxTiles = NAV_MAX_TILES; p.maxPolys = NAV_MAX_POLYS;

    if (m->useMmap) {
        char hdr[300];
        snprintf(hdr, sizeof(hdr), "%s\\%04d.mmap", s_mmapRoot, mapId);
        FILE* hf = fopen(hdr, "rb");
        if (hf) {
            /* TWO .mmap LAYOUTS, measured on the real files:
             *   3.3.5 : dtNavMeshParams alone            (28 bytes)
             *   master: 'PAMM' + version, THEN the params (40 bytes, params @8)
             * Both sets carry identical values there, but reading the master
             * file as a bare struct lands tileWidth on orig[2] -- a large
             * negative that fails the > 1.0f test below, so it would silently
             * fall back to the compiled defaults instead of the file's grid.
             * Detect by magic rather than by size. */
            unsigned char hbuf[64];
            size_t rd0 = fread(hbuf, 1, sizeof(hbuf), hf);
            fclose(hf);
            size_t hoff = (rd0 >= 8 && *(const unsigned int*)hbuf == 0x4D4D4150u) ? 8 : 0;

            dtNavMeshParams fp;
            memset(&fp, 0, sizeof(fp));
            size_t rd = 0;
            if (rd0 >= hoff + sizeof(fp)) { memcpy(&fp, hbuf + hoff, sizeof(fp)); rd = sizeof(fp); }
            if (rd == sizeof(fp) && fp.tileWidth > 1.0f) {
                /* Take the ORIGIN and TILE SIZE from the file — they define the
                 * grid the tiles were baked on, and getTileAt() resolves against
                 * them. Do NOT take maxTiles/maxPolys: the staged header carries
                 * maxPolys = 0x80000000, which is negative as a signed int and
                 * makes dtNavMesh::init reject the params outright. Our own
                 * budget also has to satisfy the DT_POLYREF64 salt/tile/poly bit
                 * split, so keep the values we already validated. */
                p.orig[0] = fp.orig[0]; p.orig[1] = fp.orig[1]; p.orig[2] = fp.orig[2];
                p.tileWidth = fp.tileWidth; p.tileHeight = fp.tileHeight;
            }
        }
    }
    if (dtStatusFailed(m->mesh->init(&p))) {
        dtFreeNavMesh(m->mesh); free(m);
        setStatus("nav: dtNavMesh::init failed (need -DDT_POLYREF64)");
        return NULL;
    }
    m->query = dtAllocNavMeshQuery();
    if (!m->query || dtStatusFailed(m->query->init(m->mesh, NAV_MAX_NODES))) {
        if (m->query) dtFreeNavMeshQuery(m->query);
        dtFreeNavMesh(m->mesh); free(m);
        setStatus("nav: query init failed");
        return NULL;
    }
    s_maps[s_mapCount++] = m;
    return m;
}

static int tileResident(MapMesh* m, int tx, int tz) {
    for (int i = 0; i < m->tileCount; ++i)
        if (m->tiles[i].tx == tx && m->tiles[i].tz == tz) {
            m->tiles[i].touch = ++m->touch;
            return 1;
        }
    return 0;
}

static void evictOldest(MapMesh* m) {
    if (m->tileCount <= 0) return;
    int oldest = 0;
    for (int i = 1; i < m->tileCount; ++i)
        if (m->tiles[i].touch < m->tiles[oldest].touch) oldest = i;
    m->mesh->removeTile(m->tiles[oldest].ref, NULL, NULL);   /* frees data (DT_TILE_FREE_DATA) */
    m->tiles[oldest] = m->tiles[--m->tileCount];
}

/* Load one tile from disk if present and not already resident. */
static int ensureTile(MapMesh* m, int tx, int tz) {
    if (tx < 0 || tz < 0) return 0;
    if (tileResident(m, tx, tz)) return 1;

    char path[300];

    /* THIRD SOURCE: tiles LiveMesh generated at runtime. They are written with
     * the same 20-byte header as an mmtile and a native dtMeshData body, so they
     * parse through the identical path below — no second translator.
     *
     * Only consulted when this map is NOT using mmaps, and that restriction is
     * load-bearing: LiveMesh bakes on the quarter-ADT grid measured from
     * NAV_ORIGIN (wowTileIndex), while the mmap path indexes tiles on
     * TrinityCore's full-ADT 32-minus grid. Mixing them would look up a real
     * file under the wrong index and splice a tile in kilometres from where it
     * belongs. */
    int nativeDt = m->useMmap;
    FILE* f = NULL;
    if (!m->useMmap) {
        snprintf(path, sizeof(path), "%s\\%d\\tile_%d_%d.lmt",
                 DinkrLiveMeshCacheDir(), m->mapId, tx, tz);
        f = fopen(path, "rb");
        if (f) nativeDt = 1;
    }
    if (!f) {
        if (m->useMmap) {
            /* TWO mmtile NAMINGS, and both are in play here.
             *
             *   3.3.5 mmaps_generator : 00002337.mmtile   (packed)
             *   master mmaps_generator: 0000_23_37.mmtile (underscore)
             *
             * The tile BODY is the same in both: a 20-byte MmapTileHeader
             * ('PAMM', dtVersion 7) then native dtMeshData. Only the NAME
             * differs, so one loader handles both. Packed is tried first
             * because that is what the currently staged set uses.
             *
             * Getting this wrong is SILENT -- fopen just misses, missCount goes
             * up, and the query reports "no poly near" exactly as it would for
             * genuinely unmeshed ground. */
            snprintf(path, sizeof(path), "%s\\%04d%02d%02d.mmtile", s_mmapRoot, m->mapId, tx, tz);
            f = fopen(path, "rb");
            if (!f) {
                snprintf(path, sizeof(path), "%s\\%04d_%02d_%02d.mmtile", s_mmapRoot, m->mapId, tx, tz);
                f = fopen(path, "rb");
            }
        } else {
            snprintf(path, sizeof(path), "%s\\%d\\tile_%d_%d.dnm", s_root, m->mapId, tx, tz);
            f = fopen(path, "rb");
        }
    }
    if (!f) { m->missCount++; return 0; }          /* no tile here = not walkable */
    fseek(f, 0, SEEK_END);
    long len = ftell(f);
    fseek(f, 0, SEEK_SET);
    if (len <= 0 || len > (16 << 20)) { fclose(f); return 0; }
    unsigned char* raw = (unsigned char*)malloc((size_t)len);
    if (!raw) { fclose(f); return 0; }
    size_t rd = fread(raw, 1, (size_t)len, f);
    fclose(f);
    if (rd != (size_t)len) { free(raw); return 0; }

    unsigned char* tileData = NULL; int tileLen = 0;
    int ok;
    if (nativeDt) {
        /* mmtile = 20-byte MmapTileHeader then NATIVE dtMeshData. No struct
         * translation is needed at all, unlike the .dnm path. addTile takes
         * ownership (DT_TILE_FREE_DATA), so the body must live in dtAlloc
         * memory rather than the malloc buffer we read into. */
        ok = 0;
        if (len > 20) {
            const unsigned int magic = *(const unsigned int*)raw;
            const unsigned int dtver = *(const unsigned int*)(raw + 4);
            /* 'M','M','A','P' on disk, read as a little-endian uint32, is
             * 0x4D4D4150 — NOT 0x50414D4D. That byte-swapped constant rejected
             * EVERY tile, so nothing loaded and the query reported "no poly
             * near" while perfectly valid tiles sat on disk. */
            if (magic == 0x4D4D4150u && dtver == DT_NAVMESH_VERSION) {
                const int bodyLen = (int)len - 20;
                unsigned char* body = (unsigned char*)dtAlloc(bodyLen, DT_ALLOC_PERM);
                if (body) {
                    memcpy(body, raw + 20, (size_t)bodyLen);
                    tileData = body; tileLen = bodyLen; ok = 1;
                }
            } else {
                setStatus("nav: %04d%02d%02d.mmtile bad magic/version (0x%08X v%u)",
                          m->mapId, tx, tz, magic, dtver);
            }
        }
    } else {
        ok = convertDnmTile(raw, (int)len, &tileData, &tileLen);
    }
    free(raw);
    if (!ok) { setStatus("nav: tile %d_%d convert failed", tx, tz); return 0; }

    if (m->tileCount >= NAV_MAX_TILES) evictOldest(m);

    dtTileRef ref = 0;
    dtStatus st = m->mesh->addTile(tileData, tileLen, DT_TILE_FREE_DATA, 0, &ref);
    if (dtStatusFailed(st)) {
        dtFree(tileData);
        setStatus("nav: addTile %d_%d failed (0x%x)", tx, tz, (unsigned)st);
        return 0;
    }
    LoadedTile* lt = &m->tiles[m->tileCount++];
    lt->tx = tx; lt->tz = tz; lt->ref = ref; lt->touch = ++m->touch;
    return 1;
}

/* Stream in the tiles a query between two points could need. */
static void ensureTilesFor(MapMesh* m, float sx, float sy, float gx, float gy) {
    int stx, stz, gtx, gtz;
    mapTileIndex(m, sx, sy, &stx, &stz);
    mapTileIndex(m, gx, gy, &gtx, &gtz);

    int x0 = stx < gtx ? stx : gtx, x1 = stx > gtx ? stx : gtx;
    int z0 = stz < gtz ? stz : gtz, z1 = stz > gtz ? stz : gtz;
    /* 2-tile margin, not 1: findDistanceToWall treats the boundary of the
     * LOADED tile set as a wall, so a thin corridor would push corners inward
     * off phantom edges. Keeping a spare ring of tiles around the route means
     * the walls it measures are real geometry. */
    x0 -= 2; z0 -= 2; x1 += 2; z1 += 2;

    const int wide = (x1 - x0 + 1) * (z1 - z0 + 1);
    if (wide <= 256) {                                   /* small area: load the box */
        for (int x = x0; x <= x1; ++x)
            for (int z = z0; z <= z1; ++z) ensureTile(m, x, z);
        return;
    }
    /* long haul: load a corridor along the segment instead of the whole box */
    const float dx = gx - sx, dy = gy - sy;
    const float dist = sqrtf(dx * dx + dy * dy);
    const float tsize = m->useMmap ? MMAP_TILE_SIZE : NAV_TILE_SIZE;
    const int steps = (int)(dist / (tsize * 0.5f)) + 1;
    for (int i = 0; i <= steps; ++i) {
        const float t = (steps > 0) ? (float)i / (float)steps : 0.0f;
        int cx, cz;
        mapTileIndex(m, sx + dx * t, sy + dy * t, &cx, &cz);
        for (int ox = -2; ox <= 2; ++ox)              /* 5x5: spare ring, see above */
            for (int oz = -2; oz <= 2; ++oz) ensureTile(m, cx + ox, cz + oz);
    }
}

/* Load tiles, falling back to the .dnm bake when the mmap set does not cover
 * this area.
 *
 * Two reasons this must be per-QUERY and not just per-map-creation:
 *
 *  1. COVERAGE. The staged mmaps are ~470 full-ADT tiles for map 0; the .dnm
 *     bake is ~660 ADT-equivalents. Roughly a third of the world exists only in
 *     .dnm, so a map-wide format choice strands the bot the moment it walks into
 *     an uncovered zone.
 *
 *  2. STALE LATCH. getMap() caches the format in DLL memory, which survives a
 *     /reload (only Lua reloads). If the mmap folder is absent when a map is
 *     first touched — or present then removed — the map stays latched to the
 *     wrong source and EVERY tile load fails, reporting "no tiles for map 0"
 *     with the files sitting right there on disk. That is exactly what happened.
 *
 * The grids differ (mmaps are full-ADT and TrinityCore-indexed, .dnm is
 * quarter-ADT from NAV_ORIGIN), so the retry recomputes indices via
 * mapTileIndex after flipping the flag. */
static void ensureTilesForAuto(MapMesh* m, float sx, float sy, float gx, float gy) {
    ensureTilesFor(m, sx, sy, gx, gy);
    if (m->tileCount > 0) return;

    /* MMAPS ONLY: no .dnm fallback by design.
     *
     * Zero tiles here means the mmap set genuinely lacks this area (the staged
     * set is ~470 full-ADT tiles for map 0). Say so plainly rather than failing
     * with a generic "no tiles", so an uncovered zone is distinguishable from a
     * broken loader — the two look identical from the Lua side otherwise. */
    char probe[300];
    snprintf(probe, sizeof(probe), "%s\\%04d.mmap", s_mmapRoot, m->mapId);
    FILE* hf = fopen(probe, "rb");
    if (!hf) {
        setStatus("nav: no mmaps for map %d (missing %04d.mmap in %s)",
                  m->mapId, m->mapId, s_mmapRoot);
    } else {
        fclose(hf);
        setStatus("nav: mmaps loaded for map %d but no tile covers this spot",
                  m->mapId);
    }
}


/* ---- edge margin: push interior corners off walls -------------------------
 * The tiles are eroded by only 2 voxels (0.5333 yd) — TrinityCore's exact
 * mmaps_generator value, right for a server NPC on the path centreline but too
 * tight for keyboard steering, so findStraightPath corners sit hard against
 * geometry and the follower clips trees and hugs doorframes.
 *
 * Re-baking with a bigger agent radius is the WRONG fix: erosion is global and
 * destructive — at radius r every gap narrower than 2r vanishes from the mesh,
 * so wide erosion seals doorways, tunnels and cave mouths outright.
 *
 * Instead push each interior corner away from the nearest wall at QUERY time
 * (GrindBot ships this as Navmesh:Query:EdgeMargin = 1.5). Where there is room
 * we get the full margin — ~3x the baked erosion; where there isn't, the push
 * clamps and we still fit through. Erosion cannot do that. */
static float s_edgeMargin = 1.5f;

/* LAST PATH REQUEST — recorded for LiveMesh's auto generator.
 *
 * Recording it HERE rather than in any one consumer is the point: walker,
 * tacoQuest's grind leash, awful.path:Find and anything else all funnel through
 * DinkrNavFindPath, so hooking the funnel makes auto-generation work for every
 * one of them without them knowing LiveMesh exists.
 *
 * It is stored even when the query FAILS, which is the case that matters most:
 * "no path from navmesh" is exactly when we want tiles built toward that goal. */
static float s_lastReq[6];
static int   s_haveReq = 0;

static int   s_moveFails = 0;
static int   s_moveNoop = 0;
static int   s_lastPushed = 0;      /* corners moved by the last call (diagnostic) */
static float s_lastMinWall = -1.0f; /* closest wall seen on the last route */

static void applyEdgeMargin(dtNavMeshQuery* q, const dtQueryFilter* filter,
                            float* pts, dtPolyRef* refs, int n) {
    s_lastPushed = 0;
    s_moveFails = 0;
    s_moveNoop = 0;
    s_lastMinWall = -1.0f;
    if (s_edgeMargin <= 0.0f || n < 3) return;
    for (int i = 1; i < n - 1; ++i) {                 /* interior corners only:
                                                       * never move the start (the player is
                                                       * there) or the goal (we must reach it) */
        for (int pass = 0; pass < 2; ++pass) {        /* 2 passes: the first push can reveal a
                                                       * second constraining wall on a convex corner */
            dtPolyRef ref = refs[i];
            if (!ref) break;
            float* p = &pts[i * 3];
            float d = 0.0f, hitPos[3], hitNormal[3];
            if (dtStatusFailed(q->findDistanceToWall(ref, p, s_edgeMargin, filter,
                                                     &d, hitPos, hitNormal))) break;
            if (pass == 0 && (s_lastMinWall < 0.0f || d < s_lastMinWall)) s_lastMinWall = d;
            if (d >= s_edgeMargin) break;             /* already clear enough */
            if (pass == 0) s_lastPushed++;

            /* Direction to push. findStraightPath corners sit EXACTLY on polygon
             * edges, so d is typically 0 and Detour's hitNormal degenerates to a
             * zero vector (it is derived from centerPos - hitPos). Fall back to
             * the corner bisector, which by construction points into the
             * walkable side, away from the corner apex. */
            float nx = hitNormal[0], nz = hitNormal[2];
            float nlen = sqrtf(nx * nx + nz * nz);
            /* NOTE the inverted test: when d == 0 (the usual case here, since
             * funnel corners sit ON the edge) Detour normalises a zero vector
             * and hitNormal comes back NaN. `nlen < 0.1f` is FALSE for NaN, so
             * a plain less-than would sail past and poison the candidate —
             * moveAlongSurface then rejects it as non-finite. `!(nlen > 0.1f)`
             * catches NaN, zero and tiny alike. */
            if (!(nlen > 0.1f)) {
                const float* pv = &pts[(i - 1) * 3];
                const float* nv = &pts[(i + 1) * 3];
                float ux = pv[0] - p[0], uz = pv[2] - p[2];
                float wx = nv[0] - p[0], wz = nv[2] - p[2];
                float ul = sqrtf(ux * ux + uz * uz), wl = sqrtf(wx * wx + wz * wz);
                if (ul > 1e-4f) { ux /= ul; uz /= ul; }
                if (wl > 1e-4f) { wx /= wl; wz /= wl; }
                nx = ux + wx; nz = uz + wz;
                nlen = sqrtf(nx * nx + nz * nz);
                if (nlen < 1e-3f) break;               /* collinear: nothing to round */
            }
            nx /= nlen; nz /= nlen;

            const float push = s_edgeMargin - d;

            /* ACCEPT ONLY AN IMPROVEMENT.
             *
             * A gap narrower than 2*margin cannot satisfy the margin from both
             * sides. Pushing the full distance there does not centre the corner,
             * it clamps against the OPPOSITE wall — so a doorway corner sitting
             * on the left frame gets shoved hard into the right frame, the next
             * pass shoves it back, and the follower ends up shouldering the
             * frame it was supposed to clear. The move is always larger than the
             * no-op threshold, so nothing caught it.
             *
             * Try the full push, then half, then a quarter, and keep whichever
             * candidate leaves the corner FURTHEST from any wall. In a wide
             * space the full push wins on the first try and behaviour is
             * unchanged; in a doorway a fractional push wins and the corner
             * lands near the middle, which is the whole point. */
            float bestPos[3] = { p[0], p[1], p[2] };
            float bestD = d;
            dtPolyRef bestRef = ref;
            int improved = 0;

            for (int attempt = 0; attempt < 3; ++attempt) {
                const float scale = 1.0f / (float)(1 << attempt);   /* 1, 1/2, 1/4 */
                const float cand[3] = { p[0] + nx * push * scale, p[1],
                                        p[2] + nz * push * scale };

                /* Validate by walking the surface rather than findNearestPoly —
                 * moveAlongSurface cannot cross a wall into the next room, so the
                 * pushed corner can never end up on the far side of geometry. */
                float res[3];
                dtPolyRef visited[16];
                int nv = 0;
                if (dtStatusFailed(q->moveAlongSurface(ref, p, cand, filter, res, visited, &nv, 16))) {
                    s_moveFails++;
                    break;
                }
                /* moveAlongSurface clamps to the polygon boundary; if it barely
                 * moved, this candidate is pinned — a smaller one will be too. */
                const float mvx = res[0] - p[0], mvz = res[2] - p[2];
                if (sqrtf(mvx * mvx + mvz * mvz) < 0.02f) break;

                const dtPolyRef resRef = (nv > 0) ? visited[nv - 1] : ref;
                float d2 = 0.0f, hp[3], hn[3];
                if (dtStatusFailed(q->findDistanceToWall(resRef, res, s_edgeMargin,
                                                         filter, &d2, hp, hn)))
                    break;
                if (d2 > bestD) {
                    bestD = d2; bestRef = resRef;
                    bestPos[0] = res[0]; bestPos[1] = res[1]; bestPos[2] = res[2];
                    improved = 1;
                }
            }

            if (!improved) { s_moveNoop++; break; }
            p[0] = bestPos[0]; p[1] = bestPos[1]; p[2] = bestPos[2];
            refs[i] = bestRef;
        }
    }
}

static void makeFilter(dtQueryFilter* f) {
    f->setIncludeFlags(FLAGS_INCLUDE);
    f->setExcludeFlags(0);
    f->setAreaCost(AREA_GROUND, 1.0f);
    f->setAreaCost(AREA_WATER,  1.3f);
    f->setAreaCost(AREA_MAGMA,  4.0f);
}

/* ---- public API ----------------------------------------------------------- */
extern "C" int DinkrNavNearestPoint(int mapId, float x, float y, float z, float* out3) {
    MapMesh* m = getMap(mapId);
    if (!m || !out3) return 0;
    ensureTilesForAuto(m, x, y, x, y);

    dtQueryFilter filter; makeFilter(&filter);
    float rc[3]; wowToRc(x, y, z, rc);
    const float ext[3] = { 4.0f, 8.0f, 4.0f };
    dtPolyRef ref = 0; float nearest[3] = { 0, 0, 0 };
    if (dtStatusFailed(m->query->findNearestPoly(rc, ext, &filter, &ref, nearest)) || !ref) {
        setStatus("nav: no poly near (%.1f, %.1f, %.1f)", x, y, z);
        return 0;
    }
    rcToWow(nearest, out3);
    return 1;
}

/* How far is this point from the nearest mesh EDGE, and which way is open?
 *
 * applyEdgeMargin already uses findDistanceToWall internally, but only on the
 * corners findStraightPath returns. The follower does not drive those corners --
 * walker densifies them into a Catmull-Rom curve afterwards, and the interpolated
 * points are never clearance-checked, so the spline can bow closer to geometry
 * between two properly cleared corners than either corner is. That is how a route
 * clips a lightpost the mesh models perfectly well.
 *
 * Exposing the primitive lets the path builder apply the same standoff to every
 * point it actually intends to drive.
 *
 * outNormal3 points AWAY from the wall in WOW space, so a caller can push along
 * it directly. Returns 0 when the point is not near any poly.
 */
extern "C" int DinkrNavDistanceToWall(int mapId, float x, float y, float z,
                                      float maxRadius, float* outDist, float* outNormal3) {
    MapMesh* m = getMap(mapId);
    if (!m || !outDist) return 0;
    ensureTilesForAuto(m, x, y, x, y);

    dtQueryFilter filter; makeFilter(&filter);
    float rc[3]; wowToRc(x, y, z, rc);
    const float ext[3] = { 4.0f, 8.0f, 4.0f };
    dtPolyRef ref = 0; float nearest[3] = { 0, 0, 0 };
    if (dtStatusFailed(m->query->findNearestPoly(rc, ext, &filter, &ref, nearest)) || !ref)
        return 0;

    if (maxRadius <= 0.0f) maxRadius = 6.0f;
    float d = 0.0f, hitPos[3], hitNormal[3];
    if (dtStatusFailed(m->query->findDistanceToWall(ref, nearest, maxRadius, &filter,
                                                    &d, hitPos, hitNormal)))
        return 0;

    *outDist = d;
    if (outNormal3) {
        /* Detour degenerates the normal to a zero vector when the query point sits
         * exactly ON an edge, which is the common case here. Fall back to the
         * direction from the wall hit back to the point, which is the same thing
         * whenever it is defined. */
        float n[3] = { hitNormal[0], hitNormal[1], hitNormal[2] };
        float len = sqrtf(n[0] * n[0] + n[2] * n[2]);
        if (!(len > 0.01f)) {
            n[0] = nearest[0] - hitPos[0]; n[1] = 0.0f; n[2] = nearest[2] - hitPos[2];
            len = sqrtf(n[0] * n[0] + n[2] * n[2]);
        }
        if (len > 1e-4f) { n[0] /= len; n[2] /= len; n[1] = 0.0f; }
        else { n[0] = 0.0f; n[1] = 0.0f; n[2] = 0.0f; }
        rcToWow(n, outNormal3);
    }
    return 1;
}

extern "C" int DinkrNavFindPath(int mapId,
                                float sx, float sy, float sz,
                                float gx, float gy, float gz,
                                float* outXYZ, int maxPts, int* outCount) {
    /* Record before any early-out, so a rejected query still tells LiveMesh
     * where somebody wanted to go. */
    s_lastReq[0] = sx; s_lastReq[1] = sy; s_lastReq[2] = sz;
    s_lastReq[3] = gx; s_lastReq[4] = gy; s_lastReq[5] = gz;
    s_haveReq = 1;

    if (outCount) *outCount = 0;
    if (!outXYZ || maxPts < 2) return WK_PATH_NOPATH;

    MapMesh* m = getMap(mapId);
    if (!m) return WK_PATH_NOPATH;

    ensureTilesForAuto(m, sx, sy, gx, gy);
    if (m->tileCount == 0) { setStatus("nav: no tiles for map %d", mapId); return WK_PATH_NOPATH; }

    dtQueryFilter filter; makeFilter(&filter);
    float rcS[3], rcG[3];
    wowToRc(sx, sy, sz, rcS);
    wowToRc(gx, gy, gz, rcG);

    /* generous vertical extent: the caller's Z may be off the surface */
    const float ext[3]    = { 4.0f, 16.0f, 4.0f };
    const float extWide[3]= { 12.0f, 256.0f, 12.0f };

    dtPolyRef startRef = 0, endRef = 0;
    float startPt[3], endPt[3];
    if (dtStatusFailed(m->query->findNearestPoly(rcS, ext, &filter, &startRef, startPt)) || !startRef)
        m->query->findNearestPoly(rcS, extWide, &filter, &startRef, startPt);
    if (dtStatusFailed(m->query->findNearestPoly(rcG, ext, &filter, &endRef, endPt)) || !endRef)
        m->query->findNearestPoly(rcG, extWide, &filter, &endRef, endPt);

    if (!startRef) { setStatus("nav: start off-mesh (%.1f, %.1f, %.1f)", sx, sy, sz); return WK_PATH_NOPATH | WK_PATH_FARFROMPOLY; }
    if (!endRef)   { setStatus("nav: goal off-mesh (%.1f, %.1f, %.1f)", gx, gy, gz);  return WK_PATH_NOPATH | WK_PATH_FARFROMPOLY; }

    static dtPolyRef polys[1024];
    int polyCount = 0;
    if (dtStatusFailed(m->query->findPath(startRef, endRef, startPt, endPt, &filter,
                                          polys, &polyCount,
                                          (int)(sizeof(polys) / sizeof(polys[0])))) || polyCount <= 0) {
        setStatus("nav: findPath failed");
        return WK_PATH_NOPATH;
    }

    /* If the corridor doesn't reach the goal poly, clamp the endpoint onto the
     * last reachable poly so we still return a usable partial route. */
    int status = WK_PATH_NORMAL;
    float target[3] = { endPt[0], endPt[1], endPt[2] };
    if (polys[polyCount - 1] != endRef) {
        status = WK_PATH_INCOMPLETE;
        float closest[3]; bool posOver = false;
        if (dtStatusSucceed(m->query->closestPointOnPoly(polys[polyCount - 1], endPt, closest, &posOver)))
            dtVcopy(target, closest);
    }

    const int cap = maxPts < 256 ? maxPts : 256;
    static float straight[256 * 3];
    static unsigned char flags[256];
    static dtPolyRef refs[256];
    int nStraight = 0;
    if (dtStatusFailed(m->query->findStraightPath(startPt, target, polys, polyCount,
                                                  straight, flags, refs, &nStraight, cap))
        || nStraight <= 0) {
        setStatus("nav: findStraightPath failed");
        return WK_PATH_NOPATH;
    }

    /* push corners off walls before handing the route back */
    applyEdgeMargin(m->query, &filter, straight, refs, nStraight);

    for (int i = 0; i < nStraight && i < maxPts; ++i)
        rcToWow(&straight[i * 3], &outXYZ[i * 3]);
    if (outCount) *outCount = (nStraight < maxPts) ? nStraight : maxPts;

    setStatus("nav: %d pts, %d polys, %d tiles, margin %.1f (pushed %d, wall %.2f, mvFail %d, noop %d)%s",
              nStraight, polyCount, m->tileCount, s_edgeMargin,
              s_lastPushed, s_lastMinWall, s_moveFails, s_moveNoop,
              (status & WK_PATH_INCOMPLETE) ? " (partial)" : "");
    return status;
}

/* See dinkr_nav.h. Walks the resident tiles and emits polygon rings.
 *
 * Boundary detection is Detour's own: dtPoly::neis[i] is 0 when edge i has no
 * neighbouring polygon, which is exactly a wall or the edge of a hole. That is
 * free -- no geometry test, no raycast -- because addTile already computed it
 * when it stitched the tile in. Reading it here means the overlay shows the
 * mesh's OWN idea of where it ends, not an approximation of it.
 *
 * Coordinates come back in WoW space; the rc<->wow swap stays internal, as
 * everywhere else in this file. */
extern "C" int DinkrNavDumpPolys(int mapId, float cx, float cy, float radius,
                                 float* out, int maxVerts,
                                 int* outCounts, int maxPolys) {
    if (!out || !outCounts || maxVerts <= 0 || maxPolys <= 0) return 0;

    MapMesh* m = getMap(mapId);
    if (!m) return 0;

    /* Load what the area needs, same as a query would, so the picture matches
     * what a path would actually route on. */
    ensureTilesForAuto(m, cx, cy, cx, cy);
    if (m->tileCount == 0) return 0;

    const float r2 = radius * radius;
    int polyCount = 0, vertCursor = 0;

    /* Iterate the map's OWN resident list rather than the whole tile array:
     * dtNavMesh::getTile(int) is private, getTileByRef is not, and LoadedTile
     * already carries the ref. It also visits only tiles this map really
     * loaded instead of scanning 4096 mostly-empty slots. */
    for (int ti = 0; ti < m->tileCount; ++ti) {
        const dtMeshTile* tile = m->mesh->getTileByRef(m->tiles[ti].ref);
        if (!tile || !tile->header) continue;

        for (int i = 0; i < tile->header->polyCount; ++i) {
            if (polyCount >= maxPolys) return polyCount;

            const dtPoly* poly = &tile->polys[i];
            if (poly->getType() == DT_POLYTYPE_OFFMESH_CONNECTION) continue;
            if (vertCursor + poly->vertCount > maxVerts) return polyCount;

            /* Cheap reject on the first vertex before touching the rest. */
            const float* v0 = &tile->verts[poly->verts[0] * 3];
            float w0[3]; rcToWow(v0, w0);
            const float dx = w0[0] - cx, dy = w0[1] - cy;
            if (dx * dx + dy * dy > r2) continue;

            for (int k = 0; k < poly->vertCount; ++k) {
                const float* v = &tile->verts[poly->verts[k] * 3];
                float w[3]; rcToWow(v, w);
                float* o = out + (vertCursor + k) * 4;
                o[0] = w[0]; o[1] = w[1]; o[2] = w[2];
                o[3] = (poly->neis[k] == 0) ? 1.0f : 0.0f;   /* no neighbour = boundary */
            }
            vertCursor += poly->vertCount;
            outCounts[polyCount++] = poly->vertCount;
        }
    }
    return polyCount;
}

extern "C" int DinkrNavTilesLoaded(int mapId) {
    for (int i = 0; i < s_mapCount; ++i)
        if (s_maps[i]->mapId == mapId) return s_maps[i]->tileCount;
    return -1;
}

extern "C" const char* DinkrNavStatusText(void) { return s_status; }

extern "C" void DinkrNavSetEdgeMargin(float yards) {
    if (yards < 0.0f) yards = 0.0f;
    if (yards > 6.0f) yards = 6.0f;          /* beyond this it starts fighting narrow doorways */
    s_edgeMargin = yards;
}

extern "C" float DinkrNavGetEdgeMargin(void) { return s_edgeMargin; }

extern "C" int DinkrNavLastRequest(float* out6) {
    if (!s_haveReq || !out6) return 0;
    for (int i = 0; i < 6; ++i) out6[i] = s_lastReq[i];
    return 1;
}

extern "C" void DinkrNavSetRoot(const char* dir) {
    if (!dir || !*dir) return;
    snprintf(s_root, sizeof(s_root), "%s", dir);
}

extern "C" void DinkrNavShutdown(void) {
    for (int i = 0; i < s_mapCount; ++i) {
        MapMesh* m = s_maps[i];
        if (m->query) dtFreeNavMeshQuery(m->query);
        if (m->mesh)  dtFreeNavMesh(m->mesh);      /* frees tiles (DT_TILE_FREE_DATA) */
        free(m);
        s_maps[i] = NULL;
    }
    s_mapCount = 0;
}
