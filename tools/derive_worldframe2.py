#!/usr/bin/env python3
"""derive_worldframe2.py -- find g_pWorldFrame by its ACCESS PATTERN, not by
reference counting (which picked a live-but-wrong object and crashed the client).

The bridge walks:
    worldFrame = *g_pWorldFrame            ; mov rax, [rip+X]
    mapIndex   = *(u32*)(worldFrame+0x20)  ; mov ecx, [rax+0x20]
    context    = *(worldFrame + mapIndex*8 + 0x10)  ; mov rcx, [rax+rcx*8+0x10]

That scaled-index load `[reg + reg*8 + 0x10]` right after a `[reg+0x20]` read is
a very specific shape. Find it, and the RIP-relative global feeding it is the
answer.
"""
import struct, os
from collections import Counter
from capstone import Cs, CS_ARCH_X86, CS_MODE_64, x86

D = open(os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "Winkr", "build", "classic", "WowClassic_69109_full.exe"), "rb").read()
md = Cs(CS_ARCH_X86, CS_MODE_64)
md.detail = True
CURRENT_BAD = 0x0601EFA8      # crashed
PREV_STALE  = 0x067BDBD8      # retail leftover, garbage


def riprel(ins):
    for op in ins.operands:
        if op.type == x86.X86_OP_MEM and op.mem.base == x86.X86_REG_RIP:
            return ins.address + ins.size + op.mem.disp
    return None


print("scanning .text for the  [reg + reg*8 + 0x10]  scaled-index load ...")
hits = Counter()
detail = {}

# walk .text in chunks so capstone stays fast
CHUNK = 0x40000
pos = 0x1000
end = min(len(D), 0x3200000)
while pos < end:
    size = min(CHUNK, end - pos)
    recent = {}          # reg -> (global_rva, addr) from a recent rip load
    idx20 = {}           # reg that was used in [reg+0x20]
    for ins in md.disasm(D[pos:pos + size], pos):
        if ins.mnemonic == "mov":
            t = riprel(ins)
            if t and len(ins.operands) and ins.operands[0].type == x86.X86_OP_REG:
                recent[ins.operands[0].reg] = (t, ins.address)
                continue
            for op in ins.operands:
                if op.type == x86.X86_OP_MEM:
                    # [reg + 0x20]  -> mapIndex read
                    if op.mem.base and op.mem.index == 0 and op.mem.disp == 0x20:
                        if op.mem.base in recent:
                            idx20[op.mem.base] = recent[op.mem.base]
                    # [base + index*8 + 0x10] -> context load
                    elif op.mem.base and op.mem.index and op.mem.scale == 8 and op.mem.disp == 0x10:
                        src = recent.get(op.mem.base) or idx20.get(op.mem.base)
                        if src:
                            hits[src[0]] += 1
                            detail.setdefault(src[0], []).append(ins.address)
    pos += size - 0x40   # small overlap so we don't split an instruction pair

print(f"  {sum(hits.values())} matching site(s) across {len(hits)} distinct globals\n")
for rva, n in hits.most_common(8):
    val = struct.unpack_from("<Q", D, rva)[0] if rva + 8 <= len(D) else 0
    tag = ""
    if rva == CURRENT_BAD: tag = "  <-- the value that CRASHED"
    elif rva == PREV_STALE: tag = "  <-- old retail leftover"
    where = ", ".join(f"0x{a:X}" for a in detail[rva][:3])
    print(f"  0x{rva:08X}  {n:3d} hit(s)  value=0x{val:016X}{tag}")
    print(f"      at {where}")

if hits:
    best = hits.most_common(1)[0][0]
    print(f"\n>>> RVA_G_P_WORLD_FRAME = 0x{best:08X}")
    print("    (verify live: TraceLine should report CLEAR in an open field)")
else:
    print("\nno match — the bridge's assumed layout may not hold on this build;")
    print("leave g_pWorldFrame pointing at something unreadable so TraceLine")
    print("fails safe to 'blocked' rather than crashing.")
