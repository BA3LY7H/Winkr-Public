/*
 * gui_warden.cpp — Warden thread suspension for the DINKR GUI
 *
 * Per-session: each WowSession owns its own suspended handles/TIDs.
 */

#include "gui_external.h"

#include <windows.h>
#include <psapi.h>
#include <tlhelp32.h>
#include <cstdio>
#include <cstring>

/* ======================================================================
 * Warden thread suspension — cross-process (per-session)
 * ====================================================================== */
int Ext_SuspendWardenThreads(WowSession* s)
{
    if (!s || !s->hProcess || !s->pid) return 0;

    /* Find Wow_loader.dll in target process */
    HMODULE hMods[512];
    DWORD cbNeeded = 0;
    if (!EnumProcessModulesEx(s->hProcess, hMods, sizeof(hMods), &cbNeeded, LIST_MODULES_ALL))
        return 0;

    int nMods = (int)(cbNeeded / sizeof(HMODULE));
    HMODULE hLoader = NULL;

    for (int i = 0; i < nMods; i++) {
        char modName[MAX_PATH] = {};
        if (GetModuleBaseNameA(s->hProcess, hMods[i], modName, sizeof(modName))) {
            if (_stricmp(modName, "Wow_loader.dll") == 0 ||
                _stricmp(modName, "WowT_loader.dll") == 0 ||
                _stricmp(modName, "WowB_loader.dll") == 0 ||
                _stricmp(modName, "WowClassic_loader.dll") == 0 ||   /* Classic Warden lives here */
                _stricmp(modName, "WowClassicB_loader.dll") == 0 ||
                _stricmp(modName, "WowClassicT_loader.dll") == 0) {
                hLoader = hMods[i];
                break;
            }
        }
    }

    if (!hLoader) return 0;

    MODULEINFO loaderInfo = {};
    if (!GetModuleInformation(s->hProcess, hLoader, &loaderInfo, sizeof(loaderInfo)))
        return 0;

    uintptr_t loaderStart = (uintptr_t)loaderInfo.lpBaseOfDll;
    uintptr_t loaderEnd   = loaderStart + loaderInfo.SizeOfImage;

    /* Enumerate all threads in the target process */
    HANDLE hSnap = CreateToolhelp32Snapshot(TH32CS_SNAPTHREAD, 0);
    if (hSnap == INVALID_HANDLE_VALUE) return 0;

    THREADENTRY32 te = {};
    te.dwSize = sizeof(te);
    int suspended = 0;

    if (Thread32First(hSnap, &te)) {
        do {
            if (te.th32OwnerProcessID != s->pid) continue;

            NT_CLIENT_ID cid = {};
            cid.UniqueProcess = (PVOID)(ULONG_PTR)s->pid;
            cid.UniqueThread  = (PVOID)(ULONG_PTR)te.th32ThreadID;

            NT_OBJECT_ATTRIBUTES oa = {};
            oa.Length = sizeof(oa);

            HANDLE hThread = NULL;
            NTSTATUS_T st = pNtOpenThread(&hThread,
                THREAD_QUERY_INFORMATION | THREAD_SUSPEND_RESUME,
                &oa, &cid);
            if (!NT_SUCCESS_CHECK(st) || !hThread) continue;

            PVOID startAddr = nullptr;
            ULONG retLen = 0;
            st = pNtQueryInformationThread(hThread, 9,
                                           &startAddr, sizeof(startAddr), &retLen);
            if (!NT_SUCCESS_CHECK(st) || !startAddr) {
                CloseHandle(hThread);
                continue;
            }

            uintptr_t addr = (uintptr_t)startAddr;
            if (addr >= loaderStart && addr < loaderEnd) {
                /* Skip if already suspended */
                bool alreadySuspended = false;
                for (int si = 0; si < s->suspendedCount; si++) {
                    if (s->suspendedTIDs[si] == te.th32ThreadID) { alreadySuspended = true; break; }
                }
                if (alreadySuspended) { CloseHandle(hThread); continue; }

                ULONG prevCount = 0;
                if (NT_SUCCESS_CHECK(pNtSuspendThread(hThread, &prevCount))) {
                    if (s->suspendedCount < MAX_SUSPENDED_HANDLES) {
                        s->suspendedHandles[s->suspendedCount] = hThread;
                        s->suspendedTIDs[s->suspendedCount] = te.th32ThreadID;
                        s->suspendedCount++;
                        hThread = NULL;
                    }
                    suspended++;
                }
            }

            if (hThread) CloseHandle(hThread);
        } while (Thread32Next(hSnap, &te));
    }

    CloseHandle(hSnap);

    if (suspended > 0) {
        char logBuf[128];
        snprintf(logBuf, sizeof(logBuf), "suspended %d Warden loader thread(s) (total: %d)",
                 suspended, s->suspendedCount);
        IpcHost_LogSession(s, "[gui]", logBuf);
    }

    return suspended;
}

/* ======================================================================
 * Diagnostic: enumerate EVERY thread by its start-module.
 *
 * Ext_SuspendWardenThreads only suspends threads whose start address is in
 * Wow_loader.dll. This proves whether anything Warden-shaped starts ELSEWHERE
 * (a spoofed/private start = possible hidden scan thread we'd be blind to).
 * Logs a per-module breakdown + every private-start thread's address.
 * NOTE: dinkr's OWN reflectively-mapped worker starts in PRIVATE memory (it's not
 * a listed module), so expect ~1-2 <private> threads that are ours, not Warden.
 * ====================================================================== */
void Ext_DiagThreadsByModule(WowSession* s)
{
    if (!s || !s->hProcess || !s->pid) return;

    struct ModRange { uintptr_t base, end; char name[48]; int count; };
    static ModRange mods[1024];
    int mc = 0;

    HMODULE hMods[1024]; DWORD cb = 0;
    if (EnumProcessModulesEx(s->hProcess, hMods, sizeof(hMods), &cb, LIST_MODULES_ALL)) {
        int n = (int)(cb / sizeof(HMODULE));
        for (int i = 0; i < n && mc < 1024; i++) {
            MODULEINFO mi = {}; char nm[48] = {};
            if (GetModuleInformation(s->hProcess, hMods[i], &mi, sizeof(mi)) &&
                GetModuleBaseNameA(s->hProcess, hMods[i], nm, sizeof(nm))) {
                mods[mc].base = (uintptr_t)mi.lpBaseOfDll;
                mods[mc].end  = mods[mc].base + mi.SizeOfImage;
                strncpy(mods[mc].name, nm, sizeof(mods[mc].name) - 1);
                mods[mc].name[sizeof(mods[mc].name) - 1] = 0;
                mods[mc].count = 0; mc++;
            }
        }
    }

    HANDLE hSnap = CreateToolhelp32Snapshot(TH32CS_SNAPTHREAD, 0);
    if (hSnap == INVALID_HANDLE_VALUE) return;
    THREADENTRY32 te = {}; te.dwSize = sizeof(te);
    int total = 0, priv = 0;
    char privList[1024]; int pp = 0; privList[0] = 0;

    if (Thread32First(hSnap, &te)) {
        do {
            if (te.th32OwnerProcessID != s->pid) continue;
            NT_CLIENT_ID cid = {}; cid.UniqueProcess = (PVOID)(ULONG_PTR)s->pid; cid.UniqueThread = (PVOID)(ULONG_PTR)te.th32ThreadID;
            NT_OBJECT_ATTRIBUTES oa = {}; oa.Length = sizeof(oa);
            HANDLE hT = NULL;
            if (!NT_SUCCESS_CHECK(pNtOpenThread(&hT, THREAD_QUERY_INFORMATION, &oa, &cid)) || !hT) continue;
            PVOID sa = nullptr; ULONG rl = 0;
            NTSTATUS_T st = pNtQueryInformationThread(hT, 9, &sa, sizeof(sa), &rl);
            CloseHandle(hT);
            if (!NT_SUCCESS_CHECK(st) || !sa) continue;
            total++;
            uintptr_t a = (uintptr_t)sa;
            int hit = -1;
            for (int m = 0; m < mc; m++) if (a >= mods[m].base && a < mods[m].end) { hit = m; break; }
            if (hit >= 0) mods[hit].count++;
            else {
                priv++;
                if (pp < 900) pp += snprintf(privList + pp, sizeof(privList) - pp,
                                             "TID=%lu@0x%llX ", (unsigned long)te.th32ThreadID, (unsigned long long)a);
            }
        } while (Thread32Next(hSnap, &te));
    }
    CloseHandle(hSnap);

    char b[256];
    snprintf(b, sizeof(b), "=== thread start-module audit: %d thread(s) total ===", total);
    IpcHost_LogSession(s, "[gui]", b);
    int suspicious = 0;
    for (int m = 0; m < mc; m++) {
        if (mods[m].count <= 0) continue;
        int isLoader = (_strnicmp(mods[m].name, "Wow", 3) == 0 && strstr(mods[m].name, "loader") != NULL);
        /* the game exe itself: Wow.exe / WowClassic.exe / WowT.exe / WowB.exe ... */
        int isWow    = (_strnicmp(mods[m].name, "Wow", 3) == 0 && strstr(mods[m].name, ".exe") != NULL &&
                        strstr(mods[m].name, "loader") == NULL);
        int isSys    = (strstr(mods[m].name, ".dll") &&
                        (_stricmp(mods[m].name, "ntdll.dll") == 0 || _strnicmp(mods[m].name, "kernel", 6) == 0 ||
                         _stricmp(mods[m].name, "user32.dll") == 0 || _stricmp(mods[m].name, "combase.dll") == 0 ||
                         _stricmp(mods[m].name, "ucrtbase.dll") == 0 || _stricmp(mods[m].name, "mswsock.dll") == 0 ||
                         _stricmp(mods[m].name, "ws2_32.dll") == 0 || _stricmp(mods[m].name, "inputhost.dll") == 0 ||
                         _stricmp(mods[m].name, "rpcrt4.dll") == 0 || _stricmp(mods[m].name, "win32u.dll") == 0 ||
                         _stricmp(mods[m].name, "gameoverlayrenderer64.dll") == 0));
        /* known-benign 3rd-party injectors: GPU drivers, Discord/Steam/RTSS overlays, etc. */
        int is3rd    = (strstr(mods[m].name, ".dll") &&
                        (_strnicmp(mods[m].name, "amd", 3) == 0 || _strnicmp(mods[m].name, "nv", 2) == 0 ||
                         _strnicmp(mods[m].name, "ig", 2) == 0 ||   /* intel graphics */
                         strstr(mods[m].name, "Discord") != NULL || strstr(mods[m].name, "discord") != NULL ||
                         strstr(mods[m].name, "Overlay") != NULL || strstr(mods[m].name, "overlay") != NULL ||
                         strstr(mods[m].name, "RTSS") != NULL || strstr(mods[m].name, "Steam") != NULL ||
                         strstr(mods[m].name, "hook") != NULL || strstr(mods[m].name, "Hook") != NULL));
        const char* tag = isLoader ? " [WARDEN -> suspended]"
                        : isWow    ? " [game]"
                        : isSys    ? " [system]"
                        : is3rd    ? " [3rd-party overlay/driver]"
                        :            " [<-- UNKNOWN: investigate]";
        if (!isLoader && !isWow && !isSys && !is3rd) suspicious++;
        snprintf(b, sizeof(b), "  %-28s %2d%s", mods[m].name, mods[m].count, tag);
        IpcHost_LogSession(s, "[gui]", b);
    }
    if (priv > 0) {
        snprintf(b, sizeof(b), "  <private/unmapped start> %d thread(s): %s (expect ~1-2 = dinkr's own worker)", priv, privList);
        IpcHost_LogSession(s, "[gui]", b);
    }
    if (suspicious == 0 && priv <= 2)
        IpcHost_LogSession(s, "[gui]", "=== audit clean: all threads are game/loader/system/known-3rd-party (no hidden Warden) ===");
    else
        IpcHost_LogSession(s, "[gui]", "=== audit: review UNKNOWN/private entries above ===");
}