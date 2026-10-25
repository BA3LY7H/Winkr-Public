/*
 * ipc_protocol.h — IPC shared memory protocol between dinkr.dll and dinkr_gui.exe
 *
 * The DLL maps a named shared memory section and populates it.
 * The GUI opens the same section read-only (mostly) and renders the data.
 * All shared fields use interlocked / single-writer access.
 */

#pragma once
#ifndef DINKR_IPC_PROTOCOL_H
#define DINKR_IPC_PROTOCOL_H

#include <stdint.h>
#include <windows.h>
#include "om_types.h"

#define DINKR_IPC_MAGIC   0x574B5200  /* "WKR\0" */
#define DINKR_LOG_SIZE    16384

/* ------------------------------------------------------------------ */
/*  Obfuscated IPC / event names — GUID-style, derived from PID       */
/*  Both DLL and GUI compute the same name for a given PID.           */
/* ------------------------------------------------------------------ */

#include <stdio.h>

static inline void DinkrIpcName(unsigned long pid, char* out, size_t sz) {
    unsigned int h = (unsigned int)pid ^ 0x8A3F21E7u;
    h *= 2654435761u; /* Knuth multiplicative hash */
    snprintf(out, sz,
             "Local\\{8A3F21E7-04D2-4B8A-%04X-%08X%04X}",
             (h >> 16) & 0xFFFF, h, (unsigned int)pid & 0xFFFF);
}

static inline void DinkrEvtName(unsigned long pid, char* out, size_t sz) {
    unsigned int h = (unsigned int)pid ^ 0x7E12F3A8u;
    h *= 2654435761u;
    snprintf(out, sz,
             "Local\\{7E12F3A8-1C9D-4A6E-%04X-%08X%04X}",
             (h >> 16) & 0xFFFF, h, (unsigned int)pid & 0xFFFF);
}


/* ------------------------------------------------------------------ */
/*  DLL lifecycle states                                              */
/* ------------------------------------------------------------------ */

typedef enum {
    DLL_STATUS_IDLE = 0,
    DLL_STATUS_ATTACHED,
    DLL_STATUS_MOD_LOADING,
    DLL_STATUS_READY,
    DLL_STATUS_ERROR,
    DLL_STATUS_DETACHED
} DllStatus;

/* ------------------------------------------------------------------ */
/*  Main IPC structure (lives in shared memory)                       */
/* ------------------------------------------------------------------ */

#pragma pack(push, 8)
typedef struct {
    /* Header */
    uint32_t       _reserved_lock;              /* reserved (was spinlock)    */
    uint32_t       magic;                   /* DINKR_IPC_MAGIC            */
    uint32_t       version;                 /* protocol version (3)       */

    /* DLL state */
    uint32_t       dll_status;              /* DllStatus enum             */
    uint32_t       build_number;            /* detected WoW build         */
    uint32_t       mod_count;               /* mods loaded                */
    uint32_t       reload_count;            /* /reload counter            */

    /* Object Manager */
    uint32_t       om_object_count;         /* objects in cache           */
    uint32_t       om_update_tick;          /* increments each OM refresh */
    volatile uint32_t om_enum_seq;          /* seqlock: odd=writing, even=stable */
    volatile uint32_t om_guid_format_tick;  /* DLL sets = om_update_tick after GUID reformat */
    uint64_t       active_player_guid_lo;
    uint64_t       active_player_guid_hi;
    uint64_t       target_guid_lo;
    uint64_t       target_guid_hi;
    uint64_t       focus_guid_lo;
    uint64_t       focus_guid_hi;
    uint64_t       mouseover_guid_lo;
    uint64_t       mouseover_guid_hi;

    /* Error / log */
    char           last_error[256];

    /* Rolling log buffer (ring buffer) */
    volatile LONG  log_write_pos;           /* next write offset          */
    char           log_buffer[DINKR_LOG_SIZE];

    /* Object Manager cache snapshot */
    OmCacheEntry   objects[MAX_OM_OBJECTS];

    /* GUI → DLL synchronization */
    volatile LONG  gui_om_ready;            /* GUI sets to 1 when first OM snapshot done */

    /* Additional data populated by GUI */
    uint32_t       map_id;                  /* from g_pZoneMapContext+0x20 */
    uint32_t       _pad_map;

    /* DLL → GUI: process info (DLL discovers these, GUI may need them) */
    uint64_t       wow_base_address;        /* DLL writes at init */
    uint64_t       game_window_handle;      /* HWND as uint64 */
    uint32_t       main_thread_id;          /* game's main thread */
    uint32_t       _pad3;

    /* Lua state monitoring (DLL writes, GUI reads for reload detection) */
    uint64_t       dll_lua_state;           /* current g_LuaState pointer */
    uint32_t       dll_lua_create_count;    /* g_LuaStateCreateCount copy */
    uint32_t       _pad4;

    /* Commands from GUI -> DLL */
    volatile LONG  cmd_reload_mods;         /* set to 1 to trigger reload */
    volatile LONG  cmd_refresh_om;          /* set to 1 to force OM refresh */

} DinkrIPC;
#pragma pack(pop)

/* Compile-time layout validation: catch struct drift early */
#ifdef __cplusplus
static_assert(sizeof(DinkrIPC) < 8 * 1024 * 1024, "DinkrIPC grew past 8MB");
#else
_Static_assert(sizeof(DinkrIPC) < 8 * 1024 * 1024, "DinkrIPC grew past 8MB");
#endif

#endif /* DINKR_IPC_PROTOCOL_H */
