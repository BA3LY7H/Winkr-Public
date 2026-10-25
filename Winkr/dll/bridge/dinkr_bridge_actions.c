/* dinkr_bridge_actions.c -- TraceLine, ScreenToWorld, Interact, NativeCast, FaceDirection, etc. */

#include "dinkr_bridge.h"

#include <math.h>

/* ========================================================================
** TraceLine / World_Intersect structs & bridge
** ======================================================================== */

typedef struct {
    float srcX, srcY, srcZ;
    float dstX, dstY, dstZ;
    int64_t flags;            /* 8 bytes — was uint32+reserved in old build */
    uint32_t threadCount;
} DinkrRayInput;

typedef struct {
    float hitX, hitY, hitZ;
    uint32_t unk0C;
    uint64_t unk10;
    float t;              /* MUST init to 1.0f */
    uint32_t unk1C;
    uint64_t hitGuidLo;
    uint64_t hitGuidHi;
    uint32_t unk30;
} DinkrRayResult;

/* World_Intersect (build 66431+).
 * 3 args: (collisionContext, rayStruct, resultStruct) — same layout as old build.
 * Context resolution still being debugged. */
typedef uint8_t (__fastcall *WorldIntersect_t)(int64_t context, DinkrRayInput* ray, DinkrRayResult* result);

/* Resolve the world-frame (collision root) that World_Intersect needs.
 *
 * On 69109 this is NOT a standalone global. Disassembling all 33 callers of
 * World_Intersect shows 32 of them build the context as [base + idx*8 + 0x10]
 * after reading [base + 0x20] — matching our layout — and `base` comes from:
 *
 *     mov rax, [rip -> 0x03CFAB20]   ; WorldFrameUI singleton (== RVA_CAM_MGR)
 *     mov r12, [rax + 0x2B8]         ; <- the world frame
 *
 * So there is one more hop than the old RVA_G_P_WORLD_FRAME assumed. That stale
 * define held a retail 68887 value pointing at garbage, which made every
 * TraceLine take the fail-safe branch and report BLOCKED — paralysing the walker
 * — and a wrong guess at it crashed the client outright.
 *
 * CAM_MGR is a re-derived, live-verified global (riprel recipe 6/6 votes, and
 * dinkr_PatchDay confirms its camera chain PASSes), so deriving from it is far
 * safer than another standalone-global hunt. The legacy direct global is kept as
 * a fallback for builds where it is correct.
 */
#define WORLDFRAMEUI_OFF_WORLDFRAME 0x2B8   /* 69109: [WorldFrameUI+0x2B8] = world frame */

static uintptr_t resolve_world_frame(void) {
    if (!g_modLoaderBase) return 0;

    /* preferred: WorldFrameUI -> +0x2B8 */
    uintptr_t ui = om_read_ptr((uintptr_t)(g_modLoaderBase + RVA_CAM_MGR));
    if (om_ptr_ok(ui, WORLDFRAMEUI_OFF_WORLDFRAME + 8)) {
        uintptr_t wf = om_read_ptr(ui + WORLDFRAMEUI_OFF_WORLDFRAME);
        if (om_ptr_ok(wf, 0x30)) return wf;
    }

    /* legacy: a global pointing straight at the world frame */
    uintptr_t direct = om_read_ptr((uintptr_t)(g_modLoaderBase + RVA_G_P_WORLD_FRAME));
    if (om_ptr_ok(direct, 0x30)) return direct;

    return 0;
}

/* The trace itself, with no Lua stack involved. Declared in nav/dinkr_ray.h so
 * the live navmesh generator can fire rays by the hundred thousand without
 * paying for a Lua round trip per ray — and so this stays the ONLY copy of the
 * world-frame resolution and its safety checks. */
int dinkr_RayCastRaw(float sx, float sy, float sz,
                     float dx, float dy, float dz,
                     unsigned int flags, float* outHit3) {
    if (!g_modLoaderBase) return -1;
    if (!flags) flags = 0x120151;

    /* Resolve terrain and collision context */
    uintptr_t worldFrame = resolve_world_frame();
    if (!om_ptr_ok(worldFrame, 0x30)) return -1;

    uint32_t mapIndex = om_read_u32(worldFrame + 0x20);
    if (mapIndex > 64) return -1;

    /* Validate terrain array bounds before indexed access.
     * Access is at worldFrame + 8*mapIndex + 0x10, so we need worldFrame to be
     * at least (8*(mapIndex+1) + 0x10) = 8*mapIndex + 0x18 bytes readable. */
    size_t terrainNeeded = 8 * (size_t)mapIndex + 0x18;
    if (!om_ptr_ok(worldFrame, terrainNeeded)) return -1;

    /* Validate the context is READABLE, not merely non-NULL. A stale
     * g_pWorldFrame points at a live-but-wrong object, so mapIndex and this
     * context both come back as plausible garbage; World_Intersect then
     * dereferences it and takes the client down — exactly how 69109 crashed
     * (ACCESS_VIOLATION at RVA 0x15251B2, adjacent to World_Intersect).
     * om_ptr_ok is VirtualQuery-backed, so a bad chain now degrades to
     * "unknown" instead of crashing. */
    int64_t context = (int64_t)om_read_ptr(worldFrame + 8 * (uintptr_t)mapIndex + 0x10);
    if (!context || !om_ptr_ok((uintptr_t)context, 0x40)) return -1;

    DinkrRayInput ray;
    memset(&ray, 0, sizeof(ray));
    ray.srcX = sx; ray.srcY = sy; ray.srcZ = sz;
    ray.dstX = dx; ray.dstY = dy; ray.dstZ = dz;
    ray.flags = (int64_t)flags;
    ray.threadCount = 0;

    DinkrRayResult result;
    memset(&result, 0, sizeof(result));
    result.t = 1.0f;

    WorldIntersect_t intersect = (WorldIntersect_t)((uintptr_t)g_modLoaderBase + RVA_WORLD_INTERSECT);
    uint8_t hit = intersect(context, &ray, &result);
    if (!hit) return 0;

    if (outHit3) { outHit3[0] = result.hitX; outHit3[1] = result.hitY; outHit3[2] = result.hitZ; }
    return 1;
}

int __fastcall dinkr_TraceLine_lua(void* L) {
    if (!g_modLoaderBase) { s_pPushnumber(L, 0.0); return 1; }

    float srcX = (float)dinkr_read_stack_number(L, 1);
    float srcY = (float)dinkr_read_stack_number(L, 2);
    float srcZ = (float)dinkr_read_stack_number(L, 3);
    float dstX = (float)dinkr_read_stack_number(L, 4);
    float dstY = (float)dinkr_read_stack_number(L, 5);
    float dstZ = (float)dinkr_read_stack_number(L, 6);

    double flagsArg = dinkr_read_stack_number(L, 7);
    uint32_t flags = (flagsArg > 0) ? (uint32_t)flagsArg : 0x120151;

    float hit[3];
    int rc = dinkr_RayCastRaw(srcX, srcY, srcZ, dstX, dstY, dstZ, flags, hit);

    if (rc < 0) {
        /* Fail-safe: report blocked (non-zero) rather than clear, by handing back
         * the ray ORIGIN. Callers that need to tell this apart from a real hit
         * compare the result against the origin — LiveMesh does exactly that. */
        s_pPushnumber(L, (double)srcX);
        s_pPushnumber(L, (double)srcY);
        s_pPushnumber(L, (double)srcZ);
        return 3;
    }
    if (rc == 0) {
        s_pPushnumber(L, 0.0);
        return 1;
    }
    s_pPushnumber(L, (double)hit[0]);
    s_pPushnumber(L, (double)hit[1]);
    s_pPushnumber(L, (double)hit[2]);
    return 3;
}

/* ========================================================================
** dinkr_ScreenToWorld — unprojects screen coordinates to a world position
**
** Lua: local x, y, z = dinkr_ScreenToWorld(sx, sy)
**   sx, sy: normalized screen coords (0–1), same format as WorldToScreen returns
** Returns: worldX, worldY, worldZ (terrain hit point) or nil if no hit
**
** How it works:
**   1. Inverts the projection to get a view-space ray direction
**   2. Transforms the ray into world space using the camera basis
**   3. Casts the ray from the camera position using World_Intersect (TraceLine)
**   4. Returns the terrain/geometry hit point
** ======================================================================== */

int __fastcall dinkr_ScreenToWorld_lua(void* L) {
    if (!g_modLoaderBase || !g_gameWindow) { s_pPushnil(L); return 1; }

    float sx = (float)dinkr_read_stack_number(L, 1);
    float sy = (float)dinkr_read_stack_number(L, 2);

    /* Optional 3rd arg: collision flags (default 0x120151 matches WorldFrame LOS path) */
    double flagsArg = dinkr_read_stack_number(L, 3);
    uint32_t collisionFlags = (flagsArg > 0) ? (uint32_t)flagsArg : 0x120151;

    /* Read eye + lookAt from WorldFrameUI/CCamera (67088 has multiple vec layouts). */
    float cx, cy, cz, rx, ry, rz, ux, uy, uz, fx, fy, fz;
    uintptr_t wf = om_read_ptr((uintptr_t)(g_modLoaderBase + RVA_CAM_MGR));
    uintptr_t camS2W = resolve_camera_object();
    if (!wf || !camS2W) { s_pPushnil(L); return 1; }

    /* Eye: prefer WorldFrame pos descriptor (+4/+8/+C), fallback to camera vectors. */
    uintptr_t posDesc = om_read_ptr(wf + CAM_OFF_POSDESC);
    int eyeOk = 0;
    if (om_ptr_ok(posDesc, 0x10)) {
        cx = *(float*)(posDesc + 0x4);
        cy = *(float*)(posDesc + 0x8);
        cz = *(float*)(posDesc + 0xC);
        eyeOk = isfinite(cx) && isfinite(cy) && isfinite(cz);
    }
    if (!eyeOk) {
        cx = *(float*)(camS2W + CCAM_OFF_EYE);
        cy = *(float*)(camS2W + CCAM_OFF_EYE + 4);
        cz = *(float*)(camS2W + CCAM_OFF_EYE + 8);
    }

    /* Forward: try both historical layouts (vec4 stride vs vec3 stride). */
    float fwX = *(float*)(camS2W + 0x1C) - *(float*)(camS2W + 0x10);
    float fwY = *(float*)(camS2W + 0x20) - *(float*)(camS2W + 0x14);
    float fwZ = *(float*)(camS2W + 0x24) - *(float*)(camS2W + 0x18);
    float fLen = sqrtf(fwX*fwX + fwY*fwY + fwZ*fwZ);
    if (!(fLen > 0.0001f && isfinite(fLen))) {
        fwX = *(float*)(camS2W + 0x20) - *(float*)(camS2W + 0x14);
        fwY = *(float*)(camS2W + 0x24) - *(float*)(camS2W + 0x18);
        fwZ = *(float*)(camS2W + 0x28) - *(float*)(camS2W + 0x1C);
        fLen = sqrtf(fwX*fwX + fwY*fwY + fwZ*fwZ);
    }
    if (fLen < 0.0001f) { s_pPushnil(L); return 1; }
    fx = fwX / fLen; fy = fwY / fLen; fz = fwZ / fLen;
    rx = fy; ry = -fx; rz = 0.0f;
    float rLen = sqrtf(rx*rx + ry*ry);
    if (rLen < 0.0001f) { s_pPushnil(L); return 1; }
    rx /= rLen; ry /= rLen;
    ux = ry*fz; uy = -rx*fz; uz = rx*fy - ry*fx;

    /* Screen size */
    RECT rc = {0};
    if (pGetClientRect) pGetClientRect(g_gameWindow, &rc);
    float scrW = (float)(rc.right - rc.left);
    float scrH = (float)(rc.bottom - rc.top);
    if (scrW < 1.0f || scrH < 1.0f) { scrW = 1920.0f; scrH = 1080.0f; }
    /* Aspect ratio W/H for software projection (see WorldToScreen comment) */
    float aspect = scrW / scrH;

    float fovRad = *(float*)(camS2W + CCAM_OFF_FOV);
    if (fovRad < 0.1f || fovRad > 3.10f) fovRad = 0.9425f;
    float halfTan = tanf(fovRad * 0.5f);

    /* Invert projection: screen (0-1) -> NDC -> view-space ray direction */
    float ndcX = sx * 2.0f - 1.0f;
    float ndcY = 1.0f - sy * 2.0f;

    float vdX = ndcX * halfTan * aspect;
    float vdY = ndcY * halfTan;
    float vdZ = 1.0f;

    /* View-space direction -> world-space direction */
    float wdX = vdX * rx + vdY * ux + vdZ * fx;
    float wdY = vdX * ry + vdY * uy + vdZ * fy;
    float wdZ = vdX * rz + vdY * uz + vdZ * fz;

    /* Normalize */
    float wdLen = sqrtf(wdX*wdX + wdY*wdY + wdZ*wdZ);
    if (wdLen < 0.0001f) { s_pPushnil(L); return 1; }
    wdX /= wdLen; wdY /= wdLen; wdZ /= wdLen;

    /* Cast ray from camera (max 1000 yards) using same path as TraceLine */
    float maxDist = 1000.0f;
    float dstX = cx + wdX * maxDist;
    float dstY = cy + wdY * maxDist;
    float dstZ = cz + wdZ * maxDist;

    /* Same collision resolution as TraceLine */
    uintptr_t worldFrame = resolve_world_frame();
    if (!om_ptr_ok(worldFrame, 0x30)) { s_pPushnil(L); return 1; }

    uint32_t mapIndex = om_read_u32(worldFrame + 0x20);
    if (mapIndex > 64) { s_pPushnil(L); return 1; }

    size_t worldFrameNeeded = 8 * (size_t)mapIndex + 0x18;
    if (!om_ptr_ok(worldFrame, worldFrameNeeded)) { s_pPushnil(L); return 1; }

    /* same readability check as TraceLine above — a stale world-frame chain must
     * degrade to nil, never reach World_Intersect with a garbage context */
    int64_t context = (int64_t)om_read_ptr(worldFrame + 8 * (uintptr_t)mapIndex + 0x10);
    if (!context || !om_ptr_ok((uintptr_t)context, 0x40)) { s_pPushnil(L); return 1; }

    DinkrRayInput ray;
    memset(&ray, 0, sizeof(ray));
    ray.srcX = cx; ray.srcY = cy; ray.srcZ = cz;
    ray.dstX = dstX; ray.dstY = dstY; ray.dstZ = dstZ;
    ray.flags = (int64_t)collisionFlags;
    ray.threadCount = 0;

    DinkrRayResult result;
    memset(&result, 0, sizeof(result));
    result.t = 1.0f;

    WorldIntersect_t intersect = (WorldIntersect_t)((uintptr_t)g_modLoaderBase + RVA_WORLD_INTERSECT);
    uint8_t hit = intersect(context, &ray, &result);

    if (hit) {
        s_pPushnumber(L, (double)result.hitX);
        s_pPushnumber(L, (double)result.hitY);
        s_pPushnumber(L, (double)result.hitZ);
        return 3;
    }

    s_pPushnil(L);
    return 1;
}

/* ========================================================================
** FaceDirection, ClickPosition, MoveTo— game function call bridges
**
** These call game functions directly (in-process). They MUST run on the
** main thread, which is guaranteed since they're called from Lua during
** normal game loop execution.
** ======================================================================== */

/* InteractUnit — calls game's interact-with-GUID function
 * Params: RCX = GUID* (16 bytes: lo at +0, hi at +8), RDX = interactType (9=default) */
typedef void (__fastcall *InteractUnit_t)(void* targetGuid, int interactType);

int __fastcall dinkr_ObjectInteract(void* L) {
    if (!g_modLoaderBase) return 0;
    DinkrIPC* ipc = GetIPC();
    if (!ipc) return 0;
    size_t len = 0;
    const char* guid_str = wk_arg_string(L, 1, &len);
    const OmCacheEntry* e = om_find_by_guid_str(ipc, guid_str);
    if (!e) return 0;
    if (!e->cgobj || !om_ptr_ok(e->cgobj, CGOBJ_TYPE_BYTE + 1)) return 0;

    struct { uint64_t lo; uint64_t hi; } guid = { e->guid_lo, e->guid_hi };

    /* Resolve by SIGNATURE, not by the hardcoded RVA.
     *
     * RVA_INTERACT_UNIT is still the retail "68887 sig" value — it was never
     * re-derived for Classic 69109. Every other entry in rva_defs.h carries a
     * "69109:" note; this one does not. Calling through it lands on the wrong
     * address, so interaction silently did nothing: the bot would walk to a quest
     * giver and then sit there reporting "interacting...".
     *
     * SIGID_INTERACT_UNIT has a pattern in sig_defs.h, and DinkrGetAddr already
     * falls back to base+RVA when a scan fails (same approach as SIGID_CAM_MGR),
     * so this is strictly better than the raw offset and self-heals across builds. */
    /* REFUSE rather than fall back to the stale RVA.
     *
     * RVA_INTERACT_UNIT has been the 68887 value through 68940, 69109 and 69547,
     * and on 69547 the signature scan finds nothing because the function was
     * rewritten (its distinctive tail -- test rax,rax / mov al,1 / pop rsi /
     * pop rbp / ret -- no longer exists anywhere in the image). Falling back
     * meant CALLING a known-wrong address through a function pointer, which is
     * a crash waiting to happen, not a degraded feature.
     *
     * Failing cleanly turns "the client died mid-quest" into "interact returned
     * 0 and said why", which is the difference between a bug report and a
     * mystery. */
    uintptr_t interactAddr = DinkrGetAddr(SIGID_INTERACT_UNIT);
    if (!interactAddr) {
        DebugLog("[interact] SIGID_INTERACT_UNIT did not resolve and RVA_INTERACT_UNIT is stale "
                 "(68887 value) -- refusing to call. Re-derive it before using interaction.");
        return 0;
    }
    InteractUnit_t interact = (InteractUnit_t)interactAddr;

#if RVA_G_TAINT_IS_VERIFIED
    volatile uintptr_t* pTaint = (volatile uintptr_t*)
        ((uintptr_t)g_modLoaderBase + RVA_G_TAINT_HANDLER_PTR);
    uintptr_t savedTaint = *pTaint;
    *pTaint = 0;

    interact(&guid, 9);  /* interactType 9 = default */

    *pTaint = savedTaint;
#else
    /* g_taint not derived for this build: pass-through (no taint write). */
    interact(&guid, 9);  /* interactType 9 = default */
#endif

    return 0;
}

/* NativeCast — calls the real Spell_C native cast pipeline (no global slot
 * writes, no unit-token resolution, no Lua-stack roundtrip).
 *
 * Lua: dinkr_NativeCast(spellID [, guidString])
 *   spellID    = numeric spell ID
 *   guidString = optional GUID string ("Player-1234-..." or whatever
 *                UnitGUID('player'/'target'/'arena1'/...) returns; nil = self).
 * Returns: boolean (true if pipeline accepted the cast).
 *
 * Pipeline RE'd in build 67186 — see rva_defs.h:
 *   mgr = SpellC_GetLocalManager();
 *   SpellC_CastGuidDirect(mgr, spellID, &guid16, 0, 0);
 *
 * This path is called by CastSpellByName/CastSpellByID Lua handlers and does
 * not touch any targeting slot globals. Use dinkr_SetNPC as fallback when
 * the manager is not yet ready (edge case on rapid successive casts). */
typedef void* (__fastcall *SpellC_GetLocalManager_t)(void);
typedef char  (__fastcall *SpellC_CastGuidDirect_t)(void* mgr,
                                                   unsigned int spellID,
                                                   void* targetGuid16,
                                                   unsigned int castFlags,
                                                   unsigned char bonus);

int __fastcall dinkr_NativeCast_lua(void* L) {
    if (!g_modLoaderBase) {
        s_pPushboolean(L, 0);
        return 1;
    }

    unsigned int spellID = (unsigned int)dinkr_read_stack_number(L, 1);
    if (!spellID) {
        s_pPushboolean(L, 0);
        return 1;
    }

    /* Target GUID — 16 bytes. Zero = self / no target (game uses this
     * convention for SwapDynamicFlightMode etc.). Accepts any GUID string
     * UnitGUID() can return, plus raw "Player-XXXX-YYYY..." strings. */
    struct { uint64_t lo; uint64_t hi; } guid = {0, 0};

    size_t len = 0;
    const char* guid_str = wk_arg_string(L, 2, &len);
    if (guid_str && len > 0) {
        DinkrIPC* ipc = GetIPC();
        if (!ipc) {
            s_pPushboolean(L, 0);
            return 1;
        }
        const OmCacheEntry* e = om_find_by_guid_str(ipc, guid_str);
        if (!e) {
            s_pPushboolean(L, 0);
            return 1;
        }
        if (!e->cgobj || !om_ptr_ok(e->cgobj, CGOBJ_TYPE_BYTE + 1)) {
            s_pPushboolean(L, 0);
            return 1;
        }
        guid.lo = e->guid_lo;
        guid.hi = e->guid_hi;
    }

    SpellC_GetLocalManager_t getMgr =
        (SpellC_GetLocalManager_t)(DinkrGetAddr(SIGID_SPELL_C_GET_LOCAL_MANAGER));
    void* mgr = getMgr();
    if (!mgr || !om_ptr_ok((uintptr_t)mgr, 8)) {
        s_pPushboolean(L, 0);
        return 1;
    }

    SpellC_CastGuidDirect_t cast =
        (SpellC_CastGuidDirect_t)(DinkrGetAddr(SIGID_SPELL_C_CAST_GUID_DIRECT));
    char ok = cast(mgr, spellID, &guid, 0, 0);
    s_pPushboolean(L, ok ? 1 : 0);
    return 1;
}

/* dinkr_SendMovementHeartbeat() — DEPRECATED: movement packet functions removed (broken RVA) */
int __fastcall dinkr_SendMovementHeartbeat_lua(void* L) {
    s_pPushstring(L, "dinkr_SendMovementHeartbeat: no longer supported");
    return 1;
}

/* dinkr_FaceDirection(angle [, sendHeartbeat]) — DEPRECATED: movement packet functions removed (broken RVA) */
/* dinkr_FaceDirection(angleRadians [, guidString]) -> boolean
 *
 * Sets an ABSOLUTE heading by writing the object's facing field (cgobj+0x38C).
 *
 * WHY THIS MATTERS: without it the only way to steer is bang-bang turn keys —
 * hold TurnLeft/TurnRight and hope to release at the right moment. That cannot
 * settle on a heading, so it weaves down straight lines, overshoots corners and
 * can spin out when an avoidance detour fights the path. FaceDirection is what
 * the whole aw1 corpus uses (63k call sites); this bridge was a stub returning
 * "no longer supported", which is why our walker had to fake it.
 *
 * The client reads this field when composing movement packets, so writing it and
 * then holding MoveForward moves in the new direction.
 *
 * Angle is WoW-standard radians: 0 = north (+X), increasing counter-clockwise,
 * normalised here to [0, 2pi) because the client rejects out-of-range values. */
/* MEASURED 2026-08-25 (build 69109, via the walker's /go faceprobe): the previous
 * implementation returned false for EVERY calling convention and never turned the
 * character. Two independent defects, either of which alone was fatal:
 *
 *  1. WRONG FIELD. It wrote cgobj+0x38C (CGOBJ_FACING), a retail-era offset. The
 *     GETTER right next door — dinkr_ObjectFacing, which agrees with the client
 *     to 3 decimals — reads the ECS EntityPosition block at pos_base+0x50. On
 *     this Classic build 0x38C is simply not the field the client uses, so even a
 *     successful write changed nothing observable.
 *
 *  2. WRONG RESOLUTION. The player branch dereferenced RVA_g_activePlayerUnit
 *     directly and bailed when om_ptr_ok() rejected the result — which is what
 *     produced the flat `false`. The OM enumerator does not trust that RVA either:
 *     it resolves the same global through DinkrGetAddr(SIGID_g_activePlayerUnit)
 *     and publishes the answer as ipc->active_player_guid.
 *
 * Both are fixed by doing exactly what the getter does — resolve through the IPC
 * OM cache, then om_resolve_entity_pos_base — and writing pos_base+ENTPOS_FACING.
 * The rule this encodes: a setter must use the same resolution path as the getter
 * that is known to agree with the client, or it is writing into the void.
 *
 * cgobj+0x38C is ALSO written when it looks sane, purely belt-and-braces for any
 * client path that still reads the old field. It is never load-bearing. */
static int dinkr_write_facing(const OmCacheEntry* e, DinkrIPC* ipc, double angle) {
    uintptr_t pos_base = 0;
    if (!e || !ipc) return 0;
    if (!om_resolve_entity_pos_base(ipc, e, &pos_base)) return 0;
    if (!om_ptr_ok(pos_base + ENTPOS_FACING, sizeof(float))) return 0;

    /* The client rejects out-of-range headings, so normalise to [0, 2pi). */
    {
        const double TAU = 6.28318530717958647692;
        double a = angle;
        if (a != a) return 0;                       /* NaN guard */
        while (a < 0.0) a += TAU;
        while (a >= TAU) a -= TAU;

        *(float*)(pos_base + ENTPOS_FACING) = (float)a;

        if (e->cgobj && om_ptr_ok(e->cgobj + CGOBJ_FACING, sizeof(float))) {
            *(float*)(e->cgobj + CGOBJ_FACING) = (float)a;
        }
    }
    return 1;
}

int __fastcall dinkr_FaceDirection_lua(void* L) {
    if (!g_modLoaderBase) { s_pPushboolean(L, 0); return 1; }

    double angle = dinkr_read_stack_number(L, 1);

    /* Optional GUID: default to the player. */
    size_t len = 0;
    const char* guid_str = wk_arg_string(L, 2, &len);

    DinkrIPC* ipc = GetIPC();
    if (!ipc) { s_pPushboolean(L, 0); return 1; }

    const OmCacheEntry* e = NULL;
    if (guid_str && len) {
        e = om_find_by_guid_str(ipc, guid_str);
    } else {
        e = om_find_by_guid_lohi(ipc, ipc->active_player_guid_lo,
                                      ipc->active_player_guid_hi);
    }

    s_pPushboolean(L, dinkr_write_facing(e, ipc, angle) ? 1 : 0);
    return 1;
}

/* Spell_C terrain click handler (RVA 0x1F7BF70)
 * Checks (targetingFlags & 0x60) and targetingGUID, writes position to spell object,
 * clears targeting flags, and finalizes the pending AOE cast.
 * a1 = GUID128* (null for terrain), a2 = Vec3*, a3 = flag, a4 = cast context ptr */
typedef char (__fastcall *HandleTerrainClick_t)(void* targetGUID, float* position, char flag, void* castContext);

int __fastcall dinkr_ClickPosition_lua(void* L) {
    if (!g_modLoaderBase) {
        s_pPushboolean(L, 0);
        return 1;
    }

    float x = (float)dinkr_read_stack_number(L, 1);
    float y = (float)dinkr_read_stack_number(L, 2);
    float z = (float)dinkr_read_stack_number(L, 3);

    uint8_t nullGuid[16];
    memset(nullGuid, 0, sizeof(nullGuid));
    float pos[3] = { x, y, z };

    void* castCtx = (void*)((uintptr_t)g_modLoaderBase + RVA_SPELL_CLICK_CONTEXT);

    /* Resolve by SIGNATURE and REFUSE if it fails, rather than calling the raw
     * RVA. RVA_HANDLE_TERRAIN_CLICK has carried its 68887 value through 68940,
     * 69109 and 69547, and its signature has not matched since -- so this call
     * site was jumping to an address known to be three builds stale, through a
     * function pointer, with no guard. That is a client crash, not a broken
     * feature.
     *
     * Deriving it needs the PREVIOUS build's dump for call-ordinal diffing
     * (tools/derive_validators.py's method); only the 69547 dump survives here,
     * and pattern recovery gave a candidate whose body reads like a container
     * bounds check rather than a click handler, which is not good enough to
     * call blind. */
    uintptr_t clickAddr = DinkrGetAddr(SIGID_HANDLE_TERRAIN_CLICK);
    if (!clickAddr) {
        DebugLog("[terrainclick] SIGID_HANDLE_TERRAIN_CLICK did not resolve and "
                 "RVA_HANDLE_TERRAIN_CLICK is stale (68887 value) -- refusing to call.");
        s_pPushboolean(L, 0);
        return 1;
    }
    HandleTerrainClick_t click = (HandleTerrainClick_t)clickAddr;

    char result;
#if RVA_G_TAINT_IS_VERIFIED
    volatile uintptr_t* pTaint = (volatile uintptr_t*)
        ((uintptr_t)g_modLoaderBase + RVA_G_TAINT_HANDLER_PTR);
    uintptr_t savedTaint = *pTaint;
    *pTaint = 0;

    result = click(nullGuid, pos, 0, castCtx);

    *pTaint = savedTaint;
#else
    /* g_taint not derived for this build: pass-through (no taint write). */
    result = click(nullGuid, pos, 0, castCtx);
#endif

    s_pPushboolean(L, result ? 1 : 0);
    return 1;
}

/* dinkr_SpellIsTargeting — returns true when spell ground-targeting is active */
int __fastcall dinkr_SpellIsTargeting_lua(void* L) {
    if (!g_modLoaderBase) {
        s_pPushboolean(L, 0);
        return 1;
    }
    uint32_t stFlags = om_read_u32((uintptr_t)(g_modLoaderBase + RVA_SPELL_TARGETING_FLAGS));
    s_pPushboolean(L, (stFlags & 0x60) ? 1 : 0);
    return 1;
}

/* SpellStopTargeting — the game's real cancel function, cleans up cursor/reticle/GUID properly */
typedef void (__fastcall *SpellStopTargeting_t)(void);

/* dinkr_SpellCancelTargeting — cancels pending spell targeting via the game's real function */
int __fastcall dinkr_SpellCancelTargeting_lua(void* L) {
    (void)L;
    if (!g_modLoaderBase) return 0;
    uint32_t stFlags = om_read_u32((uintptr_t)(g_modLoaderBase + RVA_SPELL_TARGETING_FLAGS));
    if (stFlags & 0x60) {
        SpellStopTargeting_t stopTargeting = (SpellStopTargeting_t)((uintptr_t)g_modLoaderBase + RVA_SPELL_STOP_TARGETING);

#if RVA_G_TAINT_IS_VERIFIED
        volatile uintptr_t* pTaint = (volatile uintptr_t*)
            ((uintptr_t)g_modLoaderBase + RVA_G_TAINT_HANDLER_PTR);
        uintptr_t savedTaint = *pTaint;
        *pTaint = 0;

        stopTargeting();

        *pTaint = savedTaint;
#else
        /* g_taint not derived for this build: pass-through (no taint write). */
        stopTargeting();
#endif
    }
    return 0;
}

/* dinkr_SpellTargetingReady — returns true when targeting is active AND GUID is populated
 * (Click will be silently dropped if GUID is still zero on the same frame as CastSpellByName) */
int __fastcall dinkr_SpellTargetingReady_lua(void* L) {
    if (!g_modLoaderBase) {
        s_pPushboolean(L, 0);
        return 1;
    }
    uint32_t stFlags = om_read_u32((uintptr_t)(g_modLoaderBase + RVA_SPELL_TARGETING_FLAGS));
    if (!(stFlags & 0x60)) {
        s_pPushboolean(L, 0);
        return 1;
    }
    uint64_t stGuid = om_read_u64((uintptr_t)(g_modLoaderBase + RVA_SPELL_TARGETING_GUID));
    s_pPushboolean(L, stGuid ? 1 : 0);
    return 1;
}
