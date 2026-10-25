#!/usr/bin/env python3
"""derive_cfuncptr.py -- locate validate_cfunc_ptr by body fingerprint.

retaddr_check moved only +0x10, so this region of .text barely shifted. Rather
than guess, take the OLD function's byte body as a fingerprint and find the best
match in a window around the old address in the NEW dump. Then confirm the two
structural facts the patch notes record: entry byte 0x48 (sub rsp,0x28) and a
deliberate NULL-deref later in the body.
"""
import struct, os
from capstone import Cs, CS_ARCH_X86, CS_MODE_64

_CLS = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "Winkr", "build", "classic")
OLD = os.path.join(_CLS, "WowClassic_68940_full.exe")
NEW = os.path.join(_CLS, "WowClassic_69109_full.exe")
DO = open(OLD, "rb").read()
DN = open(NEW, "rb").read()
md = Cs(CS_ARCH_X86, CS_MODE_64)

TARGETS = [
    ("RVA_VALIDATE_CFUNC_PTR", 0x0030EB70),
    ("RVA_RETADDR_CHECK",      0x001D0580),   # control: we already know -> 0x1D0590
    ("RVA_LUA_SETSECRET",      0x00530890),
]
WINDOW = 0x40000          # +/- search range
FPLEN  = 48               # fingerprint length


def norm(b):
    """Mask rel32 operands so a shifted-but-identical function still matches."""
    out = bytearray(b)
    i = 0
    while i < len(out) - 4:
        if out[i] in (0xE8, 0xE9):     # call/jmp rel32 -- displacement will differ
            out[i+1:i+5] = b"\0\0\0\0"
            i += 5
        else:
            i += 1
    return bytes(out)


def score(a, b):
    return sum(1 for x, y in zip(a, b) if x == y)


for name, old_rva in TARGETS:
    fp = norm(DO[old_rva:old_rva + FPLEN])
    best, best_s = None, -1
    lo = max(0x1000, old_rva - WINDOW)
    hi = min(len(DN) - FPLEN, old_rva + WINDOW)
    for cand in range(lo, hi):
        if DN[cand] != DO[old_rva]:      # cheap prefilter on the entry byte
            continue
        s = score(fp, norm(DN[cand:cand + FPLEN]))
        if s > best_s:
            best_s, best = s, cand
    pct = 100.0 * best_s / FPLEN if best is not None else 0
    delta = (best - old_rva) if best is not None else 0
    print(f"{name}")
    print(f"   old 0x{old_rva:08X}  ->  best match 0x{best:08X}  ({pct:.0f}% of {FPLEN} bytes, delta {delta:+#x})")
    if best is not None:
        eb = DN[best]
        print(f"   entry byte 0x{eb:02X} {'OK (sub rsp)' if eb == 0x48 else '<-- guard expects 0x48'}")
        print("   new body:")
        for ins in list(md.disasm(DN[best:best + 64], best))[:7]:
            print(f"     0x{ins.address:X}: {ins.mnemonic} {ins.op_str}")
    print()
