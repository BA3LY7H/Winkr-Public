/* dinkr_bridge_core.c -- TValue calibration + shared state definitions */

#include "dinkr_bridge.h"

/* --- Global state (extern-declared in dinkr_bridge.h) --- */
int          g_directStackReadOK = 0;
unsigned int g_tvSize            = 24;
DWORD        s_lastNPCPushTick   = 0;

void CalibrateDirectStackRead(void* L) {
    char logBuf[256];
    uintptr_t pL = (uintptr_t)L;

    s_pSettop(L, 0);
    s_pPushnumber(L, 31337.0);

    uintptr_t base = *(uintptr_t*)(pL + WK_LUA_STATE_BASE);
    if (base < 0x10000) {
        DebugLog("[stack-cal] FAIL: base ptr invalid at L+0x30");
        s_pSettop(L, 0);
        return;
    }

    if (IsBadReadPtr((const void*)base, 8) || *(double*)base != 31337.0) {
        snprintf(logBuf, sizeof(logBuf),
            "[stack-cal] FAIL: base offset wrong (read %f, expected 31337)",
            IsBadReadPtr((const void*)base, 8) ? 0.0 : *(double*)base);
        DebugLog(logBuf);
        s_pSettop(L, 0);
        return;
    }

    s_pPushnumber(L, 42.0);

    int found = 0;
    unsigned int candidates[] = { 24, 16, 32 };
    for (int c = 0; c < 3; c++) {
        uintptr_t addr = base + candidates[c];
        if (!IsBadReadPtr((const void*)addr, 8) && *(double*)addr == 42.0) {
            g_tvSize = candidates[c];
            g_directStackReadOK = 1;
            found = 1;
            snprintf(logBuf, sizeof(logBuf),
                "[stack-cal] OK: TValue=%u bytes, base=L+0x30", g_tvSize);
            DebugLog(logBuf);
            break;
        }
    }

    if (!found) {
        DebugLog("[stack-cal] FAIL: TValue size unknown");
    }

    /* Validate string direct-read: push a known string and verify */
    if (g_directStackReadOK) {
        s_pSettop(L, 0);
        s_pPushstring(L, "dinkr_cal");
        uintptr_t tv = WK_TV_AT(L, 1);
        if (!IsBadReadPtr((const void*)tv, g_tvSize) && WK_TV_TYPE(tv) == WK_LUA_TSTRING) {
            size_t slen = 0;
            const char* str = wk_tv_string(tv, &slen);
            if (str && slen == 9 && memcmp(str, "dinkr_cal", 9) == 0) {
                DebugLog("[stack-cal] string direct-read verified");
            } else {
                DebugLog("[stack-cal] WARN: string read mismatch, falling back to API");
                g_directStackReadOK = 0;
            }
        } else {
            DebugLog("[stack-cal] WARN: string type check failed, falling back to API");
            g_directStackReadOK = 0;
        }
    }

    s_pSettop(L, 0);
}
