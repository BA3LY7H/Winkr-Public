/*
 * dinkr_scanner.c - Pattern scanner and RVA resolver.
 *
 * Strategy (per entry in sig_defs.h):
 *   1. If skip_scan == 1: use hardcoded RVA directly.
 *   2. Else scan every readable committed page in the module image for
 *      the byte/mask pattern.
 *   3. If exactly one match across all scanned pages:
 *        addr = match + match_offset  (sig source).
 *   4. If zero or multiple matches: addr = base + rva  (RVA fallback,
 *      warning logged).
 *
 * Scan safety:
 *   - Only committed readable pages within SizeOfImage are touched.
 *   - Guard/noaccess pages are always skipped.
 *   - The scanner is not limited to .text or any per-entry scope.
 *
 * Scan performance:
 *   - First-byte fast skip: positions where region[i] != pattern[0] are
 *     skipped without a full compare (unless pattern[0] is wildcard).
 *   - Scan stops after finding a second match (no need to count them all).
 *   - No heap allocation; all working state is on the stack.
 *
 * Results are cached in g_dinkr_addrs[] after the one-time startup call.
 */

#include "dinkr_scanner.h"
#include "dinkr_internal.h"
#include <string.h>
#include <stdio.h>

/* ========================================================================
** Internal signature table (built from sig_defs.h X-macro)
** ======================================================================== */

typedef struct {
    const char*  name;
    uint32_t     rva;
    int          skip_scan;
    int32_t      match_offset;
    const char*  pattern;    /* raw bytes; use mask length - may contain \x00 */
    const char*  mask;       /* 'x'=exact byte, '?'=wildcard; no embedded nulls */
} DinkrSigEntry;

#define _SIG_ENTRY(name, skip, off, pat, msk) \
    { "RVA_" #name, (uint32_t)(RVA_##name), (skip), (int32_t)(off), (pat), (msk) },

static const DinkrSigEntry s_sigs[] = {
    DINKR_SIG_TABLE(_SIG_ENTRY)
};

#undef _SIG_ENTRY

/* Compile-time sanity: table length must equal SIGID_COUNT */
typedef char _sig_count_check[
    (sizeof(s_sigs) / sizeof(s_sigs[0]) == SIGID_COUNT) ? 1 : -1
];

/* ========================================================================
** Resolved address cache
** ======================================================================== */

static uintptr_t g_dinkr_addrs[SIGID_COUNT];

uintptr_t DinkrGetAddr(DinkrSigID id) {
    if ((unsigned)id >= (unsigned)SIGID_COUNT) return 0;
    return g_dinkr_addrs[id];
}

/* ========================================================================
** Memory readability helpers
** ======================================================================== */

static int is_readable_protect(DWORD protect) {
    DWORD baseProtect = protect & 0xFF;

    if (protect & PAGE_GUARD) return 0;
    if (baseProtect == PAGE_NOACCESS) return 0;

    switch (baseProtect) {
        case PAGE_READONLY:
        case PAGE_READWRITE:
        case PAGE_WRITECOPY:
        case PAGE_EXECUTE_READ:
        case PAGE_EXECUTE_READWRITE:
        case PAGE_EXECUTE_WRITECOPY:
            return 1;
        default:
            return 0;
    }
}

/* ========================================================================
** Pattern scanner
**
** Scans [region, region+region_size) for `pattern`/`mask` (length from
** strlen(mask)).  Returns:
**   0      - no match found
**   1      - exactly one match; *out_match set
**  -1      - two or more matches (not unique); *out_match set to first
** ======================================================================== */

static int scan_pattern(LPBYTE region, size_t region_size,
                         const char* pattern, const char* mask,
                         LPBYTE* out_match) {
    size_t pat_len = strlen(mask);
    if (!pat_len || pat_len > region_size) return 0;

    const uint8_t* pat  = (const uint8_t*)pattern;
    size_t         span = region_size - pat_len;

    uint8_t first      = pat[0];
    int     first_wild = (mask[0] == '?');

    int     found     = 0;
    LPBYTE  first_hit = NULL;

    for (size_t i = 0; i <= span; i++) {
        if (!first_wild && region[i] != first) continue;

        int ok = 1;
        for (size_t j = 1; j < pat_len; j++) {
            if (mask[j] == 'x' && region[i + j] != pat[j]) {
                ok = 0;
                break;
            }
        }

        if (ok) {
            found++;
            if (found == 1) {
                first_hit = region + i;
            } else {
                *out_match = first_hit;
                return -1;
            }
        }
    }

    *out_match = first_hit;
    return found; /* 0 or 1 */
}

/* Scan across every readable committed page inside the module image,
 * accumulating total match count. Returns same semantics as scan_pattern. */
static int scan_readable_image(LPBYTE base, size_t img_bound,
                                const char* pattern, const char* mask,
                                LPBYTE* out_match, int* out_regions) {
    int       total     = 0;
    LPBYTE    first_hit = NULL;
    uintptr_t cur;
    uintptr_t end;

    *out_match = NULL;
    *out_regions = 0;
    if (!base || !img_bound) return 0;

    cur = (uintptr_t)base;
    end = cur + img_bound;

    while (cur < end) {
        MEMORY_BASIC_INFORMATION mbi;
        uintptr_t region_start;
        uintptr_t region_end;
        uintptr_t scan_start;
        uintptr_t scan_end;

        if (!VirtualQuery((LPCVOID)cur, &mbi, sizeof(mbi))) break;

        region_start = (uintptr_t)mbi.BaseAddress;
        region_end   = region_start + (uintptr_t)mbi.RegionSize;
        if (region_end <= cur) break;

        if (mbi.State == MEM_COMMIT && is_readable_protect(mbi.Protect)) {
            scan_start = (region_start < (uintptr_t)base)
                       ? (uintptr_t)base
                       : region_start;
            scan_end = (region_end > end) ? end : region_end;

            if (scan_start < scan_end) {
                LPBYTE hit = NULL;
                int res;

                (*out_regions)++;
                res = scan_pattern((LPBYTE)scan_start,
                                   (size_t)(scan_end - scan_start),
                                   pattern, mask, &hit);
                if (res == -1) {
                    *out_match = hit;
                    return -1;
                }
                if (res == 1) {
                    total++;
                    if (total == 1) first_hit = hit;
                    if (total >= 2) {
                        *out_match = first_hit;
                        return -1;
                    }
                }
            }
        }

        cur = region_end;
    }

    *out_match = first_hit;
    return total; /* 0 or 1 */
}

/* ========================================================================
** RIP-relative plurality resolver (skip_scan == 2)
**
** For a DATA GLOBAL with no unique code accessor: scan every readable page for
** an accessor pattern (a `mov/lea reg,[rip+disp]`-style instruction, disp32 at
** `rel_off` within the match), compute the RIP-relative target for EVERY match,
** and return the most-common target (plurality vote). Robust when the same
** global is loaded by several (possibly obfuscated) accessors, and when the
** pattern also matches unrelated accessors -- the correct global wins by count.
**
** Returns the winning absolute VA (0 if none). *out_votes = winner's count,
** *out_total = total accessor matches (confidence = votes/total).
** ======================================================================== */
static uintptr_t scan_riprel_plurality(LPBYTE base, size_t img_bound,
                                       const char* pattern, const char* mask,
                                       int rel_off,
                                       int* out_votes, int* out_total) {
    enum { RIPREL_MAX = 64 };
    uintptr_t tgt[RIPREL_MAX];
    int       votes[RIPREL_MAX];
    int       nt = 0, total = 0;

    if (out_votes) *out_votes = 0;
    if (out_total) *out_total = 0;

    size_t pat_len = strlen(mask);
    if (!base || !img_bound || rel_off < 0 || pat_len < (size_t)(rel_off + 4))
        return 0;

    uint8_t first      = (uint8_t)pattern[0];
    int     first_wild = (mask[0] == '?');
    uintptr_t cur = (uintptr_t)base;
    uintptr_t end = cur + img_bound;

    while (cur < end) {
        MEMORY_BASIC_INFORMATION mbi;
        if (!VirtualQuery((LPCVOID)cur, &mbi, sizeof(mbi))) break;
        uintptr_t rs = (uintptr_t)mbi.BaseAddress;
        uintptr_t re = rs + (uintptr_t)mbi.RegionSize;
        if (re <= cur) break;

        if (mbi.State == MEM_COMMIT && is_readable_protect(mbi.Protect)) {
            uintptr_t ss = (rs < (uintptr_t)base) ? (uintptr_t)base : rs;
            uintptr_t se = (re > end) ? end : re;
            if (ss + pat_len <= se) {
                LPBYTE reg = (LPBYTE)ss;
                size_t span = (size_t)(se - ss) - pat_len;
                for (size_t i = 0; i <= span; i++) {
                    if (!first_wild && reg[i] != first) continue;
                    int ok = 1;
                    for (size_t j = 1; j < pat_len; j++) {
                        if (mask[j] == 'x' && reg[i + j] != (uint8_t)pattern[j]) { ok = 0; break; }
                    }
                    if (!ok) continue;

                    int32_t rel;
                    memcpy(&rel, reg + i + rel_off, 4);
                    /* disp is relative to the byte after the disp32, which for a
                     * standard `REX 8B/8D modrm disp32` instruction is the end
                     * of the instruction. */
                    uintptr_t t = (uintptr_t)(reg + i + rel_off + 4) + (intptr_t)rel;
                    if (t < (uintptr_t)base || t >= end) continue; /* in-image only */

                    total++;
                    int f = -1;
                    for (int k = 0; k < nt; k++) if (tgt[k] == t) { f = k; break; }
                    if (f >= 0) votes[f]++;
                    else if (nt < RIPREL_MAX) { tgt[nt] = t; votes[nt] = 1; nt++; }
                }
            }
        }
        cur = re;
    }

    int bi = -1, bv = 0;
    for (int k = 0; k < nt; k++) if (votes[k] > bv) { bv = votes[k]; bi = k; }
    if (out_votes) *out_votes = bv;
    if (out_total) *out_total = total;
    return (bi >= 0) ? tgt[bi] : 0;
}

/* Scorecard: SIGIDs whose sig is known-broken but whose RVA is hand-derived +
 * verified this build, so a BROKEN sig on them is expected, not action-needed.
 * Kept as name suffixes (matched against e->name "RVA_<suffix>"). */
static int scorecard_known_handled(const char* name) {
    static const char* ok[] = {
        "RVA_RETADDR_CHECK",       /* Eidolon validator, RVA hand-derived + applied */
        "RVA_VALIDATE_CFUNC_PTR",  /* Eidolon validator, RVA hand-derived + applied */
        "RVA_SPELL_STOP_TARGETING",/* RVA re-derived + live-verified */
        "RVA_LUA_SETSECRET",       /* not consumed anywhere -- dead entry */
    };
    for (int i = 0; i < (int)(sizeof(ok) / sizeof(ok[0])); i++)
        if (strcmp(name, ok[i]) == 0) return 1;
    return 0;
}

/* ========================================================================
** DinkrResolveAllAddrs
** ======================================================================== */

void DinkrResolveAllAddrs(LPBYTE base, size_t image_size) {
    char logBuf[256];

    /* Determine authoritative image bound */
    size_t img_bound = image_size;
    if (!img_bound) {
        /* Read SizeOfImage from PE headers as fallback */
        PIMAGE_DOS_HEADER dos = (PIMAGE_DOS_HEADER)base;
        if (base && dos->e_magic == IMAGE_DOS_SIGNATURE &&
            dos->e_lfanew > 0 && (DWORD)dos->e_lfanew <= 0x1000) {
            PIMAGE_NT_HEADERS nt =
                (PIMAGE_NT_HEADERS)(base + dos->e_lfanew);
            if (nt->Signature == IMAGE_NT_SIGNATURE)
                img_bound = (size_t)nt->OptionalHeader.SizeOfImage;
        }
        if (!img_bound)
            img_bound = 0x20000000; /* 512 MiB safety cap */
    }

    snprintf(logBuf, sizeof(logBuf),
             "[scanner] init: base=%p image_size=0x%zX img_bound=0x%zX",
             (void*)base, image_size, img_bound);
    DebugLog(logBuf);

    int n = (int)(sizeof(s_sigs) / sizeof(s_sigs[0]));

    /* Scorecard accumulators: sig-matched entries whose hardcoded RVA has
     * drifted (STALE), sigs that stopped matching (BROKEN), skip_scan
     * (UNVERIFIED), and clean sig==rva (PASS). The STALE list is the
     * patch-day worklist -- exactly which rva_defs.h lines to update. */
    int sc_pass = 0, sc_stale = 0, sc_broken = 0, sc_skip = 0;
    uint32_t sc_stale_idx[SIGID_COUNT];
    uint32_t sc_stale_new[SIGID_COUNT];
    int sc_stale_n = 0;
    uint32_t sc_broken_idx[SIGID_COUNT];
    int sc_broken_n = 0;
    /* RIP-relative (skip_scan==2) tracking for the scorecard */
    uint32_t sc_rr_idx[SIGID_COUNT];
    uint32_t sc_rr_new[SIGID_COUNT];
    uint16_t sc_rr_votes[SIGID_COUNT];
    uint16_t sc_rr_total[SIGID_COUNT];
    uint8_t  sc_rr_match[SIGID_COUNT];   /* 1 = resolved==RVA (recipe agrees) */
    int sc_rr_n = 0;

    for (int i = 0; i < n; i++) {
        const DinkrSigEntry* e = &s_sigs[i];
        uintptr_t rva_addr     = (uintptr_t)base + e->rva;

        if (e->skip_scan == 2) {
            /* RIP-relative plurality resolve. Consumers still read raw RVA until
             * migrated, so storing the resolved value is non-breaking; the
             * scorecard reports recipe-vs-RVA so we can prove it before switching.
             * Trust the recipe only with >=2 concurring votes; else keep RVA. */
            int votes = 0, total = 0;
            uintptr_t rr = scan_riprel_plurality(base, img_bound, e->pattern,
                                                 e->mask, e->match_offset,
                                                 &votes, &total);
            uintptr_t chosen = (rr && votes >= 2) ? rr : rva_addr;
            g_dinkr_addrs[i] = chosen;
            uint32_t rr_rva = rr ? (uint32_t)(rr - (uintptr_t)base) : 0;
            if (sc_rr_n < SIGID_COUNT) {
                sc_rr_idx[sc_rr_n]   = (uint32_t)i;
                sc_rr_new[sc_rr_n]   = rr_rva;
                sc_rr_votes[sc_rr_n] = (uint16_t)votes;
                sc_rr_total[sc_rr_n] = (uint16_t)total;
                sc_rr_match[sc_rr_n] = (rr && rr_rva == e->rva) ? 1 : 0;
                sc_rr_n++;
            }
            snprintf(logBuf, sizeof(logBuf),
                     "[scanner] %s: riprel 0x%08X (rva=0x%08X votes=%d/%d) %s",
                     e->name, rr_rva, e->rva, votes, total,
                     (rr && rr_rva == e->rva) ? "AGREE" :
                     (rr && votes >= 2) ? "RECIPE-WINS" : "fallback=RVA");
            DebugLog(logBuf);
            continue;
        }

        if (e->skip_scan) {
            g_dinkr_addrs[i] = rva_addr;
            sc_skip++;
            snprintf(logBuf, sizeof(logBuf),
                     "[scanner] %s: RVA 0x%08X (skip_scan)",
                     e->name, e->rva);
            DebugLog(logBuf);
            continue;
        }

        LPBYTE hit      = NULL;
        int    nregions = 0;
        int    count    = scan_readable_image(base, img_bound,
                                              e->pattern, e->mask,
                                              &hit, &nregions);

        if (count == 1) {
            uintptr_t sig_addr = (uintptr_t)hit +
                                 (uintptr_t)(intptr_t)e->match_offset;
            g_dinkr_addrs[i] = sig_addr;
            snprintf(logBuf, sizeof(logBuf),
                     "[scanner] %s: sig match 0x%zX (RVA=0x%08X regions=%d)",
                     e->name,
                     (size_t)(sig_addr - (uintptr_t)base),
                     e->rva, nregions);
            DebugLog(logBuf);

            if (sig_addr != rva_addr) {
                sc_stale++;
                if (sc_stale_n < SIGID_COUNT) {
                    sc_stale_idx[sc_stale_n] = (uint32_t)i;
                    sc_stale_new[sc_stale_n] = (uint32_t)(sig_addr - (uintptr_t)base);
                    sc_stale_n++;
                }
                snprintf(logBuf, sizeof(logBuf),
                         "[scanner] WARN %s: sig=0x%zX rva=0x%08X"
                         " -- RVA stale?",
                         e->name,
                         (size_t)(sig_addr - (uintptr_t)base),
                         e->rva);
                DebugLog(logBuf);
            } else {
                sc_pass++;
            }
        } else {
            g_dinkr_addrs[i] = rva_addr;
            sc_broken++;
            if (sc_broken_n < SIGID_COUNT) sc_broken_idx[sc_broken_n++] = (uint32_t)i;
            if (nregions == 0) {
                snprintf(logBuf, sizeof(logBuf),
                         "[scanner] WARN %s: no readable committed regions,"
                         " using RVA 0x%08X",
                         e->name, e->rva);
            } else if (count == 0) {
                snprintf(logBuf, sizeof(logBuf),
                         "[scanner] WARN %s: no match (regions=%d),"
                         " using RVA 0x%08X",
                         e->name, nregions, e->rva);
            } else {
                snprintf(logBuf, sizeof(logBuf),
                         "[scanner] WARN %s: multi-match (regions=%d),"
                         " using RVA 0x%08X",
                         e->name, nregions, e->rva);
            }
            DebugLog(logBuf);
        }
    }

    DebugLog("[scanner] resolve complete");

    /* ===================== PATCH-DAY SCORECARD =====================
     * One glance tells you the health of every offset for this build:
     *   PASS    = sig matched and hardcoded RVA agrees (nothing to do)
     *   STALE   = sig matched but RVA drifted -> raw-RVA consumers use the
     *             WRONG address; update rva_defs.h to the NEW value listed
     *   BROKEN  = sig stopped matching (function changed) -> needs a new sig
     *             or hand-derivation; running on the (possibly stale) RVA
     *   SKIP    = skip_scan hardcoded, not sig-verifiable (globals/gates) */
    {
        DebugLog("[scorecard] ================ PATCH-DAY HEALTH ================");
        snprintf(logBuf, sizeof(logBuf),
                 "[scorecard] sigs: %d PASS / %d STALE / %d BROKEN  (skip_scan: %d)  total: %d",
                 sc_pass, sc_stale, sc_broken, sc_skip, n);
        DebugLog(logBuf);

        if (sc_stale_n > 0) {
            DebugLog("[scorecard] STALE RVAs -- update rva_defs.h to these NEW values:");
            for (int k = 0; k < sc_stale_n; k++) {
                const DinkrSigEntry* e = &s_sigs[sc_stale_idx[k]];
                snprintf(logBuf, sizeof(logBuf),
                         "[scorecard]   #define %-34s 0x%08X   (was 0x%08X)",
                         e->name, sc_stale_new[k], e->rva);
                DebugLog(logBuf);
            }
        }
        /* Split BROKEN into known-handled (RVA hand-verified -> expected) and
         * genuinely-unknown (real action). Only unknowns count toward "action". */
        int sc_broken_action = 0;
        if (sc_broken_n > 0) {
            for (int k = 0; k < sc_broken_n; k++) {
                const DinkrSigEntry* e = &s_sigs[sc_broken_idx[k]];
                if (!scorecard_known_handled(e->name)) sc_broken_action++;
            }
            if (sc_broken_action > 0) {
                DebugLog("[scorecard] BROKEN sigs (no unique match, RVA NOT verified -- ACTION):");
                for (int k = 0; k < sc_broken_n; k++) {
                    const DinkrSigEntry* e = &s_sigs[sc_broken_idx[k]];
                    if (scorecard_known_handled(e->name)) continue;
                    snprintf(logBuf, sizeof(logBuf),
                             "[scorecard]   %-34s RVA 0x%08X (verify / re-sig)",
                             e->name, e->rva);
                    DebugLog(logBuf);
                }
            }
            int known = sc_broken_n - sc_broken_action;
            if (known > 0) {
                snprintf(logBuf, sizeof(logBuf),
                         "[scorecard] %d BROKEN sig(s) are known-handled (RVA hand-verified) -- OK, no action.",
                         known);
                DebugLog(logBuf);
            }
        }

        /* RIP-relative self-healing globals (skip_scan==2). AGREE = recipe
         * matches RVA (healthy). MISMATCH = recipe found a different address
         * than the hardcode -> if the recipe is proven, that's a self-heal
         * catch; verify before trusting. */
        if (sc_rr_n > 0) {
            DebugLog("[scorecard] RIP-relative globals (self-healing recipes):");
            for (int k = 0; k < sc_rr_n; k++) {
                const DinkrSigEntry* e = &s_sigs[sc_rr_idx[k]];
                snprintf(logBuf, sizeof(logBuf),
                         "[scorecard]   %-30s recipe 0x%08X vs rva 0x%08X  votes=%u/%u  %s",
                         e->name, sc_rr_new[k], e->rva,
                         (unsigned)sc_rr_votes[k], (unsigned)sc_rr_total[k],
                         sc_rr_match[k] ? "AGREE" :
                         (sc_rr_new[k] ? "MISMATCH -- verify" : "NO-MATCH (fell back to RVA)"));
                DebugLog(logBuf);
            }
        }

        int action = sc_stale + sc_broken_action;
        if (action == 0) {
            DebugLog("[scorecard] all sig-backed offsets HEALTHY for this build. No action needed.");
        } else {
            snprintf(logBuf, sizeof(logBuf),
                     "[scorecard] ^ ACTION: %d offset(s) need attention (see STALE/BROKEN above).",
                     action);
            DebugLog(logBuf);
        }
        DebugLog("[scorecard] ==================================================");
    }
}

