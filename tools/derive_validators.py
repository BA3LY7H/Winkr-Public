#!/usr/bin/env python3
"""derive_validators.py -- locate the two Eidolon anti-tamper validators.

They are obfuscated, so they have no usable signature. But they ARE called from
functions we can locate in both builds (luaL_loadbuffer / lua_pcall for
retaddr_check). So: find which call ordinal inside a known caller lands on the
OLD validator, then read the SAME ordinal in the new build.

    python tools/derive_validators.py
"""
import sys, struct, os
from capstone import Cs, CS_ARCH_X86, CS_MODE_64

_CLS = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "Winkr", "build", "classic")
OLD = os.path.join(_CLS, "WowClassic_68940_full.exe")
NEW = os.path.join(_CLS, "WowClassic_69109_full.exe")

# anchors: name -> (old_rva, new_rva)  [from rva_defs history + scorecard]
ANCHORS = {
    "luaL_loadbuffer": (0x02E86DB0, 0x02F40A00),
    "lua_pcall":       (0x02D17D80, 0x02DD19D0),
    "lua_newstate":    (0x02D24010, 0x02DDDC60),
    "luaH_new":        (0x02D21FE0, 0x02DDBC30),
}
OLD_TARGETS = {
    0x001D0580: "RVA_RETADDR_CHECK",
    0x0030EB70: "RVA_VALIDATE_CFUNC_PTR",
}

md = Cs(CS_ARCH_X86, CS_MODE_64)
DO = open(OLD, "rb").read()
DN = open(NEW, "rb").read()


def calls(data, rva, limit=400):
    """Ordered list of (ordinal, insn_addr, target) for direct calls."""
    out, n = [], 0
    for ins in md.disasm(data[rva:rva + limit * 16], rva):
        if ins.mnemonic == "call" and ins.op_str.startswith("0x"):
            try:
                out.append((n, ins.address, int(ins.op_str, 16)))
                n += 1
            except ValueError:
                pass
        if ins.mnemonic == "ret":
            break
    return out


def entry_byte(data, rva):
    return data[rva] if 0 <= rva < len(data) else None


print("=" * 74)
print("Finding which call-ordinal reaches each validator in the OLD build")
print("=" * 74)
found = {}
for name, (orva, nrva) in ANCHORS.items():
    oc = calls(DO, orva)
    for ordn, addr, tgt in oc:
        if tgt in OLD_TARGETS:
            vname = OLD_TARGETS[tgt]
            print(f"  {name:16} call#{ordn:<2} @0x{addr:X} -> 0x{tgt:08X}  = {vname}")
            found.setdefault(vname, []).append((name, ordn))

if not found:
    print("  no direct call from those anchors -- widening to a full .text xref scan")
    for target, vname in OLD_TARGETS.items():
        refs = []
        for i in range(0x1000, 0x3200000):
            if DO[i] == 0xE8:
                rel = struct.unpack_from("<i", DO, i + 1)[0]
                if i + 5 + rel == target:
                    refs.append(i)
                    if len(refs) >= 6:
                        break
        print(f"  {vname}: {len(refs)} caller(s) -> " + ", ".join(f"0x{r:X}" for r in refs))
        found[vname] = [("xref", r) for r in refs]

print()
print("=" * 74)
print("Reading the same ordinal in the NEW build")
print("=" * 74)
results = {}
for vname, sites in found.items():
    votes = {}
    for anchor, ordn in sites:
        if anchor not in ANCHORS:
            continue
        nrva = ANCHORS[anchor][1]
        nc = calls(DN, nrva)
        if ordn < len(nc):
            tgt = nc[ordn][2]
            eb = entry_byte(DN, tgt)
            ok = (eb == 0x48)
            votes[tgt] = votes.get(tgt, 0) + 1
            print(f"  {vname:24} via {anchor:16} call#{ordn:<2} -> 0x{tgt:08X} "
                  f"entry=0x{eb:02X} {'OK (sub rsp)' if ok else '<-- guard byte not 0x48'}")
    if votes:
        best = max(votes, key=votes.get)
        results[vname] = best

print()
print("=" * 74)
print("RESULT")
print("=" * 74)
for vname, rva in results.items():
    eb = entry_byte(DN, rva)
    old = [k for k, v in OLD_TARGETS.items() if v == vname][0]
    flag = "" if eb == 0x48 else "   !! entry byte != 0x48, DLL guard will refuse"
    print(f"  #define {vname:34} 0x{rva:08X}   // 69109 (was 0x{old:08X}){flag}")
if not results:
    print("  nothing resolved -- fall back to manual xref analysis")
