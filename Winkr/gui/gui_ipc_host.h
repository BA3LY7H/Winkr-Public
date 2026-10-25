/*
 * gui_ipc_host.h — GUI-side IPC host (per-session shared memory)
 */

#pragma once
#ifndef DINKR_GUI_IPC_HOST_H
#define DINKR_GUI_IPC_HOST_H

#include "../shared/ipc_protocol.h"

struct WowSession;  /* forward */

/* Per-session IPC — creates/destroys shared memory per PID */
bool  IpcHost_CreateForSession(WowSession* s);
void  IpcHost_DestroyForSession(WowSession* s);

/* Log to a specific session's IPC + file */
void  IpcHost_LogSession(WowSession* s, const char* prefix, const char* msg);

/* Global log — file only (no IPC), for pre-session or global messages */
void  IpcHost_Log(const char* prefix, const char* msg);

/* Signal DLL to reload mods */
void  IpcHost_SignalReload(DinkrIPC* ipc);

#endif /* DINKR_GUI_IPC_HOST_H */
