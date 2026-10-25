/* gui_worker.cpp — Per-session background worker thread */

#include "gui_worker.h"
#include "gui_external.h"
#include "gui_ipc_host.h"
#include "ipc_protocol.h"

#include <windows.h>
#include <cstdio>

DWORD WINAPI SessionWorkerThread(LPVOID param)
{
    WowSession* s = (WowSession*)param;
    if (!s) return 1;

    /* Attach to the process */
    if (!Ext_AttachSession(s)) {
        IpcHost_LogSession(s, "[gui]", "FATAL: could not attach to process");
        s->alive = false;
        return 1;
    }

    /* Create IPC mapping for this session */
    if (!IpcHost_CreateForSession(s)) {
        IpcHost_Log("[gui]", "FATAL: IPC creation failed for session");
        s->alive = false;
        return 1;
    }

    /* Check if DLL is already present (GUI restart case) */
    {
        char evtName[80];
        DinkrEvtName((unsigned long)s->pid, evtName, sizeof(evtName));
        HANDLE h = OpenEventA(SYNCHRONIZE, FALSE, evtName);
        if (h) {
            CloseHandle(h);
            IpcHost_LogSession(s, "[gui]", "reconnect: DLL already active");
            s->buildOK          = true;
            s->startupWaitDone  = true;
            s->threadsSuspended = true;
            s->inGameDetected   = true;
            s->patchesDone      = true;
            s->alreadyInjected  = true;
            InterlockedExchange(&s->dllInjected, 1);
        }
    }

    while (s->running && g_appRunning) {
        DWORD now = GetTickCount();

        /* Check if target process is still alive */
        if (WaitForSingleObject(s->hProcess, 0) == WAIT_OBJECT_0) {
            IpcHost_LogSession(s, "[gui]", "target process exited");
            s->alive = false;
            break;
        }

        /* Step 1: Verify build */
        if (!s->buildOK) {
            s->buildOK = Ext_VerifyBuild(s);
            if (!s->buildOK) {
                IpcHost_LogSession(s, "[gui]", "build verification failed");
                Sleep(5000);
                continue;
            }
        }

        /* Classic client: DUMP-ONLY. Keep Warden suspended (stealth) + idle so the Dump
         * button works; never run the retail inject/patch/OM path. */
        if (s->isClassic) {
            if (!InterlockedOr(&s->dumpActive, 0)) {
                if (!s->threadsSuspended) {
                    Ext_SuspendWardenThreads(s);
                    Ext_SuspendWardenThreads(s);
                    s->threadsSuspended = true;
                    Ext_DiagThreadsByModule(s);
                }
                if (now - s->lastWardenSweep >= 5000) {
                    Ext_SuspendWardenThreads(s);
                    s->lastWardenSweep = now;
                }
            }
            Sleep(150);
            continue;
        }

        /* Step 2: 10-second startup wait */
        if (!s->startupWaitDone) {
            IpcHost_LogSession(s, "[gui]", "waiting 10s for game initialization...");
            for (int i = 0; i < 10 && s->running && g_appRunning; i++) {
                Sleep(1000);
                if (WaitForSingleObject(s->hProcess, 0) == WAIT_OBJECT_0) break;
            }
            if (WaitForSingleObject(s->hProcess, 0) == WAIT_OBJECT_0) {
                s->alive = false;
                break;
            }
            s->startupWaitDone = true;
            IpcHost_LogSession(s, "[gui]", "startup wait complete");
        }

        /* Step 3: Suspend Warden loader threads (skip during dump) */
        if (!s->threadsSuspended && !InterlockedOr(&s->dumpActive, 0)) {
            int total = Ext_SuspendWardenThreads(s);
            Sleep(500);
            total += Ext_SuspendWardenThreads(s);
            for (int pass = 0; pass < 3; pass++) {
                Sleep(2000);
                total += Ext_SuspendWardenThreads(s);
            }
            s->threadsSuspended = true;
            char buf[128];
            snprintf(buf, sizeof(buf), "thread suspension complete: %d total", total);
            IpcHost_LogSession(s, "[gui]", buf);
            /* One-shot audit: prove nothing Warden-shaped starts outside Wow_loader.dll. */
            Ext_DiagThreadsByModule(s);
        }

        /* Step 4: Wait for player to be in-game + 10s settle */
        if (!s->inGameDetected) {
            IpcHost_LogSession(s, "[gui]", "waiting for player to enter game...");
            int waitTicks = 0;
            while (s->running && g_appRunning) {
                if (WaitForSingleObject(s->hProcess, 0) == WAIT_OBJECT_0) {
                    s->alive = false;
                    break;
                }
                if (Ext_IsPlayerInGame(s)) {
                    IpcHost_LogSession(s, "[gui]", "player in game, waiting 10s for loading screen...");
                    for (int i = 0; i < 10 && s->running && g_appRunning; i++)
                        Sleep(1000);
                    if (WaitForSingleObject(s->hProcess, 0) == WAIT_OBJECT_0) {
                        s->alive = false;
                        break;
                    }
                    IpcHost_LogSession(s, "[gui]", "post-load settle complete");
                    s->inGameDetected = true;
                    break;
                }
                if (++waitTicks % 30 == 0) {
                    uint32_t rawFlags = Ext_GetRawGameStateFlags(s);
                    char buf[96];
                    snprintf(buf, sizeof(buf), "waiting... flags=0x%08X", rawFlags);
                    IpcHost_LogSession(s, "[gui]", buf);
                }
                Sleep(1000);
            }
            if (!s->alive || !s->inGameDetected) continue;
        }

        /* Step 5: Patches (DLL handles) */
        if (!s->patchesDone) {
            Ext_ApplyPatches(s);
            s->patchesDone = true;
            IpcHost_LogSession(s, "[gui]", "patch step done (DLL handles all patches)");
        }

        /* Step 6: OM enumeration (every 200ms) */
        if (s->pIpc && (now - s->lastOM >= 200)) {
            Ext_EnumerateOM(s);
            if (!s->pIpc->gui_om_ready)
                InterlockedExchange(&s->pIpc->gui_om_ready, 1);
            s->lastOM = now;
        }

        /* Step 7: Player enter/leave detection for Warden re-suspend */
        if (s->pIpc && s->dllInjected) {
            bool playerInGame = Ext_IsPlayerInGame(s);

            if (!s->playerTrackingInit) {
                s->wasPlayerInGame = playerInGame;
                s->playerTrackingInit = true;
            }

            if (s->wasPlayerInGame && !playerInGame)
                IpcHost_LogSession(s, "[gui]", "player left world");

            if (!s->wasPlayerInGame && playerInGame && !InterlockedOr(&s->dumpActive, 0)) {
                IpcHost_LogSession(s, "[gui]", "player re-entered world, suspending Warden...");
                Sleep(2000);
                if (WaitForSingleObject(s->hProcess, 0) == WAIT_OBJECT_0) {
                    s->alive = false;
                    break;
                }
                Ext_SuspendWardenThreads(s);
                IpcHost_LogSession(s, "[gui]", "Warden suspended (DLL handles re-patching)");
            }

            s->wasPlayerInGame = playerInGame;
        }

        /* Continuous Warden sweep every ~5s (skip during dump) */
        if (now - s->lastWardenSweep >= 5000 && !InterlockedOr(&s->dumpActive, 0)) {
            Ext_SuspendWardenThreads(s);
            s->lastWardenSweep = now;
        }

        Sleep(100);
    }

    return 0;
}
