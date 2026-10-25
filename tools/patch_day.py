#!/usr/bin/env python3
"""patch_day.py -- one-command offline patch-day scorecard for a new WoW build.

Consolidates the scattered scratchpad checks (offline_scorecard + secret_gates +
riprel recipes) into a single committed tool. Given a FLAT-MAPPED dump of the new
Wow.exe (file offset == RVA), it reproduces every winkr_scanner.c resolution mode
against Winkr/shared/sig_defs.h + Winkr/shared/rva_defs.h and prints exactly what to update.

    python tools/patch_day.py [path_to_flat_dump.exe]

Modes (mirrors dll/core/winkr_scanner.c):
  skip_scan==0  unique-signature scan   -> target = match + match_offset
  skip_scan==2  RIP-relative plurality  -> target = (match + off + 4) + rel32, voted
  skip_scan==1  raw RVA only            -> UNVERIFIED (no sig; needs manual/live check)

Report buckets: PASS / STALE / BROKEN / RIPREL(AGREE|MISMATCH|NOVOTE) / UNVERIFIED,
then a paste-ready block of `#define` lines for every drifted entry, plus the
secret-value taint-gate derivation (see tools/secret_gates.py).

Flat dump: same convention as tools/offline_scorecard.py. Produce one with the
project's PE flat-mapper (build/run_dump.exe / extract_pe.exe).
"""
import re, sys, struct, os
from collections import Counter

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))  # repo root (this file lives in tools/)
WINKR = os.path.join(REPO, "Winkr")
DUMP = sys.argv[1] if len(sys.argv) > 1 else os.path.join(WINKR, "build", "Wow_68887_full.exe")
SECRETERR_NAME = "LUAG_SECRETERROR"   # anchor for the secret-gate derivation

D = open(DUMP, "rb").read()
IMG = len(D)

# ---- parse rva_defs.h : RVA_<NAME> -> int ---------------------------------
rva = {}
for line in open(os.path.join(WINKR, "shared", "rva_defs.h"), errors="ignore"):
    m = re.match(r'\s*#define\s+RVA_(\w+)\s+0x([0-9A-Fa-f]+)', line)
    if m:
        rva[m.group(1)] = int(m.group(2), 16)

# ---- parse sig_defs.h : X(NAME, skip, off, "pat", "msk") -------------------
sig_txt = open(os.path.join(WINKR, "shared", "sig_defs.h"), errors="ignore").read()
entries = []
for m in re.finditer(r'X\(\s*(\w+)\s*,\s*(\d+)\s*,\s*(-?\d+)\s*,\s*"((?:[^"\\]|\\.)*)"\s*,\s*"((?:[^"\\]|\\.)*)"\s*\)', sig_txt):
    name, skip, off, pat, msk = m.group(1), int(m.group(2)), int(m.group(3)), m.group(4), m.group(5)
    pb = bytes(int(b, 16) for b in re.findall(r'\\x([0-9A-Fa-f]{2})', pat))
    entries.append((name, skip, off, pb, msk))

def _anchor(pb, msk):
    """Longest run of fixed ('x') bytes -> (substring, offset_in_pattern) for C-speed find()."""
    best_len = best_start = 0; run = 0
    for i, c in enumerate(msk):
        if c == 'x':
            run += 1
            if run > best_len:
                best_len = run; best_start = i - run + 1
        else:
            run = 0
    return pb[best_start:best_start + best_len], best_start

def scan_all(pb, msk, limit=64):
    """Anchor on the longest fixed run, jump via bytes.find (C speed), verify the mask."""
    pl = len(msk); hits = []
    if pl == 0 or len(pb) < pl:
        return hits
    anc, ao = _anchor(pb, msk)
    if not anc:
        return hits
    pos = 0
    while True:
        f = D.find(anc, pos)
        if f < 0:
            break
        start = f - ao                       # pattern start implied by anchor position
        if start >= 0 and start + pl <= IMG:
            ok = True
            for j in range(pl):
                if msk[j] == 'x' and D[start + j] != pb[j]:
                    ok = False; break
            if ok:
                hits.append(start)
                if len(hits) >= limit:
                    break
        pos = f + 1
    return hits

def riprel_targets(pb, msk, off):
    """all in-image RIP-relative targets; plurality winner + votes/total."""
    tallies = Counter()
    for m in scan_all(pb, msk):
        rel = struct.unpack_from("<i", D, m + off)[0]
        t = (m + off + 4 + rel) & 0xFFFFFFFF
        if 0 <= t < IMG:
            tallies[t] += 1
    if not tallies:
        return None, 0, 0
    (win, votes), = tallies.most_common(1)
    return win, votes, sum(tallies.values())

PASS, STALE, BROKEN, UNVER = [], [], [], []
RIPREL = []   # (name, verdict, recipe_rva, hard_rva, votes, total)

for name, skip, off, pb, msk in entries:
    hard = rva.get(name)
    if skip == 1:
        UNVER.append(name); continue
    if skip == 2:
        win, votes, total = riprel_targets(pb, msk, off)
        if win is None or votes < 2:
            RIPREL.append((name, "NOVOTE", win or 0, hard or 0, votes, total))
        elif win == hard:
            RIPREL.append((name, "AGREE", win, hard or 0, votes, total))
        else:
            RIPREL.append((name, "MISMATCH", win, hard or 0, votes, total))
        continue
    # skip_scan == 0 : unique signature
    hits = scan_all(pb, msk, limit=3)
    if len(hits) == 1:
        sig_rva = hits[0] + off
        (PASS if sig_rva == hard else STALE).append((name, hard, sig_rva))
    else:
        BROKEN.append((name, len(hits)))

# ---- secret-value taint gate derivation (see tools/secret_gates.py) --------
def derive_secret_gates():
    err = rva.get(SECRETERR_NAME)
    if not err:
        return None
    lo, hi = err - 0x100000, err + 0x100000
    def find_gate(call):
        g = call - 4
        while g + 0xC0 > call:
            if D[g] == 0xF6 and (D[g+1] & 0x38) == 0 and D[g+2] == 0x11 and D[g+4] == 0x74:
                if D[g+3] == 0x04:
                    return g
            g -= 1
        return None
    gates = {}
    p = lo
    while p < hi - 5:
        if D[p] == 0xE8 and (p + 5 + struct.unpack_from("<i", D, p+1)[0]) & 0xFFFFFFFF == err:
            g = find_gate(p)
            if g is not None:
                t = g + 6 + struct.unpack("<b", D[g+5:g+6])[0]
                gates[g] = t
        p += 1
    safe, danger = [], []
    for g, t in sorted(gates.items()):
        store = (D[t] == 0x48 and D[t+1] == 0x8D and D[t+2] in (0x44, 0x4C) and D[t+3] == 0x24)
        (danger if store else safe).append(g)
    return safe, danger

# ------------------------------- report ------------------------------------
print(f"=== WINKR PATCH-DAY SCORECARD ===  dump={DUMP}  ({IMG:,} bytes)")
print(f"sig entries={len(entries)}  |  PASS={len(PASS)} STALE={len(STALE)} BROKEN={len(BROKEN)} "
      f"RIPREL={len(RIPREL)} UNVERIFIED(raw)={len(UNVER)}")

print("\n--- STALE (sig matched, hardcoded RVA drifted -> raw-RVA consumers use WRONG addr) ---")
for name, hard, new in STALE:
    print(f"  #define RVA_{name:<40s} 0x{new:08X}   // was 0x{(hard or 0):08X}")
if not STALE: print("  (none)")

print("\n--- RIPREL recipes (skip_scan==2 self-heal globals) ---")
for name, verdict, recipe, hard, votes, total in RIPREL:
    tag = "" if verdict == "AGREE" else "  <-- UPDATE" if verdict == "MISMATCH" else "  <-- recipe failed, verify manually"
    print(f"  {verdict:8s} RVA_{name:<28s} recipe=0x{recipe:08X} rva=0x{hard:08X} votes={votes}/{total}{tag}")
    if verdict == "MISMATCH":
        print(f"            #define RVA_{name:<40s} 0x{recipe:08X}   // was 0x{hard:08X}")

print("\n--- BROKEN (no unique sig: 0 or multi-match; RVA may still be valid, verify) ---")
for name, nh in BROKEN:
    print(f"  RVA_{name:<40s} hits={nh}  rva=0x{rva.get(name,0):08X}")
if not BROKEN: print("  (none)")

sg = derive_secret_gates()
print("\n--- SECRET-VALUE taint gates (RVA_SECRET_TAINT_GATE_0..4) ---")
if sg is None:
    print("  (LUAG_SECRETERROR RVA unknown -- cannot derive)")
else:
    safe, danger = sg
    for i, g in enumerate(safe):
        cur = rva.get(f"SECRET_TAINT_GATE_{i}")
        tag = "" if cur == g else f"  <-- UPDATE (was 0x{(cur or 0):08X})"
        print(f"  #define RVA_SECRET_TAINT_GATE_{i:<27d} 0x{g:08X}{tag}")
    print(f"  ({len(safe)} safe / {len(danger)} danger" +
          (f", danger@{['0x%X'%d for d in danger]}" if danger else "") +
          "; expected 5 safe / 1 danger on 68887)")
    if len(safe) != 5 or len(danger) != 1:
        print("  !! COUNT MISMATCH -- inspect via tools/secret_gates.py before shipping.")

print("\n--- UNVERIFIED (skip_scan==1, raw RVA only -- indirect globals/struct offsets) ---")
print("  " + ", ".join(UNVER) if UNVER else "  (none)")
print("\nNext: paste STALE + MISMATCH + gate updates into Winkr/shared/rva_defs.h, rebuild, inject,\n"
      "then read the in-DLL [scorecard] log for the live confirmation.")
