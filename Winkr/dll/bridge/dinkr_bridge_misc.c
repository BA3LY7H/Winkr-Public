/* dinkr_bridge_misc.c -- File I/O, input, Call, CLEU, debug */

#include "dinkr_bridge.h"



/* Script_CombatLogGetCurrentEventInfo — native handler (lua CFunction signature).
 * WARNING: The secure wrapper crashes when called from external DLL (obfuscated
 * post-processing dereferences NULL secure-context globals). Use PushEventArgs. */
typedef int (__fastcall *ScriptCLEU_GetCurrentEventInfo_t)(void* L);

/* CombatLog_PushEventArgs — pushes all combat log event fields onto Lua stack.
 * arg1 (RCX) = combat log entry pointer, arg2 (RDX) = Lua state.
 * Returns number of pushed values (typically 11-24 depending on event type). */
typedef int (__fastcall *CombatLog_PushEventArgs_t)(void* entry, void* L);

/* ========================================================================
** File I/O bridge functions
** ======================================================================== */

int __fastcall dinkr_ReadFile(void* L) {
    size_t pathLen = 0;
    const char* path = wk_arg_string(L, 1, &pathLen);
    if (!path || pathLen == 0) { s_pPushnil(L); return 1; }

    HANDLE hFile = CreateFileA(path, GENERIC_READ,
        FILE_SHARE_READ | FILE_SHARE_WRITE | FILE_SHARE_DELETE,
        NULL, OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL, NULL);
    if (hFile == INVALID_HANDLE_VALUE) { s_pPushnil(L); return 1; }

    DWORD fileSize = GetFileSize(hFile, NULL);
    if (fileSize == 0 || fileSize == INVALID_FILE_SIZE || fileSize > 16 * 1024 * 1024) {
        CloseHandle(hFile);
        s_pPushnil(L);
        return 1;
    }

    char* buf = (char*)VirtualAlloc(NULL, fileSize, MEM_COMMIT | MEM_RESERVE, PAGE_READWRITE);
    if (!buf) { CloseHandle(hFile); s_pPushnil(L); return 1; }

    DWORD bytesRead = 0;
    BOOL readOk = ReadFile(hFile, buf, fileSize, &bytesRead, NULL);
    CloseHandle(hFile);

    if (!readOk || bytesRead == 0) {
        VirtualFree(buf, 0, MEM_RELEASE);
        s_pPushnil(L);
        return 1;
    }

    s_pPushlstring(L, buf, bytesRead);
    VirtualFree(buf, 0, MEM_RELEASE);
    return 1;
}

int __fastcall dinkr_WriteFile(void* L) {
    size_t pathLen = 0, contentLen = 0;
    const char* path = wk_arg_string(L, 1, &pathLen);
    const char* content = wk_arg_string(L, 2, &contentLen);
    if (!path || pathLen == 0 || !content) {
        s_pPushboolean(L, 0);
        return 1;
    }

    size_t appendLen = 0;
    const char* appendStr = wk_arg_string(L, 3, &appendLen);
    BOOL appendMode = (appendStr && appendLen > 0 && appendStr[0] != '0' && appendStr[0] != 'f');

    DWORD disposition = appendMode ? OPEN_ALWAYS : CREATE_ALWAYS;
    HANDLE hFile = CreateFileA(path, GENERIC_WRITE, 0, NULL, disposition, FILE_ATTRIBUTE_NORMAL, NULL);
    if (hFile == INVALID_HANDLE_VALUE) {
        s_pPushboolean(L, 0);
        return 1;
    }

    if (appendMode) SetFilePointer(hFile, 0, NULL, FILE_END);

    DWORD bytesWritten = 0;
    BOOL ok = WriteFile(hFile, content, (DWORD)contentLen, &bytesWritten, NULL);
    CloseHandle(hFile);
    s_pPushboolean(L, ok && bytesWritten == (DWORD)contentLen);
    return 1;
}

int __fastcall dinkr_ListFiles(void* L) {
    size_t pathLen = 0;
    const char* path = wk_arg_string(L, 1, &pathLen);
    if (!path || pathLen == 0) { s_pCreatetable(L, 0, 0); return 1; }

    char searchPath[MAX_PATH];
    if (pathLen > 0 && (path[pathLen - 1] == '/' || path[pathLen - 1] == '\\'))
        snprintf(searchPath, sizeof(searchPath), "%s*", path);
    else
        snprintf(searchPath, sizeof(searchPath), "%s\\*", path);

    s_pCreatetable(L, 0, 0);

    WIN32_FIND_DATAA fd;
    HANDLE hFind = FindFirstFileA(searchPath, &fd);
    if (hFind == INVALID_HANDLE_VALUE) return 1;

    int idx = 1;
    do {
        if (fd.dwFileAttributes & FILE_ATTRIBUTE_DIRECTORY) continue;
        if (strcmp(fd.cFileName, ".") == 0 || strcmp(fd.cFileName, "..") == 0) continue;
        s_pPushstring(L, fd.cFileName);
        s_pRawseti(L, -2, idx++);
    } while (FindNextFileA(hFind, &fd));
    FindClose(hFind);
    return 1;
}

int __fastcall dinkr_ListDirectories(void* L) {
    size_t pathLen = 0;
    const char* path = wk_arg_string(L, 1, &pathLen);
    if (!path || pathLen == 0) { s_pCreatetable(L, 0, 0); return 1; }

    char searchPath[MAX_PATH];
    if (pathLen > 0 && (path[pathLen - 1] == '/' || path[pathLen - 1] == '\\'))
        snprintf(searchPath, sizeof(searchPath), "%s*", path);
    else
        snprintf(searchPath, sizeof(searchPath), "%s\\*", path);

    s_pCreatetable(L, 0, 0);

    WIN32_FIND_DATAA fd;
    HANDLE hFind = FindFirstFileA(searchPath, &fd);
    if (hFind == INVALID_HANDLE_VALUE) return 1;

    int idx = 1;
    do {
        if (!(fd.dwFileAttributes & FILE_ATTRIBUTE_DIRECTORY)) continue;
        if (strcmp(fd.cFileName, ".") == 0 || strcmp(fd.cFileName, "..") == 0) continue;
        s_pPushstring(L, fd.cFileName);
        s_pRawseti(L, -2, idx++);
    } while (FindNextFileA(hFind, &fd));
    FindClose(hFind);
    return 1;
}

int __fastcall dinkr_IsWindowForeground(void* L) {
    HWND fg = pGetForegroundWindow();
    s_pPushboolean(L, (fg == g_gameWindow) ? 1 : 0);
    return 1;
}

int __fastcall dinkr_GetKeyState(void* L) {
    int vk = (int)dinkr_read_stack_number(L, 1);
    SHORT state = GetAsyncKeyState(vk);
    s_pPushboolean(L, (state & 0x8000) ? 1 : 0);
    return 1;
}

/* ========================================================================
** dinkr_Call — taint-safe Lua function call bridge
**
** Lua usage:  dinkr_Call(fn, arg1, arg2, ...)
**
** Saves g_taint_handler_ptr and force_taint_flag, clears them so the
** called function runs in a "secure" context, then restores after the
** call completes.  Uses lua_pcall internally so taint is ALWAYS restored
** even if the called function errors.
**
** Nesting is supported up to depth 8 via a static save stack.
** ======================================================================== */

int __fastcall dinkr_Call(void* L) {
    int top = dinkr_gettop_inline(L);
    if (top < 1) return 0;  /* no function provided */
    int nargs = top - 1;

    if (!s_pPcall || !g_modLoaderBase) {
        return 0;
    }

    /* Save and temporarily zero the taint handler so our pcall runs
     * "secure".  MUST restore afterward — leaving it NULL makes WoW's
     * own Lua C functions (e.g. HandleTargetSelection) take untested
     * Splash-obfuscated code paths that crash with NULL L->top. */
    int status;
#if RVA_G_TAINT_IS_VERIFIED
    volatile uintptr_t* pTaint = (volatile uintptr_t*)
        ((uintptr_t)g_modLoaderBase + RVA_G_TAINT_HANDLER_PTR);
    uintptr_t savedTaint = *pTaint;
    *pTaint = 0;

    /* DIAGNOSTIC (first 8 calls only) -- is this address actually the taint
     * handler on this build?
     *
     * Every call through here comes from awful.call, i.e. from mod code, which
     * the client force-taints ("ForceTaint_Strong"). So savedTaint MUST read
     * non-zero here. If it reads zero on every call, RVA_G_TAINT_HANDLER_PTR is
     * not the taint handler on 69547 and this whole clear-and-restore is a
     * no-op writing into an unrelated global -- which would explain protected
     * calls still being blocked despite the bypass. */
    /* pcall: fn at index 1, nargs args after it.  LUA_MULTRET = -1. */
    status = s_pPcall(L, nargs, -1, 0);

    /* Restore taint handler before returning to WoW */
    *pTaint = savedTaint;

    /* DIAGNOSTIC -- did the call actually FAIL?
     *
     * savedTaint tells us the bypass saw the taint and cleared the right word;
     * it does not tell us whether the protected call then went through. pcall
     * status does: a blocked protected function raises, so status != 0 is a
     * REAL block, and status == 0 with taint present means the bypass worked.
     *
     * That is the measurement that separates the HealBot-on and HealBot-off
     * cases, which look identical from Lua -- issecure() reads false in BOTH,
     * so taint is not what differs between working and broken. */
    /* DIAGNOSTIC -- WHICH taint sources reach our casts?
     *
     * pcall status is useless here: a blocked protected function does NOT raise,
     * it fires ADDON_ACTION_FORBIDDEN and no-ops, so status is 0 whether the
     * cast happened or not (40/40 ok while casts visibly failed).
     *
     * What DID differ is the taint VALUE. g_taint holds a const char* naming the
     * source. Ours is the module-resident "*** ForceTaint_Strong ***" string;
     * addon taint sources are heap-allocated, so an address outside the module
     * image is somebody else's taint riding into our call path. Log each
     * distinct source once, classified, plus a periodic census. */
    {
        #define TSRC_MAX 16
        static uintptr_t s_src[TSRC_MAX];
        static int       s_cnt[TSRC_MAX];
        static int       s_srcN = 0, s_tCalls = 0;
        if (savedTaint != 0) {
            uintptr_t mod = (uintptr_t)g_modLoaderBase;
            int inModule = (savedTaint > mod && savedTaint < mod + 0x08000000);
            int idx = -1, i;
            s_tCalls++;
            for (i = 0; i < s_srcN; i++) { if (s_src[i] == savedTaint) { idx = i; break; } }
            if (idx < 0 && s_srcN < TSRC_MAX) {
                char pb[176];
                idx = s_srcN++;
                s_src[idx] = savedTaint; s_cnt[idx] = 0;
                snprintf(pb, sizeof(pb), "[taint] NEW source #%d = %016llX  %s  (at tainted call %d)",
                         idx, (unsigned long long)savedTaint,
                         inModule ? "MODULE (ForceTaint_Strong = ours)" : "HEAP (another addon's taint)",
                         s_tCalls);
                DebugLog(pb);
            }
            if (idx >= 0) s_cnt[idx]++;
            if ((s_tCalls % 400) == 0) {
                char pb[240]; int n = 0;
                n += snprintf(pb + n, sizeof(pb) - n, "[taint] census after %d tainted calls:", s_tCalls);
                for (i = 0; i < s_srcN && n < (int)sizeof(pb) - 32; i++)
                    n += snprintf(pb + n, sizeof(pb) - n, " #%d=%d", i, s_cnt[i]);
                DebugLog(pb);
            }
        }
    }
#else
    /* g_taint RVA not derived for this build (Classic): writing through the
     * stale addr would corrupt a real Classic global. Run pass-through — the
     * wrapped fn still executes; a secret return just yields non-fatal
     * "arithmetic on secret value" errors, never a crash. */
    status = s_pPcall(L, nargs, -1, 0);
#endif

    if (status != 0) {
        /* pcall caught an error — error message is on stack top.
         * Without lua_error we cannot re-raise directly from C.
         * Return the error message as the sole return value so the
         * Lua-side wrapper (awful.call) can detect and re-raise it. */
        return 1;
    }

    /* Success: return all results that pcall left on the stack. */
    return dinkr_gettop_inline(L);
}

/* dinkr_CombatLogGetCurrentEventInfo — direct bridge to CombatLog_PushEventArgs.
 *
 * Old approach called Script_CombatLogSecure_GetCurrentEventInfo (RVA 0xCC1FF0)
 * with taint zeroed. This CRASHED because the secure wrapper's obfuscated
 * epilogue code dereferences secure-context globals (e.g. global 'L' at
 * RVA 0x3FFBB08) that are NULL when called from an external DLL.
 *
 * CLEU bridge: calls the game's actual field pusher (RVA_CombatLog_PushEventArgs) directly.
 * This function takes (cleu_data_provider, L) and pushes all combat log fields.
 * The data provider is at RVA_g_CLEU_CurrentEventEntry. */
int __fastcall dinkr_CombatLogGetCurrentEventInfo_lua(void* L) {
    if (!g_modLoaderBase) return 0;

    /* Read the CLEU data provider pointer */
    uintptr_t pAddr = (uintptr_t)g_modLoaderBase + RVA_g_CLEU_CurrentEventEntry;
    if (!om_ptr_ok(pAddr, 8)) return 0;
    void** pProvider = (void**)pAddr;
    void* provider = *pProvider;
    if (!provider) return 0;

    /* Call the field pusher — pushes all CLEU event fields onto Lua stack */
    CombatLog_PushEventArgs_t pushFields =
        (CombatLog_PushEventArgs_t)((uintptr_t)g_modLoaderBase + RVA_CombatLog_PushEventArgs);

    return pushFields(provider, L);
}

/* dinkr_dbg() — minimal runtime diagnostic.
 * Returns camera position (chain source) + CLEU state as a string. */
int __fastcall dinkr_dbg_lua(void* L) {
    if (!g_modLoaderBase) { s_pPushnil(L); return 1; }

    char buf[768];
    int pos = 0;

    /* Camera source: WorldFrame pointer chain */
    uintptr_t cam = resolve_camera_object();
    if (cam) {
        float cx = *(float*)(cam + CCAM_OFF_EYE);
        float cy = *(float*)(cam + CCAM_OFF_EYE + 4);
        float cz = *(float*)(cam + CCAM_OFF_EYE + 8);
        float tx = *(float*)(cam + CCAM_OFF_LOOKAT);
        float ty = *(float*)(cam + CCAM_OFF_LOOKAT + 4);
        float tz = *(float*)(cam + CCAM_OFF_LOOKAT + 8);
        pos += snprintf(buf + pos, sizeof(buf) - pos,
            "CAM (chain)  pos=%.1f,%.1f,%.1f lookAt=%.1f,%.1f,%.1f\n",
            cx, cy, cz, tx, ty, tz);
    } else {
        pos += snprintf(buf + pos, sizeof(buf) - pos, "CAM (chain): unavailable\n");
    }

    /* CLEU/taint handler */
    uintptr_t taintAddr = (uintptr_t)g_modLoaderBase + RVA_G_TAINT_HANDLER_PTR;
    if (om_ptr_ok(taintAddr, 8)) {
        void** pTaint = (void**)taintAddr;
        pos += snprintf(buf + pos, sizeof(buf) - pos, "CLEU/taint: %p\n", *pTaint);
    } else {
        pos += snprintf(buf + pos, sizeof(buf) - pos, "CLEU/taint: not readable\n");
    }

    s_pPushlstring(L, buf, pos);
    return 1;
}
