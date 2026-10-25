/* dinkr_stealth.c -- stealth functions, PEB manipulation, user32 resolution */

#include "dinkr_stealth.h"


/* ========================================================================
** PEB module search Ã¢â‚¬â€ case-insensitive name match
** ======================================================================== */

PVOID FindModuleByName(const wchar_t* moduleName) {
    PPEB peb = GET_PEB();
    if (!peb || !peb->Ldr) return NULL;

    PLIST_ENTRY head = &peb->Ldr->InLoadOrderModuleList;
    PLIST_ENTRY current = head->Flink;

    while (current != head) {
        PLDR_DATA_TABLE_ENTRY entry = CONTAINING_RECORD(
            current, LDR_DATA_TABLE_ENTRY, InLoadOrderLinks);

        if (entry->BaseDllName.Buffer) {
            BOOL match = TRUE;
            for (USHORT i = 0; i < entry->BaseDllName.Length / sizeof(wchar_t); i++) {
                wchar_t c1 = entry->BaseDllName.Buffer[i];
                wchar_t c2 = moduleName[i];
                if (c1 >= 'A' && c1 <= 'Z') c1 += 32;
                if (c2 >= 'A' && c2 <= 'Z') c2 += 32;
                if (c1 != c2) { match = FALSE; break; }
                if (c2 == 0) break;
            }
            if (match && moduleName[entry->BaseDllName.Length / sizeof(wchar_t)] == 0) {
                return entry->DllBase;
            }
        }
        current = current->Flink;
    }
    return NULL;
}

/* ========================================================================
** ManualGetProcAddress -- bypass shimmed GetProcAddress by reading EAT directly
**
** apphelp.dll shims GetProcAddress to return trampoline addresses instead
** of real function addresses. Reading the Export Address Table from the
** module's in-memory PE headers gives us the REAL addresses.
** ======================================================================== */

FARPROC ManualGetProcAddress(HMODULE hModule, const char* funcName) {
    if (!hModule || !funcName) return NULL;

    BYTE* base = (BYTE*)hModule;
    PIMAGE_DOS_HEADER dos = (PIMAGE_DOS_HEADER)base;
    if (dos->e_magic != IMAGE_DOS_SIGNATURE) return NULL;

    /* Bounds-check e_lfanew to prevent wild memory access */
    if (dos->e_lfanew < (LONG)sizeof(IMAGE_DOS_HEADER) || dos->e_lfanew > 0x10000)
        return NULL;

    PIMAGE_NT_HEADERS nt = (PIMAGE_NT_HEADERS)(base + dos->e_lfanew);
    if (nt->Signature != IMAGE_NT_SIGNATURE) return NULL;

    DWORD exportRVA = nt->OptionalHeader.DataDirectory[IMAGE_DIRECTORY_ENTRY_EXPORT].VirtualAddress;
    DWORD exportSize = nt->OptionalHeader.DataDirectory[IMAGE_DIRECTORY_ENTRY_EXPORT].Size;
    if (!exportRVA || !exportSize) return NULL;

    PIMAGE_EXPORT_DIRECTORY exports = (PIMAGE_EXPORT_DIRECTORY)(base + exportRVA);
    DWORD* nameRVAs = (DWORD*)(base + exports->AddressOfNames);
    WORD* ordinals = (WORD*)(base + exports->AddressOfNameOrdinals);
    DWORD* funcRVAs = (DWORD*)(base + exports->AddressOfFunctions);

    for (DWORD i = 0; i < exports->NumberOfNames; i++) {
        const char* name = (const char*)(base + nameRVAs[i]);
        if (strcmp(name, funcName) == 0) {
            DWORD funcRVA = funcRVAs[ordinals[i]];

            /* Check for forwarder (RVA points within export directory) */
            if (funcRVA >= exportRVA && funcRVA < exportRVA + exportSize) {
                /* Forwarder string like "win32u.NtUserEnumWindows" */
                const char* fwd = (const char*)(base + funcRVA);
                char dllName[128] = {0};
                const char* dot = strchr(fwd, '.');
                if (!dot) return NULL;
                size_t dllLen = (size_t)(dot - fwd);
                if (dllLen >= sizeof(dllName) - 5) return NULL;
                memcpy(dllName, fwd, dllLen);
                strcat(dllName, ".dll");
                HMODULE hFwd = GetModuleHandleA(dllName);
                if (!hFwd) return NULL;
                return ManualGetProcAddress(hFwd, dot + 1);
            }

            return (FARPROC)(base + funcRVA);
        }
    }
    return NULL;
}

pfnEnumWindows_t              pEnumWindows              = NULL;
pfnSetWindowsHookExA_t        pSetWindowsHookExA        = NULL;
pfnUnhookWindowsHookEx_t      pUnhookWindowsHookEx      = NULL;
pfnCallNextHookEx_t           pCallNextHookEx            = NULL;
pfnPostMessageA_t             pPostMessageA              = NULL;
pfnGetWindowThreadProcessId_t pGetWindowThreadProcessId  = NULL;
pfnGetClassNameA_t            pGetClassNameA             = NULL;
pfnIsWindowVisible_t          pIsWindowVisible           = NULL;
pfnGetWindowLongA_t           pGetWindowLongA            = NULL;
pfnGetForegroundWindow_t      pGetForegroundWindow       = NULL;
pfnGetClientRect_t            pGetClientRect             = NULL;

BOOL ResolveUser32Functions(void) {
    char logBuf[256];
    HMODULE hUser32 = GetModuleHandleA("user32.dll");
    if (!hUser32) {
        DebugLog("[resolve] FATAL: user32.dll not loaded");
        return FALSE;
    }

    int resolved = 0;
    int total = 11;

    #define RESOLVE(var, type, name) do { \
        var = (type)(void*)ManualGetProcAddress(hUser32, name); \
        if (var) { resolved++; } else { \
            snprintf(logBuf, sizeof(logBuf), "[resolve] FAILED: %s", name); \
            DebugLog(logBuf); \
        } \
    } while(0)

    RESOLVE(pEnumWindows,              pfnEnumWindows_t,              "EnumWindows");
    RESOLVE(pSetWindowsHookExA,        pfnSetWindowsHookExA_t,        "SetWindowsHookExA");
    RESOLVE(pUnhookWindowsHookEx,      pfnUnhookWindowsHookEx_t,      "UnhookWindowsHookEx");
    RESOLVE(pCallNextHookEx,           pfnCallNextHookEx_t,           "CallNextHookEx");
    RESOLVE(pPostMessageA,             pfnPostMessageA_t,             "PostMessageA");
    RESOLVE(pGetWindowThreadProcessId, pfnGetWindowThreadProcessId_t, "GetWindowThreadProcessId");
    RESOLVE(pGetClassNameA,            pfnGetClassNameA_t,            "GetClassNameA");
    RESOLVE(pIsWindowVisible,          pfnIsWindowVisible_t,          "IsWindowVisible");
    RESOLVE(pGetWindowLongA,           pfnGetWindowLongA_t,           "GetWindowLongA");
    RESOLVE(pGetForegroundWindow,      pfnGetForegroundWindow_t,      "GetForegroundWindow");
    RESOLVE(pGetClientRect,              pfnGetClientRect_t,              "GetClientRect");

    #undef RESOLVE

    snprintf(logBuf, sizeof(logBuf), "[resolve] user32: %d/%d functions resolved via EAT", resolved, total);
    DebugLog(logBuf);

    return (resolved == total);
}
