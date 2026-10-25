/*
 * gui_crash.h — Crash handler for the DINKR GUI
 */

#pragma once
#include <windows.h>

LONG WINAPI CrashHandler(EXCEPTION_POINTERS* ep);
