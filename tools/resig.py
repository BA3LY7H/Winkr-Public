#!/usr/bin/env python3
"""resig.py -- recover a function whose signature stopped matching.

A signature fails for one of two reasons: the function genuinely moved and the
bytes changed (a real code edit), or the pattern was always slightly too long
and one instruction inside it shifted. Telling those apart by eye is slow, and
guessing wrong writes a bad address into rva_defs.h.

So: walk the pattern from the front, shortening it one byte at a time, and
report how many places in the dump match each prefix. The point where the count
drops from "thousands" to a handful is where the function's real prologue ends
and the changed instruction begins -- and those handful of hits are the
candidates.

Every candidate is then checked for being a plausible function entry, because a
match in the middle of some unrelated function is worthless.

    python tools/resig.py <dump> <SIG_NAME>
"""
import re
import os
import sys

DUMP = sys.argv[1]
WANT = sys.argv[2] if len(sys.argv) > 2 else None

data = open(DUMP, "rb").read()
_WINKR = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "Winkr")
sigsrc = open(os.path.join(_WINKR, "shared", "sig_defs.h"), encoding="utf-8", errors="replace").read()

# X(NAME , a, b, "\x48\x89...", "xxxx????xx")
ENTRY = re.compile(r'X\(\s*([A-Z0-9_]+)\s*,[^,]*,[^,]*,\s*"((?:\\x[0-9A-Fa-f]{2})+)"\s*,\s*"([x?]+)"')


def unescape(s):
    return bytes(int(b, 16) for b in re.findall(r"\\x([0-9A-Fa-f]{2})", s))


def find_all(pat, mask, limit=64):
    """Count/collect matches of pat where mask[i]=='x' means the byte must equal."""
    fixed = [(i, pat[i]) for i in range(len(pat)) if mask[i] == "x"]
    if not fixed:
        return []
    # Anchor the scan on the longest run of fixed bytes at the start.
    anchor = bytes(pat[i] for i in range(len(pat)) if mask[i] == "x")
    # cheap prefilter on the first 4 fixed bytes
    pre = anchor[:4]
    out, start = [], 0
    while len(out) < limit:
        j = data.find(pre, start)
        if j < 0:
            break
        start = j + 1
        # align: the prefilter bytes are the first 4 fixed positions, which are
        # only at the true offset when the leading mask bytes are all 'x'
        base = j
        ok = True
        for i, b in fixed:
            if base + i >= len(data) or data[base + i] != b:
                ok = False
                break
        if ok:
            out.append(base)
    return out


def looks_like_entry(rva):
    """Function entries here are MSVC x64 prologues. Anything else is a hit
    inside a function body and is not what we want."""
    w = data[rva:rva + 5]
    return (w[:1] in (b"\x48", b"\x40", b"\x4c") or w[:2] in (b"\x53\x48", b"\x55\x48"))


for m in ENTRY.finditer(sigsrc):
    name, patstr, mask = m.group(1), m.group(2), m.group(3)
    if WANT and name != WANT:
        continue
    pat = unescape(patstr)
    n = min(len(pat), len(mask))
    pat, mask = pat[:n], mask[:n]

    print(f"=== {name} ===  pattern {n} bytes")
    full = find_all(pat, mask)
    print(f"  full pattern: {len(full)} match(es)")
    if full:
        for a in full[:6]:
            print(f"     {a:#010x} {'  <-- plausible entry' if looks_like_entry(a) else ''}")
        continue

    # Shorten from the tail until it matches, so we keep the prologue and drop
    # whatever instruction changed.
    for cut in range(n - 1, 5, -1):
        hits = find_all(pat[:cut], mask[:cut], limit=40)
        if hits:
            ent = [h for h in hits if looks_like_entry(h)]
            print(f"  first match at prefix len {cut}: {len(hits)} hit(s), {len(ent)} look like entries")
            for a in (ent or hits)[:8]:
                tail = data[a + cut:a + cut + 6].hex()
                print(f"     {a:#010x}  next bytes after the prefix: {tail}")
            break
    else:
        print("  no prefix of this pattern matches anywhere -- the function was rewritten")
    print()
