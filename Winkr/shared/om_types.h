/*
 * om_types.h — Object Manager types and CGObject field offsets
 *
 * Build: 67186
 */

#pragma once
#ifndef DINKR_OM_TYPES_H
#define DINKR_OM_TYPES_H

#include <stdint.h>

/* ------------------------------------------------------------------ */
/*  CGObject field offsets (build 66838)                               */
/* ------------------------------------------------------------------ */

#define CGOBJ_GUID_LO       0x10
#define CGOBJ_GUID_HI       0x18
#define CGOBJ_TYPE_BYTE      0x24
/* 69109: DERIVED from a live alive-vs-dead dump of the same creature
 * (dinkr_DumpObject). Reads 0 alive -> 4 dead+lootable. The old 0x94 is a 68887
 * value and reads 0 for every unit on this build, which silently broke every
 * lootable/dead check that used it. Cross-check: cgobj+0x2B0 is a liveness
 * boolean, 1 alive -> 0 dead. */
#define CGOBJ_DYNAMIC_FLAGS  0x57C    /* uint32: bit 0x4 = lootable/tapped */
#define CGOBJ_ALIVE_BOOL     0x2B0    /* uint32: 1 = alive, 0 = dead */
/* 69547: VERIFIED from a live dump (dinkr_DumpObject). An Ironforge Guard read
 * cgobj+0xD0 = 0x15DB = 5595, which is that creature's entry id, and the player
 * object has NO 0xD0 field at all -- exactly right, players have no creature
 * entry. The old 0x90 is a retail leftover and reads zero here. */
#define CGOBJ_NPC_ID         0xD0
#define CGOBJ_NPC_ID_STALE   0x90     /* retail 67186; reads 0 on Classic 69547 */
#define CGOBJ_ITEM_ENTRY_ID  0x108    /* uint32: item template entry ID (CGItem_C::m_itemData+0x68) */
#define CGOBJ_HEIGHT         0xC8     /* float: model display height (partial — use Movement_C collision height for true unit height) */
#define CGOBJ_NAME_PTR       0x1E8
/* 69547: POSITION IS AT 0x138, NOT 0x380. Verified on two live objects -- the
 * player and an Ironforge Guard standing near each other both read a plausible
 * world vector at 0x138/0x13C/0x140 with matching Z (501.48), while 0x380 holds
 * 0x40490FDB = pi and 0x37C..0x384 are a run of constants (7.0, 4.5, pi, pi,
 * 1.0). Those are not coordinates.
 *
 * NOTHING CURRENTLY READS THE 0x380 VALUES, which is why movement works: the
 * enumerator takes position from the Movement sub-object via POS_OFF_*, not
 * from cgobj directly (dinkr_om_enum.c:285). Corrected anyway, because a
 * constant that is wrong and merely unused is a trap for the next caller. */
#define CGOBJ_POS_X          0x138
#define CGOBJ_POS_Y          0x13C
#define CGOBJ_POS_Z          0x140
#define CGOBJ_POS_X_STALE    0x380    /* retail; holds pi on Classic 69547 */
#define CGOBJ_FACING         0x38C    /* retail-era; see dinkr_om.h:45 -- do NOT write this */
#define CGOBJ_CAST_TARGET_LO 0x3B0    /* cast/channel target GUID low qword */
#define CGOBJ_CAST_TARGET_HI 0x3B8    /* cast/channel target GUID high qword */
#define CGOBJ_VEHICLE_DATA   0x1900
#define CGOBJ_POWER_VALUES   0x1968
/* NOT IN THIS STRUCTURE ANY MORE on 69547 -- left at the 68887 value.
 *
 * CONCLUSIVE, from dinkr_PatchDay() with a target confirmed via UnitGUID():
 *   - pcg is a REAL player object: it holds its own GUID at +0x10 (sanity check)
 *   - the target IS in the OM cache (e.g. 0000A90000159EDC matched the rat)
 *   - that GUID appears NOWHERE in cgobj+0x8..0x8A80 (the whole object)
 *   - all five GUID globals are dead: RVA_TargetGUID reads 0x1, FocusGUID /
 *     NpcTargetGUID / ActivePlayerGUID read 0, MouseoverGUID holds a pointer
 *   - a 7 MB sweep of module data around those globals found nothing
 *
 * So the selection state moved off this object and out of static data. The
 * object manager still enumerates every object correctly -- enumeration and
 * selection are different questions, and only the latter broke.
 *
 * DO NOT chase this to resolve the PLAYER'S OWN target: UnitGUID("target") is
 * a supported API, correct on every build, and om_guid_matches() already
 * consumes GUID strings. Recomputing from a struct field that moves every
 * patch is the wrong trade.
 *
 * It is still worth deriving for dinkr_om.c:328, which reads EVERY unit's
 * target ("who is this mob attacking") -- Lua cannot answer that for arbitrary
 * mobs. Lower priority than target resolution. */
#define CGOBJ_TARGET_LO      0x1B48   /* 68887; UNVERIFIED on 69547 -- see above */
#define CGOBJ_TARGET_HI      0x1B50
/* CLASSIC ERA HAS NO FOCUS. Focus targeting arrived in TBC 2.0, so this field
 * does not exist here and dinkr_PatchDay() will always report it STALE. That
 * line is a retail-era leftover in the scanner, not a real failure -- the same
 * reason its own instructions say to "/focus a DIFFERENT mob", which this
 * client cannot do. */
#define CGOBJ_FOCUS_LO       0x1BB8   /* 68887: n/a on Classic Era */
#define CGOBJ_FOCUS_HI       0x1BC0
#define CGOBJ_CREATURE_TYPE  0x1BB0
#define CGOBJ_COMBAT_REACH   0x1C04   /* float: combat reach (typically 1.5 for players). 67186: shifted +8 from 67088. */
#define CGOBJ_BOUNDING_RADIUS 0x1CC4  /* float: unit bounding radius. 67186: shifted +8 from 67088. */
#define CGOBJ_UNIT_FLAGS2    0x1BE0
#define CGOBJ_UNIT_FLAGS     0x1BE8

#define CGOBJ_CREATURE_ENTRY_ID   0x1ADC   /* uint32: creature template entry ID (for NPC name lookup) */
#define CGOBJ_CASTING_SPELL_ID    0x3A4    /* uint32: currently casting spell ID (0 = not casting) */
#define CGOBJ_CHANNELING_SPELL_ID 0x3DC    /* uint32: currently channeling spell ID (0 = not channeling) */
#define CGOBJ_GO_NAME_PTR_1       0xF0     /* ptr: first deref in GO name chain */
#define CGOBJ_GO_NAME_PTR_2_OFF   0xE0     /* offset into deref'd struct for second name ptr */

#define CGOBJ_MOVEMENT_C_PTR  0xE0     /* pointer to Movement_C struct */
#define MOVEMENT_C_FLAGS      0x190    /* uint32: movement flags */
#define MOVEMENT_C_COLLISION_HEIGHT 0x2E8  /* float: collision height (always valid) */
#define CGOBJ_SUMMONED_BY_LO  0x1B10   /* SummonedBy GUID low qword */
#define CGOBJ_SUMMONED_BY_HI  0x1B18   /* SummonedBy GUID high qword */
#define CGOBJ_CREATED_BY_LO   0x1B30   /* CreatedBy GUID low qword */
#define CGOBJ_CREATED_BY_HI   0x1B38   /* CreatedBy GUID high qword */

/* AreaTrigger-specific offsets (CGAreaTrigger_C — build 67088)
 * Evidence (IDA VAs, image base 0x7FF63EAD0000):
 *   CGAreaTrigger_C__OnCreate_67088         @ 0x7FF640C51F30 — reads caster as
 *     16-byte OWORD at a1+584 (0x248) and AreaTriggerCreatePropertiesID at
 *     a1+628 (0x274), passing both to CGAreaTrigger_C__ResolveSpellID_67088
 *     (0x7FF641D74080) and tests CLIENT_FLAGS at a1+724 (0x2D4) for 0x200/0x400.
 *   CGAreaTrigger_C__OnSMSGCreate_67088     @ 0x7FF640C559F0 — reads
 *     SpellID at a1+624 (0x270) and passes to spell-visual constructor
 *     sub_7FF640AA8500 (a3 → SpellVisual+144).
 *   sub_7FF640C53010 (spline interp helper) — uses a1[151] = 0x25C as the
 *     duration period in sub_7FF640AD4800(now,start,period). a1[181] = 0x2D4
 *     is read & masked with bit 4 (CLIENT_FLAGS).
 *   CGAreaTrigger_C__Update_67088           @ 0x7FF640C53C80 — switches on
 *     SHAPE byte at a1+1704 (0x6A8) for cases 0/1/4/7 and interpolates
 *     dimensions at a1+1712/1716 (0x6B0/0x6B4) plus +0x18 stride pairs.
 *   CGAreaTrigger_C__GetBoundingBox_67088   @ 0x7FF640C518C0 — same SHAPE
 *     switch, uses a1+1712/1716 (DIM[0]) and a1+752 (0x2F0) as a curve key.
 *   CGAreaTrigger_C__GetAreaTriggerRec_67088 @ 0x7FF640C50D80 — looks up
 *     a1+644 (0x284) in off_7FF644498650 (AreaTriggerRec DB2). NEW field.
 *   Whole AT-data block shifted +0x18 from 66838 (matches Aura ptr +0x08
 *   delta plus an extra 16-byte member added by 67088). */
#define CGOBJ_AT_CASTER_LO       0x248   /* uint64: caster GUID low (was 0x230) */
#define CGOBJ_AT_CASTER_HI       0x250   /* uint64: caster GUID high (was 0x238) */
#define CGOBJ_AT_DURATION_MS     0x258   /* uint32: duration in milliseconds (IDA: [r15+258h] in deserializer) */
#define CGOBJ_AT_SPELL_ID        0x270   /* uint32: associated spell ID */
#define CGOBJ_AT_CREATE_PROPS_ID 0x27C   /* uint32: AreaTriggerCreateProperties / DecalPropertiesID (IDA: 4 before BoundsRadius2D@0x280) */
#define CGOBJ_AT_AREA_TRIGGER_ID 0x284   /* uint32: AreaTriggerRec DB2 key (NEW in 67088) */
#define CGOBJ_AT_CLIENT_FLAGS    0x2D4   /* uint32: AREA_TRIGGER_CLIENT_FLAGS (was 0x2BC) */
#define CGOBJ_AT_SCALE_CURVE_ID  0x2F0   /* uint32: ScaleCurve DB2 key for radius/dim time-interp (NEW in 67088) */
#define CGOBJ_AT_SHAPE_TYPE      0x6A8   /* uint8: 0=sphere, 1=box, 4=circle, 7=cylinder (was 0x690) */
#define CGOBJ_AT_DIM_START       0x6B0   /* float[4]: dimension start values (was 0x698) */
#define CGOBJ_AT_DIM_END         0x6B4   /* float[4]: dimension end values (interleaved start/end pairs, stride 8) (was 0x69C) */

/* ------------------------------------------------------------------ */
/* Missile / Projectile (build 67088)                                  */
/* ------------------------------------------------------------------ */
/* Evidence (IDA VAs, image base 0x7FF63EAD0000):
 *   g_MissileInFlightListHead_67088 @ 0x7FF642C5B020 — global QWORD that
 *     points to the head of the in-flight CMissile linked list (no manager
 *     struct; the head is just a bare global pointer).
 *   CMissile__Launch_67088          @ 0x7FF640B80820 — proves field offsets
 *     for spell-id (a1+100), spellXSpellVisualId (a1+104), source position
 *     (a1+132/136/140 from launch arg a2), target-entity GUID (a1+16/24),
 *     impact position (a1+180/188), flag bitfield (a1+216/220), spell-visual
 *     handle (a1+608), cast-GUID slot (a1+624), list backptr (a1+632) and
 *     next ptr (a1+640). Inserts node at HEAD of g_MissileInFlightListHead.
 *   CMissile__Destroy_67088         @ 0x7FF640B7FCA0 — uses aux ptr a1+552
 *     to unlink from a secondary registry, then frees the missile.
 *   CMissile__TransformPositions_67088 @ 0x7FF640B81920 — applies a 4x3 world
 *     transform to vec3s at a1+132, a1+144, a1+156 (and the 5-vec basis
 *     hanging off a1+208), proving all three are world-space float[3] vectors.
 *   CMissile__HasPendingOrInFlightMissiles_Lua_67088 @ 0x7FF640D4C6D0 —
 *     iterates g_MissileInFlightListHead via *(QWORD*)(node+640), matches
 *     caster GUID at +0/+8 against unit GUID, filters by spellId at +452,
 *     and excludes nodes whose progress fraction at +464 is >= 1.0.
 *   CMissile__HasPendingMissiles_Lua_67088 @ 0x7FF640D4C5F0 — walks the
 *     unit-pending list at unit+912 (0x390) via +640 next-ptr; reads
 *     spellId at node+452 and launch tick at node+416 (compared with current
 *     world tick − 2000ms, confirming +416 is launch_time_ms).
 *   CMissile__CheckSpellInFlight_67088 @ 0x7FF640AAECA0 — same offsets,
 *     independent confirmation of +0/+8 (caster GUID), +452 (spellId),
 *     +464 (fraction), +640 (next), +416 (launch_time_ms).
 *   CMissile__FindByCasterAndSpell_67088 @ 0x7FF640B7F510 — also confirms
 *     +0/+8 (caster), +64 (an int compared against argument; when AT-spawned
 *     this is the AreaTriggerCreatePropertiesId), +640 (next).
 *   CMissile__RemoveByGUID_67088    @ 0x7FF640BF1B90 — confirms +32/+40 is
 *     a SECOND GUID (likely the resolved target GUID; caster vs target are
 *     swapped by Launch via xchg of OWORDs at +16 and +32).
 *
 * NOTE on velocity / speed: not directly observable from Launch. The trajectory
 *   integrator hangs off a1+456 (sub_7FF640B8BD20 init) and is opaque in this
 *   pass. The raw progress fraction at +464 is what the client uses for
 *   "still in flight" tests. Speed is therefore left UNVERIFIED below.
 * NOTE on positions: TransformPositions treats +132, +144, +156 as parallel
 *   vec3s. Launch initialises ALL THREE to the launch-source pos from a2,
 *   then writes the delta (target-source) into +168/+172/+176. The most
 *   probable interpretation is +132=source, +144=current, +156=target,
 *   +168=direction. This is the "best guess" labelling — see caveat in KB. */

#define MISSILE_MGR_VA              0x7FF6FBACAEE8ULL  /* g_MissileInFlightListHead — bare global QWORD, NOT a struct */
#define MISSILE_MGR_LIST_HEAD_OFF   0x00              /* the global IS the head ptr (no enclosing struct) */
#define MISSILE_MGR_COUNT_OFF       0xFFFFFFFF        /* N/A — count not stored; iterate the list to count */
#define MISSILE_LIST_NEXT_OFF       0x280             /* +640: next-pointer (singly-linked traversal) */
#define MISSILE_LIST_BACKPTR_OFF    0x278             /* +632: back-ptr to predecessor's next-slot (doubly-linked) */
#define MISSILE_STRUCT_SIZE         0x300             /* >= 0x284 verified; 0x300 is a safe over-read bound */

#define MISSILE_OFF_CASTER_LO       0x00              /* uint64: caster GUID lo (matched in HasPending/CheckSpellInFlight) */
#define MISSILE_OFF_CASTER_HI       0x08              /* uint64: caster GUID hi */
#define MISSILE_OFF_TARGET_LO       0x20              /* uint64: target GUID lo (verified in RemoveByGUID + Launch swap) */
#define MISSILE_OFF_TARGET_HI       0x28              /* uint64: target GUID hi */
#define MISSILE_OFF_TARGET_ENT_LO   0x10              /* uint64: target entity GUID used by Launch to fetch target pos */
#define MISSILE_OFF_TARGET_ENT_HI   0x18              /* uint64: ^ hi qword */

#define MISSILE_OFF_CURR_X          0x84              /* float: current interpolated X (animated per-frame by trajectory) */
#define MISSILE_OFF_CURR_Y          0x88              /* float: current interpolated Y */
#define MISSILE_OFF_CURR_Z          0x8C              /* float: current interpolated Z */
#define MISSILE_OFF_SOURCE_X        0x90              /* float: launch source X (static after init, = launch origin) */
#define MISSILE_OFF_SOURCE_Y        0x94              /* float: launch source Y */
#define MISSILE_OFF_SOURCE_Z        0x98              /* float: launch source Z */
#define MISSILE_OFF_REF_X           0x9C              /* float: reference pos X (init'd to source, used for dir calc) */
#define MISSILE_OFF_REF_Y           0xA0              /* float: reference pos Y */
#define MISSILE_OFF_REF_Z           0xA4              /* float: reference pos Z */
#define MISSILE_OFF_DIR_X           0xA8              /* float: direction/delta X (= target - source at launch) */
#define MISSILE_OFF_DIR_Y           0xAC              /* float: direction/delta Y */
#define MISSILE_OFF_DIR_Z           0xB0              /* float: direction/delta Z */
#define MISSILE_OFF_TARGET_X        0xB4              /* float: impact/target X (a1+180, set by Launch) */
#define MISSILE_OFF_TARGET_Y        0xB8              /* float: impact/target Y (a1+184) */
#define MISSILE_OFF_TARGET_Z        0xBC              /* float: impact/target Z (a1+188) */

#define MISSILE_OFF_SPELL_ID        0x40              /* 67186: uint32 canonical spell ID. Verified via sub_7FF6F99EF5F0 (global missile iterator) which filters: *(DWORD*)(missile + 64) == spellId. Was 0x1C4 in 67088 — moved here. NOTE: MISSILE_OFF_AT_PROPS_ID also lived at 0x40 historically — those were the same slot all along; 67186 just exposes it as the canonical spell id. */
#define MISSILE_OFF_SPELL_VISUAL_ID 0x64              /* uint32: SpellVisualID — DB2 key into SpellVisual table (NOT a spell ID!) */
#define MISSILE_OFF_SPELL_VIS_MISSILE_ID 0x68         /* uint32: SpellVisualMissileID — DB2 key into SpellVisualMissile table */
#define MISSILE_OFF_SPELL_VISUAL_HANDLE 0x260         /* uint32: resolved spell-visual handle (a1+608) */
#define MISSILE_OFF_AT_PROPS_ID     0x40              /* alias for SPELL_ID — see note above */

#define MISSILE_OFF_LAUNCH_TIME     0x1A0             /* uint32: launch tick in ms (matches WorldFrame+88+160 tick) */
#define MISSILE_OFF_PROGRESS        0x1D0             /* float : 0..1 flight fraction; >=1.0 means arrived */
#define MISSILE_OFF_FLAGS           0xD8              /* uint32: flag bits 0x40, 0x800, 0x10000, 0x20000, 0x80000000 */
#define MISSILE_OFF_FLAGS2          0xDC              /* uint32: secondary flag word */

#define MISSILE_OFF_CAST_GUID_LO    0x270             /* uint64: cast-GUID slot (16-byte) */
#define MISSILE_OFF_CAST_GUID_HI    0x278             /* NOTE: collides with backptr — CastGUID actually lives at +624/632 *before* list link rewrite. Treat as fluid. */
#define MISSILE_OFF_MISSILE_ID      0xFFFFFFFF        /* UNVERIFIED: no dedicated unique missile-id field observed.
                                                       * Use (caster GUID, spellId, launch_time_ms) as a stable key. */
#define MISSILE_OFF_SPEED           0xFFFFFFFF        /* UNVERIFIED: speed is owned by the trajectory engine at +0x1C8.
                                                       * Compute from |dir| / (now - launch_time) instead. */

/* Per-missile cache entry (mirrors what the orchestrator will ship via IPC).
 * Sibling array to OmCacheEntry — DO NOT embed in OmCacheEntry. */
typedef struct {
    uint64_t caster_lo, caster_hi;
    uint64_t target_lo, target_hi;   /* may be 0 if AoE / ground-targeted */
    float    source_x, source_y, source_z;
    float    target_x, target_y, target_z;
    float    curr_x,   curr_y,   curr_z;
    float    speed;                  /* derived: |dir| / elapsed_seconds */
    uint32_t spell_id;
    uint32_t spell_visual_id;
    uint32_t launch_time_ms;
    uint32_t missile_id;             /* synthetic: hash(caster_lo, spell_id, launch_time_ms) */
} OmMissileEntry;

/* Aura data (CGUnit aura container) — CLASSIC Era 1.15.9, build 68940
 * NOTE: retail 12.0.x shape preserved but ALL offsets shifted. Container base
 * ptr @ +0x8E0, count @ +0x8E8, stride 0xD8. Confirmed by three independent
 * un-obfuscated readers (spellId lookups, GetTime remaining-calc, GUID
 * normalization) and cross-verified by capstone disasm of this dump:
 *   GetAuraByIndex 0x18BCC05 : imul rdx,idx,0xd8 ; add rdx,[rbx+0x8e0]
 *   GetAuraByIndex 0x18BCBBE : cmp dword[rbx+0x8e8],edi/jbe   (count)
 *   flat accessor  0x18BC120 : mov r9,[rcx+0x8e0]; imul idx,0xd8
 *   tooltip filler 0x1E9DB55 : mov rsi,[rdx+0x8e0]
 * CAVEAT (live-validate): +0x8E0/+0x8E8 sit on the unit's aura ECS component.
 * If dinkr's cgobj (GUID->object) IS that container the direct read works;
 * else resolve component first (GUID->0x130FA60->0x130D800). Validate by
 * dereferencing g_activePlayerUnit (RVA 0x03C87AD0) and checking that
 * [cgobj+0x8E8] equals your live buff+debuff count. */
#define CGOBJ_AURA_ARRAY_PTR 0x8E0     /* qword: ptr to contiguous AuraStruct array */
#define CGOBJ_AURA_COUNT     0x8E8     /* uint32: aura count */

/* Per-AuraStruct layout — CLASSIC 68940 (stride = 0xD8 = 216 bytes)
 * Evidence (capstone-verified against WowClassic_68940_full dump):
 *   copier 0x11D7A70 : movups [+0x98] GUID; mov rax,[+0xA0]; shr 0x3a; cmp 0x2f
 *                      (GUID type-tag on hi qword) => CASTER_GUID @ 0x98 (16B)
 *   copier 0x11D7A70 : [+0xA8]u32 spell; [+0xB0]u16 flags; [+0xB2]u8 stacks;
 *                      [+0xB8]u32 dur; [+0xBC]u32 end; [+0xCC]u32 (=instanceId?)
 *   spell match      : 0x18BC0FC/0x1D4C811 cmp [entry+0xA8]  (SPELL_ID)
 *   duration secs    : 0x1D4C688 mov eax,[rbx+0xB8]; cvtdq2pd; mulsd 0.001
 *   remaining calc   : 0x1D4C674 GetTime; mov ecx,[rbx+0xBC]; sub (END_TIME)
 *   stacks arg       : 0x1E9DBF7 movzx byte[..+0xB2] -> tooltip stack count
 * Flags are the STORED bitmask on the u16 @+0xB0 (NOT the Lua filter arg):
 *   isHelpful 0x743E41: mov ecx,0x300; test cx,ax    => HELPFUL = flags & 0x300
 *   filter   0x1D4C86E: test byte[rdi+0xb0],0x10     => HARMFUL = flags & 0x10 */
#define AURA_STRUCT_SIZE     0xD8
#define AURA_OFF_CASTER_GUID 0x98      /* 16 bytes: lo @ +0x98, hi @ +0xA0 */
#define AURA_OFF_SPELL_ID    0xA8      /* uint32 */
#define AURA_OFF_DURATION    0xB8      /* int32, milliseconds */
#define AURA_OFF_END_TIME    0xBC      /* uint32, milliseconds (game-time) */
#define AURA_OFF_FLAGS       0xB0      /* uint16 stored bitmask (0x300=helpful, 0x10=harmful) */
#define AURA_OFF_STACKS      0xB2      /* uint8 (applications / stack count) */
#define AURA_OFF_INSTANCE_ID 0xCC      /* uint32 — PROVISIONAL, needs live validation (0xC8 alt) */

#define AURA_FLAG_HELPFUL    0x0300    /* stored flags bit(s) @ aura+0xB0 */
#define AURA_FLAG_HARMFUL    0x0010    /* stored flags bit @ aura+0xB0 */

/* Max auras tracked per cached object */
#define MAX_AURAS_PER_OBJECT 40

/* Per-aura cache entry (extracted from raw AuraStruct) */
typedef struct {
    uint32_t spellId;
    uint16_t flags;       /* 0x02=helpful, 0x04=harmful */
    uint8_t  stacks;
    uint8_t  _pad;
    int32_t  durationMs;  /* original duration in ms, 0 = permanent */
    uint32_t endTimeMs;   /* GetTickCount-based end time */
    char     name[48];    /* Spell name (DLL-resolved via C_Spell.GetSpellInfo) */
} OmAuraEntry;

/* ------------------------------------------------------------------ */
/*  Object types (CGTYPE enum)                                        */
/* ------------------------------------------------------------------ */

typedef enum {
    CGTYPE_OBJECT            = 0,   /* 0x00000001 - CGObject_C (0xA0) */
    CGTYPE_ITEM              = 1,   /* 0x00000003 - CGItem_C (0x470) */
    CGTYPE_CONTAINER         = 2,   /* 0x00000007 - CGContainer_C (0xAD8) */
    CGTYPE_AZERITE_EMPOWERED = 3,   /* 0x0000000B - CGAzeriteEmpoweredItem_C (0x488) */
    CGTYPE_AZERITE_ITEM      = 4,   /* 0x00000013 - CGAzeriteItem_C (0x538) */
    CGTYPE_UNIT              = 5,   /* 0x00000021 - CGUnit_C (0x1FC0) */
    CGTYPE_PLAYER            = 6,   /* 0x00000061 - CGPlayer_C (0x6040) */
    CGTYPE_ACTIVE_PLAYER     = 7,   /* 0x000000E1 - CGActivePlayer_C (0x8A88) */
    CGTYPE_GAMEOBJECT        = 8,   /* 0x00000101 - CGGameObject_C (0x2E0) */
    CGTYPE_DYNAMIC_OBJ       = 9,   /* 0x00000201 - CGDynamicObject_C (0x170) */
    CGTYPE_CORPSE            = 10,  /* 0x00000401 - CGCorpse_C (0x1D8) */
    CGTYPE_AREA_TRIGGER      = 11,  /* 0x00000801 - CGAreaTrigger_C (0x720) */
    CGTYPE_SCENE_OBJ         = 12,  /* 0x00001001 - CGSceneObject_C (0x108) */
    CGTYPE_CONVERSATION      = 13,  /* 0x00002001 - CGConversation_C (0x190) */
    CGTYPE_MESH_OBJECT       = 14,  /* 0x00004001 - CGMeshObject_C (0xA8) [TWW housing] */
    CGTYPE_UNK_15            = 15,  /* 0x00008001 - present in dword_7FF6421CA020 */
    CGTYPE_MAX               = 16
} CGObjectType;

/* Check if type is a unit/player (has unit-specific fields) */
static inline int IsUnitType(uint8_t type) {
    return type == CGTYPE_UNIT || type == CGTYPE_PLAYER || type == CGTYPE_ACTIVE_PLAYER;
}

/* Get human-readable type name */
static inline const char* CGTypeName(uint8_t type) {
    switch (type) {
        case CGTYPE_OBJECT:            return "Object";
        case CGTYPE_ITEM:              return "Item";
        case CGTYPE_CONTAINER:         return "Container";
        case CGTYPE_AZERITE_EMPOWERED: return "AzEmpowered";
        case CGTYPE_AZERITE_ITEM:      return "AzeriteItem";
        case CGTYPE_UNIT:              return "Unit";
        case CGTYPE_PLAYER:            return "Player";
        case CGTYPE_ACTIVE_PLAYER:     return "ActivePlayer";
        case CGTYPE_GAMEOBJECT:        return "GameObject";
        case CGTYPE_DYNAMIC_OBJ:       return "DynObject";
        case CGTYPE_CORPSE:            return "Corpse";
        case CGTYPE_AREA_TRIGGER:      return "AreaTrigger";
        case CGTYPE_SCENE_OBJ:         return "SceneObject";
        case CGTYPE_CONVERSATION:      return "Conversation";
        case CGTYPE_MESH_OBJECT:       return "MeshObject";
        case CGTYPE_UNK_15:            return "Unknown15";
        default:                       return "Unknown";
    }
}

/* ------------------------------------------------------------------ */
/*  OM cache                                                          */
/* ------------------------------------------------------------------ */

/* Max objects in OM cache */
#define MAX_OM_OBJECTS 2048

/* Per-object cache entry (shared between DLL and GUI via IPC) */
typedef struct {
    uintptr_t cgobj;           /* CGObject address in target process */
    uint64_t  entity;          /* ECS entity address */
    uint64_t  guid_lo;         /* GUID low qword */
    uint64_t  guid_hi;         /* GUID high qword */
    uint8_t   type;            /* CGObjectType */
    uint8_t   dynamic_flags;   /* from obj+0x94: bit 0x4 = lootable */
    uint8_t   _pad[2];
    uint32_t  npc_id;
    float     pos_x;
    float     pos_y;
    float     pos_z;
    float     facing;

    /* Unit-specific fields (only valid when IsUnitType(type)) */
    uint32_t  unit_flags;
    uint32_t  unit_flags2;
    uint32_t  movement_flags;  /* from Movement_C+0x190 */
    float     combat_reach;    /* typically 1.5 for players */
    float     bounding_radius; /* unit bounding radius */
    float     height;          /* model display height */

    /* Casting info (unit only) */
    uint32_t  casting_spell_id;    /* 0 = not casting */
    uint32_t  channeling_spell_id; /* 0 = not channeling */
    uint64_t  cast_target_lo;      /* cast/channel target GUID */
    uint64_t  cast_target_hi;

    /* Casting spell names (resolved from SpellName DB2) */
    char      casting_spell_name[48];
    char      channeling_spell_name[48];

    /* Relationships */
    uint64_t  target_guid_lo;
    uint64_t  target_guid_hi;
    uint64_t  summoned_by_lo;
    uint64_t  summoned_by_hi;
    uint64_t  created_by_lo;
    uint64_t  created_by_hi;

    /* AreaTrigger-specific fields (only valid when type == CGTYPE_AREA_TRIGGER) */
    uint64_t  at_caster_lo;
    uint64_t  at_caster_hi;
    uint32_t  at_spell_id;         /* 0 if no spell associated */
    uint32_t  at_duration_ms;      /* 0 = permanent/unknown */
    uint32_t  at_create_props_id;  /* AreaTriggerCreateProperties DB2 key */
    uint32_t  at_area_trigger_id;  /* AreaTriggerRec DB2 key (NEW in 67088) */
    uint32_t  at_scale_curve_id;   /* CurveRec DB2 key for radius/dim time-interp (NEW in 67088) */
    uint32_t  at_client_flags;
    uint8_t   at_shape_type;       /* 0=sphere, 1=box, 4=circle, 7=cylinder */
    uint8_t   _pad_at[3];
    float     at_radius;           /* effective radius (shape dim1 start) */
    char      at_caster_str[80];   /* formatted caster GUID string */

    /* Display data */
    char      name[96];        /* object name (multi-path resolved) */
    char      guid_str[80];
    char      target_guid_str[80];

    /* Auras (unit/player only) */
    uint8_t   aura_count;
    uint8_t   _pad3[3];
    OmAuraEntry auras[MAX_AURAS_PER_OBJECT];
} OmCacheEntry;

#endif /* DINKR_OM_TYPES_H */
