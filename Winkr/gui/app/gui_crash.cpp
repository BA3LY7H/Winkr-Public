/* gui_crash.cpp — SEH crash handler + diagnostic report writer */

#include "gui_crash.h"
#include <windows.h>
#include <tlhelp32.h>
#include <cstdio>
#include <cstdarg>

static const char* ExceptionCodeName(DWORD code)
{
    switch (code) {
    case 0xC0000005: return "ACCESS_VIOLATION";
    case 0xC0000008: return "INVALID_HANDLE";
    case 0xC000000D: return "INVALID_PARAMETER";
    case 0xC0000017: return "NO_MEMORY";
    case 0xC000001D: return "ILLEGAL_INSTRUCTION";
    case 0xC0000025: return "NONCONTINUABLE_EXCEPTION";
    case 0xC00000FD: return "STACK_OVERFLOW";
    case 0xC0000094: return "INTEGER_DIVIDE_BY_ZERO";
    case 0xC0000095: return "INTEGER_OVERFLOW";
    case 0xC0000096: return "PRIVILEGED_INSTRUCTION";
    case 0x80000003: return "BREAKPOINT";
    case 0x80000004: return "SINGLE_STEP";
    case 0xC000008C: return "ARRAY_BOUNDS_EXCEEDED";
    case 0xC000008D: return "FLOAT_DENORMAL_OPERAND";
    case 0xC000008E: return "FLOAT_DIVIDE_BY_ZERO";
    case 0xC0000090: return "FLOAT_INVALID_OPERATION";
    case 0xC0000091: return "FLOAT_OVERFLOW";
    case 0xC0000092: return "FLOAT_STACK_CHECK";
    case 0xC0000093: return "FLOAT_UNDERFLOW";
    case 0xE06D7363: return "CPP_EXCEPTION";
    default:         return "UNKNOWN";
    }
}

static void WriteCrashLine(HANDLE hFile, const char* fmt, ...)
{
    char buf[1024];
    va_list ap;
    va_start(ap, fmt);
    int len = vsnprintf(buf, sizeof(buf), fmt, ap);
    va_end(ap);
    if (len > 0) {
        DWORD written;
        WriteFile(hFile, buf, (DWORD)len, &written, NULL);
    }
}

LONG WINAPI CrashHandler(EXCEPTION_POINTERS* ep)
{
    CreateDirectoryA("C:\\mods", NULL);
    HANDLE hFile = CreateFileA("C:\\mods\\dinkr_crash.txt", GENERIC_WRITE,
                               FILE_SHARE_READ, NULL, CREATE_ALWAYS,
                               FILE_ATTRIBUTE_NORMAL, NULL);
    if (hFile == INVALID_HANDLE_VALUE)
        return EXCEPTION_CONTINUE_SEARCH;

    SYSTEMTIME st;
    GetLocalTime(&st);
    DWORD code = ep->ExceptionRecord->ExceptionCode;
    CONTEXT* ctx = ep->ContextRecord;

    WriteCrashLine(hFile,
        "=== DINKR CRASH REPORT ===\r\n"
        "Time: %04d-%02d-%02d %02d:%02d:%02d\r\n"
        "Exception: 0x%08lX (%s)\r\n"
        "Address: 0x%llX\r\n\r\n",
        st.wYear, st.wMonth, st.wDay, st.wHour, st.wMinute, st.wSecond,
        code, ExceptionCodeName(code),
        (unsigned long long)(uintptr_t)ep->ExceptionRecord->ExceptionAddress);

    /* Access violation details */
    if (code == 0xC0000005 && ep->ExceptionRecord->NumberParameters >= 2) {
        const char* op = ep->ExceptionRecord->ExceptionInformation[0] == 0 ? "READ"
                       : ep->ExceptionRecord->ExceptionInformation[0] == 1 ? "WRITE"
                       : "EXECUTE";
        WriteCrashLine(hFile, "Fault: %s of address 0x%llX\r\n\r\n",
                       op, (unsigned long long)ep->ExceptionRecord->ExceptionInformation[1]);
    }

    /* Register dump */
    WriteCrashLine(hFile,
        "Registers:\r\n"
        "  RAX=%016llX  RBX=%016llX  RCX=%016llX  RDX=%016llX\r\n"
        "  RSI=%016llX  RDI=%016llX  RSP=%016llX  RBP=%016llX\r\n"
        "  R8 =%016llX  R9 =%016llX  R10=%016llX  R11=%016llX\r\n"
        "  R12=%016llX  R13=%016llX  R14=%016llX  R15=%016llX\r\n"
        "  RIP=%016llX  EFLAGS=%08lX\r\n\r\n",
        (unsigned long long)ctx->Rax, (unsigned long long)ctx->Rbx,
        (unsigned long long)ctx->Rcx, (unsigned long long)ctx->Rdx,
        (unsigned long long)ctx->Rsi, (unsigned long long)ctx->Rdi,
        (unsigned long long)ctx->Rsp, (unsigned long long)ctx->Rbp,
        (unsigned long long)ctx->R8,  (unsigned long long)ctx->R9,
        (unsigned long long)ctx->R10, (unsigned long long)ctx->R11,
        (unsigned long long)ctx->R12, (unsigned long long)ctx->R13,
        (unsigned long long)ctx->R14, (unsigned long long)ctx->R15,
        (unsigned long long)ctx->Rip, (unsigned long)ctx->EFlags);

    /* Stack trace — walk RSP for return addresses in known modules */
    WriteCrashLine(hFile, "Stack trace:\r\n");
    ULONG_PTR* sp = (ULONG_PTR*)ctx->Rsp;
    int frames = 0;
    for (int i = 0; i < 128 && frames < 20; i++) {
        ULONG_PTR val = 0;
        MEMORY_BASIC_INFORMATION mbi;
        if (!VirtualQuery(&sp[i], &mbi, sizeof(mbi)) ||
            mbi.State != MEM_COMMIT ||
            (mbi.Protect & (PAGE_NOACCESS | PAGE_GUARD)))
            break;
        val = sp[i];
        if (val < 0x10000 || val > 0x00007FFFFFFFFFFF) continue;

        HMODULE hMod = NULL;
        if (GetModuleHandleExA(GET_MODULE_HANDLE_EX_FLAG_FROM_ADDRESS |
                               GET_MODULE_HANDLE_EX_FLAG_UNCHANGED_REFCOUNT,
                               (LPCSTR)val, &hMod)) {
            char modName[MAX_PATH] = {0};
            GetModuleFileNameA(hMod, modName, MAX_PATH);
            /* Strip path, keep filename only */
            char* slash = strrchr(modName, '\\');
            const char* name = slash ? slash + 1 : modName;
            ULONG_PTR base = (ULONG_PTR)hMod;
            WriteCrashLine(hFile, "  [%2d] 0x%llX  %s+0x%llX\r\n",
                           frames, (unsigned long long)val,
                           name, (unsigned long long)(val - base));
            frames++;
        }
    }
    if (frames == 0)
        WriteCrashLine(hFile, "  (no frames recovered)\r\n");

    /* Module list */
    WriteCrashLine(hFile, "\r\nLoaded modules:\r\n");
    HANDLE hSnap = CreateToolhelp32Snapshot(TH32CS_SNAPMODULE, GetCurrentProcessId());
    if (hSnap != INVALID_HANDLE_VALUE) {
        MODULEENTRY32 me;
        me.dwSize = sizeof(me);
        if (Module32First(hSnap, &me)) {
            do {
                WriteCrashLine(hFile, "  0x%llX - 0x%llX  %s\r\n",
                               (unsigned long long)(uintptr_t)me.modBaseAddr,
                               (unsigned long long)((uintptr_t)me.modBaseAddr + me.modBaseSize),
                               me.szModule);
            } while (Module32Next(hSnap, &me));
        }
        CloseHandle(hSnap);
    }

    WriteCrashLine(hFile, "\r\n=== END CRASH REPORT ===\r\n");
    CloseHandle(hFile);

    return EXCEPTION_CONTINUE_SEARCH;
}
