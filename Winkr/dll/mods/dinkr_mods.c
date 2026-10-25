/* dinkr_mods.c -- mod file loading, hook management, Lua bridge registration */

#include "dinkr_mods.h"
#include "dinkr_bridge.h"
#include "core/dinkr_selfheal.h"
#include "dinkr_security.h"
#include "dinkr_om_enum.h"
#include <stdarg.h>
#include <stdio.h>

/* Crash-proof logging: opens/flushes/closes each call so the last line survives
 * a hard WoW crash (the IPC ring log is lost when the GUI stops polling). */
static void DirectModLog(const char* fmt, ...) {
    char buf[1400];
    va_list ap; va_start(ap, fmt);
    vsnprintf(buf, sizeof(buf), fmt, ap);
    va_end(ap);
    FILE* f = fopen("C:\\projects\\dinkr_modload.txt", "a");
    if (f) { fputs(buf, f); fputc('\n', f); fflush(f); fclose(f); }
}


#define MAX_MODS      64
#define MAX_MOD_SIZE  (1024 * 1024)  /* 1 MB per file */

/* 0 = run taint-intact (loadstring safe, mods run tainted -- diagnostic/baseline).
 * 1 = clear g_taint_handler_ptr during mod exec (needs global patches or the
 *     Splash parser NULL-derefs on 68887). */
#ifndef DINKR_CLEAR_TAINT
#define DINKR_CLEAR_TAINT 0
#endif

typedef struct {
    char  filename[MAX_PATH];
    char  directory[MAX_PATH];
    char* buffer;
    DWORD size;
} ModFile;

ModFile g_modFiles[MAX_MODS];
int     g_modFileCount    = 0;

/* Saved taint handler — accessible by bridge functions for CLEU */
void* g_savedTaintHandler = NULL;
volatile LONG g_modsLoaded = FALSE;
void*   g_lastLuaState   = NULL;

DWORD   g_mainThreadId   = 0;
HWND    g_gameWindow     = NULL;
HHOOK   g_messageHook    = NULL;

/* WoW trampoline pointers -- set in ExecuteModsOnMainThread */
lua_pcall_t        s_pPcall        = NULL;
luaL_loadbuffer_t  s_pLoadBuffer   = NULL;

typedef struct {
    void** handlerPtr;
    void*  saved;
} LuaTaintScope;

static volatile LONG g_taintScopeRingWrite = 0;
static char g_taintScopeRing[8192];

static void TaintScopeRingWrite(const char* msg) {
    if (!msg) return;
    size_t len = strlen(msg);
    if (len == 0) return;
    LONG pos = InterlockedExchangeAdd(&g_taintScopeRingWrite, (LONG)len);
    const LONG mask = (LONG)(sizeof(g_taintScopeRing) - 1);
    for (LONG i = 0; i < (LONG)len; i++) {
        g_taintScopeRing[(pos + i) & mask] = msg[i];
    }
}

static void TaintScopeRingLog(const char* fmt, ...) {
    if (!fmt) return;
    char line[192];
    va_list args;
    va_start(args, fmt);
    int n = vsnprintf(line, sizeof(line), fmt, args);
    va_end(args);
    if (n <= 0) return;
    size_t written = (size_t)(n >= (int)sizeof(line) ? (int)sizeof(line) - 1 : n);
    if (written + 1 < sizeof(line)) {
        line[written++] = '\n';
        line[written] = '\0';
    }
    TaintScopeRingWrite(line);
}

static LuaTaintScope EnterLuaTaintScope(void) {
    LuaTaintScope scope = { 0 };
    LPBYTE base = g_modLoaderBase ? g_modLoaderBase : g_wowBase;
    if (!base) {
        TaintScopeRingLog("taint_scope enter skipped base=null");
        return scope;
    }
#if !RVA_SET_IS_VERIFIED
    /* SAFE MODE: RVA set is stale for this build. Writing NULL through a stale
     * g_taint_handler_ptr would corrupt unrelated WoW memory. Skip entirely. */
    TaintScopeRingLog("taint_scope SKIPPED -- RVA set unverified for build %d", (int)EXPECTED_BUILD);
    DebugLog("[mods] SAFE MODE: taint scope skipped (RVAs stale for this build)");
    return scope;
#else
    scope.handlerPtr = (void**)((uintptr_t)base + RVA_G_TAINT_HANDLER_PTR);
#if !DINKR_CLEAR_TAINT
    /* TEST MODE: do NOT clear taint. luaL_loadbuffer's Splash-obfuscated parser
     * NULL-derefs when g_taint_handler_ptr==0 (no global patches to neutralize it),
     * and the framework calls loadstring at runtime. Run everything taint-intact to
     * see whether it loads (mods run tainted -> may error but shouldn't crash). */
    scope.saved = *scope.handlerPtr;   /* record but do NOT modify */
    TaintScopeRingLog("taint_scope NO-CLEAR (test): handler left = %p", scope.saved);
    DebugLog("[mods] taint clear DISABLED (test mode) -- running taint-intact");
    return scope;
#endif
    scope.saved = *scope.handlerPtr;
    *scope.handlerPtr = NULL;
    TaintScopeRingLog("taint_scope enter ptr=%p saved=%p now=%p", scope.handlerPtr, scope.saved, *scope.handlerPtr);
    return scope;
#endif
}

static void LeaveLuaTaintScope(const LuaTaintScope* scope) {
    if (!scope || !scope->handlerPtr) return;
    TaintScopeRingLog("taint_scope leave ptr=%p restore=%p", scope->handlerPtr, scope->saved);
    *scope->handlerPtr = scope->saved;
    TaintScopeRingLog("taint_scope left ptr=%p now=%p", scope->handlerPtr, *scope->handlerPtr);
}

/* ========================================================================
** FindGameWindow Ã¢â‚¬â€ locate WoW's main window
** ======================================================================== */

static BOOL g_findWindowPass2 = FALSE;

static BOOL CALLBACK FindGameWindowCB(HWND hwnd, LPARAM lParam) {
    (void)lParam;
    DWORD pid = 0;
    DWORD tid = pGetWindowThreadProcessId(hwnd, &pid);
    if (pid != GetCurrentProcessId()) return TRUE;

    char className[128] = {0};
    pGetClassNameA(hwnd, className, sizeof(className));

    if (!g_findWindowPass2) {
        if (strcmp(className, "GxWindowClass") == 0 ||
            strcmp(className, "GxWindowClassD3d") == 0 ||
            strcmp(className, "waApplication Window") == 0 ||
            strncmp(className, "GxWindow", 8) == 0) {
            g_gameWindow   = hwnd;
            g_mainThreadId = tid;
            return FALSE;
        }
    } else {
        if (pIsWindowVisible(hwnd) && (pGetWindowLongA(hwnd, GWL_STYLE) & WS_CAPTION)) {
            g_gameWindow   = hwnd;
            g_mainThreadId = tid;
            return FALSE;
        }
    }
    return TRUE;
}

void FindGameWindowWithFallback(void) {
    g_findWindowPass2 = FALSE;
    pEnumWindows(FindGameWindowCB, 0);
    if (g_gameWindow) return;

    DebugLog("[mods] GxWindowClass not found, trying fallback");
    g_findWindowPass2 = TRUE;
    pEnumWindows(FindGameWindowCB, 0);
}

/* ========================================================================
** ReadModFiles / FreeModFiles Ã¢â‚¬â€ load .lua files from C:\projects\
** ======================================================================== */

void FreeModFiles(void) {
    for (int i = 0; i < g_modFileCount; i++) {
        if (g_modFiles[i].buffer) {
            VirtualFree(g_modFiles[i].buffer, 0, MEM_RELEASE);
            g_modFiles[i].buffer = NULL;
        }
    }
    g_modFileCount = 0;
}

int ReadModFiles(void) {
    char logBuf[1024];

    CreateDirectoryA("C:\\projects", NULL);
    FreeModFiles();

    /* Pass 1: Root-level _*.lua entry files */
    WIN32_FIND_DATAA fd;
    HANDLE hFind = FindFirstFileA("C:\\projects\\*.lua", &fd);
    if (hFind == INVALID_HANDLE_VALUE) {
        DebugLog("[mods] no .lua files in C:\\projects\\");
    } else {
        do {
            if (fd.dwFileAttributes & FILE_ATTRIBUTE_DIRECTORY) continue;
            if (fd.cFileName[0] != '_') continue;

            if (g_modFileCount >= MAX_MODS) break;
            if (fd.nFileSizeLow > MAX_MOD_SIZE || fd.nFileSizeHigh > 0) continue;

            char fullPath[MAX_PATH + 16];
            snprintf(fullPath, sizeof(fullPath), "C:\\projects\\%s", fd.cFileName);

            HANDLE hFile = CreateFileA(fullPath, GENERIC_READ,
                FILE_SHARE_READ | FILE_SHARE_WRITE | FILE_SHARE_DELETE,
                NULL, OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL, NULL);
            if (hFile == INVALID_HANDLE_VALUE) continue;

            DWORD fileSize = GetFileSize(hFile, NULL);
            if (fileSize == 0 || fileSize == INVALID_FILE_SIZE) {
                CloseHandle(hFile);
                continue;
            }

            char* buf = (char*)VirtualAlloc(NULL, fileSize + 1,
                                            MEM_COMMIT | MEM_RESERVE, PAGE_READWRITE);
            if (!buf) { CloseHandle(hFile); continue; }

            DWORD bytesRead = 0;
            if (!ReadFile(hFile, buf, fileSize, &bytesRead, NULL) || bytesRead != fileSize) {
                VirtualFree(buf, 0, MEM_RELEASE);
                CloseHandle(hFile);
                continue;
            }
            buf[fileSize] = '\0';
            CloseHandle(hFile);

            ModFile* mf = &g_modFiles[g_modFileCount];
            snprintf(mf->filename, MAX_PATH, "%s", fd.cFileName);
            mf->directory[0] = '\0';
            mf->buffer = buf;
            mf->size   = fileSize;
            g_modFileCount++;
        } while (FindNextFileA(hFind, &fd));
        FindClose(hFind);
    }

    /* Pass 2: Subdirectory _*.lua entry files */
    WIN32_FIND_DATAA fd2;
    HANDLE hFind2 = FindFirstFileA("C:\\projects\\*", &fd2);
    if (hFind2 != INVALID_HANDLE_VALUE) {
        do {
            if (!(fd2.dwFileAttributes & FILE_ATTRIBUTE_DIRECTORY)) continue;
            if (strcmp(fd2.cFileName, ".") == 0 || strcmp(fd2.cFileName, "..") == 0) continue;

            char subSearch[MAX_PATH + 16];
            snprintf(subSearch, sizeof(subSearch), "C:\\projects\\%s\\_*.lua", fd2.cFileName);

            WIN32_FIND_DATAA fd3;
            HANDLE hSub = FindFirstFileA(subSearch, &fd3);
            if (hSub == INVALID_HANDLE_VALUE) continue;

            do {
                if (fd3.dwFileAttributes & FILE_ATTRIBUTE_DIRECTORY) continue;
                if (g_modFileCount >= MAX_MODS) break;
                if (fd3.nFileSizeLow > MAX_MOD_SIZE || fd3.nFileSizeHigh > 0) continue;

                char fullPath[MAX_PATH * 3];
                snprintf(fullPath, sizeof(fullPath), "C:\\projects\\%s\\%s", fd2.cFileName, fd3.cFileName);

                HANDLE hFile = CreateFileA(fullPath, GENERIC_READ,
                    FILE_SHARE_READ | FILE_SHARE_WRITE | FILE_SHARE_DELETE,
                    NULL, OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL, NULL);
                if (hFile == INVALID_HANDLE_VALUE) continue;

                DWORD fileSize = GetFileSize(hFile, NULL);
                if (fileSize == 0 || fileSize == INVALID_FILE_SIZE) {
                    CloseHandle(hFile);
                    continue;
                }

                char* buf = (char*)VirtualAlloc(NULL, fileSize + 1,
                                                MEM_COMMIT | MEM_RESERVE, PAGE_READWRITE);
                if (!buf) { CloseHandle(hFile); continue; }

                DWORD bytesRead = 0;
                if (!ReadFile(hFile, buf, fileSize, &bytesRead, NULL) || bytesRead != fileSize) {
                    VirtualFree(buf, 0, MEM_RELEASE);
                    CloseHandle(hFile);
                    continue;
                }
                buf[fileSize] = '\0';
                CloseHandle(hFile);

                ModFile* mf = &g_modFiles[g_modFileCount];
#pragma GCC diagnostic push
#pragma GCC diagnostic ignored "-Wformat-truncation"
                snprintf(mf->filename, MAX_PATH, "%s/%s", fd2.cFileName, fd3.cFileName);
#pragma GCC diagnostic pop
                snprintf(mf->directory, MAX_PATH, "%s", fd2.cFileName);
                mf->buffer = buf;
                mf->size   = fileSize;
                g_modFileCount++;
            } while (FindNextFileA(hSub, &fd3));
            FindClose(hSub);
        } while (FindNextFileA(hFind2, &fd2));
        FindClose(hFind2);
    }

    snprintf(logBuf, sizeof(logBuf), "[mods] %d file(s) loaded from C:\\projects\\", g_modFileCount);
    DebugLog(logBuf);
    return g_modFileCount;
}

static volatile LONG g_executingMods = FALSE;

#pragma GCC diagnostic push
#pragma GCC diagnostic ignored "-Wformat-truncation"
void ExecuteModsOnMainThread(void) {
    char logBuf[1024];

    if (InterlockedCompareExchange(&g_executingMods, TRUE, FALSE) != FALSE) {
        DebugLog("[mods] skipping re-entrant call");
        return;
    }

    if (!g_modLoaderBase) {
        DebugLog("[mods] ERR: base address not set");
        InterlockedExchange(&g_executingMods, FALSE);
        return;
    }

#if !RVA_SET_IS_VERIFIED
    /* SAFE MODE: RVAs (incl. g_LuaState) are stale for this build. Reading a
     * stale g_LuaState yields a garbage lua_State* and calling into the Lua API
     * with it crashes WoW. Refuse to execute mods until RVAs are re-derived. */
    snprintf(logBuf, sizeof(logBuf),
             "[mods] SAFE MODE: mod execution disabled -- RVA set verified for build %d, running %d. Re-derive RVAs from a dump.",
             (int)RVA_VERIFIED_BUILD, (int)EXPECTED_BUILD);
    DebugLog(logBuf);
    InterlockedExchange(&g_executingMods, FALSE);
    return;
#endif

    /* Resolve WoW trampoline pointers (only loadbuffer + pcall still need RVAs) */
    luaL_loadbuffer_t pLoadBuffer = (luaL_loadbuffer_t)(g_wowBase + RVA_LUAL_LOADBUFFER);
    lua_pcall_t       pPcall      = (lua_pcall_t)      (g_wowBase + RVA_LUA_PCALL);

    /* Validate trampoline addresses are within WoW image bounds */
    if ((uintptr_t)pLoadBuffer < (uintptr_t)g_wowBase ||
        (uintptr_t)pPcall      < (uintptr_t)g_wowBase) {
        DebugLog("[mods] ERR: trampoline addresses out of range");
        InterlockedExchange(&g_executingMods, FALSE);
        return;
    }

    void** ppL = (void**)(g_wowBase + RVA_G_LUASTATE);
    void*  L   = *ppL;

    if (!L || (uintptr_t)L < 0x10000 || ((uintptr_t)L >> 48) > 0x7FFF) {
        snprintf(logBuf, sizeof(logBuf), "[mods] L is NULL or invalid (L=%p from RVA=0x%llX)", 
                 L, (unsigned long long)RVA_G_LUASTATE);
        DebugLog(logBuf);
        InterlockedExchange(&g_executingMods, FALSE);
        return;
    }

    snprintf(logBuf, sizeof(logBuf), "[mods] executing %d mod(s), L=%p", g_modFileCount, L);
    DebugLog(logBuf);

    s_pPcall       = pPcall;
    s_pLoadBuffer  = pLoadBuffer;

    /* Initialize vendored Lua dummynode bridge (WoW's .rdata sentinel).
     * RVA_DUMMYNODE re-derived for Classic 68940 (0x2F19E70 via luaH_new lea) --
     * the stale retail value 0x035E1780 pointed empty dinkr tables at garbage,
     * so WoW's luaH_getnum walked a bad node chain -> -1 deref crash. */
    mk_lua_set_host_dummynode((uintptr_t)(g_wowBase + RVA_DUMMYNODE));

    /* Root fix: clear current taint source while we touch Lua globals and run mods. */
    LuaTaintScope taintScope = EnterLuaTaintScope();
    g_savedTaintHandler = taintScope.saved;

    /* Calibrate direct stack read */
    CalibrateDirectStackRead(L);

    /* Register bridge functions as Lua globals (using vendored wk_lua_) */

    /* File I/O */
    pPushCClosure(L, (void*)dinkr_ReadFile, 0);
    pSetField(L, LUA_GLOBALSINDEX, "dinkr_ReadFile");
    pPushCClosure(L, (void*)dinkr_WriteFile, 0);
    pSetField(L, LUA_GLOBALSINDEX, "dinkr_WriteFile");
    pPushCClosure(L, (void*)dinkr_ListFiles, 0);
    pSetField(L, LUA_GLOBALSINDEX, "dinkr_ListFiles");
    pPushCClosure(L, (void*)dinkr_ListDirectories, 0);
    pSetField(L, LUA_GLOBALSINDEX, "dinkr_ListDirectories");
    pPushCClosure(L, (void*)dinkr_IsWindowForeground, 0);
    pSetField(L, LUA_GLOBALSINDEX, "dinkr_IsWindowForeground");
    pPushCClosure(L, (void*)dinkr_GetKeyState, 0);
    pSetField(L, LUA_GLOBALSINDEX, "dinkr_GetKeyState");

    /* Taint-safe call bridge */
    pPushCClosure(L, (void*)dinkr_Call, 0);
    pSetField(L, LUA_GLOBALSINDEX, "dinkr_Call");

    /* The client's OWN untainted chunk loader, re-exposed.
     *
     * Nothing is synthesised here: loadstring_untainted is a real
     * lua_CFunction already registered in the client's base library, merely not
     * published to the addon environment (plain `loadstring_untainted` reads nil
     * from /run). We push the client's own function pointer under a dinkr_ name,
     * so it behaves exactly as the client's loader does.
     *
     * This is the ROOT fix for ForceTaint_Strong on our closures. The Lua-side
     * loadstring stamps taint at COMPILE time (see RVA_LOADSTRING_UNTAINTED in
     * rva_defs.h for the gate disassembly), so every file awful2 requires is
     * tainted before it ever runs -- and no amount of clearing g_taint around
     * the call can undo a stamp applied at load. */
    pPushCClosure(L, (void*)((uintptr_t)g_modLoaderBase + RVA_LOADSTRING_UNTAINTED), 0);
    pSetField(L, LUA_GLOBALSINDEX, "dinkr_loadstring_untainted");

    /* OM functions */
    pPushCClosure(L, (void*)dinkr_GetObjectCount, 0);
    pSetField(L, LUA_GLOBALSINDEX, "dinkr_GetObjectCount");
    pPushCClosure(L, (void*)dinkr_GetObjectWithIndex, 0);
    pSetField(L, LUA_GLOBALSINDEX, "dinkr_GetObjectWithIndex");
    pPushCClosure(L, (void*)dinkr_ObjectType, 0);
    pSetField(L, LUA_GLOBALSINDEX, "dinkr_ObjectType");
    pPushCClosure(L, (void*)dinkr_ObjectPosition, 0);
    pSetField(L, LUA_GLOBALSINDEX, "dinkr_ObjectPosition");
    pPushCClosure(L, (void*)dinkr_ObjectFacing, 0);
    pSetField(L, LUA_GLOBALSINDEX, "dinkr_ObjectFacing");
    pPushCClosure(L, (void*)dinkr_ObjectRotation, 0);
    pSetField(L, LUA_GLOBALSINDEX, "dinkr_ObjectRotation");
    pPushCClosure(L, (void*)dinkr_ObjectID, 0);
    pSetField(L, LUA_GLOBALSINDEX, "dinkr_ObjectID");
    pPushCClosure(L, (void*)dinkr_ObjectDescriptor, 0);
    pSetField(L, LUA_GLOBALSINDEX, "dinkr_ObjectDescriptor");

    pPushCClosure(L, (void*)dinkr_DumpObject, 0);
    pSetField(L, LUA_GLOBALSINDEX, "dinkr_DumpObject");
    pPushCClosure(L, (void*)dinkr_ObjectName, 0);
    pSetField(L, LUA_GLOBALSINDEX, "dinkr_ObjectName");
    pPushCClosure(L, (void*)dinkr_ObjectCreator, 0);
    pSetField(L, LUA_GLOBALSINDEX, "dinkr_ObjectCreator");
    pPushCClosure(L, (void*)dinkr_ObjectTarget, 0);
    pSetField(L, LUA_GLOBALSINDEX, "dinkr_ObjectTarget");
    pPushCClosure(L, (void*)dinkr_ObjectCastingTarget, 0);
    pSetField(L, LUA_GLOBALSINDEX, "dinkr_ObjectCastingTarget");
    pPushCClosure(L, (void*)dinkr_IsValidObject, 0);
    pSetField(L, LUA_GLOBALSINDEX, "dinkr_IsValidObject");
    pPushCClosure(L, (void*)dinkr_IsPlayerGuid, 0);
    pSetField(L, LUA_GLOBALSINDEX, "dinkr_IsPlayerGuid");
    pPushCClosure(L, (void*)dinkr_IsTargetGuid, 0);
    pSetField(L, LUA_GLOBALSINDEX, "dinkr_IsTargetGuid");
    pPushCClosure(L, (void*)dinkr_IsFocusGuid, 0);
    pSetField(L, LUA_GLOBALSINDEX, "dinkr_IsFocusGuid");
    pPushCClosure(L, (void*)dinkr_ObjectMovementFlag, 0);
    pSetField(L, LUA_GLOBALSINDEX, "dinkr_ObjectMovementFlag");
    pPushCClosure(L, (void*)dinkr_ObjectCombatReach, 0);
    pSetField(L, LUA_GLOBALSINDEX, "dinkr_ObjectCombatReach");
    pPushCClosure(L, (void*)dinkr_ObjectBoundingRadius, 0);
    pSetField(L, LUA_GLOBALSINDEX, "dinkr_ObjectBoundingRadius");
    pPushCClosure(L, (void*)dinkr_ObjectCreatureType, 0);
    pSetField(L, LUA_GLOBALSINDEX, "dinkr_ObjectCreatureType");
    pPushCClosure(L, (void*)dinkr_ObjectATInfo, 0);
    pSetField(L, LUA_GLOBALSINDEX, "dinkr_ObjectATInfo");
    pPushCClosure(L, (void*)dinkr_ObjectSpecializationID, 0);
    pSetField(L, LUA_GLOBALSINDEX, "dinkr_ObjectSpecializationID");
    pPushCClosure(L, (void*)dinkr_GetMapID, 0);
    pSetField(L, LUA_GLOBALSINDEX, "dinkr_GetMapID");
    pPushCClosure(L, (void*)dinkr_LuaSetNPC, 0);
    pSetField(L, LUA_GLOBALSINDEX, "dinkr_SetNPC");
    pPushCClosure(L, (void*)dinkr_ObjectHeight, 0);
    pSetField(L, LUA_GLOBALSINDEX, "dinkr_ObjectHeight");
    pPushCClosure(L, (void*)dinkr_ObjectLootable, 0);
    pSetField(L, LUA_GLOBALSINDEX, "dinkr_ObjectLootable");
    pPushCClosure(L, (void*)dinkr_ObjectInteract, 0);
    pSetField(L, LUA_GLOBALSINDEX, "dinkr_ObjectInteract");
    pPushCClosure(L, (void*)dinkr_NativeCast_lua, 0);
    pSetField(L, LUA_GLOBALSINDEX, "dinkr_NativeCast");

    /* Aura memory read */
    pPushCClosure(L, (void*)dinkr_UnitAuras, 0);
    pSetField(L, LUA_GLOBALSINDEX, "dinkr_UnitAuras");

    /* Camera + WorldToScreen */
    pPushCClosure(L, (void*)dinkr_CameraPosition_lua, 0);
    pSetField(L, LUA_GLOBALSINDEX, "dinkr_CameraPosition");
    pPushCClosure(L, (void*)dinkr_WorldToScreen_lua, 0);
    pSetField(L, LUA_GLOBALSINDEX, "dinkr_WorldToScreen");
    pPushCClosure(L, (void*)dinkr_ScreenToWorld_lua, 0);
    pSetField(L, LUA_GLOBALSINDEX, "dinkr_ScreenToWorld");
    pPushCClosure(L, (void*)dinkr_CameraDiag_lua, 0);
    pSetField(L, LUA_GLOBALSINDEX, "dinkr_CameraDiag");

    /* Navmesh pathfinding (Detour over C:\projects\navmesh tiles) */
    pPushCClosure(L, (void*)dinkr_GeneratePath_lua, 0);
    pSetField(L, LUA_GLOBALSINDEX, "dinkr_GeneratePath");
    pPushCClosure(L, (void*)dinkr_NavNearest_lua, 0);
    pSetField(L, LUA_GLOBALSINDEX, "dinkr_NavNearest");
    pPushCClosure(L, (void*)dinkr_NavStatus_lua, 0);
    pSetField(L, LUA_GLOBALSINDEX, "dinkr_NavStatus");
    pPushCClosure(L, (void*)dinkr_NavPolys_lua, 0);
    pSetField(L, LUA_GLOBALSINDEX, "dinkr_NavPolys");

    /* LiveMesh: runtime navmesh generation. Policy lives in the Lua project
     * !projects/LiveMesh; these are just the handles it drives. */
    pPushCClosure(L, (void*)dinkr_LiveMeshBegin_lua, 0);
    pSetField(L, LUA_GLOBALSINDEX, "dinkr_LiveMeshBegin");
    pPushCClosure(L, (void*)dinkr_LiveMeshStep_lua, 0);
    pSetField(L, LUA_GLOBALSINDEX, "dinkr_LiveMeshStep");
    pPushCClosure(L, (void*)dinkr_LiveMeshStatus_lua, 0);
    pSetField(L, LUA_GLOBALSINDEX, "dinkr_LiveMeshStatus");
    pPushCClosure(L, (void*)dinkr_LiveMeshTileAt_lua, 0);
    pSetField(L, LUA_GLOBALSINDEX, "dinkr_LiveMeshTileAt");
    pPushCClosure(L, (void*)dinkr_LiveMeshHave_lua, 0);
    pSetField(L, LUA_GLOBALSINDEX, "dinkr_LiveMeshHave");
    pPushCClosure(L, (void*)dinkr_LiveMeshCancel_lua, 0);
    pSetField(L, LUA_GLOBALSINDEX, "dinkr_LiveMeshCancel");
    pPushCClosure(L, (void*)dinkr_LiveMeshWalls_lua, 0);
    pSetField(L, LUA_GLOBALSINDEX, "dinkr_LiveMeshWalls");
    pPushCClosure(L, (void*)dinkr_LiveMeshAgent_lua, 0);
    pSetField(L, LUA_GLOBALSINDEX, "dinkr_LiveMeshAgent");
    pPushCClosure(L, (void*)dinkr_LiveMeshClimb_lua, 0);
    pSetField(L, LUA_GLOBALSINDEX, "dinkr_LiveMeshClimb");
    pPushCClosure(L, (void*)dinkr_LiveMeshDiagonals_lua, 0);
    pSetField(L, LUA_GLOBALSINDEX, "dinkr_LiveMeshDiagonals");
    pPushCClosure(L, (void*)dinkr_LiveMeshProbeSkip_lua, 0);
    pSetField(L, LUA_GLOBALSINDEX, "dinkr_LiveMeshProbeSkip");
    pPushCClosure(L, (void*)dinkr_LiveMeshTileInfo_lua, 0);
    pSetField(L, LUA_GLOBALSINDEX, "dinkr_LiveMeshTileInfo");
    pPushCClosure(L, (void*)dinkr_NavLastRequest_lua, 0);
    pSetField(L, LUA_GLOBALSINDEX, "dinkr_NavLastRequest");
    pPushCClosure(L, (void*)dinkr_NavWallDist_lua, 0);
    pSetField(L, LUA_GLOBALSINDEX, "dinkr_NavWallDist");
    pPushCClosure(L, (void*)dinkr_PatchDay_lua, 0);
    pSetField(L, LUA_GLOBALSINDEX, "dinkr_PatchDay");

    /* Movement / interaction */
    pPushCClosure(L, (void*)dinkr_FaceDirection_lua, 0);
    pSetField(L, LUA_GLOBALSINDEX, "dinkr_FaceDirection");
    pPushCClosure(L, (void*)dinkr_SendMovementHeartbeat_lua, 0);
    pSetField(L, LUA_GLOBALSINDEX, "dinkr_SendMovementHeartbeat");
    pPushCClosure(L, (void*)dinkr_ClickPosition_lua, 0);
    pSetField(L, LUA_GLOBALSINDEX, "dinkr_ClickPosition");
    pPushCClosure(L, (void*)dinkr_SpellIsTargeting_lua, 0);
    pSetField(L, LUA_GLOBALSINDEX, "dinkr_SpellIsTargeting");
    pPushCClosure(L, (void*)dinkr_SpellCancelTargeting_lua, 0);
    pSetField(L, LUA_GLOBALSINDEX, "dinkr_SpellCancelTargeting");
    pPushCClosure(L, (void*)dinkr_SpellTargetingReady_lua, 0);
    pSetField(L, LUA_GLOBALSINDEX, "dinkr_SpellTargetingReady");


    /* TraceLine (World_Intersect) */
    pPushCClosure(L, (void*)dinkr_TraceLine_lua, 0);
    pSetField(L, LUA_GLOBALSINDEX, "dinkr_TraceLine");

    /* Missiles (in-flight spell missile tracking) */
    pPushCClosure(L, (void*)dinkr_Missiles, 0);
    pSetField(L, LUA_GLOBALSINDEX, "dinkr_Missiles");

    /* CombatLog */
    pPushCClosure(L, (void*)dinkr_CombatLogGetCurrentEventInfo_lua, 0);
    pSetField(L, LUA_GLOBALSINDEX, "dinkr_CombatLogGetCurrentEventInfo");
    pPushCClosure(L, (void*)dinkr_dbg_lua, 0);
    pSetField(L, LUA_GLOBALSINDEX, "dinkr_dbg");

    DebugLog("[mods] bridge registered");
    { FILE* f = fopen("C:\\projects\\dinkr_modload.txt", "w"); if (f) { fputs("=== mod load start (crash-proof log) ===\n", f); fclose(f); } }
    DirectModLog("bridge registered; taint_mode=%s", DINKR_CLEAR_TAINT ? "CLEAR" : "INTACT");

    /* Diagnostic: prove pLoadBuffer + pPcall can run trivial Lua on this build. */
    DebugLog("[mods] setup: compiling trivial script...");
    DirectModLog("setup: loadbuffer ENTER");
    {
        /* Secret-value fix: awful reads unit.health/power via the native
         * UnitHealth/UnitPower C-API, which returns a SECRET TValue while the
         * caller is tainted (awful's per-frame ticker runs outside dinkr's
         * load-time taint scope). Downstream arithmetic on that secret spams
         * "arithmetic on a secret value" and eventually a secret number gets
         * indexed as a table -> luaH_get crash (RVA 0x33E26xx).
         *
         * Fix: replace those globals BEFORE the framework captures them
         * (traits.lua/health.lua do `local UnitHealth = UnitHealth` at load,
         * which runs after this chunk). Each wrapper routes the real call
         * through dinkr_Call, which zeroes g_taint_handler_ptr for the duration
         * so the C-API returns a REAL plain number -> no secret ever enters the
         * rotation's data flow. Direct global assignment (NOT _G -- forbidden in
         * WoW's tainted env). Idempotent via dinkr_secure_installed sentinel. */
        const char* setupScript =
            "if not awful then awful = {} end\n"
            "if not fm then fm = {} end\n"
            "if not wow then wow = {} end\n"
            "if not dinkr_secure_installed and dinkr_Call then\n"
            "  dinkr_secure_installed = true\n"
            "  local wc = dinkr_Call\n"
            "  local uh, uhm, up, upm = UnitHealth, UnitHealthMax, UnitPower, UnitPowerMax\n"
            "  if uh  then UnitHealth    = function(...) return wc(uh,  ...) end end\n"
            "  if uhm then UnitHealthMax = function(...) return wc(uhm, ...) end end\n"
            "  if up  then UnitPower     = function(...) return wc(up,  ...) end end\n"
            "  if upm then UnitPowerMax  = function(...) return wc(upm, ...) end end\n"
            "  local ua, uha, uih = UnitGetTotalAbsorbs, UnitGetTotalHealAbsorbs, UnitGetIncomingHeals\n"
            "  if ua  then UnitGetTotalAbsorbs     = function(...) return wc(ua,  ...) end end\n"
            "  if uha then UnitGetTotalHealAbsorbs = function(...) return wc(uha, ...) end end\n"
            "  if uih then UnitGetIncomingHeals    = function(...) return wc(uih, ...) end end\n"
            "end\n";
        int setupResult = pLoadBuffer(L, setupScript, strlen(setupScript), "@setup");
        DirectModLog("setup: loadbuffer DONE rc=%d", setupResult);
        snprintf(logBuf, sizeof(logBuf), "[mods] setup: loadbuffer rc=%d", setupResult);
        DebugLog(logBuf);
        if (setupResult == 0) {
            DirectModLog("setup: pcall ENTER");
            DebugLog("[mods] setup: pcall ENTER");
            setupResult = pPcall(L, 0, 0, 0);
            DirectModLog("setup: pcall DONE rc=%d", setupResult);
            snprintf(logBuf, sizeof(logBuf), "[mods] setup: pcall DONE rc=%d", setupResult);
            DebugLog(logBuf);
        }
        if (setupResult != 0) {
            size_t errLen = 0;
            const char* errMsg = pTolstring(L, -1, &errLen);
            snprintf(logBuf, sizeof(logBuf), "[mods] setup error: %.*s",
                     (int)(errLen < 200 ? errLen : 200), errMsg ? errMsg : "(null)");
            DebugLog(logBuf);
            pSettop(L, -2);
        }
    }

    /* Execute each .lua mod file (the real framework entry, e.g. awful2/_local.lua) */
    int successCount = 0;
    for (int i = 0; i < g_modFileCount; i++) {
        ModFile* mf = &g_modFiles[i];

        char chunkName[MAX_PATH + 16];
        snprintf(chunkName, sizeof(chunkName), "@%s", mf->filename);

        snprintf(logBuf, sizeof(logBuf), "[mods] loading %s (%d bytes, first=0x%02X%02X%02X)",
                 mf->filename, mf->size,
                 (unsigned char)mf->buffer[0], (unsigned char)mf->buffer[1],
                 (unsigned char)mf->buffer[2]);
        DebugLog(logBuf);
        DirectModLog("mod[%d] loadbuffer ENTER '%s' (%d bytes)", i, mf->filename, mf->size);

        /* Compile the ACTUAL file contents */
        int loadResult = pLoadBuffer(L, mf->buffer, mf->size, chunkName);
        DirectModLog("mod[%d] loadbuffer DONE rc=%d", i, loadResult);
        TaintScopeRingLog("taint_scope load '%s' rc=%d taint=%p", mf->filename, loadResult, taintScope.handlerPtr ? *taintScope.handlerPtr : NULL);
        if (loadResult != 0) {
            size_t errLen = 0;
            const char* errMsg = pTolstring(L, -1, &errLen);
            snprintf(logBuf, sizeof(logBuf), "[mods] COMPILE ERROR %s: %.*s",
                     mf->filename, (int)(errLen < 400 ? errLen : 400),
                     errMsg ? errMsg : "(null)");
            DebugLog(logBuf);
            pSettop(L, -2);
            continue;
        }

        snprintf(logBuf, sizeof(logBuf), "[mods] pcall ENTER %s", mf->filename);
        DebugLog(logBuf);
        DirectModLog("mod[%d] pcall ENTER '%s'", i, mf->filename);
        int pcallResult = pPcall(L, 0, 0, 0);
        DirectModLog("mod[%d] pcall DONE rc=%d", i, pcallResult);
        snprintf(logBuf, sizeof(logBuf), "[mods] pcall DONE %s rc=%d", mf->filename, pcallResult);
        DebugLog(logBuf);
        TaintScopeRingLog("taint_scope pcall '%s' rc=%d taint=%p", mf->filename, pcallResult, taintScope.handlerPtr ? *taintScope.handlerPtr : NULL);
        if (pcallResult != 0) {
            size_t errLen = 0;
            const char* errMsg = pTolstring(L, -1, &errLen);
            snprintf(logBuf, sizeof(logBuf), "[mods] RUNTIME ERROR %s: %.*s",
                     mf->filename, (int)(errLen < 400 ? errLen : 400),
                     errMsg ? errMsg : "(null)");
            DebugLog(logBuf);
            DirectModLog("mod[%d] RUNTIME ERROR: %.*s", i,
                         (int)(errLen < 800 ? errLen : 800), errMsg ? errMsg : "(null)");
            pSettop(L, -2);
            continue;
        }

        snprintf(logBuf, sizeof(logBuf), "[mods] ok: %s", mf->filename);
        DebugLog(logBuf);
        DirectModLog("mod[%d] ok: %s", i, mf->filename);
        successCount++;
    }

    snprintf(logBuf, sizeof(logBuf), "[mods] %d/%d executed", successCount, g_modFileCount);
    DebugLog(logBuf);
    DirectModLog("=== done: %d/%d executed ===", successCount, g_modFileCount);

    /* Always restore WoW's taint source after our secure scope exits. */
    LeaveLuaTaintScope(&taintScope);

    g_lastLuaState = L;

    /* Report to IPC */
    DinkrIPC* ipc = GetIPC();
    if (ipc) {
        ipc->dll_lua_state = (uint64_t)(uintptr_t)L;
        ipc->mod_count = (uint32_t)successCount;
    }

    InterlockedExchange(&g_executingMods, FALSE);
}
#pragma GCC diagnostic pop


/* ========================================================================
** ModLoaderHookProc Ã¢â‚¬â€ WH_GETMESSAGE hook (runs on WoW's main thread)
** ======================================================================== */

static LRESULT CALLBACK ModLoaderHookProc(int nCode, WPARAM wParam, LPARAM lParam) {
    if (nCode >= 0 && g_modLoaderBase) {
        MSG* pMsg = (MSG*)lParam;
        if (pMsg && pMsg->message == WM_LOAD_MODS) {
            if (g_modLoaderBase) {
                void** ppL = (void**)(g_modLoaderBase + RVA_G_LUASTATE);
                if (*ppL == NULL) {
                    /* Lua not ready yet, skip */
                } else if (*ppL == g_lastLuaState) {
                    /* Already loaded for this L, skip */
                } else {
                    ReadModFiles();
                    ExecuteModsOnMainThread();
                    InterlockedExchange(&g_modsLoaded, TRUE);
                }
            }
            pMsg->message = WM_NULL;
        }

        /* Safety net: clear stale NPC GUID injection if push leaked */
        if (s_lastNPCPushTick != 0 && (GetTickCount() - s_lastNPCPushTick) > 200) {
            if (g_modLoaderBase) {
                uintptr_t pNpcGuid = (uintptr_t)(g_modLoaderBase + RVA_NpcTargetGUID);
                if (om_ptr_ok(pNpcGuid, 16)) {
                    uint64_t lo = 0, hi = 0;
                    memcpy(&lo, (void*)pNpcGuid, 8);
                    memcpy(&hi, (void*)(pNpcGuid + 8), 8);
                    if (lo != 0 || hi != 0) {
                        memset((void*)pNpcGuid, 0, 16);
                    }
                }
            }
            s_lastNPCPushTick = 0;
        }

        /* Precall callstatus monitor DISABLED (68887): the precall-callstatus
         * patches are intentionally not applied under the taint-scope design,
         * and RVA_PRECALL_* are stale skip_scan values from 68453. Monitoring
         * them only spammed [patch-mon]/precall_site logs and risked
         * PatchBytes-ing a wrong address if a stale byte matched 0x00/0x01/0x02.
         * The two enabled patches (retaddr_check, validate_cfunc_ptr) are one-shot
         * RET-stomps that WoW never reverts, so no runtime monitor is needed. */

    }
    return pCallNextHookEx(g_messageHook, nCode, wParam, lParam);
}

/* ========================================================================
** SetupModLoader Ã¢â‚¬â€ find window, install hook, trigger initial load
** ======================================================================== */

void SetupModLoader(LPBYTE moduleBase) {
    char logBuf[1024];

    DebugLog("[mods] initializing");
    g_modLoaderBase = moduleBase;

    CreateDirectoryA("C:\\projects", NULL);

    int modCount = ReadModFiles();
    if (modCount == 0) {
        DebugLog("[mods] no mods found (hook active for reload)");
    }

    FindGameWindowWithFallback();
    if (!g_gameWindow || !g_mainThreadId) {
        DebugLog("[mods] game window not found, retrying...");
        for (int retry = 0; retry < 30 && !g_gameWindow; retry++) {
            Sleep(2000);
            FindGameWindowWithFallback();
        }
        if (!g_gameWindow) {
            DebugLog("[mods] FATAL: no game window found");
            return;
        }
    }

    /* Write window info to IPC */
    DinkrIPC* ipc = GetIPC();
    if (ipc) {
        ipc->game_window_handle = (uint64_t)(uintptr_t)g_gameWindow;
        ipc->main_thread_id     = g_mainThreadId;
    }

    /* Install message hook on main thread */
    g_messageHook = pSetWindowsHookExA(WH_GETMESSAGE, ModLoaderHookProc, NULL, g_mainThreadId);
    if (!g_messageHook) {
        snprintf(logBuf, sizeof(logBuf), "[mods] ERR: SetWindowsHookEx err=%lu", GetLastError());
        DebugLog(logBuf);
        return;
    }
    DebugLog("[mods] hook installed");

    /* Gate initial load on in-world state */
    // Disabled for build 68453 — g_GameStateFlags RVA is stale
    //{
    //    uint16_t flags = *(uint16_t*)(moduleBase + RVA_g_GameStateFlags);
    //    if (flags & 0x200) {
            if (!pPostMessageA(g_gameWindow, WM_LOAD_MODS, 0, 0)) {
                snprintf(logBuf, sizeof(logBuf), "[mods] ERR: PostMessage err=%lu", GetLastError());
                DebugLog(logBuf);
            }
    //    } else {
    //        DebugLog("[mods] not in-world, deferring load");
    //    }
    //}

    DebugLog("[mods] ready");
}
