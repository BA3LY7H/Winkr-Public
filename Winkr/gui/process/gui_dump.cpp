/*
 * gui_dump.cpp — GUI-side binary dump orchestration
 *
 * Creates dump IPC shared memory, injects dinkr_dump.dll,
 * polls for completion (including continuous Warden scan phase).
 * Runs on background thread.
 */

#include "gui_dump.h"
#include "gui_external.h"
#include "gui_ipc_host.h"
#include "dump_protocol.h"

#include <windows.h>
#include <psapi.h>
#include <cstdio>
#include <cstring>

#define DUMP_POLL_MS     200

bool Ext_DumpProcess(WowSession* s)
{
    if (!s || !s->hProcess || !s->pid) {
        IpcHost_LogSession(s, "[dump]", "no attached process");
        return false;
    }

    /* ---- Signal worker loop to stop suspending threads ---- */
    InterlockedExchange(&s->dumpActive, 1);

    /* ---- Resume all currently suspended Warden threads ---- */
    if (s->suspendedCount > 0) {
        char buf[128];
        snprintf(buf, sizeof(buf), "resuming %d suspended thread(s) for dump",
                 s->suspendedCount);
        IpcHost_LogSession(s, "[dump]", buf);

        for (int i = 0; i < s->suspendedCount; i++) {
            if (s->suspendedHandles[i]) {
                ULONG prevCount = 0;
                pNtResumeThread(s->suspendedHandles[i], &prevCount);
            }
        }
        memset(s->suspendedTIDs, 0, sizeof(s->suspendedTIDs));
        memset(s->suspendedHandles, 0, sizeof(s->suspendedHandles));
        s->suspendedCount = 0;
        s->threadsSuspended = false;
        IpcHost_LogSession(s, "[dump]", "all threads resumed");
    }

    /* ---- 1. Build output directory: <exe_dir>\dump\ ---- */
    char exePath[MAX_PATH] = {};
    GetModuleFileNameA(NULL, exePath, MAX_PATH);
    char* lastSlash = strrchr(exePath, '\\');
    if (!lastSlash) {
        IpcHost_LogSession(s, "[dump]", "failed to resolve exe directory");
        return false;
    }
    *(lastSlash + 1) = '\0';

    char outputDir[MAX_PATH];
    snprintf(outputDir, sizeof(outputDir), "%sdump", exePath);
    CreateDirectoryA(outputDir, NULL);

    /* ---- 2. Create dump IPC shared memory ---- */
    char ipcName[80];
    DinkrDumpIpcName((unsigned long)s->pid, ipcName, sizeof(ipcName));

    SECURITY_DESCRIPTOR sd;
    InitializeSecurityDescriptor(&sd, SECURITY_DESCRIPTOR_REVISION);
    SetSecurityDescriptorDacl(&sd, TRUE, NULL, FALSE);

    SECURITY_ATTRIBUTES sa;
    sa.nLength = sizeof(SECURITY_ATTRIBUTES);
    sa.lpSecurityDescriptor = &sd;
    sa.bInheritHandle = FALSE;

    HANDLE hMapping = CreateFileMappingA(
        INVALID_HANDLE_VALUE, &sa, PAGE_READWRITE,
        0, (DWORD)sizeof(DinkrDumpIPC), ipcName);

    if (!hMapping) {
        char msg[128];
        snprintf(msg, sizeof(msg), "CreateFileMapping failed (err %lu)",
                 (unsigned long)GetLastError());
        IpcHost_LogSession(s, "[dump]", msg);
        return false;
    }

    DinkrDumpIPC* ipc = (DinkrDumpIPC*)MapViewOfFile(
        hMapping, FILE_MAP_ALL_ACCESS, 0, 0, sizeof(DinkrDumpIPC));

    if (!ipc) {
        CloseHandle(hMapping);
        IpcHost_LogSession(s, "[dump]", "MapViewOfFile failed");
        return false;
    }

    /* Store IPC in session so render thread can read modules_found */
    s->hDumpMapping = hMapping;
    s->pDumpIpc     = (void*)ipc;

    /* Detect client type from process name */
    DumpClientType clientType = DUMP_CLIENT_RETAIL;
    {
        char procName[MAX_PATH] = {};
        DWORD nameSize = MAX_PATH;
        if (QueryFullProcessImageNameA(s->hProcess, 0, procName, &nameSize)) {
            char* slash = strrchr(procName, '\\');
            const char* exeName = slash ? (slash + 1) : procName;

            if (_stricmp(exeName, "WowClassic.exe") == 0 ||
                _stricmp(exeName, "WowClassicB.exe") == 0 ||
                _stricmp(exeName, "WowClassicT.exe") == 0) {
                clientType = DUMP_CLIENT_CLASSIC;
            }
        }
    }

    {
        char msg[128];
        snprintf(msg, sizeof(msg), "client type: %s",
                 clientType == DUMP_CLIENT_CLASSIC ? "Classic" : "Retail");
        IpcHost_LogSession(s, "[dump]", msg);
    }

    /* Initialize IPC fields */
    memset(ipc, 0, sizeof(DinkrDumpIPC));
    ipc->magic       = DINKR_DUMP_MAGIC;
    ipc->client_type = (uint32_t)clientType;
    ipc->status      = DUMP_STATUS_IDLE;
    strncpy(ipc->output_path, outputDir, sizeof(ipc->output_path) - 1);
    ipc->output_path[sizeof(ipc->output_path) - 1] = '\0';

    /* ---- 3. Build dump DLL path ---- */
    char dllPath[MAX_PATH];
    snprintf(dllPath, sizeof(dllPath), "%sdinkr_dump.dll", exePath);

    IpcHost_LogSession(s, "[dump]", "injecting dump DLL...");
    {
        char msg[256];
        snprintf(msg, sizeof(msg), "IPC name='%s' output='%s' dllPath='%s'",
                 ipcName, outputDir, dllPath);
        IpcHost_LogSession(s, "[dump]", msg);
    }

    /* ---- 4. Inject the dump DLL ---- */
    if (!Ext_InjectDumpDLL(s, dllPath)) {
        IpcHost_LogSession(s, "[dump]", "dump DLL injection FAILED");
        Ext_DumpCleanup(s);
        return false;
    }

    IpcHost_LogSession(s, "[dump]", "dump DLL injected — polling...");

    /* ---- 5. Poll IPC — blocks until COMPLETE, FAILED, or stop ---- */
    bool success = false;
    DumpStatus lastStatus = DUMP_STATUS_IDLE;
    LONG lastModules = 0;

    for (;;) {
        Sleep(DUMP_POLL_MS);

        DumpStatus curStatus = (DumpStatus)InterlockedOr(&ipc->status, 0);

        /* Log status transitions */
        if (curStatus != lastStatus) {
            if (ipc->status_msg[0]) {
                IpcHost_LogSession(s, "[dump]", ipc->status_msg);
            }
            if (curStatus == DUMP_STATUS_SCANNING) {
                InterlockedExchange(&s->dumpScanning, 1);
            }
            lastStatus = curStatus;
        }

        /* Log new Warden modules as they appear */
        LONG curModules = InterlockedOr(&ipc->modules_found, 0);
        if (curModules != lastModules) {
            char msg[128];
            snprintf(msg, sizeof(msg), "Warden modules found: %ld", curModules);
            IpcHost_LogSession(s, "[dump]", msg);
            lastModules = curModules;
        }

        if (curStatus == DUMP_STATUS_COMPLETE) {
            char msg[320];
            snprintf(msg, sizeof(msg), "dump complete — %u bytes, %ld modules to %s",
                     ipc->bytes_written, curModules, ipc->output_path);
            IpcHost_LogSession(s, "[dump]", msg);
            success = true;
            break;
        }

        if (curStatus == DUMP_STATUS_FAILED) {
            char msg[320];
            snprintf(msg, sizeof(msg), "dump FAILED: %s",
                     ipc->error_msg[0] ? ipc->error_msg : "unknown error");
            IpcHost_LogSession(s, "[dump]", msg);
            break;
        }

        /* SCANNING is NOT terminal — keep polling until COMPLETE/FAILED */
    }

    /* ---- 6. Cleanup ---- */
    InterlockedExchange(&s->dumpScanning, 0);
    InterlockedExchange(&s->dumpActive, 0);
    Ext_DumpCleanup(s);

    return success;
}

void Ext_RequestDumpStop(WowSession* s)
{
    if (!s || !s->pDumpIpc) return;
    DinkrDumpIPC* ipc = (DinkrDumpIPC*)s->pDumpIpc;
    InterlockedExchange(&ipc->stop_requested, 1);
    IpcHost_LogSession(s, "[dump]", "stop requested — waiting for DLL to finish...");
}

void Ext_DumpCleanup(WowSession* s)
{
    if (!s) return;
    if (s->pDumpIpc) {
        UnmapViewOfFile(s->pDumpIpc);
        s->pDumpIpc = NULL;
    }
    if (s->hDumpMapping) {
        CloseHandle(s->hDumpMapping);
        s->hDumpMapping = NULL;
    }
}
