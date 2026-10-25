/*
 * wk_luaall.c — Single compilation unit for vendored Lua 5.1 core.
 *
 * Compiles the WoW-struct-compatible Lua 5.1 source into one object file.
 * All public symbols are renamed wk_lua_* via the prefix header to avoid
 * collision with WoW's own lua_* symbols.
 *
 * Functions compiled here operate directly on WoW's lua_State because
 * the struct layouts match exactly (TValue=24 bytes, CallInfo=56 bytes,
 * GCheader=18 bytes, taint fields, etc.).  No separate Lua state is
 * created — these are direct struct manipulations on the same state WoW
 * uses.
 *
 * We do NOT need loadbuffer (kept as WoW RVA — it's the parser/compiler).
 * We do NOT compile standard library openers (lbaselib, lmathlib, etc.).
 */

/* Apply wk_lua_* symbol renames BEFORE any Lua headers */
#include "../vendor/lua/wk_lua_prefix.h"

/* luaall_c makes all internal functions static (no symbol leaks) */
#define luaall_c
#define LUA_CORE

/* Lua core modules — order matters for dependencies */
#include "../vendor/lua/src/lapi.c"
#include "../vendor/lua/src/ldo.c"
#include "../vendor/lua/src/lfunc.c"
#include "../vendor/lua/src/lgc.c"
#include "../vendor/lua/src/lmem.c"
#include "../vendor/lua/src/lobject.c"
#include "../vendor/lua/src/lstate.c"
#include "../vendor/lua/src/lstring.c"
#include "../vendor/lua/src/ltable.c"
#include "../vendor/lua/src/ltm.c"
#include "../vendor/lua/src/lvm.c"
#include "../vendor/lua/src/ldebug.c"
#include "../vendor/lua/src/lzio.c"
#include "../vendor/lua/src/lopcodes.c"

/* ldo.c pulls in <windows.h> which #defines LoadString -> LoadStringA.
 * lundump.c has a static function also named LoadString. Undo the macro. */
#ifdef LoadString
#undef LoadString
#endif
#include "../vendor/lua/src/lundump.c"

/* Parser/compiler/dump — not called directly (we use WoW's loadbuffer RVA),
 * but ldo.c references luaY_parser, lstate.c references luaX_init, and
 * lapi.c references luaU_dump. Include them to satisfy the linker. */
#include "../vendor/lua/src/ldump.c"
#include "../vendor/lua/src/llex.c"
#include "../vendor/lua/src/lcode.c"
#include "../vendor/lua/src/lparser.c"

/* Auxiliary library (for luaL_loadbuffer fallback if ever needed) */
#include "../vendor/lua/src/lauxlib.c"
