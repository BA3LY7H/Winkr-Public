/* wk_lua_prefix.h — rename all lua_* symbols to wk_lua_* to avoid collision with WoW's Lua */
#pragma once

/*
 * These macros are applied BEFORE including any Lua .c files (via the
 * luaall.c pattern). They ensure that every public Lua C API symbol
 * compiled from vendor sources carries the wk_lua_ prefix, preventing
 * any collision with WoW's own lua_* symbols.
 *
 * Only actual function/data symbols are renamed here. Macros that expand
 * to calls to already-renamed underlying functions (e.g. lua_pop,
 * lua_newtable, lua_pushcfunction, luaL_checkstring) must NOT be listed
 * — they would cause -Wmacro-redefined errors when lua.h redefines them.
 *
 * Type names (lua_State, lua_CFunction, etc.) are NOT renamed because
 * they do not create linker symbols.
 */

/* ---- State lifecycle ------------------------------------------------- */
#define lua_newstate            wk_lua_newstate
#define lua_close               wk_lua_close
#define lua_newthread           wk_lua_newthread
#define lua_atpanic             wk_lua_atpanic

/* ---- Stack manipulation ---------------------------------------------- */
#define lua_gettop              wk_lua_gettop
#define lua_settop              wk_lua_settop
#define lua_pushvalue           wk_lua_pushvalue
#define lua_remove              wk_lua_remove
#define lua_insert              wk_lua_insert
#define lua_replace             wk_lua_replace
#define lua_checkstack          wk_lua_checkstack
#define lua_xmove               wk_lua_xmove

/* ---- Access functions (stack -> C) ----------------------------------- */
#define lua_isnumber            wk_lua_isnumber
#define lua_isstring            wk_lua_isstring
#define lua_iscfunction         wk_lua_iscfunction
#define lua_isuserdata          wk_lua_isuserdata
#define lua_type                wk_lua_type
#define lua_typename            wk_lua_typename
#define lua_equal               wk_lua_equal
#define lua_rawequal            wk_lua_rawequal
#define lua_lessthan            wk_lua_lessthan
#define lua_tonumber            wk_lua_tonumber
#define lua_tointeger           wk_lua_tointeger
#define lua_toboolean           wk_lua_toboolean
#define lua_tolstring           wk_lua_tolstring
#define lua_objlen              wk_lua_objlen
#define lua_tocfunction         wk_lua_tocfunction
#define lua_touserdata          wk_lua_touserdata
#define lua_tothread            wk_lua_tothread
#define lua_topointer           wk_lua_topointer

/* ---- Push functions (C -> stack) ------------------------------------- */
#define lua_pushnil             wk_lua_pushnil
#define lua_pushnumber          wk_lua_pushnumber
#define lua_pushinteger         wk_lua_pushinteger
#define lua_pushlstring         wk_lua_pushlstring
#define lua_pushstring          wk_lua_pushstring
#define lua_pushvfstring        wk_lua_pushvfstring
#define lua_pushfstring         wk_lua_pushfstring
#define lua_pushcclosure        wk_lua_pushcclosure
#define lua_pushboolean         wk_lua_pushboolean
#define lua_pushlightuserdata   wk_lua_pushlightuserdata
#define lua_pushthread          wk_lua_pushthread

/* ---- Get functions (Lua -> stack) ------------------------------------ */
#define lua_gettable            wk_lua_gettable
#define lua_getfield            wk_lua_getfield
#define lua_rawget              wk_lua_rawget
#define lua_rawgeti             wk_lua_rawgeti
#define lua_createtable         wk_lua_createtable
#define lua_newuserdata         wk_lua_newuserdata
#define lua_getmetatable        wk_lua_getmetatable
#define lua_getfenv             wk_lua_getfenv

/* ---- Set functions (stack -> Lua) ------------------------------------ */
#define lua_settable            wk_lua_settable
#define lua_setfield            wk_lua_setfield
#define lua_rawset              wk_lua_rawset
#define lua_rawseti             wk_lua_rawseti
#define lua_setmetatable        wk_lua_setmetatable
#define lua_setfenv             wk_lua_setfenv

/* ---- Load and call --------------------------------------------------- */
#define lua_call                wk_lua_call
#define lua_pcall               wk_lua_pcall
#define lua_cpcall              wk_lua_cpcall
#define lua_load                wk_lua_load
#define lua_dump                wk_lua_dump

/* ---- Coroutine functions --------------------------------------------- */
#define lua_yield               wk_lua_yield
#define lua_resume              wk_lua_resume
#define lua_status              wk_lua_status

/* ---- Garbage collection ---------------------------------------------- */
#define lua_gc                  wk_lua_gc

/* ---- Miscellaneous --------------------------------------------------- */
#define lua_error               wk_lua_error
#define lua_next                wk_lua_next
#define lua_concat              wk_lua_concat
#define lua_getallocf           wk_lua_getallocf
#define lua_setallocf           wk_lua_setallocf

/* ---- Debug API ------------------------------------------------------- */
#define lua_getstack            wk_lua_getstack
#define lua_getinfo             wk_lua_getinfo
#define lua_getlocal            wk_lua_getlocal
#define lua_setlocal            wk_lua_setlocal
#define lua_getupvalue          wk_lua_getupvalue
#define lua_setupvalue          wk_lua_setupvalue
#define lua_sethook             wk_lua_sethook
#define lua_gethook             wk_lua_gethook
#define lua_gethookmask         wk_lua_gethookmask
#define lua_gethookcount        wk_lua_gethookcount

/* ---- Compatibility hack ---------------------------------------------- */
#define lua_setlevel            wk_lua_setlevel

/* ---- Internal data symbols (prevent collision under luaall_c) -------- */
#define luaT_typenames          wk_luaT_typenames
#define luaX_tokens             wk_luaX_tokens

/* ---- Auxiliary library (lauxlib.h) ----------------------------------- */
#define luaL_openlib            wk_luaL_openlib
#define luaL_register           wk_luaL_register
#define luaL_getmetafield       wk_luaL_getmetafield
#define luaL_callmeta           wk_luaL_callmeta
#define luaL_typerror           wk_luaL_typerror
#define luaL_argerror           wk_luaL_argerror
#define luaL_checklstring       wk_luaL_checklstring
#define luaL_optlstring         wk_luaL_optlstring
#define luaL_checknumber        wk_luaL_checknumber
#define luaL_optnumber          wk_luaL_optnumber
#define luaL_checkinteger       wk_luaL_checkinteger
#define luaL_optinteger         wk_luaL_optinteger
#define luaL_checkstack         wk_luaL_checkstack
#define luaL_checktype          wk_luaL_checktype
#define luaL_checkany           wk_luaL_checkany
#define luaL_newmetatable       wk_luaL_newmetatable
#define luaL_checkudata         wk_luaL_checkudata
#define luaL_where              wk_luaL_where
#define luaL_error              wk_luaL_error
#define luaL_checkoption        wk_luaL_checkoption
#define luaL_ref                wk_luaL_ref
#define luaL_unref              wk_luaL_unref
#define luaL_loadfile           wk_luaL_loadfile
#define luaL_loadbuffer         wk_luaL_loadbuffer
#define luaL_loadstring         wk_luaL_loadstring
#define luaL_newstate           wk_luaL_newstate
#define luaL_gsub               wk_luaL_gsub
#define luaL_findtable          wk_luaL_findtable

/* ---- Auxiliary library: Buffer API ----------------------------------- */
#define luaL_buffinit           wk_luaL_buffinit
#define luaL_prepbuffer         wk_luaL_prepbuffer
#define luaL_addlstring         wk_luaL_addlstring
#define luaL_addstring          wk_luaL_addstring
#define luaL_addvalue           wk_luaL_addvalue
#define luaL_pushresult         wk_luaL_pushresult

/* ---- Standard library openers ---------------------------------------- */
#define luaL_openlibs           wk_luaL_openlibs
#define luaopen_base            wk_luaopen_base
#define luaopen_table           wk_luaopen_table
#define luaopen_io              wk_luaopen_io
#define luaopen_os              wk_luaopen_os
#define luaopen_string          wk_luaopen_string
#define luaopen_math            wk_luaopen_math
#define luaopen_debug           wk_luaopen_debug
#define luaopen_package         wk_luaopen_package
