/*
 * gui_injection.cpp — Reflective DLL injection for the DINKR GUI
 *
 * Per-session: all state flows through WowSession*.
 */

#include "gui_external.h"

#include <windows.h>
#include <tlhelp32.h>
#include <cstdio>
#include <cstring>

/* ======================================================================
 * Reflective DLL Injection — manual PE mapping + thread hijacking
 *
 * Ported from AutoDump-main/injector.c. Uses Win32 API for memory
 * operations (VirtualAllocEx, WriteProcessMemory, ReadProcessMemory,
 * VirtualProtectEx) and NtAPI for thread operations (NtOpenThread,
 * NtSuspendThread, NtGetContextThread, NtSetContextThread, etc.).
 * ====================================================================== */
static void StealthZeroMem(volatile void* ptr, size_t sz)
{
    volatile unsigned char* p = (volatile unsigned char*)ptr;
    while (sz--) *p++ = 0;
}

static void* ReadDLLFileExt(const char* dllPath, size_t* pSize)
{
    HANDLE hFile = CreateFileA(dllPath, GENERIC_READ, FILE_SHARE_READ, NULL,
                               OPEN_EXISTING,
                               FILE_ATTRIBUTE_NORMAL | FILE_FLAG_SEQUENTIAL_SCAN, NULL);
    if (hFile == INVALID_HANDLE_VALUE) return nullptr;

    DWORD fileSize = GetFileSize(hFile, NULL);
    if (fileSize == 0 || fileSize > 50 * 1024 * 1024) {
        CloseHandle(hFile);
        return nullptr;
    }
    *pSize = (size_t)fileSize;

    void* buffer = VirtualAlloc(NULL, fileSize, MEM_COMMIT | MEM_RESERVE, PAGE_READWRITE);
    if (!buffer) { CloseHandle(hFile); return nullptr; }

    DWORD bytesRead = 0;
    if (!ReadFile(hFile, buffer, fileSize, &bytesRead, NULL) || bytesRead != fileSize) {
        StealthZeroMem(buffer, fileSize);
        VirtualFree(buffer, 0, MEM_RELEASE);
        CloseHandle(hFile);
        return nullptr;
    }
    CloseHandle(hFile);
    return buffer;
}

/* Convert RVA to file offset using the section table */
static DWORD RvaToFileOffset(PIMAGE_NT_HEADERS pNt, DWORD rva)
{
    auto pSec = IMAGE_FIRST_SECTION(pNt);
    for (WORD i = 0; i < pNt->FileHeader.NumberOfSections; i++) {
        DWORD start = pSec[i].VirtualAddress;
        DWORD end   = start + pSec[i].Misc.VirtualSize;
        if (rva >= start && rva < end)
            return pSec[i].PointerToRawData + (rva - start);
    }
    return 0;
}

static void* ReflectiveLoadDLLExt(HANDLE hProc, void* dllBuffer, size_t dllSize)
{
    auto pDosHeader = (PIMAGE_DOS_HEADER)dllBuffer;
    if (pDosHeader->e_magic != IMAGE_DOS_SIGNATURE) return nullptr;

    /* H11: bounds-check e_lfanew before using it as an offset */
    LONG lfanew = pDosHeader->e_lfanew;
    if (lfanew < (LONG)sizeof(IMAGE_DOS_HEADER) ||
        (size_t)lfanew + sizeof(IMAGE_NT_HEADERS) > dllSize)
        return nullptr;

    auto pNtHeaders = (PIMAGE_NT_HEADERS)((LPBYTE)dllBuffer + lfanew);
    if (pNtHeaders->Signature != IMAGE_NT_SIGNATURE) return nullptr;

    SIZE_T imageSize = pNtHeaders->OptionalHeader.SizeOfImage;

    /* Allocate in target process */
    void* remoteBase = VirtualAllocEx(hProc, NULL, imageSize,
                                      MEM_COMMIT | MEM_RESERVE, PAGE_READWRITE);
    if (!remoteBase) return nullptr;

    /* Write PE headers */
    SIZE_T bw = 0;
    if (!WriteProcessMemory(hProc, remoteBase, dllBuffer,
                            pNtHeaders->OptionalHeader.SizeOfHeaders, &bw)) {
        VirtualFreeEx(hProc, remoteBase, 0, MEM_RELEASE);
        return nullptr;
    }

    /* Write sections */
    auto pSection = IMAGE_FIRST_SECTION(pNtHeaders);
    for (WORD i = 0; i < pNtHeaders->FileHeader.NumberOfSections; i++) {
        if (pSection[i].SizeOfRawData) {
            void* dest = (LPBYTE)remoteBase + pSection[i].VirtualAddress;
            void* src  = (LPBYTE)dllBuffer  + pSection[i].PointerToRawData;
            if (!WriteProcessMemory(hProc, dest, src, pSection[i].SizeOfRawData, &bw)) {
                VirtualFreeEx(hProc, remoteBase, 0, MEM_RELEASE);
                return nullptr;
            }
        }
    }

    /* Process relocations */
    DWORD_PTR delta = (DWORD_PTR)remoteBase - pNtHeaders->OptionalHeader.ImageBase;
    if (delta) {
        DWORD relocRva  = pNtHeaders->OptionalHeader.DataDirectory[IMAGE_DIRECTORY_ENTRY_BASERELOC].VirtualAddress;
        DWORD relocSize = pNtHeaders->OptionalHeader.DataDirectory[IMAGE_DIRECTORY_ENTRY_BASERELOC].Size;

        if (relocSize && relocRva) {
            DWORD relocFileOff = RvaToFileOffset(pNtHeaders, relocRva);
            if (relocFileOff) {
                auto pReloc = (PIMAGE_BASE_RELOCATION)((LPBYTE)dllBuffer + relocFileOff);
                DWORD processed = 0;

                while (relocSize > 0 && processed < 1000) {
                    processed++;
                    if (pReloc->SizeOfBlock == 0 ||
                        pReloc->SizeOfBlock < sizeof(IMAGE_BASE_RELOCATION) ||
                        pReloc->SizeOfBlock > relocSize) break;

                    DWORD count = (pReloc->SizeOfBlock - sizeof(IMAGE_BASE_RELOCATION)) / sizeof(WORD);
                    PWORD pData = (PWORD)(pReloc + 1);

                    for (DWORD ri = 0; ri < count; ri++) {
                        WORD type   = pData[ri] >> 12;
                        WORD offset = pData[ri] & 0xFFF;

                        if (type == IMAGE_REL_BASED_DIR64) {
                            void* patchAddr = (LPBYTE)remoteBase + pReloc->VirtualAddress + offset;
                            DWORD_PTR value = 0;
                            SIZE_T br = 0;
                            if (ReadProcessMemory(hProc, patchAddr, &value, sizeof(value), &br)) {
                                value += delta;
                                WriteProcessMemory(hProc, patchAddr, &value, sizeof(value), &bw);
                            }
                        }
                    }

                    relocSize -= pReloc->SizeOfBlock;
                    pReloc = (PIMAGE_BASE_RELOCATION)((LPBYTE)pReloc + pReloc->SizeOfBlock);
                }
            }
        }
    }

    /* Resolve imports — system DLLs are at the same address in all processes */
    DWORD importRva  = pNtHeaders->OptionalHeader.DataDirectory[IMAGE_DIRECTORY_ENTRY_IMPORT].VirtualAddress;
    DWORD importSize = pNtHeaders->OptionalHeader.DataDirectory[IMAGE_DIRECTORY_ENTRY_IMPORT].Size;

    if (importRva && importSize) {
        DWORD importFileOff = RvaToFileOffset(pNtHeaders, importRva);
        if (importFileOff) {
            auto pImportDesc = (PIMAGE_IMPORT_DESCRIPTOR)((LPBYTE)dllBuffer + importFileOff);

            while (pImportDesc->Name) {
                DWORD nameFileOff = RvaToFileOffset(pNtHeaders, pImportDesc->Name);
                if (!nameFileOff) { pImportDesc++; continue; }

                char* impDllName = (char*)((LPBYTE)dllBuffer + nameFileOff);
                HMODULE hModule = GetModuleHandleA(impDllName);
                if (!hModule) hModule = LoadLibraryA(impDllName);
                if (!hModule) { pImportDesc++; continue; }

                DWORD origThunkRva = pImportDesc->OriginalFirstThunk
                    ? pImportDesc->OriginalFirstThunk : pImportDesc->FirstThunk;
                DWORD thunkRva = pImportDesc->FirstThunk;

                DWORD origThunkFileOff = RvaToFileOffset(pNtHeaders, origThunkRva);
                if (!origThunkFileOff) { pImportDesc++; continue; }

                auto pOrigThunk = (PIMAGE_THUNK_DATA)((LPBYTE)dllBuffer + origThunkFileOff);
                void* pIatEntry = (LPBYTE)remoteBase + thunkRva;

                while (pOrigThunk->u1.AddressOfData) {
                    FARPROC funcAddr = nullptr;

                    if (pOrigThunk->u1.Ordinal & IMAGE_ORDINAL_FLAG) {
                        WORD ordinal = (WORD)(pOrigThunk->u1.Ordinal & 0xFFFF);
                        funcAddr = GetProcAddress(hModule, (LPCSTR)(ULONG_PTR)ordinal);
                    } else {
                        DWORD ibnFileOff = RvaToFileOffset(pNtHeaders,
                            (DWORD)pOrigThunk->u1.AddressOfData);
                        if (ibnFileOff) {
                            auto pIBN = (PIMAGE_IMPORT_BY_NAME)((LPBYTE)dllBuffer + ibnFileOff);
                            funcAddr = GetProcAddress(hModule, (char*)pIBN->Name);
                        }
                    }

                    if (funcAddr) {
                        DWORD64 addr64 = (DWORD64)funcAddr;
                        WriteProcessMemory(hProc, pIatEntry, &addr64, sizeof(addr64), &bw);
                    }

                    pOrigThunk++;
                    pIatEntry = (LPBYTE)pIatEntry + sizeof(DWORD64);
                }

                pImportDesc++;
            }
        }
    }

    /* Set section protections */
    pSection = IMAGE_FIRST_SECTION(pNtHeaders);
    for (WORD i = 0; i < pNtHeaders->FileHeader.NumberOfSections; i++) {
        DWORD protect = 0;
        DWORD ch = pSection[i].Characteristics;

        if (ch & IMAGE_SCN_MEM_EXECUTE)
            protect = (ch & IMAGE_SCN_MEM_READ) ? PAGE_EXECUTE_READ : PAGE_EXECUTE;
        else
            protect = (ch & IMAGE_SCN_MEM_WRITE) ? PAGE_READWRITE : PAGE_READONLY;

        if (protect) {
            DWORD oldProt = 0;
            VirtualProtectEx(hProc,
                             (LPBYTE)remoteBase + pSection[i].VirtualAddress,
                             pSection[i].Misc.VirtualSize,
                             protect, &oldProt);
        }
    }

    /* Protect headers */
    DWORD oldProt = 0;
    VirtualProtectEx(hProc, remoteBase,
                     pNtHeaders->OptionalHeader.SizeOfHeaders,
                     PAGE_EXECUTE_READ, &oldProt);

    return remoteBase;
}

/* Find the main (earliest-created) thread of a process */
static DWORD GetMainThreadIdExt(DWORD pid)
{
    HANDLE hSnap = CreateToolhelp32Snapshot(TH32CS_SNAPTHREAD, 0);
    if (hSnap == INVALID_HANDLE_VALUE) return 0;

    THREADENTRY32 te = {};
    te.dwSize = sizeof(te);
    DWORD mainTid = 0;
    ULONGLONG earliest = (ULONGLONG)(-1);

    if (Thread32First(hSnap, &te)) {
        do {
            if (te.th32OwnerProcessID == pid) {
                HANDLE hT = OpenThread(THREAD_QUERY_INFORMATION, FALSE, te.th32ThreadID);
                if (hT) {
                    FILETIME ct, et, kt, ut;
                    if (GetThreadTimes(hT, &ct, &et, &kt, &ut)) {
                        ULARGE_INTEGER ul;
                        ul.LowPart = ct.dwLowDateTime;
                        ul.HighPart = ct.dwHighDateTime;
                        if (ul.QuadPart < earliest) {
                            earliest = ul.QuadPart;
                            mainTid = te.th32ThreadID;
                        }
                    }
                    CloseHandle(hT);
                }
            }
        } while (Thread32Next(hSnap, &te));
    }
    CloseHandle(hSnap);
    return mainTid;
}

/* Find the best idle worker thread (not main) for thread hijacking.
 * excludeTid: skip this thread ID (0 = no exclusion) to allow retries. */
static DWORD GetWorkerThreadIdExt(DWORD pid, DWORD excludeTid,
                                  const DWORD* suspTIDs, int suspCount)
{
    HANDLE hSnap = CreateToolhelp32Snapshot(TH32CS_SNAPTHREAD, 0);
    if (hSnap == INVALID_HANDLE_VALUE) return 0;

    DWORD mainTid = GetMainThreadIdExt(pid);

    THREADENTRY32 te = {};
    te.dwSize = sizeof(te);
    DWORD candidates[64];
    ULONGLONG times[64];
    int count = 0;

    if (Thread32First(hSnap, &te)) {
        do {
            if (te.th32OwnerProcessID == pid &&
                te.th32ThreadID != mainTid &&
                te.th32ThreadID != excludeTid && count < 64) {
                /* Skip already-suspended Warden threads */
                bool isSuspended = false;
                for (int si = 0; si < suspCount; si++) {
                    if (suspTIDs[si] == te.th32ThreadID) { isSuspended = true; break; }
                }
                if (isSuspended) continue;

                HANDLE hT = OpenThread(THREAD_QUERY_INFORMATION, FALSE, te.th32ThreadID);
                if (hT) {
                    FILETIME ct, et, kt, ut;
                    if (GetThreadTimes(hT, &ct, &et, &kt, &ut)) {
                        ULARGE_INTEGER k, u;
                        k.LowPart = kt.dwLowDateTime; k.HighPart = kt.dwHighDateTime;
                        u.LowPart = ut.dwLowDateTime; u.HighPart = ut.dwHighDateTime;
                        candidates[count] = te.th32ThreadID;
                        times[count] = k.QuadPart + u.QuadPart;
                        count++;
                    }
                    CloseHandle(hT);
                }
            }
        } while (Thread32Next(hSnap, &te));
    }
    CloseHandle(hSnap);

    if (count == 0) return (excludeTid == 0) ? mainTid : 0;

    /* Prefer threads with MORE CPU time (recently active, likely to return
     * to user mode soon) over dormant threads stuck in deep kernel waits.
     * Previous heuristic picked the least-busy thread which was paradoxically
     * the most likely to be in a non-alertable wait and never execute shellcode. */
    DWORD best = 0;
    ULONGLONG bestTime = 0;
    for (int i = 0; i < count; i++) {
        if (times[i] > bestTime) {
            bestTime = times[i];
            best = candidates[i];
        }
    }
    return best ? best : candidates[0];
}

/* Hijack a specific thread to call DllMain via shellcode.
 * Returns true if the thread was successfully hijacked. */
static bool CallDllEntryPointOnThreadExt(HANDLE hProc, DWORD pid, void* dllBase, void* entryPoint, DWORD threadId)
{
    NT_CLIENT_ID clientId = {};
    clientId.UniqueProcess = (PVOID)(ULONG_PTR)pid;
    clientId.UniqueThread  = (PVOID)(ULONG_PTR)threadId;

    NT_OBJECT_ATTRIBUTES objAttr = {};
    objAttr.Length = sizeof(objAttr);

    HANDLE hThread = NULL;
    NTSTATUS_T ntStatus = pNtOpenThread(&hThread, THREAD_ALL_ACCESS, &objAttr, &clientId);
    if (!NT_SUCCESS_CHECK(ntStatus)) {
        char logBuf[256];
        snprintf(logBuf, sizeof(logBuf), "FAIL: NtOpenThread TID=%lu NTSTATUS=0x%08lX",
                 (unsigned long)threadId, (unsigned long)ntStatus);
        IpcHost_Log("[gui]", logBuf);
        return false;
    }

    /* Suspend the thread and check previous suspend count */
    ULONG prevCount = 0;
    if (!NT_SUCCESS_CHECK(pNtSuspendThread(hThread, &prevCount))) {
        CloseHandle(hThread);
        return false;
    }
    if (prevCount > 0) {
        /* Thread was already suspended — resume it and skip */
        pNtResumeThread(hThread, NULL);
        CloseHandle(hThread);
        char logBuf[256];
        snprintf(logBuf, sizeof(logBuf), "WARN: TID=%lu already suspended, skipping",
                 (unsigned long)threadId);
        IpcHost_Log("[gui]", logBuf);
        return false;
    }

    CONTEXT ctx = {};
    ctx.ContextFlags = CONTEXT_CONTROL | CONTEXT_INTEGER;
    if (!NT_SUCCESS_CHECK(pNtGetContextThread(hThread, &ctx))) {
        pNtResumeThread(hThread, NULL);
        CloseHandle(hThread);
        return false;
    }

    /* Diagnostic logging */
    {
        char logBuf[256];
        snprintf(logBuf, sizeof(logBuf), "hijacking TID=%lu, entry=%p, dllBase=%p",
                 (unsigned long)threadId, entryPoint, dllBase);
        IpcHost_Log("[gui]", logBuf);
    }

    /*
     * x64 shellcode (76 bytes): save all volatile regs + flags,
     * call DllMain(hModule, DLL_PROCESS_ATTACH, NULL), restore,
     * return to original RIP via xchg+ret trick.
     */
    unsigned char shellcode[] = {
        /* Save volatile registers + flags */
        0x50,                                                       /* push rax              */
        0x51,                                                       /* push rcx              */
        0x52,                                                       /* push rdx              */
        0x41, 0x50,                                                 /* push r8               */
        0x41, 0x51,                                                 /* push r9               */
        0x41, 0x52,                                                 /* push r10              */
        0x41, 0x53,                                                 /* push r11              */
        0x9C,                                                       /* pushfq                */
        0x48, 0x83, 0xEC, 0x28,                                     /* sub rsp, 0x28         */
        /* Call DllMain(hModule, DLL_PROCESS_ATTACH, NULL) */
        0x48, 0xB9, 0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,       /* mov rcx, <dllBase>         [+18] */
        0xBA, 0x01, 0x00, 0x00, 0x00,                               /* mov edx, 1                 */
        0x4D, 0x31, 0xC0,                                           /* xor r8, r8                 */
        0x48, 0xB8, 0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,       /* mov rax, <entryPoint>      [+36] */
        0xFF, 0xD0,                                                  /* call rax                   */
        /* Restore registers + flags */
        0x48, 0x83, 0xC4, 0x28,                                     /* add rsp, 0x28              */
        0x9D,                                                        /* popfq                      */
        0x41, 0x5B,                                                  /* pop r11                    */
        0x41, 0x5A,                                                  /* pop r10                    */
        0x41, 0x59,                                                  /* pop r9                     */
        0x41, 0x58,                                                  /* pop r8                     */
        0x5A,                                                        /* pop rdx                    */
        0x59,                                                        /* pop rcx                    */
        /* Restore rax + jump to original RIP via xchg+ret trick */
        0x48, 0xB8, 0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,       /* mov rax, <origRip>         [+63] */
        0x48, 0x87, 0x04, 0x24,                                     /* xchg rax, [rsp]            */
        0xC3                                                         /* ret                        */
    };

    DWORD64 dllBaseAddr    = (DWORD64)(uintptr_t)dllBase;
    DWORD64 entryPointAddr = (DWORD64)(uintptr_t)entryPoint;
    DWORD64 originalRip    = ctx.Rip;

    memcpy(&shellcode[18], &dllBaseAddr,     sizeof(DWORD64));
    memcpy(&shellcode[36], &entryPointAddr,  sizeof(DWORD64));
    memcpy(&shellcode[63], &originalRip,     sizeof(DWORD64));

    void* scAddr = VirtualAllocEx(hProc, NULL, sizeof(shellcode),
                                  MEM_COMMIT | MEM_RESERVE, PAGE_READWRITE);
    if (!scAddr) {
        pNtResumeThread(hThread, NULL);
        CloseHandle(hThread);
        return false;
    }

    SIZE_T bw = 0;
    if (!WriteProcessMemory(hProc, scAddr, shellcode, sizeof(shellcode), &bw)) {
        VirtualFreeEx(hProc, scAddr, 0, MEM_RELEASE);
        pNtResumeThread(hThread, NULL);
        CloseHandle(hThread);
        return false;
    }

    DWORD oldProt = 0;
    VirtualProtectEx(hProc, scAddr, sizeof(shellcode), PAGE_EXECUTE_READ, &oldProt);

    ctx.Rip = (DWORD64)(uintptr_t)scAddr;

    if (!NT_SUCCESS_CHECK(pNtSetContextThread(hThread, &ctx))) {
        VirtualFreeEx(hProc, scAddr, 0, MEM_RELEASE);
        pNtResumeThread(hThread, NULL);
        CloseHandle(hThread);
        return false;
    }

    pNtResumeThread(hThread, NULL);
    if (pNtAlertThread) pNtAlertThread(hThread);

    CloseHandle(hThread);
    return true;
}

/* Try multiple threads for DllMain hijacking with per-thread event verification.
 * After each hijack, waits for the DLL singleton event to confirm DllMain actually ran.
 * If the hijacked thread is in a kernel wait and doesn't execute within the timeout,
 * moves on to the next thread. Safe because DllMain's worker has a singleton guard.
 * evtName: the named event that the DLL creates in DllMain for confirmation. */
static bool CallDllEntryPointExt(HANDLE hProc, DWORD pid, void* dllBase,
                                 const char* evtName,
                                 const DWORD* suspTIDs, int suspCount)
{
    IMAGE_DOS_HEADER dosHdr = {};
    SIZE_T br = 0;
    if (!ReadProcessMemory(hProc, dllBase, &dosHdr, sizeof(dosHdr), &br))
        return false;

    IMAGE_NT_HEADERS ntHdr = {};
    void* ntAddr = (LPBYTE)dllBase + dosHdr.e_lfanew;
    if (!ReadProcessMemory(hProc, ntAddr, &ntHdr, sizeof(ntHdr), &br))
        return false;

    void* entryPoint = (LPBYTE)dllBase + ntHdr.OptionalHeader.AddressOfEntryPoint;

    /* Build candidate thread list: primary worker, secondary worker, main thread */
    DWORD tids[4] = {};
    int tidCount = 0;

    DWORD primary = GetWorkerThreadIdExt(pid, 0, suspTIDs, suspCount);
    if (primary) tids[tidCount++] = primary;

    DWORD secondary = GetWorkerThreadIdExt(pid, primary, suspTIDs, suspCount);
    if (secondary && secondary != primary) tids[tidCount++] = secondary;

    DWORD mainTid = GetMainThreadIdExt(pid);
    if (mainTid && tidCount < 4) {
        bool already = false;
        for (int i = 0; i < tidCount; i++) {
            if (tids[i] == mainTid) { already = true; break; }
        }
        if (!already) tids[tidCount++] = mainTid;
    }

    if (tidCount == 0) {
        IpcHost_Log("[gui]", "FAIL: no candidate threads for hijacking");
        return false;
    }

    {
        char logBuf[256];
        snprintf(logBuf, sizeof(logBuf), "injection: %d candidate thread(s)", tidCount);
        IpcHost_Log("[gui]", logBuf);
    }

    /* Try each thread: hijack, then wait for event proof before trying next */
    for (int i = 0; i < tidCount; i++) {
        if (!CallDllEntryPointOnThreadExt(hProc, pid, dllBase, entryPoint, tids[i])) {
            char logBuf[128];
            snprintf(logBuf, sizeof(logBuf), "thread %d/%d (TID=%lu) hijack failed, trying next...",
                     i + 1, tidCount, (unsigned long)tids[i]);
            IpcHost_Log("[gui]", logBuf);
            continue;
        }

        /* Hijack API succeeded — wait for DllMain to actually execute.
         * Check every 200ms for up to 5 seconds per thread. */
        bool confirmed = false;
        for (int w = 0; w < 25; w++) {
            Sleep(200);
            HANDLE h = OpenEventA(SYNCHRONIZE, FALSE, evtName);
            if (h) {
                CloseHandle(h);
                confirmed = true;
                break;
            }
        }

        if (confirmed) {
            char logBuf[128];
            snprintf(logBuf, sizeof(logBuf), "thread %d/%d (TID=%lu) confirmed — DllMain executed",
                     i + 1, tidCount, (unsigned long)tids[i]);
            IpcHost_Log("[gui]", logBuf);
            return true;
        }

        char logBuf[128];
        snprintf(logBuf, sizeof(logBuf),
                 "thread %d/%d (TID=%lu) hijacked but DllMain didn't run within 5s, trying next...",
                 i + 1, tidCount, (unsigned long)tids[i]);
        IpcHost_Log("[gui]", logBuf);
    }

    IpcHost_Log("[gui]", "FAIL: all candidate threads failed to execute DllMain");
    return false;
}

/* ======================================================================
 * DLL injection — reflective (manual PE mapping + thread hijacking)
 * ====================================================================== */

bool Ext_InjectDLL(WowSession* s, const char* dllPath)
{
    if (!s || !s->hProcess) return false;

    /* Check if DLL is already active in target process (survives GUI restart) */
    {
        char evtName[80];
        DinkrEvtName((unsigned long)s->pid, evtName, sizeof(evtName));
        HANDLE h = OpenEventA(SYNCHRONIZE, FALSE, evtName);
        if (h) {
            CloseHandle(h);
            IpcHost_LogSession(s, "[gui]", "DLL already active in target (event exists), skipping injection");
            s->alreadyInjected = true;
            return true;
        }
    }

    if (s->alreadyInjected) {
        char evtName[80];
        DinkrEvtName((unsigned long)s->pid, evtName, sizeof(evtName));
        HANDLE h = OpenEventA(SYNCHRONIZE, FALSE, evtName);
        if (h) {
            CloseHandle(h);
            IpcHost_LogSession(s, "[gui]", "WARN: DLL already injected and alive, skipping");
            return true;
        } else {
            IpcHost_LogSession(s, "[gui]", "DLL event missing — previous injection may have failed, retrying");
            s->alreadyInjected = false;
        }
    }

    if (!dllPath || !dllPath[0]) return false;

    /* Read DLL file into local memory */
    size_t dllSize = 0;
    void* dllBuffer = ReadDLLFileExt(dllPath, &dllSize);
    if (!dllBuffer) {
        IpcHost_LogSession(s, "[gui]", "FAIL: could not read DLL file");
        return false;
    }

    char logBuf[256];
    snprintf(logBuf, sizeof(logBuf), "read DLL: %zu bytes", dllSize);
    IpcHost_LogSession(s, "[gui]", logBuf);

    /* Parse PE headers from local buffer (needed for TLS extraction later) */
    auto pDosHdr = (PIMAGE_DOS_HEADER)dllBuffer;
    if (pDosHdr->e_magic != IMAGE_DOS_SIGNATURE) {
        StealthZeroMem(dllBuffer, dllSize);
        VirtualFree(dllBuffer, 0, MEM_RELEASE);
        IpcHost_LogSession(s, "[gui]", "FAIL: invalid DOS signature");
        return false;
    }
    auto pNtHeaders = (PIMAGE_NT_HEADERS)((LPBYTE)dllBuffer + pDosHdr->e_lfanew);
    if (pNtHeaders->Signature != IMAGE_NT_SIGNATURE) {
        StealthZeroMem(dllBuffer, dllSize);
        VirtualFree(dllBuffer, 0, MEM_RELEASE);
        IpcHost_LogSession(s, "[gui]", "FAIL: invalid NT signature");
        return false;
    }

    /* Reflective load: map PE manually into target */
    void* dllBase = ReflectiveLoadDLLExt(s->hProcess, dllBuffer, dllSize);
    if (!dllBase) {
        StealthZeroMem(dllBuffer, dllSize);
        VirtualFree(dllBuffer, 0, MEM_RELEASE);
        IpcHost_LogSession(s, "[gui]", "FAIL: ReflectiveLoadDLL failed");
        return false;
    }

    snprintf(logBuf, sizeof(logBuf), "DLL mapped at %p", dllBase);
    IpcHost_LogSession(s, "[gui]", logBuf);

    /* Execute DllMain via thread hijack */
    char injEvtName[80];
    DinkrEvtName((unsigned long)s->pid, injEvtName, sizeof(injEvtName));
    bool injected = CallDllEntryPointExt(s->hProcess, s->pid, dllBase,
                                         injEvtName,
                                         s->suspendedTIDs, s->suspendedCount);

    /* Zero + free local buffer now that we are done with PE headers */
    StealthZeroMem(dllBuffer, dllSize);
    VirtualFree(dllBuffer, 0, MEM_RELEASE);

    if (!injected) {
        VirtualFreeEx(s->hProcess, dllBase, 0, MEM_RELEASE);
        IpcHost_LogSession(s, "[gui]", "FAIL: CallDllEntryPoint failed (all threads)");
        return false;
    }

    s->alreadyInjected = true;
    IpcHost_LogSession(s, "[gui]", "DLL injected successfully (reflective)");
    return true;
}

/* ======================================================================
 * Dump-DLL injection — reflective load + thread hijack
 *
 * Uses the SAME proven mechanism as Ext_InjectDLL (dinkr.dll):
 *   1. Read DLL file from disk
 *   2. ReflectiveLoadDLLExt — manual PE mapping into target process
 *   3. CallDllEntryPointExt — thread hijack to call _DllMainCRTStartup
 *
 * Confirmation is via a named event (DinkrDumpEvtName) that the dump
 * DLL creates in DllMain, exactly like dinkr.dll uses DinkrEvtName.
 *
 * LoadLibraryA does NOT work here because WoW has process mitigation
 * policies that block loading unsigned DLLs. Reflective loading
 * bypasses the Windows loader entirely.
 * ====================================================================== */
bool Ext_InjectDumpDLL(WowSession* s, const char* dllPath)
{
    if (!s || !s->hProcess) return false;
    if (!dllPath || !dllPath[0]) return false;

    /* Read DLL file into local memory */
    size_t dllSize = 0;
    void* dllBuffer = ReadDLLFileExt(dllPath, &dllSize);
    if (!dllBuffer) {
        IpcHost_LogSession(s, "[dump]", "FAIL: could not read dump DLL file");
        return false;
    }

    {
        char logBuf[256];
        snprintf(logBuf, sizeof(logBuf), "read dump DLL: %zu bytes from %s",
                 dllSize, dllPath);
        IpcHost_LogSession(s, "[dump]", logBuf);
    }

    /* Validate PE headers */
    auto pDosHdr = (PIMAGE_DOS_HEADER)dllBuffer;
    if (pDosHdr->e_magic != IMAGE_DOS_SIGNATURE) {
        StealthZeroMem(dllBuffer, dllSize);
        VirtualFree(dllBuffer, 0, MEM_RELEASE);
        IpcHost_LogSession(s, "[dump]", "FAIL: invalid DOS signature in dump DLL");
        return false;
    }
    auto pNtHeaders = (PIMAGE_NT_HEADERS)((LPBYTE)dllBuffer + pDosHdr->e_lfanew);
    if (pNtHeaders->Signature != IMAGE_NT_SIGNATURE) {
        StealthZeroMem(dllBuffer, dllSize);
        VirtualFree(dllBuffer, 0, MEM_RELEASE);
        IpcHost_LogSession(s, "[dump]", "FAIL: invalid NT signature in dump DLL");
        return false;
    }

    /* Reflective load: map PE manually into target */
    void* dllBase = ReflectiveLoadDLLExt(s->hProcess, dllBuffer, dllSize);
    if (!dllBase) {
        StealthZeroMem(dllBuffer, dllSize);
        VirtualFree(dllBuffer, 0, MEM_RELEASE);
        IpcHost_LogSession(s, "[dump]", "FAIL: ReflectiveLoadDLL for dump DLL");
        return false;
    }

    {
        char logBuf[256];
        snprintf(logBuf, sizeof(logBuf), "dump DLL mapped at %p", dllBase);
        IpcHost_LogSession(s, "[dump]", logBuf);
    }

    /* Execute DllMain via thread hijack — same mechanism as dinkr.dll.
     * Confirmation event: DinkrDumpEvtName (created by dump DLL in DllMain). */
    char dumpEvtName[80];
    DinkrDumpEvtName((unsigned long)s->pid, dumpEvtName, sizeof(dumpEvtName));

    bool injected = CallDllEntryPointExt(s->hProcess, s->pid, dllBase,
                                         dumpEvtName,
                                         s->suspendedTIDs, s->suspendedCount);

    /* Zero + free local buffer */
    StealthZeroMem(dllBuffer, dllSize);
    VirtualFree(dllBuffer, 0, MEM_RELEASE);

    if (!injected) {
        VirtualFreeEx(s->hProcess, dllBase, 0, MEM_RELEASE);
        IpcHost_LogSession(s, "[dump]", "FAIL: thread hijack failed for dump DLL (all threads)");
        return false;
    }

    IpcHost_LogSession(s, "[dump]", "dump DLL injected successfully (reflective + thread hijack)");
    return true;
}