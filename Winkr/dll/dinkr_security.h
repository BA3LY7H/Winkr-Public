#pragma once
/* dinkr_security.h -- in-process patching and security bypass */

#include "dinkr_internal.h"

BOOL PatchBytes(LPBYTE addr, const BYTE* newBytes, SIZE_T count, const char* label);
BOOL ZeroTaintRoot(LPBYTE base);
BOOL EnsurePrecallPatched(LPBYTE base);
int  ApplySecurityPatches(LPBYTE base);
