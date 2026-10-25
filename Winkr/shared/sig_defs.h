/*
 * sig_defs.h - Signature definitions for Dinkr RVA resolver.
 * Build 67186 (12.0.5).
 *
 * rva_defs.h remains the hardcoded RVA source of truth. This table
 * includes every address-like RVA_* entry there, in source order,
 * excluding only count/layout/non-address metadata.
 *
 * FORMAT: X(RVA_SUFFIX, skip_scan, match_offset, pat_bytes, msk_string)
 * Example: X(LUAH_NEW, 1, 0, "\xCC", "x") derives SIGID_LUAH_NEW,
 * log label "RVA_LUAH_NEW", and fallback RVA_LUAH_NEW.
 *
 * skip_scan=1 always uses base + RVA_*; skip_scan=0 scans readable
 * committed pages in the WoW module image and accepts exactly one match.
 * Zero or multiple matches fall back to base + RVA_*.
 */

#pragma once
#ifndef DINKR_SIG_DEFS_H
#define DINKR_SIG_DEFS_H

#include "rva_defs.h"

/* clang-format off */
#define DINKR_SIG_TABLE(X) \
    X(PRECALL_C_CCLOSURE                , 1, 0, "\xCC", "x") \
    X(PRECALL_C_LUAFUNC                 , 1, 0, "\xCC", "x") \
    X(PRECALL_V1_C_CCLOSURE             , 1, 0, "\xCC", "x") \
    X(PRECALL_V1_C_LUAFUNC              , 1, 0, "\xCC", "x") \
    X(PRECALL_LUA_CCLOSURE              , 1, 0, "\xCC", "x") \
    X(PRECALL_LUA_LUAFUNC               , 1, 0, "\xCC", "x") \
    X(LUA_SETSECRET                     , 0, 0, "\x48\x83\xEC\x28\xE8\x00\x00\x00\x00\xC6\x40\x09\x01\x48\x83\xC4\x28\xC3", "xxxxx????xxxxxxxxx") \
    X(RETADDR_CHECK                     , 0, 0, "\x40\x53\x48\x83\xEC\x20\x48\x8B\xD1\x0F\x1F\x80\x00\x00\x00\x00\x81\xFC\x00\x27\x00\x00\x77\x03\x83\xEC\x55\x74\x08\x75\x06\xE8\x00\x00\x00\x00\xC3\x50\xEB\xFF\xC0\x58\x76\x34\x8A\xC0\x77\x0F", "xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx????xxxxxxxxxxxx") \
    X(VALIDATE_CFUNC_PTR                , 0, 0, "\x48\x83\xEC\x28\x48\x8B\xD1\x48\x85\xC9\x75\x07\xC6\x44\x24\x30\x53\xEB\x36\x48\x8B\x05\x00\x00\x00\x00\x48\x85\xC0\x75\x07\xC6\x44\x24\x30\x12\xEB\x23\x4C\x8B\x00\x48\x8B\x48\x08\x49\x03\xC8\x48\x3B\xD1\x73\x07\xB0\xCB\x49\x3B\xD0\x73\x04\xB0\xCE", "xxxxxxxxxxxxxxxxxxxxxx????xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx") \
    X(IS_VALUE_NOT_SECRET               , 0, 0, "\x48\x83\xEC\x28\xE8\x00\x00\x00\x00\x0F\xB6\x40\x09\x48\x83\xC4\x28\xC3", "xxxxx????xxxxxxxxx") \
    X(LUAG_SECRETERROR                  , 0, 0, "\x48\x8B\xC4\x48\x89\x58\x10\x48\x89\x68\x18\x48\x89\x70\x20\x57\x48\x81\xEC\x80\x00\x00\x00\xF6\x05\x00\x00\x00\x00\x04\x49\x8B\xF0\x48\x8B\xDA\x48\x8B\xF9\x74\x31\xC7\x40\xB8\x04\x00\x00\x00\x48\x8D\x54\x24\x40\x4C\x89\x40\xE0", "xxxxxxxxxxxxxxxxxxxxxxxxx????xxxxxxxxxxxxxxxxxxxxxxxxxxxx") \
    X(RESOLVER_LOCKDOWN_BYPASS          , 1, 0, "\xCC", "x") \
    X(RESOLVER_CANCALL_BYPASS           , 1, 0, "\xCC", "x") \
    X(FORBIDDEN_TBL_0                   , 1, 0, "\xCC", "x") \
    X(FORBIDDEN_TBL_1                   , 1, 0, "\xCC", "x") \
    X(FORBIDDEN_TBL_2                   , 1, 0, "\xCC", "x") \
    X(FORBIDDEN_TBL_3                   , 1, 0, "\xCC", "x") \
    X(FORBIDDEN_TBL_4                   , 1, 0, "\xCC", "x") \
    X(FORBIDDEN_TBL_5                   , 1, 0, "\xCC", "x") \
    X(FORBIDDEN_TBL_6                   , 1, 0, "\xCC", "x") \
    X(FORBIDDEN_TBL_7                   , 1, 0, "\xCC", "x") \
    X(FORBIDDEN_TBL_8                   , 1, 0, "\xCC", "x") \
    X(SECRET_KEY_GATE_0                 , 1, 0, "\xCC", "x") \
    X(SECRET_KEY_GATE_1                 , 1, 0, "\xCC", "x") \
    X(SECRET_KEY_GATE_2                 , 1, 0, "\xCC", "x") \
    X(SECRET_VAL_GATE_0                 , 1, 0, "\xCC", "x") \
    X(SECRET_VAL_GATE_1                 , 1, 0, "\xCC", "x") \
    X(SECRET_VAL_GATE_2                 , 1, 0, "\xCC", "x") \
    X(SECRET_VAL_GATE_3                 , 1, 0, "\xCC", "x") \
    X(SECRET_VAL_GATE_4                 , 1, 0, "\xCC", "x") \
    X(SECRET_VAL_GATE_5                 , 1, 0, "\xCC", "x") \
    X(SECRET_VAL_GATE_6                 , 1, 0, "\xCC", "x") \
    X(SECRET_VAL_GATE_7                 , 1, 0, "\xCC", "x") \
    X(SECRET_VAL_GATE_8                 , 1, 0, "\xCC", "x") \
    X(SECRET_VAL_GATE_9                 , 1, 0, "\xCC", "x") \
    X(SECRET_VAL_GATE_10                , 1, 0, "\xCC", "x") \
    X(SECRET_VAL_GATE_11                , 1, 0, "\xCC", "x") \
    X(SECRET_VAL_GATE_12                , 1, 0, "\xCC", "x") \
    X(SECRET_VAL_GATE_13                , 1, 0, "\xCC", "x") \
    X(SECRET_VAL_GATE_14                , 1, 0, "\xCC", "x") \
    X(SECRET_VAL_GATE_15                , 1, 0, "\xCC", "x") \
    X(SECRET_VAL_GATE_16                , 1, 0, "\xCC", "x") \
    X(SECRET_VAL_GATE_17                , 1, 0, "\xCC", "x") \
    X(SECRET_VAL_GATE_18                , 1, 0, "\xCC", "x") \
    X(SECRET_VAL_GATE_19                , 1, 0, "\xCC", "x") \
    X(SECRET_VAL_GATE_20                , 1, 0, "\xCC", "x") \
    X(SECRET_VAL_GATE_21                , 1, 0, "\xCC", "x") \
    X(SECRET_VAL_GATE_22                , 1, 0, "\xCC", "x") \
    X(SECRET_VAL_GATE_23                , 1, 0, "\xCC", "x") \
    X(SECRET_VAL_GATE_24                , 1, 0, "\xCC", "x") \
    X(SECRET_VAL_GATE_25                , 1, 0, "\xCC", "x") \
    X(SECRET_VAL_GATE_26                , 1, 0, "\xCC", "x") \
    X(C_API_SECRET_ARG_GATE             , 0, 0, "\x48\x83\xEC\x28\x4C\x8B\xD1\xE8\x00\x00\x00\x00\x80\x78\x09\x00\x74\x27\x49\x8B\x42\x40\x0F\xBE\x48\x24\x85\xC9\x74\x14\x83\xF9", "xxxxxxxx????xxxxxxxxxxxxxxxxxxxx") \
    X(C_API_TYPE_GATE_0                 , 1, 0, "\xCC", "x") \
    X(C_API_TYPE_GATE_1                 , 1, 0, "\xCC", "x") \
    X(C_API_TYPE_GATE_2                 , 1, 0, "\xCC", "x") \
    X(C_API_TYPE_GATE_3                 , 1, 0, "\xCC", "x") \
    X(C_API_TYPE_GATE_4                 , 1, 0, "\xCC", "x") \
    X(C_API_TYPE_GATE_5                 , 1, 0, "\xCC", "x") \
    X(LUAL_LOADBUFFER                   , 0, 0, "\x40\x53\x48\x83\xEC\x30\x49\x83\xF8\x03\x72\x19\x80\x3A\xEF\x75\x14\x80\x7A\x01\xBB\x75\x0E\x80\x7A\x02\xBF\x75\x08\x48\x83\xC2\x03\x49\x83\xE8\x03\x48\x89\x54\x24\x20\x48\x8D\x15", "xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx") \
    X(LUA_PCALL                         , 0, 0, "\x48\x89\x5C\x24\x08\x48\x89\x74\x24\x10\x57\x48\x83\xEC\x40\x41\x8B\xF0\x44\x8B\xD2\x48\x8B\xD9\x45\x85\xC9\x75\x04\x33\xC0\xEB\x0C\x41\x8B\xD1\xE8\x00\x00\x00\x00\x48\x2B\x43\x58", "xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx????xxxx") \
    X(G_LUASTATE                        , 2, 3, "\x48\x8B\x1D\x00\x00\x00\x00\x48\x8B\xCB\xE8", "xxx????xxxx") \
    X(G_TAINT_HANDLER_PTR               , 1, 0, "\xCC", "x") \
    X(G_LUASTATE_CREATE_COUNT           , 1, 0, "\xCC", "x") \
    X(DUMMYNODE                         , 1, 0, "\xCC", "x") \
    X(g_pRealObjectMgr                  , 2, 3, "\x48\x8B\x05\x00\x00\x00\x00\x48\x8B\xF1\x33\xFF\x33\xDB", "xxx????xxxxxxx") \
    X(g_pZoneMapContext                 , 1, 0, "\xCC", "x") \
    X(g_pObjectMgr                      , 2, 3, "\x48\x8B\x05\x00\x00\x00\x00\x48\x8B\xF1\x33\xFF\x33\xDB", "xxx????xxxxxxx") \
    X(g_pEntityHandleBuckets            , 1, 0, "\xCC", "x") \
    X(g_activePlayerUnit                , 2, 3, "\x48\x8B\x05\x00\x00\x00\x00\x48\x85\xC0\x48\x0F\x44\x05", "xxx????xxxxxxx") \
    X(ActivePlayerGUID                  , 1, 0, "\xCC", "x") \
    X(TargetGUID                        , 1, 0, "\xCC", "x") \
    X(FocusGUID                         , 1, 0, "\xCC", "x") \
    X(MouseoverGUID                     , 1, 0, "\xCC", "x") \
    X(NpcTargetGUID                     , 1, 0, "\xCC", "x") \
    X(g_MissileInFlightListHead         , 1, 0, "\xCC", "x") \
    X(g_GameStateFlags                  , 2, 3, "\x0F\xB7\x05\x00\x00\x00\x00\x0F\xBA\xE0\x09", "xxx????xxxx") \
    X(ACTIVE_SPEC_ID                    , 1, 0, "\xCC", "x") \
    X(HANDLE_TERRAIN_CLICK              , 0, 0, "\x48\x89\x5C\x24\x10\x48\x89\x6C\x24\x18\x48\x89\x74\x24\x20\x57\x48\x83\xEC\x40\x49\x8B\xF1\x48\x8B\xEA\x8B\xF9\xE8\x00\x00\x00\x00\x48\x8B\xD8\x48\x85\xC0", "xxxxxxxxxxxxxxxxxxxxxxxxxxxxx????xxxxxx") \
    X(SPELL_CLICK_CONTEXT               , 1, 0, "\xCC", "x") \
    X(SPELL_TARGETING_FLAGS             , 1, 0, "\xCC", "x") \
    X(SPELL_TARGETING_GUID              , 1, 0, "\xCC", "x") \
    X(SPELL_STOP_TARGETING              , 0, 0, "\x48\x89\x5C\x24\x18\x55\x48\x8D\xAC\x24\x90\xFC\xFF\xFF\x48\x81\xEC\x70\x04\x00\x00\x80\x3D\x00\x00\x00\x00\x00\x8B\xD9\x0F\x85\xB4\x01\x00\x00\x48\x89\xBC\x24\x80\x04\x00\x00\x48\x8D\x54\x24\x70\x48\x8B\x3D\x00\x00\x00\x00\x48\x8B\xCF\xC6\x05\x00\x00\x00\x00\x01", "xxxxxxxxxxxxxxxxxxxxxxx????xxxxxxxxxxxxxxxxxxxxxxxxx????xxxxx????x") \
    X(SPELL_C_CASTSPELL_WRAPPER         , 1, 0, "\xCC", "x") \
    X(SPELL_CAST_PARAMS_VERSION         , 1, 0, "\xCC", "x") \
    X(SPELL_C_CAST_GUID_DIRECT          , 0, 0, "\x48\x89\x5C\x24\x10\x55\x56\x57\x41\x54\x41\x55\x41\x56\x41\x57\x48\x81\xEC\x80\x00\x00\x00\x0F\xB7\x2D\x00\x00\x00\x00\x45\x8B", "xxxxxxxxxxxxxxxxxxxxxxxxxx????xx") \
    X(SPELL_C_CAST_GUID_IMPL            , 0, 0, "\x48\x89\x5C\x24\x20\x48\x89\x4C\x24\x08\x55\x56\x57\x41\x54\x41\x55\x48\x83\xEC\x30\x8B\x9C\x24\x88\x00\x00\x00\x45\x8B\xE8\x8B\xBC\x24\xC0\x00\x00\x00\x8B\xEA", "xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx") \
    X(SPELL_C_GET_LOCAL_MANAGER         , 1, 0, "\xCC", "x") \
    X(CombatLog_PushEventArgs           , 1, 0, "\xCC", "x") \
    X(g_CLEU_CurrentEventEntry          , 1, 0, "\xCC", "x") \
    X(CAM_MGR                           , 2, 3, "\x48\x8B\x05\x00\x00\x00\x00\x48\x8B\x88\xB0\x04\x00\x00", "xxx????xxxxxxx") \
    X(WORLD_ORIGIN_BIAS                 , 1, 0, "\xCC", "x") \
    X(WORLDFRAME_PROJECT_POINT          , 0, 0, "\x48\x8B\xC4\x48\x89\x58\x08\x48\x89\x70\x10\x57\x48\x81\xEC\xE0\x00\x00\x00\xF6\x81\x10\x01\x00\x00\x01\x49\x8B\xF0\x48\x8B\xDA\x48\x8B\xF9\x0F\x84\x10\x03\x00\x00\x0F\x10\x59\x38\xF3\x0F\x10\x91\x08\x01\x00\x00\xF3\x0F\x59\x91\xB0\x01\x00\x00", "xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx") \
    X(CAM_FOV_RAW                       , 1, 0, "\xCC", "x") \
    X(WORLD_INTERSECT                   , 0, 0, "\x48\x8B\xC4\x48\x89\x58\x10\x48\x89\x68\x18\x56\x57\x41\x57\x48\x81\xEC\xA0\x00\x00\x00\x33\xF6\x48\x8B\xF9\x48\x89\x74\x24\x30\x48\x8D\x48\x20\x0F\x57\xC0\x48", "xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx") \
    X(G_P_WORLD_FRAME                   , 1, 0, "\xCC", "x") \
    X(INTERACT_UNIT                     , 0, 0, "\x40\x55\x56\x48\x83\xEC\x28\x8B\xF2\x48\x8B\xE9\xE8\x00\x00\x00\x00\x48\x85\xC0\x75\x09\xB0\x01\x48\x83\xC4\x28\x5E\x5D\xC3\x48", "xxxxxxxxxxxxx????xxxxxxxxxxxxxxx") \
    X(LUA_NEWSTATE                      , 0, 0, "\x48\x89\x5C\x24\x18\x55\x56\x41\x56\x48\x83\xEC\x20\x48\x8B\xF2\x45\x8B\xF0\x48\x8B\xE9\x41\xB9\xB8\x02\x00\x00\x48\x8B\xCE\x45\x33\xC0\x33\xD2\xFF\xD5", "xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx") \
    X(LUAH_NEW                          , 0, 0, "\x48\x89\x5C\x24\x08\x48\x89\x6C\x24\x10\x48\x89\x74\x24\x18\x57\x48\x83\xEC\x20\x41\x8B\xF0\x8B\xDA\x45\x33\xC0\x33\xD2\x41\xB9\x48\x00\x00\x00\x48\x8B\xE9\xE8\x00\x00\x00\x00\x41\xB0\x05", "xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx????xxx") \
    X(LUA_PUSHBOOLEAN                   , 0, 0, "\x4C\x8B\x41\x28\x66\x41\xC7\x40\x08\x01\x00\x48\x8B\x05\x00\x00\x00\x00\x49\x89\x40\x10\x33\xC0\x85\xD2\x0F\x95\xC0\x41\x89\x00\x48\x83\x41\x28\x18\xC3", "xxxxxxxxxxxxxx????xxxxxxxxxxxxxxxxxxxx") \
    X(WOWGUID_TO_STRING                 , 0, 0, "\x48\x89\x5C\x24\x18\x48\x89\x6C\x24\x20\x56\x48\x83\xEC\x20\x41\x8B\xF0\x48\x8B\xDA\x48\x8B\xE9\x45\x85\xC0\x75\x12\x33\xC0\x48\x8B\x5C\x24\x40", "xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx")
/* clang-format on */

#endif /* DINKR_SIG_DEFS_H */
