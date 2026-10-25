/*
 * gui_external.h — External process operations for the DINKR GUI
 *
 * Supports multiple WoW processes via WowSession structs.
 * Each session owns its own process handle, IPC mapping, warden state,
 * injection state, worker thread, and render state.
 */

#pragma once
#ifndef DINKR_GUI_EXTERNAL_H
#define DINKR_GUI_EXTERNAL_H

#include "../shared/ipc_protocol.h"
#include "../shared/dump_protocol.h"
#include "../shared/rva_defs.h"
#include "../shared/om_types.h"
#include <windows.h>
#include <cstdint>

/* ========================================================================
 * NtAPI types & function pointers (global — loaded once, shared)
 * ======================================================================== */

typedef LONG NTSTATUS_T;
#define NT_SUCCESS_CHECK(s) ((s) == 0)

typedef struct { PVOID UniqueProcess; PVOID UniqueThread; } NT_CLIENT_ID;
typedef struct {
    ULONG Length; HANDLE RootDirectory; PVOID ObjectName;
    ULONG Attributes; PVOID SecurityDescriptor; PVOID SecurityQualityOfService;
} NT_OBJECT_ATTRIBUTES;

typedef NTSTATUS_T (NTAPI *pfn_NtOpenThread)(PHANDLE, ACCESS_MASK, NT_OBJECT_ATTRIBUTES*, NT_CLIENT_ID*);
typedef NTSTATUS_T (NTAPI *pfn_NtSuspendThread)(HANDLE, PULONG);
typedef NTSTATUS_T (NTAPI *pfn_NtResumeThread)(HANDLE, PULONG);
typedef NTSTATUS_T (NTAPI *pfn_NtGetContextThread)(HANDLE, PCONTEXT);
typedef NTSTATUS_T (NTAPI *pfn_NtSetContextThread)(HANDLE, PCONTEXT);
typedef NTSTATUS_T (NTAPI *pfn_NtQueryInformationThread)(HANDLE, ULONG, PVOID, ULONG, PULONG);
typedef NTSTATUS_T (NTAPI *pfn_NtAlertThread)(HANDLE);
typedef NTSTATUS_T (NTAPI *pfn_NtCreateThreadEx)(
    PHANDLE ThreadHandle, ACCESS_MASK DesiredAccess, PVOID ObjectAttributes,
    HANDLE ProcessHandle, PVOID StartRoutine, PVOID Argument,
    ULONG CreateFlags, SIZE_T ZeroBits, SIZE_T StackSize,
    SIZE_T MaximumStackSize, PVOID AttributeList);

extern pfn_NtOpenThread               pNtOpenThread;
extern pfn_NtSuspendThread            pNtSuspendThread;
extern pfn_NtResumeThread             pNtResumeThread;
extern pfn_NtGetContextThread         pNtGetContextThread;
extern pfn_NtSetContextThread         pNtSetContextThread;
extern pfn_NtQueryInformationThread   pNtQueryInformationThread;
extern pfn_NtAlertThread              pNtAlertThread;
extern pfn_NtCreateThreadEx           pNtCreateThreadEx;

/* ========================================================================
 * WowSession — per-process state (one per tab)
 * ======================================================================== */

#define MAX_SUSPENDED_HANDLES 128

struct WowSession {
    /* Identity */
    DWORD     pid;
    int       index;              /* 1-based display index (WoW #1, #2...) */
    bool      alive;              /* process still running?                */
    bool      userClosed;         /* user manually closed the tab?         */

    /* Process state */
    HANDLE    hProcess;
    uintptr_t baseAddr;
    bool      verified;

    /* IPC shared memory */
    HANDLE    hIpcMapping;
    DinkrIPC* pIpc;
    bool      reconnected;

    /* Worker thread */
    HANDLE    hWorkerThread;
    volatile LONG running;

    /* Worker internal state */
    bool      buildOK;
    bool      isClassic;       /* WowClassic.exe -> DUMP-ONLY (retail dinkr.dll must never inject) */
    bool      startupWaitDone;
    bool      threadsSuspended;
    bool      inGameDetected;
    bool      patchesDone;
    bool      wasAttachedWorker;
    bool      wasPlayerInGame;
    bool      playerTrackingInit;
    DWORD     lastOM;
    DWORD     lastWardenSweep;

    /* Reload detection */
    uint64_t  lastLuaState;
    uint32_t  lastLuaCreateCount;

    /* Injection state */
    bool      alreadyInjected;
    volatile LONG dllInjected;

    /* Warden thread suspension */
    HANDLE    suspendedHandles[MAX_SUSPENDED_HANDLES];
    DWORD     suspendedTIDs[MAX_SUSPENDED_HANDLES];
    int       suspendedCount;

    /* Render state (per-tab UI) */
    int       currentFilter;
    char      searchText[256];
    float     consoleHeight;
    bool      consoleAutoScroll;
    int       sortColumn;
    int       sortDirection;
    float     detailHeight;
    uint64_t  selectedGuidLo;
    uint64_t  selectedGuidHi;
    bool      injecting;
    DWORD     injectStartTick;
    bool      injectPatched;

    /* Dump state */
    volatile LONG dumping;           /* 1 = dump in progress              */
    volatile LONG dumpActive;        /* 1 = suppress thread suspension    */
    volatile LONG dumpScanning;      /* 1 = DLL in continuous scan mode   */
    DWORD         dumpDoneTick;      /* GetTickCount() when dump finished */
    int           dumpResult;        /* 0 = success, nonzero = failed     */
    HANDLE        hDumpThread;       /* background dump thread handle     */
    HANDLE        hDumpMapping;      /* IPC shared memory (kept alive)    */
    void*         pDumpIpc;          /* DinkrDumpIPC* (cast in .cpp)      */

    OmCacheEntry lastSelected;    /* detail panel snapshot */
    bool      hasSnapshot;
};

/* ---- Session lifecycle ---- */
WowSession* Session_Create(DWORD pid, int index);
void        Session_Destroy(WowSession* s);
void        Session_InitDefaults(WowSession* s);

/* ---- Process attachment (per-session) ---- */
bool      Ext_AttachSession(WowSession* s);
void      Ext_DetachSession(WowSession* s);
bool      Ext_IsSessionAttached(WowSession* s);

/* ---- Memory helpers (per-session) ---- */
bool      Ext_RPM(WowSession* s, uintptr_t addr, void* buf, size_t sz);
bool      Ext_WPM(WowSession* s, uintptr_t addr, const void* buf, size_t sz);

/* ---- Build verification ---- */
bool      Ext_VerifyBuild(WowSession* s);

/* ---- Object Manager enumeration (cross-process) ---- */
int       Ext_EnumerateOM(WowSession* s);

/* ---- In-game detection ---- */
bool      Ext_IsPlayerInGame(WowSession* s);
uint32_t  Ext_GetRawGameStateFlags(WowSession* s);

/* ---- Reload detection ---- */
bool      Ext_DetectReload(WowSession* s);

/* ---- NtDLL initialization (global, call once) ---- */
bool      Ext_InitNtdll();

/* ---- Warden thread suspension (per-session) ---- */
int       Ext_SuspendWardenThreads(WowSession* s);
void      Ext_DiagThreadsByModule(WowSession* s);  /* audit: every thread's start-module */

/* ---- Security patches (per-session, DLL handles) ---- */
int       Ext_ApplyPatches(WowSession* s);
int       Ext_ReapplyPatches(WowSession* s);

/* ---- Thread info (for GUI thread panel) ---- */
int       Ext_GetSuspendedThreads(WowSession* s, DWORD* outTIDs, int maxCount);

/* ---- DLL Injection (per-session) ---- */
bool      Ext_InjectDLL(WowSession* s, const char* dllPath);
bool      Ext_InjectDumpDLL(WowSession* s, const char* dllPath);

/* ---- Binary dump (per-session) ---- */
bool      Ext_DumpProcess(WowSession* s);

/* ---- IPC (per-session) ---- */
bool      IpcHost_CreateForSession(WowSession* s);
void      IpcHost_DestroyForSession(WowSession* s);
void      IpcHost_Log(const char* prefix, const char* msg);
void      IpcHost_LogSession(WowSession* s, const char* prefix, const char* msg);
void      IpcHost_SignalReload(DinkrIPC* ipc);

/* ---- Process scanning ---- */
int       Ext_ScanWowProcesses(DWORD* outPids, int maxCount);

#endif /* DINKR_GUI_EXTERNAL_H */
