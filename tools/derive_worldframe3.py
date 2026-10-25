#!/usr/bin/env python3
"""derive_worldframe3.py -- fast, targeted: what does WoW itself pass as the
first argument (rcx) to World_Intersect?

Only ~33 call sites exist, so disassemble a short window before each and trace
what lands in rcx. That is the collision "context" the bridge is trying to
reconstruct — and whatever global it comes from is g_pWorldFrame.
"""
import struct, os
from collections import Counter
from capstone import Cs, CS_ARCH_X86, CS_MODE_64, x86

D = open(os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "Winkr", "build", "classic", "WowClassic_69109_full.exe"), "rb").read()
md = Cs(CS_ARCH_X86, CS_MODE_64)
md.detail = True
WORLD_INTERSECT = 0x01525560
WINDOW = 0x120


def riprel(ins):
    for op in ins.operands:
        if op.type == x86.X86_OP_MEM and op.mem.base == x86.X86_REG_RIP:
            return ins.address + ins.size + op.mem.disp
    return None


callers = []
for i in range(0x1000, min(len(D), 0x3200000) - 5):
    if D[i] == 0xE8:
        rel = struct.unpack_from("<i", D, i + 1)[0]
        if i + 5 + rel == WORLD_INTERSECT:
            callers.append(i)
print(f"{len(callers)} call sites\n")

globals_seen = Counter()
patterns = Counter()

for ci, c in enumerate(callers):
    start = max(0x1000, c - WINDOW)
    ins_list = list(md.disasm(D[start:c + 5], start))
    # walk backwards from the call, tracking what defines rcx
    want = x86.X86_REG_RCX
    trail = []
    for ins in reversed(ins_list):
        if not ins.operands:
            continue
        dst = ins.operands[0]
        if dst.type == x86.X86_OP_REG and dst.reg == want and ins.mnemonic in ("mov", "lea"):
            trail.append(f"{ins.mnemonic} {ins.op_str}")
            t = riprel(ins)
            if t:
                globals_seen[t] += 1
                patterns[f"direct global -> rcx"] += 1
                break
            src = ins.operands[1] if len(ins.operands) > 1 else None
            if src and src.type == x86.X86_OP_MEM:
                if src.mem.index and src.mem.scale == 8:
                    patterns[f"[base+idx*8+0x{src.mem.disp:X}]"] += 1
                elif src.mem.base:
                    patterns[f"[base+0x{src.mem.disp:X}]"] += 1
                want = src.mem.base or want
            elif src and src.type == x86.X86_OP_REG:
                want = src.reg
            else:
                break
    if ci < 4:
        print(f"  call @0x{c:X}: " + " <- ".join(trail[:4] if trail else ["(rcx not traced)"]))

print("\nhow rcx is formed across all sites:")
for p, n in patterns.most_common(8):
    print(f"  {n:3d}x  {p}")

print("\nglobals that reach rcx directly:")
for rva, n in globals_seen.most_common(8):
    val = struct.unpack_from("<Q", D, rva)[0] if rva + 8 <= len(D) else 0
    print(f"  0x{rva:08X}  {n:3d}x   value=0x{val:016X}")
if globals_seen:
    best = globals_seen.most_common(1)[0][0]
    print(f"\n>>> best candidate for the collision context global: 0x{best:08X}")
