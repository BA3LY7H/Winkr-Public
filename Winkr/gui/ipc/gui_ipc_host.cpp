/*
 * gui_ipc_host.cpp — GUI-side IPC implementation (per-session)
 *
 * Each WowSession gets its own shared memory region, named
 * with a GUID-style IPC name derived from the process PID.
 */

#include "gui_ipc_host.h"
#include "gui_external.h"
#include <cstdio>
#include <cstring>

/* ======================================================================
 * Shared helper: write timestamped line to IPC ring buffer + file
 * ====================================================================== */

static void WriteLog(volatile DinkrIPC* ipc, const char* filename,
                     const char* prefix, const char* msg)
{
    SYSTEMTIME st;
    GetLocalTime(&st);

    char line[512];
    int len = snprintf(line, sizeof(line), "[%02d:%02d:%02d.%03d] %s %s\n",
                       st.wHour, st.wMinute, st.wSecond, st.wMilliseconds,
                       prefix ? prefix : "", msg ? msg : "");
    if (len <= 0 || len >= (int)sizeof(line)) return;

    /* Write to IPC ring buffer using CAS loop */
    if (ipc) {
        for (;;) {
            LONG cur = ipc->log_write_pos;
            LONG next = cur + len;
            if (next > DINKR_LOG_SIZE) next = len; /* wrap */
            if (InterlockedCompareExchange(&ipc->log_write_pos, next, cur) == cur) {
                LONG writePos = (next > cur) ? cur : 0;
                memcpy((void*)(ipc->log_buffer + writePos), line, (size_t)len);
                break;
            }
        }
    }

    /* Append to file log */
    if (filename) {
        FILE* f = fopen(filename, "a");
        if (f) { fwrite(line, 1, (size_t)len, f); fclose(f); }
    }
}

/* ======================================================================
 * Per-session Create / Destroy
 * ====================================================================== */

bool IpcHost_CreateForSession(WowSession* s)
{
    if (!s || s->pIpc) return (s && s->pIpc);

    CreateDirectoryA("C:\\mods", NULL);

    char ipcName[80];
    DinkrIpcName((unsigned long)s->pid, ipcName, sizeof(ipcName));

    s->hIpcMapping = CreateFileMappingA(
        INVALID_HANDLE_VALUE, NULL, PAGE_READWRITE,
        0, (DWORD)sizeof(DinkrIPC), ipcName);

    if (!s->hIpcMapping) return false;

    bool alreadyExisted = (GetLastError() == ERROR_ALREADY_EXISTS);

    s->pIpc = (DinkrIPC*)MapViewOfFile(
        s->hIpcMapping, FILE_MAP_ALL_ACCESS, 0, 0, sizeof(DinkrIPC));

    if (!s->pIpc) {
        CloseHandle(s->hIpcMapping);
        s->hIpcMapping = NULL;
        return false;
    }

    /* Build per-session log filename */
    char logPath[128];
    snprintf(logPath, sizeof(logPath), "C:\\mods\\dinkr_gui_%lu.txt",
             (unsigned long)s->pid);

    if (alreadyExisted &&
        s->pIpc->magic == DINKR_IPC_MAGIC &&
        s->pIpc->dll_status >= DLL_STATUS_ATTACHED &&
        s->pIpc->dll_status <= DLL_STATUS_READY)
    {
        /* DLL still present — reconnect without wiping state */
        s->pIpc->log_write_pos = 0;
        memset((void*)s->pIpc->log_buffer, 0, DINKR_LOG_SIZE);
        s->reconnected = true;

        FILE* f = fopen(logPath, "w"); if (f) fclose(f);

        IpcHost_LogSession(s, "[gui]", "=== reconnected to active DLL ===");
        return true;
    }

    /* Fresh session */
    memset((void*)s->pIpc, 0, sizeof(DinkrIPC));
    s->pIpc->magic   = DINKR_IPC_MAGIC;
    s->pIpc->version = 3;
    s->reconnected = false;

    FILE* f = fopen(logPath, "w"); if (f) fclose(f);

    IpcHost_LogSession(s, "[gui]", "=== DINKR session started ===");
    return true;
}

void IpcHost_DestroyForSession(WowSession* s)
{
    if (!s) return;
    if (s->pIpc) {
        UnmapViewOfFile((void*)s->pIpc);
        s->pIpc = nullptr;
    }
    if (s->hIpcMapping) {
        CloseHandle(s->hIpcMapping);
        s->hIpcMapping = NULL;
    }
}

/* ======================================================================
 * Logging
 * ====================================================================== */

void IpcHost_LogSession(WowSession* s, const char* prefix, const char* msg)
{
    char logPath[128];
    if (s && s->pid)
        snprintf(logPath, sizeof(logPath), "C:\\mods\\dinkr_gui_%lu.txt",
                 (unsigned long)s->pid);
    else
        snprintf(logPath, sizeof(logPath), "C:\\mods\\dinkr_gui_debug.txt");

    WriteLog(s ? s->pIpc : nullptr, logPath, prefix, msg);
}

void IpcHost_Log(const char* prefix, const char* msg)
{
    WriteLog(nullptr, "C:\\mods\\dinkr_gui_debug.txt", prefix, msg);
}

/* ======================================================================
 * Command helpers
 * ====================================================================== */

void IpcHost_SignalReload(DinkrIPC* ipc)
{
    if (!ipc) return;
    InterlockedExchange(&ipc->cmd_reload_mods, 1);
}
