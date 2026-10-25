# derive_69547.py -- copy of derive_69109.py with the anchor RVAs re-pointed
# at what the 69547 scorecard resolved. The anchors in the original are
# hardcoded 69109 addresses, so running it unchanged on a new dump anchors
# on stale code: DUMMYNODE echoed the previous value and the g_taint gates
# scored zero votes.
#!/usr/bin/env python3
"""derive_69109.py -- re-derive the no-signature globals for a new build.

patch_day.py covers everything with a code signature. This handles the rest:
the indirect globals that only exist as RIP-relative operands inside known
functions. Each is derived from an ANCHOR function whose address we already
trust (from the scorecard or the dump's named-offset table), then
cross-validated where two independent anchors should agree.

    python tools/derive_69109.py <flat_dump> <named_offsets.txt>
"""
import sys, re, struct, os
from collections import Counter

try:
    from capstone import Cs, CS_ARCH_X86, CS_MODE_64
except ImportError:
    raise SystemExit("pip install capstone")

_CLS = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "Winkr", "build", "classic")
DUMP = sys.argv[1] if len(sys.argv) > 1 else os.path.join(_CLS, "WowClassic_69109_full.exe")
NAMES = sys.argv[2] if len(sys.argv) > 2 else os.path.join(_CLS, "classic_69109_offsets.txt")
D = open(DUMP, "rb").read()
md = Cs(CS_ARCH_X86, CS_MODE_64)
md.detail = True

named = {}
for line in open(NAMES, errors="ignore"):
    m = re.match(r"\s*(\w+)\s*=\s*0x([0-9A-Fa-f]+)", line)
    if m:
        named[m.group(1)] = int(m.group(2), 16)
print(f"loaded {len(named):,} named offsets\n")


def dis(rva, count=160):
    return list(md.disasm(D[rva:rva + count * 16], rva))[:count]


def riprel(ins):
    """Resolve a RIP-relative memory operand to an absolute RVA."""
    for op in ins.operands:
        if op.type == 3 and op.mem.base == 41:      # X86_OP_MEM, RIP
            return ins.address + ins.size + op.mem.disp
    return None


def find_in(rva, pred, limit=200):
    out = []
    for ins in dis(rva, limit):
        r = pred(ins)
        if r is not None:
            out.append((ins, r))
        if ins.mnemonic == "ret" and len(out):
            break
    return out


def count_refs(target, sample_mb=None):
    """How many RIP-relative instructions in .text point at `target`."""
    n = 0
    end = len(D) if sample_mb is None else min(len(D), sample_mb << 20)
    pat = struct.pack("<i", 0)  # placeholder; brute scan below
    # brute force: scan for any 4-byte rel32 whose (addr+4+rel) == target
    for i in range(0x1000, min(end, 0x3000000) - 4, 1):
        rel = struct.unpack_from("<i", D, i)[0]
        if i + 4 + rel == target:
            n += 1
    return n


print("=" * 72)
print("1. DUMMYNODE  (anchor: luaH_new)  -- the stale-value crash from the port")
print("=" * 72)
luaH_new = 0x02D224F0      # from the scorecard STALE list
print(f"   luaH_new @ 0x{luaH_new:X}")
cands = find_in(luaH_new, lambda i: riprel(i) if i.mnemonic == "lea" else None, 60)
for ins, tgt in cands[:6]:
    print(f"     0x{ins.address:X}: {ins.mnemonic} {ins.op_str:38} -> 0x{tgt:08X}")
if cands:
    print(f"   >>> RVA_DUMMYNODE = 0x{cands[0][1]:08X}   (was 0x02F19E70)")

print()
print("=" * 72)
print("2. G_TAINT_HANDLER_PTR  (anchors: the secret gates; must all agree)")
print("=" * 72)
anchors = {
    "is_value_not_secret":   0x02D17E90,
    "c_api_secret_arg_gate": 0x02D16E50,
    "luaG_secreterror":      0x02D152C0,
}
votes = Counter()
for name, rva in anchors.items():
    hits = find_in(rva, lambda i: riprel(i) if i.mnemonic == "cmp" and "0" in i.op_str else None, 120)
    for ins, tgt in hits[:3]:
        votes[tgt] += 1
        print(f"   {name:24} 0x{ins.address:X}: {ins.op_str[:44]:44} -> 0x{tgt:08X}")
if votes:
    best, nv = votes.most_common(1)[0]
    print(f"   >>> RVA_G_TAINT_HANDLER_PTR = 0x{best:08X}  ({nv} anchors agree, was 0x03BDDDB0)")

print()
print("=" * 72)
print("3. MOVEMENT  (anchor: MoveForwardStart from the named table)")
print("=" * 72)
mfs = named.get("MoveForwardStart")
print(f"   MoveForwardStart @ 0x{mfs:X}" if mfs else "   MoveForwardStart not in table")
if mfs:
    gate = ctl = evt = None
    calls = []
    flag = None
    for ins in dis(mfs, 90):
        t = riprel(ins)
        if ins.mnemonic == "cmp" and t and gate is None and ", 0" in ins.op_str:
            gate = t
            print(f"     gate   0x{ins.address:X}: {ins.op_str[:44]:44} -> 0x{t:08X}")
        elif ins.mnemonic == "lea" and t and "rcx" in ins.op_str and ctl is None:
            ctl = t
            print(f"     ctl    0x{ins.address:X}: {ins.op_str[:44]:44} -> 0x{t:08X}")
        elif ins.mnemonic == "mov" and t and "esi" in ins.op_str and evt is None:
            evt = t
            print(f"     time   0x{ins.address:X}: {ins.op_str[:44]:44} -> 0x{t:08X}")
        elif ins.mnemonic == "mov" and ins.op_str.startswith("edx, 0x") and flag is None:
            flag = ins.op_str.split("0x")[1]
            print(f"     flag   0x{ins.address:X}: {ins.op_str}")
        elif ins.mnemonic == "call":
            try: calls.append(int(ins.op_str, 16))
            except ValueError: pass
        if ins.mnemonic == "ret":
            break
    print(f"   >>> RVA_INPUT_CONTROL   = 0x{ctl:08X}   (was 0x03A05B60)" if ctl else "   ctl not found")
    print(f"   >>> RVA_INPUT_EVENT_TIME= 0x{evt:08X}   (was 0x03C3CC28)" if evt else "   time not found")
    print(f"   >>> movement gate       = 0x{gate:08X}   (should EQUAL g_taint above)" if gate else "")
    if len(calls) >= 2:
        print(f"   >>> set-bit / dispatch candidates: " + ", ".join(f"0x{c:08X}" for c in calls[:5]))

print()
print("=" * 72)
print("4. cross-check: IsPlayerMoving reads CInputControl+4 (the flags dword)")
print("=" * 72)
ipm = named.get("IsPlayerMoving")
if ipm:
    print(f"   IsPlayerMoving @ 0x{ipm:X}")
    for ins in dis(ipm, 12):
        t = riprel(ins)
        if t:
            print(f"     0x{ins.address:X}: {ins.mnemonic} {ins.op_str[:40]:40} -> 0x{t:08X}  "
                  f"(= InputControl+{t - (ctl or 0):#x})" if ctl else "")
            break
