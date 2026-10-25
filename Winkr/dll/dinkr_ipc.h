/*
** dinkr_ipc.h — DLL-side IPC function prototypes
**
** All types (DinkrIPC, DllStatus, OmCacheEntry, etc.) are
** defined in the shared headers so both DLL and GUI agree on layout.
*/

#ifndef DINKR_DLL_IPC_H
#define DINKR_DLL_IPC_H

#include "../shared/ipc_protocol.h"

/* DLL-side IPC API */
BOOL      InitIPC(void);
void      CloseIPC(void);
DinkrIPC* GetIPC(void);
void      IpcLog(const char* prefix, const char* msg);
void      IpcSetStatus(uint32_t status);
BOOL      IpcCheckReloadCmd(void);
BOOL      IpcCheckRefreshCmd(void);

#endif /* DINKR_DLL_IPC_H */