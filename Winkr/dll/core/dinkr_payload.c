/*
** dinkr_payload.c -- Core DLL entry point for DINKR payload
**
** After refactoring, this file contains only:
**   - Global state definitions
**   - DebugLog()
**   - DumpWorkerThread (background worker)
**   - DumpWorkerCallback + DllMain
**
** All other logic has been extracted to focused modules:
**   dinkr_stealth.c  -- PEB manipulation, user32 resolution
**   dinkr_security.c -- in-process patching
**   dinkr_bridge.c   -- Lua bridge functions
**   dinkr_om_enum.c  -- DLL-side OM enumeration
**   dinkr_mods.c     -- mod loading, hook management
*/

#include "dinkr_internal.h"
#include "dinkr_stealth.h"
#include "dinkr_security.h"
#include "dinkr_bridge.h"
#include "dinkr_om_enum.h"
#include "dinkr_mods.h"


/* ========================================================================
** Module state
** ======================================================================== */

HMODULE    g_hSelf       = NULL;   /* our DLL module handle */
HANDLE     g_hSingletonEvt = NULL; /* named event for injection detection */
LPBYTE     g_modLoaderBase  = NULL;
LPBYTE     g_wowBase        = NULL;
size_t     g_wowModuleSize  = 0;
volatile BOOL g_shuttingDown = FALSE; /* worker exit signal */

/* ========================================================================
** DebugLog -- writes to IPC ring buffer
** ======================================================================== */

/* Mirror every line to disk as well as the IPC ring.
 *
 * The ring only ever reached the GUI window, so the [dll] stream -- scorecard,
 * selfheal, patch results, mod loader errors -- existed nowhere a tool could
 * read it. Diagnosing anything meant a human copying text out of a window,
 * which is slow and loses the lines that scroll past.
 *
 * Opened append/close per line rather than held open: this is called from the
 * worker AND from the hooked main thread, the volume is a few hundred lines a
 * session, and a handle held across a reflectively-mapped DLL's lifetime is one
 * more thing to leak on unload. Failure is silent by design -- logging must
 * never be able to take the client down.
 *
 * Path is fixed rather than derived from the module: the DLL is manually mapped
 * so GetModuleFileName is not meaningful for it, and C:\projects already exists as
 * the loader's own directory. */
void DebugLog(const char* msg) {
    IpcLog("[dll]", msg);

    FILE* f = fopen("C:\\projects\\dinkr_dll_debug.log", "a");
    if (!f) return;
    SYSTEMTIME t; GetLocalTime(&t);
    fprintf(f, "[%02u:%02u:%02u.%03u] %s\n", t.wHour, t.wMinute, t.wSecond, t.wMilliseconds,
            msg ? msg : "(null)");
    fclose(f);
}


/* ========================================================================
** DumpWorkerThread Ã¢â‚¬â€ simplified background worker
**
** 1. Find WoW module base (PEB ImageBaseAddress)
** 2. Open IPC shared memory (retry loop Ã¢â‚¬â€ GUI creates it)
** 3. Wait for OM to be ready (gui_om_ready)
** 4. Set up mod loader (hooks main thread, executes .lua mods)
** 5. Main loop: handle GUI commands (reload, refresh)
** ======================================================================== */

DWORD WINAPI DumpWorkerThread(LPVOID lpParam) {
    (void)lpParam;
    char logBuf[256];

    /* Singleton event was already created in DllMain (g_hSingletonEvt).
     * If it's NULL, another instance owns the event — bail. */
    if (!g_hSingletonEvt) {
        DebugLog("[worker] duplicate DLL instance — exiting");
        return 0;
    }

    DebugLog("[worker] DumpWorkerThread started");

    /* NOTE: DLL is reflectively loaded — not in PEB module lists.
     * apphelp.dll shims GetProcAddress to return trampoline addresses.
     * Fix: resolve user32 functions via ManualGetProcAddress (reads EAT
     * directly from PE headers) and call through function pointers,
     * bypassing apphelp's shim trampolines entirely. */
    if (!ResolveUser32Functions()) {
        DebugLog("[worker] FATAL: could not resolve user32 functions");
        return 1;
    }
    CreateDirectoryA("C:\\mods", NULL);

    /* Attempt IPC connection early (non-fatal if GUI hasn't started yet) */
    if (InitIPC()) {
        IpcSetStatus(DLL_STATUS_ATTACHED);
    }

    
    DebugLog("[init] dinkr_payload loaded (v4 -- bridge-only DLL)");

    /* --- Step 1: Find WoW module base --- */
    PPEB peb = GET_PEB();
    if (!peb || !peb->ImageBaseAddress) {
        DebugLog("[worker] FATAL: no PEB / ImageBaseAddress");
        return 1;
    }
    LPBYTE base = (LPBYTE)peb->ImageBaseAddress;

    snprintf(logBuf, sizeof(logBuf), "[worker] module base: %p", (void*)base);
    DebugLog(logBuf);

    g_wowBase = base;

    /* Compute module size from PE header for fast page validation */
    {
        PIMAGE_DOS_HEADER dos = (PIMAGE_DOS_HEADER)base;
        if (dos->e_magic == IMAGE_DOS_SIGNATURE && dos->e_lfanew > 0 && dos->e_lfanew < 0x1000) {
            PIMAGE_NT_HEADERS nt = (PIMAGE_NT_HEADERS)(base + dos->e_lfanew);
            if (nt->Signature == IMAGE_NT_SIGNATURE) {
                g_wowModuleSize = nt->OptionalHeader.SizeOfImage;
            }
        }
    }

    /* --- Step 1b: Resolve RVAs / pattern scan ---
     * Run immediately after base+size are known, before any RVA is used.
     * Populates g_dinkr_addrs[] for DinkrGetAddr() callers. */
    DebugLog("[worker] resolving addresses (sig scan / RVA fallback)...");
    DinkrResolveAllAddrs(base, g_wowModuleSize);

    /* --- Step 2: Connect IPC (retry loop) --- */
    if (!GetIPC()) {
        DebugLog("[worker] IPC not ready, retrying...");
        for (int retry = 0; retry < 120; retry++) {
            Sleep(1000);
            if (InitIPC()) {
                DebugLog("[worker] IPC connected");
                break;
            }
        }
        if (!GetIPC()) {
            DebugLog("[worker] WARN: IPC connection failed, continuing without GUI");
        }
    }

    IpcSetStatus(DLL_STATUS_ATTACHED);

    /* Write base address + build to IPC for GUI */
    DinkrIPC* ipc = GetIPC();
    if (ipc) {
        ipc->wow_base_address = (uint64_t)(uintptr_t)base;
        ipc->build_number = EXPECTED_BUILD;
    }

    /* --- Step 3: Apply all security patches (DLL-owned) --- */
    DebugLog("[worker] applying security patches...");
    {
        /* On 68887 exactly TWO global patches are required: the Eidolon caller/pointer
         * validators (retaddr_check, validate_cfunc_ptr). The old forbidden-table/secret
         * gate groups are disabled by design (taint-scope + UnitHealth wrappers cover
         * secrets), so ApplySecurityPatches returning 2 is HEALTHY -- not a stale-RVA sign. */
        const int DINKR_REQUIRED_PATCHES = 2;
        int applied = ApplySecurityPatches(base);
        snprintf(logBuf, sizeof(logBuf),
                 "[worker] security patches: %d/%d required applied (other groups disabled by design)",
                 applied, DINKR_REQUIRED_PATCHES);
        DebugLog(logBuf);
        if (applied < DINKR_REQUIRED_PATCHES) {
            /* ABORT rather than warn-and-continue. These two are Eidolon
             * anti-tamper guards: with them unpatched, the FIRST Lua C-API call
             * this DLL makes (the setup script's luaL_loadbuffer) hits a
             * deliberate NULL-deref and takes the client down. Warning and
             * carrying on is exactly how a stale RVA turned into a crash on
             * patch day 69109. Stop here instead — WoW is left completely
             * untouched and the log says what to re-derive. */
            DebugLog("[worker] ABORT: a REQUIRED Eidolon validator did not apply -- retaddr_check/"
                     "validate_cfunc_ptr is STALE for this build.");
            DebugLog("[worker] Lua C-API calls WOULD CRASH the client, so mod execution is skipped."
                     " Re-derive both (Documents/PatchDay.md, tools/derive_validators.py) and rebuild.");
            return 0;
        }
    }

    /* --- Step 4: Wait for OM to be ready --- */
    DebugLog("[worker] waiting for GUI OM...");
    {
        int omReady = 0;
        for (int wait = 0; wait < 600; wait++) {
            ipc = GetIPC();
            if (ipc && ipc->gui_om_ready) {
                DebugLog("[worker] GUI OM ready");
                omReady = 1;
                break;
            }
            Sleep(500);
        }
        if (!omReady) {
            ipc = GetIPC();
            snprintf(logBuf, sizeof(logBuf),
                     "[worker] WARN: gui_om_ready timeout (ipc=%p, flag=%d)",
                     (void*)ipc, ipc ? (int)ipc->gui_om_ready : -1);
            DebugLog(logBuf);
        }
    }

    /* --- Step 5: Set up mod loader --- */
    DebugLog("[worker] setting up mod loader...");
    IpcSetStatus(DLL_STATUS_MOD_LOADING);
    SetupModLoader(base);
    IpcSetStatus(DLL_STATUS_READY);

    /* --- Step 6: Main loop --- */
    /* self-healing: g_GameStateFlags via the scanner's RIP-relative recipe (auto-
     * updates on a build bump), fallback to the hardcoded RVA. */
    uintptr_t gsfAddr = DinkrGetAddr(SIGID_g_GameStateFlags);
    volatile uint16_t* pGameStateFlags  = (volatile uint16_t*)(gsfAddr ? gsfAddr : (uintptr_t)(base + RVA_g_GameStateFlags));
    /* g_LuaState via the self-healing RIP recipe (fallback raw RVA). CreateCount is
     * ALWAYS g_LuaState + 0x118 -- DERIVE it rather than using the raw
     * RVA_G_LUASTATE_CREATE_COUNT, which is client-specific and pointed PAST the Classic
     * image (0x63F1BB0 > 0x62F1000) -> read-past-module crash on first /reload check. */
    uintptr_t luaStateVA = DinkrGetAddr(SIGID_G_LUASTATE);
    if (!luaStateVA) luaStateVA = (uintptr_t)(base + RVA_G_LUASTATE);
    void**             ppLuaState       = (void**)          (luaStateVA);
    volatile DWORD*    pLuaCreateCount  = (volatile DWORD*) (luaStateVA + 0x118);
    void**             ppTaintHandler   = (void**)            (base + RVA_G_TAINT_HANDLER_PTR);

    BOOL  wasInWorld            = FALSE;
    BOOL  modsCurrentlyLoaded   = FALSE;
    DWORD lastLuaCreateCount    = 0;
    BOOL  createCountSeeded     = FALSE;
    DWORD lastTaintWaitLog      = 0;
    DWORD modsLoadWaitStartTick = 0;  /* When we first saw L!=NULL but taint==NULL after VM change. */

    /* Request 1ms timer resolution so Sleep(5) actually sleeps ~5ms
     * instead of the default ~15.6ms Windows quantum. */
    timeBeginPeriod(1);

    /* OM runs every 10ms (100Hz — covers up to 100fps);
     * slow-path checks every 500ms (50 fast ticks) */
    int fastTick = 0;
    BOOL allPatchesVerified = FALSE;

    while (!g_shuttingDown) {

        /* in-world gate: g_GameStateFlags re-derived for 68887 (0x4962998), bit
         * 0x200 = in world. (The stale 68453 RVA read garbage and wedged this loop
         * -> that was the real cause of the empty Object Manager.) */
        uint16_t flags = *pGameStateFlags;
        BOOL inWorld = (flags & 0x200) != 0;

        /* During world transitions, sleep longer to avoid reading freed memory */
        if (!inWorld) {
            Sleep(100);
            fastTick = 0;
            if (wasInWorld) {
                DebugLog("[worker] left world (flags change), mods unloaded");
                modsCurrentlyLoaded = FALSE;
                g_lastLuaState = NULL;
            }
            wasInWorld = FALSE;
            continue;
        }

        /* Just entered world — wait 2s for game to stabilize entities */
        if (!wasInWorld && inWorld) {
            wasInWorld = TRUE;
            DebugLog("[worker] world entered, settling...");
            Sleep(2000);
            continue;
        }

        /* --- Fast path: OM enumeration ~100Hz -> shared memory -> GUI Object
         * Manager. RE-ENABLED for 68887: the OM globals (g_pObjectMgr, entity
         * buckets, offsets) are verified correct live -- the framework's /wl
         * targeting reads the same OM via bridges. DLL_EnumerateOM is fully
         * om_ptr_ok-guarded at every deref, so stale offsets yield 0 objects,
         * never a crash. --- */
        if (g_modLoaderBase && modsCurrentlyLoaded) {
            DLL_EnumerateOM(base);
        }

        /* --- Slow path: everything else every 500ms (50 fast ticks) --- */
        if (++fastTick >= 50) {
            fastTick = 0;

            ipc = GetIPC();

            if (ipc) {
                ipc->dll_lua_state = (uint64_t)(uintptr_t)(*ppLuaState);
                ipc->dll_lua_create_count = *pLuaCreateCount;
            }

            /* /reload detection: inWorld stays TRUE during /reload, but the
             * Lua VM is destroyed and recreated (create_count increments).
             * Seed the baseline on first observation so we don't false-flush
             * on the initial load (where lastLuaCreateCount starts at 0). */
            DWORD curCreateCount = *pLuaCreateCount;
            if (!createCountSeeded) {
                lastLuaCreateCount = curCreateCount;
                createCountSeeded = TRUE;
            } else if (modsCurrentlyLoaded && curCreateCount != lastLuaCreateCount) {
                snprintf(logBuf, sizeof(logBuf),
                         "[worker] Lua VM changed (count %lu -> %lu) — /reload detected, flushing mods",
                         (unsigned long)lastLuaCreateCount, (unsigned long)curCreateCount);
                DebugLog(logBuf);
                modsCurrentlyLoaded = FALSE;
                g_lastLuaState = NULL;
                lastLuaCreateCount = curCreateCount;
                modsLoadWaitStartTick = 0;  /* reset timeout tracker */
            }

            /* Transition: not-loaded + in-world = time to load mods */
            if (inWorld && !modsCurrentlyLoaded) {
                void* currentL = *ppLuaState;
                void* taintHandler = *ppTaintHandler;

                /* Start watchdog on first observation of new Lua VM. */
                if (currentL != NULL && modsLoadWaitStartTick == 0) {
                    modsLoadWaitStartTick = GetTickCount();
                }

                /* 5s fallback: if taint handler stays NULL after /reload, proceed
                 * anyway. When handler is NULL, EnterLuaTaintScope saves NULL /
                 * LeaveLuaTaintScope restores NULL — a harmless no-op as long as
                 * WoW itself repopulates the handler later via its own registration
                 * path. Otherwise we'd hang forever and mods never reload. */
                BOOL taintTimedOut = (currentL != NULL && taintHandler == NULL &&
                                      modsLoadWaitStartTick != 0 &&
                                      (GetTickCount() - modsLoadWaitStartTick) >= 5000);

                if (currentL != NULL && g_gameWindow && g_messageHook &&
                    (taintHandler != NULL || taintTimedOut)) {
                    snprintf(logBuf, sizeof(logBuf),
                             "[worker] in-world detected (flags=0x%04X, L=%p, taint=%p%s), re-applying security patches...",
                             (unsigned)flags, currentL, taintHandler,
                             taintTimedOut ? " TIMED_OUT" : "");
                    DebugLog(logBuf);

                    if (!allPatchesVerified) {
                        int applied = ApplySecurityPatches(base);
                        allPatchesVerified = (applied >= 2);  /* 2 required validators (was stale ==13) */
                    }

                    Sleep(1000);
                    if (pPostMessageA(g_gameWindow, WM_LOAD_MODS, 0, 0)) {
                        modsCurrentlyLoaded = TRUE;
                        lastLuaCreateCount = curCreateCount;
                        modsLoadWaitStartTick = 0;
                        if (ipc) ipc->reload_count++;
                    } else {
                        DebugLog("[worker] WARN: PostMessage WM_LOAD_MODS failed");
                    }
                } else if (currentL != NULL && taintHandler == NULL) {
                    /* L is up but FrameXML not finished — rate-limit log to 10s. */
                    DWORD now = GetTickCount();
                    if (now - lastTaintWaitLog >= 10000) {
                        lastTaintWaitLog = now;
                        DWORD waited = modsLoadWaitStartTick ? (now - modsLoadWaitStartTick) : 0;
                        snprintf(logBuf, sizeof(logBuf),
                                 "[worker] waiting for taint handler (FrameXML still loading, %lus)...",
                                 (unsigned long)(waited / 1000));
                        DebugLog(logBuf);
                    }
                }
            }

            wasInWorld = inWorld;

            /* Post WM_NULL to keep message hook alive for patch monitoring */
            if (g_gameWindow) {
                pPostMessageA(g_gameWindow, WM_NULL, 0, 0);
            }

            /* GUI reload command */
            if (IpcCheckReloadCmd()) {
                DebugLog("[worker] reload command from GUI");
                modsCurrentlyLoaded = FALSE;
                g_lastLuaState = NULL;
            }

            if (IpcCheckRefreshCmd()) {
                DebugLog("[worker] refresh command from GUI");
            }
        }

        Sleep(10);
    }

    timeEndPeriod(1);

    /* Singleton event cleaned up by DllMain(DETACH) */
    return 0;
}

/* ========================================================================
** DllMain -- entry point
** ======================================================================== */

void CALLBACK DumpWorkerCallback(PTP_CALLBACK_INSTANCE Instance, PVOID Context)
{
    (void)Instance;
    (void)Context;
    DumpWorkerThread(NULL);
}

/* ========================================================================
** Custom PE entry point -- guards against double CRT initialization
** ========================================================================
** When the injector hijacks a second thread (because the first one didn't
** respond within the timeout), that second thread also calls our entry
** point. Calling _DllMainCRTStartup twice triggers R6031 ("Attempt to
** initialize the CRT more than once").
**
** This wrapper is set as the PE entry point via `-Wl,-e,DinkrDllEntry`.
** On the FIRST call, it forwards to _DllMainCRTStartup (which runs CRT
** init + calls our DllMain).  On any subsequent call it simply returns
** TRUE without re-entering the CRT.
**
** The guard uses __atomic builtins (compiled to LOCK CMPXCHG inline with
** zero external deps) so it is safe to call before CRT init.
** ======================================================================== */

extern BOOL WINAPI DllMainCRTStartup(HINSTANCE hInst, DWORD reason, LPVOID reserved);

BOOL WINAPI DinkrDllEntry(HINSTANCE hInst, DWORD reason, LPVOID reserved) {
    /* .bss-resident zero-initialized by loader (no CRT needed). */
    static volatile LONG s_crtInitDone = 0;

    if (reason == DLL_PROCESS_ATTACH) {
        LONG prev = 0;
        if (!__atomic_compare_exchange_n(&s_crtInitDone, &prev, 1, 0,
                                          __ATOMIC_SEQ_CST, __ATOMIC_SEQ_CST)) {
            /* CRT was already initialized by a prior injector call on
             * another thread. Skipping CRT re-init avoids R6031. */
            return TRUE;
        }
    } else if (reason == DLL_PROCESS_DETACH) {
        /* Only run DETACH if we actually ran ATTACH. */
        if (s_crtInitDone == 0) return TRUE;
    }

    return DllMainCRTStartup(hInst, reason, reserved);
}

BOOL APIENTRY DllMain(HMODULE hModule, DWORD dwReason, LPVOID lpReserved) {

    if (dwReason == DLL_PROCESS_ATTACH) {
        DisableThreadLibraryCalls(hModule);
        g_hSelf = hModule;

        /* Create singleton event NOW (inside DllMain) so the injector
         * sees it immediately, instead of after threadpool worker starts.
         * This eliminates the race where the injector retries another
         * thread before the worker has created the event. */
        {
            char evtName[80];
            DinkrEvtName((unsigned long)GetCurrentProcessId(), evtName, sizeof(evtName));
            g_hSingletonEvt = CreateEventA(NULL, TRUE, FALSE, evtName);
            if (GetLastError() == ERROR_ALREADY_EXISTS) {
                /* Another instance already running — bail out */
                if (g_hSingletonEvt) CloseHandle(g_hSingletonEvt);
                g_hSingletonEvt = NULL;
                return TRUE;
            }
        }

        DebugLog("[init] DllMain entered \xe2\x80\x94 CRT init OK");

        /* MINIMAL DllMain: store handle + submit threadpool work.
         * Using TrySubmitThreadpoolCallback instead of CreateThread to avoid
         * loader-lock deadlock (Warden threads may hold LdrpLoaderLock). */

        /* Start worker via threadpool (avoids loader-lock deadlock) */
        if (!TrySubmitThreadpoolCallback(DumpWorkerCallback, NULL, NULL)) {
            DebugLog("[init] FATAL: threadpool submit failed, worker NOT started");
        }

        return TRUE;
    }

    if (dwReason == DLL_PROCESS_DETACH) {
        DebugLog("[shutdown] detaching");

        /* Signal worker to exit; only wait on explicit FreeLibrary (lpReserved==NULL).
         * During process termination (lpReserved!=NULL), threads are already dead. */
        InterlockedExchange((volatile LONG*)&g_shuttingDown, TRUE);
        if (lpReserved == NULL) {
            /* Give worker thread time to notice g_shuttingDown and exit */
            Sleep(200);
        }

        /* Unhook mod loader */
        if (g_messageHook) {
            if (pUnhookWindowsHookEx) pUnhookWindowsHookEx(g_messageHook);
            g_messageHook = NULL;
        }

        /* Free mod file buffers */
        FreeModFiles();

        /* Close singleton event */
        if (g_hSingletonEvt) { CloseHandle(g_hSingletonEvt); g_hSingletonEvt = NULL; }

        /* Close IPC (also closes persistent log file handle) */
        CloseIPC();
    }

    return TRUE;
}
