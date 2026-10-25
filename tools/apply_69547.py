#!/usr/bin/env python3
"""apply_69547.py -- write the derived 69547 RVAs into shared/rva_defs.h.

Every value here came from either tools/patch_day.py (signature / RIP-relative
recipe) or tools/derive_69109.py (anchored disassembly). Nothing is
extrapolated from a delta -- section shift is region-dependent.
"""
import io, re, sys, os

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))  # repo root (this file lives in tools/)
HDR = os.path.join(REPO, "Winkr", "shared", "rva_defs.h")
NOTE = "69547"

# name -> (new value, provenance)
UPDATES = {
    "RVA_IS_VALUE_NOT_SECRET":       (0x02d17e90, "sig"),
    "RVA_LUAG_SECRETERROR":          (0x02d152c0, "sig"),
    "RVA_C_API_SECRET_ARG_GATE":     (0x02d16e50, "sig"),
    "RVA_LUAL_LOADBUFFER":           (0x02e872c0, "sig"),
    "RVA_LUA_PCALL":                 (0x02d18290, "sig; matches named table lua_pcall"),
    "RVA_SPELL_STOP_TARGETING":      (0x01ad2480, "sig"),
    "RVA_WORLDFRAME_PROJECT_POINT":  (0x01c1bd60, "sig"),
    "RVA_WORLD_INTERSECT":           (0x0147ec20, "sig"),
    "RVA_LUA_NEWSTATE":              (0x02d24520, "sig"),
    "RVA_LUAH_NEW":                  (0x02d224f0, "sig"),
    "RVA_LUA_PUSHBOOLEAN":           (0x02d18380, "sig"),
    "RVA_WOWGUID_TO_STRING":         (0x02d85c30, "sig"),
    "RVA_G_LUASTATE":                (0x05b3c018, "riprel 6/15; delta -0xB90C0 matches g_pObjectMgr"),
    "RVA_g_activePlayerUnit":        (0x03c87ae0, "riprel 43/43"),
    "RVA_g_GameStateFlags":          (0x0411bcd0, "riprel 14/14"),
    "RVA_CAM_MGR":                   (0x03c41c70, "riprel 6/6; world frame derives from this +0x2B8"),
    "RVA_g_pRealObjectMgr":          (0x05d3e2c0, "riprel 1/1 NOVOTE; delta -0xB90C0 matches G_LUASTATE"),
    "RVA_g_pObjectMgr":              (0x05d3e2c0, "riprel 1/1 NOVOTE; delta -0xB90C0 matches G_LUASTATE"),
    "RVA_DUMMYNODE":                 (0x02f19e70, "derived from luaH_new 0x02D224F0; unchanged from 69109"),
    "RVA_G_TAINT_HANDLER_PTR":       (0x03bdddf0, "3 anchors agree: is_value_not_secret, c_api_secret_arg_gate, MoveForwardStart"),
    "RVA_INPUT_CONTROL":             (0x03a05ba0, "MoveForwardStart lea; IsPlayerMoving reads +0x4 = 0x03A05BA4"),
    "RVA_INPUT_EVENT_TIME":          (0x03c3cc68, "MoveForwardStart mov esi"),
}


src = io.open(HDR, encoding="utf-8", newline="").read()
changed, missing, same = [], [], []

for name, (val, why) in UPDATES.items():
    pat = re.compile(r"^(#define\s+" + re.escape(name) + r"\s+)0x([0-9A-Fa-f]+)(.*)$", re.M)
    m = pat.search(src)
    if not m:
        missing.append(name)
        continue
    old = int(m.group(2), 16)
    if old == val:
        same.append(name)
        continue
    comment = m.group(3)
    # keep the historical comment, prepend the new provenance
    newline = f"{m.group(1)}0x{val:08X}  // {NOTE}: {why} (was 0x{old:08X}){comment}"
    src = src[:m.start()] + newline + src[m.end():]
    changed.append((name, old, val))

io.open(HDR, "w", encoding="utf-8", newline="").write(src)

print(f"updated {len(changed)} defines in Winkr/shared/rva_defs.h")
for n, o, v in changed:
    print(f"  {n:38} 0x{o:08X} -> 0x{v:08X}")
if same:
    print(f"\nalready correct ({len(same)}): {', '.join(same)}")
if missing:
    print(f"\n!! NOT FOUND in header ({len(missing)}): {', '.join(missing)}")
