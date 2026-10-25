/* dinkr_bridge_camera.c -- Camera data reading + WorldToScreen projection */

#include "dinkr_bridge.h"
#include "core/dinkr_scanner.h"   /* DinkrGetAddr(SIGID_CAM_MGR) — self-healing camera singleton */

#include <math.h>

/* ========================================================================
** Camera / projection (67088).
**
** WorldFrameUI__Ctor (0x7FF640810227): [worldFrameUI+0x4B0] = CCamera*
** Projection math in sub_7FF640817E80 uses WorldFrameUI matrix columns
** stored at +0x388, +0x398, +0x3A8, +0x3B8.
** ======================================================================== */

static uintptr_t resolve_worldframe_ui(void) {
    if (!g_modLoaderBase) return 0;
    /* Self-healing: CAM_MGR resolves via RIP-relative recipe (8/8 votes on 68887);
     * DinkrGetAddr falls back to base+RVA_CAM_MGR when the scan hasn't run / sig fails. */
    uintptr_t p = DinkrGetAddr(SIGID_CAM_MGR);
    if (!p) p = (uintptr_t)(g_modLoaderBase + RVA_CAM_MGR);
    uintptr_t wf = om_read_ptr(p);
    if (!om_ptr_ok(wf, 0x3C4 + 4)) return 0;
    return wf;
}

uintptr_t resolve_camera_object(void) {
    uintptr_t wf = resolve_worldframe_ui();
    if (!om_ptr_ok(wf, CAM_OFF_CCAMERA + 8)) return 0;
    uintptr_t cam = om_read_ptr(wf + CAM_OFF_CCAMERA);
    if (!om_ptr_ok(cam, CCAM_OFF_FOV + 4)) return 0;
    return cam;
}

int __fastcall dinkr_CameraPosition_lua(void* L) {
    if (!g_modLoaderBase) {
        s_pPushnumber(L, 0.0);
        s_pPushnumber(L, 0.0);
        s_pPushnumber(L, 0.0);
        return 3;
    }

    uintptr_t cam = resolve_camera_object();
    if (!cam) {
        s_pPushnumber(L, 0.0);
        s_pPushnumber(L, 0.0);
        s_pPushnumber(L, 0.0);
        return 3;
    }

    float cx = *(float*)(cam + CCAM_OFF_EYE);
    float cy = *(float*)(cam + CCAM_OFF_EYE + 4);
    float cz = *(float*)(cam + CCAM_OFF_EYE + 8);
    s_pPushnumber(L, (double)cx);
    s_pPushnumber(L, (double)cy);
    s_pPushnumber(L, (double)cz);
    return 3;
}

/* Diagnostic: comprehensive camera state dump for debugging.
 * Call from Lua: local diag = dinkr_CameraDiag()
 * Returns a multi-line string with ALL camera chain data, pointers,
 * matrix values, viewport, origin bias — everything needed to diagnose
 * W2S/S2W issues without recompiling. */
int __fastcall dinkr_CameraDiag_lua(void* L) {
    char buf[4096];
    if (!g_modLoaderBase) {
        s_pPushstring(L, "g_modLoaderBase is NULL");
        return 1;
    }

    int n = 0;
    uintptr_t base = (uintptr_t)g_modLoaderBase;

    /* --- Pointer chain --- */
    uintptr_t wfPtr = base + RVA_CAM_MGR;
    uintptr_t wf = om_read_ptr(wfPtr);
    n += snprintf(buf + n, sizeof(buf) - n,
        "=== CAMERA DIAG (build %d) ===\n"
        "Base: 0x%llX\n"
        "RVA_CAM_MGR: 0x%X -> WF*@0x%llX = 0x%llX\n",
        EXPECTED_BUILD, (unsigned long long)base,
        (unsigned)RVA_CAM_MGR, (unsigned long long)wfPtr, (unsigned long long)wf);

    if (!om_ptr_ok(wf, 0x4C0)) {
        n += snprintf(buf + n, sizeof(buf) - n, "WorldFrame: INVALID (0x%llX)\n", (unsigned long long)wf);
        s_pPushstring(L, buf);
        return 1;
    }

    uintptr_t cam = om_read_ptr(wf + CAM_OFF_CCAMERA);
    uintptr_t posDesc = om_read_ptr(wf + CAM_OFF_POSDESC);
    n += snprintf(buf + n, sizeof(buf) - n,
        "WF+0x%X (CCamera*): 0x%llX\n"
        "WF+0x%X (PosDesc*): 0x%llX\n",
        (unsigned)CAM_OFF_CCAMERA, (unsigned long long)cam,
        (unsigned)CAM_OFF_POSDESC, (unsigned long long)posDesc);

    /* --- CCamera fields --- */
    if (om_ptr_ok(cam, 0x44)) {
        float ex = *(float*)(cam + CCAM_OFF_EYE),     ey = *(float*)(cam + CCAM_OFF_EYE + 4),     ez = *(float*)(cam + CCAM_OFF_EYE + 8);
        float lx = *(float*)(cam + CCAM_OFF_LOOKAT),  ly = *(float*)(cam + CCAM_OFF_LOOKAT + 4),  lz = *(float*)(cam + CCAM_OFF_LOOKAT + 8);
        float fov = *(float*)(cam + CCAM_OFF_FOV);
        float dx = lx - ex, dy = ly - ey, dz = lz - ez;
        float dist = sqrtf(dx*dx + dy*dy + dz*dz);
        n += snprintf(buf + n, sizeof(buf) - n,
            "--- CCamera ---\n"
            "Eye (+0x%X): %.4f, %.4f, %.4f\n"
            "LookAt (+0x%X): %.4f, %.4f, %.4f\n"
            "Fwd (norm): %.4f, %.4f, %.4f (len=%.4f)\n"
            "FovRad (+0x%X): %.6f (%.1f deg)\n",
            CCAM_OFF_EYE, ex, ey, ez,
            CCAM_OFF_LOOKAT, lx, ly, lz,
            dist > 0.001f ? dx/dist : 0, dist > 0.001f ? dy/dist : 0, dist > 0.001f ? dz/dist : 0, dist,
            CCAM_OFF_FOV, fov, fov * 57.2957795f);
    } else {
        n += snprintf(buf + n, sizeof(buf) - n, "CCamera: INVALID\n");
    }

    /* --- PosDesc (Lua userdata fast path for eye pos) --- */
    if (om_ptr_ok(posDesc, 0x10)) {
        float px = *(float*)(posDesc + 0x4), py = *(float*)(posDesc + 0x8), pz = *(float*)(posDesc + 0xC);
        n += snprintf(buf + n, sizeof(buf) - n,
            "--- PosDesc ---\n"
            "Pos (+4/+8/+C): %.4f, %.4f, %.4f\n", px, py, pz);
    } else {
        n += snprintf(buf + n, sizeof(buf) - n, "PosDesc: NULL/INVALID\n");
    }

    /* --- View-Projection matrix (4 columns, 4 floats each) --- */
    n += snprintf(buf + n, sizeof(buf) - n, "--- VP Matrix (WF+0x%X) ---\n", (unsigned)WORLDFRAME_OFF_VIEWPROJ);
    const float* m = (const float*)(wf + WORLDFRAME_OFF_VIEWPROJ);
    if (om_ptr_ok((uintptr_t)m, 64)) {
        for (int col = 0; col < 4; col++) {
            n += snprintf(buf + n, sizeof(buf) - n,
                "Col%d: %.6f, %.6f, %.6f, %.6f\n",
                col, m[col*4+0], m[col*4+1], m[col*4+2], m[col*4+3]);
        }
    } else {
        n += snprintf(buf + n, sizeof(buf) - n, "VP Matrix: UNREADABLE\n");
    }

    /* --- Origin bias --- */
    const float* origin = (const float*)(base + RVA_WORLD_ORIGIN_BIAS);
    if (om_ptr_ok((uintptr_t)origin, 12)) {
        n += snprintf(buf + n, sizeof(buf) - n,
            "--- Origin Bias (RVA 0x%X) ---\n"
            "Origin: %.4f, %.4f, %.4f\n",
            (unsigned)RVA_WORLD_ORIGIN_BIAS, origin[0], origin[1], origin[2]);
    } else {
        n += snprintf(buf + n, sizeof(buf) - n, "Origin Bias: UNREADABLE\n");
    }

    /* --- Viewport extents --- */
    n += snprintf(buf + n, sizeof(buf) - n, "--- Viewport (WF+0x38..0x44) ---\n");
    if (om_ptr_ok(wf + 0x38, 16)) {
        float minX = *(float*)(wf + WFUI_OFF_VIEWPORT_MIN_X);
        float minY = *(float*)(wf + WFUI_OFF_VIEWPORT_MIN_Y);
        float maxX = *(float*)(wf + WFUI_OFF_VIEWPORT_MAX_X);
        float maxY = *(float*)(wf + WFUI_OFF_VIEWPORT_MAX_Y);
        n += snprintf(buf + n, sizeof(buf) - n,
            "Min: %.2f, %.2f  Max: %.2f, %.2f  (%.0fx%.0f)\n",
            minX, minY, maxX, maxY, maxX - minX, maxY - minY);
    }

    /* --- Window client rect --- */
    if (g_gameWindow) {
        RECT rc = {0};
        if (pGetClientRect) pGetClientRect(g_gameWindow, &rc);
        n += snprintf(buf + n, sizeof(buf) - n,
            "--- Window ---\n"
            "HWND: 0x%llX  Client: %ldx%ld\n",
            (unsigned long long)(uintptr_t)g_gameWindow,
            rc.right - rc.left, rc.bottom - rc.top);
    }

    /* --- Quick W2S sanity check: project player pos if available --- */
    n += snprintf(buf + n, sizeof(buf) - n, "--- W2S Self-Test ---\n");
    if (om_ptr_ok(wf, WORLDFRAME_OFF_VIEWPROJ + 64) && om_ptr_ok((uintptr_t)origin, 12) && om_ptr_ok(cam, 0x20)) {
        float ex = *(float*)(cam + CCAM_OFF_EYE), ey = *(float*)(cam + CCAM_OFF_EYE + 4), ez = *(float*)(cam + CCAM_OFF_EYE + 8);
        float testX = ex, testY = ey, testZ = ez - 2.0f; /* 2 units below eye */
        float ox = origin[0], oy = origin[1], oz = origin[2];
        float vx = testX - ox, vy = testY - oy, vz = testZ - oz;
        float cX = m[0]*vx + m[4]*vy + m[8]*vz;
        float cY = m[1]*vx + m[5]*vy + m[9]*vz;
        float cW = m[3]*vx + m[7]*vy + m[11]*vz;
        if (cW > 0.001f) {
            float sx = (cX/cW + 1.0f) * 0.5f;
            float sy = (1.0f - cY/cW) * 0.5f;
            n += snprintf(buf + n, sizeof(buf) - n,
                "Test(eye-2z): world(%.1f,%.1f,%.1f) -> clip(%.4f,%.4f,w=%.4f) -> screen(%.4f,%.4f) %s\n",
                testX, testY, testZ, cX, cY, cW, sx, sy,
                (sx > 0 && sx < 1 && sy > 0 && sy < 1) ? "OK" : "OFF-SCREEN");
        } else {
            n += snprintf(buf + n, sizeof(buf) - n, "Test: behind camera (clipW=%.4f)\n", cW);
        }
    } else {
        n += snprintf(buf + n, sizeof(buf) - n, "Test: skipped (ptrs invalid)\n");
    }

    s_pPushstring(L, buf);
    return 1;
}

int __fastcall dinkr_WorldToScreen_lua(void* L) {
    if (!g_modLoaderBase || !g_gameWindow) {
        s_pPushnumber(L, 0.0);
        s_pPushnumber(L, 0.0);
        s_pPushboolean(L, 0);
        return 3;
    }

    float wx = (float)dinkr_read_stack_number(L, 1);
    float wy = (float)dinkr_read_stack_number(L, 2);
    float wz = (float)dinkr_read_stack_number(L, 3);

    uintptr_t wf = resolve_worldframe_ui();
    if (!wf) {
        s_pPushnumber(L, 0.0); s_pPushnumber(L, 0.0); s_pPushboolean(L, 0);
        return 3;
    }

    const float* m = (const float*)(wf + WORLDFRAME_OFF_VIEWPROJ);
    /* 68887: the wf+0x388 VP matrix is camera-relative -> the origin is the camera EYE
     * (verified: player projects to (0.50,0.56)). The old world-origin-bias global is dead. */
    uintptr_t cam = om_read_ptr(wf + CAM_OFF_CCAMERA);
    float ox = 0.0f, oy = 0.0f, oz = 0.0f;
    if (cam && om_ptr_ok(cam + CCAM_OFF_EYE, 12)) {
        ox = *(float*)(cam + CCAM_OFF_EYE);
        oy = *(float*)(cam + CCAM_OFF_EYE + 4);
        oz = *(float*)(cam + CCAM_OFF_EYE + 8);
    }
    float vx = wx - ox;
    float vy = wy - oy;
    float vz = wz - oz;

    float clipX = m[0] * vx + m[4] * vy + m[8] * vz;
    float clipY = m[1] * vx + m[5] * vy + m[9] * vz;
    float clipW = m[3] * vx + m[7] * vy + m[11] * vz;

    if (clipW <= 0.0f) {
        s_pPushnumber(L, 0.0); s_pPushnumber(L, 0.0); s_pPushboolean(L, 0);
        return 3;
    }

    float ndcX = clipX / clipW;
    float ndcY = clipY / clipW;
    float sx = (ndcX + 1.0f) * 0.5f;
    float sy = (1.0f - ndcY) * 0.5f;

    s_pPushnumber(L, (double)sx);
    s_pPushnumber(L, (double)sy);
    s_pPushboolean(L, 1);
    return 3;
}
