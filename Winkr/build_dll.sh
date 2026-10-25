#!/bin/bash
# =============================================================================
# build_dll.sh — build dinkr.dll only (no GUI), from bash/MSYS2
# -----------------------------------------------------------------------------
# WHY THIS EXISTS ALONGSIDE build.bat. build.bat is the full 7-step build and is
# the documented entry point, but it is stored with LF endings and cmd refuses to
# run it ("not recognized"), which is what build_crlf.bat works around. From a
# bash shell it is simpler to drive gcc directly, and iterating on the DLL alone
# skips the ImGui/GUI half entirely.
#
# PATHS ARE DERIVED, NOT HARDCODED. This previously pointed at /s/Dev/Winkr/WINKR
# — a path from a different machine — so it could not run anywhere else. It now
# resolves its own directory, so it works from any checkout location.
#
# Usage:
#   ./build_dll.sh          incremental (reuses build/obj)
#   ./build_dll.sh clean    recompile everything, including Recast/Detour
# =============================================================================
set -u

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$HERE" || exit 1

# MSYS2 mingw64 toolchain. Prepended rather than replacing PATH so git, python
# and the rest of the environment still resolve.
export PATH="/c/msys64/mingw64/bin:$PATH"

command -v gcc >/dev/null || { echo "gcc not found — is MSYS2 mingw64 installed?"; exit 1; }

OBJ=build/obj
mkdir -p "$OBJ"

CFLAGS="-Wall -O2 -DNDEBUG -Ishared -Idll"
# Detour/Recast: no exceptions or RTTI keeps the injected DLL free of the C++
# unwinder. DT_POLYREF64 is required for the maxTiles/maxPolys budget.
NAVFLAGS="-w -O2 -DNDEBUG -DDT_POLYREF64 -std=c++17 -fno-exceptions -fno-rtti -Ishared -Idll -Ivendor/detour/Include -Ivendor/recast/Include"

if [ "${1:-}" = "clean" ]; then
	echo "=== clean ==="
	rm -rf "$OBJ"
	mkdir -p "$OBJ"
fi

fail=0
cc() {  # cc <out-name> <source> [extra flags...]
	local out="$1" src="$2"; shift 2
	gcc $CFLAGS "$@" -c -o "$OBJ/$out.o" "$src" || { echo "  FAILED: $src"; fail=1; }
}

echo "=== [1/4] vendored Lua ==="
gcc -w -O2 -DNDEBUG -Ishared -Ivendor/lua/src -c -o "$OBJ/dll_wk_luaall.o" dll/wk_luaall.c || fail=1

echo "=== [2/4] DLL C sources ==="
for f in ipc/dinkr_ipc om/dinkr_om security/dinkr_stealth security/dinkr_security \
         om/dinkr_om_enum core/dinkr_scanner; do
	cc "dll_$(basename "$f")" "dll/$f.c"
done
# These include the Lua headers, so they need the vendored Lua include path.
for f in bridge/dinkr_bridge_core bridge/dinkr_bridge_camera bridge/dinkr_bridge_objects \
         bridge/dinkr_bridge_combat bridge/dinkr_bridge_actions bridge/dinkr_bridge_misc \
         mods/dinkr_mods core/dinkr_payload core/dinkr_selfheal; do
	cc "dll_$(basename "$f")" "dll/$f.c" -Ivendor/lua/src
done
cc dll_dinkr_bridge_nav dll/bridge/dinkr_bridge_nav.c -Ivendor/lua/src -Idll/nav

echo "=== [3/4] Recast + Detour + LiveMesh ==="
# Only rebuilt when missing: these are vendored and never change, and they are
# the slow half of the build.
build_cpp() {  # build_cpp <out-name> <source> [extra flags...]
	local out="$1" src="$2"; shift 2
	[ -f "$OBJ/$out.o" ] && return 0
	gcc $NAVFLAGS "$@" -c -o "$OBJ/$out.o" "$src" || { echo "  FAILED: $src"; fail=1; }
}
for n in Recast RecastAlloc RecastArea RecastAssert RecastContour RecastFilter \
         RecastLayers RecastMesh RecastMeshDetail RecastRasterization RecastRegion; do
	build_cpp "rc_$n" "vendor/recast/Source/$n.cpp"
done
for n in Alloc Assert Common NavMesh NavMeshBuilder NavMeshQuery Node; do
	out="dt_$(echo "$n" | tr 'A-Z' 'a-z')"
	build_cpp "$out" "vendor/detour/Source/Detour$n.cpp"
done
build_cpp dll_dinkr_nav      dll/nav/dinkr_nav.cpp      -Idll/nav
build_cpp dll_dinkr_livemesh dll/nav/dinkr_livemesh.cpp -Idll/nav

if [ "$fail" -ne 0 ]; then
	echo "*** COMPILE FAILED — see errors above ***"
	exit 1
fi

echo "=== [4/4] link dinkr.dll ==="
# -Wl,-e,DinkrDllEntry: reflective injection calls the entry point directly, so
# it must be the DLL's declared entry rather than DllMain.
g++ -shared -static -s -o build/dinkr.dll \
	"$OBJ"/dll_*.o "$OBJ"/rc_*.o "$OBJ"/dt_*.o \
	-Wl,-e,DinkrDllEntry -lkernel32 -lpsapi -lversion -lwinmm || {
		echo "*** DLL LINK FAILED ***"; exit 1; }

ls -la build/dinkr.dll
echo "DLL_OK"
