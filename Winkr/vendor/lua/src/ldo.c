/*
** $Id: ldo.c,v 2.38.1.4 2012/01/18 02:27:10 roberto Exp $
** Stack and Call structure of Lua
** See Copyright Notice in lua.h
*/


#include <setjmp.h>
#include <stdlib.h>
#include <string.h>
#include <stdio.h>

#if defined(_WIN32)
#include <windows.h>
#endif

#define ldo_c
#define LUA_CORE

#include "lua.h"

#include "ldebug.h"
#include "ldo.h"
#include "lfunc.h"
#include "lgc.h"
#include "lmem.h"
#include "lobject.h"
#include "lopcodes.h"
#include "lparser.h"
#include "lstate.h"
#include "lstring.h"
#include "ltable.h"
#include "ltm.h"
#include "lundump.h"
#include "lvm.h"
#include "lzio.h"




/*
** {======================================================
** Error-recovery functions
** =======================================================
*/


/* chain list of long jump buffers */
struct lua_longjmp {
  struct lua_longjmp *previous;
  luai_jmpbuf b;
  volatile int status;  /* error code */
};


void luaD_seterrorobj (lua_State *L, int errcode, StkId oldtop) {
  switch (errcode) {
    case LUA_ERRMEM: {
      setsvalue2s(L, oldtop, luaS_newliteral(L, MEMERRMSG));
      break;
    }
    case LUA_ERRERR: {
      setsvalue2s(L, oldtop, luaS_newliteral(L, "error in error handling"));
      break;
    }
    case LUA_ERRSYNTAX:
    case LUA_ERRRUN: {
      setobjs2s(L, oldtop, L->top - 1);  /* error message on current top */
      break;
    }
  }
  L->top = oldtop + 1;
}


static void restore_stack_limit (lua_State *L) {
  lua_assert(L->stack_last - L->stack == L->stacksize - EXTRA_STACK - 1);
  if (L->size_ci > LUAI_MAXCALLS) {  /* there was an overflow? */
    int inuse = cast_int(L->ci - L->base_ci);
    if (inuse + 1 < LUAI_MAXCALLS)  /* can `undo' overflow? */
      luaD_reallocCI(L, LUAI_MAXCALLS);
  }
}


static void resetstack (lua_State *L, int status) {
  L->ci = L->base_ci;
  L->base = L->ci->base;
  luaF_close(L, L->base);  /* close eventual pending closures */
  luaD_seterrorobj(L, status, L->base);
  L->nCcalls = L->baseCcalls;
  L->allowhook = 1;
  restore_stack_limit(L);
  L->errfunc = 0;
  L->errorJmp = NULL;
}


void luaD_throw (lua_State *L, int errcode) {
  if (L->errorJmp) {
    L->errorJmp->status = errcode;
    LUAI_THROW(L, L->errorJmp);
  }
  else {
    L->status = cast_byte(errcode);
    if (G(L)->panic) {
      resetstack(L, errcode);
      lua_unlock(L);
      G(L)->panic(L);
    }
    exit(EXIT_FAILURE);
  }
}


int luaD_rawrunprotected (lua_State *L, Pfunc f, void *ud) {
  struct lua_longjmp lj;
  lj.status = 0;
  lj.previous = L->errorJmp;  /* chain new error handler */
  L->errorJmp = &lj;
  LUAI_TRY(L, &lj,
    (*f)(L, ud);
  );
  L->errorJmp = lj.previous;  /* restore old error handler */
  return lj.status;
}

/* }====================================================== */


static void correctstack (lua_State *L, TValue *oldstack) {
  CallInfo *ci;
  GCObject *up;
  L->top = (L->top - oldstack) + L->stack;
  for (up = L->openupval; up != NULL; up = up->gch.next)
    gco2uv(up)->v = (gco2uv(up)->v - oldstack) + L->stack;
  for (ci = L->base_ci; ci <= L->ci; ci++) {
    ci->top = (ci->top - oldstack) + L->stack;
    ci->base = (ci->base - oldstack) + L->stack;
    ci->func = (ci->func - oldstack) + L->stack;
  }
  L->base = (L->base - oldstack) + L->stack;
}


void luaD_reallocstack (lua_State *L, int newsize) {
  TValue *oldstack = L->stack;
  int realsize = newsize + 1 + EXTRA_STACK;
  lua_assert(L->stack_last - L->stack == L->stacksize - EXTRA_STACK - 1);
  luaM_reallocvector(L, L->stack, L->stacksize, realsize, TValue);
  L->stacksize = realsize;
  L->stack_last = L->stack+newsize;
  correctstack(L, oldstack);
}


void luaD_reallocCI (lua_State *L, int newsize) {
  CallInfo *oldci = L->base_ci;
  luaM_reallocvector(L, L->base_ci, L->size_ci, newsize, CallInfo);
  L->size_ci = newsize;
  L->ci = (L->ci - oldci) + L->base_ci;
  L->end_ci = L->base_ci + L->size_ci - 1;
}


void luaD_growstack (lua_State *L, int n) {
  if (n <= L->stacksize)  /* double size is enough? */
    luaD_reallocstack(L, 2*L->stacksize);
  else
    luaD_reallocstack(L, L->stacksize + n);
}


static CallInfo *growCI (lua_State *L) {
  if (L->size_ci > LUAI_MAXCALLS)  /* overflow while handling overflow? */
    luaD_throw(L, LUA_ERRERR);
  else {
    luaD_reallocCI(L, 2*L->size_ci);
    if (L->size_ci > LUAI_MAXCALLS)
      luaG_runerror(L, "stack overflow");
  }
  return ++L->ci;
}


void luaD_callhook (lua_State *L, int event, int line) {
  lua_Hook hook = L->hook;
  if (hook && L->allowhook) {
    ptrdiff_t top = savestack(L, L->top);
    ptrdiff_t ci_top = savestack(L, L->ci->top);
    lua_Debug ar;
    ar.event = event;
    ar.currentline = line;
    if (event == LUA_HOOKTAILRET)
      ar.i_ci = 0;  /* tail call; no debug information about it */
    else
      ar.i_ci = cast_int(L->ci - L->base_ci);
    luaD_checkstack(L, LUA_MINSTACK);  /* ensure minimum stack size */
    L->ci->top = L->top + LUA_MINSTACK;
    lua_assert(L->ci->top <= L->stack_last);
    L->allowhook = 0;  /* cannot call hooks inside a hook */
    lua_unlock(L);
    (*hook)(L, &ar);
    lua_lock(L);
    lua_assert(!L->allowhook);
    L->allowhook = 1;
    L->ci->top = restorestack(L, ci_top);
    L->top = restorestack(L, top);
  }
}


static StkId adjust_varargs (lua_State *L, Proto *p, int actual) {
  int i;
  int nfixargs = p->numparams;
  Table *htab = NULL;
  StkId base, fixed;
  for (; actual < nfixargs; ++actual)
    setnilvalue(L->top++);
#if defined(LUA_COMPAT_VARARG)
  if (p->is_vararg & VARARG_NEEDSARG) { /* compat. with old-style vararg? */
    int nvar = actual - nfixargs;  /* number of extra arguments */
    lua_assert(p->is_vararg & VARARG_HASARG);
    luaC_checkGC(L);
    luaD_checkstack(L, p->maxstacksize);
    htab = luaH_new(L, nvar, 1);  /* create `arg' table */
    for (i=0; i<nvar; i++)  /* put extra arguments into `arg' table */
      setobj2n(L, luaH_setnum(L, htab, i+1), L->top - nvar + i);
    /* store counter in field `n' */
    setnvalue(luaH_setstr(L, htab, luaS_newliteral(L, "n")), cast_num(nvar));
  }
#endif
  /* move fixed parameters to final position */
  fixed = L->top - actual;  /* first fixed argument */
  base = L->top;  /* final position of first argument */
  for (i=0; i<nfixargs; i++) {
    setobjs2s(L, L->top++, fixed+i);
    setnilvalue(fixed+i);
  }
  /* add `arg' parameter */
  if (htab) {
    sethvalue(L, L->top++, htab);
    lua_assert(iswhite(obj2gco(htab)));
  }
  return base;
}


static StkId tryfuncTM (lua_State *L, StkId func) {
  const TValue *tm = luaT_gettmbyobj(L, func, TM_CALL);
  StkId p;
  ptrdiff_t funcr = savestack(L, func);
  if (!ttisfunction(tm))
    luaG_typeerror(L, func, "call");
  /* Open a hole inside the stack at `func' */
  for (p = L->top; p > func; p--) setobjs2s(L, p, p-1);
  incr_top(L);
  func = restorestack(L, funcr);  /* previous call may change stack */
  setobj2s(L, func, tm);  /* tag method is the new function to be called */
  return func;
}


static int lm_precall_diag_cached = -1;
static int lm_precall_first_fault_logged = 0;

static int lm_precall_diag_enabled (void) {
  if (lm_precall_diag_cached >= 0)
    return lm_precall_diag_cached;
  {
    const char *v = getenv("LM_PRECALL_DIAG");
    lm_precall_diag_cached =
      (v != NULL && (v[0] == '1' || v[0] == 't' || v[0] == 'T' ||
                     v[0] == 'y' || v[0] == 'Y')) ? 1 : 0;
  }
  return lm_precall_diag_cached;
}

static void lm_precall_emit (const char *msg) {
  if (!msg) return;
#if defined(_WIN32)
  OutputDebugStringA(msg);
  OutputDebugStringA("\n");
#endif
  fprintf(stderr, "%s\n", msg);
}

static int lm_precall_ptr_readable (const void *ptr, size_t size) {
  if (ptr == NULL || size == 0)
    return 0;
#if defined(_WIN32)
  {
    MEMORY_BASIC_INFORMATION mbi;
    uintptr_t p = (uintptr_t)ptr;
    uintptr_t end = p + (uintptr_t)size - 1;
    if (VirtualQuery((LPCVOID)p, &mbi, sizeof(mbi)) == 0)
      return 0;
    if (mbi.State != MEM_COMMIT)
      return 0;
    if ((mbi.Protect & PAGE_GUARD) || (mbi.Protect & PAGE_NOACCESS))
      return 0;
    if (end >= (uintptr_t)mbi.BaseAddress + (uintptr_t)mbi.RegionSize)
      return 0;
  }
#endif
  return 1;
}

static void lm_precall_log (const char *reason,
                            lua_State *L,
                            StkId func,
                            int nresults,
                            int force) {
  char buf[640];
  unsigned int func_tt = 0xFFFFFFFFu;
  uintptr_t gc_ptr = 0;
  unsigned int gc_tt = 0xFFFFFFFFu;
  int is_c = -1;
  uintptr_t proto_ptr = 0;
  unsigned int proto_tt = 0xFFFFFFFFu;
  int maxstack = -1;

  if (!force && !lm_precall_diag_enabled())
    return;

  if (func != NULL) {
    func_tt = (unsigned int)ttype(func);
    if (iscollectable(func) && func->value.gc != NULL) {
      gc_ptr = (uintptr_t)func->value.gc;
      if (lm_precall_ptr_readable((const void*)gc_ptr, sizeof(GCheader)))
        gc_tt = (unsigned int)func->value.gc->gch.tt;
      if (gc_tt == LUA_TFUNCTION &&
          lm_precall_ptr_readable((const void*)&func->value.gc->cl.l, sizeof(LClosure))) {
        LClosure *cl = &func->value.gc->cl.l;
        is_c = cl->isC ? 1 : 0;
        if (!cl->isC) {
          proto_ptr = (uintptr_t)cl->p;
          if (cl->p != NULL && lm_precall_ptr_readable((const void*)proto_ptr, sizeof(Proto))) {
            proto_tt = (unsigned int)cl->p->tt;
            maxstack = (int)cl->p->maxstacksize;
          }
        }
      }
    }
  }

  snprintf(buf, sizeof(buf),
           "[lua51/precall] reason=%s L=%p func=%p tt=%u gc=%p gc_tt=%u isC=%d proto=%p proto_tt=%u maxstack=%d top=%p base=%p ci=%p nres=%d",
           reason ? reason : "unknown",
           (void*)L,
           (void*)func,
           func_tt,
           (void*)gc_ptr,
           gc_tt,
           is_c,
           (void*)proto_ptr,
           proto_tt,
           maxstack,
           (void*)(L ? L->top : NULL),
           (void*)(L ? L->base : NULL),
           (void*)(L ? L->ci : NULL),
           nresults);
  lm_precall_emit(buf);
}

static void lm_precall_log_fault_once (const char *reason,
                                       lua_State *L,
                                       StkId func,
                                       int nresults) {
  int first = (lm_precall_first_fault_logged == 0);
  if (first)
    lm_precall_first_fault_logged = 1;
  lm_precall_log(reason, L, func, nresults, first);
}



#define inc_ci(L) \
  ((L->ci == L->end_ci) ? growCI(L) : \
   (condhardstacktests(luaD_reallocCI(L, L->size_ci)), ++L->ci))


int luaD_precall (lua_State *L, StkId func, int nresults) {
  LClosure *cl;
  ptrdiff_t funcr;
  int do_diag;
  if (!ttisfunction(func)) /* `func' is not a function? */
    func = tryfuncTM(L, func);  /* check the `function' tag method */

  do_diag = lm_precall_diag_enabled();
  if (do_diag)
    lm_precall_log("entry", L, func, nresults, 0);

  if (do_diag) {
    if (!ttisfunction(func)) {
      lm_precall_log_fault_once("func-not-function", L, func, nresults);
      luaG_runerror(L, "corrupt function TValue in luaD_precall");
    }
    if (!iscollectable(func) || func->value.gc == NULL) {
      lm_precall_log_fault_once("func-missing-gc", L, func, nresults);
      luaG_runerror(L, "corrupt closure pointer in luaD_precall");
    }
    if (!lm_precall_ptr_readable((const void*)func->value.gc, sizeof(Closure))) {
      lm_precall_log_fault_once("func-gc-unreadable", L, func, nresults);
      luaG_runerror(L, "unreadable closure pointer in luaD_precall");
    }
    if (func->value.gc->gch.tt != LUA_TFUNCTION) {
      lm_precall_log_fault_once("func-gc-tt-mismatch", L, func, nresults);
      luaG_runerror(L, "function GC header mismatch in luaD_precall");
    }

    funcr = savestack(L, func);
    cl = &clvalue(func)->l;
    if (!lm_precall_ptr_readable((const void*)cl, sizeof(LClosure))) {
      lm_precall_log_fault_once("closure-unreadable", L, func, nresults);
      luaG_runerror(L, "unreadable closure body in luaD_precall");
    }
    if (!cl->isC) {
      Proto *pp = cl->p;
      if (pp == NULL) {
        lm_precall_log_fault_once("proto-null", L, func, nresults);
        luaG_runerror(L, "null proto in luaD_precall");
      }
      if (!lm_precall_ptr_readable((const void*)pp, sizeof(Proto))) {
        lm_precall_log_fault_once("proto-unreadable", L, func, nresults);
        luaG_runerror(L, "unreadable proto in luaD_precall");
      }
      if (pp->tt != LUA_TPROTO) {
        lm_precall_log_fault_once("proto-tt-mismatch", L, func, nresults);
        luaG_runerror(L, "proto type mismatch in luaD_precall");
      }
    }
  }

  funcr = savestack(L, func);
  cl = &clvalue(func)->l;
  L->ci->savedpc = L->savedpc;
  if (!cl->isC) {  /* Lua function? prepare its call */
    CallInfo *ci;
    StkId st, base;
    Proto *p = cl->p;
    luaD_checkstack(L, p->maxstacksize);
    func = restorestack(L, funcr);
    if (!p->is_vararg) {  /* no varargs? */
      base = func + 1;
      if (L->top > base + p->numparams)
        L->top = base + p->numparams;
    }
    else {  /* vararg function */
      int nargs = cast_int(L->top - func) - 1;
      base = adjust_varargs(L, p, nargs);
      func = restorestack(L, funcr);  /* previous call may change the stack */
    }
    ci = inc_ci(L);  /* now `enter' new function */
    ci->func = func;
    L->base = ci->base = base;
    ci->top = L->base + p->maxstacksize;
    lua_assert(ci->top <= L->stack_last);
    L->savedpc = p->code;  /* starting point */
    /*
    ** WoW 66709 (x64) CI taint init -- match Lua-function "clean" path.
    ** IDA: MOV WORD PTR [ci+24h], 0x0001 -> [0]=1, [1]=0
    **      MOV BYTE PTR [ci+28h], 0     -> [4]=0
    ** g_taintHandlerPtr is zeroed -> restricted_action returns 1 (allowed)
    ** regardless of CI taint level; we just need WoW-normal values here.
    */
    memset(ci->_wk_ci_taint, 0, sizeof(ci->_wk_ci_taint));
    ci->_wk_ci_taint[0] = 1;  /* mode (Lua function path) */
    ci->_wk_ci_taint[1] = 0;  /* secret level (not needed for Lua code) */
    ci->_wk_ci_pad[0] = 0;
    ci->_wk_ci_pad[1] = 0;
    ci->tailcalls = 0;
    ci->nresults = nresults;
    for (st = L->top; st < ci->top; st++)
      setnilvalue(st);
    L->top = ci->top;
    if (L->hookmask & LUA_MASKCALL) {
      L->savedpc++;  /* hooks assume 'pc' is already incremented */
      luaD_callhook(L, LUA_HOOKCALL, -1);
      L->savedpc--;  /* correct 'pc' */
    }
    return PCRLUA;
  }
  else {  /* if is a C function, call it */
    CallInfo *ci;
    int n;
    luaD_checkstack(L, LUA_MINSTACK);  /* ensure minimum stack size */
    ci = inc_ci(L);  /* now `enter' new function */
    ci->func = restorestack(L, funcr);
    L->base = ci->base = ci->func + 1;
    ci->top = L->top + LUA_MINSTACK;
    lua_assert(ci->top <= L->stack_last);
    /*
    ** WoW 66709 (x64) CI taint init -- match C-function "clean" path.
    ** IDA: MOV WORD PTR [ci+24h], 0x0100 -> [0]=0, [1]=1
    **      MOV BYTE PTR [ci+28h], 0     -> [4]=0
    */
    memset(ci->_wk_ci_taint, 0, sizeof(ci->_wk_ci_taint));
    ci->_wk_ci_taint[0] = 0;  /* mode (C function path) */
    ci->_wk_ci_taint[1] = 1;  /* secret level = conditional */
    ci->_wk_ci_pad[0] = 0;
    ci->_wk_ci_pad[1] = 0;
    ci->nresults = nresults;
    if (L->hookmask & LUA_MASKCALL)
      luaD_callhook(L, LUA_HOOKCALL, -1);
    lua_unlock(L);
    n = (*curr_func(L)->c.f)(L);  /* do the actual call */
    lua_lock(L);
    if (n < 0)  /* yielding? */
      return PCRYIELD;
    else {
      luaD_poscall(L, L->top - n);
      return PCRC;
    }
  }
}


static StkId callrethooks (lua_State *L, StkId firstResult) {
  ptrdiff_t fr = savestack(L, firstResult);  /* next call may change stack */
  luaD_callhook(L, LUA_HOOKRET, -1);
  if (f_isLua(L->ci)) {  /* Lua function? */
    while ((L->hookmask & LUA_MASKRET) && L->ci->tailcalls--) /* tail calls */
      luaD_callhook(L, LUA_HOOKTAILRET, -1);
  }
  return restorestack(L, fr);
}


int luaD_poscall (lua_State *L, StkId firstResult) {
  StkId res;
  int wanted, i;
  CallInfo *ci;
  if (L->hookmask & LUA_MASKRET)
    firstResult = callrethooks(L, firstResult);
  ci = L->ci--;
  res = ci->func;  /* res == final position of 1st result */
  wanted = ci->nresults;
  L->base = (ci - 1)->base;  /* restore base */
  L->savedpc = (ci - 1)->savedpc;  /* restore savedpc */
  /* move results to correct place */
  for (i = wanted; i != 0 && firstResult < L->top; i--)
    setobjs2s(L, res++, firstResult++);
  while (i-- > 0)
    setnilvalue(res++);
  L->top = res;
  return (wanted - LUA_MULTRET);  /* 0 iff wanted == LUA_MULTRET */
}


/*
** Call a function (C or Lua). The function to be called is at *func.
** The arguments are on the stack, right after the function.
** When returns, all the results are on the stack, starting at the original
** function position.
*/ 
void luaD_call (lua_State *L, StkId func, int nResults) {
  if (++L->nCcalls >= LUAI_MAXCCALLS) {
    if (L->nCcalls == LUAI_MAXCCALLS)
      luaG_runerror(L, "C stack overflow");
    else if (L->nCcalls >= (LUAI_MAXCCALLS + (LUAI_MAXCCALLS>>3)))
      luaD_throw(L, LUA_ERRERR);  /* error while handing stack error */
  }
  if (luaD_precall(L, func, nResults) == PCRLUA)  /* is a Lua function? */
    luaV_execute(L, 1);  /* call it */
  L->nCcalls--;
  luaC_checkGC(L);
}


static void resume (lua_State *L, void *ud) {
  StkId firstArg = cast(StkId, ud);
  CallInfo *ci = L->ci;
  if (L->status == 0) {  /* start coroutine? */
    lua_assert(ci == L->base_ci && firstArg > L->base);
    if (luaD_precall(L, firstArg - 1, LUA_MULTRET) != PCRLUA)
      return;
  }
  else {  /* resuming from previous yield */
    lua_assert(L->status == LUA_YIELD);
    L->status = 0;
    if (!f_isLua(ci)) {  /* `common' yield? */
      /* finish interrupted execution of `OP_CALL' */
      lua_assert(GET_OPCODE(*((ci-1)->savedpc - 1)) == OP_CALL ||
                 GET_OPCODE(*((ci-1)->savedpc - 1)) == OP_TAILCALL);
      if (luaD_poscall(L, firstArg))  /* complete it... */
        L->top = L->ci->top;  /* and correct top if not multiple results */
    }
    else  /* yielded inside a hook: just continue its execution */
      L->base = L->ci->base;
  }
  luaV_execute(L, cast_int(L->ci - L->base_ci));
}


static int resume_error (lua_State *L, const char *msg) {
  L->top = L->ci->base;
  setsvalue2s(L, L->top, luaS_new(L, msg));
  incr_top(L);
  lua_unlock(L);
  return LUA_ERRRUN;
}


LUA_API int lua_resume (lua_State *L, int nargs) {
  int status;
  lua_lock(L);
  if (L->status != LUA_YIELD && (L->status != 0 || L->ci != L->base_ci))
      return resume_error(L, "cannot resume non-suspended coroutine");
  if (L->nCcalls >= LUAI_MAXCCALLS)
    return resume_error(L, "C stack overflow");
  luai_userstateresume(L, nargs);
  lua_assert(L->errfunc == 0);
  L->baseCcalls = ++L->nCcalls;
  status = luaD_rawrunprotected(L, resume, L->top - nargs);
  if (status != 0) {  /* error? */
    L->status = cast_byte(status);  /* mark thread as `dead' */
    luaD_seterrorobj(L, status, L->top);
    L->ci->top = L->top;
  }
  else {
    lua_assert(L->nCcalls == L->baseCcalls);
    status = L->status;
  }
  --L->nCcalls;
  lua_unlock(L);
  return status;
}


LUA_API int lua_yield (lua_State *L, int nresults) {
  luai_userstateyield(L, nresults);
  lua_lock(L);
  if (L->nCcalls > L->baseCcalls)
    luaG_runerror(L, "attempt to yield across metamethod/C-call boundary");
  L->base = L->top - nresults;  /* protect stack slots below */
  L->status = LUA_YIELD;
  lua_unlock(L);
  return -1;
}


int luaD_pcall (lua_State *L, Pfunc func, void *u,
                ptrdiff_t old_top, ptrdiff_t ef) {
  int status;
  unsigned short oldnCcalls = L->nCcalls;
  ptrdiff_t old_ci = saveci(L, L->ci);
  lu_byte old_allowhooks = L->allowhook;
  ptrdiff_t old_errfunc = L->errfunc;
  L->errfunc = ef;
  status = luaD_rawrunprotected(L, func, u);
  if (status != 0) {  /* an error occurred? */
    StkId oldtop = restorestack(L, old_top);
    luaF_close(L, oldtop);  /* close eventual pending closures */
    luaD_seterrorobj(L, status, oldtop);
    L->nCcalls = oldnCcalls;
    L->ci = restoreci(L, old_ci);
    L->base = L->ci->base;
    L->savedpc = L->ci->savedpc;
    L->allowhook = old_allowhooks;
    restore_stack_limit(L);
  }
  L->errfunc = old_errfunc;
  return status;
}



/*
** Execute a protected parser.
*/
struct SParser {  /* data to `f_parser' */
  ZIO *z;
  Mbuffer buff;  /* buffer to be used by the scanner */
  const char *name;
};

static void f_parser (lua_State *L, void *ud) {
  int i;
  Proto *tf;
  Closure *cl;
  struct SParser *p = cast(struct SParser *, ud);
  int c = luaZ_lookahead(p->z);
  luaC_checkGC(L);
  tf = ((c == LUA_SIGNATURE[0]) ? luaU_undump : luaY_parser)(L, p->z,
                                                             &p->buff, p->name);
  cl = luaF_newLclosure(L, tf->nups, hvalue(gt(L)));
  cl->l.p = tf;
  for (i = 0; i < tf->nups; i++)  /* initialize eventual upvalues */
    cl->l.upvals[i] = luaF_newupval(L);
  setclvalue(L, L->top, cl);
  incr_top(L);
}


int luaD_protectedparser (lua_State *L, ZIO *z, const char *name) {
  struct SParser p;
  int status;
  p.z = z; p.name = name;
  luaZ_initbuffer(L, &p.buff);
  status = luaD_pcall(L, f_parser, &p, savestack(L, L->top), L->errfunc);
  luaZ_freebuffer(L, &p.buff);
  return status;
}


