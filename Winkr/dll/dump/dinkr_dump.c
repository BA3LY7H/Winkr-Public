/*
 * dinkr_dump.c — Lightweight dump DLL injected into WoW by dinkr_gui.exe
 *
 * Reads output path from IPC shared memory, dumps the PE image with
 * Eidolon gadget decryption, extracts offsets, dumps loader + warden
 * modules, generates IDA script, then self-destructs.
 *
 * Compiled as pure C with: gcc -Wall -O2 -shared -static -s
 * Ported from DumperOnly/helper_dll.c — stripped of stealth/syscall/VEH.
 */

#include <windows.h>
#include <stdint.h>
#include <psapi.h>
#include <string.h>
#include <stdio.h>
#include <ctype.h>

#include "dump_protocol.h"

/* ------------------------------------------------------------------ */
/*  Constants                                                          */
/* ------------------------------------------------------------------ */

#define MAX_OFFSETS     32000
#define MAX_NAME_LEN    128
#define CHUNK_SIZE_16MB (16 * 1024 * 1024)

#define DECRYPT_GADGET_RVA_RETAIL  0x1E7040
#define DECRYPT_GADGET_RVA_CLASSIC 0x6629E0

/* Consolidated dump chunk header (appended after main PE in dump.bin) */
#define DUMP_CHUNK_MAGIC 0x4B434441  /* "ADCK" */

#ifndef min
#define min(a, b) ((a) < (b) ? (a) : (b))
#endif

/* ------------------------------------------------------------------ */
/*  Types                                                              */
/* ------------------------------------------------------------------ */

typedef enum {
    OFFSET_LUA_FUNCTION,
    OFFSET_BINDING_COMMAND,
    OFFSET_GLOBAL_POINTER,
    OFFSET_STATIC_DATA
} OffsetType;

typedef struct {
    char name[MAX_NAME_LEN];
    uint64_t rva;
    OffsetType type;
} OffsetEntry;

typedef struct {
    uint32_t magic;
    uint32_t type;       /* 0=loader, 1=warden */
    uint64_t dataSize;
    uint64_t runtimeBase;
    char name[32];
} DumpChunkHeader;

typedef UINT64 (__fastcall *DecryptGadgetFunc)(PVOID address);

#define MAX_TLS_CALLBACKS 64

typedef struct {
    PVOID callbacks[MAX_TLS_CALLBACKS];
    int count;
    BOOL initialized;
    PVOID originalCallbackArray;
    DWORD originalCallbackArrayRva;
} TLS_CALLBACK_TRACKER;

/* ------------------------------------------------------------------ */
/*  PEB structures (for IAT reconstruction & module walk)              */
/* ------------------------------------------------------------------ */

typedef struct _PEB_LDR_DATA {
    ULONG Length;
    BOOLEAN Initialized;
    PVOID SsHandle;
    LIST_ENTRY InLoadOrderModuleList;
    LIST_ENTRY InMemoryOrderModuleList;
    LIST_ENTRY InInitializationOrderModuleList;
} PEB_LDR_DATA, *PPEB_LDR_DATA;

typedef struct _UNICODE_STRING_PEB {
    USHORT Length;
    USHORT MaximumLength;
    PWSTR Buffer;
} UNICODE_STRING_PEB, *PUNICODE_STRING_PEB;

typedef struct _LDR_DATA_TABLE_ENTRY {
    LIST_ENTRY InLoadOrderLinks;
    LIST_ENTRY InMemoryOrderLinks;
    LIST_ENTRY InInitializationOrderLinks;
    PVOID DllBase;
    PVOID EntryPoint;
    ULONG SizeOfImage;
    UNICODE_STRING_PEB FullDllName;
    UNICODE_STRING_PEB BaseDllName;
} LDR_DATA_TABLE_ENTRY, *PLDR_DATA_TABLE_ENTRY;

typedef struct _PEB {
    BOOLEAN InheritedAddressSpace;
    BOOLEAN ReadImageFileExecOptions;
    BOOLEAN BeingDebugged;
    union {
        BOOLEAN BitField;
        struct {
            BOOLEAN ImageUsesLargePages : 1;
            BOOLEAN IsProtectedProcess : 1;
            BOOLEAN IsLegacyProcess : 1;
            BOOLEAN IsImageDynamicallyRelocated : 1;
            BOOLEAN SkipPatchingUser32Forwarders : 1;
            BOOLEAN SpareBits : 3;
        };
    };
    HANDLE Mutant;
    PVOID ImageBaseAddress;
    PPEB_LDR_DATA Ldr;
} PEB, *PPEB;

#ifdef _WIN64
#define GET_PEB() ((PPEB)__readgsqword(0x60))
#else
#define GET_PEB() ((PPEB)__readfsdword(0x30))
#endif

/* ------------------------------------------------------------------ */
/*  Module-scope state (single-threaded, no locks needed)              */
/* ------------------------------------------------------------------ */

static HINSTANCE g_hModule = NULL;
static DinkrDumpIPC* g_ipc = NULL;
static HANDLE g_ipcMapping = NULL;
static DecryptGadgetFunc g_decryptGadget = NULL;
static char g_outputDir[MAX_PATH] = {0};
static uint32_t g_dumpChunkCount = 0;

/* ------------------------------------------------------------------ */
/*  Early debug log — writes to C:\mods\ using kernel32 API            */
/*  Works even if CRT has issues; always writes to a known location.   */
/* ------------------------------------------------------------------ */

static void DumpLog(const char* msg) {
    CreateDirectoryA("C:\\mods", NULL);
    HANDLE hFile = CreateFileA("C:\\mods\\dinkr_dump_debug.txt",
                               FILE_APPEND_DATA,
                               FILE_SHARE_READ | FILE_SHARE_WRITE,
                               NULL, OPEN_ALWAYS, FILE_ATTRIBUTE_NORMAL, NULL);
    if (hFile == INVALID_HANDLE_VALUE) return;
    DWORD written;
    WriteFile(hFile, msg, (DWORD)lstrlenA(msg), &written, NULL);
    WriteFile(hFile, "\r\n", 2, &written, NULL);
    CloseHandle(hFile);
}

/* ------------------------------------------------------------------ */
/*  Forced-decrypt VEH infrastructure (ported from DumperOnly)         */
/* ------------------------------------------------------------------ */

typedef struct {
    PVOID targetPage;
    PVOID destBuffer;
    DWORD64 originalRip;
    DWORD64 originalRsp;
    DWORD64 originalRflags;
    HANDLE completionEvent;
    volatile BOOL decrypted;
    volatile BOOL inProgress;
    DWORD pageSize;
} FORCED_DECRYPT_STATE;

static FORCED_DECRYPT_STATE g_forceDecrypt = {0};
static PVOID g_vehHandle = NULL;
static CRITICAL_SECTION g_decryptLock;

static volatile BOOL g_execDecryptInProgress = FALSE;
static volatile PVOID g_execDecryptTarget = NULL;
static volatile PVOID g_execDecryptDest = NULL;
static volatile BOOL g_execDecryptSuccess = FALSE;
static HANDLE g_execDecryptEvent = NULL;
static volatile DWORD g_decryptedPages = 0;

static LONG CALLBACK DecryptCaptureVEH(PEXCEPTION_POINTERS ep) {
    if (!g_execDecryptInProgress) return EXCEPTION_CONTINUE_SEARCH;

    DWORD code = ep->ExceptionRecord->ExceptionCode;
    DWORD64 addr = (DWORD64)ep->ExceptionRecord->ExceptionAddress;
    DWORD64 target = (DWORD64)g_execDecryptTarget;

    if (code == EXCEPTION_SINGLE_STEP) {
        if (addr >= target && addr < target + 4096) {
            memcpy((PVOID)g_execDecryptDest, (PVOID)g_execDecryptTarget, 4096);
            g_execDecryptSuccess = TRUE;
            g_decryptedPages++;
            g_execDecryptInProgress = FALSE;
            if (g_execDecryptEvent) SetEvent(g_execDecryptEvent);

            ep->ContextRecord->Rip = (DWORD64)ExitThread;
            ep->ContextRecord->Rcx = 0;
            return EXCEPTION_CONTINUE_EXECUTION;
        }
    }

    if (code == EXCEPTION_BREAKPOINT) {
        if (addr >= target && addr < target + 4096) {
            memcpy((PVOID)g_execDecryptDest, (PVOID)g_execDecryptTarget, 4096);
            g_execDecryptSuccess = TRUE;
            g_decryptedPages++;
            g_execDecryptInProgress = FALSE;
            if (g_execDecryptEvent) SetEvent(g_execDecryptEvent);
            ep->ContextRecord->Rip = (DWORD64)ExitThread;
            ep->ContextRecord->Rcx = 0;
            return EXCEPTION_CONTINUE_EXECUTION;
        }
    }

    return EXCEPTION_CONTINUE_SEARCH;
}

static BOOL InitForcedDecryption(void) {
    InitializeCriticalSection(&g_decryptLock);

    g_forceDecrypt.completionEvent = CreateEventA(NULL, TRUE, FALSE, NULL);
    if (!g_forceDecrypt.completionEvent) return FALSE;

    g_forceDecrypt.pageSize = 4096;
    g_forceDecrypt.inProgress = FALSE;

    g_vehHandle = AddVectoredExceptionHandler(0, DecryptCaptureVEH);
    if (!g_vehHandle) {
        CloseHandle(g_forceDecrypt.completionEvent);
        return FALSE;
    }

    return TRUE;
}

static void CleanupForcedDecryption(void) {
    if (g_vehHandle) {
        RemoveVectoredExceptionHandler(g_vehHandle);
        g_vehHandle = NULL;
    }
    if (g_forceDecrypt.completionEvent) {
        CloseHandle(g_forceDecrypt.completionEvent);
        g_forceDecrypt.completionEvent = NULL;
    }
    DeleteCriticalSection(&g_decryptLock);
}

/* Check if a memory range is readable (safe to dereference) */
static BOOL IsPageReadable(LPCVOID addr, SIZE_T size) {
    MEMORY_BASIC_INFORMATION mbi;
    if (VirtualQuery(addr, &mbi, sizeof(mbi)) == 0) return FALSE;
    if (mbi.State != MEM_COMMIT) return FALSE;
    DWORD prot = mbi.Protect & 0xFF;
    return (prot == PAGE_READONLY || prot == PAGE_READWRITE ||
            prot == PAGE_EXECUTE_READ || prot == PAGE_EXECUTE_READWRITE ||
            prot == PAGE_EXECUTE_WRITECOPY || prot == PAGE_WRITECOPY);
}
static int g_isClassic = 0;

/* ------------------------------------------------------------------ */
/*  IPC helpers                                                        */
/* ------------------------------------------------------------------ */

static void IpcSetStatus(DumpStatus st, const char* msg) {
    if (!g_ipc) return;
    InterlockedExchange(&g_ipc->status, (LONG)st);
    if (msg) {
        strncpy(g_ipc->status_msg, msg, sizeof(g_ipc->status_msg) - 1);
        g_ipc->status_msg[sizeof(g_ipc->status_msg) - 1] = '\0';
    }
}

static void IpcSetProgress(uint32_t pct) {
    if (g_ipc) g_ipc->progress_pct = pct;
}

static void IpcFail(const char* err) {
    if (!g_ipc) return;
    InterlockedExchange(&g_ipc->status, (LONG)DUMP_STATUS_FAILED);
    strncpy(g_ipc->error_msg, err, sizeof(g_ipc->error_msg) - 1);
    g_ipc->error_msg[sizeof(g_ipc->error_msg) - 1] = '\0';
    strncpy(g_ipc->status_msg, "FAILED", sizeof(g_ipc->status_msg) - 1);
}

/* ------------------------------------------------------------------ */
/*  Output path helpers                                                */
/* ------------------------------------------------------------------ */

static void BuildOutputPath(const char* filename, char* fullPath, SIZE_T sz) {
    if (g_outputDir[0]) {
        int n = snprintf(fullPath, sz, "%s\\%s", g_outputDir, filename);
        if (n < 0 || (SIZE_T)n >= sz)
            fullPath[sz - 1] = '\0';
    } else {
        strncpy(fullPath, filename, sz - 1);
        fullPath[sz - 1] = '\0';
    }
}

/* ------------------------------------------------------------------ */
/*  Debug log (file-based, to output dir)                              */
/* ------------------------------------------------------------------ */

static void DebugLog(const char* msg) {
    char fullPath[MAX_PATH];
    BuildOutputPath("dinkr_dump_log.txt", fullPath, sizeof(fullPath));

    HANDLE hFile = CreateFileA(fullPath, FILE_APPEND_DATA,
                               FILE_SHARE_READ | FILE_SHARE_WRITE,
                               NULL, OPEN_ALWAYS, FILE_ATTRIBUTE_NORMAL, NULL);
    if (hFile != INVALID_HANDLE_VALUE) {
        DWORD written;
        WriteFile(hFile, msg, (DWORD)strlen(msg), &written, NULL);
        WriteFile(hFile, "\r\n", 2, &written, NULL);
        CloseHandle(hFile);
    }
}

/* ------------------------------------------------------------------ */
/*  Eidolon gadget decrypt                                             */
/* ------------------------------------------------------------------ */

static BOOL DecryptPageWithGadget(PVOID srcPage, PVOID dstBuffer) {
    if (!g_decryptGadget) return FALSE;

    UINT64* src = (UINT64*)srcPage;
    UINT64* dst = (UINT64*)dstBuffer;

    for (int i = 0; i < 512; i++) {
        dst[i] = g_decryptGadget(&src[i]);
    }
    return TRUE;
}

static BOOL CopyPageAfterTouch(PVOID srcPage, PVOID dstBuffer) {
    if (!g_decryptGadget) {
        memcpy(dstBuffer, srcPage, 4096);
        return TRUE;
    }

    UINT64* src = (UINT64*)srcPage;
    UINT64* dst = (UINT64*)dstBuffer;

    for (int i = 0; i < 512; i++) {
        dst[i] = g_decryptGadget(&src[i]);
    }
    return TRUE;
}

/* ------------------------------------------------------------------ */
/*  PEB module walk                                                    */
/* ------------------------------------------------------------------ */

static PVOID FindModuleByName(const wchar_t* moduleName) {
    PPEB peb = GET_PEB();
    if (!peb || !peb->Ldr) return NULL;

    PLIST_ENTRY head = &peb->Ldr->InLoadOrderModuleList;
    PLIST_ENTRY current = head->Flink;

    while (current != head) {
        PLDR_DATA_TABLE_ENTRY entry =
            CONTAINING_RECORD(current, LDR_DATA_TABLE_ENTRY, InLoadOrderLinks);

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

/* ------------------------------------------------------------------ */
/*  TLS callback reconstruction                                        */
/* ------------------------------------------------------------------ */

static TLS_CALLBACK_TRACKER g_tlsTracker = {0};

static BOOL IsTlsCallbackTracked(PVOID callback) {
    if (!callback) return TRUE;
    for (int i = 0; i < g_tlsTracker.count; i++) {
        if (g_tlsTracker.callbacks[i] == callback) return TRUE;
    }
    return FALSE;
}

static void TrackTlsCallback(PVOID callback) {
    if (!callback || IsTlsCallbackTracked(callback)) return;
    if (g_tlsTracker.count >= MAX_TLS_CALLBACKS) return;
    g_tlsTracker.callbacks[g_tlsTracker.count++] = callback;
}

static void ScanAndTrackTlsCallbacks(PVOID imageBase) {
    PIMAGE_DOS_HEADER pDos = (PIMAGE_DOS_HEADER)imageBase;
    if (pDos->e_magic != IMAGE_DOS_SIGNATURE) return;

    PIMAGE_NT_HEADERS pNt = (PIMAGE_NT_HEADERS)((LPBYTE)imageBase + pDos->e_lfanew);
    if (pNt->Signature != IMAGE_NT_SIGNATURE) return;

    DWORD tlsRva = pNt->OptionalHeader.DataDirectory[IMAGE_DIRECTORY_ENTRY_TLS].VirtualAddress;
    if (!tlsRva) return;

    PIMAGE_TLS_DIRECTORY pTls = (PIMAGE_TLS_DIRECTORY)((LPBYTE)imageBase + tlsRva);
    if (!pTls->AddressOfCallBacks) return;

    g_tlsTracker.originalCallbackArray = (PVOID)pTls->AddressOfCallBacks;
    DWORD_PTR imageStart = (DWORD_PTR)imageBase;
    g_tlsTracker.originalCallbackArrayRva =
        (DWORD)((DWORD_PTR)pTls->AddressOfCallBacks - imageStart);

    PVOID* callbackArray = (PVOID*)pTls->AddressOfCallBacks;
    for (int i = 0; i < MAX_TLS_CALLBACKS; i++) {
        PVOID cb = NULL;
        memcpy(&cb, &callbackArray[i], sizeof(PVOID));
        if (!cb) break;
        TrackTlsCallback(cb);
    }
    g_tlsTracker.initialized = TRUE;
}

static void ReconstructTlsCallbacks(PVOID imageBase, PVOID dumpBuffer, SIZE_T imageSize) {
    PIMAGE_DOS_HEADER pDumpDos = (PIMAGE_DOS_HEADER)dumpBuffer;
    PIMAGE_NT_HEADERS pDumpNt = (PIMAGE_NT_HEADERS)((LPBYTE)dumpBuffer + pDumpDos->e_lfanew);

    DWORD tlsRva = pDumpNt->OptionalHeader.DataDirectory[IMAGE_DIRECTORY_ENTRY_TLS].VirtualAddress;
    if (!tlsRva) return;

    PIMAGE_TLS_DIRECTORY pDumpTls = (PIMAGE_TLS_DIRECTORY)((LPBYTE)dumpBuffer + tlsRva);
    PIMAGE_TLS_DIRECTORY pOrigTls = (PIMAGE_TLS_DIRECTORY)((LPBYTE)imageBase + tlsRva);

    memcpy(pDumpTls, pOrigTls, sizeof(IMAGE_TLS_DIRECTORY));

    if (g_tlsTracker.count > 0 && g_tlsTracker.originalCallbackArrayRva > 0) {
        DWORD_PTR callbackRva = g_tlsTracker.originalCallbackArrayRva;
        if (callbackRva < imageSize) {
            PVOID* dumpCallbacks = (PVOID*)((LPBYTE)dumpBuffer + callbackRva);
            for (int i = 0; i < g_tlsTracker.count && i < MAX_TLS_CALLBACKS; i++) {
                dumpCallbacks[i] = g_tlsTracker.callbacks[i];
            }
            if (g_tlsTracker.count < MAX_TLS_CALLBACKS) {
                dumpCallbacks[g_tlsTracker.count] = NULL;
            }
            return;
        }
    }

    if (pOrigTls->AddressOfCallBacks) {
        DWORD_PTR imageStart = (DWORD_PTR)imageBase;
        DWORD_PTR callbackAddr = (DWORD_PTR)pOrigTls->AddressOfCallBacks;

        if (callbackAddr >= imageStart && callbackAddr < imageStart + imageSize) {
            DWORD_PTR callbackRva = callbackAddr - imageStart;
            PVOID* origCallbacks = (PVOID*)pOrigTls->AddressOfCallBacks;
            PVOID* dumpCallbacks = (PVOID*)((LPBYTE)dumpBuffer + callbackRva);

            for (int i = 0; i < 32; i++) {
                PVOID cb = NULL;
                memcpy(&cb, &origCallbacks[i], sizeof(PVOID));
                dumpCallbacks[i] = cb;
                if (!cb) break;
            }
        }
    }
}

/* ------------------------------------------------------------------ */
/*  IAT reconstruction (PEB walk)                                      */
/* ------------------------------------------------------------------ */

static BOOL ReconstructIAT(PVOID imageBase, PVOID dumpBuffer, SIZE_T imageSize) {
    PIMAGE_DOS_HEADER pDos = (PIMAGE_DOS_HEADER)imageBase;
    if (pDos->e_magic != IMAGE_DOS_SIGNATURE) return FALSE;

    PIMAGE_NT_HEADERS pNt = (PIMAGE_NT_HEADERS)((LPBYTE)imageBase + pDos->e_lfanew);
    if (pNt->Signature != IMAGE_NT_SIGNATURE) return FALSE;

    DWORD importRva = pNt->OptionalHeader.DataDirectory[IMAGE_DIRECTORY_ENTRY_IMPORT].VirtualAddress;
    if (!importRva) return FALSE;

    PIMAGE_IMPORT_DESCRIPTOR pImport = (PIMAGE_IMPORT_DESCRIPTOR)((LPBYTE)imageBase + importRva);
    IMAGE_IMPORT_DESCRIPTOR importDesc;
    int dllCount = 0, funcCount = 0;

    while (TRUE) {
        memcpy(&importDesc, pImport, sizeof(IMAGE_IMPORT_DESCRIPTOR));
        if (!importDesc.Name) break;

        char dllName[256] = {0};
        char* dllNamePtr = (char*)((LPBYTE)imageBase + importDesc.Name);
        memcpy(dllName, dllNamePtr, sizeof(dllName) - 1);

        /* Resolve via PEB loader list */
        HMODULE hModule = NULL;
        PPEB peb = GET_PEB();
        if (peb && peb->Ldr) {
            PLIST_ENTRY entry = peb->Ldr->InLoadOrderModuleList.Flink;
            while (entry != &peb->Ldr->InLoadOrderModuleList) {
                PLDR_DATA_TABLE_ENTRY ldrEntry =
                    CONTAINING_RECORD(entry, LDR_DATA_TABLE_ENTRY, InLoadOrderLinks);
                if (ldrEntry->BaseDllName.Buffer) {
                    char entryName[256] = {0};
                    WideCharToMultiByte(CP_ACP, 0, ldrEntry->BaseDllName.Buffer,
                                       ldrEntry->BaseDllName.Length / sizeof(WCHAR),
                                       entryName, sizeof(entryName) - 1, NULL, NULL);
                    if (_stricmp(entryName, dllName) == 0) {
                        hModule = (HMODULE)ldrEntry->DllBase;
                        break;
                    }
                }
                entry = entry->Flink;
            }
        }

        if (!hModule) { pImport++; continue; }
        dllCount++;

        if (importDesc.OriginalFirstThunk) {
            PIMAGE_THUNK_DATA pOrigThunk =
                (PIMAGE_THUNK_DATA)((LPBYTE)imageBase + importDesc.OriginalFirstThunk);
            PIMAGE_THUNK_DATA pDumpThunk =
                (PIMAGE_THUNK_DATA)((LPBYTE)dumpBuffer + importDesc.FirstThunk);

            IMAGE_THUNK_DATA thunk;
            int idx = 0;

            while (idx < 10000) {
                memcpy(&thunk, &pOrigThunk[idx], sizeof(IMAGE_THUNK_DATA));
                if (!thunk.u1.AddressOfData) break;

                FARPROC proc = NULL;

                if (thunk.u1.Ordinal & IMAGE_ORDINAL_FLAG) {
                    WORD ordinal = (WORD)(thunk.u1.Ordinal & 0xFFFF);
                    proc = GetProcAddress(hModule, (LPCSTR)(ULONG_PTR)ordinal);
                } else {
                    DWORD_PTR hintNameRva = thunk.u1.AddressOfData;
                    if (hintNameRva < imageSize) {
                        PIMAGE_IMPORT_BY_NAME pName =
                            (PIMAGE_IMPORT_BY_NAME)((LPBYTE)imageBase + hintNameRva);
                        char funcName[256] = {0};
                        memcpy(funcName, pName->Name, sizeof(funcName) - 1);
                        if (funcName[0]) {
                            proc = GetProcAddress(hModule, funcName);
                        }
                    }
                }

                if (proc) {
                    pDumpThunk[idx].u1.Function = (ULONG_PTR)proc;
                    funcCount++;
                }
                idx++;
            }
        }
        pImport++;
    }

    return (dllCount > 0);
}

/* ------------------------------------------------------------------ */
/*  Offset extraction helpers                                          */
/* ------------------------------------------------------------------ */

static int IsValidFuncName(const char* str, int maxLen) {
    if (!str || (!isalpha((unsigned char)str[0]) && str[0] != '_')) return 0;
    int len = 0;
    for (int i = 0; i < maxLen && str[i]; i++) {
        char c = str[i];
        if (!isalnum((unsigned char)c) && c != '_') return 0;
        len++;
    }
    return (len >= 2 && len < MAX_NAME_LEN - 1) ? len : 0;
}

static int IsValidCodeRVA(uint64_t rva, uint64_t textStart, uint64_t textEnd, uint8_t* mem) {
    if (rva < textStart || rva >= textEnd) return 0;
    uint8_t* p = mem + rva;
    if (p[0] == 0x55) return 1;
    if (p[0] == 0x53 || p[0] == 0x56 || p[0] == 0x57) return 1;
    if (p[0] == 0x41 && (p[1] >= 0x54 && p[1] <= 0x57)) return 1;
    if (p[0] == 0x40 && (p[1] >= 0x50 && p[1] <= 0x57)) return 1;
    if (p[0] == 0x48 && p[1] == 0x89) return 1;
    if (p[0] == 0x48 && p[1] == 0x83 && p[2] == 0xEC) return 1;
    if (p[0] == 0x48 && p[1] == 0x8B) return 1;
    if (p[0] == 0x4C && p[1] == 0x89) return 1;
    if (p[0] == 0x4C && p[1] == 0x8B) return 1;
    if (p[0] == 0x33 || p[0] == 0x31) return 1;
    if (p[0] == 0xB8 || p[0] == 0xE9 || p[0] == 0xE8) return 1;
    if (p[0] == 0x44 || p[0] == 0x45 || p[0] == 0x49) return 1;
    return 0;
}

static void AddOffset(OffsetEntry* offsets, int* count, int max,
                      const char* name, int nameLen, uint64_t rva, OffsetType type) {
    if (!offsets || *count >= max) return;

    for (int i = 0; i < *count; i++) {
        if (strncmp(offsets[i].name, name, nameLen) == 0 && offsets[i].name[nameLen] == 0)
            return;
    }

    strncpy(offsets[*count].name, name, nameLen);
    offsets[*count].name[nameLen] = 0;
    offsets[*count].rva = rva;
    offsets[*count].type = type;
    (*count)++;
}

/* ------------------------------------------------------------------ */
/*  Pattern scanning                                                   */
/* ------------------------------------------------------------------ */

static int64_t ScanPattern(uint8_t* buffer, DWORD bufferSize, const char* pattern) {
    uint8_t patBytes[64];
    uint8_t patMask[64];
    int patLen = 0;

    const char* p = pattern;
    while (*p && patLen < 64) {
        while (*p == ' ') p++;
        if (!*p) break;

        if (*p == '?') {
            patBytes[patLen] = 0;
            patMask[patLen] = 0;
            patLen++;
            p++;
            if (*p == '?') p++;
        } else {
            unsigned int b = 0;
            if (sscanf(p, "%02X", &b) == 1) {
                patBytes[patLen] = (uint8_t)b;
                patMask[patLen] = 1;
                patLen++;
            }
            p += 2;
        }
    }

    if (patLen == 0) return -1;

    for (DWORD i = 0; i + patLen <= bufferSize; i++) {
        BOOL match = TRUE;
        for (int j = 0; j < patLen; j++) {
            if (patMask[j] && buffer[i + j] != patBytes[j]) {
                match = FALSE;
                break;
            }
        }
        if (match) return (int64_t)i;
    }
    return -1;
}

static uint64_t ResolveCallTarget(uint8_t* buffer, DWORD bufferSize, uint64_t callOffset) {
    if (callOffset + 5 > bufferSize) return 0;
    if (buffer[callOffset] != 0xE8) return 0;
    int32_t rel = *(int32_t*)(buffer + callOffset + 1);
    int64_t target = (int64_t)callOffset + 5 + rel;
    if (target < 0 || (uint64_t)target >= bufferSize) return 0;
    return (uint64_t)target;
}

static uint64_t ResolveRipRelative(uint8_t* buffer, DWORD bufferSize,
                                   uint64_t instrOffset, int dispOff, int instrLen) {
    if (instrOffset + instrLen > bufferSize) return 0;
    int32_t disp = *(int32_t*)(buffer + instrOffset + dispOff);
    int64_t target = (int64_t)instrOffset + instrLen + disp;
    if (target < 0 || (uint64_t)target >= bufferSize) return 0;
    return (uint64_t)target;
}

/* ------------------------------------------------------------------ */
/*  Lua function extraction                                            */
/* ------------------------------------------------------------------ */

static void ExtractLuaFunctions(PVOID moduleBase, uint8_t* dumpBuffer, DWORD imageSize,
                                uint64_t textStart, uint64_t textEnd,
                                uint64_t rdataStart, uint64_t rdataEnd,
                                uint64_t dataStart, uint64_t dataEnd,
                                OffsetEntry* offsets, int* count, int max) {
    uint64_t imageBaseVA = (uint64_t)moduleBase;

    /* Scan .rdata for (string_ptr, code_ptr) pairs */
    for (uint64_t addr = rdataStart; addr < rdataEnd - 16 && addr < imageSize - 16; addr += 8) {
        uint64_t ptr1 = *(uint64_t*)(dumpBuffer + addr);
        uint64_t ptr2 = *(uint64_t*)(dumpBuffer + addr + 8);

        if (ptr1 < imageBaseVA || ptr2 < imageBaseVA) continue;

        uint64_t strRva = ptr1 - imageBaseVA;
        uint64_t codeRva = ptr2 - imageBaseVA;

        if (strRva < rdataStart || strRva >= rdataEnd) continue;
        if (codeRva < textStart || codeRva >= textEnd) continue;
        if (strRva >= imageSize || codeRva >= imageSize) continue;

        char* str = (char*)(dumpBuffer + strRva);
        int nameLen = IsValidFuncName(str, 100);
        if (!nameLen) continue;

        if (IsValidCodeRVA(codeRva, textStart, textEnd, dumpBuffer)) {
            AddOffset(offsets, count, max, str, nameLen, codeRva, OFFSET_LUA_FUNCTION);
        }
    }

    /* Scan .data for binding commands */
    for (uint64_t addr = dataStart; addr < dataEnd - 16 && addr < imageSize - 16; addr += 8) {
        uint64_t ptr1 = *(uint64_t*)(dumpBuffer + addr);
        uint64_t ptr2 = *(uint64_t*)(dumpBuffer + addr + 8);

        if (ptr1 < imageBaseVA || ptr2 < imageBaseVA) continue;

        uint64_t strRva = ptr1 - imageBaseVA;
        uint64_t codeRva = ptr2 - imageBaseVA;

        if (strRva < rdataStart || strRva >= rdataEnd) continue;
        if (codeRva < textStart || codeRva >= textEnd) continue;
        if (strRva >= imageSize || codeRva >= imageSize) continue;

        char* str = (char*)(dumpBuffer + strRva);
        int nameLen = IsValidFuncName(str, 100);
        if (!nameLen) continue;

        AddOffset(offsets, count, max, str, nameLen, codeRva, OFFSET_BINDING_COMMAND);
    }

    /* Scan .text for LEA-relative references to .rdata strings */
    for (uint64_t addr = textStart; addr < textEnd - 7 && addr < imageSize - 7; addr++) {
        uint8_t* p = dumpBuffer + addr;

        if ((p[0] == 0x48 || p[0] == 0x4C) && p[1] == 0x8D) {
            uint8_t modrm = p[2];
            if ((modrm & 0xC7) == 0x05) {
                int32_t disp = *(int32_t*)(p + 3);
                uint64_t targetRva = addr + 7 + disp;

                if (targetRva >= rdataStart && targetRva < rdataEnd && targetRva < imageSize) {
                    char* str = (char*)(dumpBuffer + targetRva);
                    int nameLen = IsValidFuncName(str, 100);

                    if (nameLen) {
                        uint64_t funcStart = 0;
                        for (int back = 0; back < 256; back++) {
                            uint64_t check = addr - back;
                            if (check <= textStart) break;

                            if (back > 0) {
                                uint8_t prev = dumpBuffer[check - 1];
                                if (prev == 0xCC || prev == 0xC3 || prev == 0xC2) {
                                    if (IsValidCodeRVA(check, textStart, textEnd, dumpBuffer)) {
                                        funcStart = check;
                                        break;
                                    }
                                }
                            }
                        }

                        if (funcStart) {
                            AddOffset(offsets, count, max, str, nameLen, funcStart, OFFSET_LUA_FUNCTION);
                        }
                    }
                }
            }
        }
    }
}

/* ------------------------------------------------------------------ */
/*  Global offset extraction                                           */
/* ------------------------------------------------------------------ */

static void ExtractGlobalOffsets(PVOID moduleBase, uint8_t* dumpBuffer, DWORD imageSize,
                                 uint64_t textStart, uint64_t textEnd,
                                 uint64_t dataStart, uint64_t dataEnd,
                                 OffsetEntry* offsets, int* count, int max) {
    uint64_t imageBaseVA = (uint64_t)moduleBase;

    typedef struct {
        uint64_t rva;
        int refCount;
        int accessOffsets[8];
        int accessCount;
    } GlobalCandidate;

    #define MAX_CANDIDATES 1024
    GlobalCandidate* candidates = VirtualAlloc(NULL, MAX_CANDIDATES * sizeof(GlobalCandidate),
                                               MEM_COMMIT | MEM_RESERVE, PAGE_READWRITE);
    if (!candidates) return;
    int candidateCount = 0;

    for (uint64_t addr = textStart; addr < textEnd - 14 && addr < imageSize - 14; addr++) {
        uint8_t* p = dumpBuffer + addr;

        if (p[0] == 0x48 && p[1] == 0x8B && p[2] == 0x05) {
            int32_t disp = *(int32_t*)(p + 3);
            uint64_t globalRva = addr + 7 + disp;

            if (globalRva >= dataStart && globalRva < dataEnd && globalRva < imageSize) {
                int accessOffset = -1;

                if (p[7] == 0x48 && p[8] == 0x8B) {
                    uint8_t modrm = p[9];
                    if ((modrm & 0xC0) == 0x40)
                        accessOffset = (int8_t)p[10];
                    else if ((modrm & 0xC0) == 0x80)
                        accessOffset = *(int32_t*)(p + 10);
                    else if ((modrm & 0xC0) == 0x00)
                        accessOffset = 0;
                }

                int found = -1;
                for (int i = 0; i < candidateCount; i++) {
                    if (candidates[i].rva == globalRva) { found = i; break; }
                }

                if (found >= 0) {
                    candidates[found].refCount++;
                    if (accessOffset >= 0 && candidates[found].accessCount < 8) {
                        int alreadyHas = 0;
                        for (int j = 0; j < candidates[found].accessCount; j++) {
                            if (candidates[found].accessOffsets[j] == accessOffset) {
                                alreadyHas = 1; break;
                            }
                        }
                        if (!alreadyHas) {
                            candidates[found].accessOffsets[candidates[found].accessCount++] = accessOffset;
                        }
                    }
                } else if (candidateCount < MAX_CANDIDATES) {
                    candidates[candidateCount].rva = globalRva;
                    candidates[candidateCount].refCount = 1;
                    candidates[candidateCount].accessCount = 0;
                    if (accessOffset >= 0) {
                        candidates[candidateCount].accessOffsets[0] = accessOffset;
                        candidates[candidateCount].accessCount = 1;
                    }
                    candidateCount++;
                }
            }
        }

        if ((p[0] == 0x48 || p[0] == 0x4C) && p[1] == 0x8D && (p[2] & 0xC7) == 0x05) {
            int32_t disp = *(int32_t*)(p + 3);
            uint64_t targetRva = addr + 7 + disp;

            if (targetRva >= dataStart && targetRva < dataEnd && targetRva < imageSize) {
                int found = -1;
                for (int i = 0; i < candidateCount; i++) {
                    if (candidates[i].rva == targetRva) { found = i; break; }
                }

                if (found >= 0) {
                    candidates[found].refCount++;
                } else if (candidateCount < MAX_CANDIDATES) {
                    candidates[candidateCount].rva = targetRva;
                    candidates[candidateCount].refCount = 1;
                    candidates[candidateCount].accessCount = 0;
                    candidateCount++;
                }
            }
        }
    }

    int globals = 0;
    for (int i = 0; i < candidateCount; i++) {
        if (candidates[i].refCount >= 5) {
            uint64_t rva = candidates[i].rva;
            uint64_t value = 0;
            if (rva + 8 <= imageSize) {
                value = *(uint64_t*)(dumpBuffer + rva);
            }

            char name[64];
            if (candidates[i].accessCount > 0 &&
                (candidates[i].accessOffsets[0] == 0x8 || candidates[i].accessOffsets[0] == 0x10)) {
                snprintf(name, sizeof(name), "g_Manager_%llX", (unsigned long long)rva);
            } else if (value >= imageBaseVA && value < imageBaseVA + imageSize) {
                snprintf(name, sizeof(name), "g_Ptr_%llX", (unsigned long long)rva);
            } else {
                snprintf(name, sizeof(name), "g_Data_%llX", (unsigned long long)rva);
            }

            AddOffset(offsets, count, max, name, (int)strlen(name), rva, OFFSET_GLOBAL_POINTER);
            globals++;
        }
    }

    const char* knownPatterns[] = {"Camera", "Player", "Object", "Entity", "Unit", "Spell", NULL};

    for (uint64_t addr = dataStart; addr < dataEnd - 8 && addr < imageSize - 8; addr += 8) {
        uint64_t ptr = *(uint64_t*)(dumpBuffer + addr);

        if (ptr >= imageBaseVA && ptr < imageBaseVA + imageSize) {
            uint64_t targetRva = ptr - imageBaseVA;

            if (targetRva >= 0x335A000 && targetRva < 0x3C8CAF8 && targetRva < imageSize) {
                char* str = (char*)(dumpBuffer + targetRva);

                for (int k = 0; knownPatterns[k]; k++) {
                    if (strncmp(str, knownPatterns[k], strlen(knownPatterns[k])) == 0) {
                        int nameLen = IsValidFuncName(str, 64);
                        if (nameLen) {
                            char fullName[80];
                            snprintf(fullName, sizeof(fullName), "g_%s", str);
                            AddOffset(offsets, count, max, fullName,
                                      (int)strlen(fullName), addr, OFFSET_STATIC_DATA);
                            globals++;
                        }
                        break;
                    }
                }
            }
        }
    }

    VirtualFree(candidates, 0, MEM_RELEASE);
}

/* ------------------------------------------------------------------ */
/*  Critical offset extraction (sig scan + RVA fallback)               */
/* ------------------------------------------------------------------ */

static void ExtractCriticalOffsets(uint8_t* dumpBuffer, DWORD imageSize,
                                   OffsetEntry* offsets, int* count, int max) {
    DebugLog("Extracting critical offsets (sig scan + fallback)...");

    /* lua_loadbuffer */
    {
        uint64_t rva = 0;
        int64_t match = ScanPattern(dumpBuffer, imageSize,
            "E8 ?? ?? ?? ?? 48 8B 4C 24 ?? 8B D8 E8 ?? ?? ?? ?? 85 DB 75");
        if (match >= 0)
            rva = ResolveCallTarget(dumpBuffer, imageSize, (uint64_t)match);
        if (!rva) rva = 0x33B1900;
        AddOffset(offsets, count, max, "lua_loadbuffer", 14, rva, OFFSET_LUA_FUNCTION);
    }

    /* lua_DoString */
    {
        int64_t match = ScanPattern(dumpBuffer, imageSize,
            "48 89 54 24 10 55 56 57 41 55 41 57 48 8D AC 24");
        uint64_t rva = (match >= 0) ? (uint64_t)match : 0x4EB310;
        AddOffset(offsets, count, max, "lua_DoString", 12, rva, OFFSET_LUA_FUNCTION);
    }

    /* g_LuaState */
    {
        uint64_t rva = 0;
        int64_t match = ScanPattern(dumpBuffer, imageSize,
            "4C 39 3D ?? ?? ?? ?? 0F 84 ?? ?? ?? ?? FF 15");
        if (match >= 0)
            rva = ResolveRipRelative(dumpBuffer, imageSize, (uint64_t)match, 3, 7);
        if (!rva) rva = 0x5A4C288;
        AddOffset(offsets, count, max, "g_LuaState", 10, rva, OFFSET_GLOBAL_POINTER);
    }

    /* g_ObjManager */
    {
        uint64_t rva = 0;
        int64_t match = ScanPattern(dumpBuffer, imageSize,
            "48 8B 15 ?? ?? ?? ?? 4C 89 70");
        if (match >= 0)
            rva = ResolveRipRelative(dumpBuffer, imageSize, (uint64_t)match, 3, 7);
        if (!rva) rva = 0x5C4E7F0;
        AddOffset(offsets, count, max, "g_ObjManager", 12, rva, OFFSET_GLOBAL_POINTER);
    }

    /* lua_pcall */
    {
        uint64_t rva = 0;
        int64_t match = ScanPattern(dumpBuffer, imageSize,
            "E8 ?? ?? ?? ?? 48 89 1D ?? ?? ?? ?? 48 8B CF");
        if (match >= 0)
            rva = ResolveCallTarget(dumpBuffer, imageSize, (uint64_t)match);
        if (!rva) rva = 0x323D0C0;
        AddOffset(offsets, count, max, "lua_pcall", 9, rva, OFFSET_LUA_FUNCTION);
    }

    /* lua_getfield — no unique sig, direct RVA */
    AddOffset(offsets, count, max, "lua_getfield", 12, 0x323D5C0, OFFSET_LUA_FUNCTION);

    /* ScriptHandler_GetGlobal */
    AddOffset(offsets, count, max, "ScriptHandler_GetGlobal", 23, 0x5049B0, OFFSET_LUA_FUNCTION);

    DebugLog("Critical offsets extracted");
}

/* ------------------------------------------------------------------ */
/*  Write offsets file                                                 */
/* ------------------------------------------------------------------ */

static void WriteOffsetsFile(PVOID moduleBase, OffsetEntry* offsets, int count) {
    char fullPath[MAX_PATH];
    BuildOutputPath("wow_offsets.txt", fullPath, sizeof(fullPath));

    HANDLE hFile = CreateFileA(fullPath, GENERIC_WRITE, 0, NULL,
                               CREATE_ALWAYS, FILE_ATTRIBUTE_NORMAL, NULL);
    if (hFile == INVALID_HANDLE_VALUE) return;

    char header[512];
    int headerLen = snprintf(header, sizeof(header),
        "// WoW Offsets - Auto-extracted by dinkr_dump.dll\r\n"
        "// Image Base: 0x%llX\r\n"
        "// Total: %d offsets\r\n\r\n",
        (unsigned long long)moduleBase, count);

    DWORD written;
    WriteFile(hFile, header, headerLen, &written, NULL);

    const char* sections[] = {
        "\r\n// === LUA FUNCTIONS ===\r\n\r\n",
        "\r\n// === BINDING COMMANDS ===\r\n\r\n",
        "\r\n// === GLOBAL POINTERS ===\r\n\r\n",
        "\r\n// === STATIC DATA ===\r\n\r\n"
    };

    for (int t = 0; t < 4; t++) {
        WriteFile(hFile, sections[t], (DWORD)strlen(sections[t]), &written, NULL);
        for (int i = 0; i < count; i++) {
            if (offsets[i].type == t) {
                char line[256];
                int lineLen = snprintf(line, sizeof(line), "%s = 0x%llX\r\n",
                                       offsets[i].name, (unsigned long long)offsets[i].rva);
                WriteFile(hFile, line, lineLen, &written, NULL);
            }
        }
    }

    CloseHandle(hFile);
    DebugLog("Offsets file written");
}

/* ------------------------------------------------------------------ */
/*  Append chunk to consolidated dump.bin                              */
/* ------------------------------------------------------------------ */

static BOOL AppendDumpChunk(const char* chunkName, uint32_t chunkType,
                            PVOID data, DWORD dataSize, uint64_t runtimeBase) {
    char dumpPath[MAX_PATH];
    BuildOutputPath("dump.bin", dumpPath, sizeof(dumpPath));

    HANDLE hFile = CreateFileA(dumpPath, FILE_APPEND_DATA, FILE_SHARE_READ, NULL,
                               OPEN_ALWAYS, FILE_ATTRIBUTE_NORMAL, NULL);
    if (hFile == INVALID_HANDLE_VALUE) return FALSE;

    DumpChunkHeader hdr;
    hdr.magic = DUMP_CHUNK_MAGIC;
    hdr.type = chunkType;
    hdr.dataSize = dataSize;
    hdr.runtimeBase = runtimeBase;
    memset(hdr.name, 0, sizeof(hdr.name));
    strncpy(hdr.name, chunkName, sizeof(hdr.name) - 1);

    DWORD written;
    WriteFile(hFile, &hdr, sizeof(DumpChunkHeader), &written, NULL);

    /* Chunked writes for reliability */
    DWORD remaining = dataSize;
    LPBYTE ptr = (LPBYTE)data;
    while (remaining > 0) {
        DWORD toWrite = (remaining > CHUNK_SIZE_16MB) ? CHUNK_SIZE_16MB : remaining;
        DWORD w = 0;
        if (!WriteFile(hFile, ptr, toWrite, &w, NULL) || w == 0) break;
        ptr += w;
        remaining -= w;
    }

    g_dumpChunkCount++;
    CloseHandle(hFile);
    return TRUE;
}

/* ------------------------------------------------------------------ */
/*  Wow_loader.dll dump                                                */
/* ------------------------------------------------------------------ */

static DecryptGadgetFunc FindLoaderDecryptGadget(PVOID loaderBase, DWORD imageSize) {
    LPBYTE p = (LPBYTE)loaderBase;

    for (DWORD offset = 0x1000; offset < imageSize - 4; offset++) {
        if (p[offset] == 0x48 && p[offset+1] == 0x8B &&
            p[offset+2] == 0x01 && p[offset+3] == 0xC3) {
            if (offset > 0 && (p[offset-1] == 0xCC || p[offset-1] == 0xC3 || p[offset-1] == 0x90)) {
                return (DecryptGadgetFunc)(p + offset);
            }
        }
    }

    for (DWORD offset = 0x1000; offset < imageSize - 8; offset++) {
        if (p[offset] == 0x48 && p[offset+1] == 0x8B && p[offset+2] == 0x01 &&
            p[offset+3] == 0x48 && p[offset+4] == 0x31 && p[offset+7] == 0xC3) {
            return (DecryptGadgetFunc)(p + offset);
        }
    }
    return NULL;
}

static int IsLoaderFuncPrologue(uint8_t* p) {
    if (p[0] == 0x55) return 1;
    if (p[0] == 0x53 || p[0] == 0x56 || p[0] == 0x57) return 1;
    if (p[0] == 0x41 && (p[1] >= 0x54 && p[1] <= 0x57)) return 1;
    if (p[0] == 0x40 && (p[1] >= 0x53 && p[1] <= 0x57)) return 1;
    if (p[0] == 0x48 && p[1] == 0x89) return 1;
    if (p[0] == 0x48 && p[1] == 0x83 && p[2] == 0xEC) return 1;
    if (p[0] == 0x48 && p[1] == 0x81 && p[2] == 0xEC) return 1;
    if (p[0] == 0x4C && p[1] == 0x89) return 1;
    if (p[0] == 0x4C && p[1] == 0x8B) return 1;
    return 0;
}

static void DumpLoaderExports(PVOID loaderBase, PIMAGE_NT_HEADERS pNt) {
    DWORD exportRva = pNt->OptionalHeader.DataDirectory[IMAGE_DIRECTORY_ENTRY_EXPORT].VirtualAddress;
    DWORD exportSize = pNt->OptionalHeader.DataDirectory[IMAGE_DIRECTORY_ENTRY_EXPORT].Size;

    if (!exportRva || !exportSize) return;

    PIMAGE_EXPORT_DIRECTORY pExport = (PIMAGE_EXPORT_DIRECTORY)((LPBYTE)loaderBase + exportRva);
    DWORD* nameRvas = (DWORD*)((LPBYTE)loaderBase + pExport->AddressOfNames);
    DWORD* funcRvas = (DWORD*)((LPBYTE)loaderBase + pExport->AddressOfFunctions);
    WORD* ordinals = (WORD*)((LPBYTE)loaderBase + pExport->AddressOfNameOrdinals);

    char fullPath[MAX_PATH];
    BuildOutputPath(g_isClassic ? "wowclassic_loader_exports.txt" : "wow_loader_exports.txt",
                    fullPath, sizeof(fullPath));
    HANDLE hFile = CreateFileA(fullPath, GENERIC_WRITE, 0, NULL,
                               CREATE_ALWAYS, FILE_ATTRIBUTE_NORMAL, NULL);
    if (hFile == INVALID_HANDLE_VALUE) return;

    char header[128];
    const char* loaderDllName = g_isClassic ? "WowClassic_loader.dll" : "Wow_loader.dll";
    int headerLen = snprintf(header, sizeof(header),
        "// %s Exports\r\n// Base: 0x%p\r\n// Count: %lu\r\n\r\n",
        loaderDllName, loaderBase, pExport->NumberOfNames);
    DWORD written;
    WriteFile(hFile, header, headerLen, &written, NULL);

    for (DWORD i = 0; i < pExport->NumberOfNames && i < 1000; i++) {
        char* funcName = (char*)((LPBYTE)loaderBase + nameRvas[i]);
        DWORD funcRva = funcRvas[ordinals[i]];

        char line[256];
        int lineLen = snprintf(line, sizeof(line), "%s = 0x%lX\r\n", funcName, funcRva);
        WriteFile(hFile, line, lineLen, &written, NULL);
    }

    CloseHandle(hFile);
}

static void ExtractLoaderFunctions(uint8_t* dumpBuffer, DWORD imageSize,
                                   PIMAGE_NT_HEADERS pNt, PVOID loaderBase) {
    uint64_t textStart = 0, textEnd = 0;
    PIMAGE_SECTION_HEADER pSections = IMAGE_FIRST_SECTION(pNt);

    for (WORD i = 0; i < pNt->FileHeader.NumberOfSections; i++) {
        char secName[9] = {0};
        memcpy(secName, pSections[i].Name, 8);
        if (strcmp(secName, ".text") == 0) {
            textStart = pSections[i].VirtualAddress;
            textEnd = textStart + pSections[i].Misc.VirtualSize;
            break;
        }
    }

    if (!textStart || !textEnd) return;

    char funcPath[MAX_PATH];
    BuildOutputPath(g_isClassic ? "wowclassic_loader_functions.txt" : "wow_loader_functions.txt",
                    funcPath, sizeof(funcPath));
    HANDLE hFile = CreateFileA(funcPath, GENERIC_WRITE, 0, NULL,
                               CREATE_ALWAYS, FILE_ATTRIBUTE_NORMAL, NULL);
    if (hFile == INVALID_HANDLE_VALUE) return;

    DWORD written;
    int funcCount = 0;

    char header[512];
    const char* loaderDllName2 = g_isClassic ? "WowClassic_loader.dll" : "Wow_loader.dll";
    int headerLen = snprintf(header, sizeof(header),
        "// %s Internal Functions\r\n"
        "// Base: 0x%p\r\n"
        "// .text: 0x%llX - 0x%llX\r\n"
        "// Auto-extracted with forced decryption\r\n\r\n"
        "// === EXPORTS ===\r\n"
        "eidolon_run = 0x3B91D0\r\n"
        "eidolon_run_real = 0x3B91E0\r\n"
        "g_warden_aegis_crash_callback = 0x641BC8\r\n\r\n"
        "// === CRYPTO CONSTANTS ===\r\n"
        "eidolon_key1 = 0xFD07B4FF3A00D412\r\n"
        "eidolon_key2 = 0x028BF84B00C5FF2B\r\n\r\n"
        "// === INTERNAL FUNCTIONS ===\r\n",
        loaderDllName2, loaderBase, (unsigned long long)textStart, (unsigned long long)textEnd);
    WriteFile(hFile, header, headerLen, &written, NULL);

    for (uint64_t addr = textStart + 1; addr < textEnd - 16 && addr < imageSize - 16; addr++) {
        uint8_t prev = dumpBuffer[addr - 1];
        if (prev == 0xCC || prev == 0xC3) {
            uint8_t* p = dumpBuffer + addr;
            if (IsLoaderFuncPrologue(p)) {
                char line[64];
                int lineLen = snprintf(line, sizeof(line), "sub_%llX = 0x%llX\r\n",
                                       (unsigned long long)addr, (unsigned long long)addr);
                WriteFile(hFile, line, lineLen, &written, NULL);
                funcCount++;
            }
        }
    }

    CloseHandle(hFile);
}

static void ExtractLoaderCrypto(uint8_t* dumpBuffer, DWORD imageSize) {
    char cryptoPath[MAX_PATH];
    BuildOutputPath(g_isClassic ? "wowclassic_loader_crypto.txt" : "wow_loader_crypto.txt",
                    cryptoPath, sizeof(cryptoPath));
    HANDLE hFile = CreateFileA(cryptoPath, GENERIC_WRITE, 0, NULL,
                               CREATE_ALWAYS, FILE_ATTRIBUTE_NORMAL, NULL);
    if (hFile == INVALID_HANDLE_VALUE) return;

    DWORD written;
    char header[] = "// Wow_loader.dll Crypto Analysis\r\n"
                    "// Auto-extracted encryption keys and constants\r\n\r\n";
    if (g_isClassic) {
        char classicHeader[] = "// WowClassic_loader.dll Crypto Analysis\r\n"
                               "// Auto-extracted encryption keys and constants\r\n\r\n";
        WriteFile(hFile, classicHeader, sizeof(classicHeader) - 1, &written, NULL);
    } else {
        WriteFile(hFile, header, sizeof(header) - 1, &written, NULL);
    }

    uint64_t eidolonRunReal = 0x3B91E0;
    if (eidolonRunReal + 64 < imageSize) {
        char section[] = "// === EIDOLON_RUN CONSTANTS ===\r\n";
        WriteFile(hFile, section, sizeof(section) - 1, &written, NULL);

        uint8_t* p = dumpBuffer + eidolonRunReal;
        int keyCount = 0;

        for (int i = 0; i < 200 && keyCount < 10; i++) {
            if (p[i] == 0x48 && (p[i+1] == 0xBE || p[i+1] == 0xBF || p[i+1] == 0xB8)) {
                uint64_t key = *(uint64_t*)(p + i + 2);
                if (key > 0x1000000000000000ULL) {
                    char line[128];
                    int lineLen = snprintf(line, sizeof(line),
                        "key_%d = 0x%016llX  // at offset +0x%X\r\n",
                        keyCount, (unsigned long long)key, i);
                    WriteFile(hFile, line, lineLen, &written, NULL);
                    keyCount++;
                }
                i += 9;
            }
        }
    }

    char cryptoSection[] = "\r\n// === CRYPTO ALGORITHM SIGNATURES ===\r\n";
    WriteFile(hFile, cryptoSection, sizeof(cryptoSection) - 1, &written, NULL);

    uint8_t aesBox[] = {0x63, 0x7C, 0x77, 0x7B};
    uint8_t sha256Init[] = {0x67, 0xE6, 0x09, 0x6A};

    for (DWORD i = 0; i < imageSize - 4; i++) {
        if (memcmp(dumpBuffer + i, aesBox, 4) == 0) {
            char line[64];
            int lineLen = snprintf(line, sizeof(line), "AES_SBOX = 0x%lX\r\n", i);
            WriteFile(hFile, line, lineLen, &written, NULL);
            break;
        }
    }

    for (DWORD i = 0; i < imageSize - 4; i++) {
        if (memcmp(dumpBuffer + i, sha256Init, 4) == 0) {
            char line[64];
            int lineLen = snprintf(line, sizeof(line), "SHA256_INIT = 0x%lX\r\n", i);
            WriteFile(hFile, line, lineLen, &written, NULL);
            break;
        }
    }

    CloseHandle(hFile);
}

static void DumpWowLoader(void) {
    PVOID loaderBase = NULL;

    if (g_isClassic) {
        loaderBase = FindModuleByName(L"WowClassic_loader.dll");
    } else {
        loaderBase = FindModuleByName(L"Wow_loader.dll");
        if (!loaderBase)
            loaderBase = FindModuleByName(L"WowT_loader.dll");
        if (!loaderBase)
            loaderBase = FindModuleByName(L"WowB_loader.dll");
    }
    if (!loaderBase) return;

    const char* loaderLabel = g_isClassic ? "WowClassic_loader.dll" : "Wow_loader.dll";
    char statusMsg[64];
    snprintf(statusMsg, sizeof(statusMsg), "Dumping %s...", loaderLabel);
    IpcSetStatus(DUMP_STATUS_EXTRACTING, statusMsg);

    PIMAGE_DOS_HEADER pDos = (PIMAGE_DOS_HEADER)loaderBase;
    if (pDos->e_magic != IMAGE_DOS_SIGNATURE) return;

    PIMAGE_NT_HEADERS pNt = (PIMAGE_NT_HEADERS)((LPBYTE)loaderBase + pDos->e_lfanew);
    if (pNt->Signature != IMAGE_NT_SIGNATURE) return;

    DWORD imageSize = pNt->OptionalHeader.SizeOfImage;

    DecryptGadgetFunc loaderGadget = FindLoaderDecryptGadget(loaderBase, imageSize);
    DecryptGadgetFunc useGadget = loaderGadget ? loaderGadget : g_decryptGadget;

    PVOID dumpBuffer = VirtualAlloc(NULL, imageSize, MEM_COMMIT | MEM_RESERVE, PAGE_READWRITE);
    if (!dumpBuffer) return;

    memcpy(dumpBuffer, loaderBase, pNt->OptionalHeader.SizeOfHeaders);

    PIMAGE_SECTION_HEADER pSections = IMAGE_FIRST_SECTION(pNt);
    DWORD pageSize = 4096;

    for (WORD i = 0; i < pNt->FileHeader.NumberOfSections; i++) {
        PIMAGE_SECTION_HEADER pSec = &pSections[i];
        char secName[9] = {0};
        memcpy(secName, pSec->Name, 8);

        DWORD secRVA = pSec->VirtualAddress;
        DWORD secSize = pSec->Misc.VirtualSize;
        if (secSize == 0) secSize = pSec->SizeOfRawData;
        if (secRVA + secSize > imageSize) continue;

        BOOL isCodeSection = (pSec->Characteristics & IMAGE_SCN_CNT_CODE) ||
                             (secName[0] == '.' && secName[1] == 't' && secName[2] == 'e');

        for (DWORD offset = 0; offset < secSize; offset += pageSize) {
            DWORD copySize = (offset + pageSize > secSize) ? (secSize - offset) : pageSize;
            PVOID srcPage = (LPBYTE)loaderBase + secRVA + offset;
            PVOID dstPage = (LPBYTE)dumpBuffer + secRVA + offset;

            MEMORY_BASIC_INFORMATION mbi;
            if (VirtualQuery(srcPage, &mbi, sizeof(mbi)) == 0) continue;

            BOOL decrypted = FALSE;

            if (mbi.Protect == PAGE_NOACCESS || mbi.Protect == 0) {
                if (isCodeSection && useGadget && copySize == pageSize) {
                    DWORD oldProt;
                    if (VirtualProtect(srcPage, copySize, PAGE_EXECUTE_READ, &oldProt)) {
                        UINT64* src = (UINT64*)srcPage;
                        UINT64* dst = (UINT64*)dstPage;
                        for (int q = 0; q < 512; q++) {
                            dst[q] = useGadget(&src[q]);
                        }
                        VirtualProtect(srcPage, copySize, oldProt, &oldProt);
                        decrypted = TRUE;
                    }
                }
                if (!decrypted) {
                    DWORD oldProt;
                    if (VirtualProtect(srcPage, copySize, PAGE_READONLY, &oldProt)) {
                        memcpy(dstPage, srcPage, copySize);
                        VirtualProtect(srcPage, copySize, oldProt, &oldProt);
                    }
                }
            } else if (!(mbi.Protect & PAGE_GUARD)) {
                if (isCodeSection && useGadget && copySize == pageSize) {
                    UINT64* src = (UINT64*)srcPage;
                    UINT64* dst = (UINT64*)dstPage;
                    for (int q = 0; q < 512; q++) {
                        dst[q] = useGadget(&src[q]);
                    }
                } else {
                    memcpy(dstPage, srcPage, copySize);
                }
            }
        }
    }

    /* Fix section raw pointers for IDA */
    PIMAGE_DOS_HEADER pDumpDos = (PIMAGE_DOS_HEADER)dumpBuffer;
    PIMAGE_NT_HEADERS pDumpNt = (PIMAGE_NT_HEADERS)((LPBYTE)dumpBuffer + pDumpDos->e_lfanew);
    PIMAGE_SECTION_HEADER pDumpSections = IMAGE_FIRST_SECTION(pDumpNt);

    for (WORD i = 0; i < pDumpNt->FileHeader.NumberOfSections; i++) {
        pDumpSections[i].PointerToRawData = pDumpSections[i].VirtualAddress;
        pDumpSections[i].SizeOfRawData = pDumpSections[i].Misc.VirtualSize;
    }
    pDumpNt->OptionalHeader.FileAlignment = pDumpNt->OptionalHeader.SectionAlignment;

    AppendDumpChunk(g_isClassic ? "wowclassic_loader" : "wow_loader",
                    0, dumpBuffer, imageSize,
                    (uint64_t)(uintptr_t)loaderBase);

    DumpLoaderExports(loaderBase, pNt);
    ExtractLoaderFunctions(dumpBuffer, imageSize, pNt, loaderBase);
    ExtractLoaderCrypto(dumpBuffer, imageSize);

    VirtualFree(dumpBuffer, 0, MEM_RELEASE);
    DebugLog("Loader dump complete");
}

/* ------------------------------------------------------------------ */
/*  Warden module scan (single pass)                                   */
/* ------------------------------------------------------------------ */

#define MAX_LOGGED_MODULES 32
static PVOID g_loggedModules[MAX_LOGGED_MODULES] = {0};
static int g_loggedModuleCount = 0;

static BOOL IsAddressInKnownModule(PVOID addr) {
    PPEB peb = GET_PEB();
    if (!peb || !peb->Ldr) return FALSE;

    PLIST_ENTRY head = &peb->Ldr->InLoadOrderModuleList;
    PLIST_ENTRY current = head->Flink;

    while (current != head) {
        PLDR_DATA_TABLE_ENTRY entry =
            CONTAINING_RECORD(current, LDR_DATA_TABLE_ENTRY, InLoadOrderLinks);
        if (entry->DllBase) {
            DWORD_PTR moduleStart = (DWORD_PTR)entry->DllBase;
            DWORD_PTR moduleEnd = moduleStart + entry->SizeOfImage;
            DWORD_PTR checkAddr = (DWORD_PTR)addr;
            if (checkAddr >= moduleStart && checkAddr < moduleEnd) return TRUE;
        }
        current = current->Flink;
    }
    return FALSE;
}

static BOOL IsNewExecutableMemory(PVOID base, SIZE_T size) {
    if (!base || size < 1024) return FALSE;

    MEMORY_BASIC_INFORMATION mbi;
    if (VirtualQuery(base, &mbi, sizeof(mbi)) == 0) return FALSE;
    if (mbi.State != MEM_COMMIT) return FALSE;

    BOOL isExecutable = (mbi.Protect == PAGE_EXECUTE_READ ||
                         mbi.Protect == PAGE_EXECUTE_READWRITE ||
                         mbi.Protect == PAGE_EXECUTE);
    if (!isExecutable) return FALSE;
    if (mbi.Type != MEM_PRIVATE) return FALSE;
    if (IsAddressInKnownModule(base)) return FALSE;

    return TRUE;
}

static BOOL IsModuleLogged(PVOID moduleBase) {
    for (int i = 0; i < g_loggedModuleCount; i++) {
        if (g_loggedModules[i] == moduleBase) return TRUE;
    }
    return FALSE;
}

static int ScanAndDumpWardenModules(void) {
    IpcSetStatus(DUMP_STATUS_EXTRACTING, "Scanning for Warden modules...");

    SYSTEM_INFO si;
    GetSystemInfo(&si);

    PVOID minAddr = si.lpMinimumApplicationAddress;
    PVOID maxAddr = si.lpMaximumApplicationAddress;

    int newModulesFound = 0;
    MEMORY_BASIC_INFORMATION mbi;
    PVOID currentAddr = minAddr;

    while (currentAddr < maxAddr) {
        if (VirtualQuery(currentAddr, &mbi, sizeof(mbi)) == 0) break;

        if (IsNewExecutableMemory(mbi.BaseAddress, mbi.RegionSize)) {
            if (!IsModuleLogged(mbi.BaseAddress) && g_loggedModuleCount < MAX_LOGGED_MODULES) {
                int moduleIndex = g_loggedModuleCount;
                g_loggedModules[g_loggedModuleCount++] = mbi.BaseAddress;

                SIZE_T moduleSize = mbi.RegionSize;

                PVOID dumpBuf = VirtualAlloc(NULL, moduleSize,
                                             MEM_COMMIT | MEM_RESERVE, PAGE_READWRITE);
                if (dumpBuf) {
                    memcpy(dumpBuf, mbi.BaseAddress, moduleSize);

                    char chunkName[48];
                    snprintf(chunkName, sizeof(chunkName), "warden_module_%d", moduleIndex);
                    AppendDumpChunk(chunkName, 1, dumpBuf, (DWORD)moduleSize,
                                   (uint64_t)(uintptr_t)mbi.BaseAddress);

                    /* Append info to offsets file */
                    char offsetsPath[MAX_PATH];
                    BuildOutputPath("wow_offsets.txt", offsetsPath, sizeof(offsetsPath));
                    HANDLE hFile = CreateFileA(offsetsPath, FILE_APPEND_DATA,
                                              FILE_SHARE_READ, NULL,
                                              OPEN_ALWAYS, FILE_ATTRIBUTE_NORMAL, NULL);
                    if (hFile != INVALID_HANDLE_VALUE) {
                        uint8_t* data = (uint8_t*)dumpBuf;
                        int beefCount = 0, fnvCount = 0, syscallCount = 0;

                        for (SIZE_T j = 0; j + 2 < moduleSize; j++) {
                            if (*(uint16_t*)(data + j) == 0xBEEF) beefCount++;
                        }
                        for (SIZE_T j = 0; j + 4 < moduleSize; j++) {
                            if (*(uint32_t*)(data + j) == 0x811C9DC5) fnvCount++;
                        }
                        for (SIZE_T j = 0; j + 11 < moduleSize; j++) {
                            if (data[j] == 0x4C && data[j+1] == 0x8B && data[j+2] == 0xD1 &&
                                data[j+3] == 0xB8 && data[j+8] == 0x0F && data[j+9] == 0x05 &&
                                data[j+10] == 0xC3) {
                                syscallCount++;
                            }
                        }

                        char info[512];
                        int len = snprintf(info, sizeof(info),
                            "\r\n// === WARDEN MODULE %d ===\r\n"
                            "warden_module_%d_base = 0x%p\r\n"
                            "warden_module_%d_size = 0x%llX\r\n"
                            "warden_module_%d_beef_markers = %d\r\n"
                            "warden_module_%d_fnv_constants = %d\r\n"
                            "warden_module_%d_syscall_stubs = %d\r\n",
                            moduleIndex,
                            moduleIndex, mbi.BaseAddress,
                            moduleIndex, (unsigned long long)moduleSize,
                            moduleIndex, beefCount,
                            moduleIndex, fnvCount,
                            moduleIndex, syscallCount);

                        DWORD written = 0;
                        WriteFile(hFile, info, len, &written, NULL);
                        CloseHandle(hFile);
                    }

                    VirtualFree(dumpBuf, 0, MEM_RELEASE);
                }
                newModulesFound++;
            }
        }
        currentAddr = (PVOID)((ULONG_PTR)mbi.BaseAddress + mbi.RegionSize);
        if ((ULONG_PTR)currentAddr <= (ULONG_PTR)mbi.BaseAddress) break;
    }

    return newModulesFound;
}

/* ------------------------------------------------------------------ */
/*  IDA script generation                                              */
/* ------------------------------------------------------------------ */

static void GenerateIDAScript(void) {
    char scriptPath[MAX_PATH];
    BuildOutputPath("dump_segments.py", scriptPath, sizeof(scriptPath));

    FILE* fp = fopen(scriptPath, "w");
    if (!fp) return;

    fprintf(fp, "# dump_segments.py - Auto-generated by dinkr_dump.dll\n");
    fprintf(fp, "# Run in IDA: File > Script file > dump_segments.py\n");
    fprintf(fp, "import ida_segment\n");
    fprintf(fp, "import ida_bytes\n");
    fprintf(fp, "import idautils\n");
    fprintf(fp, "import idc\n");
    fprintf(fp, "import struct\n");
    fprintf(fp, "import os\n");
    fprintf(fp, "\n");
    fprintf(fp, "CHUNK_MAGIC = 0x4B434441  # \"ADCK\"\n");
    fprintf(fp, "HEADER_SIZE = 56  # 4+4+8+8+32 bytes\n");
    fprintf(fp, "\n");
    fprintf(fp, "def load_segments():\n");
    fprintf(fp, "    input_path = idc.get_input_file_path()\n");
    fprintf(fp, "    if not input_path or not os.path.exists(input_path):\n");
    fprintf(fp, "        input_path = idc.get_root_filename()\n");
    fprintf(fp, "        if not input_path or not os.path.exists(input_path):\n");
    fprintf(fp, "            print(\"[!] Cannot find dump.bin - place script next to it\")\n");
    fprintf(fp, "            return\n");
    fprintf(fp, "\n");
    fprintf(fp, "    with open(input_path, \"rb\") as f:\n");
    fprintf(fp, "        f.seek(0, 2)\n");
    fprintf(fp, "        file_size = f.tell()\n");
    fprintf(fp, "\n");
    fprintf(fp, "        f.seek(0x3C)\n");
    fprintf(fp, "        e_lfanew = struct.unpack(\"<I\", f.read(4))[0]\n");
    fprintf(fp, "        f.seek(e_lfanew + 0x18 + 0x38)\n");
    fprintf(fp, "        main_pe_size = struct.unpack(\"<I\", f.read(4))[0]\n");
    fprintf(fp, "\n");
    fprintf(fp, "        offset = main_pe_size\n");
    fprintf(fp, "        chunk_idx = 0\n");
    fprintf(fp, "\n");
    fprintf(fp, "        while offset + HEADER_SIZE <= file_size:\n");
    fprintf(fp, "            f.seek(offset)\n");
    fprintf(fp, "            hdr = f.read(HEADER_SIZE)\n");
    fprintf(fp, "            if len(hdr) < HEADER_SIZE:\n");
    fprintf(fp, "                break\n");
    fprintf(fp, "\n");
    fprintf(fp, "            magic, ctype = struct.unpack_from(\"<II\", hdr, 0)\n");
    fprintf(fp, "            data_size, runtime_base = struct.unpack_from(\"<QQ\", hdr, 8)\n");
    fprintf(fp, "            name = hdr[24:56].split(b\"\\x00\")[0].decode(\"ascii\", errors=\"replace\")\n");
    fprintf(fp, "\n");
    fprintf(fp, "            if magic != CHUNK_MAGIC:\n");
    fprintf(fp, "                print(f\"[!] Bad magic at offset 0x{offset:X}, stopping\")\n");
    fprintf(fp, "                break\n");
    fprintf(fp, "\n");
    fprintf(fp, "            data_offset = offset + HEADER_SIZE\n");
    fprintf(fp, "\n");
    fprintf(fp, "            if ctype == 0:\n");
    fprintf(fp, "                load_loader_pe(f, data_offset, data_size, runtime_base, name)\n");
    fprintf(fp, "            else:\n");
    fprintf(fp, "                load_warden_module(f, data_offset, data_size, runtime_base, name, chunk_idx)\n");
    fprintf(fp, "\n");
    fprintf(fp, "            offset = data_offset + data_size\n");
    fprintf(fp, "            chunk_idx += 1\n");
    fprintf(fp, "\n");
    fprintf(fp, "    print(\"[+] Done loading segments\")\n");
    fprintf(fp, "\n\n");
    fprintf(fp, "def load_loader_pe(f, data_offset, data_size, runtime_base, name):\n");
    fprintf(fp, "    f.seek(data_offset)\n");
    fprintf(fp, "    pe_data = f.read(min(data_size, 0x1000))\n");
    fprintf(fp, "    if len(pe_data) < 0x40:\n");
    fprintf(fp, "        return\n");
    fprintf(fp, "    e_magic = struct.unpack_from(\"<H\", pe_data, 0)[0]\n");
    fprintf(fp, "    if e_magic != 0x5A4D:\n");
    fprintf(fp, "        return\n");
    fprintf(fp, "    e_lfanew = struct.unpack_from(\"<I\", pe_data, 0x3C)[0]\n");
    fprintf(fp, "    if e_lfanew + 0x18 + 0x70 > len(pe_data):\n");
    fprintf(fp, "        return\n");
    fprintf(fp, "    num_sections = struct.unpack_from(\"<H\", pe_data, e_lfanew + 6)[0]\n");
    fprintf(fp, "    opt_hdr_size = struct.unpack_from(\"<H\", pe_data, e_lfanew + 0x14)[0]\n");
    fprintf(fp, "    sec_table_offset = e_lfanew + 0x18 + opt_hdr_size\n");
    fprintf(fp, "    print(f\"[+] Loading loader PE '{name}' @ 0x{runtime_base:X} ({num_sections} sections)\")\n");
    fprintf(fp, "    for i in range(num_sections):\n");
    fprintf(fp, "        sec_off = sec_table_offset + i * 40\n");
    fprintf(fp, "        if sec_off + 40 > len(pe_data):\n");
    fprintf(fp, "            break\n");
    fprintf(fp, "        sec_name = pe_data[sec_off:sec_off+8].split(b\"\\x00\")[0].decode(\"ascii\", errors=\"replace\")\n");
    fprintf(fp, "        vsize = struct.unpack_from(\"<I\", pe_data, sec_off + 8)[0]\n");
    fprintf(fp, "        va = struct.unpack_from(\"<I\", pe_data, sec_off + 12)[0]\n");
    fprintf(fp, "        raw_size = struct.unpack_from(\"<I\", pe_data, sec_off + 16)[0]\n");
    fprintf(fp, "        characteristics = struct.unpack_from(\"<I\", pe_data, sec_off + 36)[0]\n");
    fprintf(fp, "        if vsize == 0: vsize = raw_size\n");
    fprintf(fp, "        if vsize == 0: continue\n");
    fprintf(fp, "        seg_start = runtime_base + va\n");
    fprintf(fp, "        seg_end = seg_start + vsize\n");
    fprintf(fp, "        seg_name = f\"ldr{sec_name}\"\n");
    fprintf(fp, "        if characteristics & 0x20: seg_class = \"CODE\"\n");
    fprintf(fp, "        elif characteristics & 0x40:\n");
    fprintf(fp, "            seg_class = \"DATA\" if characteristics & 0x80000000 else \"CONST\"\n");
    fprintf(fp, "        else: seg_class = \"DATA\"\n");
    fprintf(fp, "        if not ida_segment.add_segm(0, seg_start, seg_end, seg_name, seg_class):\n");
    fprintf(fp, "            continue\n");
    fprintf(fp, "        seg = ida_segment.getseg(seg_start)\n");
    fprintf(fp, "        if seg:\n");
    fprintf(fp, "            seg.bitness = 2\n");
    fprintf(fp, "            seg.perm = 0\n");
    fprintf(fp, "            if characteristics & 0x40000000: seg.perm |= 4\n");
    fprintf(fp, "            if characteristics & 0x80000000: seg.perm |= 2\n");
    fprintf(fp, "            if characteristics & 0x20000000: seg.perm |= 1\n");
    fprintf(fp, "            if seg.perm == 0: seg.perm = 5\n");
    fprintf(fp, "            if characteristics & 0x20: seg.type = 2\n");
    fprintf(fp, "            else: seg.type = 3\n");
    fprintf(fp, "            seg.update()\n");
    fprintf(fp, "        f.seek(data_offset + va)\n");
    fprintf(fp, "        sec_data = f.read(min(vsize, raw_size if raw_size > 0 else vsize))\n");
    fprintf(fp, "        ida_bytes.put_bytes(seg_start, sec_data)\n");
    fprintf(fp, "\n\n");
    fprintf(fp, "def load_warden_module(f, data_offset, data_size, runtime_base, name, idx):\n");
    fprintf(fp, "    if data_size == 0 or runtime_base == 0:\n");
    fprintf(fp, "        return\n");
    fprintf(fp, "    seg_name = f\"wdn{idx}\"\n");
    fprintf(fp, "    seg_start = runtime_base\n");
    fprintf(fp, "    seg_end = runtime_base + data_size\n");
    fprintf(fp, "    f.seek(data_offset)\n");
    fprintf(fp, "    first_bytes = f.read(min(16, data_size))\n");
    fprintf(fp, "    seg_class = \"DATA\"\n");
    fprintf(fp, "    if len(first_bytes) >= 2:\n");
    fprintf(fp, "        if first_bytes[0] == 0xCC or (first_bytes[0] == 0x48 and first_bytes[1] in (0x89, 0x83, 0x8B)):\n");
    fprintf(fp, "            seg_class = \"CODE\"\n");
    fprintf(fp, "    if not ida_segment.add_segm(0, seg_start, seg_end, seg_name, seg_class):\n");
    fprintf(fp, "        return\n");
    fprintf(fp, "    seg = ida_segment.getseg(seg_start)\n");
    fprintf(fp, "    if seg:\n");
    fprintf(fp, "        seg.bitness = 2\n");
    fprintf(fp, "        if seg_class == 'CODE': seg.perm = 5; seg.type = 2\n");
    fprintf(fp, "        else: seg.perm = 4; seg.type = 3\n");
    fprintf(fp, "        seg.update()\n");
    fprintf(fp, "    f.seek(data_offset)\n");
    fprintf(fp, "    mod_data = f.read(data_size)\n");
    fprintf(fp, "    ida_bytes.put_bytes(seg_start, mod_data)\n");
    fprintf(fp, "\n\n");
    fprintf(fp, "def run_auto_analysis():\n");
    fprintf(fp, "    import ida_auto\n");
    fprintf(fp, "    print(\"[*] Running auto-analysis on new segments...\")\n");
    fprintf(fp, "    ida_auto.auto_wait()\n");
    fprintf(fp, "    print(\"[+] Auto-analysis complete\")\n");
    fprintf(fp, "\n\n");
    fprintf(fp, "if __name__ == \"__main__\":\n");
    fprintf(fp, "    load_segments()\n");
    fprintf(fp, "    run_auto_analysis()\n");
    fprintf(fp, "else:\n");
    fprintf(fp, "    load_segments()\n");
    fprintf(fp, "    run_auto_analysis()\n");

    fclose(fp);
    DebugLog("Generated dump_segments.py for IDA");
}

/* ------------------------------------------------------------------ */
/*  Main dump worker thread                                            */
/* ------------------------------------------------------------------ */

static DWORD WINAPI DumpWorkerThread(LPVOID lpParam) {
    (void)lpParam;
    char logBuf[256];
    DumpLog("DumpWorkerThread: entered");

    /* ---- Open IPC shared memory ---- */
    char ipcName[128];
    DinkrDumpIpcName(GetCurrentProcessId(), ipcName, sizeof(ipcName));

    {
        snprintf(logBuf, sizeof(logBuf), "DumpWorkerThread: IPC name='%s', PID=%lu",
                 ipcName, (unsigned long)GetCurrentProcessId());
        DumpLog(logBuf);
    }

    g_ipcMapping = OpenFileMappingA(FILE_MAP_ALL_ACCESS, FALSE, ipcName);
    if (g_ipcMapping) {
        g_ipc = (DinkrDumpIPC*)MapViewOfFile(g_ipcMapping, FILE_MAP_ALL_ACCESS,
                                              0, 0, sizeof(DinkrDumpIPC));
    }

    {
        snprintf(logBuf, sizeof(logBuf), "DumpWorkerThread: OpenFileMapping=%p MapView=%p err=%lu",
                 (void*)g_ipcMapping, (void*)g_ipc, (unsigned long)GetLastError());
        DumpLog(logBuf);
    }

    if (!g_ipc || g_ipc->magic != DINKR_DUMP_MAGIC) {
        snprintf(logBuf, sizeof(logBuf),
                 "IPC unavailable (mapping=%p, ipc=%p, magic=0x%08X) — fallback to C:\\dumps",
                 (void*)g_ipcMapping, (void*)g_ipc,
                 g_ipc ? (unsigned)g_ipc->magic : 0u);
        DumpLog(logBuf);

        if (g_ipc) { UnmapViewOfFile(g_ipc); g_ipc = NULL; }
        if (g_ipcMapping) { CloseHandle(g_ipcMapping); g_ipcMapping = NULL; }

        /* Fallback: dump to C:\dumps\ (matches helper_dll.c behavior) */
        strncpy(g_outputDir, "C:\\dumps", sizeof(g_outputDir) - 1);
        CreateDirectoryA(g_outputDir, NULL);
        DumpLog("DumpWorkerThread: using fallback C:\\dumps");
    } else {
        /* Read output directory from IPC */
        strncpy(g_outputDir, g_ipc->output_path, sizeof(g_outputDir) - 1);
        g_outputDir[sizeof(g_outputDir) - 1] = '\0';

        /* Read client type from IPC */
        g_isClassic = (g_ipc->client_type == DUMP_CLIENT_CLASSIC) ? 1 : 0;

        /* Ensure output directory exists */
        CreateDirectoryA(g_outputDir, NULL);

        snprintf(logBuf, sizeof(logBuf), "DumpWorkerThread: output='%s' client=%s",
                 g_outputDir, g_isClassic ? "Classic" : "Retail");
        DumpLog(logBuf);
    }

    IpcSetStatus(DUMP_STATUS_INIT, "Initializing dump...");
    IpcSetProgress(0);
    DumpLog("DumpWorkerThread: starting dump sequence");
    DebugLog("Dump DLL attached, starting dump...");

    /* ---- Initialize forced-decrypt VEH infrastructure ---- */
    if (!InitForcedDecryption()) {
        DumpLog("DumpWorkerThread: InitForcedDecryption FAILED");
        DebugLog("WARNING: InitForcedDecryption failed — forced decrypt unavailable");
    } else {
        DumpLog("DumpWorkerThread: VEH initialized");
        DebugLog("Forced-decrypt VEH initialized");
    }

    /* ---- Locate WoW image base ---- */
    PPEB peb = GET_PEB();
    if (!peb || !peb->ImageBaseAddress) {
        DumpLog("DumpWorkerThread: PEB/ImageBaseAddress NULL");
        IpcFail("Cannot read PEB/ImageBaseAddress");
        goto cleanup;
    }

    PVOID moduleBase = peb->ImageBaseAddress;
    {
        snprintf(logBuf, sizeof(logBuf), "DumpWorkerThread: moduleBase=%p", moduleBase);
        DumpLog(logBuf);
    }

    /* ---- Find Eidolon decrypt gadget ---- */
    IpcSetStatus(DUMP_STATUS_INIT, "Finding Eidolon gadget...");

    DWORD gadgetRVA = g_isClassic ? DECRYPT_GADGET_RVA_CLASSIC : DECRYPT_GADGET_RVA_RETAIL;
    LPBYTE gadgetBytes = (LPBYTE)moduleBase + gadgetRVA;
    if (IsPageReadable(gadgetBytes, 4) &&
        gadgetBytes[0] == 0x48 && gadgetBytes[1] == 0x8B &&
        gadgetBytes[2] == 0x01 && gadgetBytes[3] == 0xC3) {
        g_decryptGadget = (DecryptGadgetFunc)gadgetBytes;
        snprintf(logBuf, sizeof(logBuf), "Eidolon gadget @ RVA 0x%lX (%s)",
                 (unsigned long)gadgetRVA, g_isClassic ? "Classic" : "Retail");
        DebugLog(logBuf);
    } else {
        /* Brute-force scan first 48MB for 48 8B 01 C3 bounded by CC */
        g_decryptGadget = NULL;
        for (DWORD offset = 0x1000; offset < 0x3000000; offset++) {
            LPBYTE p = (LPBYTE)moduleBase + offset;
            if (!IsPageReadable(p, 5)) {
                /* Skip to next page boundary */
                offset = ((offset + 0x1000) & ~0xFFFu) - 1;
                continue;
            }
            if (p[0] == 0x48 && p[1] == 0x8B && p[2] == 0x01 && p[3] == 0xC3) {
                if ((offset > 0x1000 && IsPageReadable(p - 1, 1) && p[-1] == 0xCC) || p[4] == 0xCC) {
                    g_decryptGadget = (DecryptGadgetFunc)p;
                    snprintf(logBuf, sizeof(logBuf),
                             "Eidolon gadget found via scan @ offset 0x%lX", (unsigned long)offset);
                    DebugLog(logBuf);
                    break;
                }
            }
        }
        if (!g_decryptGadget) {
            DebugLog("WARNING: Eidolon gadget not found - decryption may fail");
        }
    }

    /* ---- Validate PE headers ---- */
    IpcSetStatus(DUMP_STATUS_READING_PE, "Reading PE headers...");
    IpcSetProgress(5);

    PIMAGE_DOS_HEADER pDos = (PIMAGE_DOS_HEADER)moduleBase;
    if (pDos->e_magic != IMAGE_DOS_SIGNATURE) {
        DumpLog("DumpWorkerThread: Invalid DOS signature");
        IpcFail("Invalid DOS signature");
        goto cleanup;
    }

    PIMAGE_NT_HEADERS pNt = (PIMAGE_NT_HEADERS)((LPBYTE)moduleBase + pDos->e_lfanew);
    if (pNt->Signature != IMAGE_NT_SIGNATURE) {
        DumpLog("DumpWorkerThread: Invalid NT signature");
        IpcFail("Invalid NT signature");
        goto cleanup;
    }

    DWORD imageSize = pNt->OptionalHeader.SizeOfImage;
    {
        snprintf(logBuf, sizeof(logBuf), "DumpWorkerThread: imageSize=%lu sections=%d",
                 (unsigned long)imageSize, pNt->FileHeader.NumberOfSections);
        DumpLog(logBuf);
    }

    /* ---- Allocate dump buffer ---- */
    PVOID dumpBuffer = VirtualAlloc(NULL, imageSize, MEM_COMMIT | MEM_RESERVE, PAGE_READWRITE);
    if (!dumpBuffer) {
        IpcFail("VirtualAlloc failed for dump buffer");
        goto cleanup;
    }

    /* Copy PE headers */
    memcpy(dumpBuffer, moduleBase, pNt->OptionalHeader.SizeOfHeaders);

    /* ---- Copy + decrypt sections ---- */
    IpcSetStatus(DUMP_STATUS_DECRYPTING, "Copying and decrypting sections...");
    IpcSetProgress(10);

    PIMAGE_SECTION_HEADER pSections = IMAGE_FIRST_SECTION(pNt);
    WORD numSections = pNt->FileHeader.NumberOfSections;
    DWORD pageSize = 4096;
    DWORD totalDecrypted = 0, totalCopied = 0;
    DWORD totalPages = 0;

    /* Pre-compute total pages for progress */
    for (WORD i = 0; i < numSections; i++) {
        DWORD secSize = pSections[i].Misc.VirtualSize;
        if (secSize == 0) secSize = pSections[i].SizeOfRawData;
        totalPages += (secSize + pageSize - 1) / pageSize;
    }

    DWORD pagesProcessed = 0;

    for (WORD i = 0; i < numSections; i++) {
        PIMAGE_SECTION_HEADER pSec = &pSections[i];
        char secName[9] = {0};
        memcpy(secName, pSec->Name, 8);

        DWORD secRVA = pSec->VirtualAddress;
        DWORD secSize = pSec->Misc.VirtualSize;
        if (secSize == 0) secSize = pSec->SizeOfRawData;
        if (secSize == 0 || secRVA + secSize > imageSize) continue;

        BOOL isCodeSection = (pSec->Characteristics & IMAGE_SCN_CNT_CODE) ||
                             (secName[0] == '.' && secName[1] == 't' && secName[2] == 'e');

        for (DWORD offset = 0; offset < secSize; offset += pageSize) {
            DWORD copySize = (offset + pageSize > secSize) ? (secSize - offset) : pageSize;
            PVOID srcPage = (LPBYTE)moduleBase + secRVA + offset;
            PVOID dstPage = (LPBYTE)dumpBuffer + secRVA + offset;

            MEMORY_BASIC_INFORMATION mbi;
            if (VirtualQuery(srcPage, &mbi, sizeof(mbi)) == 0) {
                pagesProcessed++;
                continue;
            }

            if (mbi.Protect == PAGE_NOACCESS || mbi.Protect == 0) {
                BOOL decrypted = FALSE;

                if (isCodeSection && copySize == pageSize && CopyPageAfterTouch(srcPage, dstPage)) {
                    decrypted = TRUE;
                    totalDecrypted++;
                    totalCopied++;
                }

                if (!decrypted && isCodeSection && g_decryptGadget && copySize == pageSize) {
                    DWORD oldProt;
                    if (VirtualProtect(srcPage, copySize, PAGE_EXECUTE_READ, &oldProt)) {
                        if (DecryptPageWithGadget(srcPage, dstPage)) {
                            decrypted = TRUE;
                            totalDecrypted++;
                            totalCopied++;
                        }
                        VirtualProtect(srcPage, copySize, oldProt, &oldProt);
                    }
                }

                if (!decrypted) {
                    DWORD oldProt;
                    if (VirtualProtect(srcPage, copySize, PAGE_EXECUTE_READ, &oldProt)) {
                        memcpy(dstPage, srcPage, copySize);
                        VirtualProtect(srcPage, copySize, oldProt, &oldProt);
                        totalCopied++;
                    }
                }
            } else if (!(mbi.Protect & PAGE_GUARD)) {
                if (isCodeSection && copySize == pageSize && CopyPageAfterTouch(srcPage, dstPage)) {
                    totalDecrypted++;
                    totalCopied++;
                } else {
                    memcpy(dstPage, srcPage, copySize);
                    totalCopied++;
                }
            }

            pagesProcessed++;
            /* Update progress: 10-60% range for section copy */
            if (totalPages > 0) {
                uint32_t pct = 10 + (pagesProcessed * 50) / totalPages;
                IpcSetProgress(pct);
            }
        }
    }

    snprintf(logBuf, sizeof(logBuf), "Sections: %lu pages copied, %lu decrypted",
             totalCopied, totalDecrypted);
    DebugLog(logBuf);

    /* ---- Fix PE for disk (RawData = VirtualAddress) ---- */
    PIMAGE_DOS_HEADER pDumpDos = (PIMAGE_DOS_HEADER)dumpBuffer;
    PIMAGE_NT_HEADERS pDumpNt = (PIMAGE_NT_HEADERS)((LPBYTE)dumpBuffer + pDumpDos->e_lfanew);
    PIMAGE_SECTION_HEADER pDumpSections = IMAGE_FIRST_SECTION(pDumpNt);

    for (WORD i = 0; i < pDumpNt->FileHeader.NumberOfSections; i++) {
        pDumpSections[i].PointerToRawData = pDumpSections[i].VirtualAddress;
        pDumpSections[i].SizeOfRawData = pDumpSections[i].Misc.VirtualSize;
    }
    pDumpNt->OptionalHeader.FileAlignment = pDumpNt->OptionalHeader.SectionAlignment;

    if (pDumpNt->OptionalHeader.NumberOfRvaAndSizes > IMAGE_DIRECTORY_ENTRY_BOUND_IMPORT) {
        pDumpNt->OptionalHeader.DataDirectory[IMAGE_DIRECTORY_ENTRY_BOUND_IMPORT].VirtualAddress = 0;
        pDumpNt->OptionalHeader.DataDirectory[IMAGE_DIRECTORY_ENTRY_BOUND_IMPORT].Size = 0;
    }
    if (pDumpNt->OptionalHeader.NumberOfRvaAndSizes > IMAGE_DIRECTORY_ENTRY_SECURITY) {
        pDumpNt->OptionalHeader.DataDirectory[IMAGE_DIRECTORY_ENTRY_SECURITY].VirtualAddress = 0;
        pDumpNt->OptionalHeader.DataDirectory[IMAGE_DIRECTORY_ENTRY_SECURITY].Size = 0;
    }

    /* ---- Reconstruct TLS + IAT ---- */
    IpcSetStatus(DUMP_STATUS_EXTRACTING, "Reconstructing TLS & IAT...");
    IpcSetProgress(62);

    ScanAndTrackTlsCallbacks(moduleBase);
    ReconstructTlsCallbacks(moduleBase, dumpBuffer, imageSize);
    ReconstructIAT(moduleBase, dumpBuffer, imageSize);

    /* ---- Extract offsets ---- */
    IpcSetStatus(DUMP_STATUS_EXTRACTING, "Extracting offsets...");
    IpcSetProgress(65);

    uint64_t textStart = 0, textEnd = 0;
    uint64_t rdataStart = 0, rdataEnd = 0;
    uint64_t dataStart = 0, dataEnd = 0;

    PIMAGE_SECTION_HEADER pSection = IMAGE_FIRST_SECTION(pNt);
    for (WORD i = 0; i < numSections; i++) {
        char secName[9] = {0};
        memcpy(secName, pSection[i].Name, 8);
        uint32_t virtualSize = pSection[i].Misc.VirtualSize;
        uint32_t virtualAddr = pSection[i].VirtualAddress;

        if (strcmp(secName, ".text") == 0) {
            textStart = virtualAddr; textEnd = virtualAddr + virtualSize;
        } else if (strcmp(secName, ".rdata") == 0) {
            rdataStart = virtualAddr; rdataEnd = virtualAddr + virtualSize;
        } else if (strcmp(secName, ".data") == 0) {
            dataStart = virtualAddr; dataEnd = virtualAddr + virtualSize;
        }
    }

    OffsetEntry* offsets = NULL;
    int offsetCount = 0;

    if (textStart && rdataStart && dataStart) {
        offsets = VirtualAlloc(NULL, MAX_OFFSETS * sizeof(OffsetEntry),
                               MEM_COMMIT | MEM_RESERVE, PAGE_READWRITE);
        if (offsets) {
            ExtractLuaFunctions(moduleBase, dumpBuffer, imageSize,
                                textStart, textEnd, rdataStart, rdataEnd,
                                dataStart, dataEnd, offsets, &offsetCount, MAX_OFFSETS);

            IpcSetProgress(75);
            IpcSetStatus(DUMP_STATUS_EXTRACTING, "Extracting globals...");

            ExtractGlobalOffsets(moduleBase, dumpBuffer, imageSize,
                                textStart, textEnd, dataStart, dataEnd,
                                offsets, &offsetCount, MAX_OFFSETS);

            IpcSetProgress(80);
            IpcSetStatus(DUMP_STATUS_EXTRACTING, "Scanning critical sigs...");

            ExtractCriticalOffsets(dumpBuffer, imageSize, offsets, &offsetCount, MAX_OFFSETS);

            WriteOffsetsFile(moduleBase, offsets, offsetCount);

            snprintf(logBuf, sizeof(logBuf), "Offsets extracted: %d", offsetCount);
            DebugLog(logBuf);

            VirtualFree(offsets, 0, MEM_RELEASE);
            offsets = NULL;
        }
    }

    /* ---- Write main dump.bin ---- */
    IpcSetStatus(DUMP_STATUS_WRITING, "Writing dump.bin...");
    IpcSetProgress(85);
    DumpLog("DumpWorkerThread: writing dump.bin");

    char dumpPath[MAX_PATH];
    BuildOutputPath("dump.bin", dumpPath, sizeof(dumpPath));

    HANDLE hFile = CreateFileA(dumpPath, GENERIC_WRITE, 0, NULL,
                               CREATE_ALWAYS, FILE_ATTRIBUTE_NORMAL, NULL);

    if (hFile == INVALID_HANDLE_VALUE) {
        DWORD err = GetLastError();
        snprintf(logBuf, sizeof(logBuf), "CreateFile failed for dump.bin path='%s' (err=%lu)", dumpPath, err);
        DumpLog(logBuf);
        IpcFail(logBuf);
        VirtualFree(dumpBuffer, 0, MEM_RELEASE);
        goto cleanup;
    }

    {
        DWORD totalWritten = 0;
        LPBYTE ptr = (LPBYTE)dumpBuffer;
        DWORD remaining = imageSize;
        BOOL ok = TRUE;

        while (remaining > 0 && ok) {
            DWORD toWrite = (remaining > CHUNK_SIZE_16MB) ? CHUNK_SIZE_16MB : remaining;
            DWORD written = 0;
            ok = WriteFile(hFile, ptr, toWrite, &written, NULL);
            if (ok && written > 0) {
                totalWritten += written;
                ptr += written;
                remaining -= written;
            } else {
                break;
            }
        }

        CloseHandle(hFile);

        if (ok) {
            snprintf(logBuf, sizeof(logBuf), "dump.bin: %lu bytes written", totalWritten);
            DebugLog(logBuf);
            if (g_ipc) g_ipc->bytes_written = totalWritten;
        } else {
            snprintf(logBuf, sizeof(logBuf), "dump.bin: write failed at %lu", totalWritten);
            IpcFail(logBuf);
            VirtualFree(dumpBuffer, 0, MEM_RELEASE);
            goto cleanup;
        }
    }

    VirtualFree(dumpBuffer, 0, MEM_RELEASE);

    /* ---- Dump Wow_loader.dll ---- */
    IpcSetStatus(DUMP_STATUS_EXTRACTING, "Dumping loader...");
    IpcSetProgress(90);
    DumpWowLoader();

    /* ---- Single-pass Warden module scan ---- */
    IpcSetStatus(DUMP_STATUS_EXTRACTING, "Scanning Warden modules...");
    IpcSetProgress(95);
    {
        int newModules = ScanAndDumpWardenModules();
        if (newModules > 0) {
            snprintf(logBuf, sizeof(logBuf), "Warden scan: %d module(s) found", newModules);
            DebugLog(logBuf);
        }
    }

    /* ---- Generate IDA script ---- */
    GenerateIDAScript();

    /* ---- Continuous Warden module scan (like helper_dll.c) ---- */
    if (g_ipc) {
        IpcSetStatus(DUMP_STATUS_SCANNING, "Scanning for Warden modules...");
        InterlockedExchange(&g_ipc->modules_found, (LONG)g_loggedModuleCount);
        DumpLog("Entering continuous Warden scan loop (500ms interval)");

        int scanCount = 0;
        while (!InterlockedOr(&g_ipc->stop_requested, 0)) {
            Sleep(500);
            scanCount++;

            int newModules = ScanAndDumpWardenModules();

            if (newModules > 0) {
                InterlockedExchange(&g_ipc->modules_found, (LONG)g_loggedModuleCount);

                snprintf(logBuf, sizeof(logBuf), "Scan #%d: %d new module(s), total=%d",
                         scanCount, newModules, g_loggedModuleCount);
                DumpLog(logBuf);
                DebugLog(logBuf);

                GenerateIDAScript();

                char statusBuf[128];
                snprintf(statusBuf, sizeof(statusBuf), "Scanning... %d modules found", g_loggedModuleCount);
                IpcSetStatus(DUMP_STATUS_SCANNING, statusBuf);
            }
        }
        DumpLog("Stop requested — exiting scan loop");
    } else {
        DumpLog("No IPC — skipping continuous scan (fallback mode)");
    }

    /* ---- Done ---- */
    IpcSetStatus(DUMP_STATUS_COMPLETE, "Dump complete");
    IpcSetProgress(100);
    DumpLog("DumpWorkerThread: DUMP COMPLETE");
    DebugLog("Dump complete — self-destructing");

cleanup:
    CleanupForcedDecryption();
    if (g_ipc) UnmapViewOfFile(g_ipc);
    if (g_ipcMapping) CloseHandle(g_ipcMapping);
    g_ipc = NULL;
    g_ipcMapping = NULL;

    DumpLog("DumpWorkerThread: cleanup done, returning");
    return 0;
}

/* ------------------------------------------------------------------ */
/*  Thread pool callback — matches helper_dll.c pattern                */
/* ------------------------------------------------------------------ */

static VOID CALLBACK DumpPoolCallback(PTP_CALLBACK_INSTANCE Instance, PVOID Context) {
    (void)Instance; (void)Context;
    DumpLog("DumpPoolCallback: entered, sleeping 2s");
    Sleep(2000);  /* brief settle — let threads resume */
    DumpLog("DumpPoolCallback: calling DumpWorkerThread");
    DumpWorkerThread(NULL);
    DumpLog("DumpPoolCallback: DumpWorkerThread returned");
}

/* ------------------------------------------------------------------ */
/*  DLL entry point                                                    */
/* ------------------------------------------------------------------ */

BOOL WINAPI DllMain(HINSTANCE hinstDLL, DWORD fdwReason, LPVOID lpvReserved) {
    (void)lpvReserved;

    if (fdwReason == DLL_PROCESS_ATTACH) {
        DumpLog("DllMain: DLL_PROCESS_ATTACH entry");
        g_hModule = hinstDLL;
        DisableThreadLibraryCalls(hinstDLL);
        DumpLog("DllMain: DisableThreadLibraryCalls done");

        /* Create confirmation event so the GUI knows DllMain executed.
         * Manual-reset, initially signaled — GUI polls for this via OpenEventA. */
        {
            char evtName[80];
            DinkrDumpEvtName((unsigned long)GetCurrentProcessId(), evtName, sizeof(evtName));
            CreateEventA(NULL, TRUE, TRUE, evtName);
            DumpLog("DllMain: created confirmation event");
        }

        /* Queue dump work on the existing thread pool — no new thread creation.
         * Matches helper_dll.c's TrySubmitThreadpoolCallback pattern. */
        if (!TrySubmitThreadpoolCallback(DumpPoolCallback, NULL, NULL)) {
            DumpLog("DllMain: TrySubmitThreadpoolCallback FAILED — running inline");
            Sleep(2000);
            DumpWorkerThread(NULL);
        } else {
            DumpLog("DllMain: TrySubmitThreadpoolCallback OK");
        }
        DumpLog("DllMain: returning TRUE");
    }
    return TRUE;
}
