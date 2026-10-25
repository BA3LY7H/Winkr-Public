#pragma once
/* dinkr_internal.h -- shared state across all DLL modules */

#include <windows.h>
#include <timeapi.h>
#include <stdint.h>
#include <string.h>
#include <stdio.h>

#include "dinkr_ipc.h"
#include "dinkr_om.h"
#include "../shared/rva_defs.h"
#include "../shared/wow_guid_format.h"
#include "core/dinkr_scanner.h"

/* --- Core globals (defined in dinkr_payload.c) --- */
extern HMODULE          g_hSelf;
extern volatile BOOL    g_shuttingDown;

/* --- WoW base addresses (defined in dinkr_payload.c, set by worker thread) --- */
extern LPBYTE           g_modLoaderBase;
extern LPBYTE           g_wowBase;
extern size_t           g_wowModuleSize;

/* --- Window state (defined in dinkr_mods.c) --- */
extern HWND             g_gameWindow;
extern DWORD            g_mainThreadId;

/* --- WoW Lua trampoline pointers (defined in dinkr_mods.c, set during mod setup) --- */
typedef int   (__fastcall *luaL_loadbuffer_t)(void* L, const char* buff, size_t sz, const char* name);
typedef int   (__fastcall *lua_pcall_t)(void* L, int nargs, int nresults, int errfunc);
extern lua_pcall_t        s_pPcall;
extern luaL_loadbuffer_t  s_pLoadBuffer;

/* --- Logging --- */
void DebugLog(const char* msg);

/* --- User32 function pointer types (resolved in dinkr_stealth.c) --- */
typedef BOOL    (WINAPI *pfnEnumWindows_t)(WNDENUMPROC, LPARAM);
typedef HHOOK   (WINAPI *pfnSetWindowsHookExA_t)(int, HOOKPROC, HINSTANCE, DWORD);
typedef BOOL    (WINAPI *pfnUnhookWindowsHookEx_t)(HHOOK);
typedef LRESULT (WINAPI *pfnCallNextHookEx_t)(HHOOK, int, WPARAM, LPARAM);
typedef BOOL    (WINAPI *pfnPostMessageA_t)(HWND, UINT, WPARAM, LPARAM);
typedef DWORD   (WINAPI *pfnGetWindowThreadProcessId_t)(HWND, LPDWORD);
typedef int     (WINAPI *pfnGetClassNameA_t)(HWND, LPSTR, int);
typedef BOOL    (WINAPI *pfnIsWindowVisible_t)(HWND);
typedef LONG    (WINAPI *pfnGetWindowLongA_t)(HWND, int);
typedef HWND    (WINAPI *pfnGetForegroundWindow_t)(void);
typedef BOOL    (WINAPI *pfnGetClientRect_t)(HWND, LPRECT);

extern pfnEnumWindows_t              pEnumWindows;
extern pfnSetWindowsHookExA_t        pSetWindowsHookExA;
extern pfnUnhookWindowsHookEx_t      pUnhookWindowsHookEx;
extern pfnCallNextHookEx_t           pCallNextHookEx;
extern pfnPostMessageA_t             pPostMessageA;
extern pfnGetWindowThreadProcessId_t pGetWindowThreadProcessId;
extern pfnGetClassNameA_t            pGetClassNameA;
extern pfnIsWindowVisible_t          pIsWindowVisible;
extern pfnGetWindowLongA_t           pGetWindowLongA;
extern pfnGetForegroundWindow_t      pGetForegroundWindow;
extern pfnGetClientRect_t            pGetClientRect;
