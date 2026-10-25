/* dinkr_selfheal.h -- patch-day live re-derivation of no-signature struct offsets. */
#pragma once
#ifndef DINKR_SELFHEAL_H
#define DINKR_SELFHEAL_H

/* Full live scan: verifies/derives target/focus GUID + camera struct offsets against
 * live memory and writes a paste-ready report to C:\projects\dinkr_patchday.txt.
 * Trigger via the dinkr_PatchDay() Lua bridge (be in-world with a target set). */
void DinkrPatchDayScan(void);

/* Lightweight one-shot passive check (call once after OM is populated). Logs a single
 * [selfheal] summary line to the debug ring; if anything is STALE it says so + hints
 * to run dinkr_PatchDay(). Safe/cheap. */
void DinkrSelfHealCheck(void);

/* Lua bridge: runs DinkrPatchDayScan, returns the report path string. */
int __fastcall dinkr_PatchDay_lua(void* L);

#endif
