/*
 * gui_worker.h — Per-session background worker thread
 */

#pragma once
#include <windows.h>

/* Shared app-running flag (defined in gui_main.cpp) */
extern volatile LONG g_appRunning;

DWORD WINAPI SessionWorkerThread(LPVOID param);
