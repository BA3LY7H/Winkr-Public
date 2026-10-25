/*
 * dump_protocol.h — Dump IPC protocol between dinkr_dump.dll and dinkr_gui.exe
 *
 * GUI creates shared memory, writes output_path, injects dump DLL.
 * DLL opens shared memory, reads output_path, performs dump, updates status.
 */

#pragma once
#ifndef DINKR_DUMP_PROTOCOL_H
#define DINKR_DUMP_PROTOCOL_H

#include <stdint.h>
#include <stdio.h>
#include <windows.h>

#define DINKR_DUMP_MAGIC   0x574B4400  /* "WKD\0" */

typedef enum {
    DUMP_CLIENT_RETAIL = 0,
    DUMP_CLIENT_CLASSIC = 1
} DumpClientType;

typedef enum {
    DUMP_STATUS_IDLE = 0,
    DUMP_STATUS_INIT,
    DUMP_STATUS_READING_PE,
    DUMP_STATUS_DECRYPTING,
    DUMP_STATUS_EXTRACTING,
    DUMP_STATUS_WRITING,
    DUMP_STATUS_SCANNING,       /* continuous Warden module scan    */
    DUMP_STATUS_COMPLETE,
    DUMP_STATUS_FAILED
} DumpStatus;

#pragma pack(push, 8)
typedef struct {
    uint32_t       magic;              /* DINKR_DUMP_MAGIC               */
    uint32_t       client_type;        /* DumpClientType enum            */
    volatile LONG  status;             /* DumpStatus enum                */
    uint32_t       progress_pct;       /* 0-100                          */
    uint32_t       bytes_written;      /* total bytes written to disk    */
    volatile LONG  stop_requested;     /* GUI sets to 1 to stop scanning */
    volatile LONG  modules_found;      /* Warden modules found so far   */
    char           output_path[260];   /* GUI writes, DLL reads          */
    char           status_msg[256];    /* DLL writes progress text       */
    char           error_msg[256];     /* DLL writes on failure          */
} DinkrDumpIPC;
#pragma pack(pop)

/* PID-derived name for the dump shared memory section */
static inline void DinkrDumpIpcName(unsigned long pid, char* out, size_t sz) {
    unsigned int h = (unsigned int)pid ^ 0x5A2E19C3u;
    h *= 2654435761u;
    snprintf(out, sz,
             "Local\\{5A2E19C3-08F1-4C7A-%04X-%08X%04X}",
             (h >> 16) & 0xFFFF, h, (unsigned int)pid & 0xFFFF);
}

/* PID-derived name for the dump DLL confirmation event.
 * GUI checks for this event to verify DllMain actually executed
 * after reflective load + thread hijack. */
static inline void DinkrDumpEvtName(unsigned long pid, char* out, size_t sz) {
    unsigned int h = (unsigned int)pid ^ 0xB7E2C1A9u;
    h *= 2654435761u;
    snprintf(out, sz, "Local\\WkDump_%08X", h);
}

#endif /* DINKR_DUMP_PROTOCOL_H */
