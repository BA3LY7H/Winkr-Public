/*
 * rva_defs.h � RVA definitions for WoW build 68453 (12.0.7)
 *
 * Auto-generated from IDA verification. Source: decrypted dump + wow_offsets.txt
 * Build verified: 68453 | Base: 0x7FF79F350000
 */

#ifndef DINKR_RVA_DEFS_H
#define DINKR_RVA_DEFS_H

/* ============================================================================
 * BUILD 68887 MIGRATION -- PARTIAL (source: DINKR/build/Wow_68887_full.exe dump)
 *
 * VERIFIED for 68887 (dump + LIVE runtime, 2026-07-24) -- fully working:
 *   RVA_G_LUASTATE (now RIP-relative self-healing), RVA_G_LUASTATE_CREATE_COUNT,
 *   RVA_G_TAINT_HANDLER_PTR, the sig-confirmed Lua/spell functions ("68887 sig"),
 *   the two Eidolon validators (RET-stomp applied), and the OM-enum globals
 *   (g_pObjectMgr, *GUID, g_GameStateFlags) -- OM enumerates live and /wl cast
 *   on a real target, so these are CORRECT, not stale. SAFE MODE is OFF.
 *
 * NOT sig/dump-verifiable (harmless):
 *   - Target/Focus/Mouseover GUID globals: no code accessors; verified live via
 *     targeting instead. Correct on 68887.
 *   - Security patch sites (FORBIDDEN_TBL/SECRET_*_GATE/PRECALL): unused --
 *     ApplySecurityPatches applies only the 2 validators (taint-scope bypass).
 *
 * Re-derivation method: flat-mapped dump (file offset == RVA) + capstone; anchor
 * globals via the function that writes them (e.g. g_LuaState = store after the
 * lua_newstate call at 0x557BD2). Shift is region-dependent -- never extrapolate.
 * ========================================================================== */
/* PATCH DAY (2026-08-08): client 1.15.9.68940 -> 1.15.9.69109.
 * Bumping EXPECTED_BUILD alone arms SAFE MODE on every gate below (they all
 * compare against it), so the DLL can be injected to TAKE A DUMP with no taint
 * write, no mod execution and no stale-pointer deref.
 *
 * IMPORTANT: the on-disk WowClassic.exe is ENCRYPTED — .text samples read
 * entropy 7.96 with zero x64 prologues, vs 6.1-7.0 with hundreds in a real
 * dump. An offline PE flat-map therefore scores 0 on every signature. The image
 * only decrypts in memory, so patch-day re-derivation REQUIRES a runtime dump
 * of the live process. (tools/flatmap.py is kept for unencrypted builds only.) */
#define EXPECTED_BUILD 69547  // WoW Classic Era (build 69547); was 69109

/* Build the RVA set below was actually derived + verified against.
 * When this != EXPECTED_BUILD the DLL runs in SAFE MODE: no taint-scope writes
 * and no mod execution, because the data globals are stale (writing through a
 * stale g_taint_handler_ptr corrupts memory; a stale g_LuaState crashes Lua).
 * Bump this to EXPECTED_BUILD only after re-deriving the globals from a dump.
 *
 * 68940: mod-critical EXEC globals verified live -- g_LuaState (recipe AGREE,
 * L resolved valid in-world), luaL_loadbuffer + lua_pcall (sig PASS), CreateCount
 * (derived from g_LuaState+0x118). OM-enum globals verified (86 entities live).
 * Camera verified (selfheal camera=OK). Exiting SAFE MODE enables mod execution.
 * DINKR_CLEAR_TAINT=0 (taint-intact) so this does NOT trigger any g_taint write.
 *
 * 69109 (2026-08-08): re-derived from a RUNTIME dump (the on-disk exe is
 * encrypted). Scorecard: 12 STALE sigs relocated, 4 RIP-relative recipes agreed
 * by vote (g_activePlayerUnit 43/43, g_GameStateFlags 14/14, CAM_MGR 6/6,
 * g_LuaState 6/15). DUMMYNODE + g_taint re-derived by anchored disassembly.
 * g_taint is 3-WAY cross-validated: both Lua secret gates AND MoveForwardStart's
 * inline gate all resolve to 0x03C96C70. CInputControl confirmed independently
 * by IsPlayerMoving reading base+0x4. */
#define RVA_VERIFIED_BUILD 69547  // exec-critical globals re-derived from the 69547 runtime dump
#define RVA_SET_IS_VERIFIED (RVA_VERIFIED_BUILD == EXPECTED_BUILD)

/* g_taint_handler_ptr is a SEPARATE gate: writing 0 through a WRONG address
 * would corrupt whatever real global lives there, so this only opens once
 * g_taint is positively identified for the build. When it is closed every
 * taint-clear runs PASS-THROUGH (the wrapped fn is called without touching
 * taint) -- unit.health then returns SECRET values, which is non-fatal chat
 * spam rather than a crash.
 *
 * 69109 = 0x03C96C70, derived three independent ways that all agree:
 *   is_value_not_secret   @0x2DD1616  cmp qword [rip+0xec5652], 0
 *   c_api_secret_arg_gate @0x2DD05B3  cmp qword [rip+0xec66b5], 0
 *   MoveForwardStart      @0x167F9FF  cmp qword [rip+0x2617269], 0
 * The third is the strongest signal -- a completely unrelated subsystem
 * (movement keybinds) gating on the same global. (68940 was 0x3BDDDB0.) */
#define RVA_G_TAINT_VERIFIED_BUILD 69547  // g_taint 3-way cross-validated on 69547 (2 secret gates + MoveForwardStart)
#define RVA_G_TAINT_IS_VERIFIED (RVA_G_TAINT_VERIFIED_BUILD == EXPECTED_BUILD)

/* OM STRUCT gate. The CGObject field offsets in om_types.h beyond pos/GUID/type
 * (auras: CGOBJ_AURA_*, AURA_OFF_*; missiles: MISSILE_OFF_*, g_MissileInFlightListHead)
 * are all retail (67088/67186/68887) values -- NOT re-derived for Classic 68940.
 * Bridges that WALK these structures and build Lua tables from them (dinkr_UnitAuras,
 * dinkr_Missiles) read garbage on Classic. dinkr_Missiles in particular reads a stale
 * head RVA -> walks a garbage "linked list" -> forces the vendored table into the hash
 * path with rehashing on junk -> luaH_getnum node-chain crash (0xffff... deref).
 * Until the OM struct offsets are re-derived, those bridges return empty/nil so awful
 * falls back to the native WoW aura API and skips missile tracking. Only pos/GUID/type
 * are verified (live OM enum = 79 entities). Bump when om_types is re-derived. */
#define RVA_OM_STRUCT_VERIFIED_BUILD 0  // CGObject aura/missile offsets NOT derived for Classic
#define RVA_OM_STRUCT_IS_VERIFIED (RVA_OM_STRUCT_VERIFIED_BUILD == EXPECTED_BUILD)

// === Lua API ===
#define RVA_ACTIVE_SPEC_ID                                 0x05C7739C
#define RVA_CAM_FOV_RAW                                    0x03F704F8
#define RVA_CAM_MGR                                        0x03C41C70  // 69547: riprel 6/6; world frame derives from this +0x2B8 (was 0x03CFAB20)  // 69109: riprel recipe 6/6 votes (was 0x03C41C50)  // CLASSIC 68940 (was retail)  // 68887 WorldFrameUI singleton (live+disasm confirmed: 319 refs, [+0x4B0]=CCamera; was stale 0x04154730 0-ref)
#define RVA_C_API_SECRET_ARG_GATE                          0x02D16E50  // 69547: sig (was 0x02DD0590)  // 69109: sig (was 0x02D16940)  // CLASSIC 68940 (was retail)  // 68887 sig
#define RVA_C_API_TYPE_GATE_0                              0x03338CC3
#define RVA_C_API_TYPE_GATE_1                              0x03338D33
#define RVA_C_API_TYPE_GATE_2                              0x03338DAA
#define RVA_C_API_TYPE_GATE_3                              0x03338E43
#define RVA_C_API_TYPE_GATE_4                              0x03338EC3
#define RVA_C_API_TYPE_GATE_5                              0x0333AAC3
#define RVA_CombatLog_PushEventArgs                        0x01393F10
#define RVA_DUMMYNODE                                      0x02F19E70  // 69547: derived from luaH_new 0x02D224F0; unchanged from 69109 (was 0x02FD3E70)  // 69109: luaH_new@0x2DDBC30 lea [rip+0x1f81e0] (was 0x02F19E70)  // 68940 Classic: luaH_new@0x2D21FE0 lea [rip+0x1f7e30] -> 0x2F19E70, written as empty-table node. (retail 68887 was 0x035E1780 -- stale value pointed empty dinkr tables at garbage -> luaH_getnum -1 crash)
#define RVA_G_TAINT_GC_SOURCE                              0x03C96C88  // 69109: g_taint + 0x18, same adjacency as 68940 (was 0x03BDDDC8)  // 68940: GC-object taint source. WoW luaC_link @0x2D24DF0 stamps new obj gc_taint = *this when *g_taint(0x3BDDDB0)!=0. Adjacent to RVA_G_TAINT_HANDLER_PTR.
#define RVA_FORBIDDEN_TBL_0                                0x03342BCC
#define RVA_FORBIDDEN_TBL_1                                0x03342D8B
#define RVA_FORBIDDEN_TBL_2                                0x03342E4B
#define RVA_FORBIDDEN_TBL_3                                0x03342F28
#define RVA_FORBIDDEN_TBL_4                                0x033430B2
#define RVA_FORBIDDEN_TBL_5                                0x03343588
#define RVA_FORBIDDEN_TBL_6                                0x033436DE
#define RVA_FORBIDDEN_TBL_7                                0x0334379C
#define RVA_FORBIDDEN_TBL_8                                0x03343E5F
#define RVA_G_LUASTATE                                     0x05B3C018  // 69547: riprel 6/15; delta -0xB90C0 matches g_pObjectMgr (was 0x05BF50D8)  // 69109: riprel recipe 6/15 votes (was 0x05B3C1D8)  // CLASSIC 68940 (was retail)  // 68887 dump-verified: lua_newstate caller store, 302 refs (was 68453 0x06481458)
#define RVA_G_LUASTATE_CREATE_COUNT                        0x063F1BB0  // 68887 dump-verified: inc after lua_newstate (was 0x05A57420)
#define RVA_G_P_WORLD_FRAME                                0x0601EFA8  // 69109: 25/33 World_Intersect callers load it; holds a live heap ptr. Previous value was a RETAIL 68887 leftover holding garbage, so dinkr_TraceLine hit its om_ptr_ok fail-safe and reported BLOCKED on every call (was 0x067BDBD8)  // 68887 world/map base ptr (10 trace sites deref it: [base+0x20]=mapIndex, [base+idx*8+0x10]=intersect context). was stale 0x05E24038 (0 refs) -> TraceLine fail-safe -> los always false
#define RVA_G_TAINT_HANDLER_PTR                            0x03BDDDF0  // 69547: 3 anchors agree: is_value_not_secret, c_api_secret_arg_gate, MoveForwardStart (was 0x03C96C70)  // 69109: 3-way: both Lua secret gates + MoveForwardStart gate (was 0x03BDDDB0)  // g_taint_handler_ptr (g_pCurrentTaint) 68940: cross-anchor derived (c_api_secret_arg_gate cmp-vs-0 @0x2D16963, lua_pushboolean first-read @0x2D17E7B stamps TValue+0x10, lua_newstate default-write, is_value_not_secret/luaG_secreterror cmp-vs-0), 2352 rip-refs (dominant). retail 68887 was 0x043C89F0
/* loadstring_untainted -- the Lua base-library loader that does NOT stamp taint.
 * 69547: named registration in the client's base-lib table, sitting directly
 * beside `loadstring` (0x02E89590); verified a lua_CFunction by disassembly
 * (standard rcx=lua_State* prologue at 0x02E89070).
 *
 * WHY THIS MATTERS. loadstring @0x02E89590 opens with
 *     cmp DWORD [0x03BDDDF8],0 ; je  skip
 *     cmp DWORD [0x03BDDDFC],0 ; jne skip
 *     <stamp the compiled chunk with the current taint>
 * so every chunk the Lua-side `loadstring` compiles is born TAINTED. awful2
 * loads essentially all of itself that way (_local.lua require/loadFile), which
 * is where "*** ForceTaint_Strong ***" on our closures comes from. Clearing
 * g_taint at CALL time (dinkr_Call) can never undo it -- the closure was
 * already stamped at LOAD time. Re-exposing this lets us load untainted.
 *
 * 0x03BDDDF8 / 0x03BDDDFC are the force-taint gate DWORDs, adjacent to
 * g_taint_handler_ptr (0x03BDDDF0, +8 and +0xC). They are the "force_taint_flag"
 * that dinkr_Call's comment references and that was never implemented.
 * Documented, NOT written: re-exposing the untainted loader is surgical, while
 * flipping a global gate changes compile behaviour for the whole client. */
/* PROTECTED-CALL GATE -- DERIVED AND DOCUMENTED, DELIBERATELY NOT PATCHED.
 *
 * These addresses are correct (both pattern guards matched live) but nothing
 * writes to them any more; see dinkr_security.c for why the patch was reverted.
 * The short version: it did not fix the problem it was made for -- casting was
 * blocked by awful's usable/los pre-checks in Lua, not by this gate.
 *
 * Kept because the derivation was expensive and is the right starting point if
 * a future build genuinely needs a protected-call bypass.
 *
 * CastSpellByName (0x01AFFFA0) opens with
 *     mov edx,1 ; call 0x02D17EB0 ; test eax,eax ; jne <refuse>
 * and that callee is the permission gate. In full:
 *
 *   02D17EB0  call 0x2D16C00          ; ctx = current call context
 *   02D17EBF  cmp  BYTE [ctx+9],0 ; je  0x2D17EEC
 *   02D17EC5  mov  rcx,[L+0x40]
 *   02D17EC9  movsx edx,BYTE [rcx+0x24]
 *   02D17ECF  test edx,edx        ; je  0x2D17EE5     <-- "no source" path
 *   02D17ED1  cmp  edx,1          ; jne 0x2D17EEC
 *   02D17ED6  cmp  QWORD [g_taint],0
 *   02D17EDE  sete al ; test al,al
 *   02D17EE3  jne  0x2D17EEC      ; SECURE -> keep ctx
 *   02D17EE5  lea  r10,[0x2F19748]; TAINTED -> swap in the force-taint struct
 *   02D17EEC  movzx eax,BYTE [r10+8]   ; strength
 *   02D17EF1  cmp al,4 ; je blocked
 *   02D17EF5  cmp al,3 ; je blocked
 *             xor eax,eax ; ret 0      ; ALLOWED
 *             mov eax,1   ; ret 1      ; BLOCKED
 *
 * So a tainted caller is judged on the strength byte of a FIXED struct rather
 * than on its own context, and 3/4 ("Strong", hence the source name
 * "*** ForceTaint_Strong ***") means refuse. The byte reads 0 in an
 * uninjected dump and is raised at runtime, so writing the DATA byte is
 * pointless -- it gets re-set. Patch the BRANCH instead.
 *
 * 0x75 (jne) -> 0xEB (jmp) at 0x02D17EE3 makes the tainted path skip the lea,
 * leaving r10 = ctx, so tainted code is judged exactly as untainted code is.
 * SURGICAL: the other route to that lea (the je at 0x02D17ECF, taken when no
 * taint source is recorded) is untouched, and WoW's own code runs with
 * g_taint == 0 so it never took this branch anyway -- its behaviour is
 * byte-for-byte unchanged. Guarded by an exact 75 07 pattern check, so a stale
 * RVA fails closed instead of stomping.
 *
 * MEASURED CORRECTION (2026-09-01): patching only the jne at 0x02D17EE3 was NOT
 * enough -- it applied cleanly (75 07 matched) and casts were still refused.
 * There are TWO routes to the lea, and ours is the other one: edx comes from
 * [L+0x40][0x24], the recorded taint-source index, and injected code is not a
 * registered addon so that byte is 0. We therefore take the `je 0x2D17EE5` at
 * 0x02D17ECF and never reach the branch that was flipped. NOP the lea itself
 * and every route leaves r10 = ctx.
 *
 * This is broader than the single-branch flip: a legitimate "no recorded
 * source" caller now also gets judged on ctx rather than the default struct.
 * WoW's own protected calls come from secure contexts that pass either way, so
 * the practical exposure is small, but it is a wider change than the jne. */
#define RVA_PROTECTED_CALL_GATE_JNE                        0x02D17EE3  // 69547: jne in the protected-call gate reached from CastSpellByName@0x1AFFFA0 (insufficient alone)
#define RVA_PROTECTED_CALL_GATE_LEA                        0x02D17EE5  // 69547: lea r10,[force-taint struct] -- 7 bytes, NOP to close every route
#define RVA_LOADSTRING_UNTAINTED                           0x02E89070  // 69547: base-lib registration beside loadstring; verified lua_CFunction by disasm
#define RVA_FORCE_TAINT_GATE_A                             0x03BDDDF8  // 69547: loadstring taint gate (je skip when == 0). NOT written.
#define RVA_FORCE_TAINT_GATE_B                             0x03BDDDFC  // 69547: loadstring taint gate (jne skip when != 0). NOT written.
#define RVA_HANDLE_TERRAIN_CLICK                           0x01C06240  // 68887 sig
#define RVA_INTERACT_UNIT                                  0x01F10F60  // 68887 sig
#define RVA_IS_VALUE_NOT_SECRET                            0x02D17E90  // 69547: sig (was 0x02DD15D0)  // 69109: sig (was 0x02D17980)  // CLASSIC 68940 (was retail)  // 68887 sig
#define RVA_LUAG_SECRETERROR                               0x02D152C0  // 69547: sig (was 0x02DCEA00)  // 69109: sig (was 0x02D14DB0)  // CLASSIC 68940 (was retail)  // 68887 sig
#define RVA_LUAH_NEW                                       0x02D224F0  // 69547: sig (was 0x02DDBC30)  // 69109: sig (was 0x02D21FE0)  // CLASSIC 68940 (was retail)  // 68887 sig
#define RVA_LUAL_LOADBUFFER                                0x02E872C0  // 69547: sig (was 0x02F40A00)  // 69109: sig (was 0x02E86DB0)  // CLASSIC 68940 (was retail)  // 68887 sig
#define RVA_LUA_NEWSTATE                                   0x02D24520  // 69547: sig (was 0x02DDDC60)  // 69109: sig (was 0x02D24010)  // CLASSIC 68940 (was retail)  // 68887 sig
#define RVA_LUA_PCALL                                      0x02D18290  // 69547: sig; matches named table lua_pcall (was 0x02DD19D0)  // 69109: sig; matches named table lua_pcall (was 0x02D17D80)  // CLASSIC 68940 (was retail)  // 68887 sig
#define RVA_LUA_PUSHBOOLEAN                                0x02D18380  // 69547: sig (was 0x02DD1AC0)  // 69109: sig (was 0x02D17E70)  // CLASSIC 68940 (was retail)  // 68887 sig
#define RVA_LUA_SETSECRET                                  0x00530890
#define RVA_PRECALL_C_CCLOSURE                             0x0333BA9B
#define RVA_PRECALL_C_LUAFUNC                              0x0333B9C6
#define RVA_PRECALL_LUA_CCLOSURE                           0x0333BA9B
#define RVA_PRECALL_LUA_LUAFUNC                            0x0333B9C6
#define RVA_PRECALL_V1_C_CCLOSURE                          0x0333B79C
#define RVA_PRECALL_V1_C_LUAFUNC                           0x0333B6C9
#define RVA_RESOLVER_CANCALL_BYPASS                        0x004F9709
#define RVA_RESOLVER_LOCKDOWN_BYPASS                       0x004F973B
#define RVA_RETADDR_CHECK                                  0x001D0580  // 69547: the ONLY common callee of luaL_loadbuffer(0x02E872C0) and lua_pcall(0x02D18290), entry byte 0x48 = sub rsp,0x28. The 69109 value 0x001D0590 lands 0x10 INTO the body (cmp esp,0x1c00) so the prologue guard read 0x81 and refused to patch -- which is exactly what aborted mod execution on 69547  // 69109: call#1 of luaL_loadbuffer + #2 lua_pcall + #0 lua_newstate all agree; body fp 79%; entry 0x48 (was 0x001D0580)  // CLASSIC 68940 Eidolon validator (24 callers, RE-derived)  // 68887 caller-validator (Eidolon): 0x1D7E80..0x1D8118, faults movzx eax,[r10] @0x1D8110; 24 callers all discard ret -> entry RET-stomp safe. Re-derived from crash dump (was 68453 0x188EC0)
#define RVA_SECRET_KEY_GATE_0                              0x03342BE2
#define RVA_SECRET_KEY_GATE_1                              0x033430CB
#define RVA_SECRET_KEY_GATE_2                              0x033435AC
// Secret-value taint-PROPAGATION gates (68887 dump-verified via tools/secret_gates.py).
// Each is `test byte[reg+0x11],4; je` guarding a call to the taint-propagation helper
// (luaG_taintpropagate 0x33E4FD0/0x33E4FF0) inside a Lua VM leaf value-op
// (luaO_arith / luaV_lessthan / luaV_tonumber / luaV_tostring / boolean+length ops).
// Flipping imm 0x04->0x00 forces the je (skip-propagate) so tainted mod code's COMPUTED
// values are not re-marked secret -> breaks the chain that raises "arithmetic on a secret
// number value" when a rotation reads unit.health/power. Behaviour-identical for WoW's own
// UNTAINTED code (context bit 4 already 0 -> je already taken). EXCLUDES the settable gate
// 0x33E207D (secret-value-as-table-key store; flipping it crashes -> NULL node deref).
// Re-derive per build: python tools/secret_gates.py  (prints the 5 gate RVAs + veto check).
#define RVA_SECRET_TAINT_GATE_0                            0x02DD242D  // 69109: shape-verified (F6 42 11 04 74) in the runtime dump; was 0x033D8EDD -- 68887 luaO_arith value-op propagate-gate
#define RVA_SECRET_TAINT_GATE_1                            0x02DD255F  // 69109: shape-verified (F6 42 11 04 74) in the runtime dump; was 0x033D900F -- 68887 value-op propagate-gate (arith/concat)
#define RVA_SECRET_TAINT_GATE_2                            0x02DD28ED  // 69109: shape-verified (F6 42 11 04 74) in the runtime dump; was 0x033D939D -- 68887 value-op propagate-gate (compare)
#define RVA_SECRET_TAINT_GATE_3                            0x02DD2AFB  // 69109: shape-verified (F6 42 11 04 74) in the runtime dump; was 0x033D95AB -- 68887 value-op propagate-gate (tonumber/len)
#define RVA_SECRET_TAINT_GATE_4                            0x02DD2E16  // 69109: shape-verified (F6 42 11 04 74) in the runtime dump; was 0x033D98C6 -- 68887 value-op propagate-gate (boolean test)
// secret_val_gate: 68453 dump-verified (cmp byte[reg+9],0; je -> luaG_secreterror), 46 sites
#define RVA_SECRET_VAL_GATE_0                   0x03468479
#define RVA_SECRET_VAL_GATE_1                   0x03468803
#define RVA_SECRET_VAL_GATE_2                   0x03469103
#define RVA_SECRET_VAL_GATE_3                   0x034691A5
#define RVA_SECRET_VAL_GATE_4                   0x034698CD
#define RVA_SECRET_VAL_GATE_5                   0x03469942
#define RVA_SECRET_VAL_GATE_6                   0x03469A28
#define RVA_SECRET_VAL_GATE_7                   0x03469AA2
#define RVA_SECRET_VAL_GATE_8                   0x03469BC9
#define RVA_SECRET_VAL_GATE_9                   0x03469CFC
#define RVA_SECRET_VAL_GATE_10                  0x03469E52
#define RVA_SECRET_VAL_GATE_11                  0x0346A09A
#define RVA_SECRET_VAL_GATE_12                  0x0346A2C9
#define RVA_SECRET_VAL_GATE_13                  0x0346A6F9
#define RVA_SECRET_VAL_GATE_14                  0x0346A7A1
#define RVA_SECRET_VAL_GATE_15                  0x0346A890
#define RVA_SECRET_VAL_GATE_16                  0x0346A92D
#define RVA_SECRET_VAL_GATE_17                  0x0346A99B
#define RVA_SECRET_VAL_GATE_18                  0x0346AA08
#define RVA_SECRET_VAL_GATE_19                  0x0346AAA3
#define RVA_SECRET_VAL_GATE_20                  0x0346AB13
#define RVA_SECRET_VAL_GATE_21                  0x0346C6C7
#define RVA_SECRET_VAL_GATE_22                  0x0346C7E6
#define RVA_SECRET_VAL_GATE_23                  0x0346C95E
#define RVA_SECRET_VAL_GATE_24                  0x0346DA63
#define RVA_SECRET_VAL_GATE_25                  0x0346E66A
#define RVA_SECRET_VAL_GATE_26                  0x0346E7F0
#define RVA_SECRET_VAL_GATE_27                  0x0346E9A0
#define RVA_SECRET_VAL_GATE_28                  0x0346F341
#define RVA_SECRET_VAL_GATE_29                  0x0346F3ED
#define RVA_SECRET_VAL_GATE_30                  0x0346F467
#define RVA_SECRET_VAL_GATE_31                  0x0346F989
#define RVA_SECRET_VAL_GATE_32                  0x0347067A
#define RVA_SECRET_VAL_GATE_33                  0x03470844
#define RVA_SECRET_VAL_GATE_34                  0x034709F5
#define RVA_SECRET_VAL_GATE_35                  0x034712F5
#define RVA_SECRET_VAL_GATE_36                  0x0347137D
#define RVA_SECRET_VAL_GATE_37                  0x034713EB
#define RVA_SECRET_VAL_GATE_38                  0x034719E6
#define RVA_SECRET_VAL_GATE_39                  0x03472463
#define RVA_SECRET_VAL_GATE_40                  0x03472484
#define RVA_SECRET_VAL_GATE_41                  0x0347264D
#define RVA_SECRET_VAL_GATE_42                  0x03472BFB
#define RVA_SECRET_VAL_GATE_43                  0x03472C4C
#define RVA_SECRET_VAL_GATE_44                  0x03472D94
#define RVA_SECRET_VAL_GATE_45                  0x03472DC9
#define RVA_SECRET_VAL_GATE_COUNT               46
#define RVA_SPELL_CAST_PARAMS_VERSION                      0x03F21808
#define RVA_SPELL_CLICK_CONTEXT                            0x03F21930
#define RVA_SPELL_C_CASTSPELL_WRAPPER                      0x024AFAE0
#define RVA_SPELL_C_CAST_GUID_DIRECT                       0x01BF7890  // 68887 sig
#define RVA_SPELL_C_CAST_GUID_IMPL                         0x01C5A8B0  // 68887 sig
#define RVA_SPELL_C_GET_LOCAL_MANAGER                      0x005224A0
#define RVA_SPELL_STOP_TARGETING                           0x01AD2480  // 69547: sig (was 0x01B7B810)  // 69109: sig (was 0x01AD1FA0)  // CLASSIC 68940 (was retail)  // 68887 sig (offline scorecard: was stale 0x01C9FB70 -> mid-instruction garbage; sig unique-matches here)
#define RVA_VALIDATE_CFUNC_PTR                             0x0030EB70  // 69547: verified by disassembly -- mov r8,[rax]; mov rcx,[rax+8]; add rcx,r8; cmp rdx,rcx; cmp rdx,r8 (the [base,base+size) range check) then xor eax,eax; movzx eax,[rax] (the deliberate NULL deref). Entry byte 0x48. The 69109 value 0x0030EB50 sits 0x20 EARLIER, inside the previous function's epilogue (push rax / adc / add rsp,0x28 / ret), so the guard read 0x50 and skipped the patch  // 69109: body fingerprint 81% at delta -0x20; entry 0x48; null+range check confirmed (was 0x0030EB70)  // CLASSIC 68940 Eidolon validator (9 callers, RE-derived)  // 68887 C-func-ptr whitelist (Eidolon): range-checks ptr vs [base,base+size) global @rip+0x4106D96; out-of-range -> deliberate movzx eax,[NULL] crash @0x31FC00. Our dinkr_ bridges are outside .text -> crash on first call. 9 callers all discard ret -> entry RET-stomp safe. Re-derived from crash dump (was 68453 0x2C53A0)
#define RVA_WORLDFRAME_PROJECT_POINT                       0x01C1BD60  // 69547: sig (was 0x01CC7270)  // 69109: sig (was 0x01C1B850)  // CLASSIC 68940 (was retail)  // 68887 sig
#define RVA_WORLD_INTERSECT                                0x0147EC20  // 69547: sig (was 0x01525560)  // 69109: sig (was 0x0147EC00)  // CLASSIC 68940 (was retail)  // 68887 sig
#define RVA_WOWGUID_TO_STRING                              0x02D85C30  // 69547: sig (was 0x02E3F370)  // 69109: sig (was 0x02D85720)  // CLASSIC 68940 (was retail)  // 68887 sig
#define RVA_g_pEntityHandleBuckets                         0x0413FC60  // 68887 g_pEntityRegistry base (872 lea xrefs; ClntObjMgr_GetRegistry). was 0x03EB9C60
#define RVA_g_pObjectMgr                                   0x05D3E2C0  // 69547: riprel 1/1 NOVOTE; delta -0xB90C0 matches G_LUASTATE (was 0x05DF7380)  // 69109: riprel recipe 1/1 vote -- LOW CONFIDENCE, verify live (was 0x05D3E480)  // CLASSIC 68940 (was retail)  // 68887 (was stale 0x05C4E7F0 -> count=1 sentinel = 0-objects). accessor 0x176C38C: mov rax,[rip]; [rax+8]=entries; [rax+0x10]=count; 0x3FFFFFFF walk
#define RVA_g_pRealObjectMgr                               0x05D3E2C0  // 69547: riprel 1/1 NOVOTE; delta -0xB90C0 matches G_LUASTATE (was 0x05DF7380)  // 69109: riprel recipe 1/1 vote -- LOW CONFIDENCE, verify live (was 0x05D3E480)  // CLASSIC 68940 (was retail)  // 68887 same flat all-entities RecordSet manager. was 0x05C4E7F0
#define RVA_g_activePlayerUnit                             0x03C87AE0  // 69547: riprel 43/43 (was 0x03D40990)  // 69109: riprel recipe 43/43 votes (was 0x03C87AD0)  // CLASSIC 68940 (was retail)  // 68887 active-player object ptr (GetActivePlayer: mov rax,[rip]; test; cmove rax,[rip]). used for ActivePlayer tagging by pointer identity

// === NEED MANUAL UPDATE ===
#define RVA_ActivePlayerGUID                               0x045E3C90  // OLD RVA - needs update
#define RVA_FocusGUID                                      0x045E37B0  // OLD RVA - needs update
#define RVA_MouseoverGUID                                  0x049629A0  // 68887 raw global (mouseover UnitToken resolver @0x25623BD). was stale 0x04683478 (zeroed)
#define RVA_NpcTargetGUID                                  0x045E37C0  // OLD RVA - needs update
#define RVA_SPELL_TARGETING_FLAGS                          0x0418AD74  // OLD RVA - needs update
#define RVA_SPELL_TARGETING_GUID                           0x045F7290  // OLD RVA - needs update
#define RVA_TargetGUID                                     0x045E3770  // OLD RVA - needs update
#define RVA_WORLD_ORIGIN_BIAS                              0x0484AFDC  // OLD RVA - needs update
#define RVA_g_CLEU_CurrentEventEntry                       0x05C6B2F8  // OLD RVA - needs update
#define RVA_g_GameStateFlags                               0x0411BCD0  // 69547: riprel 14/14 (was 0x041D4BB0)  // 69109: riprel recipe 14/14 votes (was 0x0411BCA0)  // CLASSIC 68940 (was retail)  // 68887 u16, bit 0x200=in-world (verified @0x1E4FA4 'and ebp,0x200' + @0x534543 'bt eax,9'). was stale 0x04683470
#define RVA_g_MissileInFlightListHead                      0x0418AEE8  // OLD RVA - needs update
#define RVA_g_pZoneMapContext                              0x05C59928  // OLD RVA - needs update

// === Security patch counts ===
#define RVA_FORBIDDEN_TBL_COUNT     9
#define RVA_SECRET_KEY_GATE_COUNT    3
#define RVA_C_API_TYPE_GATE_COUNT    6

#endif /* DINKR_RVA_DEFS_H */
