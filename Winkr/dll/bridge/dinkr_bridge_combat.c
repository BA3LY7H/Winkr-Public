/* dinkr_bridge_combat.c -- UnitAuras + Missiles */

#include "dinkr_bridge.h"

/* ========================================================================
** dinkr_UnitAuras -- direct memory read of unit aura data
**
** Lua: local auras = dinkr_UnitAuras(guidString, filter)
** filter: "HELPFUL", "HARMFUL", or nil (all)
** Returns: array of aura tables, or nil if unit not found
** ======================================================================== */

int __fastcall dinkr_UnitAuras(void* L) {
    DinkrIPC* ipc = GetIPC();
    if (!ipc) { s_pPushnil(L); return 1; }

    /* Classic 68940: aura offsets RE-DERIVED + live-validated (array@cgobj+0x8E0,
     * count@+0x8E8, stride 0xD8, spellId@0xA8) -- probe returned real spell IDs
     * (465 Devotion Aura, 20598 The Human Spirit). Bridge is LIVE. */

    /* Arg 1: guidString */
    size_t len = 0;
    const char* guid_str = wk_arg_string(L, 1, &len);
    if (!guid_str || len == 0) { s_pPushnil(L); return 1; }

    /* Arg 2: filter (optional) -- "HELPFUL", "HARMFUL", or nil */
    size_t flen = 0;
    const char* filter = wk_arg_string(L, 2, &flen);
    uint16_t filterMask = 0;
    if (filter && flen >= 4) {
        if (filter[0] == 'H' && filter[1] == 'E') /* HELPFUL */
            filterMask = AURA_FLAG_HELPFUL;
        else if (filter[0] == 'H' && filter[1] == 'A') /* HARMFUL */
            filterMask = AURA_FLAG_HARMFUL;
    }

    /* Resolve OM cache entry */
    const OmCacheEntry* e = om_find_by_guid_str(ipc, guid_str);
    if (!e) { s_pPushnil(L); return 1; }

    uintptr_t cgobj = e->cgobj;
    if (!om_ptr_ok(cgobj + CGOBJ_AURA_ARRAY_PTR, 12)) { s_pPushnil(L); return 1; }

    /* Read aura array pointer and count */
    uintptr_t aura_array = om_read_ptr(cgobj + CGOBJ_AURA_ARRAY_PTR);
    uint32_t aura_count = om_read_u32(cgobj + CGOBJ_AURA_COUNT);

    if (!aura_array || aura_count == 0) {
        s_pCreatetable(L, 0, 0);
        return 1;
    }
    if (aura_count > 255) aura_count = 255;

    /* Validate full aura array memory range */
    if (!om_ptr_ok(aura_array, (size_t)aura_count * AURA_STRUCT_SIZE)) {
        s_pPushnil(L); return 1;
    }

    /* Active player GUID for isFromPlayerOrPlayerPet comparison. 68887:
     * ActivePlayerGUID is no longer a raw global -- use active_player_guid
     * captured by the OM enumerator from the CGTYPE_ACTIVE_PLAYER object. */
    uint64_t playerLo = 0, playerHi = 0;
    { DinkrIPC* pip = GetIPC(); if (pip) { playerLo = pip->active_player_guid_lo; playerHi = pip->active_player_guid_hi; } }

    DWORD tickNow = (DWORD)GetTickCount();

    /* Result table (array of aura sub-tables) */
    s_pCreatetable(L, (int)aura_count, 0);
    int ri = 1;

    typedef struct {
        uint64_t lo;
        uint64_t hi;
        char str[80];
    } AuraCasterCache;
    AuraCasterCache caster_cache[16];
    int caster_cache_count = 0;

    for (uint32_t i = 0; i < aura_count; i++) {
        uintptr_t a = aura_array + (uintptr_t)i * AURA_STRUCT_SIZE;

        uint32_t spellId = om_read_u32(a + AURA_OFF_SPELL_ID);
        if (spellId == 0) continue;

        uint16_t flags = om_read_u16(a + AURA_OFF_FLAGS);
        if (filterMask && !(flags & filterMask)) continue;

        int isHelpful = (flags & AURA_FLAG_HELPFUL) != 0;
        int isHarmful = (flags & AURA_FLAG_HARMFUL) != 0;

        int32_t  duration_ms = (int32_t)om_read_u32(a + AURA_OFF_DURATION);
        uint32_t endTime_ms  = om_read_u32(a + AURA_OFF_END_TIME);
        uint8_t  stacks      = om_read_u8(a + AURA_OFF_STACKS);
        uint32_t instanceId  = om_read_u32(a + AURA_OFF_INSTANCE_ID);

        uint64_t casterLo = om_read_u64(a + AURA_OFF_CASTER_GUID);
        uint64_t casterHi = om_read_u64(a + AURA_OFF_CASTER_GUID + 8);

        /* Resolve caster GUID string: OM cache first, then local formatter */
        const char* casterStr = "";
        char casterBuf[80];
        casterBuf[0] = '\0';
        int cached_caster_hit = 0;
        if (casterLo || casterHi) {
            for (int ci = 0; ci < caster_cache_count; ci++) {
                if (caster_cache[ci].lo == casterLo && caster_cache[ci].hi == casterHi) {
                    casterStr = caster_cache[ci].str;
                    cached_caster_hit = 1;
                    break;
                }
            }
        }

        if (!cached_caster_hit) {
            const OmCacheEntry* ce = om_find_by_guid_lohi(ipc, casterLo, casterHi);
            if (ce) {
                OmCacheEntry* ce_mut = (OmCacheEntry*)ce;
                om_ensure_guid_formatted(ce_mut);
                if (ce_mut->guid_str[0]) {
                    casterStr = ce_mut->guid_str;
                }
            }
            if (!casterStr[0] && (casterLo || casterHi)) {
                int w = WowGuid_Format(casterHi, casterLo, casterBuf, sizeof(casterBuf));
                if (w > 0 && w < (int)sizeof(casterBuf)) casterStr = casterBuf;
            }
            if (casterStr[0] && caster_cache_count < (int)(sizeof(caster_cache) / sizeof(caster_cache[0]))) {
                caster_cache[caster_cache_count].lo = casterLo;
                caster_cache[caster_cache_count].hi = casterHi;
                snprintf(caster_cache[caster_cache_count].str,
                         sizeof(caster_cache[caster_cache_count].str), "%s", casterStr);
                caster_cache_count++;
            }
        }

        int isFromPlayer = (playerLo && casterLo == playerLo && casterHi == playerHi) ? 1 : 0;

        double durSec = (duration_ms > 0) ? (double)duration_ms / 1000.0 : 0.0;
        double remainSec = 0.0;
        if (endTime_ms > 0) {
            int32_t rem = (int32_t)(endTime_ms - tickNow);
            remainSec = (rem > 0) ? (double)rem / 1000.0 : 0.0;
        }

        /* Build sub-table with named fields (17 entries) */
        s_pCreatetable(L, 0, 17);

        s_pPushnumber(L, (double)spellId);
        s_pSetField(L, -2, "spellId");

        s_pPushnumber(L, durSec);
        s_pSetField(L, -2, "duration");

        s_pPushnumber(L, remainSec);
        s_pSetField(L, -2, "_remainingSec");

        /* expirationTime: compute using GetTime()-based epoch.
         * endTime_ms is based on GetTickCount; convert to "GetTime" seconds
         * by computing an offset from now. Lua side uses GetTime() for reference. */
        double expTime = 0.0;
        if (endTime_ms > 0 && remainSec > 0.0) {
            /* remainSec is how long until expiry; Lua's GetTime() is seconds since login.
             * We don't have GetTime() here, so set expirationTime = remainSec (Lua can add GetTime()). */
            expTime = remainSec;
        }
        s_pPushnumber(L, expTime);
        s_pSetField(L, -2, "expirationTime");

        s_pPushnumber(L, (double)stacks);
        s_pSetField(L, -2, "applications");

        s_pPushstring(L, casterStr);
        s_pSetField(L, -2, "sourceUnit");

        s_pPushnumber(L, (double)instanceId);
        s_pSetField(L, -2, "auraInstanceID");

        s_pPushboolean(L, isHelpful);
        s_pSetField(L, -2, "isHelpful");

        s_pPushboolean(L, isHarmful);
        s_pSetField(L, -2, "isHarmful");

        s_pPushstring(L, "");
        s_pSetField(L, -2, "name");

        s_pPushnumber(L, 0.0);
        s_pSetField(L, -2, "icon");

        s_pPushstring(L, "");
        s_pSetField(L, -2, "dispelName");

        s_pPushboolean(L, 0);
        s_pSetField(L, -2, "isStealable");

        s_pPushboolean(L, 0);
        s_pSetField(L, -2, "isBossAura");

        s_pPushboolean(L, isFromPlayer);
        s_pSetField(L, -2, "isFromPlayerOrPlayerPet");

        s_pPushnumber(L, 1.0);
        s_pSetField(L, -2, "timeMod");

        /* Insert sub-table into result array */
        s_pRawseti(L, -2, ri++);
    }

    return 1;
}

/* ========================================================================
** dinkr_Missiles — walk the in-flight missile linked list
**
** Lua: local missiles = dinkr_Missiles()
** Returns: array of missile tables (ipairs-compatible), or empty table
**
** CMissile is a pool-allocated doubly-linked list (NOT part of the ECS OM).
** Head pointer: g_MissileInFlightListHead. pNext at +0x280.
**
** Offsets are sourced from MISSILE_OFF_* in shared/om_types.h (build 67088,
** verified via sukuna IDA-MCP reversal). The earlier inline CMISSILE_*
** table was 10.x-era and read AreaTriggerCreatePropertiesId as spellId.
**
** Position triplet labelling (+0x84/+0x90/+0x9C) is sukuna's best-guess
** (source / curr / target). Verify live with a Frostbolt cast before
** trusting in production.
** ======================================================================== */

int __fastcall dinkr_Missiles(void* L) {
    if (!g_modLoaderBase) { s_pPushnil(L); return 1; }

#if !RVA_OM_STRUCT_IS_VERIFIED
    /* Classic: g_MissileInFlightListHead + MISSILE_OFF_* are stale retail values.
     * Walking them reads a garbage "linked list" -> the vendored table builder is
     * forced into the hash path with rehashing on junk -> luaH_getnum crash.
     * Return an empty table until the missile struct is re-derived for 68940. */
    s_pCreatetable(L, 0, 0); return 1;
#endif

    uintptr_t headAddr = (uintptr_t)(g_modLoaderBase + RVA_g_MissileInFlightListHead);
    if (!om_ptr_ok(headAddr, 8)) { s_pCreatetable(L, 0, 0); return 1; }

    uintptr_t headPtrVal = headAddr;          /* sentinel for cycle detection */
    uintptr_t missile = om_read_ptr(headAddr);

    s_pCreatetable(L, 32, 0);
    int ri = 1;
    int safety = 256;

    while (missile && missile != headPtrVal && safety-- > 0) {
        if (!om_ptr_ok(missile, MISSILE_STRUCT_SIZE)) break;

        uint64_t casterLo = om_read_u64(missile + MISSILE_OFF_CASTER_LO);
        uint64_t casterHi = om_read_u64(missile + MISSILE_OFF_CASTER_HI);
        uint64_t targetLo = om_read_u64(missile + MISSILE_OFF_TARGET_LO);
        uint64_t targetHi = om_read_u64(missile + MISSILE_OFF_TARGET_HI);

        /* Canonical spell id at +0x1C4 (IDA-confirmed: HasPendingMissiles reads this).
         * +0x64 is SpellVisualID (NOT a spell ID!) — do NOT use as fallback.
         * +0x68 is SpellVisualMissileID. +0x40 is AreaTriggerCreatePropertiesId. */
        uint32_t spellId    = om_read_u32(missile + MISSILE_OFF_SPELL_ID);
        uint32_t spellVisId = om_read_u32(missile + MISSILE_OFF_SPELL_VISUAL_ID);
        uint32_t spellVisMissileId = om_read_u32(missile + MISSILE_OFF_SPELL_VIS_MISSILE_ID);
        uint32_t atPropsId  = om_read_u32(missile + MISSILE_OFF_AT_PROPS_ID);
        uint32_t flags      = om_read_u32(missile + MISSILE_OFF_FLAGS);
        uint32_t flags2     = om_read_u32(missile + MISSILE_OFF_FLAGS2);
        uint32_t launchTime = om_read_u32(missile + MISSILE_OFF_LAUNCH_TIME);
        float    progress   = om_read_f32(missile + MISSILE_OFF_PROGRESS);

        /* Position triplet — IDA-verified in FireMissiles (build 67088):
         *   +0x84 = current (animated per-frame by trajectory engine)
         *   +0x90 = source  (static after init = launch origin)
         *   +0xB4 = target  (impact point, set from Launch args) */
        float srcX = om_read_f32(missile + MISSILE_OFF_SOURCE_X);
        float srcY = om_read_f32(missile + MISSILE_OFF_SOURCE_Y);
        float srcZ = om_read_f32(missile + MISSILE_OFF_SOURCE_Z);

        float curX = om_read_f32(missile + MISSILE_OFF_CURR_X);
        float curY = om_read_f32(missile + MISSILE_OFF_CURR_Y);
        float curZ = om_read_f32(missile + MISSILE_OFF_CURR_Z);

        float tgtX = om_read_f32(missile + MISSILE_OFF_TARGET_X);
        float tgtY = om_read_f32(missile + MISSILE_OFF_TARGET_Y);
        float tgtZ = om_read_f32(missile + MISSILE_OFF_TARGET_Z);

        float dirX = om_read_f32(missile + MISSILE_OFF_DIR_X);
        float dirY = om_read_f32(missile + MISSILE_OFF_DIR_Y);
        float dirZ = om_read_f32(missile + MISSILE_OFF_DIR_Z);

        /* Synthetic stable id: hash(caster_lo, spell_id, launch_time_ms) */
        uint32_t missileId = (uint32_t)(casterLo ^ (casterLo >> 32))
                           ^ (spellId * 2654435761u)
                           ^ (launchTime * 0x9E3779B1u);

        /* Format GUIDs */
        char casterStr[80] = "";
        char targetStr[80] = "";
        if (casterLo || casterHi) {
            int w = WowGuid_Format(casterHi, casterLo, casterStr, sizeof(casterStr));
            if (w <= 0 || w >= (int)sizeof(casterStr)) casterStr[0] = '\0';
        }
        if (targetLo || targetHi) {
            int w = WowGuid_Format(targetHi, targetLo, targetStr, sizeof(targetStr));
            if (w <= 0 || w >= (int)sizeof(targetStr)) targetStr[0] = '\0';
        }

        /* Build sub-table */
        s_pCreatetable(L, 0, 25);

        s_pPushnumber(L, (double)spellId);
        s_pSetField(L, -2, "spellId");

        s_pPushnumber(L, (double)spellVisId);
        s_pSetField(L, -2, "spellVisualId");

        s_pPushnumber(L, (double)spellVisMissileId);
        s_pSetField(L, -2, "spellVisualMissileId");

        s_pPushnumber(L, (double)atPropsId);
        s_pSetField(L, -2, "areaTriggerCreatePropsId");

        s_pPushnumber(L, (double)missileId);
        s_pSetField(L, -2, "missileId");

        s_pPushstring(L, casterStr);
        s_pSetField(L, -2, "caster");

        s_pPushstring(L, targetStr);
        s_pSetField(L, -2, "target");

        /* "x/y/z" = current interpolated position (what callers expect to
         * draw the missile at right now). */
        s_pPushnumber(L, (double)curX);
        s_pSetField(L, -2, "x");
        s_pPushnumber(L, (double)curY);
        s_pSetField(L, -2, "y");
        s_pPushnumber(L, (double)curZ);
        s_pSetField(L, -2, "z");

        s_pPushnumber(L, (double)srcX);
        s_pSetField(L, -2, "sourceX");
        s_pPushnumber(L, (double)srcY);
        s_pSetField(L, -2, "sourceY");
        s_pPushnumber(L, (double)srcZ);
        s_pSetField(L, -2, "sourceZ");

        /* "impactX/Y/Z" kept for back-compat with awful2; aliases targetX/Y/Z. */
        s_pPushnumber(L, (double)tgtX);
        s_pSetField(L, -2, "impactX");
        s_pPushnumber(L, (double)tgtY);
        s_pSetField(L, -2, "impactY");
        s_pPushnumber(L, (double)tgtZ);
        s_pSetField(L, -2, "impactZ");

        s_pPushnumber(L, (double)tgtX);
        s_pSetField(L, -2, "targetX");
        s_pPushnumber(L, (double)tgtY);
        s_pSetField(L, -2, "targetY");
        s_pPushnumber(L, (double)tgtZ);
        s_pSetField(L, -2, "targetZ");

        s_pPushnumber(L, (double)dirX);
        s_pSetField(L, -2, "dirX");
        s_pPushnumber(L, (double)dirY);
        s_pSetField(L, -2, "dirY");
        s_pPushnumber(L, (double)dirZ);
        s_pSetField(L, -2, "dirZ");

        s_pPushnumber(L, (double)progress);
        s_pSetField(L, -2, "progress");

        s_pPushnumber(L, (double)flags);
        s_pSetField(L, -2, "flags");

        s_pPushnumber(L, (double)flags2);
        s_pSetField(L, -2, "flags2");

        s_pPushnumber(L, (double)launchTime);
        s_pSetField(L, -2, "fireTimeMS");
        s_pPushnumber(L, (double)launchTime);
        s_pSetField(L, -2, "launchTimeMS");

        s_pRawseti(L, -2, ri++);

        missile = om_read_ptr(missile + MISSILE_LIST_NEXT_OFF);
    }

    return 1;
}
