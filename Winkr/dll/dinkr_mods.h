#pragma once
/* dinkr_mods.h -- mod file loading, hook management, Lua bridge registration */

#include "dinkr_internal.h"

#define WM_LOAD_MODS  (WM_USER + 0x4D4F)

int  ReadModFiles(void);
void FreeModFiles(void);
void FindGameWindowWithFallback(void);
void ExecuteModsOnMainThread(void);
void SetupModLoader(LPBYTE moduleBase);

/* Hook proc and state -- accessible for unhooking from DllMain */
extern HHOOK g_messageHook;

/* Last Lua state -- reset by worker thread on world transitions */
extern void* g_lastLuaState;
