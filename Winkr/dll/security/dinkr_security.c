/* dinkr_security.c -- in-process patching and security bypass */

#include "dinkr_security.h"

/* ========================================================================
** In-process patching helpers
** ======================================================================== */

BOOL PatchBytes(LPBYTE addr, const BYTE* newBytes, SIZE_T count, const char* label) {
    char logBuf[256];
    DWORD oldProtect;
    if (!VirtualProtect(addr, count, PAGE_EXECUTE_READWRITE, &oldProtect)) {
        snprintf(logBuf, sizeof(logBuf), "[patch] %s: VirtualProtect failed (err=%lu)", label, GetLastError());
        DebugLog(logBuf);
        return FALSE;
    }
    memcpy(addr, newBytes, count);
    VirtualProtect(addr, count, oldProtect, &oldProtect);
    FlushInstructionCache(GetCurrentProcess(), addr, count);
    return TRUE;
}

/* Zero the global taint handler pointer in .data.
 * When NULL, restricted_action() returns 1 for all actions.
 * This is a .data write — no VirtualProtect needed. */
BOOL ZeroTaintRoot(LPBYTE base) {
    volatile uintptr_t* pTaintRoot = (volatile uintptr_t*)(base + RVA_G_TAINT_HANDLER_PTR);
    *pTaintRoot = 0;
    if (*pTaintRoot != 0) {
        DebugLog("[patch] FATAL: taint root verification failed");
        return FALSE;
    }
    DebugLog("[patch] taint root zeroed");
    return TRUE;
}

/* ========================================================================
** EnsurePrecallPatched — 67088 castbar-safe precall tuning.
**
** WoW 67088 has TWO precall functions (luaD_precall_v1 and v2) selected at
** runtime by `lua_call` wrapper based on `*(L+56)+32`. Each has two 16-bit
** callstatus stamps (Lua-function frame setup vs C-function dispatch).
**
** Castbar emitters (UNIT_SPELLCAST_*) execute Lua callbacks and expect the
** Lua-function frame stamp to remain vanilla (0x01). For dinkr bypass we
** raise both C-dispatch stamp low bytes from 0x00 -> 0x02 so that resolver
** helpers (sub_7FF641E0A890 / E0A810 / E09780) recognise the new C-frame as
** dinkr-blessed and don't return -2 on secret-tagged self values.
**
** Native UI event-dispatched calls (Spark:Hide, EssenceFrame:IsShown) route
** through v1; mods route through v2. Patching only v2 broke the UI side —
** that was the round-1/2/3 cast bar regression.
** ======================================================================== */

BOOL EnsurePrecallPatched(LPBYTE base) {
    static const struct {
        DWORD rva;
        BYTE desired;
        BYTE baseline;
    } sites[] = {
        /* v2: Lua-func frame stamp 0x01 -> 0x02 (67186: inline secret checks
         * everywhere trigger on Lua frames with taint_check==1 whenever
         * g_TaintHandlerPtr != NULL. Stamping 2 marks the frame fully-bypass). */
        { RVA_PRECALL_C_LUAFUNC,     0x02, 0x01 },
        /* v2: C-dispatch stamp 0x00 -> 0x02. */
        { RVA_PRECALL_C_CCLOSURE,    0x02, 0x00 },
        /* v1: Lua-func frame stamp 0x01 -> 0x02. */
        { RVA_PRECALL_V1_C_LUAFUNC,  0x02, 0x01 },
        /* v1: C-dispatch stamp 0x00 -> 0x02 (cast-bar path). */
        { RVA_PRECALL_V1_C_CCLOSURE, 0x02, 0x00 },
    };
    const int total = (int)(sizeof(sites) / sizeof(sites[0]));
    int ok = 0;
    for (int i = 0; i < total; i++) {
        LPBYTE site = base + sites[i].rva;
        if (*site == sites[i].desired) { ok++; continue; }
        if (*site == sites[i].baseline || *site == 0x02 || *site == 0x01 || *site == 0x00) {
            char lbl[48];
            snprintf(lbl, sizeof(lbl), "precall_site_%d", i);
            if (PatchBytes(site, &sites[i].desired, 1, lbl)) ok++;
        } else {
            char logBuf[160];
            snprintf(logBuf, sizeof(logBuf),
                     "[patch] precall_site_%d: unexpected byte 0x%02X at RVA 0x%08X",
                     i, (unsigned)*site, (unsigned int)sites[i].rva);
            DebugLog(logBuf);
        }
    }
    char logBuf[128];
    snprintf(logBuf, sizeof(logBuf), "[patch] precall_sites: %d/%d OK", ok, total);
    DebugLog(logBuf);
    return (ok == total);
}

/* ========================================================================
** ApplyRound1Patches_68453 — dump-verified, crash-safe subset for build 68453.
**
** Only patches re-derived and verified against Wow_68453_full.exe are enabled:
**   1. is_value_not_secret   -> xor eax,eax; ret   (RVA prologue-verified)
**   2. c_api_secret_arg_gate -> mov al,1; ret       (sig-confirmed)
**   3. secret_val_gate x46   -> JZ->JMP             (all 0x74 forward-je, verified)
**
** DISABLED pending re-derivation (stale/unverified RVAs -> would crash or misfire):
**   retaddr_check, validate_cfunc_ptr (unconditional RET-stomp),
**   precall x4, forbidden_tbl x9, secret_key_gate x3, c_api_type_gate x6,
**   resolver_lockdown/cancall.
**
** All enabled patches are crash-safe: RET-stomps target confirmed addresses;
** JZ-flips only rewrite a byte that is actually 0x74 (same jump target), and
** log+skip anything else.
** ======================================================================== */
static const DWORD g_SecretValSites_68453[RVA_SECRET_VAL_GATE_COUNT] = {
    RVA_SECRET_VAL_GATE_0,  RVA_SECRET_VAL_GATE_1,  RVA_SECRET_VAL_GATE_2,
    RVA_SECRET_VAL_GATE_3,  RVA_SECRET_VAL_GATE_4,  RVA_SECRET_VAL_GATE_5,
    RVA_SECRET_VAL_GATE_6,  RVA_SECRET_VAL_GATE_7,  RVA_SECRET_VAL_GATE_8,
    RVA_SECRET_VAL_GATE_9,  RVA_SECRET_VAL_GATE_10, RVA_SECRET_VAL_GATE_11,
    RVA_SECRET_VAL_GATE_12, RVA_SECRET_VAL_GATE_13, RVA_SECRET_VAL_GATE_14,
    RVA_SECRET_VAL_GATE_15, RVA_SECRET_VAL_GATE_16, RVA_SECRET_VAL_GATE_17,
    RVA_SECRET_VAL_GATE_18, RVA_SECRET_VAL_GATE_19, RVA_SECRET_VAL_GATE_20,
    RVA_SECRET_VAL_GATE_21, RVA_SECRET_VAL_GATE_22, RVA_SECRET_VAL_GATE_23,
    RVA_SECRET_VAL_GATE_24, RVA_SECRET_VAL_GATE_25, RVA_SECRET_VAL_GATE_26,
    RVA_SECRET_VAL_GATE_27, RVA_SECRET_VAL_GATE_28, RVA_SECRET_VAL_GATE_29,
    RVA_SECRET_VAL_GATE_30, RVA_SECRET_VAL_GATE_31, RVA_SECRET_VAL_GATE_32,
    RVA_SECRET_VAL_GATE_33, RVA_SECRET_VAL_GATE_34, RVA_SECRET_VAL_GATE_35,
    RVA_SECRET_VAL_GATE_36, RVA_SECRET_VAL_GATE_37, RVA_SECRET_VAL_GATE_38,
    RVA_SECRET_VAL_GATE_39, RVA_SECRET_VAL_GATE_40, RVA_SECRET_VAL_GATE_41,
    RVA_SECRET_VAL_GATE_42, RVA_SECRET_VAL_GATE_43, RVA_SECRET_VAL_GATE_44,
    RVA_SECRET_VAL_GATE_45
};

/* ========================================================================
** PatchSecretTaintGates — the secret-value / taint bypass.
**
** Modern WoW tags unit.health/power etc. as "secret" TValues (real value at
** TValue+0, secret flag byte at TValue+9). When TAINTED code (all injected mod
** code -- "ForceTaint_Strong") does arithmetic/ops on a secret value, the Lua VM
** gates on the global-state taint flag `[G+0x11] & 4` and calls luaG_secreterror
** (noreturn -> int3 follows every call, so it CANNOT be RET-stomped).
**
** We neutralize the GATE, not the error: flip `test byte[reg+0x11], 4` ->
** `test byte[reg+0x11], 0` at each secret-error call site, so the tainted branch
** is skipped and the arithmetic proceeds on the real value. This is surgical and
** crash-safe: WoW's OWN code runs UNTAINTED (flag bit 0), so it already takes the
** skip branch -- its behavior is byte-for-byte unchanged. Only our tainted code
** changes. Unlike the past crashes, this does NOT touch is_value_not_secret
** (values stay correctly flagged), does NOT zero g_taint_handler_ptr, and does
** NOT RET-stomp a noreturn.
**
** CURATED (2026-07-27): the self-locating "flip ALL 6 gates" approach crashed --
** ONE of the 6 gates (0x33E207D) is NOT a leaf value-op: it guards a secret-value
** table STORE (luaV_settable loop, verb "loop in settable"). Its skip path sets up
** args and `call`s luaH_set (0x33D5AC0), so forcing the skip stores a secret key/
** value without the taint bookkeeping -> NULL node deref (fault @0x33E2600).
** The other 5 gates ARE leaf value-ops (arith/compare/convert/bool/length): their
** skip path is a short stack-cleanup ending in `ret`. We patch ONLY those 5, from a
** verify-guarded RVA allowlist (rva_defs.h RVA_SECRET_TAINT_GATE_0..4). Fail-safe:
** a stale/moved RVA fails the `F6 /r 11 04 74` pattern check -> skipped, never
** stomped (allowlist fails to under-patch, NOT into a crash). A structural veto
** additionally rejects any site whose je-skip target begins with `lea r*,[rsp+..]`
** (48 8D 44/4C 24 -- the settable store-arg signature) as a second independent guard.
** Re-derive on build bump: python tools/secret_gates.py.
** ======================================================================== */
/* DISABLED 2026-07-27 (default 0): superseded by the taint-cleared UnitHealth/Power
 * wrappers in dinkr_mods.c (setupScript). Those make the native health/power C-API
 * return REAL numbers so no secret value ever reaches the rotation -- the gate flips
 * (which un-secret only COMPUTED values) neither stopped the error spam nor the
 * secret-number-as-table luaH_get crash (RVA 0x33E26xx, reproduced with gates ON and
 * OFF). The curated 5-gate logic below is kept, verified, and re-enablable (set to 1)
 * as defense-in-depth if the wrapper approach proves insufficient. */
#ifndef DINKR_SECRET_BYPASS
#define DINKR_SECRET_BYPASS 0   /* curated 5-gate subset; 1 to enable as defense-in-depth */
#endif
static int PatchSecretTaintGates(LPBYTE base) {
#if !DINKR_SECRET_BYPASS
    DebugLog("[patch] secret taint bypass: DISABLED (build flag)");
    return 0;
#else
    char lb[160];
    static const DWORD kGateRVAs[] = {
        RVA_SECRET_TAINT_GATE_0, RVA_SECRET_TAINT_GATE_1, RVA_SECRET_TAINT_GATE_2,
        RVA_SECRET_TAINT_GATE_3, RVA_SECRET_TAINT_GATE_4,
    };
    const int N = (int)(sizeof(kGateRVAs) / sizeof(kGateRVAs[0]));
    int patched = 0, already = 0, stale = 0, vetoed = 0;
    for (int i = 0; i < N; i++) {
        volatile BYTE* g = (volatile BYTE*)(base + kGateRVAs[i]);
        /* Verify the exact gate shape: test byte[reg+0x11],0x04 ; je rel8
         *   F6 /r      -> g[0]==0xF6, modrm reg field == /0 (test imm), (g[1]&0x38)==0
         *   disp8 0x11 -> g[2]==0x11
         *   imm8       -> g[3]==0x04 (patchable) or 0x00 (already done)
         *   je short   -> g[4]==0x74 */
        if (g[0] != 0xF6 || (g[1] & 0x38) != 0x00 || g[2] != 0x11 || g[4] != 0x74) {
            snprintf(lb, sizeof(lb), "[patch] secret gate %d @RVA 0x%X: shape mismatch (%02X %02X %02X %02X %02X) -- STALE, skipped",
                     i, (unsigned)kGateRVAs[i], g[0], g[1], g[2], g[3], g[4]);
            DebugLog(lb); stale++; continue;
        }
        if (g[3] == 0x00) { already++; continue; }        /* idempotent */
        if (g[3] != 0x04) {
            snprintf(lb, sizeof(lb), "[patch] secret gate %d @RVA 0x%X: unexpected imm 0x%02X -- skipped",
                     i, (unsigned)kGateRVAs[i], g[3]);
            DebugLog(lb); stale++; continue;
        }
        /* Structural veto: je skip-target = (g+6) + (int8)g[5]. Reject the settable
         * store shape `lea r*,[rsp+..]` (48 8D 44 24 / 48 8D 4C 24). */
        volatile BYTE* tgt = g + 6 + (int)(signed char)g[5];
        if (tgt[0] == 0x48 && tgt[1] == 0x8D && (tgt[2] == 0x44 || tgt[2] == 0x4C) && tgt[3] == 0x24) {
            snprintf(lb, sizeof(lb), "[patch] secret gate %d @RVA 0x%X: VETO -- skip-target is store-arg setup (not a leaf value-op)",
                     i, (unsigned)kGateRVAs[i]);
            DebugLog(lb); vetoed++; continue;
        }
        BYTE zero = 0x00;
        if (PatchBytes((LPBYTE)(g + 3), &zero, 1, "secret_taint_gate")) patched++;
    }
    snprintf(lb, sizeof(lb), "[patch] secret taint bypass: %d/%d gates patched (already=%d stale=%d vetoed=%d)",
             patched, N, already, stale, vetoed);
    DebugLog(lb);
    return patched;
#endif
}

int ApplyRound1Patches_68453(LPBYTE base) {
    (void)base;
    /* Build 68453: global security patches DISABLED — they crash WoW, and are
     * unnecessary. Root-cause analysis (dump-verified):
     *
     *  - Functions like c_api_secret_arg_gate (0x3467E10) and is_value_not_secret
     *    (0x3468E50) are called by WoW's OWN secure UI code every frame. They gate
     *    on `[g_taint_handler_ptr] == 0` (arg gate branches to the OK path when the
     *    handler is null). WoW's own code expects real secret enforcement; a global
     *    RET-stomp forces "ok/not-secret" and WoW then derefs secret sentinels as
     *    real values -> crash with no user action (observed: round-1b).
     *
     *  - The bypass we actually need only has to cover MOD code, and it already does:
     *    the mod loader clears g_taint_handler_ptr for the duration of mod execution
     *    (EnterLuaTaintScope / LeaveLuaTaintScope in dinkr_mods.c) and dinkr_Call does
     *    the same per call. While that pointer is 0, every secret/arg/type gate
     *    NATURALLY returns "ok" for mod code, and WoW's own code (handler != 0) runs
     *    untouched. No global .text patch is needed or safe on 68453.
     *
     * The legacy 66838 patch body (below, unreachable) and g_SecretValSites_68453
     * are retained for reference only. */
    DebugLog("[patch] 68453: global secret patches disabled by design -- taint-scope bypass covers mod code");

    /* Eidolon C-API caller/pointer validators — the enabled global patches.
     * Both are deliberate-NULL-deref anti-tamper guards that fire when a Lua
     * C-API path is entered from the injected DLL (outside WoW .text):
     *   retaddr_check      (0x1D7E80): luaL_loadbuffer/lua_pcall caller check;
     *                       NULL-reads [r10] @0x1D8110 (dinkr-eidolon-loadbuffer).
     *   validate_cfunc_ptr (0x31FB80): C-function-pointer whitelist; range-checks
     *                       the ptr vs WoW's [base,base+size) and NULL-derefs
     *                       @0x31FC00 when out of range. Our dinkr_ bridge
     *                       closures live in the DLL -> tripped on first call.
     * Every caller of both discards the return, so a 1-byte entry RET is
     * crash-safe for WoW's own code (unlike the secret-handling RET-stomps
     * above). Prologue guard: only patch if the entry byte is 0x48 (sub rsp,0x28)
     * so a stale RVA can never stomp garbage. */
    {
        char lb[160];
        struct { DWORD rva; const char* name; } guards[] = {
            { RVA_RETADDR_CHECK,      "retaddr_check" },
            { RVA_VALIDATE_CFUNC_PTR, "validate_cfunc_ptr" },
        };
        int applied = 0;
        for (int i = 0; i < (int)(sizeof(guards)/sizeof(guards[0])); i++) {
            LPBYTE va = base + guards[i].rva;
            BYTE cur = va[0];
            if (cur == 0xC3) {
                snprintf(lb, sizeof(lb), "[patch] %s: already RET (skip)", guards[i].name);
                DebugLog(lb); applied++;
            } else if (cur == 0x48) {
                BYTE ret = 0xC3;
                if (PatchBytes(va, &ret, 1, guards[i].name)) {
                    applied++;
                    snprintf(lb, sizeof(lb), "[patch] %s RET-stomp: APPLIED", guards[i].name);
                    DebugLog(lb);
                }
            } else {
                snprintf(lb, sizeof(lb), "[patch] %s: prologue guard FAIL (byte=0x%02X @RVA 0x%X) -- STALE, not patched", guards[i].name, cur, (unsigned)guards[i].rva);
                DebugLog(lb);
            }
        }
        snprintf(lb, sizeof(lb), "[patch] caller/ptr validators: %d/2 applied", applied);
        DebugLog(lb);

        /* PROTECTED-CALL GATE — TRIED AND REVERTED (2026-09-01/02).
         *
         * The gate at 0x02D17EB0 (called by CastSpellByName) judges a TAINTED
         * caller on the strength byte of a fixed "ForceTaint_Strong" struct
         * rather than on its own call context, and 3/4 means refuse. Flipping
         * the jne at RVA_PROTECTED_CALL_GATE_JNE to jmp, or NOPing the lea at
         * RVA_PROTECTED_CALL_GATE_LEA, makes tainted code judged like anyone
         * else. Both applied cleanly (the pattern guards matched, so the RVAs
         * are right) and are documented in rva_defs.h.
         *
         * NOT APPLIED, for three reasons:
         *
         *  1. It did not fix anything. Casts stayed blocked with it live. The
         *     real cause was Lua-side: friendly spells in dinkrPaladin never
         *     skipped awful's usable/los pre-checks, which are known-broken on
         *     Classic. Fixing that made healing work with this patch inert.
         *
         *  2. The blast radius is the whole client, not just us. It changes how
         *     EVERY protected call is evaluated, including Blizzard's own UI.
         *     That was never verified -- only reasoned about.
         *
         *  3. Detection surface. Patching a security function for no benefit is
         *     gratuitous, and it cuts against how this file already works: the
         *     secret-taint gates below ship DISABLED for the same reason.
         *
         * Kept as documentation rather than deleted: the addresses and the
         * disassembly cost real effort to derive, and if a future build genuinely
         * needs a protected-call bypass this is where it starts. Re-enable by
         * restoring the PatchBytes calls from git history.
         */

        /* Secret-value / taint bypass: lets tainted mod code read unit.health,
         * power, etc. (the deepest anti-cheat wall). Surgical gate flips; safe
         * for WoW's own untainted code. */
        applied += PatchSecretTaintGates(base);
        return applied;
    }
}

/* ========================================================================
** ApplySecurityPatches — single call applies all 7 security patch groups
**
** 1. retaddr_check     → RET (.text, 1 byte)
** 2. lua_setsecret     → NO-OP (kept unpatched on 67088)
** 3. validate_cfunc_ptr→ RET (.text, 1 byte)
** 4. is_value_not_secret→ mov al,1; ret (.text, 3 bytes)
** 5. precall callstatus sites (EnsurePrecallPatched, 2 effective bytes)
** 6. ZeroTaintRoot     → zero taint handler (.data, 8 bytes)
** 7. Forbidden table JZ→JMP (9 × .text, 1 byte each)
** 8. Resolver lockdown bypass JNZ→JMP (1 byte, castbar path 5)
** 9. Resolver canCall bypass JZ→NOP NOP (2 bytes, castbar path 2)
**
** ======================================================================== */

int ApplySecurityPatches(LPBYTE base) {
    /* Build 68453: dispatch to the dump-verified round-1 subset above.
     * The legacy 66838 patch body below is unreachable and retained only as
     * reference while the remaining groups are re-derived for 68453. */
    return ApplyRound1Patches_68453(base);
    char logBuf[256];
    int applied = 0;
    const int total = 13;
    BYTE ret = 0xC3;
    BYTE xor_eax_ret[3] = { 0x31, 0xC0, 0xC3 }; /* xor eax,eax; ret  (restored post-Round-6 polarity guess) */

    /* 1: retaddr_check → RET */
    if (PatchBytes(base + RVA_RETADDR_CHECK, &ret, 1, "retaddr_check")) applied++;

    /* 2: lua_setsecret — keep original code.
     * 67088 castbar path (UNIT_SPELLCAST_SENT/START emitters) calls
     * lua_setsecret directly; RET-stomping this leaf suppresses the
     * cast-bar UI event path while server-side casts still succeed. */
    applied++;  /* intentionally unpatched */

    /* 3: validate_cfunc_ptr → RET */
    if (PatchBytes(base + RVA_VALIDATE_CFUNC_PTR, &ret, 1, "validate_cfunc_ptr")) applied++;

    /* 4: is_value_not_secret → xor eax,eax; ret (return 0).
     *    Round-6 attempted the inverse polarity (mov al,1; ret) as a guess —
     *    that broke mod loading and corrupted UI. Reverted. */
    if (PatchBytes(base + RVA_IS_VALUE_NOT_SECRET, xor_eax_ret, 3, "is_value_not_secret")) applied++;

    /* 5: precall callstatus tuning
     * - keep Lua-function frame stamp at 0x01 (castbar-safe)
     * - patch only C-dispatch stamp low byte 0x00->0x02 */
    if (EnsurePrecallPatched(base)) applied++;

    /* 6: ZeroTaintRoot — REMOVED.
     * Permanently zeroing the taint handler causes WoW's own Splash-
     * obfuscated Lua C functions (e.g. HandleTargetSelection at RVA
     * 0x1F8AFB0) to take an alternate code path that crashes with NULL
     * L->top.  The forbidden table JZ→JMP patches + precall patches
     * already handle our needs; dinkr_Call saves/restores the handler
     * temporarily for each pcall. */
    applied++;  /* count it as success (no-op) */

    /* 7: Forbidden table guards.
     * Round-8 (sukuna): IDA verified — all 9 sites RVA_FORBIDDEN_TBL_0..8
     * are functionally identical: each is the leading
     *   if ((tbl->flags & 1) && g_TaintHandlerPtr && L->ci != L->base_ci)
     *       throw "attempted to %s a table that cannot be accessed while tainted"
     * inside its respective luaH_*_secure helper:
     *   0  luaH_get_secure_check         (read)
     *   1  luaH_getn_secure_check        (length)
     *   2  luaH_getint_secure_check      (read int key)
     *   3  luaH_getshortstr_secure_check (read shortstr key)
     *   4  luaH_next_secure              (iteration — pairs/next)
     *   5  luaH_newkey_secure            (insert new key)
     *   6  luaH_setint_secure            (write int key)
     *   7  luaH_setobj_secure            (write any key)
     *   8  luaH_setnum_resize_rehash     (rehash on grow)
     * The actual flag SETTER is `or [rdi+44h],5` at RVA 0x13433B7 inside
     * luaH_newkey_secure (gated on TValue+9). Site #5 alone only blocks
     * subsequent throws on insert; pairs(self.SparkFx) hits site #4
     * (luaH_next_secure) and still emits the <forbidden table> sentinel.
     * All 9 sites are read/write checks of an already-set bit, so we
     * neutralize the entire family JZ->JMP. */
    {
        static const DWORD forbiddenSites[RVA_FORBIDDEN_TBL_COUNT] = {
            RVA_FORBIDDEN_TBL_0, RVA_FORBIDDEN_TBL_1, RVA_FORBIDDEN_TBL_2,
            RVA_FORBIDDEN_TBL_3, RVA_FORBIDDEN_TBL_4, RVA_FORBIDDEN_TBL_5,
            RVA_FORBIDDEN_TBL_6, RVA_FORBIDDEN_TBL_7, RVA_FORBIDDEN_TBL_8
        };
        BYTE jz = 0x74;
        BYTE jmp = 0xEB;
        int vanilla = 0;
        int restored = 0;
        int patched = 0;
        for (int i = 0; i < RVA_FORBIDDEN_TBL_COUNT; i++) {
            LPBYTE site = base + forbiddenSites[i];
            int wantPatched = 1; /* patch all 9: identical forbidden-table checks */
            BYTE want = wantPatched ? jmp : jz;
            if (*site == want) {
                if (wantPatched) patched++; else vanilla++;
                continue;
            }
            if (*site == jz || *site == jmp) {
                char lbl[40];
                snprintf(lbl, sizeof(lbl), "forbidden_set_%d", i);
                if (PatchBytes(site, &want, 1, lbl)) {
                    if (wantPatched) patched++; else restored++;
                }
            } else {
                snprintf(logBuf, sizeof(logBuf),
                          "[patch] forbidden_%d: unexpected byte 0x%02X at RVA 0x%08X",
                          i, (unsigned)*site, (unsigned int)forbiddenSites[i]);
                DebugLog(logBuf);
            }
        }
        snprintf(logBuf, sizeof(logBuf),
                  "[patch] forbidden_tbl: patched %d, vanilla %d, restored %d, total %d",
                  patched, vanilla, restored, RVA_FORBIDDEN_TBL_COUNT);
        DebugLog(logBuf);
        if (patched + vanilla + restored == RVA_FORBIDDEN_TBL_COUNT) applied++;
    }

    /* 7b: Secret-key gate guards (sister of forbidden-tbl).
     * Each of the 3 secure-table helpers (luaH_get, luaH_next, luaH_newkey)
     * has a SECOND check after the forbidden-tbl one:
     *   if (key->is_secret) {
     *     if (ci->taint_mode == 0
     *         || (ci->taint_mode == 1 && g_TaintHandlerPtr)
     *         || (table->flags & 2))
     *       throw "attempted to %s a table that cannot be indexed with secret keys";
     *     ci->taint_dirty = 1;
     *   }
     * The whole block is gated by `cmp byte ptr [keyptr+9], 0; jz <skip>`
     * (the JZ jumps to the tail call when the key isn't secret). Flipping
     * 0x74 -> 0xEB makes that JZ unconditional, so the whole secret-key
     * block (including the throw) is bypassed regardless of key type.
     * Without this, addons that iterate frames via pairs() spam the
     * "751x attempted to iterate a table that cannot be indexed with secret
     * keys" error whenever g_TaintHandlerPtr is set during the addon's
     * execution context. */
    {
        static const DWORD secretKeySites[RVA_SECRET_KEY_GATE_COUNT] = {
            RVA_SECRET_KEY_GATE_0, RVA_SECRET_KEY_GATE_1, RVA_SECRET_KEY_GATE_2
        };
        BYTE jz  = 0x74;
        BYTE jmp = 0xEB;
        int patched = 0, vanilla = 0;
        for (int i = 0; i < RVA_SECRET_KEY_GATE_COUNT; i++) {
            LPBYTE site = base + secretKeySites[i];
            if (*site == jmp) { patched++; continue; }
            if (*site == jz) {
                char lbl[40];
                snprintf(lbl, sizeof(lbl), "secret_key_gate_%d", i);
                if (PatchBytes(site, &jmp, 1, lbl)) patched++;
            } else {
                snprintf(logBuf, sizeof(logBuf),
                         "[patch] secret_key_gate_%d: unexpected byte 0x%02X at RVA 0x%08X",
                         i, (unsigned)*site, (unsigned int)secretKeySites[i]);
                DebugLog(logBuf);
            }
        }
        snprintf(logBuf, sizeof(logBuf),
                 "[patch] secret_key_gate: patched %d, vanilla %d, total %d",
                 patched, vanilla, RVA_SECRET_KEY_GATE_COUNT);
        DebugLog(logBuf);
        if (patched == RVA_SECRET_KEY_GATE_COUNT) applied++;
    }

    /* 7c: Secret-VALUE gate guards (JZ -> JMP, 1 byte each).
     * Sister to secret_key_gate above. Each site is the entry-gate
     * `cmp byte ptr [val+9], 0; jz <skip>` inside a function that throws
     * via luaG_secreterror (sub_7FF6FAC762B0). Flipping JZ to JMP makes
     * the entire secret-value check block unreachable, killing throws like
     * "attempt to perform numeric conversion on a secret number value"
     * and "attempt to perform boolean test on a secret value" without
     * touching any noreturn function (which would crash via int 3 padding
     * at every call site). Verified 67186 — 27 sites across 24 functions. */
    {
        static const DWORD secretValSites[RVA_SECRET_VAL_GATE_COUNT] = {
            RVA_SECRET_VAL_GATE_0,  RVA_SECRET_VAL_GATE_1,  RVA_SECRET_VAL_GATE_2,
            RVA_SECRET_VAL_GATE_3,  RVA_SECRET_VAL_GATE_4,  RVA_SECRET_VAL_GATE_5,
            RVA_SECRET_VAL_GATE_6,  RVA_SECRET_VAL_GATE_7,  RVA_SECRET_VAL_GATE_8,
            RVA_SECRET_VAL_GATE_9,  RVA_SECRET_VAL_GATE_10, RVA_SECRET_VAL_GATE_11,
            RVA_SECRET_VAL_GATE_12, RVA_SECRET_VAL_GATE_13, RVA_SECRET_VAL_GATE_14,
            RVA_SECRET_VAL_GATE_15, RVA_SECRET_VAL_GATE_16, RVA_SECRET_VAL_GATE_17,
            RVA_SECRET_VAL_GATE_18, RVA_SECRET_VAL_GATE_19, RVA_SECRET_VAL_GATE_20,
            RVA_SECRET_VAL_GATE_21, RVA_SECRET_VAL_GATE_22, RVA_SECRET_VAL_GATE_23,
            RVA_SECRET_VAL_GATE_24, RVA_SECRET_VAL_GATE_25, RVA_SECRET_VAL_GATE_26
        };
        BYTE jz  = 0x74;
        BYTE jmp = 0xEB;
        int patched = 0, vanilla = 0;
        for (int i = 0; i < RVA_SECRET_VAL_GATE_COUNT; i++) {
            LPBYTE site = base + secretValSites[i];
            if (*site == jmp) { patched++; continue; }
            if (*site == jz) {
                DWORD oldp = 0;
                VirtualProtect(site, 1, PAGE_EXECUTE_READWRITE, &oldp);
                *site = jmp;
                VirtualProtect(site, 1, oldp, &oldp);
                FlushInstructionCache(GetCurrentProcess(), site, 1);
                patched++;
            } else {
                vanilla++;
            }
        }
        snprintf(logBuf, sizeof(logBuf),
                 "[patch] secret_val_gate: patched %d, vanilla %d, total %d",
                 patched, vanilla, RVA_SECRET_VAL_GATE_COUNT);
        DebugLog(logBuf);
        if (patched == RVA_SECRET_VAL_GATE_COUNT) applied++;
    }

    /* 7d: Universal C-API secret-arg gate (sub_7FF6FAC77E00, 786 callers).
     * Used by every UnitHealth/UnitName/UnitGUID/etc. arg-validator. Returns
     * AL=1 when the arg is OK and AL=0 when secret+tainted, and each caller
     * does `test al, al; jnz <skip-throw>`. RET-stomping the function entry
     * with `mov al, 1; ret` (B0 01 C3) forces every caller down the OK path
     * — same as the natural "not secret" return. Stack stays balanced
     * because we return before the prologue's `sub rsp, 28h`. Kills the
     * entire "Secret values are only allowed during untainted execution"
     * error class with one 3-byte patch. */
    {
        BYTE want[3] = { 0xB0, 0x01, 0xC3 };
        LPBYTE site = base + RVA_C_API_SECRET_ARG_GATE;
        if (site[0] == 0xB0 && site[1] == 0x01 && site[2] == 0xC3) {
            applied++;
        } else if (PatchBytes(site, want, 3, "c_api_secret_arg_gate")) {
            applied++;
        }
    }

    /* 7e: C-API type-check entry gates (JZ -> JMP, 1 byte each).
     * Sister of secret_val_gate / c_api_secret_arg_gate. Each site is the
     * entry-gate cmp byte ptr [val+9], 0; jz <validate> inside lua_type
     * and lua_to / lua_is helpers. On the secret+tainted path these either
     * cause callers to throw bare "Usage: ..." argerrors (awful2 line-270
     * UnitIsPlayer/UnitIsVisible/UnitHealth errors) or return -2 which
     * lua_typename renders as "secret" (causing pairs to fail with
     * "table expected, got secret"). Flipping JZ -> JMP forces every site
     * down the normal validate path. RET-stomp would mis-balance the stack
     * because each function has differing post-prologue layouts. */
    {
        static const DWORD typeGateSites[RVA_C_API_TYPE_GATE_COUNT] = {
            RVA_C_API_TYPE_GATE_0, RVA_C_API_TYPE_GATE_1, RVA_C_API_TYPE_GATE_2,
            RVA_C_API_TYPE_GATE_3, RVA_C_API_TYPE_GATE_4, RVA_C_API_TYPE_GATE_5
        };
        BYTE jz  = 0x74;
        BYTE jmp = 0xEB;
        int patched = 0, vanilla = 0;
        for (int i = 0; i < RVA_C_API_TYPE_GATE_COUNT; i++) {
            LPBYTE site = base + typeGateSites[i];
            if (*site == jmp) { patched++; continue; }
            if (*site == jz) {
                DWORD oldp = 0;
                VirtualProtect(site, 1, PAGE_EXECUTE_READWRITE, &oldp);
                *site = jmp;
                VirtualProtect(site, 1, oldp, &oldp);
                FlushInstructionCache(GetCurrentProcess(), site, 1);
                patched++;
            } else {
                vanilla++;
            }
        }
        snprintf(logBuf, sizeof(logBuf),
                 "[patch] c_api_type_gate: patched %d, vanilla %d, total %d",
                 patched, vanilla, RVA_C_API_TYPE_GATE_COUNT);
        DebugLog(logBuf);
        if (patched == RVA_C_API_TYPE_GATE_COUNT) applied++;
    }

    /* 8: Self-validator "fully locked-down" bypass.
     * sub_7FF63EFC9600 emits "Attempt to access fully locked-down object"
     * when a6==0 AND [userdata+0xC] has bit3 set OR bit5 clear. The
     * error path through sub_7FF63F2ED170 surfaces as "bad self
     * (Usage: self:Hide())" in Lua (CastingBarFrame.lua:630).
     * g_TaintHandlerPtr=0 rules out the forbidden-object branch above
     * so this is the only remaining failure path for valid Texture
     * userdata. Patch 0x75 1A -> 0xEB 1A at RVA_RESOLVER_LOCKDOWN_BYPASS
     * to always take the "secure caller" shortcut for this branch. */
    {
        LPBYTE site = base + RVA_RESOLVER_LOCKDOWN_BYPASS;
        BYTE want = 0xEB;
        if (*site == want) {
            applied++;
        } else if (*site == 0x75) {
            if (PatchBytes(site, &want, 1, "resolver_lockdown_bypass")) applied++;
        } else {
            snprintf(logBuf, sizeof(logBuf),
                     "[patch] resolver_lockdown_bypass: unexpected byte 0x%02X at RVA 0x%08X",
                     (unsigned)*site, (unsigned int)RVA_RESOLVER_LOCKDOWN_BYPASS);
            DebugLog(logBuf);
        }
    }

    /* 9: Self-validator "Wrong object type" (canCall vtable) bypass.
     * sub_7FF63EFC9600 calls `[v12->vtable+0x98](v12, funcID)` as a
     * per-object "can this caller invoke this function?" security gate.
     * A 0 return makes the resolver emit "Wrong object type for function"
     * which surfaces as Lua "calling 'X' on bad self" (path 2 of 5).
     * In 67088 this gate started rejecting C-dispatcher events on
     * PlayerCastingBarFrame.Spark:Hide and EssencePlayerFrame:IsShown
     * (both get called from the game's internal event queue, not from
     * mods). The real Hide/IsShown method pointers live in a different
     * vtable slot used at the caller, so bypassing this gate does not
     * change which function runs — only whether the resolver pre-rejects
     * self. Patch JZ (74 B0) -> NOP NOP (90 90) at RVA_RESOLVER_CANCALL_BYPASS. */
    {
        LPBYTE site = base + RVA_RESOLVER_CANCALL_BYPASS;
        BYTE want[2] = { 0x90, 0x90 };
        if (site[0] == 0x90 && site[1] == 0x90) {
            applied++;
        } else if (site[0] == 0x74) {
            if (PatchBytes(site, want, 2, "resolver_cancall_bypass")) applied++;
        } else {
            snprintf(logBuf, sizeof(logBuf),
                     "[patch] resolver_cancall_bypass: unexpected bytes 0x%02X 0x%02X at RVA 0x%08X",
                     (unsigned)site[0], (unsigned)site[1], (unsigned int)RVA_RESOLVER_CANCALL_BYPASS);
            DebugLog(logBuf);
        }
    }

    snprintf(logBuf, sizeof(logBuf), "[patch] ApplySecurityPatches: %d/%d groups OK", applied, total);
    DebugLog(logBuf);
    return applied;
}
