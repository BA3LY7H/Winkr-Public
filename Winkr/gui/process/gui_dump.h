/*
 * gui_dump.h — GUI-side binary dump orchestration
 */

#pragma once
#ifndef DINKR_GUI_DUMP_H
#define DINKR_GUI_DUMP_H

#include "gui_external.h"

/* Start a binary dump for the given session. Injects dinkr_dump.dll,
 * polls IPC until DLL finishes or stop is requested.
 * Blocks until complete — call from background thread only. */
bool Ext_DumpProcess(WowSession* s);

/* Signal the dump DLL to stop its continuous Warden scan.
 * Called from the render thread — non-blocking. */
void Ext_RequestDumpStop(WowSession* s);

/* Clean up dump IPC resources (called after dump thread exits). */
void Ext_DumpCleanup(WowSession* s);

#endif /* DINKR_GUI_DUMP_H */
