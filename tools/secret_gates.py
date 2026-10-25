#!/usr/bin/env python3
"""Re-derive the 5 curated secret-value taint-PROPAGATION gate RVAs for the current
WoW build, and verify the settable store-gate is correctly excluded.

Usage:  python tools/secret_gates.py [path_to_flat_dump.exe]

The dump must be flat-mapped (file offset == RVA), same convention as
tools/offline_scorecard.py. Prints #define lines to paste into Winkr/shared/rva_defs.h
(RVA_SECRET_TAINT_GATE_0..4) plus a PASS/FAIL veto audit.

Gate shape:  test byte[reg+0x11], 4 ; je short   (F6 /0 11 04 74 rel8)
Patch:       imm 0x04 -> 0x00  (force the je -> skip taint propagation on tainted
             mod code's computed values so unit.health math stops erroring).
SAFE gates : leaf value-ops (arith/compare/convert/bool/length); skip-target is a
             short stack-cleanup ending in `ret`.
DANGER gate: luaV_settable store (skip-target begins `lea r*,[rsp+..]` -> call
             luaH_set). Flipping it crashes (NULL node deref). MUST be excluded.
"""
import sys, struct, os
from capstone import Cs, CS_ARCH_X86, CS_MODE_64

DUMP = sys.argv[1] if len(sys.argv) > 1 else os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "Winkr", "build", "Wow_68887_full.exe")
SECRETERR = 0x033D54B0   # RVA_LUAG_SECRETERROR (sig-verified). Update if it moves.
WINDOW    = 0x100000     # secreterror callers cluster within +/-1MB in the Lua VM

D = open(DUMP, "rb").read()
md = Cs(CS_ARCH_X86, CS_MODE_64)

def find_gate(call):
    g = call - 4
    while g + 0xC0 > call:
        if D[g] == 0xF6 and (D[g+1] & 0x38) == 0 and D[g+2] == 0x11 and D[g+4] == 0x74:
            if D[g+3] == 0x04:
                return g
        g -= 1
    return None

def skip_target(g):
    return g + 6 + struct.unpack("<b", D[g+5:g+6])[0]

def is_store_shape(t):
    return D[t] == 0x48 and D[t+1] == 0x8D and D[t+2] in (0x44, 0x4C) and D[t+3] == 0x24

# enumerate E8 callers of luaG_secreterror, back-scan each to its F6/r 11 04 gate
gates = {}
p = SECRETERR - WINDOW
while p < SECRETERR + WINDOW - 5:
    if D[p] == 0xE8 and (p + 5 + struct.unpack("<i", D[p+1:p+5])[0]) & 0xFFFFFFFF == SECRETERR:
        g = find_gate(p)
        if g is not None:
            gates[g] = skip_target(g)
    p += 1

safe, danger = [], []
for g, t in sorted(gates.items()):
    (danger if is_store_shape(t) else safe).append((g, t))

print(f"luaG_secreterror @0x{SECRETERR:X}: {len(gates)} taint gates found\n")
print("--- SAFE leaf value-op gates (patch these) ---")
for i, (g, t) in enumerate(safe):
    print(f"#define RVA_SECRET_TAINT_GATE_{i:<28d} 0x{g:08X}  // 68887 value-op propagate-gate (skip->0x{t:X})")
print(f"\n--- DANGER store gates (EXCLUDED, must not be in the allowlist) ---")
for g, t in danger:
    print(f"  0x{g:08X}  skip->0x{t:X}  (lea r*,[rsp] store-arg setup)")
print(f"\nAudit: {len(safe)} safe / {len(danger)} danger  "
      f"(expected 5 safe / 1 danger on 68887).")
if len(safe) != 5 or len(danger) != 1:
    print("!! COUNT MISMATCH -- inspect manually before shipping.")
