#!/usr/bin/env python3
"""apply_69109.py -- write the derived 69109 RVAs into shared/rva_defs.h.

Every value here came from either tools/patch_day.py (signature / RIP-relative
recipe) or tools/derive_69109.py (anchored disassembly). Nothing is
extrapolated from a delta -- section shift is region-dependent.
"""
import io, re, sys, os

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))  # repo root (this file lives in tools/)
HDR = os.path.join(REPO, "Winkr", "shared", "rva_defs.h")
NOTE = "69109"

# name -> (new value, provenance)
UPDATES = {
    # --- scorecard STALE (unique signature matched at the new address) ---
    "RVA_IS_VALUE_NOT_SECRET":      (0x02DD15D0, "sig"),
    "RVA_LUAG_SECRETERROR":         (0x02DCEA00, "sig"),
    "RVA_C_API_SECRET_ARG_GATE":    (0x02DD0590, "sig"),
    "RVA_LUAL_LOADBUFFER":          (0x02F40A00, "sig"),
    "RVA_LUA_PCALL":                (0x02DD19D0, "sig; matches named table lua_pcall"),
    "RVA_SPELL_STOP_TARGETING":     (0x01B7B810, "sig"),
    "RVA_WORLDFRAME_PROJECT_POINT": (0x01CC7270, "sig"),
    "RVA_WORLD_INTERSECT":          (0x01525560, "sig"),
    "RVA_LUA_NEWSTATE":             (0x02DDDC60, "sig"),
    "RVA_LUAH_NEW":                 (0x02DDBC30, "sig"),
    "RVA_LUA_PUSHBOOLEAN":          (0x02DD1AC0, "sig"),
    "RVA_WOWGUID_TO_STRING":        (0x02E3F370, "sig"),

    # --- RIP-relative recipe, votes agreed ---
    "RVA_G_LUASTATE":               (0x05BF50D8, "riprel recipe 6/15 votes"),
    "RVA_g_activePlayerUnit":       (0x03D40990, "riprel recipe 43/43 votes"),
    "RVA_g_GameStateFlags":         (0x041D4BB0, "riprel recipe 14/14 votes"),
    "RVA_CAM_MGR":                  (0x03CFAB20, "riprel recipe 6/6 votes"),
    "RVA_g_pObjectMgr":             (0x05DF7380, "riprel recipe 1/1 vote -- LOW CONFIDENCE, verify live"),
    "RVA_g_pRealObjectMgr":         (0x05DF7380, "riprel recipe 1/1 vote -- LOW CONFIDENCE, verify live"),

    # --- anchored disassembly (derive_69109.py) ---
    "RVA_DUMMYNODE":                (0x02FD3E70, "luaH_new@0x2DDBC30 lea [rip+0x1f81e0]"),
    "RVA_G_TAINT_HANDLER_PTR":      (0x03C96C70, "3-way: both Lua secret gates + MoveForwardStart gate"),
    "RVA_G_TAINT_GC_SOURCE":        (0x03C96C88, "g_taint + 0x18, same adjacency as 68940"),
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
