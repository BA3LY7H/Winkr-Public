/* dinkr_bridge_objects.c -- OM-backed Lua bridge functions */

#include <stdio.h>
#include "dinkr_bridge.h"

/* ========================================================================
** OM-backed Lua bridge functions
**
** These read from IPC shared memory (populated by GUI via ReadProcessMemory)
** and use in-process reads for real-time position/facing data.
** ======================================================================== */

int __fastcall dinkr_GetObjectCount(void* L) {
    DinkrIPC* ipc = GetIPC();
    int count = ipc ? (int)ipc->om_object_count : 0;
    s_pPushnumber(L, (double)count);
    return 1;
}

int __fastcall dinkr_GetObjectWithIndex(void* L) {
    int idx = (int)wk_arg_number(L, 1);

    DinkrIPC* ipc = GetIPC();
    if (!ipc || idx < 1 || idx > (int)ipc->om_object_count) {
        s_pPushnil(L);
        return 1;
    }
    OmCacheEntry* e = &ipc->objects[idx - 1];
    om_ensure_guid_formatted(e);
    s_pPushstring(L, e->guid_str);
    return 1;
}

/* Helper: look up OM entry via IPC and validate cgobj pointer */
static const OmCacheEntry* om_ipc_resolve_with_ipc(void* L, size_t maxOffset, DinkrIPC** out_ipc) {
    DinkrIPC* ipc = GetIPC();
    if (out_ipc) *out_ipc = ipc;
    if (!ipc) return NULL;
    size_t len = 0;
    const char* guid_str = wk_arg_string(L, 1, &len);
    if (!guid_str || len == 0) return NULL;
    const OmCacheEntry* e = om_find_by_guid_str(ipc, guid_str);
    if (!e) return NULL;
    if (!om_ptr_ok(e->cgobj, maxOffset + 8)) return NULL;
    return e;
}

static const OmCacheEntry* om_ipc_resolve(void* L, size_t maxOffset) {
    return om_ipc_resolve_with_ipc(L, maxOffset, NULL);
}

typedef struct {
    DinkrIPC* ipc;
    uint32_t tick;
    uint64_t guid_lo;
    uint64_t guid_hi;
    uintptr_t pos_base;
    uint8_t valid;
} OmEntityPosCache;

static OmEntityPosCache g_entity_pos_cache = {0};

static void om_cache_entity_pos(DinkrIPC* ipc, const OmCacheEntry* e, uint32_t tick, uintptr_t pos_base, int valid) {
    if (!e) return;
    g_entity_pos_cache.ipc = ipc;
    g_entity_pos_cache.tick = tick;
    g_entity_pos_cache.guid_lo = e->guid_lo;
    g_entity_pos_cache.guid_hi = e->guid_hi;
    g_entity_pos_cache.pos_base = pos_base;
    g_entity_pos_cache.valid = valid ? 1 : 0;
}

/* Resolve ECS EntityPosition base once per GUID per OM tick. */
int om_resolve_entity_pos_base(DinkrIPC* ipc, const OmCacheEntry* e, uintptr_t* out_pos_base) {
    if (!ipc || !e || !out_pos_base) return 0;
    uint32_t tick = ipc->om_update_tick;
    if (g_entity_pos_cache.ipc == ipc &&
        g_entity_pos_cache.tick == tick &&
        g_entity_pos_cache.guid_lo == e->guid_lo &&
        g_entity_pos_cache.guid_hi == e->guid_hi) {
        if (!g_entity_pos_cache.valid) return 0;
        if (!om_ptr_ok(g_entity_pos_cache.pos_base + 0x8C, 4)) {
            g_entity_pos_cache.valid = 0;
            return 0;
        }
        *out_pos_base = g_entity_pos_cache.pos_base;
        return 1;
    }

    uintptr_t entity = (uintptr_t)e->entity;
    if (!entity || entity < 0x10000) {
        om_cache_entity_pos(ipc, e, tick, 0, 0);
        return 0;
    }
    uintptr_t archetype = om_read_ptr(entity + 8);
    if (!om_ptr_ok(archetype, 0x38)) {
        om_cache_entity_pos(ipc, e, tick, 0, 0);
        return 0;
    }
    int32_t pos_offset = (int32_t)om_read_u32(archetype + 0x34);
    if (pos_offset < 0 || pos_offset > 0x10000) {
        om_cache_entity_pos(ipc, e, tick, 0, 0);
        return 0;
    }

    uintptr_t pos_base = entity + (uintptr_t)pos_offset;
    if (!om_ptr_ok(pos_base + 0x8C, 4)) {
        om_cache_entity_pos(ipc, e, tick, 0, 0);
        return 0;
    }

    om_cache_entity_pos(ipc, e, tick, pos_base, 1);
    *out_pos_base = pos_base;
    return 1;
}

int __fastcall dinkr_ObjectType(void* L) {
    const OmCacheEntry* e = om_ipc_resolve(L, CGOBJ_TYPE_BYTE);
    if (!e) { s_pPushnil(L); return 1; }
    int type = (int)e->type;
    if (type == 7) type = 6;  /* ActivePlayer \xe2\x86\x92 Player for awful2 */
    s_pPushnumber(L, (double)type);
    return 1;
}

int __fastcall dinkr_ObjectPosition(void* L) {
    DinkrIPC* ipc = NULL;
    const OmCacheEntry* e = om_ipc_resolve_with_ipc(L, CGOBJ_TYPE_BYTE + 1, &ipc);
    if (!e || !ipc) { s_pPushnil(L); return 1; }
    uintptr_t pos_base = 0;
    if (!om_resolve_entity_pos_base(ipc, e, &pos_base)) { s_pPushnil(L); return 1; }
    float x = om_read_f32(pos_base + 0x84);
    float y = om_read_f32(pos_base + 0x88);
    float z = om_read_f32(pos_base + 0x8C);
    s_pPushnumber(L, (double)x);
    s_pPushnumber(L, (double)y);
    s_pPushnumber(L, (double)z);
    return 3;
}

int __fastcall dinkr_ObjectFacing(void* L) {
    DinkrIPC* ipc = NULL;
    const OmCacheEntry* e = om_ipc_resolve_with_ipc(L, CGOBJ_TYPE_BYTE + 1, &ipc);
    if (!e || !ipc) { s_pPushnumber(L, 0.0); return 1; }
    uintptr_t pos_base = 0;
    if (!om_resolve_entity_pos_base(ipc, e, &pos_base)) { s_pPushnumber(L, 0.0); return 1; }
    float facing = om_read_f32(pos_base + 0x50);
    s_pPushnumber(L, (double)facing);
    return 1;
}

/* ObjectRotation is an alias for ObjectFacing (same data at +0x50) */
int __fastcall dinkr_ObjectRotation(void* L) {
    return dinkr_ObjectFacing(L);
}

/* Entry (template) id for units AND game objects.
 *
 * Prefers the GUID-encoded entry over the CGOBJ_NPC_ID descriptor field, which
 * reads 0 for BOTH on this build: Marshal McBride (entry 197) reported 0, and
 * every herb/ore node reported 0 too, so each Lua consumer had to re-derive the
 * id itself. WowGuid_Entry returns 0 for GUID formats that carry no entry field
 * (players, items), so the raw field remains the fallback. */
int __fastcall dinkr_ObjectID(void* L) {
    const OmCacheEntry* e = om_ipc_resolve(L, CGOBJ_NPC_ID + 4);
    if (!e) { s_pPushnumber(L, 0.0); return 1; }

    uint32_t entry = WowGuid_Entry(e->guid_hi, e->guid_lo);
    if (entry) { s_pPushnumber(L, (double)entry); return 1; }

    uint32_t npcId = om_read_u32(e->cgobj + CGOBJ_NPC_ID);
    s_pPushnumber(L, (double)npcId);
    return 1;
}

int __fastcall dinkr_ObjectName(void* L) {
    DinkrIPC* ipc = GetIPC();
    if (!ipc) { s_pPushnil(L); return 1; }
    size_t len = 0;
    const char* guid_str = wk_arg_string(L, 1, &len);
    if (!guid_str || len == 0) { s_pPushnil(L); return 1; }
    const OmCacheEntry* e = om_find_by_guid_str(ipc, guid_str);
    if (!e || !e->name[0]) { s_pPushnil(L); return 1; }
    s_pPushstring(L, e->name);
    return 1;
}

int __fastcall dinkr_ObjectCreator(void* L) {
    DinkrIPC* ipc = GetIPC();
    if (!ipc) { s_pPushnil(L); return 1; }
    size_t len = 0;
    const char* guid_str = wk_arg_string(L, 1, &len);
    if (!guid_str || len == 0) { s_pPushnil(L); return 1; }
    const OmCacheEntry* e = om_find_by_guid_str(ipc, guid_str);
    if (!e || !e->cgobj) { s_pPushnil(L); return 1; }

    /* Check SummonedBy first */
    uint64_t lo = om_read_u64(e->cgobj + CGOBJ_SUMMONED_BY_LO);
    uint64_t hi = om_read_u64(e->cgobj + CGOBJ_SUMMONED_BY_HI);

    /* If SummonedBy is zero, try CreatedBy */
    if (!lo && !hi) {
        lo = om_read_u64(e->cgobj + CGOBJ_CREATED_BY_LO);
        hi = om_read_u64(e->cgobj + CGOBJ_CREATED_BY_HI);
    }

    if (!lo && !hi) { s_pPushnil(L); return 1; }

    /* Convert to GUID string — same pattern as dinkr_ObjectCastingTarget */
    const OmCacheEntry* creator = om_find_by_guid_lohi(ipc, lo, hi);
    if (creator) {
        OmCacheEntry* creator_mut = (OmCacheEntry*)creator;
        om_ensure_guid_formatted(creator_mut);
        if (creator_mut->guid_str[0]) {
            s_pPushstring(L, creator_mut->guid_str);
            return 1;
        }
    }

    {
        char buf[80];
        int w = WowGuid_Format(hi, lo, buf, sizeof(buf));
        if (w > 0 && w < (int)sizeof(buf)) {
            s_pPushstring(L, buf);
            return 1;
        }
    }

    char buf[80];
    snprintf(buf, sizeof(buf), "0x%016llX-%016llX",
             (unsigned long long)hi, (unsigned long long)lo);
    s_pPushstring(L, buf);
    return 1;
}

int __fastcall dinkr_ObjectTarget(void* L) {
    DinkrIPC* ipc = GetIPC();
    if (!ipc) { s_pPushnil(L); return 1; }
    size_t len = 0;
    const char* guid_str = wk_arg_string(L, 1, &len);
    if (!guid_str || len == 0) { s_pPushnil(L); return 1; }
    const OmCacheEntry* e = om_find_by_guid_str(ipc, guid_str);
    if (!e || (e->target_guid_lo == 0 && e->target_guid_hi == 0)) {
        s_pPushnil(L);
        return 1;
    }
    OmCacheEntry* em = (OmCacheEntry*)e;
    om_ensure_target_guid_formatted(em);
    if (em->target_guid_str[0]) {
        s_pPushstring(L, em->target_guid_str);
        return 1;
    }

    char buf[80];
    int w = WowGuid_Format(e->target_guid_hi, e->target_guid_lo, buf, sizeof(buf));
    if (w > 0 && w < (int)sizeof(buf)) {
        s_pPushstring(L, buf);
        return 1;
    }

    snprintf(buf, sizeof(buf), "0x%016llX-%016llX",
             (unsigned long long)e->target_guid_hi,
             (unsigned long long)e->target_guid_lo);
    s_pPushstring(L, buf);
    return 1;
}

int __fastcall dinkr_ObjectCastingTarget(void* L) {
    DinkrIPC* ipc = GetIPC();
    if (!ipc) { s_pPushnil(L); return 1; }
    size_t len = 0;
    const char* guid_str = wk_arg_string(L, 1, &len);
    if (!guid_str || len == 0) { s_pPushnil(L); return 1; }
    const OmCacheEntry* e = om_find_by_guid_str(ipc, guid_str);
    if (!e || !e->cgobj || !om_ptr_ok(e->cgobj, CGOBJ_CAST_TARGET_HI + 8)) {
        s_pPushnil(L); return 1;
    }

    /* Read cast/channel target GUID from live memory */
    uint64_t lo = om_read_u64(e->cgobj + CGOBJ_CAST_TARGET_LO);
    uint64_t hi = om_read_u64(e->cgobj + CGOBJ_CAST_TARGET_HI);
    if (!lo && !hi) { s_pPushnil(L); return 1; }

    /* Try OM cache for pre-formatted GUID string */
    const OmCacheEntry* target = om_find_by_guid_lohi(ipc, lo, hi);
    if (target) {
        OmCacheEntry* target_mut = (OmCacheEntry*)target;
        om_ensure_guid_formatted(target_mut);
        if (target_mut->guid_str[0]) {
            s_pPushstring(L, target_mut->guid_str);
            return 1;
        }
    }

    /* Fallback: local WoW GUID formatter */
    {
        char buf[80];
        int w = WowGuid_Format(hi, lo, buf, sizeof(buf));
        if (w > 0 && w < (int)sizeof(buf)) {
            s_pPushstring(L, buf);
            return 1;
        }
    }

    /* Final fallback: manual hex format */
    char buf[80];
    snprintf(buf, sizeof(buf), "0x%016llX-%016llX",
             (unsigned long long)hi,
             (unsigned long long)lo);
    s_pPushstring(L, buf);
    return 1;
}

int __fastcall dinkr_IsValidObject(void* L) {
    DinkrIPC* ipc = GetIPC();
    if (!ipc) { s_pPushboolean(L, 0); return 1; }
    size_t len = 0;
    const char* guid_str = wk_arg_string(L, 1, &len);
    if (!guid_str || len == 0) { s_pPushboolean(L, 0); return 1; }
    const OmCacheEntry* e = om_find_by_guid_str(ipc, guid_str);
    int valid = (e != NULL && om_ptr_ok(e->cgobj, CGOBJ_TYPE_BYTE + 1));
    s_pPushboolean(L, valid);
    return 1;
}

int __fastcall dinkr_IsPlayerGuid(void* L) {
    size_t len = 0;
    const char* guid_str = wk_arg_string(L, 1, &len);
    if (!guid_str || len == 0 || !g_modLoaderBase) { s_pPushboolean(L, 0); return 1; }
    DinkrIPC* ipc = GetIPC();
    if (!ipc) { s_pPushboolean(L, 0); return 1; }
    const OmCacheEntry* e = om_find_by_guid_str(ipc, guid_str);
    if (!e) { s_pPushboolean(L, 0); return 1; }
    /* 68887: ActivePlayerGUID is no longer a raw global. Use active_player_guid
     * captured by the OM enumerator from the CGTYPE_ACTIVE_PLAYER object. */
    uint64_t plo = ipc->active_player_guid_lo;
    uint64_t phi = ipc->active_player_guid_hi;
    s_pPushboolean(L, ((plo | phi) != 0 && e->guid_lo == plo && e->guid_hi == phi) ? 1 : 0);
    return 1;
}

int __fastcall dinkr_IsTargetGuid(void* L) {
    size_t len = 0;
    const char* guid_str = wk_arg_string(L, 1, &len);
    if (!guid_str || len == 0 || !g_modLoaderBase) { s_pPushboolean(L, 0); return 1; }
    DinkrIPC* ipc = GetIPC();
    if (!ipc) { s_pPushboolean(L, 0); return 1; }
    /* 68887: RVA_TargetGUID is a dead global -> use the OM-populated player target
     * (from active-player cgobj+CGOBJ_TARGET_LO, written in dinkr_om_enum.c). */
    uint64_t tlo = ipc->target_guid_lo;
    uint64_t thi = ipc->target_guid_hi;
    BOOL match = om_guid_matches(ipc, guid_str, tlo, thi);
    s_pPushboolean(L, match ? 1 : 0);
    return 1;
}

int __fastcall dinkr_IsFocusGuid(void* L) {
    size_t len = 0;
    const char* guid_str = wk_arg_string(L, 1, &len);
    if (!guid_str || len == 0 || !g_modLoaderBase) { s_pPushboolean(L, 0); return 1; }
    DinkrIPC* ipc = GetIPC();
    if (!ipc) { s_pPushboolean(L, 0); return 1; }
    /* 68887: RVA_FocusGUID is a dead global -> use the OM-populated player focus
     * (from active-player cgobj+CGOBJ_FOCUS_LO, written in dinkr_om_enum.c). */
    uint64_t flo = ipc->focus_guid_lo;
    uint64_t fhi = ipc->focus_guid_hi;
    BOOL match = om_guid_matches(ipc, guid_str, flo, fhi);
    s_pPushboolean(L, match ? 1 : 0);
    return 1;
}

/* ========================================================================
** SetNPC — write a GUID to the real NPC slot for temporary resolution
**
** Lua: dinkr_SetNPC(guidString)  — sets NPC slot to this GUID
**      returns true on success, nothing on failure
** Lua: dinkr_SetNPC()            — clears NPC slot (zeros out)
** ======================================================================== */

int __fastcall dinkr_LuaSetNPC(void* L) {
    if (!g_modLoaderBase) return 0;

    /* The "npc" unit token resolves from g_NpcTargetGUID @ RVA 0x45E37C0
     * (verified via unit-token reverse resolver sub_7FF6FA22BBC0 in 67186). */
    uintptr_t pNpcGuid = (uintptr_t)(g_modLoaderBase + RVA_NpcTargetGUID);
    if (!om_ptr_ok(pNpcGuid, 16)) return 0;

    /* Check if we have an argument */
    size_t len = 0;
    const char* guid_str = wk_arg_string(L, 1, &len);

    if (!guid_str || len == 0) {
        /* CLEAR: zero NPC GUID only */
        memset((void*)pNpcGuid, 0, 16);
        s_lastNPCPushTick = 0;
        return 0;
    }

    /* Find object in OM cache by GUID string */
    DinkrIPC* ipc = GetIPC();
    if (!ipc) return 0;

    const OmCacheEntry* e = om_find_by_guid_str(ipc, guid_str);
    if (!e) return 0;

    /* Write the 128-bit GUID to the NPC slot */
    memcpy((void*)pNpcGuid,       &e->guid_lo, 8);
    memcpy((void*)(pNpcGuid + 8), &e->guid_hi, 8);

    s_lastNPCPushTick = GetTickCount();

    s_pPushboolean(L, 1);
    return 1;
}

int __fastcall dinkr_ObjectCombatReach(void* L) {
    const OmCacheEntry* e = om_ipc_resolve(L, CGOBJ_COMBAT_REACH + 4);
    if (!e) { s_pPushnumber(L, 0.0); return 1; }
    float reach = om_read_f32(e->cgobj + CGOBJ_COMBAT_REACH);
    s_pPushnumber(L, (double)reach);
    return 1;
}

int __fastcall dinkr_ObjectBoundingRadius(void* L) {
    const OmCacheEntry* e = om_ipc_resolve(L, CGOBJ_BOUNDING_RADIUS + 4);
    if (!e) { s_pPushnumber(L, 0.0); return 1; }
    float radius = om_read_f32(e->cgobj + CGOBJ_BOUNDING_RADIUS);
    s_pPushnumber(L, (double)radius);
    return 1;
}

int __fastcall dinkr_ObjectCreatureType(void* L) {
    const OmCacheEntry* e = om_ipc_resolve(L, CGOBJ_CREATURE_TYPE + 1);
    if (!e) { s_pPushnumber(L, 0.0); return 1; }
    if (!IsUnitType(e->type)) { s_pPushnumber(L, 0.0); return 1; }
    uint8_t ct = om_read_u8(e->cgobj + CGOBJ_CREATURE_TYPE);
    s_pPushnumber(L, (double)ct);
    return 1;
}

int __fastcall dinkr_ObjectATInfo(void* L) {
    const OmCacheEntry* e = om_ipc_resolve(L, CGOBJ_AT_DIM_START + 4);
    if (!e || e->type != CGTYPE_AREA_TRIGGER) { s_pPushnil(L); return 1; }
    DinkrIPC* ipc = GetIPC();

    s_pCreatetable(L, 0, 10);

    s_pPushnumber(L, (double)e->at_spell_id);
    s_pSetField(L, -2, "spellId");

    s_pPushnumber(L, (double)e->at_duration_ms);
    s_pSetField(L, -2, "duration");

    s_pPushnumber(L, (double)e->at_create_props_id);
    s_pSetField(L, -2, "createPropsId");

    s_pPushnumber(L, (double)e->at_area_trigger_id);
    s_pSetField(L, -2, "areaTriggerId");

    s_pPushnumber(L, (double)e->at_scale_curve_id);
    s_pSetField(L, -2, "scaleCurveId");

    s_pPushnumber(L, (double)e->at_client_flags);
    s_pSetField(L, -2, "flags");

    s_pPushnumber(L, (double)e->at_shape_type);
    s_pSetField(L, -2, "shapeType");

    s_pPushnumber(L, (double)e->at_radius);
    s_pSetField(L, -2, "radius");

    if (e->at_caster_lo || e->at_caster_hi) {
        const char* caster = NULL;
        char casterBuf[80];
        casterBuf[0] = '\0';
        const OmCacheEntry* ce = om_find_by_guid_lohi(ipc, e->at_caster_lo, e->at_caster_hi);
        if (ce) {
            OmCacheEntry* ce_mut = (OmCacheEntry*)ce;
            om_ensure_guid_formatted(ce_mut);
            if (ce_mut->guid_str[0]) caster = ce_mut->guid_str;
        }
        if (!caster) {
            int w = WowGuid_Format(e->at_caster_hi, e->at_caster_lo, casterBuf, sizeof(casterBuf));
            if (w > 0 && w < (int)sizeof(casterBuf)) caster = casterBuf;
        }
        if (caster) {
            s_pPushlstring(L, caster, strlen(caster));
            s_pSetField(L, -2, "caster");
        }
    }

    return 1;
}

int __fastcall dinkr_ObjectMovementFlag(void* L) {
    DinkrIPC* ipc = GetIPC();
    if (!ipc) { s_pPushnumber(L, 0.0); return 1; }
    size_t len = 0;
    const char* guid_str = wk_arg_string(L, 1, &len);
    const OmCacheEntry* e = om_find_by_guid_str(ipc, guid_str);
    if (!e || !e->cgobj) { s_pPushnumber(L, 0.0); return 1; }

    /* Read Movement_C pointer from unit + 0xE0 */
    uintptr_t movement_c = om_read_ptr(e->cgobj + CGOBJ_MOVEMENT_C_PTR);
    if (!om_ptr_ok(movement_c, MOVEMENT_C_FLAGS + 4)) {
        s_pPushnumber(L, 0.0); return 1;
    }

    /* Read movement flags from Movement_C + 0x190 */
    uint32_t flags = om_read_u32(movement_c + MOVEMENT_C_FLAGS);
    s_pPushnumber(L, (double)flags);
    return 1;
}

/* dinkr_DumpObject(guid, [label])
 * Write every non-zero dword of an object to C:\projects\dinkr_objdump.txt.
 *
 * WHY A BRIDGE AND NOT THE PATCH-DAY SCAN: that scan located the target through
 * cgobj+CGOBJ_TARGET_LO, and 0x1B48 is itself STALE on 69109 -- it reported
 * "no target" with a target set, because the offset it used to find the target
 * had moved. Taking the GUID as an argument removes every stale-offset
 * dependency: Lua passes UnitGUID("target"), which is an API call and cannot
 * drift.
 *
 * PURPOSE: dead-state detection has no working route on this build. Dynamic
 * flags at 0x94 read 0, dinkr_SetNPC mints no token, and health is a secret
 * value so it can never be matched in memory. Dump a LIVE unit and a CORPSE,
 * diff the two files, and the offset that changes is the flag.
 *
 * Appends, so successive calls build up a comparable log. */
int __fastcall dinkr_DumpObject(void* L) {
    DinkrIPC* ipc = GetIPC();
    if (!ipc) { s_pPushnil(L); return 1; }
    size_t len = 0;
    const char* guid_str = wk_arg_string(L, 1, &len);
    const OmCacheEntry* e = om_find_by_guid_str(ipc, guid_str);
    if (!e || !e->cgobj) { s_pPushnil(L); return 1; }

    size_t len2 = 0;
    const char* label = wk_arg_string(L, 2, &len2);

    FILE* f = fopen("C:\\projects\\dinkr_objdump.txt", "a");
    if (!f) { s_pPushnil(L); return 1; }
    fprintf(f, "\n=== OBJECT DUMP  label=%s  guid=%s  cgobj=0x%llX ===\n",
            label ? label : "(none)", guid_str ? guid_str : "?",
            (unsigned long long)e->cgobj);
    int shown = 0;
    for (uintptr_t off = 0x0; off <= 0x2A00; off += 4) {
        if (!om_ptr_ok(e->cgobj + off, 4)) continue;
        uint32_t v = *(uint32_t*)(e->cgobj + off);
        if (v == 0) continue;
        fprintf(f, "+0x%04X = 0x%08X\n", (unsigned)off, v);
        shown++;
    }
    fprintf(f, "=== %d non-zero fields ===\n", shown);
    fclose(f);
    s_pPushnumber(L, (double)shown);
    return 1;
}

/* dinkr_ObjectDescriptor(guid, offset, type)
 * Read raw value from CGObject at given offset.
 * Types: 1=Bool,2=Char,3=Byte,4=Short,5=UShort,6=Int,7=UInt,8=Long,9=ULong,
 *        10=Float,11=Double,12=String,13=IntPtr,14=UIntPtr,15=GUID(128bit→string)
 * Returns number (or string for types 12/15), or nil if invalid. */
int __fastcall dinkr_ObjectDescriptor(void* L) {
    DinkrIPC* ipc = GetIPC();
    if (!ipc) { s_pPushnil(L); return 1; }
    size_t len = 0;
    const char* guid_str = wk_arg_string(L, 1, &len);
    const OmCacheEntry* e = om_find_by_guid_str(ipc, guid_str);
    if (!e || !e->cgobj) { s_pPushnil(L); return 1; }

    size_t len2 = 0, len3 = 0;
    const char* soff = wk_arg_string(L, 2, &len2);
    const char* styp = wk_arg_string(L, 3, &len3);
    if (!soff) { s_pPushnil(L); return 1; }

    int offset = atoi(soff);
    int rtype  = styp ? atoi(styp) : 7; /* default UInt */

    if (offset < 0 || offset > 0x10000) { s_pPushnil(L); return 1; }
    uintptr_t addr = e->cgobj + (uintptr_t)offset;

    switch (rtype) {
        case 1: /* Bool */
            if (!om_ptr_ok(addr, 1)) { s_pPushnil(L); return 1; }
            s_pPushboolean(L, om_read_u8(addr) ? 1 : 0);
            break;
        case 2: /* Char (signed byte) */
            if (!om_ptr_ok(addr, 1)) { s_pPushnil(L); return 1; }
            s_pPushnumber(L, (double)(int8_t)om_read_u8(addr));
            break;
        case 3: /* Byte (unsigned) */
            if (!om_ptr_ok(addr, 1)) { s_pPushnil(L); return 1; }
            s_pPushnumber(L, (double)om_read_u8(addr));
            break;
        case 4: /* Short (signed 16) */
            if (!om_ptr_ok(addr, 2)) { s_pPushnil(L); return 1; }
            s_pPushnumber(L, (double)(int16_t)om_read_u16(addr));
            break;
        case 5: /* UShort (unsigned 16) */
            if (!om_ptr_ok(addr, 2)) { s_pPushnil(L); return 1; }
            s_pPushnumber(L, (double)om_read_u16(addr));
            break;
        case 6: /* Int (signed 32) */
            if (!om_ptr_ok(addr, 4)) { s_pPushnil(L); return 1; }
            s_pPushnumber(L, (double)(int32_t)om_read_u32(addr));
            break;
        case 7: /* UInt (unsigned 32) */
            if (!om_ptr_ok(addr, 4)) { s_pPushnil(L); return 1; }
            s_pPushnumber(L, (double)om_read_u32(addr));
            break;
        case 8: /* Long (signed 64) */
            if (!om_ptr_ok(addr, 8)) { s_pPushnil(L); return 1; }
            s_pPushnumber(L, (double)(int64_t)om_read_u64(addr));
            break;
        case 9: /* ULong (unsigned 64) */
            if (!om_ptr_ok(addr, 8)) { s_pPushnil(L); return 1; }
            s_pPushnumber(L, (double)om_read_u64(addr));
            break;
        case 10: /* Float */
            if (!om_ptr_ok(addr, 4)) { s_pPushnil(L); return 1; }
            s_pPushnumber(L, (double)om_read_f32(addr));
            break;
        case 11: /* Double */
            if (!om_ptr_ok(addr, 8)) { s_pPushnil(L); return 1; }
            { double d; memcpy(&d, (void*)addr, 8); s_pPushnumber(L, d); }
            break;
        case 12: /* String (read null-terminated, max 256 chars) */
            if (!om_ptr_ok(addr, 8)) { s_pPushnil(L); return 1; }
            {
                uintptr_t strptr = om_read_ptr(addr);
                if (!strptr || !om_ptr_ok(strptr, 1)) { s_pPushnil(L); return 1; }
                const char* s = (const char*)strptr;
                size_t slen = 0;
                while (slen < 256 && s[slen]) slen++;
                s_pPushlstring(L, s, slen);
            }
            break;
        case 13: /* IntPtr (pointer as signed) */
        case 14: /* UIntPtr (pointer as unsigned) */
            if (!om_ptr_ok(addr, 8)) { s_pPushnil(L); return 1; }
            s_pPushnumber(L, (double)om_read_u64(addr));
            break;
        case 15: /* GUID (128bit → formatted string) */
            if (!om_ptr_ok(addr, 16)) { s_pPushnil(L); return 1; }
            {
                uint64_t glo = om_read_u64(addr);
                uint64_t ghi = om_read_u64(addr + 8);
                if (glo == 0 && ghi == 0) { s_pPushnil(L); return 1; }
                char buf[80];
                WowGuid_Format(ghi, glo, buf, sizeof(buf));
                s_pPushlstring(L, buf, strlen(buf));
            }
            break;
        default:
            s_pPushnil(L);
            break;
    }
    return 1;
}

int __fastcall dinkr_ObjectSpecializationID(void* L) {
    if (!g_modLoaderBase) { s_pPushnumber(L, 0.0); return 1; }

    DinkrIPC* ipc = GetIPC();
    if (!ipc) { s_pPushnumber(L, 0.0); return 1; }
    size_t len = 0;
    const char* guid_str = wk_arg_string(L, 1, &len);
    const OmCacheEntry* e = om_find_by_guid_str(ipc, guid_str);
    if (!e) { s_pPushnumber(L, 0.0); return 1; }

    /* Read specId from CGObject descriptor — works for local and remote players.
     * Offset 0x2264 is the ChrSpecialization ID in the unit descriptor. */
    if (e->cgobj && om_ptr_ok(e->cgobj + 0x2264, 4)) {
        uint32_t specId = om_read_u32(e->cgobj + 0x2264);
        if (specId > 0 && specId < 2000) {
            s_pPushnumber(L, (double)specId);
            return 1;
        }
    }

    /* Fallback: match the OM-captured active_player_guid (68887: no raw global) */
    uint64_t plo = ipc->active_player_guid_lo;
    uint64_t phi = ipc->active_player_guid_hi;

    if ((plo | phi) != 0 && e->guid_lo == plo && e->guid_hi == phi) {
        uint32_t specId = om_read_u32((uintptr_t)(g_modLoaderBase + RVA_ACTIVE_SPEC_ID + 8));
        if (specId > 0 && specId < 2000) {
            s_pPushnumber(L, (double)specId);
            return 1;
        }
    }

    s_pPushnumber(L, 0.0);
    return 1;
}

int __fastcall dinkr_ObjectHeight(void* L) {
    DinkrIPC* ipc = GetIPC();
    if (!ipc) { s_pPushnumber(L, 0.0); return 1; }
    size_t len = 0;
    const char* guid_str = wk_arg_string(L, 1, &len);
    const OmCacheEntry* e = om_find_by_guid_str(ipc, guid_str);
    if (!e || !e->cgobj) { s_pPushnumber(L, 0.0); return 1; }

    /* Read Movement_C pointer at unit + 0xE0 */
    if (!om_ptr_ok(e->cgobj, CGOBJ_MOVEMENT_C_PTR + 8)) {
        s_pPushnumber(L, 0.0);
        return 1;
    }
    uintptr_t movement_c = om_read_ptr(e->cgobj + CGOBJ_MOVEMENT_C_PTR);
    if (!om_ptr_ok(movement_c, 0x2EC)) {
        s_pPushnumber(L, 0.0);
        return 1;
    }

    /* Collision height at Movement_C + 0x2E8 — always valid when unit exists */
    float height = om_read_f32(movement_c + MOVEMENT_C_COLLISION_HEIGHT);
    s_pPushnumber(L, (double)height);
    return 1;
}

int __fastcall dinkr_ObjectLootable(void* L) {
    DinkrIPC* ipc = GetIPC();
    if (!ipc) { s_pPushboolean(L, 0); return 1; }
    size_t len = 0;
    const char* guid_str = wk_arg_string(L, 1, &len);
    const OmCacheEntry* e = om_find_by_guid_str(ipc, guid_str);
    if (!e || !e->cgobj || !om_ptr_ok(e->cgobj, CGOBJ_DYNAMIC_FLAGS + 1)) {
        s_pPushboolean(L, 0); return 1;
    }
    uint8_t dynFlags = om_read_u8(e->cgobj + CGOBJ_DYNAMIC_FLAGS);
    s_pPushboolean(L, (dynFlags & 0x4) ? 1 : 0);
    return 1;
}

int __fastcall dinkr_GetMapID(void* L) {
    DinkrIPC* ipc = GetIPC();
    if (ipc && ipc->map_id) {
        s_pPushnumber(L, (double)ipc->map_id);
    } else if (g_modLoaderBase) {
        uintptr_t pCtx = om_read_ptr((uintptr_t)(g_modLoaderBase + RVA_g_pZoneMapContext));
        uint32_t mapId = pCtx ? om_read_u32(pCtx + 0x20) : 0;
        s_pPushnumber(L, (double)mapId);
    } else {
        s_pPushnumber(L, 0.0);
    }
    return 1;
}
