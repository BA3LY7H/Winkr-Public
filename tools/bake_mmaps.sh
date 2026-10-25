#!/usr/bin/env bash
#
# bake_mmaps.sh -- rebuild the staged Detour navmesh with the tuned parameters.
#
# WHY THIS FILE EXISTS. The parameters below are not the generator's defaults
# and are not recoverable from the tiles once they are baked. They were lost
# once already and had to be reconstructed by md5-matching a staged tile against
# every candidate output directory. Write them down.
#
# THE PARAMETERS, and why each one differs from TrinityCore stock:
#
#   --agentHeight 2.0   TC ships 1.6, which describes a server-side NPC rather
#   --agentClimb  1.0   than a player. A mesh built to 1.6 yd height walks under
#                       arches a 2 yd character cannot fit through; one built to
#                       1.6 yd climb bridges ledges a player cannot step up.
#                       These match this repo's own LiveMesh (dinkr_livemesh.cpp).
#
#   --simplify 0.9      Recast's contour tolerance in VOXELS. TC ships 1.8, which
#                       at the 0.2666 yd cell lets a mesh border sit half a yard
#                       from the true walkable boundary -- far enough, in a city,
#                       to put walkable surface inside a wall.
#
#   --detailDist 4      Detail-mesh sampling in CELLS. TC ships 16, sampling
#                       terrain height only every 4.27 yd. The detail mesh is what
#                       getPolyHeight reads, so this decides whether the mesh sits
#                       on the ground or hovers over dips between samples. It costs
#                       detail verts, NOT routing polys.
#
#   --maxAngle 50 --maxAngleNotSteep 45
#
#   agentRadius is DELIBERATELY NOT PASSED. It stays at TC stock 0.5333 yd.
#   Edge clearance is applied at runtime instead, by DinkrNavSetEdgeMargin().
#
# REQUIREMENTS. The tools are MSYS2 mingw64 builds and will not start from a
# plain shell -- they need libicuuc*.dll, which lives in the mingw64 bin dir.
# That is what PATH below is for; without it every map fails with rc=127 and
# "error while loading shared libraries", having written nothing.
#
# USAGE
#   tools/bake_mmaps.sh              # every map the extract has
#   tools/bake_mmaps.sh 33 43 389    # only these map ids
#
# Output goes to $OUT; stage it by copying $OUT/. over projects/mmaps/, which IS
# committed so that a fresh clone can path immediately. A re-bake rewrites every
# tile, so committing a second one costs another 2.7 GB of history -- purge the
# old set with git-filter-repo rather than stacking bakes.

set -u

export PATH="/c/msys64/mingw64/bin:$PATH"

TC="${TC:-/c/tc}"
GEN="$TC/build/bin/Release/mmaps_generator.exe"
IN="${IN:-C:/tc/extract}"
OUT="${OUT:-C:/tc/mmapsPlayer}"
THREADS="${THREADS:-20}"
LOG="${LOG:-$TC/bake_mmaps.log}"

PARAMS=(--simplify 0.9 --detailDist 4 --maxAngle 50 --maxAngleNotSteep 45
        --agentHeight 2.0 --agentClimb 1.0)

[ -x "$GEN" ] || { echo "no generator at $GEN" >&2; exit 1; }
"$GEN" --help >/dev/null 2>&1 || {
	echo "generator will not start -- is /c/msys64/mingw64/bin present?" >&2; exit 1; }

# Map ids come from the extract itself, so a map the client does not have is
# never attempted. The staged set used to carry 59 Outland/Northrend maps left
# over from a WotLK extract; Classic Era cannot load any of them.
if [ $# -gt 0 ]; then
	MAPS=("$@")
else
	mapfile -t MAPS < <(ls "${IN#C:}/maps" 2>/dev/null | cut -c1-4 | sort -u | sed 's/^0*//')
fi

: > "$LOG"
n=0
for M in "${MAPS[@]}"; do
	n=$((n + 1))
	printf '=== [%d/%d] map %s  %s ===\n' "$n" "${#MAPS[@]}" "$M" "$(date +%H:%M:%S)" | tee -a "$LOG"
	"$GEN" --input "$IN" --output "$OUT" "${PARAMS[@]}" --threads "$THREADS" "$M" >> "$LOG" 2>&1
	rc=$?
	tiles=$(ls "${OUT#C:}/mmaps" 2>/dev/null | grep -c "^$(printf '%04d' "$M")_")
	printf -- '--- map %s rc=%d tiles=%d ---\n' "$M" "$rc" "$tiles" | tee -a "$LOG"
done
echo "=== BAKE COMPLETE $(date) ===" | tee -a "$LOG"

# Verify before staging. Zero rejected tiles and zero "no path" is the bar;
# through-geometry and narrow-corridor findings are expected in dungeon
# interiors and are not load failures.
echo
echo "verify with:"
echo "  $TC/build/bin/Release/mesh_audit.exe --input $IN --mmaps $OUT/mmaps --map 33"
