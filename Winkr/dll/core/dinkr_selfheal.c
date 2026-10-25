/* dinkr_selfheal.c -- patch-day live re-derivation of no-signature struct offsets.
 *
 * The offline scorecard (tools/patch_day.py) covers everything with a code signature.
 * The remaining ~78 entries are STRUCT OFFSETS and indirect globals that have NO sig and
 * can only be checked against LIVE memory. This module does exactly that, using value
 * anchors that are build-independent:
 *   - a unit's target/focus field holds the GUID of an ENUMERATED object,
 *   - the camera EYE sits within ~60yd of the player,
 *   - the camera FOV is ~pi/2 radians,
 *   - the view-projection matrix projects the PLAYER to screen-center.
 * It VERIFIES the current hardcoded offsets (PASS/STALE) and, when stale, lists the live
 * candidates -- turning a multi-hour re-RE into "run dinkr_PatchDay(), read the report,
 * paste the offsets." All reads are om_ptr_ok-guarded and bounded (no memory scan).
 */

#include "dinkr_bridge.h"
#include "dinkr_internal.h"
#include "dinkr_ipc.h"
#include "dinkr_om.h"
#include "core/dinkr_scanner.h"
#include "core/dinkr_selfheal.h"
#include "om_types.h"
#include "rva_defs.h"

#include <windows.h>
#include <stdio.h>
#include <stdarg.h>
#include <math.h>

#define PD_REPORT "C:\\projects\\dinkr_patchday.txt"

static void PD_Log(const char* fmt, ...) {
    char line[512];
    va_list ap; va_start(ap, fmt);
    vsnprintf(line, sizeof(line), fmt, ap); va_end(ap);
    FILE* f = fopen(PD_REPORT, "a");
    if (f) { fputs(line, f); fputc('\n', f); fclose(f); }
    DebugLog(line);
}

/* Active player's cgobj + position from the OM (returns 0 if not in-world). */
static uintptr_t pd_player(DinkrIPC* ipc, float* px, float* py, float* pz,
                           uint64_t* slo, uint64_t* shi) {
    uint64_t lo = ipc->active_player_guid_lo, hi = ipc->active_player_guid_hi;
    if (!(lo | hi)) return 0;
    uint32_t n = ipc->om_object_count; if (n > MAX_OM_OBJECTS) n = MAX_OM_OBJECTS;
    for (uint32_t k = 0; k < n; k++)
        if (ipc->objects[k].guid_lo == lo && ipc->objects[k].guid_hi == hi) {
            if (px) { *px = ipc->objects[k].pos_x; *py = ipc->objects[k].pos_y; *pz = ipc->objects[k].pos_z; }
            if (slo) *slo = lo;
            if (shi) *shi = hi;
            return (uintptr_t)ipc->objects[k].cgobj;
        }
    return 0;
}

/* Resolve any GUID -> cgobj from the OM cache (0 if not enumerated). */
static uintptr_t pd_find_cgobj(DinkrIPC* ipc, uint64_t lo, uint64_t hi) {
    if ((lo | hi) == 0) return 0;
    uint32_t n = ipc->om_object_count; if (n > MAX_OM_OBJECTS) n = MAX_OM_OBJECTS;
    for (uint32_t k = 0; k < n; k++)
        if (ipc->objects[k].guid_lo == lo && ipc->objects[k].guid_hi == hi)
            return (uintptr_t)ipc->objects[k].cgobj;
    return 0;
}

/* Does a 16-byte value match some enumerated non-self object's GUID? */
static int pd_is_live_guid(DinkrIPC* ipc, uint64_t vlo, uint64_t vhi,
                           uint64_t self_lo, uint64_t self_hi, int* out_type) {
    if ((vlo | vhi) == 0) return 0;
    if (vlo == self_lo && vhi == self_hi) return 0;
    uint32_t n = ipc->om_object_count; if (n > MAX_OM_OBJECTS) n = MAX_OM_OBJECTS;
    for (uint32_t k = 0; k < n; k++)
        if (ipc->objects[k].guid_lo == vlo && ipc->objects[k].guid_hi == vhi) {
            if (out_type) *out_type = ipc->objects[k].type;
            return 1;
        }
    return 0;
}

void DinkrPatchDayScan(void) {
    DinkrIPC* ipc = GetIPC();
    if (!ipc || !g_modLoaderBase) { DebugLog("[patchday] no ipc / base -- inject first"); return; }
    uintptr_t base = (uintptr_t)g_modLoaderBase;

    { FILE* f = fopen(PD_REPORT, "w"); if (f) { fputs("=== DINKR PATCH-DAY LIVE SCAN ===\n", f); fclose(f); } }
    PD_Log("build=%d  (verify struct offsets vs live memory; paste any STALE lines)", (int)EXPECTED_BUILD);

    float px = 0, py = 0, pz = 0; uint64_t slo = 0, shi = 0;
    uintptr_t pcg = pd_player(ipc, &px, &py, &pz, &slo, &shi);
    if (!pcg || !om_ptr_ok(pcg, 0x2A10)) {
        PD_Log("[patchday] active player cgobj unavailable -- be in-world, then rerun");
        return;
    }
    PD_Log("player cgobj=0x%llX pos=%.1f,%.1f,%.1f", (unsigned long long)pcg, px, py, pz);

    /* ---- target / focus GUID field offsets ---- */
    PD_Log("--- target/focus GUID fields (cgobj offsets holding a live unit's GUID) ---");
    PD_Log("    (set a target + /focus a DIFFERENT mob before scanning to disambiguate)");
    int cur_tgt = 0, cur_foc = 0, ty;
    /* Sweep the WHOLE object, not the first third of it.
     *
     * CGActivePlayer_C is 0x8A88 bytes (om_types.h CGObjectType), and this loop
     * stopped at 0x2A00 -- so a field that moved past that point was invisible
     * and got reported as "STALE or no target set" no matter how many times it
     * was run. On 69547 both 0x1B48 and 0x1968 read all-zero with a target
     * confirmed set via UnitGUID(), so the field is somewhere this range never
     * reached. */
    /* Sweep from the TOP of the object, not 0x800.
     *
     * Starting at 0x800 assumed the field could only have moved upward. On
     * 69547 the target GUID is provably in the OM cache and provably absent
     * from 0x800..0x8A80, so if it is in this object at all it is below 0x800. */
    for (uintptr_t off = 0x8; off <= 0x8A80; off += 8) {
        if (!om_ptr_ok(pcg + off, 16)) continue;
        uint64_t vlo = *(uint64_t*)(pcg + off), vhi = *(uint64_t*)(pcg + off + 8);
        if (pd_is_live_guid(ipc, vlo, vhi, slo, shi, &ty)) {
            const char* tag = (off == CGOBJ_TARGET_LO) ? "  <== CURRENT TARGET"
                            : (off == CGOBJ_FOCUS_LO)  ? "  <== CURRENT FOCUS"  : "";
            PD_Log("    cgobj+0x%X -> live obj type=%d%s", (unsigned)off, ty, tag);
            if (off == CGOBJ_TARGET_LO) cur_tgt = 1;
            if (off == CGOBJ_FOCUS_LO)  cur_foc = 1;
        }
    }
    PD_Log("  CGOBJ_TARGET_LO = 0x%X : %s", (unsigned)CGOBJ_TARGET_LO,
           cur_tgt ? "PASS" : "STALE or no target set -- pick the target's offset above");

    /* When the sweep finds NOTHING the report above is ambiguous three ways:
     * no target set, the field moved outside the swept range, or the target is
     * simply absent from the OM cache. Those need different fixes, and the
     * "STALE or no target set" line cannot tell them apart -- which cost
     * several inconclusive runs on 69547.
     *
     * So dump the evidence rather than the verdict: what the OM actually holds,
     * and what raw bytes sit at the candidate offsets. A GUID visible in the
     * cache but at none of the offsets means the field moved; a GUID at an
     * offset but missing from the cache means the cache is the problem. */
    if (!cur_tgt) {
        /* Does this object contain its OWN GUID? If not, pcg is not pointing at
         * a CGActivePlayer and nothing else read through it means anything --
         * which would explain cgobj+0x1B48 reading as Lua source text. This is
         * the check that should have run before any offset was changed. */
        int self_at = -1;
        for (uintptr_t off = 0x8; off <= 0x8A80; off += 8) {
            if (!om_ptr_ok(pcg + off, 16)) continue;
            if (*(uint64_t*)(pcg + off) == slo && *(uint64_t*)(pcg + off + 8) == shi) {
                self_at = (int)off; break;
            }
        }
        if (self_at >= 0)
            PD_Log("    -- SANITY: object holds its own GUID at +0x%X, so pcg is a real player object",
                   (unsigned)self_at);
        else
            PD_Log("    -- SANITY FAIL: object does NOT contain its own GUID anywhere in 0x8..0x8A80. "
                   "pcg=0x%llX is not a CGActivePlayer -- fix the player resolution before trusting any offset.",
                   (unsigned long long)pcg);

        PD_Log("    -- no match. raw bytes at the candidate offsets:");
        static const uintptr_t cand[] = { 0x1968, 0x1B48, 0x1B60, 0x1BB8 };
        for (unsigned i = 0; i < sizeof(cand)/sizeof(cand[0]); i++) {
            if (!om_ptr_ok(pcg + cand[i], 16)) { PD_Log("       +0x%X : unreadable", (unsigned)cand[i]); continue; }
            PD_Log("       +0x%X : %016llX %016llX", (unsigned)cand[i],
                   (unsigned long long)*(uint64_t*)(pcg + cand[i]),
                   (unsigned long long)*(uint64_t*)(pcg + cand[i] + 8));
        }
        uint32_t n = ipc->om_object_count; if (n > MAX_OM_OBJECTS) n = MAX_OM_OBJECTS;
        PD_Log("    -- OM cache holds %u object(s); their GUIDs:", n);
        /* Print the whole cache, not a 24-entry slice: with 127 objects
         * resident a truncated dump made "the target is not cached" look like a
         * finding when it was only the cap. */
        for (uint32_t k = 0; k < n; k++)
            PD_Log("       [%u] type=%u  %016llX %016llX", k, (unsigned)ipc->objects[k].type,
                   (unsigned long long)ipc->objects[k].guid_lo,
                   (unsigned long long)ipc->objects[k].guid_hi);
        /* The target is in the OM cache and provably NOT in the player object,
         * so it lives in a global. Check the known GUID globals first, then
         * sweep the data region around them -- WoW keeps these clustered, and a
         * global that merely shifted is the likeliest explanation.
         *
         * Scanning the whole 103 MB image for 16-byte patterns would be far too
         * slow; a few MB around the known cluster is instant and covers a
         * plausible move. */
        PD_Log("    -- GUID globals (module base + RVA):");
        struct { uintptr_t rva; const char* name; } gl[] = {
            { RVA_TargetGUID,       "RVA_TargetGUID"       },
            { RVA_FocusGUID,        "RVA_FocusGUID"        },
            { RVA_MouseoverGUID,    "RVA_MouseoverGUID"    },
            { RVA_NpcTargetGUID,    "RVA_NpcTargetGUID"    },
            { RVA_ActivePlayerGUID, "RVA_ActivePlayerGUID" },
        };
        for (unsigned i = 0; i < sizeof(gl)/sizeof(gl[0]); i++) {
            uintptr_t a = base + gl[i].rva;
            if (!om_ptr_ok(a, 16)) { PD_Log("       %-22s +0x%X : unreadable", gl[i].name, (unsigned)gl[i].rva); continue; }
            uint64_t glo = *(uint64_t*)a, ghi = *(uint64_t*)(a + 8);
            int gt = 0;
            int live = pd_is_live_guid(ipc, glo, ghi, slo, shi, &gt);
            PD_Log("       %-22s +0x%X : %016llX %016llX%s", gl[i].name, (unsigned)gl[i].rva,
                   (unsigned long long)glo, (unsigned long long)ghi,
                   live ? "  <== LIVE OBJECT, this is it" : "");
        }

        /* Bounded sweep of the data region around the known cluster. */
        PD_Log("    -- sweeping module data 0x04300000..0x04A00000 for any cached GUID:");
        int found = 0;
        for (uintptr_t r = 0x04300000; r < 0x04A00000 && found < 12; r += 8) {
            uintptr_t a = base + r;
            if (!om_ptr_ok(a, 16)) continue;
            uint64_t vlo = *(uint64_t*)a, vhi = *(uint64_t*)(a + 8);
            if ((vlo | vhi) == 0) continue;
            int t2 = 0;
            if (pd_is_live_guid(ipc, vlo, vhi, slo, shi, &t2)) {
                PD_Log("       base+0x%08X -> live obj type=%d", (unsigned)r, t2);
                found++;
            }
        }
        if (!found) {
            PD_Log("       (nothing there -- sweeping the WHOLE image)");

            /* Full-image sweep. 103 MB at 8-byte steps is 13M positions, and
             * testing each against 127 cached GUIDs linearly would be 1.6
             * billion compares -- far too slow for a synchronous call from Lua.
             *
             * Sort the cached guid_lo values once and binary-search instead:
             * ~7 compares per position, ~90M total, well under a second. Only
             * on a guid_lo hit do we bother reading and checking guid_hi. */
            uint32_t cn = ipc->om_object_count; if (cn > MAX_OM_OBJECTS) cn = MAX_OM_OBJECTS;
            static uint64_t lo_sorted[MAX_OM_OBJECTS];
            uint32_t ln = 0;
            for (uint32_t k = 0; k < cn; k++) {
                uint64_t v = ipc->objects[k].guid_lo;
                if (v == slo || v == 0) continue;
                lo_sorted[ln++] = v;
            }
            for (uint32_t i = 1; i < ln; i++) {          /* insertion sort; ln is ~127 */
                uint64_t key = lo_sorted[i]; int j = (int)i - 1;
                while (j >= 0 && lo_sorted[j] > key) { lo_sorted[j+1] = lo_sorted[j]; j--; }
                lo_sorted[j+1] = key;
            }

            int hits = 0;
            const uintptr_t imgEnd = 0x62F1000;   /* from [scanner] init log */
            for (uintptr_t r = 0x1000; r + 16 < imgEnd && hits < 16; r += 8) {
                uintptr_t a = base + r;
                if (!om_ptr_ok(a, 16)) { r += 0xFF8; continue; }   /* skip unmapped pages */
                uint64_t vlo = *(uint64_t*)a;
                if (!vlo) continue;
                int loI = 0, hiI = (int)ln - 1, got = 0;
                while (loI <= hiI) {
                    int mid = (loI + hiI) >> 1;
                    if (lo_sorted[mid] == vlo) { got = 1; break; }
                    if (lo_sorted[mid] < vlo) loI = mid + 1; else hiI = mid - 1;
                }
                if (!got) continue;
                uint64_t vhi = *(uint64_t*)(a + 8);
                int t3 = 0;
                if (pd_is_live_guid(ipc, vlo, vhi, slo, shi, &t3)) {
                    PD_Log("       base+0x%08X -> live obj type=%d", (unsigned)r, t3);
                    hits++;
                }
            }
            if (!hits)
                PD_Log("       NOT ANYWHERE in the module image -- the target GUID lives on the HEAP "
                       "(a manager object), not in static data. Reaching it needs a pointer chain, "
                       "not an RVA.");
        }
    }
    PD_Log("  CGOBJ_FOCUS_LO  = 0x%X : %s", (unsigned)CGOBJ_FOCUS_LO,
           cur_foc ? "PASS" : "STALE or no focus set -- pick the focus's offset above");

    /* ---- TARGET OBJECT FIELD DUMP -------------------------------------------
     * Why this exists: dead-state detection has no working route on 69109.
     * CGOBJ_DYNAMIC_FLAGS (0x94) reads 0 for every unit, dinkr_SetNPC mints no
     * token, and health is a SECRET VALUE so it can never be matched in memory.
     * The unit block itself has clearly moved -- om_types.h offsets in that
     * region are annotated 68887/67186.
     *
     * Rather than keep guessing offsets from Lua (which can only read a few
     * thousand of them per frame before it stutters), dump the WHOLE target
     * object here, where it costs nothing. Run it once with a LIVE target and
     * once with a CORPSE targeted, then diff the two reports: any offset whose
     * value changes is a candidate for the dead flag, and one of them will be
     * the attackable/selectable bit that clears on death.
     *
     * Non-zero fields only -- a full 0x2A00 dump is mostly padding.
     */
    PD_Log("--- TARGET object non-zero dwords (diff a LIVE target vs a CORPSE) ---");
    {
        uintptr_t tcg = 0;
        if (om_ptr_ok(pcg + CGOBJ_TARGET_LO, 16)) {
            uint64_t tlo = *(uint64_t*)(pcg + CGOBJ_TARGET_LO);
            uint64_t thi = *(uint64_t*)(pcg + CGOBJ_TARGET_LO + 8);
            /* Use the existing lookup rather than walking the cache by hand --
             * it already knows the entry layout and the bounds. */
            const OmCacheEntry* te = om_find_by_guid_lohi(ipc, tlo, thi);
            if (te) tcg = te->cgobj;
        }
        if (!tcg) {
            PD_Log("    no target -- target something and rerun");
        } else {
            PD_Log("    target cgobj=0x%llX", (unsigned long long)tcg);
            int shown = 0;
            for (uintptr_t off = 0x0; off <= 0x2A00; off += 4) {
                if (!om_ptr_ok(tcg + off, 4)) continue;
                uint32_t v = *(uint32_t*)(tcg + off);
                if (v == 0) continue;
                PD_Log("    +0x%04X = 0x%08X", (unsigned)off, v);
                if (++shown > 900) { PD_Log("    ... truncated"); break; }
            }
            PD_Log("    (%d non-zero fields)", shown);
        }
    }

    /* ---- camera chain ---- */
    PD_Log("--- camera / WorldToScreen chain ---");
    uintptr_t pmgr = DinkrGetAddr(SIGID_CAM_MGR); if (!pmgr) pmgr = base + RVA_CAM_MGR;
    PD_Log("  CAM_MGR (recipe/fallback) rva=0x%llX", (unsigned long long)(pmgr - base));
    uintptr_t wf = om_ptr_ok(pmgr, 8) ? *(uintptr_t*)pmgr : 0;
    if (!om_ptr_ok(wf, 0x4C0)) {
        PD_Log("  WorldFrameUI INVALID -- CAM_MGR recipe drifted; re-derive with tools/patch_day.py");
        goto done;
    }
    uintptr_t cam = *(uintptr_t*)(wf + CAM_OFF_CCAMERA);
    PD_Log("  CCamera @ wf+0x%X : %s", (unsigned)CAM_OFF_CCAMERA,
           om_ptr_ok(cam, 0x140) ? "PASS" : "STALE (re-derive CAM_OFF_CCAMERA)");
    if (!om_ptr_ok(cam, 0x140)) goto done;

    int eye_ok = 0;
    for (uintptr_t o = 0; o <= 0x80; o += 4) {
        float ex = *(float*)(cam + o), ey = *(float*)(cam + o + 4), ez = *(float*)(cam + o + 8);
        if (ex != ex || ey != ey || ez != ez) continue;
        float dx = ex - px, dy = ey - py, dz = ez - pz;
        if (dx*dx + dy*dy + dz*dz < 3600.0f) {
            PD_Log("    eye  cand cam+0x%X = %.1f,%.1f,%.1f%s", (unsigned)o, ex, ey, ez,
                   o == CCAM_OFF_EYE ? "  <== CURRENT" : "");
            if (o == CCAM_OFF_EYE) eye_ok = 1;
        }
    }
    PD_Log("  CCAM_OFF_EYE = 0x%X : %s", (unsigned)CCAM_OFF_EYE,
           eye_ok ? "PASS" : "STALE -- pick the eye candidate nearest the player");

    for (uintptr_t o = 0; o <= 0x80; o += 4) {
        float fv = *(float*)(cam + o);
        if (fv > 1.3f && fv < 1.7f)
            PD_Log("    fov  cand cam+0x%X = %.4f%s", (unsigned)o, fv, o == CCAM_OFF_FOV ? "  <== CURRENT" : "");
    }
    PD_Log("  CCAM_OFF_FOV = 0x%X (expect ~1.571)", (unsigned)CCAM_OFF_FOV);

    {
        const float* m = (const float*)(wf + WORLDFRAME_OFF_VIEWPROJ);
        float ex = *(float*)(cam + CCAM_OFF_EYE), ey = *(float*)(cam + CCAM_OFF_EYE + 4), ez = *(float*)(cam + CCAM_OFF_EYE + 8);
        float vx = px - ex, vy = py - ey, vz = pz - ez;
        float cX = m[0]*vx + m[4]*vy + m[8]*vz, cY = m[1]*vx + m[5]*vy + m[9]*vz, cW = m[3]*vx + m[7]*vy + m[11]*vz;
        if (cW > 0.01f) {
            float sx = (cX/cW + 1) * 0.5f, sy = (1 - cY/cW) * 0.5f;
            int ok = (sx > 0.35f && sx < 0.65f && sy > 0.30f && sy < 0.72f);
            PD_Log("  VP matrix wf+0x%X: player -> (%.3f,%.3f) : %s", (unsigned)WORLDFRAME_OFF_VIEWPROJ,
                   sx, sy, ok ? "PASS" : "OFF -- WORLDFRAME_OFF_VIEWPROJ drifted (dump wf+0x300..0x4B0)");
        } else {
            PD_Log("  VP matrix wf+0x%X: player behind camera (cW=%.2f) -- matrix/eye drifted",
                   (unsigned)WORLDFRAME_OFF_VIEWPROJ, cW);
        }
    }
done:
    PD_Log("=== done -> %s. Paste STALE offsets into shared/om_types.h + dll/dinkr_bridge.h, rebuild. ===", PD_REPORT);
}

/* Dump up to 8 of a unit's auras as [spellId:rawFlags@+0xB0] pairs. If oneShot
 * is non-NULL and already set, skips (and sets it after logging). */
static void aura_dump(uintptr_t cgobj, const char* prefix, int* oneShot) {
    if (oneShot && *oneShot) return;
    if (!om_ptr_ok(cgobj + CGOBJ_AURA_ARRAY_PTR, 12)) return;
    uintptr_t arr = *(uintptr_t*)(cgobj + CGOBJ_AURA_ARRAY_PTR);
    uint32_t  cnt = *(uint32_t*) (cgobj + CGOBJ_AURA_COUNT);
    if (!arr || !cnt || cnt > 255) return;
    int nr = (cnt > 20) ? 20 : (int)cnt;
    if (!om_ptr_ok(arr, (size_t)nr * AURA_STRUCT_SIZE)) return;
    char tb[640]; int p = snprintf(tb, sizeof(tb), "%scnt=%u", prefix, (unsigned)cnt);
    for (int i = 0; i < nr && p < (int)sizeof(tb) - 24; i++) {
        uintptr_t a = arr + (uintptr_t)i * AURA_STRUCT_SIZE;
        uint32_t sid = *(uint32_t*)(a + AURA_OFF_SPELL_ID);
        uint16_t fl  = *(uint16_t*)(a + AURA_OFF_FLAGS);
        p += snprintf(tb + p, sizeof(tb) - p, " [%u:0x%X]", (unsigned)sid, (unsigned)fl);
    }
    DebugLog(tb);
    if (oneShot) *oneShot = 1;
}

/* Hash of a unit's aura spellId set. The array is sparse (empty 0-slots), so a
 * seal can reuse a slot without changing the count -- hashing every id catches
 * it. Used to log a dump only when the set actually CHANGES. */
static uint32_t aura_hash(uintptr_t cgobj) {
    if (!om_ptr_ok(cgobj + CGOBJ_AURA_ARRAY_PTR, 12)) return 0;
    uintptr_t arr = *(uintptr_t*)(cgobj + CGOBJ_AURA_ARRAY_PTR);
    uint32_t  cnt = *(uint32_t*) (cgobj + CGOBJ_AURA_COUNT);
    uint32_t  h   = cnt + 1u;
    if (!arr || !cnt || cnt > 255) return h;
    int nr = (cnt > 20) ? 20 : (int)cnt;
    if (!om_ptr_ok(arr, (size_t)nr * AURA_STRUCT_SIZE)) return h;
    for (int i = 0; i < nr; i++)
        h = h * 31u + *(uint32_t*)(arr + (uintptr_t)i * AURA_STRUCT_SIZE + AURA_OFF_SPELL_ID);
    return h;
}

void DinkrSelfHealCheck(void) {
    DinkrIPC* ipc = GetIPC();
    if (!ipc || !g_modLoaderBase) return;
    uintptr_t base = (uintptr_t)g_modLoaderBase;
    float px = 0, py = 0, pz = 0; uint64_t slo = 0, shi = 0;
    uintptr_t pcg = pd_player(ipc, &px, &py, &pz, &slo, &shi);
    if (!pcg || !om_ptr_ok(pcg, CGOBJ_TARGET_LO + 16)) return;

    /* camera: does the current chain resolve to an eye near the player? */
    int cam_ok = 0;
    uintptr_t pmgr = DinkrGetAddr(SIGID_CAM_MGR); if (!pmgr) pmgr = base + RVA_CAM_MGR;
    uintptr_t wf = om_ptr_ok(pmgr, 8) ? *(uintptr_t*)pmgr : 0;
    if (om_ptr_ok(wf, 0x4C0)) {
        uintptr_t cam = *(uintptr_t*)(wf + CAM_OFF_CCAMERA);
        if (om_ptr_ok(cam, CCAM_OFF_EYE + 12)) {
            float ex = *(float*)(cam + CCAM_OFF_EYE), ey = *(float*)(cam + CCAM_OFF_EYE + 4), ez = *(float*)(cam + CCAM_OFF_EYE + 8);
            float dx = ex - px, dy = ey - py, dz = ez - pz;
            if (ex == ex && dx*dx + dy*dy + dz*dz < 10000.0f) cam_ok = 1;
        }
    }
    /* target field: holds a live GUID? (only meaningful with a target set; treat 0 as "unknown") */
    int tgt_state = 0; /* 0=empty/unknown, 1=live */
    if (om_ptr_ok(pcg + CGOBJ_TARGET_LO, 16)) {
        uint64_t vlo = *(uint64_t*)(pcg + CGOBJ_TARGET_LO), vhi = *(uint64_t*)(pcg + CGOBJ_TARGET_LO + 8);
        if (pd_is_live_guid(ipc, vlo, vhi, slo, shi, NULL)) tgt_state = 1;
    }
    /* status line: log only when it CHANGES, so a healthy session stays quiet */
    static int s_lastCam = -1, s_lastTgt = -1;
    if (cam_ok != s_lastCam || tgt_state != s_lastTgt) {
        s_lastCam = cam_ok; s_lastTgt = tgt_state;
        char b[192];
        snprintf(b, sizeof(b), "[selfheal] camera=%s target-field=%s%s",
                 cam_ok ? "OK" : "STALE",
                 tgt_state ? "OK" : "empty(no-target?)",
                 cam_ok ? "" : "  -- run /run dinkr_PatchDay() to re-derive");
        DebugLog(b);
    }

    /* AURA PROBE -- change-triggered (dumps only when a unit's aura SET changes,
     * so it never spams). PLAYER = reference for the HELPFUL bit (buff flags carry
     * 0x0300). TARGET = HARMFUL validation: Judgement a mob and its debuff appears;
     * its +0xB0 flags reveal the real harmful bit (expect & 0x0010 set and
     * & 0x0300 clear). Dumps [spellId:rawFlags] pairs. */
    static uint32_t s_meHash = 0xFFFFFFFFu, s_tgtHash = 0xFFFFFFFFu;
    uint32_t mh = aura_hash(pcg);
    if (mh != s_meHash) { s_meHash = mh; aura_dump(pcg, "[aura-me] ", NULL); }

    uintptr_t tcg = 0;
    if (om_ptr_ok(pcg + CGOBJ_TARGET_LO, 16)) {
        uint64_t tlo = *(uint64_t*)(pcg + CGOBJ_TARGET_LO);
        uint64_t thi = *(uint64_t*)(pcg + CGOBJ_TARGET_LO + 8);
        tcg = pd_find_cgobj(ipc, tlo, thi);
    }
    if (tcg) {
        uint32_t th = aura_hash(tcg);
        if (th != s_tgtHash) { s_tgtHash = th; aura_dump(tcg, "[aura-tgt] ", NULL); }
    } else {
        s_tgtHash = 0xFFFFFFFFu;   /* no target -> re-dump on the next one */
    }
}

int __fastcall dinkr_PatchDay_lua(void* L) {
    DinkrPatchDayScan();
    s_pPushstring(L, "dinkr patch-day scan -> C:\\projects\\dinkr_patchday.txt");
    return 1;
}
