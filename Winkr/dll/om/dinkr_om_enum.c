/* dinkr_om_enum.c -- DLL-side OM enumeration */

#include "dinkr_om_enum.h"
#include "core/dinkr_selfheal.h"
#include <stddef.h>

/* ECS / OM field offset definitions (build 67186 — may need update for 68453) */
#define ARCH_PTR_OFF               0x08   /* ptr to archetype */
#define ARCH_CGOBJ_OFF_FIELD       0x38   /* cgobj offset in archetype */
#define ARCH_POS_OFF_FIELD         0x34   /* pos offset in archetype */

#define OM_TBL_OFF_ENTRIES         0x08   /* entry ptr in OM table */
#define OM_TBL_OFF_COUNT           0x10   /* count in OM table */
#define OM_ENTRY_OFF_STATUS        0x00   /* status at entry start */
#define OM_ENTRY_OFF_SLOT          0x08   /* entity ptr in entry */
#define OM_ENTRY_STRIDE            0x10   /* 16 bytes per entry */

#define POS_OFF_X                  0x84   /* position x in pos data */
#define POS_OFF_Y                  0x88   /* position y */
#define POS_OFF_Z                  0x8C   /* position z */
#define POS_OFF_FACING             0x50   /* facing in pos data */

#define CGOBJ_OFF_TYPE_BYTE        0x24   /* = CGOBJ_TYPE_BYTE */
#define CGOBJ_OFF_GUID_LO_UNIT     0x10   /* = CGOBJ_GUID_LO */
#define CGOBJ_OFF_GUID_HI_UNIT     0x18   /* = CGOBJ_GUID_HI */
#define CGOBJ_OFF_GUID_LO_GAMEOBJECT 0x30 /* GUID lo for game objects */
#define CGOBJ_OFF_GUID_HI_GAMEOBJECT 0x38 /* GUID hi for game objects */
#define CGOBJ_OFF_FLAGS            0x94   /* dynamic flags byte */
#define OM_ENTRY_STATUS_FREE_MASK  0x3FFFFFFF  /* mask for free-tombstone check */
#define OM_ENTRY_STATUS_FREE_VAL   0x3FFFFFFF  /* low 31 bits all 1 = free slot */

/* ========================================================================
** DLL_EnumerateOM - enumerate entities from inside the process
** 67088 ECS path:
**   entry(+8) -> entity
**   entity+0x08 -> archetype
**   archetype+0x38 -> cgobj_off; cgobj = *(entity + cgobj_off)
**   archetype+0x34 -> pos_off; pos = entity + pos_off (inline fragment)
** ======================================================================== */

#define DINKR_OM_VERBOSE_LOG 1
/* One-build diagnostic: scan the active-player cgobj for any field holding an
 * ENUMERATED object's GUID (dinkr's own format -> no /run format mismatch). Reveals
 * the target/focus GUID field offset. Throttled ~1.5s; logs to dinkr_dll_debug.txt.
 * Set to 0 (and rebuild) once RVA_ offsets are pinned. */
#define DINKR_DIAG_TGT 0   /* done: target=cgobj+0x1B48, focus=cgobj+0x1BB8 */
/* SAFE camera struct dump: the chain is confirmed (CAM_MGR=0x442C958 -> +0x4B0 = CCamera),
 * so this reads ONLY those two structs at fixed, guarded offsets (no memory scan) to reveal
 * eye/lookat/fov (in CCamera) and viewport/view-proj matrix (in WorldFrameUI). One-shot. */
#define DINKR_DIAG_CAM 0   /* done: eye=cam+0x10, fov=cam+0x40, VP matrix=wf+0x388, origin=eye */
/* W2S self-test (done: bridge computes sx=0.500,sy=0.553; framework env/dinkr.lua scales to px). */
#define DINKR_DIAG_W2S 0
#define RVA_CAM_MGR_68887 0x0442C958   /* WorldFrameUI singleton (319 refs; disasm-confirmed [+0x4B0]=CCamera) */

static inline int om_should_track_type(uint8_t type) {
    switch (type) {
        case CGTYPE_UNIT:
        case CGTYPE_PLAYER:
        case CGTYPE_ACTIVE_PLAYER:
        case CGTYPE_GAMEOBJECT:
        case CGTYPE_DYNAMIC_OBJ:
        case CGTYPE_CORPSE:
        case CGTYPE_AREA_TRIGGER:
            return 1;
        default:
            return 0;
    }
}

static inline void om_fill_guid_string(OmCacheEntry* e) {
    if (!e) return;
    if ((e->guid_lo | e->guid_hi) == 0) {
        e->guid_str[0] = '\0';
        return;
    }
    int w = WowGuid_Format(e->guid_hi, e->guid_lo, e->guid_str, sizeof(e->guid_str));
    if (w <= 0 || w >= (int)sizeof(e->guid_str)) {
        snprintf(e->guid_str, sizeof(e->guid_str), "Unknown-0x%016llX%016llX",
                 (unsigned long long)e->guid_hi, (unsigned long long)e->guid_lo);
    }
}

static inline void om_fill_guid_raw(uint64_t hi, uint64_t lo, char* out, size_t out_sz) {
    if (!out || out_sz == 0) return;
    if ((hi | lo) == 0) {
        out[0] = '\0';
        return;
    }
    int w = WowGuid_Format(hi, lo, out, (int)out_sz);
    if (w <= 0 || w >= (int)out_sz) {
        snprintf(out, out_sz, "Unknown-0x%016llX%016llX",
                 (unsigned long long)hi, (unsigned long long)lo);
    }
}

static void DLL_EnumerateOM_Inner(LPBYTE base, DinkrIPC* ipc);

void DLL_EnumerateOM(LPBYTE base) {
    DinkrIPC* ipc = GetIPC();
    if (!ipc) return;

    /* Quick sanity: re-check in-world flag right before enumeration.
     * Disabled for build 68453 — g_GameStateFlags RVA is stale.
     * TODO: re-enable once the correct RVA is found. */
    //volatile uint16_t* pFlags = (volatile uint16_t*)(base + RVA_g_GameStateFlags);
    //uint16_t flags = *pFlags;
    //if (!(flags & 0x200)) {
    //    if (ipc->om_object_count > 0) {
    //        ipc->om_object_count = 0;
    //        ipc->om_update_tick++;
    //    }
    //    return;
    //}

    DLL_EnumerateOM_Inner(base, ipc);
}

static void DLL_EnumerateOM_Inner(LPBYTE base, DinkrIPC* ipc) {

    static DWORD s_lastLog = 0;
    DWORD now = GetTickCount();
#if DINKR_OM_VERBOSE_LOG
    int doLog = (now - s_lastLog >= 10000);  /* Log every 10s */
    if (doLog) s_lastLog = now;
#else
    int doLog = 0;
    (void)now;
    (void)s_lastLog;
#endif

    /* Signal readers: enumeration in progress (odd = writing) */
    InterlockedIncrement((volatile LONG*)&ipc->om_enum_seq);
    MemoryBarrier();

    /* GUID globals. 68887: ActivePlayer/Target/Focus are NO LONGER raw globals.
     *  - ActivePlayer: resolved below by pointer identity against g_activePlayerUnit
     *    (the live active-player object ptr) during the walk, which backfills the GUID.
     *  - Target/Focus: object-relative / UnitToken on 68887 (old RVAs read 0). TODO.
     *  - Mouseover: still a raw global (re-derived 0x49629A0). */
    uintptr_t activePlayerObj = 0;
    {
        uintptr_t pAP = DinkrGetAddr(SIGID_g_activePlayerUnit);
        if (pAP && om_ptr_ok(pAP, 8)) activePlayerObj = *(uintptr_t*)pAP;
        if (activePlayerObj && !om_ptr_ok(activePlayerObj, 0x40)) activePlayerObj = 0;
    }
    /* Do NOT zero active_player_guid here. The GUI reads it live @~60fps to compute
     * every unit's distance; catching the transient 0 between this reset and the
     * mid-walk backfill made every distance cell flicker to "?". Accumulate into
     * locals and commit once after the walk, preserving the last-known GUID across a
     * transient miss (if the player object truly leaves, FindActivePlayer simply
     * won't match it -> no stale distance). */
    uint64_t found_ap_lo = 0, found_ap_hi = 0;
    ipc->target_guid_lo        = 0;   /* TODO 68887: object-relative UnitToken resolve */
    ipc->target_guid_hi        = 0;
    ipc->focus_guid_lo         = 0;
    ipc->focus_guid_hi         = 0;
    ipc->mouseover_guid_lo     = *(uint64_t*)(base + RVA_MouseoverGUID);
    ipc->mouseover_guid_hi     = *(uint64_t*)(base + RVA_MouseoverGUID + 8);

    int cached = 0;

    /* === 67088 OM walk (ECS)
     *
     * The live OM is a single flat array reachable at:
     *   table   = *(uintptr_t*)(base + RVA_g_pRealObjectMgr)
     *   entries = *(OmEntry**)(table + 0x08)
     *   count   = *(uint64_t*)(table + 0x10)
     *
     * Each OmEntry is 16 bytes: { uint32 status; uint32 _gen; uintptr_t entity }.
     * Status: high bit set = ACTIVE; (status & 0x3FFFFFFF) == 0x3FFFFFFF = FREE.
     *
     * Entity expansion:
     *   archetype = *(entity + ARCH_PTR_OFF)
     *   cgobj_off = *(int32*)(archetype + ARCH_CGOBJ_OFF_FIELD)
     *   cgobj     = *(entity + cgobj_off)
     *   guid      = [cgobj + 0x10/0x18], type=[cgobj+0x24]
     *   pos_off   = *(int32*)(archetype + ARCH_POS_OFF_FIELD)
     *   pos       = entity + pos_off (inline); xyz=[+0x84/+0x88/+0x8C], facing=[+0x50]
     */
    /* Self-healing: resolve the OM manager global via the scanner (RIP-relative
     * recipe -> auto-updates on a build bump), falling back to the hardcoded RVA. */
    uintptr_t pMgr = DinkrGetAddr(SIGID_g_pRealObjectMgr);
    uintptr_t table = pMgr ? *(uintptr_t*)pMgr : *(uintptr_t*)(base + RVA_g_pRealObjectMgr);
    if (!om_ptr_ok(table, 0x20)) {
        ipc->om_object_count = 0;
        MemoryBarrier();
        InterlockedIncrement((volatile LONG*)&ipc->om_enum_seq);
        ipc->om_update_tick++;
        return;
    }

    uintptr_t entries = *(uintptr_t*)(table + OM_TBL_OFF_ENTRIES);
    uint64_t  count   = *(uint64_t*)(table + OM_TBL_OFF_COUNT);

    if (!om_ptr_ok(entries, OM_ENTRY_STRIDE) || count == 0 || count > 200000) {
        ipc->om_object_count = 0;
        MemoryBarrier();
        InterlockedIncrement((volatile LONG*)&ipc->om_enum_seq);
        ipc->om_update_tick++;
        return;
    }

    if (doLog) {
        char dbg[160];
        snprintf(dbg, sizeof(dbg),
            "[dll-om] OM table=0x%llX entries=0x%llX count=%llu",
            (uint64_t)table, (uint64_t)entries, (unsigned long long)count);
        DebugLog(dbg);
    }

    /* Per-stage rejection counters for diagnostics */
    int rej_status_free = 0, rej_status_inactive = 0, rej_slot = 0;
    int rej_arch = 0, rej_arch_off = 0;
    int rej_cgobj = 0, rej_class = 0, rej_guid = 0;

    for (uint64_t i = 0; i < count && cached < MAX_OM_OBJECTS; i++) {
        uint8_t* ep = (uint8_t*)(entries + i * OM_ENTRY_STRIDE);
        uint32_t status = *(uint32_t*)(ep + OM_ENTRY_OFF_STATUS);

        /* === Canonical live test, verbatim from ObjectMgr__DumpListStatus
         *     (sub_7FF6405BF6C0, decompile line 0x7FF6405BF731):
         *       v9 && (status & 0x3FFFFFFF) != 0x3FFFFFFF && (int32)status < 0
         *
         *   slot != NULL                         (entry+8 is the slot pointer)
         *   (status & 0x3FFFFFFF) != 0x3FFFFFFF   (not the free-tombstone)
         *   bit 31 of status set                  ((int32)status < 0 == ACTIVE)
         *
         *   NOTE: the engine's own iterator does NOT vtable-check the cgobj;
         *   it just reads the classifier dwords. Trust the live test + slot. */
        if ((status & OM_ENTRY_STATUS_FREE_MASK) == OM_ENTRY_STATUS_FREE_VAL) {
            rej_status_free++;
            continue;
        }
        if ((int32_t)status >= 0) {
            rej_status_inactive++;
            continue;
        }

        uintptr_t entity = *(uintptr_t*)(ep + OM_ENTRY_OFF_SLOT);
        if (!om_ptr_ok(entity, 0x40)) { rej_slot++; continue; }

        uintptr_t archetype = *(uintptr_t*)(entity + ARCH_PTR_OFF);
        if (!om_ptr_ok(archetype, ARCH_CGOBJ_OFF_FIELD + 4)) { rej_arch++; continue; }

        int32_t cgobj_off = *(int32_t*)(archetype + ARCH_CGOBJ_OFF_FIELD);
        if (cgobj_off < 0 || cgobj_off > 0x10000) { rej_arch_off++; continue; }

        uintptr_t cgobj = *(uintptr_t*)(entity + cgobj_off);
        if (!om_ptr_ok(cgobj, CGOBJ_OFF_TYPE_BYTE + 1)) { rej_cgobj++; continue; }
        uint8_t type = *(uint8_t*)(cgobj + CGOBJ_OFF_TYPE_BYTE);

        uint32_t guid_lo_off = CGOBJ_OFF_GUID_LO_UNIT;
        uint32_t guid_hi_off = CGOBJ_OFF_GUID_HI_UNIT;
        if (type == CGTYPE_GAMEOBJECT) {
            guid_lo_off = CGOBJ_OFF_GUID_LO_GAMEOBJECT;
            guid_hi_off = CGOBJ_OFF_GUID_HI_GAMEOBJECT;
        }
        if (!om_ptr_ok(cgobj, guid_hi_off + 8)) { rej_cgobj++; continue; }

        uint64_t guid_lo = *(uint64_t*)(cgobj + guid_lo_off);
        uint64_t guid_hi = *(uint64_t*)(cgobj + guid_hi_off);
        if ((guid_lo | guid_hi) == 0) { rej_guid++; continue; }

        /* Active-player detection (68887: no raw ActivePlayerGUID global). The OM
         * natively types the active player as CGTYPE_ACTIVE_PLAYER (7); pointer
         * identity against g_activePlayerUnit is a fallback. Backfill
         * active_player_guid from the matched object so distance / self-reference /
         * dinkr_IsPlayerGuid all work. */
        if (type == CGTYPE_ACTIVE_PLAYER ||
            (activePlayerObj && (cgobj == activePlayerObj || entity == activePlayerObj))) {
            type = CGTYPE_ACTIVE_PLAYER;
            found_ap_lo = guid_lo;
            found_ap_hi = guid_hi;
        }
        if (type >= CGTYPE_MAX || !om_should_track_type(type)) { rej_class++; continue; }

        float px = 0.0f, py = 0.0f, pz = 0.0f, facing = 0.0f;
        int32_t pos_off = *(int32_t*)(archetype + ARCH_POS_OFF_FIELD);
        if (pos_off >= 0 && pos_off < 0x10000) {
            uintptr_t pos = entity + (uintptr_t)pos_off;
            if (om_ptr_ok(pos, 0x90)) {
                px = *(float*)(pos + POS_OFF_X);
                py = *(float*)(pos + POS_OFF_Y);
                pz = *(float*)(pos + POS_OFF_Z);
                facing = *(float*)(pos + POS_OFF_FACING);
            }
        }

        OmCacheEntry* e = &ipc->objects[cached];
        uint64_t prev_guid_lo = e->guid_lo;
        uint64_t prev_guid_hi = e->guid_hi;

        e->cgobj  = cgobj;
        e->entity = (uint64_t)entity;
        e->type   = type;
        e->guid_lo = guid_lo;
        e->guid_hi = guid_hi;
        uint32_t state_flags = *(uint32_t*)(cgobj + CGOBJ_OFF_FLAGS);
        e->dynamic_flags = state_flags;
        if ((state_flags & 1u) != 0)
            e->dynamic_flags |= 1u; /* propagate dead flag */
        e->npc_id = 0;
        e->pos_x = px;
        e->pos_y = py;
        e->pos_z = pz;
        e->facing = facing;
        e->unit_flags = 0; e->unit_flags2 = 0; e->movement_flags = 0;
        e->combat_reach = 0; e->bounding_radius = 0; e->height = 0;
        e->casting_spell_id = 0; e->channeling_spell_id = 0;
        e->cast_target_lo = 0; e->cast_target_hi = 0;
        e->casting_spell_name[0] = '\0';
        e->channeling_spell_name[0] = '\0';
        /* Unit's current target GUID (68887: cgobj+0x1B48). Guarded per object. */
        if (om_ptr_ok(cgobj + CGOBJ_TARGET_LO, 16)) {
            e->target_guid_lo = *(uint64_t*)(cgobj + CGOBJ_TARGET_LO);
            e->target_guid_hi = *(uint64_t*)(cgobj + CGOBJ_TARGET_HI);
        } else { e->target_guid_lo = 0; e->target_guid_hi = 0; }
        e->summoned_by_lo = 0; e->summoned_by_hi = 0;
        e->created_by_lo = 0; e->created_by_hi = 0;
        e->at_caster_lo = 0; e->at_caster_hi = 0;
        e->at_spell_id = 0; e->at_duration_ms = 0;
        e->at_create_props_id = 0; e->at_client_flags = 0;
        e->at_area_trigger_id = 0; e->at_scale_curve_id = 0;
        e->at_shape_type = 0; e->at_radius = 0;
        e->at_caster_str[0] = '\0';
        if (prev_guid_lo != guid_lo || prev_guid_hi != guid_hi) {
            e->guid_str[0] = '\0';
            e->target_guid_str[0] = '\0';
            e->name[0] = '\0';
            e->aura_count = 0;
        }
        if (e->guid_str[0] == '\0') {
            om_fill_guid_string(e);
        }

        /* Populate AreaTrigger-specific fields */
        if (type == CGTYPE_AREA_TRIGGER && om_ptr_ok(cgobj, CGOBJ_AT_DIM_START + 16)) {
            e->at_spell_id       = om_read_u32(cgobj + CGOBJ_AT_SPELL_ID);
            e->at_duration_ms    = om_read_u32(cgobj + CGOBJ_AT_DURATION_MS);
            e->at_create_props_id = om_read_u32(cgobj + CGOBJ_AT_CREATE_PROPS_ID);
            e->at_area_trigger_id = om_read_u32(cgobj + CGOBJ_AT_AREA_TRIGGER_ID);
            e->at_scale_curve_id = om_read_u32(cgobj + CGOBJ_AT_SCALE_CURVE_ID);
            e->at_client_flags   = om_read_u32(cgobj + CGOBJ_AT_CLIENT_FLAGS);
            e->at_shape_type     = om_read_u8(cgobj + CGOBJ_AT_SHAPE_TYPE);
            e->at_caster_lo      = om_read_u64(cgobj + CGOBJ_AT_CASTER_LO);
            e->at_caster_hi      = om_read_u64(cgobj + CGOBJ_AT_CASTER_HI);
            float dim0 = om_read_f32(cgobj + CGOBJ_AT_DIM_START);
            e->at_radius = (dim0 > 0.0f && dim0 < 200.0f) ? dim0 : 0.0f;
            e->at_caster_str[0] = '\0';
        }
        cached++;
    }

    /* Commit the active-player GUID exactly once, and only when found -- preserves the
     * last-known value across a transient miss so the GUI's distance column never
     * flickers to "?" (see the reset site above). */
    if (found_ap_lo | found_ap_hi) {
        ipc->active_player_guid_lo = found_ap_lo;
        ipc->active_player_guid_hi = found_ap_hi;

        /* Player target/focus GUIDs from the active-player cgobj (68887 offsets). */
        uintptr_t pcg = 0;
        for (int k = 0; k < cached; k++)
            if (ipc->objects[k].guid_lo == found_ap_lo && ipc->objects[k].guid_hi == found_ap_hi) {
                pcg = (uintptr_t)ipc->objects[k].cgobj; break;
            }
        if (pcg) {
            if (om_ptr_ok(pcg + CGOBJ_TARGET_LO, 16)) {
                ipc->target_guid_lo = *(uint64_t*)(pcg + CGOBJ_TARGET_LO);
                ipc->target_guid_hi = *(uint64_t*)(pcg + CGOBJ_TARGET_HI);
            }
            if (om_ptr_ok(pcg + CGOBJ_FOCUS_LO, 16)) {
                ipc->focus_guid_lo = *(uint64_t*)(pcg + CGOBJ_FOCUS_LO);
                ipc->focus_guid_hi = *(uint64_t*)(pcg + CGOBJ_FOCUS_HI);
            }
        }
    }

    /* Passive patch-day drift check: once, ~3s after the player first appears (OM settled),
     * log a one-line [selfheal] summary. If camera is STALE it hints to run dinkr_PatchDay(). */
    {
        static int   s_shDone = 0;
        static DWORD s_shStart = 0;
        if (!s_shDone && (found_ap_lo | found_ap_hi)) {
            if (s_shStart == 0) s_shStart = now;
            else if (now - s_shStart > 3000) { DinkrSelfHealCheck(); s_shDone = 1; }
        }
    }

#if DINKR_DIAG_TGT
    /* Target/focus field finder: for the active-player object, log every offset whose
     * 16 bytes equal an enumerated object's GUID. Target a KNOWN mob (and set focus)
     * and read the [diag-tgt] lines -- the offset that tracks your target = the field. */
    {
        static DWORD s_lastTgt = 0;
        /* Player cgobj from the enumerated entry (g_activePlayerUnit may be null). */
        uintptr_t pcgobj = 0;
        for (int k = 0; k < cached; k++)
            if (ipc->objects[k].guid_lo == found_ap_lo && ipc->objects[k].guid_hi == found_ap_hi) {
                pcgobj = (uintptr_t)ipc->objects[k].cgobj; break;
            }
        if (pcgobj && (found_ap_lo | found_ap_hi) && (now - s_lastTgt) > 1500) {
            s_lastTgt = now;
            int hits = 0;
            for (uintptr_t off = 0x800; off <= 0x2A00 && hits < 16; off += 8) {
                if (!om_ptr_ok(pcgobj + off, 16)) continue;
                uint64_t vlo = *(uint64_t*)(pcgobj + off);
                uint64_t vhi = *(uint64_t*)(pcgobj + off + 8);
                if ((vlo | vhi) == 0) continue;
                if (vlo == found_ap_lo && vhi == found_ap_hi) continue;   /* self */
                for (int k = 0; k < cached; k++) {
                    if (ipc->objects[k].guid_lo == vlo && ipc->objects[k].guid_hi == vhi) {
                        char b[160];
                        snprintf(b, sizeof(b), "[diag-tgt] player+0x%X -> obj[%d] type=%d",
                                 (unsigned)off, k, ipc->objects[k].type);
                        DebugLog(b);
                        hits++;
                        break;
                    }
                }
            }
            if (hits == 0)
                DebugLog("[diag-tgt] no player-obj field matched an enumerated GUID this pass");
        }
    }
#endif

#if DINKR_DIAG_CAM
    /* SAFE camera struct dump (no scan): CAM_MGR=0x442C958 -> [+0x4B0]=CCamera confirmed.
     * Dump fixed, guarded ranges of both structs so the eye (point ~player), lookat,
     * fov (~0.7-1.5 rad), viewport, and view-proj matrix (16 floats) offsets can be read
     * off directly. One-shot. Player pos printed for the eye anchor. */
    {
        static int s_camDumped = 0;
        if (!s_camDumped) {
            uintptr_t wfp = (uintptr_t)base + RVA_CAM_MGR_68887;
            if (om_ptr_ok(wfp, 8)) {
                uintptr_t wf = *(uintptr_t*)wfp;
                if (om_ptr_ok(wf, 0x4C0)) {
                    uintptr_t cam = *(uintptr_t*)(wf + 0x4B0);
                    if (om_ptr_ok(cam, 0x140)) {
                        s_camDumped = 1;
                        char b[256];
                        float ppx = 0, ppy = 0, ppz = 0;
                        for (int k = 0; k < cached; k++)
                            if (ipc->objects[k].guid_lo == found_ap_lo && ipc->objects[k].guid_hi == found_ap_hi) {
                                ppx = ipc->objects[k].pos_x; ppy = ipc->objects[k].pos_y; ppz = ipc->objects[k].pos_z; break;
                            }
                        snprintf(b, sizeof(b), "[camdump] player pos %.2f,%.2f,%.2f  wf=0x%llX cam=0x%llX",
                                 ppx, ppy, ppz, (unsigned long long)wf, (unsigned long long)cam);
                        DebugLog(b);
                        for (uintptr_t o = 0; o <= 0x130; o += 0x10) {
                            const float* f = (const float*)(cam + o);
                            snprintf(b, sizeof(b), "[camdump] cam+0x%03X: %.3f %.3f %.3f %.3f",
                                     (unsigned)o, f[0], f[1], f[2], f[3]);
                            DebugLog(b);
                        }
                        for (uintptr_t o = 0x30; o <= 0x50; o += 0x10) {
                            const float* f = (const float*)(wf + o);
                            snprintf(b, sizeof(b), "[camdump] wf+0x%03X: %.3f %.3f %.3f %.3f",
                                     (unsigned)o, f[0], f[1], f[2], f[3]);
                            DebugLog(b);
                        }
                        for (uintptr_t o = 0x300; o <= 0x4B0; o += 0x10) {
                            const float* f = (const float*)(wf + o);
                            snprintf(b, sizeof(b), "[camdump] wf+0x%03X: %.4f %.4f %.4f %.4f",
                                     (unsigned)o, f[0], f[1], f[2], f[3]);
                            DebugLog(b);
                        }
                    }
                }
            }
            if (!s_camDumped) DebugLog("[camdump] chain not ready (wf/cam invalid)");
            s_camDumped = 1;
        }
    }
#endif

#if DINKR_DIAG_W2S
    {
        static int s_w2s = 0;
        if (!s_w2s && (found_ap_lo | found_ap_hi)) {
            uintptr_t wfp = (uintptr_t)base + RVA_CAM_MGR_68887;
            if (om_ptr_ok(wfp, 8)) {
                uintptr_t wf = *(uintptr_t*)wfp;
                if (om_ptr_ok(wf, 0x3C8)) {
                    uintptr_t cam = *(uintptr_t*)(wf + 0x4B0);
                    if (om_ptr_ok(cam, 0x1C)) {
                        float ppx = 0, ppy = 0, ppz = 0;
                        for (int k = 0; k < cached; k++)
                            if (ipc->objects[k].guid_lo == found_ap_lo && ipc->objects[k].guid_hi == found_ap_hi) {
                                ppx = ipc->objects[k].pos_x; ppy = ipc->objects[k].pos_y; ppz = ipc->objects[k].pos_z; break;
                            }
                        if (ppx != 0.0f || ppy != 0.0f) {
                            s_w2s = 1;
                            const float* m = (const float*)(wf + 0x388);
                            float ex = *(float*)(cam + 0x10), ey = *(float*)(cam + 0x14), ez = *(float*)(cam + 0x18);
                            char b[256];
                            snprintf(b, sizeof(b), "[w2s] eye=%.2f,%.2f,%.2f player=%.2f,%.2f,%.2f", ex, ey, ez, ppx, ppy, ppz); DebugLog(b);
                            snprintf(b, sizeof(b), "[w2s] m0-3   %.4f %.4f %.4f %.4f", m[0], m[1], m[2], m[3]);  DebugLog(b);
                            snprintf(b, sizeof(b), "[w2s] m4-7   %.4f %.4f %.4f %.4f", m[4], m[5], m[6], m[7]);  DebugLog(b);
                            snprintf(b, sizeof(b), "[w2s] m8-11  %.4f %.4f %.4f %.4f", m[8], m[9], m[10], m[11]); DebugLog(b);
                            snprintf(b, sizeof(b), "[w2s] m12-15 %.4f %.4f %.4f %.4f", m[12], m[13], m[14], m[15]); DebugLog(b);
                            float vx = ppx - ex, vy = ppy - ey, vz = ppz - ez;
                            float cX = m[0]*vx + m[4]*vy + m[8]*vz;
                            float cY = m[1]*vx + m[5]*vy + m[9]*vz;
                            float cW = m[3]*vx + m[7]*vy + m[11]*vz;
                            snprintf(b, sizeof(b), "[w2s] v=%.2f,%.2f,%.2f cX=%.3f cY=%.3f cW=%.3f -> sx=%.3f sy=%.3f",
                                     vx, vy, vz, cX, cY, cW, cW != 0 ? (cX/cW+1)*0.5f : 0, cW != 0 ? (1-cY/cW)*0.5f : 0);
                            DebugLog(b);
                        }
                    }
                }
            }
        }
    }
#endif

    if (doLog) {
        char dbg[256];
        if (cached > 0) {
            char guidBuf[80];
            om_fill_guid_raw(ipc->objects[0].guid_hi, ipc->objects[0].guid_lo, guidBuf, sizeof(guidBuf));
            snprintf(dbg, sizeof(dbg),
                "[dll-om] OM: %d entities (first: type=%d %s pos=%.1f,%.1f,%.1f)",
                cached, ipc->objects[0].type, guidBuf,
                ipc->objects[0].pos_x, ipc->objects[0].pos_y, ipc->objects[0].pos_z);
        } else {
            snprintf(dbg, sizeof(dbg), "[dll-om] OM: 0 entities");
        }
        DebugLog(dbg);
        snprintf(dbg, sizeof(dbg),
            "[dll-om] reject: free=%d inactive=%d slot=%d arch=%d arch_off=%d cgobj=%d class=%d guid=%d",
            rej_status_free, rej_status_inactive, rej_slot, rej_arch,
            rej_arch_off, rej_cgobj, rej_class, rej_guid);
        DebugLog(dbg);
    }

    if (doLog && cached > 0) {
        char dbg[128];
        snprintf(dbg, sizeof(dbg), "[dll-om] total: %d entities", cached);
        DebugLog(dbg);
    }

    ipc->om_object_count = (uint32_t)cached;
    MemoryBarrier();
    InterlockedIncrement((volatile LONG*)&ipc->om_enum_seq); /* even = stable */
    ipc->om_update_tick++;
}
