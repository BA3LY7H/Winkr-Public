/*
 * gui_external.cpp — External process operations for the DINKR GUI
 *
 * Core module: process attachment, build verification, OM enumeration,
 * memory read/write, game state detection, and security patches.
 * All operations are per-session (WowSession*) to support multiple WoW windows.
 *
 * Build: 66838
 * Compiler: GCC (MinGW-w64), compiled as C++17
 */

#include "gui_external.h"
#include "rva_defs.h"
#include "om_types.h"
#include "ipc_protocol.h"
#include "wow_guid_format.h"

#include <windows.h>
#include <psapi.h>
#include <tlhelp32.h>
#include <cstdio>
#include <cstring>
#include <cstdlib>

/* ======================================================================
 * NtAPI function pointers (global — loaded once, shared across sessions)
 * ====================================================================== */

pfn_NtOpenThread               pNtOpenThread              = nullptr;
pfn_NtSuspendThread            pNtSuspendThread           = nullptr;
pfn_NtResumeThread             pNtResumeThread            = nullptr;
pfn_NtGetContextThread         pNtGetContextThread        = nullptr;
pfn_NtSetContextThread         pNtSetContextThread        = nullptr;
pfn_NtQueryInformationThread   pNtQueryInformationThread  = nullptr;
pfn_NtAlertThread              pNtAlertThread             = nullptr;
pfn_NtCreateThreadEx           pNtCreateThreadEx          = nullptr;

/* ======================================================================
 * Session lifecycle
 * ====================================================================== */

void Session_InitDefaults(WowSession* s)
{
    s->currentFilter     = 0;
    s->searchText[0]     = '\0';
    s->consoleHeight     = 200.0f;
    s->consoleAutoScroll = true;
    s->sortColumn        = 0;
    s->sortDirection     = 1; /* ImGuiSortDirection_Ascending */
    s->detailHeight      = 280.0f;
    s->selectedGuidLo    = 0;
    s->selectedGuidHi    = 0;
    s->injecting         = false;
    s->injectStartTick   = 0;
    s->injectPatched     = false;
    s->dumping           = 0;
    s->dumpActive        = 0;
    s->dumpScanning      = 0;
    s->dumpDoneTick      = 0;
    s->dumpResult        = 0;
    s->hDumpThread       = NULL;
    s->hDumpMapping      = NULL;
    s->pDumpIpc          = NULL;
    s->hasSnapshot       = false;
    memset(&s->lastSelected, 0, sizeof(s->lastSelected));
}

WowSession* Session_Create(DWORD pid, int index)
{
    auto* s = (WowSession*)calloc(1, sizeof(WowSession));
    if (!s) return nullptr;

    s->pid   = pid;
    s->index = index;
    s->alive = true;
    s->userClosed = false;
    s->running = 1;

    Session_InitDefaults(s);
    return s;
}

void Session_Destroy(WowSession* s)
{
    if (!s) return;

    /* Signal worker thread to stop */
    InterlockedExchange(&s->running, 0);
    if (s->hWorkerThread) {
        WaitForSingleObject(s->hWorkerThread, 5000);
        CloseHandle(s->hWorkerThread);
        s->hWorkerThread = NULL;
    }

    Ext_DetachSession(s);
    IpcHost_DestroyForSession(s);
    free(s);
}

int Ext_GetSuspendedThreads(WowSession* s, DWORD* outTIDs, int maxCount)
{
    if (!s) return 0;
    int count = s->suspendedCount;
    if (count > maxCount) count = maxCount;
    if (count > 0 && outTIDs)
        memcpy(outTIDs, s->suspendedTIDs, count * sizeof(DWORD));
    return count;
}

/* Entity resolution offsets (same as DLL, for cross-process OM walk) */
#define ENTITY_ARCHETYPE     8
#define ARCH_RESOLVE_OFFSET  56
#define ARCH_CHUNKLIST       1104
#define ENTITY_SLOT          16

/* ======================================================================
 * Helpers
 * ====================================================================== */

bool Ext_RPM(WowSession* s, uintptr_t addr, void* buf, size_t sz)
{
    if (!s || !s->hProcess || !addr || !buf || !sz) return false;
    SIZE_T bytesRead = 0;
    return ReadProcessMemory(s->hProcess, (LPCVOID)addr, buf, sz, &bytesRead)
           && bytesRead == sz;
}

bool Ext_WPM(WowSession* s, uintptr_t addr, const void* buf, size_t sz)
{
    if (!s || !s->hProcess || !addr || !buf || !sz) return false;
    SIZE_T bytesWritten = 0;
    return WriteProcessMemory(s->hProcess, (LPVOID)addr, buf, sz, &bytesWritten)
           && bytesWritten == sz;
}

/* Convenience wrappers (session-based) */
static uint64_t rpm_u64(WowSession* s, uintptr_t addr) {
    uint64_t val = 0; Ext_RPM(s, addr, &val, sizeof(val)); return val;
}
static uint32_t rpm_u32(WowSession* s, uintptr_t addr) {
    uint32_t val = 0; Ext_RPM(s, addr, &val, sizeof(val)); return val;
}

/* ======================================================================
 * Process scanning — find all Wow.exe PIDs
 * ====================================================================== */

int Ext_ScanWowProcesses(DWORD* outPids, int maxCount)
{
    HANDLE hSnap = CreateToolhelp32Snapshot(TH32CS_SNAPPROCESS, 0);
    if (hSnap == INVALID_HANDLE_VALUE) return 0;

    PROCESSENTRY32 pe = {};
    pe.dwSize = sizeof(pe);
    int found = 0;

    if (Process32First(hSnap, &pe)) {
        do {
            if ((_stricmp(pe.szExeFile, "WowClassic.exe") == 0 ||    /* Classic repo: WowClassic is the target */
                 _stricmp(pe.szExeFile, "WowClassicB.exe") == 0 ||
                 _stricmp(pe.szExeFile, "WowClassicT.exe") == 0) &&
                found < maxCount)
            {
                outPids[found++] = pe.th32ProcessID;
            }
        } while (Process32Next(hSnap, &pe));
    }
    CloseHandle(hSnap);
    return found;
}

/* ======================================================================
 * Process attachment (per-session)
 * ====================================================================== */

bool Ext_AttachSession(WowSession* s)
{
    if (!s || s->hProcess) return true;

    HANDLE hProc = OpenProcess(
        PROCESS_VM_READ | PROCESS_VM_WRITE | PROCESS_VM_OPERATION |
        PROCESS_QUERY_INFORMATION | PROCESS_CREATE_THREAD,
        FALSE, s->pid);
    if (!hProc) return false;

    HMODULE hMods[1];
    DWORD cbNeeded = 0;
    if (!EnumProcessModulesEx(hProc, hMods, sizeof(hMods), &cbNeeded, LIST_MODULES_ALL) ||
        cbNeeded == 0) {
        CloseHandle(hProc);
        return false;
    }

    MODULEINFO modInfo = {};
    if (!GetModuleInformation(hProc, hMods[0], &modInfo, sizeof(modInfo))) {
        CloseHandle(hProc);
        return false;
    }

    s->hProcess = hProc;
    s->baseAddr = (uintptr_t)modInfo.lpBaseOfDll;
    s->verified = false;

    return true;
}

void Ext_DetachSession(WowSession* s)
{
    if (!s) return;

    if (s->hProcess) {
        CloseHandle(s->hProcess);
        s->hProcess = NULL;
    }
    s->baseAddr  = 0;
    s->verified  = false;

    /* Close all suspended-thread handles */
    for (int i = 0; i < s->suspendedCount; i++) {
        if (s->suspendedHandles[i]) {
            CloseHandle(s->suspendedHandles[i]);
            s->suspendedHandles[i] = NULL;
        }
        s->suspendedTIDs[i] = 0;
    }
    s->suspendedCount = 0;

    /* Reset Lua reload-detection state */
    s->lastLuaState       = 0;
    s->lastLuaCreateCount = 0;

    /* Allow re-injection */
    s->alreadyInjected = false;
}

bool Ext_IsSessionAttached(WowSession* s)
{
    if (!s || !s->hProcess) return false;
    DWORD exitCode = 0;
    if (!GetExitCodeProcess(s->hProcess, &exitCode) || exitCode != STILL_ACTIVE) {
        Ext_DetachSession(s);
        s->alive = false;
        return false;
    }
    return true;
}

/* ======================================================================
 * Build verification
 * ====================================================================== */

bool Ext_VerifyBuild(WowSession* s)
{
    if (!s) return false;
    if (s->verified) return true;
    if (!s->hProcess) return false;

    /* Get exe path via QueryFullProcessImageNameA */
    char exePath[MAX_PATH] = {};
    DWORD pathLen = MAX_PATH;
    if (!QueryFullProcessImageNameA(s->hProcess, 0, exePath, &pathLen)) {
        IpcHost_LogSession(s, "[gui]", "WARN: QueryFullProcessImageName failed");
        return false;
    }

    /* DINKR_CLASSIC repo: WowClassic.exe IS the native target -> full inject.
     * (In the retail repo this block flips WowClassic to dump-only; here it's removed
     * so it goes through the normal build check against EXPECTED_BUILD=68940.) */

    /* Load version.dll to read VERSIONINFO */
    HMODULE hVersion = LoadLibraryA("version.dll");
    if (!hVersion) return false;

    typedef DWORD (WINAPI *pfnGetFileVersionInfoSizeA)(LPCSTR, LPDWORD);
    typedef BOOL  (WINAPI *pfnGetFileVersionInfoA)(LPCSTR, DWORD, DWORD, LPVOID);
    typedef BOOL  (WINAPI *pfnVerQueryValueA)(LPCVOID, LPCSTR, LPVOID*, PUINT);

    auto pGetSize = (pfnGetFileVersionInfoSizeA)(void*)GetProcAddress(hVersion, "GetFileVersionInfoSizeA");
    auto pGetInfo = (pfnGetFileVersionInfoA)(void*)GetProcAddress(hVersion, "GetFileVersionInfoA");
    auto pQuery   = (pfnVerQueryValueA)(void*)GetProcAddress(hVersion, "VerQueryValueA");

    if (!pGetSize || !pGetInfo || !pQuery) {
        FreeLibrary(hVersion);
        return false;
    }

    DWORD dummy = 0;
    DWORD infoSize = pGetSize(exePath, &dummy);
    if (infoSize == 0) { FreeLibrary(hVersion); return false; }

    auto verBuf = (BYTE*)VirtualAlloc(NULL, infoSize, MEM_COMMIT | MEM_RESERVE, PAGE_READWRITE);
    if (!verBuf) { FreeLibrary(hVersion); return false; }

    if (!pGetInfo(exePath, 0, infoSize, verBuf)) {
        VirtualFree(verBuf, 0, MEM_RELEASE);
        FreeLibrary(hVersion);
        return false;
    }

    DWORD buildNumber = 0;

    /* Try Translation table first */
    {
        struct { WORD wLanguage; WORD wCodePage; } *pTranslate = nullptr;
        UINT translateLen = 0;
        char cpStrings[8][20];
        int cpCount = 0;

        if (pQuery(verBuf, "\\VarFileInfo\\Translation",
                   (LPVOID*)&pTranslate, &translateLen) &&
            pTranslate && translateLen >= 4) {
            int n = (int)(translateLen / 4);
            for (int i = 0; i < n && cpCount < 6; i++)
                snprintf(cpStrings[cpCount++], 20, "%04x%04x",
                         pTranslate[i].wLanguage, pTranslate[i].wCodePage);
        }
        if (cpCount == 0) {
            snprintf(cpStrings[cpCount++], 20, "040904B0");
            snprintf(cpStrings[cpCount++], 20, "040904E4");
            snprintf(cpStrings[cpCount++], 20, "000004B0");
        }

        for (int i = 0; i < cpCount && !buildNumber; i++) {
            char qp[128];
            snprintf(qp, sizeof(qp), "\\StringFileInfo\\%s\\FileVersion", cpStrings[i]);
            LPVOID strPtr = nullptr;
            UINT strLen = 0;
            if (pQuery(verBuf, qp, &strPtr, &strLen) && strPtr && strLen > 0) {
                const char* verStr = (const char*)strPtr;
                const char* last = nullptr;
                for (const char* p = verStr; *p; p++)
                    if (*p == '.' || *p == ',') last = p;
                if (last && *(last + 1)) {
                    const char* ns = last + 1;
                    while (*ns == ' ') ns++;
                    buildNumber = (DWORD)atoi(ns);
                }
            }
        }
    }

    /* Fallback: VS_FIXEDFILEINFO — extract build from version DWORD directly */
    if (!buildNumber) {
        struct { DWORD sig, sv, fvMS, fvLS, pvMS, pvLS, ffm, ff, fo, ft, fst, fdMS, fdLS; } *pF = nullptr;
        UINT fLen = 0;
        if (pQuery(verBuf, "\\", (LPVOID*)&pF, &fLen) && pF && fLen >= 52 && pF->sig == 0xFEEF04BD) {
            /* fvLS: high word = minor2, low word = build (last component) */
            buildNumber = pF->fvLS & 0xFFFF;
        }
    }

    VirtualFree(verBuf, 0, MEM_RELEASE);
    FreeLibrary(hVersion);

    if (buildNumber != EXPECTED_BUILD) {
        char logBuf[256];
        snprintf(logBuf, sizeof(logBuf), "BUILD MISMATCH: expected %u, got %lu",
                 EXPECTED_BUILD, (unsigned long)buildNumber);
        IpcHost_LogSession(s, "[gui]", logBuf);
        return false;
    }

    if (s->pIpc) s->pIpc->build_number = buildNumber;

    s->verified = true;

    char logBuf2[128];
    snprintf(logBuf2, sizeof(logBuf2), "build %lu verified", (unsigned long)buildNumber);
    IpcHost_LogSession(s, "[gui]", logBuf2);

    return true;
}

/* ======================================================================
 * OM enumeration — cross-process via RPM
 * ====================================================================== */

int Ext_EnumerateOM(WowSession* s)
{
    if (!s || !s->pIpc || !s->hProcess || !s->baseAddr) return 0;
    DinkrIPC* ipc = s->pIpc;

    /* Read GUIDs from globals (fallback — DLL also does this) */
    if (ipc->active_player_guid_lo == 0 && ipc->active_player_guid_hi == 0) {
        ipc->active_player_guid_lo = rpm_u64(s, s->baseAddr + RVA_ActivePlayerGUID);
        ipc->active_player_guid_hi = rpm_u64(s, s->baseAddr + RVA_ActivePlayerGUID + 8);
        ipc->target_guid_lo        = rpm_u64(s, s->baseAddr + RVA_TargetGUID);
        ipc->target_guid_hi        = rpm_u64(s, s->baseAddr + RVA_TargetGUID + 8);
        ipc->focus_guid_lo         = rpm_u64(s, s->baseAddr + RVA_FocusGUID);
        ipc->focus_guid_hi         = rpm_u64(s, s->baseAddr + RVA_FocusGUID + 8);
        ipc->mouseover_guid_lo     = rpm_u64(s, s->baseAddr + RVA_MouseoverGUID);
        ipc->mouseover_guid_hi     = rpm_u64(s, s->baseAddr + RVA_MouseoverGUID + 8);
    }

    return (int)ipc->om_object_count;
}


/* ======================================================================
 * In-game detection (cross-process)
 * ====================================================================== */

bool Ext_IsPlayerInGame(WowSession* s)
{
    // Disabled for build 68453 — g_GameStateFlags RVA is stale
    return true;
    //if (!s || !s->hProcess || !s->baseAddr) return false;
    //uint16_t flags = (uint16_t)rpm_u32(s, s->baseAddr + RVA_g_GameStateFlags);
    //return (flags & 0x200) != 0;
}

uint32_t Ext_GetRawGameStateFlags(WowSession* s)
{
    if (!s || !s->hProcess || !s->baseAddr) return 0;
    return rpm_u32(s, s->baseAddr + RVA_g_GameStateFlags);
}

/* ======================================================================
 * Reload detection
 * ====================================================================== */

bool Ext_DetectReload(WowSession* s)
{
    if (!s || !s->pIpc || !s->hProcess || !s->baseAddr) return false;

    static DWORD g_lastReloadDetectTick = 0;

    uint64_t  curLua   = rpm_u64(s, s->baseAddr + RVA_G_LUASTATE);
    uint32_t  curCount = rpm_u32(s, s->baseAddr + RVA_G_LUASTATE_CREATE_COUNT);

    bool reload = false;
    if (s->lastLuaState != 0 || s->lastLuaCreateCount != 0) {
        if (curLua != s->lastLuaState || curCount != s->lastLuaCreateCount) {
            DWORD now = GetTickCount();
            if ((now - g_lastReloadDetectTick) < 5000) {
                char logBuf[256];
                snprintf(logBuf, sizeof(logBuf),
                         "reload suppressed (cooldown): L %llX->%llX, count %u->%u",
                         (unsigned long long)s->lastLuaState, (unsigned long long)curLua,
                         s->lastLuaCreateCount, curCount);
                IpcHost_LogSession(s, "[gui]", logBuf);
            } else {
                reload = true;
                g_lastReloadDetectTick = now;
                char logBuf[256];
                snprintf(logBuf, sizeof(logBuf),
                         "reload detected: L %llX->%llX, count %u->%u",
                         (unsigned long long)s->lastLuaState, (unsigned long long)curLua,
                         s->lastLuaCreateCount, curCount);
                IpcHost_LogSession(s, "[gui]", logBuf);
            }
        }
    }

    s->lastLuaState       = curLua;
    s->lastLuaCreateCount = curCount;

    return reload;
}

/* ======================================================================
 * Security patches — handled by DLL
 * ====================================================================== */

int Ext_ApplyPatches(WowSession* s)
{
    (void)s;
    IpcHost_Log("[gui]", "[security] patches now handled by DLL — GUI is no-op");
    return 0;
}

int Ext_ReapplyPatches(WowSession* s)
{
    (void)s;
    IpcHost_Log("[gui]", "[security] re-patches now handled by DLL — GUI is no-op");
    return 0;
}

/* ======================================================================
 * NtDLL initialization
 * ====================================================================== */

bool Ext_InitNtdll()
{
    HMODULE hNtdll = GetModuleHandleA("ntdll.dll");
    if (!hNtdll) return false;

    pNtOpenThread             = (pfn_NtOpenThread)(void*)GetProcAddress(hNtdll, "NtOpenThread");
    pNtSuspendThread          = (pfn_NtSuspendThread)(void*)GetProcAddress(hNtdll, "NtSuspendThread");
    pNtResumeThread           = (pfn_NtResumeThread)(void*)GetProcAddress(hNtdll, "NtResumeThread");
    pNtGetContextThread       = (pfn_NtGetContextThread)(void*)GetProcAddress(hNtdll, "NtGetContextThread");
    pNtSetContextThread       = (pfn_NtSetContextThread)(void*)GetProcAddress(hNtdll, "NtSetContextThread");
    pNtQueryInformationThread = (pfn_NtQueryInformationThread)(void*)GetProcAddress(hNtdll, "NtQueryInformationThread");
    pNtAlertThread            = (pfn_NtAlertThread)(void*)GetProcAddress(hNtdll, "NtAlertThread");
    pNtCreateThreadEx         = (pfn_NtCreateThreadEx)(void*)GetProcAddress(hNtdll, "NtCreateThreadEx");

    return (pNtOpenThread && pNtSuspendThread && pNtResumeThread &&
            pNtGetContextThread && pNtSetContextThread && pNtQueryInformationThread);
}