/*
** $Id: lstate.h,v 2.24.1.2 2008/01/03 15:20:39 roberto Exp $
** Global State
** See Copyright Notice in lua.h
*/

#ifndef lstate_h
#define lstate_h

#include "lua.h"

#include "lobject.h"
#include "ltm.h"
#include "lzio.h"



struct lua_longjmp;  /* defined in ldo.c */


/* table of globals */
#define gt(L)	(&L->l_gt)

/* registry */
#define registry(L)	(&G(L)->l_registry)


/* extra stack space to handle TM calls and some other extras */
#define EXTRA_STACK   5


#define BASIC_CI_SIZE           8

#define BASIC_STACK_SIZE        (2*LUA_MINSTACK)



typedef struct stringtable {
  GCObject **hash;
  lu_int32 nuse;  /* number of elements */
  int size;
} stringtable;


/*
** informations about a call
**
** WoW 66709 CallInfo is 56 bytes (0x38) -- vanilla Lua 5.1 = 40 bytes.
** IDA-confirmed from x64 build 66709:
**   nresults stride: MOV [rdx+2Ch], r15d  -> nresults at +0x2C
**   taint control:   MOV WORD PTR [rdx+24h], value -> taint at +0x24
**   taint byte:      MOV BYTE PTR [rdx+28h], 0 -> extra taint at +0x28
**   CI stride:       ADD rdx, 38h -> 56-byte stride
**   poscall reads:   MOVSX r15d, BYTE PTR [r13+25h] -> [1] is mode byte
**
** Prior 48-byte layout was from ARM/macOS build 66431/66527; x64 build
** 66709 uses 56 bytes with nresults shifted to +0x2C.
*/
typedef struct CallInfo {
  StkId base;                   /* +0x00: base for this function */
  StkId func;                   /* +0x08: function index in the stack */
  StkId	top;                    /* +0x10: top for this function */
  const Instruction *savedpc;   /* +0x18: saved PC for Lua functions */
  int tailcalls;                /* +0x20: number of tail calls lost under this entry */
  lu_byte _wk_ci_taint[8];     /* +0x24: WoW taint control block (8 bytes).
                                   IDA 66709 (x64):
                                     Lua-func precall: MOV WORD PTR [ci+24h], 0x0001
                                       -> [0]=1 (mode), [1]=0 (secret level)
                                     C-func precall:   MOV WORD PTR [ci+24h], 0x0100
                                       -> [0]=0 (mode), [1]=1 (secret level)
                                     Both paths:       MOV BYTE PTR [ci+28h], 0
                                       -> [4]=0 (return propagation)
                                     poscall:          MOVSX r15d, BYTE PTR [ci+25h]
                                       -> [1] consumed as return-propagation mode
                                     ci+0x24: security elevation byte */
  int nresults;                 /* +0x2C: expected number of results
                                   IDA 66709: MOV [rdx+2Ch], r15d in precall */
  int _wk_ci_pad[2];           /* +0x30: padding to 56-byte stride (0x38) */
} CallInfo;

#include <stddef.h>
_Static_assert(sizeof(CallInfo) == 56, "WoW 66709 CallInfo must be 56 bytes (0x38 stride)");
_Static_assert(offsetof(CallInfo, tailcalls)    == 0x20,
    "WoW 66709 CallInfo tailcalls at +0x20");
_Static_assert(offsetof(CallInfo, _wk_ci_taint) == 0x24,
    "WoW 66709 CallInfo taint control at +0x24");
_Static_assert(offsetof(CallInfo, nresults)     == 0x2C,
    "WoW 66709 CallInfo nresults at +0x2C");



#define curr_func(L)	(clvalue(L->ci->func))
#define ci_func(ci)	(clvalue((ci)->func))
#define f_isLua(ci)	(!ci_func(ci)->c.isC)
#define isLua(ci)	(ttisfunction((ci)->func) && f_isLua(ci))


/*
** `global state', shared by all threads of this state
*/
typedef struct global_State {
  stringtable strt;  /* hash table for strings */
  lua_Alloc frealloc;  /* function to reallocate memory */
  void *ud;         /* auxiliary data to `frealloc' */
  lu_byte _wk_mode;      /* +32: WoW mode byte. IDA-CONFIRMED (66527): NOT the secret access gate. Secret access is controlled by CallInfo._wk_ci_taint[1], not this field. */
  lu_byte currentwhite;   /* +33: (vanilla was +32, shifted by _wk_mode) */
  lu_byte gcstate;  /* +34: state of garbage collector (vanilla was +33) */
  /* +35: 1 byte implicit pad before int sweepstrgc */
  int sweepstrgc;  /* position of sweep in `strt' */
  GCObject *rootgc;  /* list of all collectable objects */
  GCObject **sweepgc;  /* position of sweep in `rootgc' */
  GCObject *gray;  /* list of gray objects */
  GCObject *grayagain;  /* list of objects to be traversed atomically */
  GCObject *weak;  /* list of weak tables (to be cleared) */
  GCObject *tmudata;  /* last element of list of userdata to be GC */
  Mbuffer buff;  /* temporary buffer for string concatentation */
  lu_mem GCthreshold;
  lu_mem totalbytes;  /* number of bytes currently allocated */
  lu_mem estimate;  /* an estimate of number of bytes actually in use */
  lu_mem gcdept;  /* how much GC is `behind schedule' */
  int gcpause;  /* size of pause between successive GCs */
  int gcstepmul;  /* GC `granularity' */
  lua_CFunction panic;  /* +152: to be called in unprotected errors */
  uintptr_t _wk_gs_taint[2];  /* +160: 16 bytes WoW taint fields before registry (opaque) */
  TValue l_registry;           /* +176: (vanilla was +160, shifted by _wk_gs_taint) */
  struct lua_State *mainthread;
  UpVal uvhead;  /* head of double-linked list of all open upvalues */
  struct Table *mt[NUM_TAGS];  /* metatables for basic types */
  TString *tmname[TM_N];  /* array with tag-method names */
} global_State;


/*
** `per thread' state
**
** WoW 66431 extends lua_State with several additional fields.
** All offsets are IDA-confirmed from luaE_newthread (0x100020048) and
** luaD_precall (0x100014E64).
**
** Vanilla 64-bit offsets: top=+16, base=+24, l_G=+32, ...
** WoW 66431 offsets:      top=+40, base=+48, l_G=+56, ...
**
** Extra WoW fields in the header:
**   +0x08: _wk_gc_taint (8 bytes, CommonHeader GC taint source pointer)
**   +0x10: tt (1 byte, CommonHeader type tag)
**   +0x11: marked (1 byte, CommonHeader GC color)
**   +0x12–0x17: 6-byte alignment pad after CommonHeader
**   +0x18: _wk_thread_ctx pointer (copied from parent thread)
**   +0x20: status (shifted from vanilla +10)
**   +0x21–0x27: 7-byte alignment pad before top
**
** Extra WoW fields mid-struct:
**   +0x7C: _wk_nCcalls_status (CC nesting status byte)
**   +0x7F: _wk_gcblock (GC block flag, checked in luaD_call)
*/
struct lua_State {
  CommonHeader;                         /* +0x00: 18 bytes (WoW: next+gc_taint+tt+marked) */
  lu_byte _wk_ch_align[6];             /* +0x12: 6-byte pad to reach 0x18 (8-byte alignment for _wk_thread_ctx pointer) */
  void   *_wk_thread_ctx;              /* +0x18: WoW thread context (copied from parent) */
  lu_byte status;                       /* +0x20: coroutine status byte. IDA-CONFIRMED (66527): NOT the secret access gate. Secret access is controlled by CallInfo._wk_ci_taint[1], not this field. */
  lu_byte _wk_status_align[7];         /* +0x21: align to 8 for top */
  StkId top;                            /* +0x28: first free slot in the stack */
  StkId base;                           /* +0x30: base of current function */
  global_State *l_G;                    /* +0x38 */
  CallInfo *ci;                         /* +0x40: call info for current function */
  const Instruction *savedpc;           /* +0x48: `savedpc' of current function */
  StkId stack_last;                     /* +0x50: last free slot in the stack */
  StkId stack;                          /* +0x58: stack base */
  CallInfo *end_ci;                     /* +0x60: points after end of ci array */
  CallInfo *base_ci;                    /* +0x68: array of CallInfo's */
  int stacksize;                        /* +0x70 */
  int size_ci;                          /* +0x74: size of array `base_ci' */
  unsigned short nCcalls;               /* +0x78: number of nested C calls */
  unsigned short baseCcalls;            /* +0x7A: nested C calls when resuming coroutine */
  lu_byte _wk_nCcalls_status;          /* +0x7C: WoW CC nesting status byte */
  lu_byte hookmask;                     /* +0x7D: IDA: LDRB [X19,#0x7D] in luaD_precall */
  lu_byte allowhook;                    /* +0x7E: IDA: STRB [X19,#0x7E] toggle */
  lu_byte _wk_gcblock;                  /* +0x7F: WoW GC block flag (luaD_call: LDRB [X20,#0x7F]) */
  int basehookcount;                    /* +0x80 */
  int hookcount;                        /* +0x84 */
  lua_Hook hook;                        /* +0x88: IDA: LDR [X19,#0x88] in hook check */
  TValue l_gt;                          /* +0x90: table of globals */
  TValue env;                           /* +0xA8: temporary place for environments */
  GCObject *openupval;                  /* +0xC0: list of open upvalues in this stack */
  GCObject *gclist;                     /* +0xC8 */
  struct lua_longjmp *errorJmp;         /* +0xD0: current error recover point */
  ptrdiff_t errfunc;                    /* +0xD8: current error handling function (stack index) */
};


#define G(L)	(L->l_G)


/*
** Union of all collectable objects
*/
union GCObject {
  GCheader gch;
  union TString ts;
  union Udata u;
  union Closure cl;
  struct Table h;
  struct Proto p;
  struct UpVal uv;
  struct lua_State th;  /* thread */
};


/* macros to convert a GCObject into a specific value */
#define rawgco2ts(o)	check_exp((o)->gch.tt == LUA_TSTRING, &((o)->ts))
#define gco2ts(o)	(&rawgco2ts(o)->tsv)
#define rawgco2u(o)	check_exp((o)->gch.tt == LUA_TUSERDATA, &((o)->u))
#define gco2u(o)	(&rawgco2u(o)->uv)
#define gco2cl(o)	check_exp((o)->gch.tt == LUA_TFUNCTION, &((o)->cl))
#define gco2h(o)	check_exp((o)->gch.tt == LUA_TTABLE, &((o)->h))
#define gco2p(o)	check_exp((o)->gch.tt == LUA_TPROTO, &((o)->p))
#define gco2uv(o)	check_exp((o)->gch.tt == LUA_TUPVAL, &((o)->uv))
#define ngcotouv(o) \
	check_exp((o) == NULL || (o)->gch.tt == LUA_TUPVAL, &((o)->uv))
#define gco2th(o)	check_exp((o)->gch.tt == LUA_TTHREAD, &((o)->th))

/* macro to convert any Lua object into a GCObject */
#define obj2gco(v)	(cast(GCObject *, (v)))


LUAI_FUNC lua_State *luaE_newthread (lua_State *L);
LUAI_FUNC void luaE_freethread (lua_State *L, lua_State *L1);

#endif
