/*
** dinkr_om.h — DLL-side Object Manager helpers (IPC-backed)
**
** The DLL no longer enumerates the OM directly — the GUI does that
** via ReadProcessMemory. This header provides thin IPC-backed lookups
** and safe in-process memory read helpers for real-time object data.
*/

#ifndef DINKR_DLL_OM_H
#define DINKR_DLL_OM_H

#include "../shared/om_types.h"
#include "../shared/ipc_protocol.h"
#include <windows.h>

/* Lazy GUID formatting */
void om_ensure_guid_formatted(OmCacheEntry* e);
void om_ensure_target_guid_formatted(OmCacheEntry* e);

/* Safe in-process memory read (for real-time object data) */
int       om_ptr_ok(uintptr_t addr, size_t sz);
uintptr_t om_read_ptr(uintptr_t addr);
uint64_t  om_read_u64(uintptr_t addr);
uint32_t  om_read_u32(uintptr_t addr);
uint16_t  om_read_u16(uintptr_t addr);
uint8_t   om_read_u8(uintptr_t addr);
float     om_read_f32(uintptr_t addr);

/* IPC-backed OM lookups */
const OmCacheEntry* om_find_by_guid_str(DinkrIPC* ipc, const char* guid_str);
const OmCacheEntry* om_find_by_guid_lohi(DinkrIPC* ipc, uint64_t lo, uint64_t hi);
BOOL om_guid_matches(DinkrIPC* ipc, const char* guid_str, uint64_t cmp_lo, uint64_t cmp_hi);

/* Resolve an object's ECS EntityPosition base (live game memory).
 *
 * This is the block the CLIENT actually reads and writes for position and
 * facing on Classic. Facing lives at +0x50 (see ENTPOS_FACING), position at
 * +0x84/0x88/0x8C. Defined in dinkr_bridge_objects.c; exported because the
 * facing SETTER must use exactly the same resolution as the getter, or it
 * writes a field nothing reads. */
int om_resolve_entity_pos_base(DinkrIPC* ipc, const OmCacheEntry* e, uintptr_t* out_pos_base);

/* Facing, as an offset into the EntityPosition block above.
 *
 * NOT CGOBJ_FACING (0x38C). That constant is a retail-era cgobj offset and is
 * dead on this Classic build: dinkr_ObjectFacing reads pos_base+0x50 and agrees
 * with the client, while a write to cgobj+0x38C changes nothing observable. */
#define ENTPOS_FACING 0x50

#endif /* DINKR_DLL_OM_H */
