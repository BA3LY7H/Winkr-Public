/*
 * mesh_audit -- cross-check a baked navmesh against the collision geometry it
 * was built from.
 *
 * The generator's own report ("N tiles written") only says Recast did not
 * crash. It says nothing about whether the resulting mesh lets a path cut a
 * corner through a wall, bridge a cliff that cannot be climbed, or squeeze
 * down a corridor narrower than the character. Those are exactly the failures
 * that show up in game as a bot walking into a building.
 *
 * So this tool holds two independent representations of the same world at
 * once -- the navmesh (Detour) and the source collision (VMAP) -- and looks
 * for places where they disagree:
 *
 *   1. CONVENTION   the axis mapping between them, established from the data
 *                   rather than assumed, because every later check is
 *                   meaningless if this is wrong
 *   2. TOPOLOGY     degenerate/oversized polys, unreachable islands
 *   3. ROUTES       real paths, every segment raycast against real collision
 *   4. CLEARANCE    corridor width along those paths vs the character
 *
 * A finding here is a claim about the mesh, so each one carries the world
 * coordinates that produced it -- they can be pasted straight into
 * mmap_inspect or walked to in game.
 */

#include "Banner.h"
#include "DB2FileLoader.h"
#include "DB2FileSystemSource.h"
#include "DetourCommon.h"
#include "DetourNavMesh.h"
#include "DetourNavMeshQuery.h"
#include "ExtractorDB2LoadInfo.h"
#include "Locales.h"
#include "Log.h"
#include "MMapDefines.h"
#include "ModelIgnoreFlags.h"
#include "VMapManager.h"

#include <boost/filesystem/directory.hpp>
#include <boost/filesystem/operations.hpp>
#include <algorithm>
#include <cmath>
#include <cstdio>
#include <cstring>
#include <random>
#include <string>
#include <unordered_map>
#include <unordered_set>
#include <vector>

namespace
{
    // ---------------------------------------------------------------------
    // Coordinate spaces
    // ---------------------------------------------------------------------
    // rc = (wowY, wowZ, wowX). A pure cyclic swap, no negation.
    //
    // TerrainBuilder LOOKS like it mirrors both horizontal axes -- it writes
    // coord[0] = -(yOffset + ...) and coord[2] = -(xOffset + ...). But the
    // offsets are themselves built from the tile index as (tile - 32) * GRID,
    // which is already the negation of the world coordinate, so the two
    // negations cancel and the result is +wow. Reading the minus signs alone
    // gives the opposite answer, which is why auditConvention() measures this
    // against real geometry instead of trusting either reading. Y is up in
    // Detour; VMAP's public API takes plain world coords.
    struct Wow { float x, y, z; };

    inline Wow rcToWow(float const* rc) { return { rc[2], rc[0], rc[1] }; }
    inline void wowToRc(Wow const& w, float* rc) { rc[0] = w.y; rc[1] = w.z; rc[2] = w.x; }

    inline float dist3(float const* a, float const* b)
    {
        float dx = a[0] - b[0], dy = a[1] - b[1], dz = a[2] - b[2];
        return std::sqrt(dx * dx + dy * dy + dz * dz);
    }

    inline float dist2(float const* a, float const* b)
    {
        float dx = a[0] - b[0], dz = a[2] - b[2];
        return std::sqrt(dx * dx + dz * dz);
    }

    // ---------------------------------------------------------------------
    // Character envelope
    // ---------------------------------------------------------------------
    // These are what the mesh is audited AGAINST, and they are deliberately
    // the player's dimensions rather than the generator's agent. The bake
    // erodes by 0.5333 yd (2 cells); a player is wider than that, which is
    // why the runtime adds an edge margin on top. Auditing against the player
    // is the point -- it finds the places where that margin is not enough.
    struct Character
    {
        float radius = 0.6f;    // collision radius; /lm width measures it live
        float height = 2.0f;    // standing height, for line-of-sight rays
        float eye    = 1.5f;    // ray height for corridor checks
        float climb  = 1.0f;    // step height a player can walk up
        float maxDrop = 3.0f;   // fall a path may take without being a cliff
    };

    // ---------------------------------------------------------------------
    // Findings
    // ---------------------------------------------------------------------
    struct Finding
    {
        std::string kind;
        std::string detail;
        Wow where{};
    };

    class Report
    {
    public:
        void add(std::string kind, std::string detail, Wow where)
        {
            _counts[kind]++;
            if (_samples[kind].size() < SAMPLES_PER_KIND)
                _samples[kind].push_back({ std::move(kind), std::move(detail), where });
        }

        void bump(std::string const& kind) { _counts[kind]++; }

        uint32 count(std::string const& kind) const
        {
            auto itr = _counts.find(kind);
            return itr != _counts.end() ? itr->second : 0u;
        }

        void print(char const* title) const
        {
            printf("\n=== %s ===\n", title);
            if (_counts.empty())
            {
                printf("  (nothing)\n");
                return;
            }

            std::vector<std::pair<std::string, uint32>> rows(_counts.begin(), _counts.end());
            std::sort(rows.begin(), rows.end(), [](auto const& a, auto const& b) { return a.second > b.second; });
            for (auto const& [kind, n] : rows)
            {
                printf("  %-34s %6u\n", kind.c_str(), n);
                auto itr = _samples.find(kind);
                if (itr == _samples.end())
                    continue;

                for (Finding const& f : itr->second)
                    printf("        at (%.1f, %.1f, %.1f)  %s\n", f.where.x, f.where.y, f.where.z, f.detail.c_str());
            }
        }

    private:
        static constexpr std::size_t SAMPLES_PER_KIND = 4;
        std::unordered_map<std::string, uint32> _counts;
        std::unordered_map<std::string, std::vector<Finding>> _samples;
    };

    // ---------------------------------------------------------------------
    // Navmesh loading -- mirrors what the game-side loader does, including
    // accepting both the 3.3.5 and master file layouts, so that a mesh which
    // audits clean here is the same mesh that gets loaded there.
    // ---------------------------------------------------------------------
    dtNavMesh* loadNavMesh(std::string const& mmapDir, uint32 mapId, uint32& tilesLoaded, uint32& tilesRejected)
    {
        char path[512];
        snprintf(path, sizeof(path), "%s/%04u.mmap", mmapDir.c_str(), mapId);
        FILE* fp = fopen(path, "rb");
        if (!fp)
        {
            printf("no %04u.mmap in %s\n", mapId, mmapDir.c_str());
            return nullptr;
        }

        // master prefixes the params with magic + version; 3.3.5 does not.
        uint32 magic = 0;
        long paramsOff = 0;
        if (fread(&magic, sizeof(magic), 1, fp) == 1 && magic == MMAP_MAGIC)
            paramsOff = 8;
        fseek(fp, paramsOff, SEEK_SET);

        dtNavMeshParams params = {};
        if (fread(&params, sizeof(params), 1, fp) != 1)
        {
            fclose(fp);
            printf("%04u.mmap is truncated\n", mapId);
            return nullptr;
        }
        fclose(fp);

        // The file's maxPolys is a bit budget, not a count, and is negative as
        // a signed int. Detour rejects it outright, so use our own budget and
        // keep only the grid definition -- origin and tile size -- which is
        // what tile lookup actually resolves against.
        params.maxTiles = 4096;
        params.maxPolys = 1 << 18;

        dtNavMesh* mesh = dtAllocNavMesh();
        if (!mesh || dtStatusFailed(mesh->init(&params)))
        {
            printf("navmesh init failed for map %u\n", mapId);
            return nullptr;
        }

        for (uint32 x = 0; x < 64; ++x)
        {
            for (uint32 y = 0; y < 64; ++y)
            {
                snprintf(path, sizeof(path), "%s/%04u_%02u_%02u.mmtile", mmapDir.c_str(), mapId, x, y);
                FILE* tf = fopen(path, "rb");
                if (!tf)
                {
                    snprintf(path, sizeof(path), "%s/%04u%02u%02u.mmtile", mmapDir.c_str(), mapId, x, y);
                    tf = fopen(path, "rb");
                }
                if (!tf)
                    continue;

                MmapTileHeader header = {};
                if (fread(&header, sizeof(header), 1, tf) != 1 || header.mmapMagic != MMAP_MAGIC
                    || header.dtVersion != uint32(DT_NAVMESH_VERSION) || !header.size)
                {
                    fclose(tf);
                    ++tilesRejected;
                    continue;
                }

                unsigned char* data = static_cast<unsigned char*>(dtAlloc(header.size, DT_ALLOC_PERM));
                if (fread(data, header.size, 1, tf) != 1)
                {
                    dtFree(data);
                    fclose(tf);
                    ++tilesRejected;
                    continue;
                }
                fclose(tf);

                if (dtStatusFailed(mesh->addTile(data, header.size, DT_TILE_FREE_DATA, 0, nullptr)))
                {
                    dtFree(data);
                    ++tilesRejected;
                    continue;
                }
                ++tilesLoaded;
            }
        }

        return mesh;
    }

    // ---------------------------------------------------------------------
    // Every walkable poly, with its centre, so later phases can sample the
    // mesh uniformly rather than guessing at coordinates.
    // ---------------------------------------------------------------------
    struct PolySample
    {
        dtPolyRef ref;
        float centre[3];
        float area;         // rough, for spotting degenerate and oversized polys
        int vertCount;
        int tile;           // owning tile index, for --densest
    };

    void collectPolys(dtNavMesh const* mesh, std::vector<PolySample>& out, Report& topo)
    {
        for (int t = 0; t < mesh->getMaxTiles(); ++t)
        {
            dtMeshTile const* tile = mesh->getTile(t);
            if (!tile || !tile->header)
                continue;

            for (int i = 0; i < tile->header->polyCount; ++i)
            {
                dtPoly const* poly = &tile->polys[i];
                if (poly->getType() == DT_POLYTYPE_OFFMESH_CONNECTION)
                    continue;

                PolySample s{};
                s.ref = mesh->encodePolyId(tile->salt, uint32(t), uint32(i));
                s.tile = t;
                s.vertCount = poly->vertCount;

                float centre[3] = { 0, 0, 0 };
                for (int v = 0; v < poly->vertCount; ++v)
                {
                    float const* p = &tile->verts[poly->verts[v] * 3];
                    dtVadd(centre, centre, p);
                }
                dtVscale(s.centre, centre, 1.0f / float(poly->vertCount));

                // Shoelace on the horizontal plane. Exact area is not the
                // point -- separating slivers from normal polys is.
                float a = 0.0f;
                for (int v = 0; v < poly->vertCount; ++v)
                {
                    float const* p = &tile->verts[poly->verts[v] * 3];
                    float const* q = &tile->verts[poly->verts[(v + 1) % poly->vertCount] * 3];
                    a += p[0] * q[2] - q[0] * p[2];
                }
                s.area = std::fabs(a) * 0.5f;

                if (poly->vertCount < 3)
                    topo.add("poly/degenerate-vertcount", "fewer than 3 verts", rcToWow(s.centre));
                else if (s.area < 0.01f)
                    topo.add("poly/sliver", "area < 0.01 yd^2, too thin to stand on", rcToWow(s.centre));
                else if (s.area > 6000.0f)
                    topo.add("poly/oversized", "area > 6000 yd^2, terrain detail was lost here", rcToWow(s.centre));

                out.push_back(s);
            }
        }
    }

    // ---------------------------------------------------------------------
    // Reachability. Polys that no path can ever reach are either genuinely
    // sealed rooms or -- more often -- a bake artefact, and either way a
    // router that snaps onto one strands the character.
    // ---------------------------------------------------------------------
    void auditConnectivity(dtNavMesh const* mesh, std::vector<PolySample> const& polys, Report& topo)
    {
        if (polys.empty())
            return;

        std::unordered_map<dtPolyRef, std::size_t> index;
        index.reserve(polys.size());
        for (std::size_t i = 0; i < polys.size(); ++i)
            index[polys[i].ref] = i;

        std::vector<int> component(polys.size(), -1);
        std::vector<std::size_t> componentSize;

        std::vector<std::size_t> stack;
        for (std::size_t seed = 0; seed < polys.size(); ++seed)
        {
            if (component[seed] != -1)
                continue;

            int id = int(componentSize.size());
            std::size_t size = 0;
            stack.clear();
            stack.push_back(seed);
            component[seed] = id;

            while (!stack.empty())
            {
                std::size_t cur = stack.back();
                stack.pop_back();
                ++size;

                dtMeshTile const* tile = nullptr;
                dtPoly const* poly = nullptr;
                if (dtStatusFailed(mesh->getTileAndPolyByRef(polys[cur].ref, &tile, &poly)))
                    continue;

                for (uint32 k = poly->firstLink; k != DT_NULL_LINK; k = tile->links[k].next)
                {
                    dtPolyRef neighbour = tile->links[k].ref;
                    if (!neighbour)
                        continue;

                    auto itr = index.find(neighbour);
                    if (itr == index.end() || component[itr->second] != -1)
                        continue;

                    component[itr->second] = id;
                    stack.push_back(itr->second);
                }
            }

            componentSize.push_back(size);
        }

        std::size_t largest = 0;
        for (std::size_t s : componentSize)
            largest = std::max(largest, s);

        // A disconnected component is not automatically a defect. Recast meshes
        // every walkable surface, and rooftops, ledges and sealed interiors are
        // genuinely unreachable on foot. The number that matters to a router is
        // how much of the mesh sits in a component too small to go anywhere
        // useful -- that is the surface a snap can strand the character on.
        std::size_t strandable = 0;
        for (std::size_t i = 0; i < polys.size(); ++i)
            if (componentSize[component[i]] < 20)
                ++strandable;

        printf("  components: %zu  (largest holds %zu of %zu polys, %.1f%%)\n",
               componentSize.size(), largest, polys.size(), 100.0 * double(largest) / double(polys.size()));
        printf("  polys in components < 20 polys: %zu (%.2f%% -- snapping here strands the character)\n",
               strandable, 100.0 * double(strandable) / double(polys.size()));

        for (std::size_t i = 0; i < polys.size(); ++i)
        {
            std::size_t size = componentSize[component[i]];
            if (size <= 4 && size != largest)
                topo.add("region/tiny-island", "unreachable cluster of <= 4 polys", rcToWow(polys[i].centre));
        }
    }

    // ---------------------------------------------------------------------
    // Area census. Confirms the liquid areas the bake is supposed to mark
    // actually reached the tiles -- the runtime charges water 1.3 and magma
    // 4.0 against these values, and if they are all NAV_AREA_GROUND then those
    // costs have been doing nothing.
    // ---------------------------------------------------------------------
    void auditAreas(dtNavMesh const* mesh)
    {
        std::unordered_map<uint32, std::size_t> byArea;
        std::size_t total = 0;

        for (int t = 0; t < mesh->getMaxTiles(); ++t)
        {
            dtMeshTile const* tile = mesh->getTile(t);
            if (!tile || !tile->header)
                continue;

            for (int i = 0; i < tile->header->polyCount; ++i)
            {
                dtPoly const* poly = &tile->polys[i];
                if (poly->getType() == DT_POLYTYPE_OFFMESH_CONNECTION)
                    continue;

                ++byArea[poly->getArea()];
                ++total;
            }
        }

        auto name = [](uint32 area) -> char const*
        {
            switch (area)
            {
                case 11: return "ground";
                case 10: return "ground steep";
                case  9: return "water";
                case  8: return "magma/slime";
                case  0: return "EMPTY (unwalkable)";
                default: return "other";
            }
        };

        printf("  area census:");
        for (uint32 area : { 11u, 10u, 9u, 8u, 0u })
        {
            auto itr = byArea.find(area);
            std::size_t n = itr != byArea.end() ? itr->second : 0;
            printf("  %s %zu (%.2f%%)", name(area), n, total ? 100.0 * double(n) / double(total) : 0.0);
        }
        printf("\n");

        if (!byArea.count(9) && !byArea.count(8))
            printf("  NOTE: no liquid areas in this map -- expected for a dry one, wrong for a coastal map.\n");
    }

    // ---------------------------------------------------------------------
    // Vertically ambiguous ground. Where a balcony, bridge or upper storey
    // sits over walkable floor, one X/Y carries more than one surface, and a
    // router that snaps by nearest-poly can land the character on the wrong
    // one. This does not mean the mesh is wrong -- multi-storey geometry is
    // supposed to look like this -- it measures how much of the map a naive
    // snap can get wrong, which is what decides whether the query needs a
    // tighter vertical extent.
    // ---------------------------------------------------------------------
    void auditVerticalAmbiguity(dtNavMeshQuery* query, std::vector<PolySample> const& polys,
                                std::mt19937& rng, Report& topo)
    {
        if (polys.empty())
            return;

        dtQueryFilter filter;
        filter.setIncludeFlags(0xffff);
        filter.setExcludeFlags(0);

        std::uniform_int_distribution<std::size_t> pick(0, polys.size() - 1);

        constexpr int SAMPLES = 3000;

        // The exact vertical extents dinkr_nav.cpp queries with: 8 for the snap
        // helpers, 16 for path endpoints, and 256 for the wide fallback it
        // drops to when the tight query misses. Measuring at 50 -- a number
        // this tool made up -- would report an exposure the DLL does not have,
        // and would miss the one it does.
        // Two probe offsets: 1 yd models a caller passing an accurate
        // player Z, 5 yd a caller guessing. The gap between them is the answer
        // to whether this is a mesh property or a query-hygiene problem.
        for (auto [probeUp, vExtent] : { std::pair{1.0f, 8.0f}, std::pair{5.0f, 8.0f}, std::pair{5.0f, 256.0f} })
        {
        int tested = 0, ambiguous = 0, wrongStorey = 0;

        for (int i = 0; i < SAMPLES; ++i)
        {
            PolySample const& s = polys[pick(rng)];

            // A generous vertical extent is exactly what a caller uses when it
            // does not already know the character's height -- which is the
            // case that goes wrong.
            // Query slightly ABOVE the surface, not at it. Asking at a poly's
            // own centre returns that poly by definition, which measures
            // nothing -- the first version of this check reported 0/2991 for
            // exactly that reason. A caller with approximate Z is the real
            // case: the bot knows roughly where it is, and the question is
            // whether a roof or balcony overhead wins the snap.
            float probe[3] = { s.centre[0], s.centre[1] + probeUp, s.centre[2] };
            float wide[3] = { 2.0f, vExtent, 2.0f };
            dtPolyRef ref = 0;
            float snapped[3] = {};
            if (dtStatusFailed(query->findNearestPoly(probe, wide, &filter, &ref, snapped)) || !ref)
                continue;

            ++tested;
            if (ref == s.ref)
                continue;

            ++ambiguous;

            // Landing on a different poly at essentially the same height is
            // harmless -- adjacent polys tile the same floor. Landing metres
            // above or below is the balcony case.
            float dy = std::fabs(snapped[1] - s.centre[1]);
            if (dy > 2.0f)
            {
                ++wrongStorey;
                if (vExtent > 200.0f)
                {
                    char detail[256];
                    snprintf(detail, sizeof(detail), "wide-fallback snap lands %.1f yd off in height -- another storey at this X/Y", dy);
                    topo.add("vertical/ambiguous-storey", detail, rcToWow(s.centre));
                }
            }
        }

        printf("  vertical (probe +%.0f yd, extent %5.0f yd): %d sampled | %d snapped elsewhere | %d landed on another storey (%.2f%%)\n",
               probeUp, vExtent, tested, ambiguous, wrongStorey, tested ? 100.0 * wrongStorey / tested : 0.0);
        }
    }

    // ---------------------------------------------------------------------
    // Pick the N densest tiles and return only the polys inside them.
    //
    // Poly count per tile tracks geometric complexity directly -- Recast emits
    // more polys where there is more to represent -- so this finds cities and
    // towns without anyone having to type a coordinate. Prints its choice with
    // world coords so the selection can be sanity-checked against the map.
    // ---------------------------------------------------------------------
    std::vector<PolySample> densestTiles(dtNavMesh const* mesh, std::vector<PolySample> const& polys, int wanted)
    {
        std::unordered_map<int, std::size_t> perTile;
        for (PolySample const& p : polys)
            ++perTile[p.tile];

        std::vector<std::pair<int, std::size_t>> ranked(perTile.begin(), perTile.end());
        std::sort(ranked.begin(), ranked.end(), [](auto const& a, auto const& b) { return a.second > b.second; });
        if (int(ranked.size()) > wanted)
            ranked.resize(wanted);

        std::unordered_set<int> keep;
        printf("  densest %d tiles (poly count -> world centre):\n", int(ranked.size()));
        for (auto const& [t, n] : ranked)
        {
            keep.insert(t);
            dtMeshTile const* tile = mesh->getTile(t);
            if (!tile || !tile->header)
                continue;

            float mid[3] = {
                (tile->header->bmin[0] + tile->header->bmax[0]) * 0.5f,
                (tile->header->bmin[1] + tile->header->bmax[1]) * 0.5f,
                (tile->header->bmin[2] + tile->header->bmax[2]) * 0.5f
            };
            Wow w = rcToWow(mid);
            printf("        [%02d,%02d]  %6zu polys  near (%.0f, %.0f)\n",
                   tile->header->x, tile->header->y, n, w.x, w.y);
        }

        std::vector<PolySample> subset;
        subset.reserve(polys.size() / 4);
        for (PolySample const& p : polys)
            if (keep.count(p.tile))
                subset.push_back(p);

        printf("  route sampling restricted to %zu of %zu polys\n", subset.size(), polys.size());
        return subset;
    }

    // ---------------------------------------------------------------------
    // Convention check. Establishes, from the data, that navmesh space and
    // VMAP space describe the same world -- and reports what the alternative
    // (unnegated) mapping would give, because that is the mapping the game
    // client-side loader uses and the two disagreeing would invalidate every
    // route finding below.
    // ---------------------------------------------------------------------
    void auditConvention(VMAP::VMapManager* vmap, uint32 mapId, std::vector<PolySample> const& polys, std::mt19937& rng)
    {
        if (polys.empty())
            return;

        std::uniform_int_distribution<std::size_t> pick(0, polys.size() - 1);

        int negatedAgree = 0, plainAgree = 0, negatedTested = 0, plainTested = 0;
        float negatedWorst = 0.0f;

        for (int i = 0; i < 400; ++i)
        {
            PolySample const& s = polys[pick(rng)];

            // The mapping the rest of the tool uses.
            Wow w = rcToWow(s.centre);
            float h = vmap->getHeight(mapId, w.x, w.y, w.z + 2.0f, 10.0f);
            if (h > VMAP_INVALID_HEIGHT)
            {
                ++negatedTested;
                float d = std::fabs(h - w.z);
                if (d < 1.0f)
                    ++negatedAgree;
                negatedWorst = std::max(negatedWorst, d);
            }

            // The mirrored mapping, for comparison.
            Wow p{ -s.centre[2], -s.centre[0], s.centre[1] };
            float ph = vmap->getHeight(mapId, p.x, p.y, p.z + 2.0f, 10.0f);
            if (ph > VMAP_INVALID_HEIGHT)
            {
                ++plainTested;
                if (std::fabs(ph - p.z) < 1.0f)
                    ++plainAgree;
            }
        }

        // Only polys that sit under or over a building return a VMAP height at
        // all -- open terrain is not VMAP geometry -- so the sample that counts
        // is small and that is expected. What matters is the agreement rate
        // within it, and that the mirrored mapping scores near zero.
        printf("  axis mapping ( rcZ,  rcX, rcY): %d/%d sampled polys land on VMAP geometry within 1 yd\n",
               negatedAgree, negatedTested);
        printf("  axis mapping (-rcZ, -rcX, rcY): %d/%d  (expected to be ~0)\n", plainAgree, plainTested);

        // Judge the two mappings against each other, not against an absolute
        // rate. Multi-level buildings drag the agreement rate down honestly --
        // getHeight returns one floor and the poly may sit on another -- so on
        // Kalimdor the correct mapping scores 75%%, which an absolute threshold
        // reads as failure. What actually proves the mapping is that the
        // mirrored one scores near zero.
        bool decisive = negatedTested >= 20 && negatedAgree > 2 * plainAgree && negatedAgree * 5 >= negatedTested * 2;
        if (!decisive)
            printf("  WARNING: the mesh and the collision do not agree on where the world is.\n"
                   "           Every route finding below is unreliable until this is resolved.\n");
        else
            printf("  mapping confirmed; route checks below are meaningful.\n");
    }

    // ---------------------------------------------------------------------
    // Route audit. The core of the tool: real paths, checked against real
    // collision rather than against the mesh that produced them.
    // ---------------------------------------------------------------------
    struct RouteStats
    {
        uint32 attempted = 0;
        uint32 complete = 0;
        uint32 partial = 0;
        uint32 failed = 0;
        uint32 bufferFull = 0;
        uint32 segments = 0;
        uint32 blocked = 0;
        uint32 grazed = 0;
        uint32 lowClip = 0;
        uint32 narrow = 0;
        uint32 steep = 0;
    };

    // Distance bands, in yards. A bot paths between a mob and a vendor, not
    // from Stormwind to Booty Bay in one query, so audit the range that is
    // actually asked of the mesh -- and note that the long band exists to
    // stress tile seams, not because anything routes that far in one call.
    struct Band { char const* name; float min, max; };
    constexpr Band BANDS[] = {
        { "close  (5-30 yd)",    5.0f,   30.0f },
        { "medium (30-150 yd)",  30.0f,  150.0f },
        { "long   (150-600 yd)", 150.0f, 600.0f },
    };

    void auditRoutes(dtNavMesh const* mesh, dtNavMeshQuery* query, VMAP::VMapManager* vmap, uint32 mapId,
                     std::vector<PolySample> const& polys, Character const& ch, uint32 samplesPerBand,
                     std::mt19937& rng, Report& routes, RouteStats& stats)
    {
        if (polys.size() < 2)
            return;

        dtQueryFilter filter;
        filter.setIncludeFlags(0xffff);
        filter.setExcludeFlags(0);

        std::uniform_int_distribution<std::size_t> pick(0, polys.size() - 1);

        // Coarse hash grid over poly centres, so the short bands can find a
        // partner near a given poly instead of rejection-sampling the whole
        // continent and almost never succeeding.
        constexpr float CELL = 32.0f;
        auto key = [](float x, float z) -> uint64
        {
            int32 cx = int32(std::floor(x / CELL));
            int32 cz = int32(std::floor(z / CELL));
            return (uint64(uint32(cx)) << 32) | uint32(cz);
        };

        std::unordered_map<uint64, std::vector<std::size_t>> grid;
        grid.reserve(polys.size() / 4);
        for (std::size_t i = 0; i < polys.size(); ++i)
            grid[key(polys[i].centre[0], polys[i].centre[2])].push_back(i);

        // Pick a partner for `from` whose distance falls in the band, by
        // searching outward through grid cells rather than at random.
        auto partnerNear = [&](PolySample const& from, Band const& band) -> PolySample const*
        {
            int32 reach = int32(std::ceil(band.max / CELL)) + 1;
            int32 cx = int32(std::floor(from.centre[0] / CELL));
            int32 cz = int32(std::floor(from.centre[2] / CELL));

            std::vector<std::size_t> candidates;
            for (int32 dx = -reach; dx <= reach; ++dx)
            {
                for (int32 dz = -reach; dz <= reach; ++dz)
                {
                    auto itr = grid.find((uint64(uint32(cx + dx)) << 32) | uint32(cz + dz));
                    if (itr == grid.end())
                        continue;

                    for (std::size_t idx : itr->second)
                    {
                        float d = dist2(from.centre, polys[idx].centre);
                        if (d >= band.min && d <= band.max)
                            candidates.push_back(idx);
                    }
                }
            }

            if (candidates.empty())
                return nullptr;

            std::uniform_int_distribution<std::size_t> c(0, candidates.size() - 1);
            return &polys[candidates[c(rng)]];
        };

        // Big enough that a legitimate route is never truncated. A truncated
        // path looks exactly like a disconnected one, and conflating the two
        // is what made the first run's numbers useless.
        constexpr int MAX_PATH = 8192;
        constexpr int MAX_CORNERS = 1024;
        std::vector<dtPolyRef> pathPolys(MAX_PATH);
        std::vector<float> corners(3 * MAX_CORNERS);
        std::vector<unsigned char> cornerFlags(MAX_CORNERS);
        std::vector<dtPolyRef> cornerRefs(MAX_CORNERS);

        for (Band const& band : BANDS)
        {
            RouteStats bandStats;

            for (uint32 i = 0; i < samplesPerBand; ++i)
            {
                PolySample const& from = polys[pick(rng)];
                PolySample const* a = &from;
                PolySample const* b = partnerNear(from, band);
                if (!b || b->ref == a->ref)
                    continue;

                ++bandStats.attempted;

                int pathCount = 0;
                dtStatus st = query->findPath(a->ref, b->ref, a->centre, b->centre, &filter,
                                              pathPolys.data(), &pathCount, MAX_PATH);
                if (dtStatusFailed(st) || !pathCount)
                {
                    ++bandStats.failed;
                    continue;
                }
                if (st & DT_BUFFER_TOO_SMALL)
                    ++bandStats.bufferFull;

                // Detour reports a partial path when the goal is unreachable.
                // Those segments are still real mesh, but a partial result is
                // not evidence about routing quality, so only complete paths
                // are audited below.
                if (pathPolys[pathCount - 1] != b->ref)
                {
                    ++bandStats.partial;
                    continue;
                }
                ++bandStats.complete;

                int cornerCount = 0;
                if (dtStatusFailed(query->findStraightPath(a->centre, b->centre, pathPolys.data(), pathCount,
                                                           corners.data(), cornerFlags.data(), cornerRefs.data(),
                                                           &cornerCount, MAX_CORNERS)) || cornerCount < 2)
                    continue;

                for (int c = 0; c + 1 < cornerCount; ++c)
                {
                    float const* p = &corners[c * 3];
                    float const* q = &corners[(c + 1) * 3];
                    ++bandStats.segments;

                    Wow wp = rcToWow(p);
                    Wow wq = rcToWow(q);

                    // --- does the segment cross solid geometry? -------------
                    // Two rays, and the PAIR is what classifies the hit.
                    // A wall blocks both. A staircase blocks only the low one,
                    // because the chord between two corners on a stair dips
                    // below the treads while chest height clears them -- that
                    // was reading as "route through building" until the second
                    // ray was made a requirement rather than an alternative.
                    // An overhang or lintel blocks only the high one.
                    //
                    // VMAP holds WMO and M2 collision only, never terrain, so
                    // no hit here can come from the segment cutting a hillside.
                    bool lowBlocked = !vmap->isInLineOfSight(mapId, wp.x, wp.y, wp.z + 0.5f,
                                                             wq.x, wq.y, wq.z + 0.5f,
                                                             VMAP::ModelIgnoreFlags::Nothing);
                    bool highBlocked = !vmap->isInLineOfSight(mapId, wp.x, wp.y, wp.z + ch.eye,
                                                              wq.x, wq.y, wq.z + ch.eye,
                                                              VMAP::ModelIgnoreFlags::Nothing);

                    if (lowBlocked || highBlocked)
                    {
                        float hx = 0, hy = 0, hz = 0;
                        float rayH = highBlocked ? ch.eye : 0.5f;
                        vmap->getObjectHitPos(mapId, wp.x, wp.y, wp.z + rayH, wq.x, wq.y, wq.z + rayH,
                                              hx, hy, hz, -0.5f);

                        float hitRc[3];
                        wowToRc(Wow{ hx, hy, hz }, hitRc);
                        float fromStart = dist2(p, hitRc);
                        float fromEnd = dist2(q, hitRc);
                        float segLen = dist2(p, q);

                        char detail[256];
                        if (lowBlocked && !highBlocked)
                        {
                            // Something shin-to-waist high. On a staircase this
                            // is the steps themselves and is not a defect; on
                            // open ground it is a crate or a fence rail the
                            // route is trying to walk over.
                            ++bandStats.lowClip;
                            snprintf(detail, sizeof(detail), "%.0f yd segment clips low geometry at (%.1f, %.1f, %.1f), chest height clear",
                                     segLen, hx, hy, hz);
                            routes.add("route/clips-low-geometry", detail, wp);
                        }
                        else if (std::min(fromStart, fromEnd) < 1.0f)
                        {
                            // Brushing a wall it runs alongside. Real, but this
                            // is precisely what the runtime edge margin absorbs.
                            ++bandStats.grazed;
                            snprintf(detail, sizeof(detail), "%.0f yd segment brushes a wall %.1f yd from its end",
                                     segLen, std::min(fromStart, fromEnd));
                            routes.add("route/grazes-wall", detail, wp);
                        }
                        else
                        {
                            ++bandStats.blocked;
                            snprintf(detail, sizeof(detail), "%.0f yd segment enters collision %.1f yd in, at (%.1f, %.1f, %.1f)",
                                     segLen, fromStart, hx, hy, hz);
                            routes.add("route/through-geometry", detail, wp);
                        }
                    }

                    // --- is there room for the character's width? -----------
                    // Corridor width, not distance-to-nearest-wall. The latter
                    // reads 0 whenever the probe sits on a poly edge, which is
                    // where string-pulled paths run by construction, so it
                    // condemns ordinary wall-following. Raycasting the mesh
                    // perpendicular to travel in both directions and summing
                    // gives the width the character actually has to fit into.
                    float segDir[3] = { q[0] - p[0], 0.0f, q[2] - p[2] };
                    float segLen2 = std::sqrt(segDir[0] * segDir[0] + segDir[2] * segDir[2]);
                    if (segLen2 > 0.5f)
                    {
                        float nx = -segDir[2] / segLen2, nz = segDir[0] / segLen2;
                        constexpr float PROBE = 3.0f;

                        for (float t : { 0.25f, 0.5f, 0.75f })
                        {
                            float probe[3] = {
                                p[0] + (q[0] - p[0]) * t,
                                p[1] + (q[1] - p[1]) * t,
                                p[2] + (q[2] - p[2]) * t
                            };

                            float ext[3] = { 2.0f, 4.0f, 2.0f };
                            dtPolyRef ref = 0;
                            float snapped[3] = {};
                            if (dtStatusFailed(query->findNearestPoly(probe, ext, &filter, &ref, snapped)) || !ref)
                                continue;

                            float width = 0.0f;
                            bool measured = true;
                            for (float side : { -1.0f, 1.0f })
                            {
                                float target[3] = { snapped[0] + nx * PROBE * side, snapped[1],
                                                    snapped[2] + nz * PROBE * side };
                                float hitParam = 0.0f, hitNormal[3] = {};
                                dtPolyRef visited[32];
                                int visitedCount = 0;
                                if (dtStatusFailed(query->raycast(ref, snapped, target, &filter, &hitParam,
                                                                  hitNormal, visited, &visitedCount, 32)))
                                {
                                    measured = false;
                                    break;
                                }
                                width += std::min(hitParam, 1.0f) * PROBE;
                            }

                            if (measured && width < ch.radius * 2.0f)
                            {
                                ++bandStats.narrow;
                                Wow wm = rcToWow(snapped);
                                char detail[256];
                                snprintf(detail, sizeof(detail), "corridor %.2f yd wide, character needs %.2f",
                                         width, ch.radius * 2.0f);
                                routes.add("route/narrower-than-character", detail, wm);
                                break;
                            }
                        }
                    }

                    // --- is the elevation change actually walkable? ---------
                    // By angle, not by raw drop: the mesh is baked to walk up
                    // to 55 degrees, so a 38 yd fall over 33 yd of ground is a
                    // legitimate hillside. What is not legitimate is a near
                    // vertical step, which means a ledge got linked to the
                    // ground beneath it.
                    float rise = std::fabs(p[1] - q[1]);
                    float run = dist2(p, q);
                    if (rise > ch.climb)
                    {
                        float slope = std::atan2(rise, std::max(run, 0.01f)) * 57.2957795f;
                        if (slope > 60.0f)
                        {
                            ++bandStats.steep;
                            char detail[256];
                            snprintf(detail, sizeof(detail), "%.0f degree step, %.1f yd over %.1f yd -- not climbable",
                                     slope, rise, run);
                            routes.add("route/unclimbable-step", detail, rcToWow(p));
                        }
                    }
                }
            }

            printf("  %-20s attempted %5u | complete %5u | partial %5u | no path %4u | truncated %u\n",
                   band.name, bandStats.attempted, bandStats.complete, bandStats.partial,
                   bandStats.failed, bandStats.bufferFull);
            printf("  %-20s segments %6u | THROUGH wall %4u (%.2f%%) | grazes %3u | low clip %4u | narrow %4u (%.2f%%) | unclimbable %3u\n",
                   "", bandStats.segments,
                   bandStats.blocked, bandStats.segments ? 100.0 * bandStats.blocked / bandStats.segments : 0.0,
                   bandStats.grazed, bandStats.lowClip,
                   bandStats.narrow, bandStats.segments ? 100.0 * bandStats.narrow / bandStats.segments : 0.0,
                   bandStats.steep);

            stats.attempted += bandStats.attempted;
            stats.complete  += bandStats.complete;
            stats.partial   += bandStats.partial;
            stats.failed    += bandStats.failed;
            stats.bufferFull += bandStats.bufferFull;
            stats.segments  += bandStats.segments;
            stats.blocked   += bandStats.blocked;
            stats.grazed    += bandStats.grazed;
            stats.lowClip   += bandStats.lowClip;
            stats.narrow    += bandStats.narrow;
            stats.steep     += bandStats.steep;
        }
    }

    // ---------------------------------------------------------------------
    // Setup borrowed from PathGenerator: VMAP needs the parent-map chain from
    // Map.db2 and liquid sound banks from LiquidType.db2.
    // ---------------------------------------------------------------------
    std::unordered_map<uint32, uint8> _liquidTypes;
    std::unordered_map<uint32, int16> _parentMap;

    int16 parentOf(uint32 mapId)
    {
        auto itr = _parentMap.find(mapId);
        return itr != _parentMap.end() ? itr->second : int16(-1);
    }

    void loadDb2(boost::filesystem::path const& inputDirectory, std::string const& locale)
    {
        {
            DB2FileLoader db2;
            DB2FileSystemSource source((inputDirectory / "dbc" / locale / "LiquidType.db2").string());
            db2.Load(&source, &LiquidTypeLoadInfo::Instance);
            for (uint32 x = 0; x < db2.GetRecordCount(); ++x)
                if (DB2Record record = db2.GetRecord(x))
                    _liquidTypes[record.GetId()] = record.GetUInt8("SoundBank");
        }
        {
            DB2FileLoader db2;
            DB2FileSystemSource source((inputDirectory / "dbc" / locale / "Map.db2").string());
            db2.Load(&source, &MapLoadInfo::Instance);
            for (uint32 x = 0; x < db2.GetRecordCount(); ++x)
            {
                DB2Record record = db2.GetRecord(x);
                if (!record)
                    continue;

                int16 parentMapId = int16(record.GetUInt16("ParentMapID"));
                if (parentMapId < 0)
                    parentMapId = int16(record.GetUInt16("CosmeticParentMapID"));

                _parentMap[record.GetId()] = parentMapId;
            }
        }
    }

    std::unique_ptr<VMAP::VMapManager> createVMapManager(uint32 mapId)
    {
        auto vmgr = std::make_unique<VMAP::VMapManager>();
        uint32 cur = mapId;
        for (;;)
        {
            int32 parentMapId = parentOf(cur);
            vmgr->InitializeThreadUnsafe(cur, parentMapId);
            if (parentMapId < 0)
                break;
            cur = uint32(parentMapId);
        }

        vmgr->GetLiquidFlagsPtr = [](uint32 liquidId) -> uint32
        {
            auto itr = _liquidTypes.find(liquidId);
            return itr != _liquidTypes.end() ? (1u << itr->second) : 0u;
        };
        vmgr->LoadPathOnlyModels = true;
        vmgr->IsVMAPDisabledForPtr = [](uint32, uint8) { return false; };
        return vmgr;
    }

    void usage()
    {
        printf(
            "mesh_audit -- cross-check a baked navmesh against its source collision\n"
            "\n"
            "  --input <dir>    extraction root, holding dbc/ maps/ vmaps/   (default C:/tc/extract)\n"
            "  --mmaps <dir>    directory of .mmap/.mmtile to audit          (default <input>/../mmaps_out/mmaps)\n"
            "  --map <id>       map to audit; repeatable. default: 0 and 1\n"
            "  --routes <n>     route samples per map                        (default 2000)\n"
            "  --radius <yd>    character collision radius                   (default 0.60)\n"
            "  --seed <n>       RNG seed, for reproducible runs              (default 1)\n"
            "  --densest <n>    audit routes only in the n most complex tiles (cities, towns)\n");
    }
}

int main(int argc, char** argv)
{
    Trinity::Locale::Init();
    Trinity::Banner::Show("Navmesh auditor", [](char const* text) { printf("%s\n", text); }, nullptr);

    std::string input = "C:/tc/extract";
    std::string mmaps;
    std::vector<uint32> maps;
    uint32 routeSamples = 2000;
    int densest = 0;
    uint32 seed = 1;
    Character ch;

    for (int i = 1; i < argc; ++i)
    {
        auto next = [&](char const* what) -> char const*
        {
            if (i + 1 >= argc)
            {
                printf("missing value for %s\n", what);
                exit(2);
            }
            return argv[++i];
        };

        if (!strcmp(argv[i], "--input"))        input = next("--input");
        else if (!strcmp(argv[i], "--mmaps"))   mmaps = next("--mmaps");
        else if (!strcmp(argv[i], "--map"))     maps.push_back(uint32(atoi(next("--map"))));
        else if (!strcmp(argv[i], "--routes"))  routeSamples = uint32(atoi(next("--routes")));
        else if (!strcmp(argv[i], "--radius"))  ch.radius = float(atof(next("--radius")));
        else if (!strcmp(argv[i], "--seed"))    seed = uint32(atoi(next("--seed")));
        else if (!strcmp(argv[i], "--densest")) densest = atoi(next("--densest"));
        else { usage(); return 2; }
    }

    if (mmaps.empty())
        mmaps = "C:/tc/mmaps_out/mmaps";
    if (maps.empty())
        maps = { 0, 1 };

    boost::filesystem::path inputDir(input);

    std::vector<std::string> locales;
    for (auto itr = boost::filesystem::directory_iterator(inputDir / "dbc");
         itr != boost::filesystem::directory_iterator(); ++itr)
        if (boost::filesystem::is_directory(*itr))
            locales.push_back(itr->path().filename().string());

    if (locales.empty())
    {
        printf("no dbc locale directory under %s/dbc\n", input.c_str());
        return 3;
    }

    try
    {
        loadDb2(inputDir, locales[0]);
    }
    catch (std::exception const& e)
    {
        printf("failed to read DB2s: %s\n", e.what());
        return 4;
    }

    std::string vmapDir = (inputDir / "vmaps").string();

    for (uint32 mapId : maps)
    {
        printf("\n########## map %u ##########\n", mapId);

        uint32 loaded = 0, rejected = 0;
        dtNavMesh* mesh = loadNavMesh(mmaps, mapId, loaded, rejected);
        if (!mesh)
            continue;

        printf("  tiles: %u loaded, %u rejected\n", loaded, rejected);

        std::unique_ptr<VMAP::VMapManager> vmap = createVMapManager(mapId);
        vmap->setEnableLineOfSightCalc(true);
        vmap->setEnableHeightCalc(true);

        uint32 vmapTiles = 0;
        for (uint32 x = 0; x < 64; ++x)
            for (uint32 y = 0; y < 64; ++y)
                if (vmap->loadMap(vmapDir, mapId, x, y) == VMAP::LoadResult::Success)
                    ++vmapTiles;

        printf("  vmap tiles: %u loaded\n", vmapTiles);
        if (!vmapTiles)
            printf("  WARNING: no collision loaded -- route checks will pass vacuously.\n");

        std::mt19937 rng(seed + mapId);

        Report topo;
        std::vector<PolySample> polys;
        collectPolys(mesh, polys, topo);
        printf("  polys: %zu\n", polys.size());

        printf("\n-- convention --\n");
        auditConvention(vmap.get(), mapId, polys, rng);

        printf("\n-- topology --\n");
        auditAreas(mesh);
        auditConnectivity(mesh, polys, topo);

        dtNavMeshQuery* query = dtAllocNavMeshQuery();
        if (!query || dtStatusFailed(query->init(mesh, 8192)))
        {
            printf("  query init failed\n");
            continue;
        }

        auditVerticalAmbiguity(query, polys, rng, topo);

        // Topology above ran over the whole map; routes may be narrowed to the
        // built-up tiles, which is where a character meets doorframes, carts
        // and market stalls rather than open hillside.
        std::vector<PolySample> routePolys = polys;
        if (densest > 0)
        {
            printf("\n-- built-up areas --\n");
            routePolys = densestTiles(mesh, polys, densest);
        }

        Report routes;
        RouteStats stats;
        printf("\n-- routes (%u samples per distance band%s) --\n",
               routeSamples, densest > 0 ? ", built-up tiles only" : "");
        auditRoutes(mesh, query, vmap.get(), mapId, routePolys, ch, routeSamples, rng, routes, stats);

        printf("  ----\n  totals               attempted %5u | complete %5u | partial %5u | no path %4u\n",
               stats.attempted, stats.complete, stats.partial, stats.failed);

        topo.print("topology findings");
        routes.print("route findings");

        dtFreeNavMeshQuery(query);
        dtFreeNavMesh(mesh);
        vmap->unloadMap(mapId);
    }

    return 0;
}
