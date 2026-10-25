#!/usr/bin/env python3
"""derive_worldframe.py -- find g_pWorldFrame (the collision/terrain root).

winkr_TraceLine walks:  worldFrame = *g_pWorldFrame
                        mapIndex   = *(u32*)(worldFrame + 0x20)
                        context    = *(worldFrame + 8*mapIndex + 0x10)
                        World_Intersect(context, &ray, &result)

So WoW's own callers of World_Intersect must load that same global and index it
the same way. Find direct callers of World_Intersect, then take the most common
RIP-relative qword load feeding rcx.
"""
import struct, os
from collections import Counter
from capstone import Cs, CS_ARCH_X86, CS_MODE_64

D = open(os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "Winkr", "build", "classic", "WowClassic_69109_full.exe"), "rb").read()
md = Cs(CS_ARCH_X86, CS_MODE_64)
md.detail = True
WORLD_INTERSECT = 0x01525560          # sig-matched on 69109
CURRENT = 0x067BDBD8


def riprel(ins):
    for op in ins.operands:
        if op.type == 3 and op.mem.base == 41:
            return ins.address + ins.size + op.mem.disp
    return None


print("scanning .text for direct callers of World_Intersect ...")
callers = []
for i in range(0x1000, min(len(D), 0x3200000) - 5):
    if D[i] == 0xE8:
        rel = struct.unpack_from("<i", D, i + 1)[0]
        if i + 5 + rel == WORLD_INTERSECT:
            callers.append(i)
            if len(callers) >= 60:
                break
print(f"  {len(callers)} caller site(s)")

votes = Counter()
for c in callers:
    start = max(0x1000, c - 0x200)
    for ins in md.disasm(D[start:c + 8], start):
        if ins.mnemonic == "mov" and ins.op_str.startswith("r"):
            t = riprel(ins)
            if t and 0x3000000 < t < len(D):
                votes[t] += 1

print("\nmost-referenced globals near those calls:")
for rva, n in votes.most_common(10):
    val = struct.unpack_from("<Q", D, rva)[0] if rva + 8 <= len(D) else 0
    # a live pointer global reads 0 in a static dump; garbage means "not a pointer slot"
    looks_ptr = (val == 0) or (0x140000000 <= val <= 0x160000000)
    tag = "  <-- CURRENT (stale)" if rva == CURRENT else ("  plausible ptr slot" if looks_ptr else "")
    print(f"  0x{rva:08X}  {n:3d} refs   static value 0x{val:016X}{tag}")

print("\nNOTE: in a static dump a runtime pointer global reads 0 (it is filled in")
print("at load time). A slot holding random bytes is NOT a pointer global — that is")
print("exactly how the current value was proven stale.")
