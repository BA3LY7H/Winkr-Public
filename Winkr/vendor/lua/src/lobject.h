/*
** $Id: lobject.h,v 2.20.1.2 2008/08/06 13:29:48 roberto Exp $
** Type definitions for Lua objects
** See Copyright Notice in lua.h
*/


#ifndef lobject_h
#define lobject_h


#include <stdarg.h>
#include <stdint.h>
#include <string.h>


#include "llimits.h"
#include "lua.h"


/* tags for values visible from Lua */
#define LAST_TAG	LUA_TTHREAD

#define NUM_TAGS	(LAST_TAG+1)


/*
** Extra tags for non-values
*/
#define LUA_TPROTO	(LAST_TAG+1)
#define LUA_TUPVAL	(LAST_TAG+2)
#define LUA_TDEADKEY	(LAST_TAG+3)


/*
** Union of all collectable objects
*/
typedef union GCObject GCObject;


/*
** WoW-patched CommonHeader: 18 bytes total.
** Layout (IDA-confirmed, WoW build 66431):
**   +0x00: next           (8 bytes, GCObject*)
**   +0x08: _wk_gc_taint   (8 bytes, WoW GC taint source pointer)
**          IDA proof: luaS_newlstr_from_buf at 0x100020930: STR X8, [X0,#8]
**   +0x10: tt             (1 byte, type tag)
**          IDA proof: propagatemark at 0x1000185E4: switch(*(BYTE*)(v3+16))
**                     luaS_newlstr_from_buf at 0x100020908: STRB W8, [X0,#0x10]
**   +0x11: marked         (1 byte, GC color)
**          IDA proof: luaC_barrierf at 0x10001834C: *(_BYTE*)(a2+17)
** (CommonHeader expanded from vanilla 10→18 bytes.)
*/
#define CommonHeader	GCObject *next; lu_byte _wk_gc_taint[8]; \
	lu_byte tt; lu_byte marked


/*
** Common header in struct form
*/
typedef struct GCheader {
  CommonHeader;
} GCheader;




/*
** Union of all Lua values
** NOTE: GCObject *gc is kept (not replaced by void *p) so that existing
** Lua source code referencing value.gc compiles unmodified.
*/
typedef union {
  GCObject *gc;     /* collectable objects */
  lua_Number n;     /* LUA_TNUMBER */
  void      *p;     /* light userdata */
  int        b;     /* LUA_TBOOLEAN */
  uintptr_t  fn;    /* lua_CFunction (stored as integer, avoids -Wpedantic) */
} Value;


/*
** Tagged Values
**
** WoW-modified TValue: 24 bytes to accommodate taint metadata.
** Vanilla Lua 5.1 uses 16 bytes; WoW extends it with is_secret + taint_src.
** The vendored build must match this layout exactly.
*/

#define TValuefields \
  Value value; lu_byte tt; lu_byte is_secret; lu_byte _wk_pad[6]; uint64_t taint_src

typedef struct lua_TValue {
  Value    value;      /* +0  (8 bytes) */
  lu_byte  tt;         /* +8  type tag  */
  lu_byte  is_secret;  /* +9  taint marker flag */
  lu_byte  _wk_pad[6]; /* +10 alignment padding */
  uint64_t taint_src;  /* +16 taint source pointer */
} __attribute__((aligned(8))) TValue;

/* Clean new values: zero the WoW-only taint fields on every fresh write */
#define setcleanvalue(obj) \
  do { __typeof__(obj) __mk_clean_obj = (obj); \
    lua_assert(((uintptr_t)__mk_clean_obj & 0x7) == 0 && "TValue pointer must be 8-byte aligned"); \
    __mk_clean_obj->is_secret = 0; \
    memset(__mk_clean_obj->_wk_pad, 0, sizeof(__mk_clean_obj->_wk_pad)); \
    __mk_clean_obj->taint_src = 0; } while(0)


/* Macros to test type */
#define ttisnil(o)	(ttype(o) == LUA_TNIL)
#define ttisnumber(o)	(ttype(o) == LUA_TNUMBER)
#define ttisstring(o)	(ttype(o) == LUA_TSTRING)
#define ttistable(o)	(ttype(o) == LUA_TTABLE)
#define ttisfunction(o)	(ttype(o) == LUA_TFUNCTION)
#define ttisboolean(o)	(ttype(o) == LUA_TBOOLEAN)
#define ttisuserdata(o)	(ttype(o) == LUA_TUSERDATA)
#define ttisthread(o)	(ttype(o) == LUA_TTHREAD)
#define ttislightuserdata(o)	(ttype(o) == LUA_TLIGHTUSERDATA)

/* Macros to access values */
#define ttype(o)	((o)->tt)
#define gcvalue(o)	check_exp(iscollectable(o), (o)->value.gc)
#define pvalue(o)	check_exp(ttislightuserdata(o), (o)->value.p)
#define nvalue(o)	check_exp(ttisnumber(o), (o)->value.n)
#define rawtsvalue(o)	check_exp(ttisstring(o), &(o)->value.gc->ts)
#define tsvalue(o)	(&rawtsvalue(o)->tsv)
#define rawuvalue(o)	check_exp(ttisuserdata(o), &(o)->value.gc->u)
#define uvalue(o)	(&rawuvalue(o)->uv)
#define clvalue(o)	check_exp(ttisfunction(o), &(o)->value.gc->cl)
#define hvalue(o)	check_exp(ttistable(o), &(o)->value.gc->h)
#define bvalue(o)	check_exp(ttisboolean(o), (o)->value.b)
#define thvalue(o)	check_exp(ttisthread(o), &(o)->value.gc->th)

#define l_isfalse(o)	(ttisnil(o) || (ttisboolean(o) && bvalue(o) == 0))

/*
** for internal debug only
*/
#define checkconsistency(obj) \
  lua_assert(!iscollectable(obj) || (ttype(obj) == (obj)->value.gc->gch.tt))

#define checkliveness(g,obj) \
  lua_assert(!iscollectable(obj) || \
  ((ttype(obj) == (obj)->value.gc->gch.tt) && !isdead(g, (obj)->value.gc)))


/* Macros to set values */
#define setnilvalue(obj) \
  do { __typeof__(obj) __mk_nil_obj=(obj); __mk_nil_obj->tt=LUA_TNIL; setcleanvalue(__mk_nil_obj); } while(0)

#define setnvalue(obj,x) \
  do { TValue *i_o=(obj); i_o->value.n=(x); i_o->tt=LUA_TNUMBER; \
    setcleanvalue(i_o); } while(0)

#define setpvalue(obj,x) \
  do { TValue *i_o=(obj); i_o->value.p=(x); i_o->tt=LUA_TLIGHTUSERDATA; \
    setcleanvalue(i_o); } while(0)

#define setbvalue(obj,x) \
  do { TValue *i_o=(obj); i_o->value.b=(x); i_o->tt=LUA_TBOOLEAN; \
    setcleanvalue(i_o); } while(0)

#define setsvalue(L,obj,x) \
  do { TValue *i_o=(obj); \
    i_o->value.gc=cast(GCObject *, (x)); i_o->tt=LUA_TSTRING; \
    setcleanvalue(i_o); checkliveness(G(L),i_o); } while(0)

#define setuvalue(L,obj,x) \
  do { TValue *i_o=(obj); \
    i_o->value.gc=cast(GCObject *, (x)); i_o->tt=LUA_TUSERDATA; \
    setcleanvalue(i_o); checkliveness(G(L),i_o); } while(0)

#define setthvalue(L,obj,x) \
  do { TValue *i_o=(obj); \
    i_o->value.gc=cast(GCObject *, (x)); i_o->tt=LUA_TTHREAD; \
    setcleanvalue(i_o); checkliveness(G(L),i_o); } while(0)

#define setclvalue(L,obj,x) \
  do { TValue *i_o=(obj); \
    i_o->value.gc=cast(GCObject *, (x)); i_o->tt=LUA_TFUNCTION; \
    setcleanvalue(i_o); checkliveness(G(L),i_o); } while(0)

#define sethvalue(L,obj,x) \
  do { TValue *i_o=(obj); \
    i_o->value.gc=cast(GCObject *, (x)); i_o->tt=LUA_TTABLE; \
    setcleanvalue(i_o); checkliveness(G(L),i_o); } while(0)

#define setptvalue(L,obj,x) \
  do { TValue *i_o=(obj); \
    i_o->value.gc=cast(GCObject *, (x)); i_o->tt=LUA_TPROTO; \
    setcleanvalue(i_o); checkliveness(G(L),i_o); } while(0)




/*
** ARM64 alignment safety: compiler barrier prevents Clang from merging
** adjacent field copies into LDP/STP pair instructions, which fault on
** misaligned addresses on Apple Silicon. Individual LDR/STR instructions
** handle unaligned access in hardware.
*/
#if defined(__aarch64__) || defined(__arm64__)
#define WK_ALIGN_BARRIER() __asm__ volatile("" ::: "memory")
#else
#define WK_ALIGN_BARRIER() ((void)0)
#endif

#define setobj(L,obj1,obj2) \
  do { const TValue *o2=(obj2); TValue *o1=(obj1); \
    o1->value = o2->value; \
    WK_ALIGN_BARRIER(); \
    o1->tt = o2->tt; \
    o1->is_secret = o2->is_secret; \
    memcpy(o1->_wk_pad, o2->_wk_pad, sizeof(o1->_wk_pad)); \
    WK_ALIGN_BARRIER(); \
    o1->taint_src = o2->taint_src; \
    checkliveness(G(L),o1); } while(0)


/*
** different types of sets, according to destination
*/

/* from stack to (same) stack */
#define setobjs2s	setobj
/* to stack (not from same stack) */
#define setobj2s	setobj
#define setsvalue2s	setsvalue
#define sethvalue2s	sethvalue
#define setptvalue2s	setptvalue
/* from table to same table */
#define setobjt2t	setobj
/* to table */
#define setobj2t	setobj
/* to new object */
#define setobj2n	setobj
#define setsvalue2n	setsvalue

#define setttype(obj, tt) (ttype(obj) = (tt))


#define iscollectable(o)	(ttype(o) >= LUA_TSTRING)



typedef TValue *StkId;  /* index to stack elements */


/*
** String headers for string table
*/
typedef union TString {
  L_Umaxalign dummy;  /* ensures maximum alignment for strings */
  struct {
    CommonHeader;
    lu_byte reserved;
    unsigned int hash;
    size_t len;
  } tsv;
} TString;


#define getstr(ts)	cast(const char *, (ts) + 1)
#define svalue(o)       getstr(rawtsvalue(o))



typedef union Udata {
  L_Umaxalign dummy;  /* ensures maximum alignment for `local' udata */
  struct {
    CommonHeader;
    struct Table *metatable;
    struct Table *env;
    size_t len;
  } uv;
} Udata;




/*
** Function Prototypes
*/
typedef struct Proto {
  CommonHeader;
  TValue *k;  /* constants used by the function */
  Instruction *code;
  struct Proto **p;  /* functions defined inside the function */
  int *lineinfo;  /* map from opcodes to source lines */
  struct LocVar *locvars;  /* information about local variables */
  TString **upvalues;  /* upvalue names */
  TString  *source;
  int sizeupvalues;
  int sizek;  /* size of `k' */
  int sizecode;
  int sizelineinfo;
  int sizep;  /* size of `p' */
  int sizelocvars;
  int linedefined;
  int lastlinedefined;
  GCObject *gclist;
  lu_byte nups;  /* number of upvalues */
  lu_byte numparams;
  lu_byte is_vararg;
  lu_byte maxstacksize;
} Proto;


/* masks for new-style vararg */
#define VARARG_HASARG		1
#define VARARG_ISVARARG		2
#define VARARG_NEEDSARG		4


typedef struct LocVar {
  TString *varname;
  int startpc;  /* first point where variable is active */
  int endpc;    /* first point where variable is dead */
} LocVar;



/*
** Upvalues
*/

typedef struct UpVal {
  CommonHeader;
  TValue *v;  /* points to stack or to its own value */
  union {
    TValue value;  /* the value (when closed) */
    struct {  /* double linked list (when open) */
      struct UpVal *prev;
      struct UpVal *next;
    } l;
  } u;
} UpVal;


/*
** Closures
*/

#define ClosureHeader \
	CommonHeader; lu_byte isC; lu_byte nupvalues; GCObject *gclist; \
	struct Table *env; \
	void *_wk_cl_taint  /* WoW: per-closure taint tracking struct (+40, IDA-confirmed) */

typedef struct CClosure {
  ClosureHeader;
  lua_CFunction f;
  TValue upvalue[1];
} CClosure;


typedef struct LClosure {
  ClosureHeader;
  struct Proto *p;
  UpVal *upvals[1];
} LClosure;


typedef union Closure {
  CClosure c;
  LClosure l;
} Closure;


#define iscfunction(o)	(ttype(o) == LUA_TFUNCTION && clvalue(o)->c.isC)
#define isLfunction(o)	(ttype(o) == LUA_TFUNCTION && !clvalue(o)->c.isC)


/*
** Tables
*/

typedef union TKey {
  struct {
    TValuefields;
    struct Node *next;  /* for chaining */
  } nk;
  TValue tvk;
} TKey;


typedef struct Node {
  TValue i_val;
  TKey i_key;
} Node;


typedef struct Table {
  CommonHeader;
  lu_byte flags;  /* 1<<p means tagmethod(p) is not present */ 
  lu_byte lsizenode;  /* log2 of size of `node' array */
  struct Table *metatable;
  TValue *array;  /* array part */
  Node *node;
  Node *lastfree;  /* any free position is before this position */
  GCObject *gclist;
  int sizearray;  /* size of `array' array */
} Table;



/*
** `module' operation for hashing (size is always a power of 2)
*/
#define lmod(s,size) \
	(check_exp((size&(size-1))==0, (cast(int, (s) & ((size)-1)))))


#define twoto(x)	(1<<(x))
#define sizenode(t)	(twoto((t)->lsizenode))


#define luaO_nilobject		(&luaO_nilobject_)

LUAI_DATA const TValue luaO_nilobject_;

#define ceillog2(x)	(luaO_log2((x)-1) + 1)

LUAI_FUNC int luaO_log2 (unsigned int x);
LUAI_FUNC int luaO_int2fb (unsigned int x);
LUAI_FUNC int luaO_fb2int (int x);
LUAI_FUNC int luaO_rawequalObj (const TValue *t1, const TValue *t2);
LUAI_FUNC int luaO_str2d (const char *s, lua_Number *result);
LUAI_FUNC const char *luaO_pushvfstring (lua_State *L, const char *fmt,
                                                       va_list argp);
LUAI_FUNC const char *luaO_pushfstring (lua_State *L, const char *fmt, ...);
LUAI_FUNC void luaO_chunkid (char *out, const char *source, size_t len);


#endif
