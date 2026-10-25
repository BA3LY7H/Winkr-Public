/*
** dinkr_om.c — IPC-backed Object Manager helpers for DINKR DLL
**
** Build: 66838
** The DLL no longer enumerates the OM — the GUI does that via RPM.
** This file provides safe in-process memory read helpers and IPC lookups.
*/

#include "dinkr_om.h"
#include "../shared/wow_guid_format.h"
#include <string.h>
#include <stdio.h>

extern LPBYTE g_wowBase;
extern size_t g_wowModuleSize;

#define OM_LOHI_INDEX_CAPACITY      4096u
#define OM_LOHI_INDEX_MASK          (OM_LOHI_INDEX_CAPACITY - 1u)
#define OM_GUID_INDEX_CAPACITY      4096u
#define OM_GUID_INDEX_MASK          (OM_GUID_INDEX_CAPACITY - 1u)
#define OM_PAGE_CACHE_CAPACITY      1024u
#define OM_PAGE_CACHE_MASK          (OM_PAGE_CACHE_CAPACITY - 1u)
#define OM_CANONICAL_USER_MAX       0x0000800000000000ULL

typedef struct {
    DinkrIPC* ipc;
    uint32_t tick;
    uint32_t count;
    uint32_t slots[OM_LOHI_INDEX_CAPACITY]; /* idx+1, 0 = empty */
} OmLohiIndex;

typedef struct {
    DinkrIPC* ipc;
    uint32_t tick;
    uint32_t count;
    uint32_t slots[OM_GUID_INDEX_CAPACITY]; /* idx+1, 0 = empty */
} OmGuidIndex;

typedef struct {
    uintptr_t page;
    uint8_t readable;
} OmPageCacheEntry;

typedef struct {
    DinkrIPC* ipc;
    uint32_t tick;
    uint64_t lo;
    uint64_t hi;
    uint32_t slot; /* idx+1, 0 = miss */
} OmLohiLookupCache;

typedef struct {
    DinkrIPC* ipc;
    uint32_t tick;
    uint32_t hash;
    uint16_t key_len;
    uint16_t _pad;
    char key[80];
    uint32_t slot; /* idx+1, 0 = miss */
} OmGuidLookupCache;

typedef struct {
    volatile DWORD tid;
    OmLohiIndex lohi_index;
    OmGuidIndex guid_index;
    OmPageCacheEntry page_cache[OM_PAGE_CACHE_CAPACITY];
    DWORD page_cache_flush_tick;
    OmLohiLookupCache last_lohi_lookup;
    OmGuidLookupCache last_guid_lookup;
} OmThreadState;

static OmThreadState g_thread_state_a = { 0 };
static OmThreadState g_thread_state_b = { 0 };

static inline uint32_t om_clamped_count(DinkrIPC* ipc) {
    uint32_t count = ipc ? ipc->om_object_count : 0;
    if (count > MAX_OM_OBJECTS) count = MAX_OM_OBJECTS;
    return count;
}

static inline uint32_t om_hash_u64(uint64_t v) {
    v ^= v >> 33;
    v *= 0xff51afd7ed558ccdULL;
    v ^= v >> 33;
    v *= 0xc4ceb9fe1a85ec53ULL;
    v ^= v >> 33;
    return (uint32_t)v;
}

static inline uint32_t om_hash_guid_pair(uint64_t lo, uint64_t hi) {
    uint64_t mixed = lo ^ (hi + 0x9E3779B97F4A7C15ULL + (lo << 6) + (lo >> 2));
    return om_hash_u64(mixed);
}

static inline uint32_t om_hash_guid_str(const char* s) {
    uint32_t h = 2166136261u; /* FNV-1a */
    while (*s) {
        h ^= (uint8_t)(*s++);
        h *= 16777619u;
    }
    return h;
}

static inline int om_protect_readable(DWORD protect) {
    if (protect & (PAGE_GUARD | PAGE_NOACCESS)) return 0;
    switch (protect & 0xFFu) {
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

static void om_reset_lookup_cache(OmThreadState* ts) {
    if (!ts) return;
    memset(&ts->last_lohi_lookup, 0, sizeof(ts->last_lohi_lookup));
    memset(&ts->last_guid_lookup, 0, sizeof(ts->last_guid_lookup));
}

static inline void om_cache_lohi_lookup(OmThreadState* ts, DinkrIPC* ipc, uint32_t tick, uint64_t lo, uint64_t hi, uint32_t slot) {
    OmLohiLookupCache* c = &ts->last_lohi_lookup;
    c->ipc = ipc;
    c->tick = tick;
    c->lo = lo;
    c->hi = hi;
    c->slot = slot;
}

static inline void om_cache_guid_lookup(OmThreadState* ts, DinkrIPC* ipc, uint32_t tick, const char* key, size_t key_len, uint32_t hash, uint32_t slot) {
    OmGuidLookupCache* c = &ts->last_guid_lookup;
    if (!key || key_len >= sizeof(c->key)) {
        c->ipc = NULL;
        c->tick = 0;
        c->hash = 0;
        c->key_len = 0;
        c->key[0] = '\0';
        c->slot = 0;
        return;
    }
    c->ipc = ipc;
    c->tick = tick;
    c->hash = hash;
    c->key_len = (uint16_t)key_len;
    memcpy(c->key, key, key_len);
    c->key[key_len] = '\0';
    c->slot = slot;
}

static OmThreadState* om_get_thread_state(void) {
    DWORD tid = GetCurrentThreadId();

    DWORD a_tid = g_thread_state_a.tid;
    if (a_tid == tid) return &g_thread_state_a;
    if (a_tid == 0) {
        if (InterlockedCompareExchange((volatile LONG*)&g_thread_state_a.tid, (LONG)tid, 0) == 0) {
            memset(&g_thread_state_a.lohi_index, 0, sizeof(g_thread_state_a.lohi_index));
            memset(&g_thread_state_a.guid_index, 0, sizeof(g_thread_state_a.guid_index));
            memset(g_thread_state_a.page_cache, 0, sizeof(g_thread_state_a.page_cache));
            g_thread_state_a.page_cache_flush_tick = 0;
            om_reset_lookup_cache(&g_thread_state_a);
            return &g_thread_state_a;
        }
        if (g_thread_state_a.tid == tid) return &g_thread_state_a;
    }

    DWORD b_tid = g_thread_state_b.tid;
    if (b_tid == tid) return &g_thread_state_b;
    if (b_tid == 0) {
        if (InterlockedCompareExchange((volatile LONG*)&g_thread_state_b.tid, (LONG)tid, 0) == 0) {
            memset(&g_thread_state_b.lohi_index, 0, sizeof(g_thread_state_b.lohi_index));
            memset(&g_thread_state_b.guid_index, 0, sizeof(g_thread_state_b.guid_index));
            memset(g_thread_state_b.page_cache, 0, sizeof(g_thread_state_b.page_cache));
            g_thread_state_b.page_cache_flush_tick = 0;
            om_reset_lookup_cache(&g_thread_state_b);
            return &g_thread_state_b;
        }
        if (g_thread_state_b.tid == tid) return &g_thread_state_b;
    }

    return &g_thread_state_a;
}

static int om_is_readable_page(uintptr_t page) {
    /* Fast path: addresses within WoW's own module are always readable
     * (.text, .data, .rdata, .bss — all committed and readable) */
    uintptr_t modBase = (uintptr_t)g_wowBase;
    size_t modSize = g_wowModuleSize;
    if (modBase && modSize && page >= modBase && page < modBase + modSize) {
        return 1;
    }

    OmThreadState* ts = om_get_thread_state();
    OmPageCacheEntry* page_cache = ts->page_cache;
    DWORD* flush_tick = &ts->page_cache_flush_tick;

    DWORD now = GetTickCount();
    if ((now - *flush_tick) >= 1000 || now < *flush_tick) {
        memset(page_cache, 0, sizeof(ts->page_cache));
        *flush_tick = now;
    }

    uint32_t slot = (uint32_t)((page >> 12) & OM_PAGE_CACHE_MASK);
    OmPageCacheEntry* e = &page_cache[slot];
    if (e->page == page) {
        return e->readable ? 1 : 0;
    }

    MEMORY_BASIC_INFORMATION mbi;
    SIZE_T got = VirtualQuery((const void*)page, &mbi, sizeof(mbi));
    int readable = 0;
    if (got == sizeof(mbi) && mbi.State == MEM_COMMIT) {
        readable = om_protect_readable(mbi.Protect);
    }

    e->page = page;
    e->readable = (uint8_t)(readable ? 1 : 0);
    return readable;
}

static void om_reset_lohi_index(OmLohiIndex* idx) {
    if (!idx) return;
    idx->ipc = NULL;
    idx->tick = 0;
    idx->count = 0;
    memset(idx->slots, 0, sizeof(idx->slots));
}

static void om_reset_guid_index(OmGuidIndex* idx) {
    if (!idx) return;
    idx->ipc = NULL;
    idx->tick = 0;
    idx->count = 0;
    memset(idx->slots, 0, sizeof(idx->slots));
}

static void om_rebuild_indexes(OmThreadState* ts, DinkrIPC* ipc) {
    OmLohiIndex* lohi = &ts->lohi_index;
    OmGuidIndex* guid = &ts->guid_index;
    om_reset_lohi_index(lohi);
    om_reset_guid_index(guid);
    if (!ipc) return;

    uint32_t count = om_clamped_count(ipc);

    lohi->ipc = ipc;
    lohi->tick = ipc->om_update_tick;
    lohi->count = count;
    guid->ipc = ipc;
    guid->tick = ipc->om_update_tick;
    guid->count = count;

    for (uint32_t i = 0; i < count; i++) {
        OmCacheEntry* e = &ipc->objects[i];
        if (e->guid_lo || e->guid_hi) {
            uint32_t slot = om_hash_guid_pair(e->guid_lo, e->guid_hi) & OM_LOHI_INDEX_MASK;
            for (uint32_t probe = 0; probe < OM_LOHI_INDEX_CAPACITY; probe++) {
                uint32_t cur = lohi->slots[slot];
                if (cur == 0) {
                    lohi->slots[slot] = i + 1;
                    break;
                }

                const OmCacheEntry* existing = &ipc->objects[cur - 1];
                if (existing->guid_lo == e->guid_lo && existing->guid_hi == e->guid_hi) {
                    lohi->slots[slot] = i + 1;
                    break;
                }
                slot = (slot + 1u) & OM_LOHI_INDEX_MASK;
            }
        }

        if (e->guid_str[0] == '\0') {
            om_ensure_guid_formatted(e);
        }
        if (e->guid_str[0] == '\0') continue;

        uint32_t slot = om_hash_guid_str(e->guid_str) & OM_GUID_INDEX_MASK;
        for (uint32_t probe = 0; probe < OM_GUID_INDEX_CAPACITY; probe++) {
            uint32_t cur = guid->slots[slot];
            if (cur == 0) {
                guid->slots[slot] = i + 1;
                break;
            }

            OmCacheEntry* existing = &ipc->objects[cur - 1];
            if (existing->guid_str[0] && strcmp(existing->guid_str, e->guid_str) == 0) {
                guid->slots[slot] = i + 1;
                break;
            }
            slot = (slot + 1u) & OM_GUID_INDEX_MASK;
        }
    }
    om_reset_lookup_cache(ts);
}

static void om_ensure_indexes(DinkrIPC* ipc) {
    OmThreadState* ts = om_get_thread_state();
    if (!ipc) {
        om_rebuild_indexes(ts, NULL);
        return;
    }
    uint32_t tick = ipc->om_update_tick;
    if (ts->lohi_index.ipc != ipc || ts->guid_index.ipc != ipc ||
        ts->lohi_index.tick != tick || ts->guid_index.tick != tick) {
        om_rebuild_indexes(ts, ipc);
    }
}

void om_ensure_guid_formatted(OmCacheEntry* e) {
    if (!e) return;
    if (e->guid_str[0] != '\0') return;
    if (e->guid_lo == 0 && e->guid_hi == 0) return;
    int written = WowGuid_Format(e->guid_hi, e->guid_lo, e->guid_str, sizeof(e->guid_str));
    if (written <= 0 || written >= (int)sizeof(e->guid_str)) {
        snprintf(e->guid_str, sizeof(e->guid_str), "Unknown-0x%016llX%016llX",
                 (unsigned long long)e->guid_hi, (unsigned long long)e->guid_lo);
    }
}

void om_ensure_target_guid_formatted(OmCacheEntry* e) {
    if (!e) return;
    if (e->target_guid_str[0] != '\0') return;
    if (e->target_guid_lo == 0 && e->target_guid_hi == 0) return;
    int written = WowGuid_Format(e->target_guid_hi, e->target_guid_lo, e->target_guid_str, sizeof(e->target_guid_str));
    if (written <= 0 || written >= (int)sizeof(e->target_guid_str)) {
        snprintf(e->target_guid_str, sizeof(e->target_guid_str), "Unknown-0x%016llX%016llX",
                 (unsigned long long)e->target_guid_hi, (unsigned long long)e->target_guid_lo);
    }
}

/* ========================================================================
** Safe in-process memory read helpers
** ======================================================================== */

int om_ptr_ok(uintptr_t addr, size_t sz) {
    if (addr < 0x10000 || sz == 0) return 0;
    uintptr_t end = addr + sz - 1;
    if (end < addr || end >= (uintptr_t)OM_CANONICAL_USER_MAX) return 0;

    uintptr_t page = addr & ~(uintptr_t)0xFFF;
    uintptr_t end_page = end & ~(uintptr_t)0xFFF;
    while (1) {
        if (!om_is_readable_page(page)) return 0;
        if (page == end_page) break;
        page += 0x1000;
    }
    return 1;
}

uintptr_t om_read_ptr(uintptr_t addr) {
    if (!om_ptr_ok(addr, sizeof(uintptr_t))) return 0;
    return *(uintptr_t*)addr;
}

uint64_t om_read_u64(uintptr_t addr) {
    if (!om_ptr_ok(addr, sizeof(uint64_t))) return 0;
    return *(uint64_t*)addr;
}

uint32_t om_read_u32(uintptr_t addr) {
    if (!om_ptr_ok(addr, sizeof(uint32_t))) return 0;
    return *(uint32_t*)addr;
}

uint16_t om_read_u16(uintptr_t addr) {
    if (!om_ptr_ok(addr, sizeof(uint16_t))) return 0;
    return *(uint16_t*)addr;
}

uint8_t om_read_u8(uintptr_t addr) {
    if (!om_ptr_ok(addr, sizeof(uint8_t))) return 0;
    return *(uint8_t*)addr;
}

float om_read_f32(uintptr_t addr) {
    if (!om_ptr_ok(addr, sizeof(float))) return 0.0f;
    return *(float*)addr;
}

/* ========================================================================
** IPC-backed OM lookups
** ======================================================================== */

const OmCacheEntry* om_find_by_guid_str(DinkrIPC* ipc, const char* guid_str) {
    if (!ipc || !guid_str || !guid_str[0]) return NULL;

    OmThreadState* ts = om_get_thread_state();
    uint32_t tick = ipc->om_update_tick;
    uint32_t hash = om_hash_guid_str(guid_str);
    size_t key_len = strlen(guid_str);

    /* Seqlock: if OM worker is mid-enumeration, skip index rebuild
     * but still allow lookups (entries are never zeroed, always valid) */
    int writing = (ipc->om_enum_seq & 1) != 0;

    OmGuidLookupCache* cached = &ts->last_guid_lookup;
    if (cached->ipc == ipc &&
        (writing || cached->tick == tick) &&
        cached->hash == hash &&
        key_len == (size_t)cached->key_len &&
        key_len < sizeof(cached->key) &&
        memcmp(cached->key, guid_str, key_len) == 0) {
        if (cached->slot == 0) return NULL;
        uint32_t count = om_clamped_count(ipc);
        uint32_t entry_idx = cached->slot - 1;
        if (entry_idx < count) {
            OmCacheEntry* e = &ipc->objects[entry_idx];
            if (e->guid_str[0] && strcmp(e->guid_str, guid_str) == 0) {
                return e;
            }
        }
    }

    /* During active write, skip index rebuild but still search with stale index */
    if (!writing) {
        om_ensure_indexes(ipc);
    }
    OmGuidIndex* idx = &ts->guid_index;
    if (idx->ipc == ipc) {
        uint32_t slot = hash & OM_GUID_INDEX_MASK;
        for (uint32_t probe = 0; probe < OM_GUID_INDEX_CAPACITY; probe++) {
            uint32_t v = idx->slots[slot];
            if (v == 0) break;

            uint32_t entry_idx = v - 1;
            if (entry_idx < idx->count) {
                OmCacheEntry* e = &ipc->objects[entry_idx];
                if (e->guid_str[0] && strcmp(e->guid_str, guid_str) == 0) {
                    if (!writing)
                        om_cache_guid_lookup(ts, ipc, tick, guid_str, key_len, hash, entry_idx + 1);
                    return e;
                }
            }
            slot = (slot + 1u) & OM_GUID_INDEX_MASK;
        }
    }

    uint32_t count = om_clamped_count(ipc);
    for (uint32_t i = 0; i < count; i++) {
        OmCacheEntry* e = &ipc->objects[i];
        om_ensure_guid_formatted(e);
        if (e->guid_str[0] && strcmp(e->guid_str, guid_str) == 0) {
            if (!writing)
                om_cache_guid_lookup(ts, ipc, tick, guid_str, key_len, hash, i + 1);
            return e;
        }
    }
    if (!writing)
        om_cache_guid_lookup(ts, ipc, tick, guid_str, key_len, hash, 0);
    return NULL;
}

const OmCacheEntry* om_find_by_guid_lohi(DinkrIPC* ipc, uint64_t lo, uint64_t hi) {
    if (!ipc || (lo == 0 && hi == 0)) return NULL;

    OmThreadState* ts = om_get_thread_state();
    uint32_t tick = ipc->om_update_tick;

    /* Seqlock: skip index rebuild during write, but still allow lookups */
    int writing = (ipc->om_enum_seq & 1) != 0;

    OmLohiLookupCache* cached = &ts->last_lohi_lookup;
    if (cached->ipc == ipc &&
        (writing || cached->tick == tick) &&
        cached->lo == lo && cached->hi == hi) {
        if (cached->slot == 0) return NULL;
        uint32_t count = om_clamped_count(ipc);
        uint32_t entry_idx = cached->slot - 1;
        if (entry_idx < count) {
            const OmCacheEntry* e = &ipc->objects[entry_idx];
            if (e->guid_lo == lo && e->guid_hi == hi) {
                return e;
            }
        }
    }

    if (!writing) {
        om_ensure_indexes(ipc);
    }
    OmLohiIndex* idx = &ts->lohi_index;
    if (idx->ipc == ipc) {
        uint32_t slot = om_hash_guid_pair(lo, hi) & OM_LOHI_INDEX_MASK;
        for (uint32_t probe = 0; probe < OM_LOHI_INDEX_CAPACITY; probe++) {
            uint32_t v = idx->slots[slot];
            if (v == 0) break;

            uint32_t entry_idx = v - 1;
            if (entry_idx < idx->count) {
                const OmCacheEntry* e = &ipc->objects[entry_idx];
                if (e->guid_lo == lo && e->guid_hi == hi) {
                    if (!writing)
                        om_cache_lohi_lookup(ts, ipc, tick, lo, hi, entry_idx + 1);
                    return e;
                }
            }
            slot = (slot + 1u) & OM_LOHI_INDEX_MASK;
        }
    }

    uint32_t count = om_clamped_count(ipc);
    for (uint32_t i = 0; i < count; i++) {
        const OmCacheEntry* e = &ipc->objects[i];
        if (e->guid_lo == lo && e->guid_hi == hi) {
            if (!writing)
                om_cache_lohi_lookup(ts, ipc, tick, lo, hi, i + 1);
            return e;
        }
    }
    if (!writing)
        om_cache_lohi_lookup(ts, ipc, tick, lo, hi, 0);
    return NULL;
}

BOOL om_guid_matches(DinkrIPC* ipc, const char* guid_str, uint64_t cmp_lo, uint64_t cmp_hi) {
    if (!ipc || !guid_str) return FALSE;
    const OmCacheEntry* e = om_find_by_guid_str(ipc, guid_str);
    if (!e) return FALSE;
    return (e->guid_lo == cmp_lo && e->guid_hi == cmp_hi);
}
