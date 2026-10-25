#pragma once
/*
 * dinkr_scanner.h - Pattern-scan / RVA resolver API.
 *
 * Call DinkrResolveAllAddrs() once after g_wowBase and g_wowModuleSize
 * are populated (early in DumpWorkerThread).  After that, DinkrGetAddr()
 * is safe to call from any context.
 *
 * Each resolved address either comes from a successful unique pattern
 * scan across all readable committed image pages, or from the hardcoded RVA
 * fallback.  Either way the address is guaranteed valid (base + RVA) in
 * the fallback path.  The DLL log records the source so stale RVAs are
 * visible the moment they diverge from their pattern.
 *
 */

#include <windows.h>
#include <stdint.h>
#include "sig_defs.h"

/* ------------------------------------------------------------------
 * Signature IDs - same order as DINKR_SIG_TABLE and rva_defs.h address RVAs.
 * ------------------------------------------------------------------ */
typedef enum {
#define _SIG_ENUM(name, skip, off, pat, msk) SIGID_##name,
    DINKR_SIG_TABLE(_SIG_ENUM)
#undef _SIG_ENUM
    SIGID_COUNT
} DinkrSigID;

/* Compatibility alias for the old all-caps spelling. */
#define SIGID_COMBATLOG_PUSH_EVENT_ARGS SIGID_CombatLog_PushEventArgs

/*
 * DinkrResolveAllAddrs - scan the WoW module image and resolve every
 * signature in sig_defs.h.  Results are cached in an internal array.
 *
 *   base        = PEB ImageBaseAddress
 *   image_size  = SizeOfImage from NT headers (0 = read from PE headers
 *                 directly; safe fallback caps at 512 MiB)
 */
void DinkrResolveAllAddrs(LPBYTE base, size_t image_size);

/*
 * DinkrGetAddr - retrieve the resolved VA for a signature ID.
 *
 * Returns 0 only if DinkrResolveAllAddrs was never called (startup bug).
 * Otherwise always returns base + rva (fallback or scanned).
 */
uintptr_t DinkrGetAddr(DinkrSigID id);
