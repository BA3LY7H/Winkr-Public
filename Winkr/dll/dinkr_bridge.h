#pragma once
/* dinkr_bridge.h -- Lua bridge functions + vendored Lua API macros */

#include "dinkr_internal.h"
#include "../vendor/lua/wk_lua_prefix.h"
#include "../vendor/lua/src/lua.h"
#include "../vendor/lua/src/lauxlib.h"

/* WorldFrame / camera offsets (68887: live camdump-derived) */
#define CAM_OFF_CCAMERA    0x4B0   /* ptr: CCamera object in WorldFrameUI (disasm-confirmed) */

/* WorldFrame viewport / projection (68887) */
#define WORLDFRAME_OFF_VIEWPROJ   0x388  /* float[16] col-major VP matrix; W2S: clip=M*(world-eye), player->(0.50,0.56) verified */
#define WFUI_OFF_VIEWPORT_MIN_X   0x210   /* NOTE: 68887 viewport offset unverified (W2S returns normalized 0-1; caller scales by window) */
#define WFUI_OFF_VIEWPORT_MIN_Y   0x214
#define WFUI_OFF_VIEWPORT_MAX_X   0x218
#define WFUI_OFF_VIEWPORT_MAX_Y   0x21C

/* Camera/WorldFrame field offsets (68887: live camdump-derived) */
#define CAM_OFF_POSDESC    0x150   /* WorldFrame + pos_desc pointer (unverified 68887) */
#define CCAM_OFF_EYE       0x10    /* vec3f: camera eye position (=(-258,-2518,40), ~28yd from player) */
#define CCAM_OFF_LOOKAT    0x20    /* approx: rotation/dir region (cosmetic; true lookat point is wf+0x318) */
#define CCAM_OFF_FOV       0x40    /* float: camera FOV radians (=1.571=pi/2) */

/* Dummynode bridging -- vendored ltable.c needs WoW's .rdata sentinel */
extern void mk_lua_set_host_dummynode(uintptr_t addr);

/* Compatibility macros: map old function-pointer names to vendored calls.
 * All 430 existing call sites use void* L; vendored functions take
 * lua_State* which is the same pointer at ABI level. */
#define s_pSettop(L, idx)          wk_lua_settop((lua_State*)(L), (idx))
#define s_pPushnil(L)              wk_lua_pushnil((lua_State*)(L))
#define s_pPushstring(L, s)        wk_lua_pushstring((lua_State*)(L), (s))
#define s_pPushboolean(L, b)       wk_lua_pushboolean((lua_State*)(L), (b))
#define s_pPushnumber(L, n)        wk_lua_pushnumber((lua_State*)(L), (n))
#define s_pPushlstring(L, s, l)    wk_lua_pushlstring((lua_State*)(L), (s), (l))
#define s_pCreatetable(L, a, r)    wk_lua_createtable((lua_State*)(L), (a), (r))
#define s_pRawseti(L, i, n)        wk_lua_rawseti((lua_State*)(L), (i), (n))
#define s_pTolstring(L, i, len)    wk_lua_tolstring((lua_State*)(L), (i), (len))
#define s_pSetField(L, i, k)       wk_lua_setfield((lua_State*)(L), (i), (k))

/* Local pointer names used in SetupModLoader -- same mapping */
#define pPushCClosure(L, fn, n)    wk_lua_pushcclosure((lua_State*)(L), (lua_CFunction)(fn), (n))
#define pSetField(L, i, k)         wk_lua_setfield((lua_State*)(L), (i), (k))
#define pTolstring(L, i, len)      wk_lua_tolstring((lua_State*)(L), (i), (len))
#define pSettop(L, idx)            wk_lua_settop((lua_State*)(L), (idx))
#define pLoadBuffer(L, b, s, n)    s_pLoadBuffer((L), (b), (s), (n))
#define pPcall(L, a, r, e)         s_pPcall((L), (a), (r), (e))

/* --- TValue direct-read state (defined in dinkr_bridge.c) --- */
extern int          g_directStackReadOK;
extern unsigned int g_tvSize;

/* NPC push tick (shared between bridge.c and mods.c) */
extern DWORD        s_lastNPCPushTick;

/* Calibration */
void CalibrateDirectStackRead(void* L);

/* ========================================================================
** TValue direct-read macros & inline helpers
**
** Moved here from dinkr_bridge.c so all split bridge files can use them.
** WoW TValue layout (24 bytes default, calibrated at runtime):
**   +0x00  Value (double/pointer/int)  +0x08  tt (type)  +0x09  is_secret
** ======================================================================== */

#define WK_LUA_STATE_TOP   0x28
#define WK_LUA_STATE_BASE  0x30

#define WK_TV_BASE(L)   (*(uintptr_t*)((uintptr_t)(L) + WK_LUA_STATE_BASE))
#define WK_TV_TOP(L)    (*(uintptr_t*)((uintptr_t)(L) + WK_LUA_STATE_TOP))
#define WK_TV_AT(L,idx) (WK_TV_BASE(L) + (uintptr_t)((idx)-1) * g_tvSize)
#define WK_TV_TYPE(tv)  (*(uint8_t*)((tv) + 8))

#define WK_LUA_TNIL      0
#define WK_LUA_TBOOLEAN  1
#define WK_LUA_TNUMBER   3
#define WK_LUA_TSTRING   4

static inline double wk_tv_number(uintptr_t tv) {
    return *(double*)tv;
}

static inline const char* wk_tv_string(uintptr_t tv, size_t* out_len) {
    uintptr_t tstr = *(uintptr_t*)tv;
    if (!tstr || IsBadReadPtr((const void*)tstr, 0x28)) {
        if (out_len) *out_len = 0;
        return NULL;
    }
    if (out_len) *out_len = *(size_t*)(tstr + 0x18);
    return (const char*)(tstr + 0x20);
}

static inline int wk_tv_bool(uintptr_t tv) {
    return *(int*)tv;
}

static inline double wk_arg_number(void* L, int idx) {
    if (!g_directStackReadOK || idx < 1) return 0.0;
    uintptr_t tv = WK_TV_AT(L, idx);
    if (IsBadReadPtr((const void*)tv, g_tvSize)) return 0.0;
    return (WK_TV_TYPE(tv) == WK_LUA_TNUMBER) ? wk_tv_number(tv) : 0.0;
}

static inline const char* wk_arg_string(void* L, int idx, size_t* out_len) {
    if (!g_directStackReadOK || idx < 1) {
        if (out_len) *out_len = 0;
        return NULL;
    }
    uintptr_t tv = WK_TV_AT(L, idx);
    if (IsBadReadPtr((const void*)tv, g_tvSize)) {
        if (out_len) *out_len = 0;
        return NULL;
    }
    if (WK_TV_TYPE(tv) != WK_LUA_TSTRING) {
        if (out_len) *out_len = 0;
        return NULL;
    }
    return wk_tv_string(tv, out_len);
}

static inline int wk_arg_bool(void* L, int idx) {
    if (!g_directStackReadOK || idx < 1) return 0;
    uintptr_t tv = WK_TV_AT(L, idx);
    if (IsBadReadPtr((const void*)tv, g_tvSize)) return 0;
    if (WK_TV_TYPE(tv) == WK_LUA_TBOOLEAN) return wk_tv_bool(tv);
    if (WK_TV_TYPE(tv) == WK_LUA_TNIL) return 0;
    return 1;
}

static inline int wk_arg_is_nil(void* L, int idx) {
    if (!g_directStackReadOK || idx < 1) return 1;
    uintptr_t tv = WK_TV_AT(L, idx);
    if (IsBadReadPtr((const void*)tv, g_tvSize)) return 1;
    return WK_TV_TYPE(tv) == WK_LUA_TNIL;
}

static inline double dinkr_read_stack_number(void* L, int idx) {
    return wk_arg_number(L, idx);
}

static inline int dinkr_gettop_inline(void* L) {
    uintptr_t top  = *(uintptr_t*)((uintptr_t)L + WK_LUA_STATE_TOP);
    uintptr_t base = *(uintptr_t*)((uintptr_t)L + WK_LUA_STATE_BASE);
    if (top <= base || g_tvSize == 0) return 0;
    return (int)((top - base) / g_tvSize);
}

/* Camera helper — defined in bridge_camera.c, used by bridge_misc.c (dbg) */
uintptr_t resolve_camera_object(void);

/* --- All bridge functions (registered in ExecuteModsOnMainThread) --- */
int __fastcall dinkr_CameraPosition_lua(void* L);
int __fastcall dinkr_CameraDiag_lua(void* L);
int __fastcall dinkr_WorldToScreen_lua(void* L);
/* Navmesh (Detour) — dll/bridge/dinkr_bridge_nav.c */
int __fastcall dinkr_GeneratePath_lua(void* L);
int __fastcall dinkr_NavNearest_lua(void* L);
int __fastcall dinkr_NavPolys_lua(void* L);
int __fastcall dinkr_NavStatus_lua(void* L);
int __fastcall dinkr_LiveMeshBegin_lua(void* L);
int __fastcall dinkr_LiveMeshStep_lua(void* L);
int __fastcall dinkr_LiveMeshStatus_lua(void* L);
int __fastcall dinkr_LiveMeshTileAt_lua(void* L);
int __fastcall dinkr_LiveMeshHave_lua(void* L);
int __fastcall dinkr_LiveMeshCancel_lua(void* L);
int __fastcall dinkr_LiveMeshWalls_lua(void* L);
int __fastcall dinkr_LiveMeshAgent_lua(void* L);
int __fastcall dinkr_LiveMeshClimb_lua(void* L);
int __fastcall dinkr_LiveMeshDiagonals_lua(void* L);
int __fastcall dinkr_LiveMeshProbeSkip_lua(void* L);
int __fastcall dinkr_LiveMeshTileInfo_lua(void* L);
int __fastcall dinkr_NavLastRequest_lua(void* L);
int __fastcall dinkr_NavWallDist_lua(void* L);
int __fastcall dinkr_GetObjectCount(void* L);
int __fastcall dinkr_GetObjectWithIndex(void* L);
int __fastcall dinkr_ObjectType(void* L);
int __fastcall dinkr_ObjectPosition(void* L);
int __fastcall dinkr_ObjectFacing(void* L);
int __fastcall dinkr_ObjectRotation(void* L);
int __fastcall dinkr_ObjectID(void* L);
int __fastcall dinkr_ObjectName(void* L);
int __fastcall dinkr_ObjectCreator(void* L);
int __fastcall dinkr_ObjectTarget(void* L);
int __fastcall dinkr_ObjectCastingTarget(void* L);
int __fastcall dinkr_IsValidObject(void* L);
int __fastcall dinkr_IsPlayerGuid(void* L);
int __fastcall dinkr_IsTargetGuid(void* L);
int __fastcall dinkr_IsFocusGuid(void* L);
int __fastcall dinkr_LuaSetNPC(void* L);
int __fastcall dinkr_ObjectCombatReach(void* L);
int __fastcall dinkr_ObjectBoundingRadius(void* L);
int __fastcall dinkr_ObjectCreatureType(void* L);
int __fastcall dinkr_ObjectATInfo(void* L);
int __fastcall dinkr_ObjectMovementFlag(void* L);
int __fastcall dinkr_ObjectDescriptor(void* L);
int __fastcall dinkr_DumpObject(void* L);
int __fastcall dinkr_ObjectSpecializationID(void* L);
int __fastcall dinkr_ObjectHeight(void* L);
int __fastcall dinkr_ObjectLootable(void* L);
int __fastcall dinkr_GetMapID(void* L);
int __fastcall dinkr_ReadFile(void* L);
int __fastcall dinkr_WriteFile(void* L);
int __fastcall dinkr_ListFiles(void* L);
int __fastcall dinkr_ListDirectories(void* L);
int __fastcall dinkr_IsWindowForeground(void* L);
int __fastcall dinkr_GetKeyState(void* L);
int __fastcall dinkr_Call(void* L);
int __fastcall dinkr_UnitAuras(void* L);
int __fastcall dinkr_Missiles(void* L);
int __fastcall dinkr_TraceLine_lua(void* L);
int __fastcall dinkr_ScreenToWorld_lua(void* L);
int __fastcall dinkr_ObjectInteract(void* L);
int __fastcall dinkr_NativeCast_lua(void* L);
int __fastcall dinkr_FaceDirection_lua(void* L);
int __fastcall dinkr_SendMovementHeartbeat_lua(void* L);
int __fastcall dinkr_ClickPosition_lua(void* L);
int __fastcall dinkr_SpellIsTargeting_lua(void* L);
int __fastcall dinkr_SpellCancelTargeting_lua(void* L);
int __fastcall dinkr_SpellTargetingReady_lua(void* L);
int __fastcall dinkr_CombatLogGetCurrentEventInfo_lua(void* L);
int __fastcall dinkr_dbg_lua(void* L);

