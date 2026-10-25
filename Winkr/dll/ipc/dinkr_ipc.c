/*
** dinkr_ipc.c — DLL-side IPC implementation
**
** Opens the shared memory region created by the GUI process and provides
** functions to write logs, update OM snapshots, report patch status, and
** check for GUI commands.
**
** Thread safety: All writes to shared memory use interlocked operations
** or are single-writer (only the DLL writes to most fields).
** The GUI reads atomically by checking sequence numbers.
*/

#include "dinkr_ipc.h"
#include <string.h>
#include <stdio.h>

/* ========================================================================
** Module state
** ======================================================================== */

static HANDLE    g_hMapping = NULL;
static DinkrIPC* g_pIpc     = NULL;
static HANDLE    g_hLogFile = INVALID_HANDLE_VALUE; /* persistent file log handle */

/* ========================================================================
** Init / Close
** ======================================================================== */

BOOL InitIPC(void) {
    if (g_pIpc) return TRUE;  /* already initialized */

    /* Open the named shared memory created by the GUI (name derived from PID) */
    char ipcName[80];
    DinkrIpcName((unsigned long)GetCurrentProcessId(), ipcName, sizeof(ipcName));
    g_hMapping = OpenFileMappingA(FILE_MAP_ALL_ACCESS, FALSE, ipcName);
    if (!g_hMapping) {
        return FALSE;
    }

    g_pIpc = (DinkrIPC*)MapViewOfFile(
        g_hMapping, FILE_MAP_ALL_ACCESS, 0, 0, sizeof(DinkrIPC));
    if (!g_pIpc) {
        CloseHandle(g_hMapping);
        g_hMapping = NULL;
        return FALSE;
    }

    /* Validate magic — ensures GUI created the region correctly */
    if (g_pIpc->magic != DINKR_IPC_MAGIC) {
        UnmapViewOfFile(g_pIpc);
        g_pIpc = NULL;
        CloseHandle(g_hMapping);
        g_hMapping = NULL;
        return FALSE;
    }

    /* Validate protocol version — DLL and GUI must agree */
    if (g_pIpc->version < 3) {
        UnmapViewOfFile(g_pIpc);
        g_pIpc = NULL;
        CloseHandle(g_hMapping);
        g_hMapping = NULL;
        return FALSE;
    }

    /* Initial status */
    g_pIpc->dll_status = DLL_STATUS_ATTACHED;

    return TRUE;
}

void CloseIPC(void) {
    /* Close persistent log file handle */
    if (g_hLogFile != INVALID_HANDLE_VALUE) {
        CloseHandle(g_hLogFile);
        g_hLogFile = INVALID_HANDLE_VALUE;
    }
    if (g_pIpc) {
        g_pIpc->dll_status = DLL_STATUS_DETACHED;
        UnmapViewOfFile(g_pIpc);
        g_pIpc = NULL;
    }
    if (g_hMapping) {
        CloseHandle(g_hMapping);
        g_hMapping = NULL;
    }
}

DinkrIPC* GetIPC(void) {
    return g_pIpc;
}

/* ========================================================================
** Logging — flat ring buffer write
**
** The shared header uses a flat char buffer (log_buffer[DINKR_LOG_SIZE])
** with log_write_pos. The GUI reads this as a flat text string line-by-line.
** We append formatted text lines and advance log_write_pos atomically.
** ======================================================================== */

void IpcLog(const char* prefix, const char* msg) {
    SYSTEMTIME st;
    GetLocalTime(&st);

    char line[512];
    int len = snprintf(line, sizeof(line), "[%02d:%02d:%02d.%03d] %s %s\n",
                       st.wHour, st.wMinute, st.wSecond, st.wMilliseconds,
                       prefix ? prefix : "", msg ? msg : "");
    if (len <= 0 || len >= (int)sizeof(line)) return;

    /* Write to IPC ring buffer using CAS loop to prevent OOB writes.
     * Two concurrent writers could both InterlockedExchangeAdd past the end;
     * CAS ensures the position wraps atomically. */
    if (g_pIpc) {
        for (;;) {
            LONG cur = g_pIpc->log_write_pos;
            LONG next = cur + len;
            if (next > DINKR_LOG_SIZE) next = len; /* wrap */
            if (InterlockedCompareExchange(&g_pIpc->log_write_pos, next, cur) == cur) {
                LONG writePos = (next > cur) ? cur : 0;
                memcpy(g_pIpc->log_buffer + writePos, line, len);
                break;
            }
        }
    }

    /* Append to persistent log file (opened once, kept open for performance) */
    if (g_hLogFile == INVALID_HANDLE_VALUE) {
        g_hLogFile = CreateFileA("C:\\mods\\dinkr_dll_debug.txt",
                                 FILE_APPEND_DATA,
                                 FILE_SHARE_READ | FILE_SHARE_WRITE,
                                 NULL, OPEN_ALWAYS, FILE_ATTRIBUTE_NORMAL, NULL);
    }
    if (g_hLogFile != INVALID_HANDLE_VALUE) {
        DWORD written;
        WriteFile(g_hLogFile, line, (DWORD)len, &written, NULL);
    }
}

/* ========================================================================
** Status
** ======================================================================== */

void IpcSetStatus(uint32_t status) {
    if (!g_pIpc) return;
    g_pIpc->dll_status = status;
}

/* ========================================================================
** GUI command polling
**
** Uses CompareExchange: atomically reads the flag and clears it.
** Returns TRUE if the command was pending (flag was 1).
** ======================================================================== */

BOOL IpcCheckReloadCmd(void) {
    if (!g_pIpc) return FALSE;
    return InterlockedCompareExchange(&g_pIpc->cmd_reload_mods, 0, 1) == 1;
}

BOOL IpcCheckRefreshCmd(void) {
    if (!g_pIpc) return FALSE;
    return InterlockedCompareExchange(&g_pIpc->cmd_refresh_om, 0, 1) == 1;
}
