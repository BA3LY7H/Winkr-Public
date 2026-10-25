/*
 * wow_guid_format.h — WoW-style GUID formatting (header-only)
 *
 * Provides human-readable GUID strings matching WoW's internal format.
 * All functions are static inline for C/C++ compatibility.
 *
 * Usage:
 *   char buf[80];
 *   WowGuid_Format(hi, lo, buf, sizeof(buf));
 *
 *   char short_buf[40];
 *   WowGuid_ShortForm(hi, lo, short_buf, sizeof(short_buf));
 */

#ifndef WOW_GUID_FORMAT_H
#define WOW_GUID_FORMAT_H

#include <stdint.h>
#include <stdio.h>
#include <string.h>

/* ======================================================================
 * GUID type names (58 entries, indices 0-57)
 * ====================================================================== */

static const char* g_GuidTypeNames[58] = {
    "",                  /* 0  Null            */
    "Uniq",              /* 1  Uniq            */
    "Player",            /* 2  Player          */
    "Item",              /* 3  Item            */
    "WorldTransaction",  /* 4  WorldTransaction*/
    "StaticDoor",        /* 5  StaticDoor      */
    "Transport",         /* 6  Transport       */
    "Conversation",      /* 7  Conversation    */
    "Creature",          /* 8  Creature        */
    "Vehicle",           /* 9  Vehicle         */
    "Pet",               /* 10 Pet             */
    "GameObject",        /* 11 GameObject      */
    "DynamicObject",     /* 12 DynamicObject   */
    "AreaTrigger",       /* 13 AreaTrigger     */
    "Corpse",            /* 14 Corpse          */
    "LootObject",        /* 15 LootObject      */
    "SceneObject",       /* 16 SceneObject     */
    "Scenario",          /* 17 Scenario        */
    "AIGroup",           /* 18 AIGroup         */
    "DynamicDoor",       /* 19 DynamicDoor     */
    "ClientActor",       /* 20 ClientActor     */
    "Vignette",          /* 21 Vignette        */
    "CallForHelp",       /* 22 CallForHelp     */
    "AIResource",        /* 23 AIResource      */
    "AILock",            /* 24 AILock          */
    "AILockTicket",      /* 25 AILockTicket    */
    "ChatChannel",       /* 26 ChatChannel     */
    "Party",             /* 27 Party           */
    "Guild",             /* 28 Guild           */
    "WowAccount",        /* 29 WowAccount      */
    "BNetAccount",       /* 30 BNetAccount     */
    "GMTask",            /* 31 GMTask          */
    "MobileSession",     /* 32 MobileSession   */
    "RaidGroup",         /* 33 RaidGroup       */
    "Spell",             /* 34 Spell           */
    "Mail",              /* 35 Mail            */
    "WebObj",            /* 36 WebObj          */
    "LFGObject",         /* 37 LFGObject       */
    "LFGList",           /* 38 LFGList         */
    "UserRouter",        /* 39 UserRouter      */
    "PVPQueueGroup",     /* 40 PVPQueueGroup   */
    "UserClient",        /* 41 UserClient      */
    "PetBattle",         /* 42 PetBattle       */
    "UniqUserClient",    /* 43 UniqUserClient  */
    "BattlePet",         /* 44 BattlePet       */
    "CommerceObj",       /* 45 CommerceObj     */
    "ClientSession",     /* 46 ClientSession   */
    "Cast",              /* 47 Cast            */
    "ClientConnection",  /* 48 ClientConnection*/
    "ClubFinder",        /* 49 ClubFinder      */
    "ToolsClient",       /* 50 ToolsClient     */
    "WorldLayer",        /* 51 WorldLayer      */
    "ArenaTeam",         /* 52 ArenaTeam       */
    "LMMParty",          /* 53 LMMParty        */
    "LMMLobby",          /* 54 LMMLobby        */
    "Housing",           /* 55 Housing         */
    "MeshObject",        /* 56 MeshObject      */
    "Entity"             /* 57 Entity          */
};

/* ======================================================================
 * Format pattern enum + dispatch table
 * ====================================================================== */

enum WowGuidFmt {
    FMT_OTHER    = 0,
    FMT_PLAYER   = 1,
    FMT_ITEM     = 2,
    FMT_STANDARD = 3,
    FMT_TRANSPORT= 4,
    FMT_GUILD    = 5,
    FMT_BNET     = 6,
    FMT_PARTY    = 7
};

static const int g_TypeToFormat[58] = {
    /* 0  Null           */ FMT_OTHER,
    /* 1  Uniq           */ FMT_OTHER,
    /* 2  Player         */ FMT_PLAYER,
    /* 3  Item           */ FMT_ITEM,
    /* 4  WorldTx        */ FMT_STANDARD,
    /* 5  StaticDoor     */ FMT_TRANSPORT,
    /* 6  Transport      */ FMT_TRANSPORT,
    /* 7  Conversation   */ FMT_STANDARD,
    /* 8  Creature       */ FMT_STANDARD,
    /* 9  Vehicle        */ FMT_STANDARD,
    /* 10 Pet            */ FMT_STANDARD,
    /* 11 GameObject     */ FMT_STANDARD,
    /* 12 DynamicObject  */ FMT_STANDARD,
    /* 13 AreaTrigger    */ FMT_STANDARD,
    /* 14 Corpse         */ FMT_STANDARD,
    /* 15 LootObject     */ FMT_STANDARD,
    /* 16 SceneObject    */ FMT_STANDARD,
    /* 17 Scenario       */ FMT_STANDARD,
    /* 18 AIGroup        */ FMT_STANDARD,
    /* 19 DynamicDoor    */ FMT_STANDARD,
    /* 20 ClientActor    */ FMT_OTHER,
    /* 21 Vignette       */ FMT_STANDARD,
    /* 22 CallForHelp    */ FMT_STANDARD,
    /* 23 AIResource     */ FMT_STANDARD,
    /* 24 AILock         */ FMT_STANDARD,
    /* 25 AILockTicket   */ FMT_STANDARD,
    /* 26 ChatChannel    */ FMT_OTHER,
    /* 27 Party          */ FMT_PARTY,
    /* 28 Guild          */ FMT_GUILD,
    /* 29 WowAccount     */ FMT_BNET,
    /* 30 BNetAccount    */ FMT_BNET,
    /* 31 GMTask         */ FMT_BNET,
    /* 32 MobileSession  */ FMT_OTHER,
    /* 33 RaidGroup      */ FMT_BNET,
    /* 34 Spell          */ FMT_BNET,
    /* 35 Mail           */ FMT_BNET,
    /* 36 WebObj         */ FMT_OTHER,
    /* 37 LFGObject      */ FMT_OTHER,
    /* 38 LFGList        */ FMT_OTHER,
    /* 39 UserRouter     */ FMT_BNET,
    /* 40 PVPQueueGroup  */ FMT_BNET,
    /* 41 UserClient     */ FMT_BNET,
    /* 42 PetBattle      */ FMT_PARTY,
    /* 43 UniqUserClient */ FMT_PARTY,
    /* 44 BattlePet      */ FMT_BNET,
    /* 45 CommerceObj    */ FMT_BNET,
    /* 46 ClientSession  */ FMT_PARTY,
    /* 47 Cast           */ FMT_STANDARD,
    /* 48 ClientConn     */ FMT_OTHER,
    /* 49 ClubFinder     */ FMT_OTHER,
    /* 50 ToolsClient    */ FMT_OTHER,
    /* 51 WorldLayer     */ FMT_GUILD,
    /* 52 ArenaTeam      */ FMT_OTHER,
    /* 53 LMMParty       */ FMT_OTHER,
    /* 54 LMMLobby       */ FMT_OTHER,
    /* 55 Housing        */ FMT_STANDARD,
    /* 56 MeshObject     */ FMT_STANDARD,
    /* 57 Entity         */ FMT_STANDARD
};

/* ======================================================================
 * Helper: variable-length hex (min 8 chars)
 * ====================================================================== */

static inline int wg_hex_var(uint64_t val, char* buf, int bufSize)
{
    if (val <= 0xFFFFFFFFULL)
        return snprintf(buf, bufSize, "%08llX", (unsigned long long)val);
    else
        return snprintf(buf, bufSize, "%016llX", (unsigned long long)val);
}

/* ======================================================================
 * WowGuid_TypeName — return type name for a hi qword
 * ====================================================================== */

static inline const char* WowGuid_TypeName(uint64_t hi)
{
    unsigned type = (unsigned)((hi >> 58) & 0x3F);
    if (type >= 58) return "Unknown";
    return g_GuidTypeNames[type];
}

/* ======================================================================
 * WowGuid_Entry — entry (creature/gameobject template) id from the GUID
 *
 * The descriptor field CGOBJ_NPC_ID reads 0 for BOTH units and game objects on
 * the Classic build, so dinkr_ObjectID could never be trusted: Marshal McBride
 * (entry 197) reported 0, and each consumer worked around it separately.
 *
 * Every FMT_STANDARD type (Creature, Vehicle, Pet, GameObject, ...) carries its
 * entry id inside the GUID, so decode it here rather than chasing a struct
 * offset that drifts on patch day. Same shift/mask WowGuid_Format uses below.
 *
 * Returns 0 for formats with no entry field (Player, Item, Transport, ...).
 * ====================================================================== */

static inline uint32_t WowGuid_Entry(uint64_t hi, uint64_t lo)
{
    (void)lo;
    unsigned type = (unsigned)((hi >> 58) & 0x3F);
    if (type >= 58) return 0;
    if (g_TypeToFormat[type] != FMT_STANDARD) return 0;
    return (uint32_t)((hi >> 6) & 0x7FFFFF);
}

/* ======================================================================
 * WowGuid_Format — full human-readable GUID string
 *
 * Returns number of characters written (excluding NUL), or 0 on error.
 * ====================================================================== */

static inline int WowGuid_Format(uint64_t hi, uint64_t lo, char* buf, int bufSize)
{
    if (bufSize <= 0) return 0;

    unsigned type = (unsigned)((hi >> 58) & 0x3F);
    if (type >= 58) {
        return snprintf(buf, bufSize, "Unknown-0x%016llX-%016llX",
                        (unsigned long long)hi, (unsigned long long)lo);
    }

    const char* name = g_GuidTypeNames[type];
    int fmt = g_TypeToFormat[type];

    switch (fmt) {

    /* ----- FMT_STANDARD ----- */
    case FMT_STANDARD: {
        uint32_t subType  = (uint32_t)(hi & 0x3F);
        uint16_t realmID  = (uint16_t)(hi >> 42);
        uint32_t mapID    = (uint32_t)((hi >> 29) & 0x1FFF);
        uint32_t serverID = (uint32_t)(lo >> 40);
        uint32_t entry    = (uint32_t)((hi >> 6) & 0x7FFFFF);
        uint64_t spawnID  = lo & 0xFFFFFFFFFFULL;
        return snprintf(buf, bufSize,
            "%s-%u-%u-%u-%u-%u-%010llX",
            name, subType, realmID, mapID, serverID, entry,
            (unsigned long long)spawnID);
    }

    /* ----- FMT_PLAYER ----- */
    case FMT_PLAYER: {
        uint16_t realmID = (uint16_t)(hi >> 42);
        uint32_t subType = (uint32_t)((hi >> 40) & 3);
        if (subType == 0) {
            char hexBuf[20];
            wg_hex_var(lo, hexBuf, sizeof(hexBuf));
            return snprintf(buf, bufSize, "Player-%u-%s", realmID, hexBuf);
        } else if (subType == 2) {
            uint32_t creatorRealmID = (uint32_t)((hi >> 16) & 0xFFFFFF);
            return snprintf(buf, bufSize, "Player-%u-%u-%u-%016llX",
                            realmID, subType, creatorRealmID,
                            (unsigned long long)lo);
        } else {
            /* subType 1 or 3 */
            return snprintf(buf, bufSize, "Player-%u-%u-%016llX",
                            realmID, subType, (unsigned long long)lo);
        }
    }

    /* ----- FMT_ITEM ----- */
    case FMT_ITEM: {
        uint16_t realmID = (uint16_t)(hi >> 42);
        uint32_t counter = (uint32_t)((hi >> 18) & 0xFFFFFF);
        return snprintf(buf, bufSize, "Item-%u-%u-%016llX",
                        realmID, counter, (unsigned long long)lo);
    }

    /* ----- FMT_TRANSPORT ----- */
    case FMT_TRANSPORT: {
        uint32_t entry = (uint32_t)((hi >> 38) & 0xFFFFF);
        return snprintf(buf, bufSize, "%s-%u-%016llX",
                        name, entry, (unsigned long long)lo);
    }

    /* ----- FMT_GUILD ----- */
    case FMT_GUILD: {
        uint16_t realmID = (uint16_t)(hi >> 42);
        char hexBuf[20];
        wg_hex_var(lo, hexBuf, sizeof(hexBuf));
        return snprintf(buf, bufSize, "%s-%u-%s", name, realmID, hexBuf);
    }

    /* ----- FMT_BNET ----- */
    case FMT_BNET: {
        uint64_t hiField = hi & 0x3FFFFFFFFFFFFFFULL;
        return snprintf(buf, bufSize, "%s-%llu-%016llX",
                        name, (unsigned long long)hiField,
                        (unsigned long long)lo);
    }

    /* ----- FMT_PARTY ----- */
    case FMT_PARTY: {
        uint16_t realmID = (uint16_t)(hi >> 42);
        uint32_t field2  = (uint32_t)(hi >> 10);
        char hexBuf[20];
        wg_hex_var(lo, hexBuf, sizeof(hexBuf));
        return snprintf(buf, bufSize, "%s-%u-%u-%s",
                        name, realmID, field2, hexBuf);
    }

    /* ----- FMT_OTHER ----- */
    case FMT_OTHER:
    default: {
        /* Null GUID */
        if (type == 0 && hi == 0 && lo == 0) {
            return snprintf(buf, bufSize, "0000000000000000");
        }
        /* Fallback: TypeName-hiHex-loHex */
        if (name[0] == '\0')
            return snprintf(buf, bufSize, "0x%016llX-%016llX",
                            (unsigned long long)hi, (unsigned long long)lo);
        return snprintf(buf, bufSize, "%s-0x%016llX-%016llX",
                        name, (unsigned long long)hi, (unsigned long long)lo);
    }

    } /* switch */
}

/* ======================================================================
 * WowGuid_ShortForm — compact display for table column (~22 chars max)
 *
 * Format: TypeAbbrev..LoHex8
 * ====================================================================== */

static inline int WowGuid_ShortForm(uint64_t hi, uint64_t lo, char* buf, int bufSize)
{
    if (bufSize <= 0) return 0;

    unsigned type = (unsigned)((hi >> 58) & 0x3F);
    if (type >= 58) {
        return snprintf(buf, bufSize, "??..%08X", (uint32_t)(lo & 0xFFFFFFFF));
    }

    /* Abbreviated type names for long ones */
    const char* abbr;
    switch (type) {
    case 0:  abbr = "Null";    break;
    case 2:  abbr = "Player";  break;
    case 3:  abbr = "Item";    break;
    case 8:  abbr = "Creature";break;
    case 9:  abbr = "Vehicle"; break;
    case 10: abbr = "Pet";     break;
    case 11: abbr = "GO";      break;  /* GameObject */
    case 12: abbr = "DynObj";  break;  /* DynamicObject */
    case 13: abbr = "AT";      break;  /* AreaTrigger */
    case 14: abbr = "Corpse";  break;
    case 15: abbr = "Loot";    break;  /* LootObject */
    case 16: abbr = "Scene";   break;  /* SceneObject */
    case 7:  abbr = "Conv";    break;  /* Conversation */
    case 47: abbr = "Cast";    break;
    default: {
        /* Use full name if short, else truncate to 6 chars */
        abbr = g_GuidTypeNames[type];
        break;
    }
    }

    /* For STANDARD types, show spawnID (low 40 bits); for others, low 32 bits */
    int fmt = (type < 58) ? g_TypeToFormat[type] : FMT_OTHER;
    if (fmt == FMT_STANDARD) {
        uint64_t spawnID = lo & 0xFFFFFFFFFFULL;
        /* Show low 32 bits of spawnID for compactness */
        return snprintf(buf, bufSize, "%s..%08X", abbr,
                        (uint32_t)(spawnID & 0xFFFFFFFF));
    } else {
        return snprintf(buf, bufSize, "%s..%08X", abbr,
                        (uint32_t)(lo & 0xFFFFFFFF));
    }
}

#endif /* WOW_GUID_FORMAT_H */
