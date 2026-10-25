/*
 * gui_main.cpp — DINKR GUI Application entry point
 *
 * Win32 + DirectX 11 + Dear ImGui
 * Architecture v2: GUI creates IPC, runs background worker thread
 * for external process operations (attach, patch, OM, watchdog).
 *
 * Compiled with GCC (MinGW-w64):
 *   g++ -O2 -std=c++17 -o dinkr_gui.exe ...
 */

#define WIN32_LEAN_AND_MEAN
#define INITGUID                        /* make DEFINE_GUID emit definitions  */
#include <windows.h>
#include <dwmapi.h>
#include <d3d11.h>
#include <dxgi.h>
#include <tlhelp32.h>
#include <cstdio>
#include <cstdarg>
#include <vector>

#include "imgui.h"
#include "imgui_impl_win32.h"
#include "imgui_impl_dx11.h"
#include "assets/dinkr_font_data.h"

#include "gui_render.h"
#include "gui_external.h"
#include "gui_ipc_host.h"
#include "ipc_protocol.h"

#include "gui_crash.h"
#include "gui_worker.h"
#include "gui_theme.h"

/* Thread-local ImGui context pointer (defined once, declared in imconfig.h) */
thread_local ImGuiContext* MyImGuiTLS = nullptr;

/* ======================================================================
 * Forward declarations
 * ====================================================================== */

static bool CreateDeviceD3D(HWND hWnd);
static void CleanupDeviceD3D();
static void CreateRenderTarget();
static void CleanupRenderTarget();
LRESULT WINAPI WndProc(HWND hWnd, UINT msg, WPARAM wParam, LPARAM lParam);

/* ImGui Win32 backend WndProc handler (defined in imgui_impl_win32.cpp) */
extern IMGUI_IMPL_API LRESULT ImGui_ImplWin32_WndProcHandler(
    HWND hWnd, UINT msg, WPARAM wParam, LPARAM lParam);

/* ======================================================================
 * Globals
 * ====================================================================== */

static ID3D11Device*            g_pd3dDevice          = nullptr;
static ID3D11DeviceContext*     g_pd3dDeviceContext    = nullptr;
static IDXGISwapChain*          g_pSwapChain          = nullptr;
static ID3D11RenderTargetView*  g_mainRenderTargetView = nullptr;

/* IPC shared memory — no longer singleton; per-session */

/* Background worker — now per-session */

/* Session manager state */
static std::vector<WowSession*> g_sessions;
static WowSession*              g_activeSession  = nullptr;
volatile LONG                   g_appRunning     = 1;
static DWORD                    g_lastScanTick   = 0;
static int                      g_nextIndex      = 1;

/* ======================================================================
 * D3D11 helpers
 * ====================================================================== */

static bool CreateDeviceD3D(HWND hWnd)
{
    DXGI_SWAP_CHAIN_DESC sd = {};
    sd.BufferCount                        = 2;
    sd.BufferDesc.Width                   = 0;
    sd.BufferDesc.Height                  = 0;
    sd.BufferDesc.Format                  = DXGI_FORMAT_R8G8B8A8_UNORM;
    sd.BufferDesc.RefreshRate.Numerator   = 60;
    sd.BufferDesc.RefreshRate.Denominator = 1;
    sd.Flags            = DXGI_SWAP_CHAIN_FLAG_ALLOW_MODE_SWITCH;
    sd.BufferUsage      = DXGI_USAGE_RENDER_TARGET_OUTPUT;
    sd.OutputWindow     = hWnd;
    sd.SampleDesc.Count = 1;
    sd.SampleDesc.Quality = 0;
    sd.Windowed         = TRUE;
    sd.SwapEffect       = DXGI_SWAP_EFFECT_DISCARD;

    D3D_FEATURE_LEVEL featureLevel;
    const D3D_FEATURE_LEVEL levels[] = { D3D_FEATURE_LEVEL_11_0, D3D_FEATURE_LEVEL_10_0 };

    HRESULT hr = D3D11CreateDeviceAndSwapChain(
        nullptr, D3D_DRIVER_TYPE_HARDWARE, nullptr,
        0 /* flags */,
        levels, 2,
        D3D11_SDK_VERSION,
        &sd,
        &g_pSwapChain,
        &g_pd3dDevice,
        &featureLevel,
        &g_pd3dDeviceContext);

    if (FAILED(hr)) return false;

    CreateRenderTarget();
    return true;
}

static void CreateRenderTarget()
{
    ID3D11Texture2D* pBackBuffer = nullptr;
    g_pSwapChain->GetBuffer(0, __uuidof(ID3D11Texture2D), (void**)&pBackBuffer);
    if (pBackBuffer) {
        g_pd3dDevice->CreateRenderTargetView(pBackBuffer, nullptr, &g_mainRenderTargetView);
        pBackBuffer->Release();
    }
}

static void CleanupRenderTarget()
{
    if (g_mainRenderTargetView) {
        g_mainRenderTargetView->Release();
        g_mainRenderTargetView = nullptr;
    }
}

static void CleanupDeviceD3D()
{
    CleanupRenderTarget();
    if (g_pSwapChain)        { g_pSwapChain->Release();        g_pSwapChain = nullptr; }
    if (g_pd3dDeviceContext) { g_pd3dDeviceContext->Release(); g_pd3dDeviceContext = nullptr; }
    if (g_pd3dDevice)        { g_pd3dDevice->Release();        g_pd3dDevice = nullptr; }
}

/* ======================================================================
 * WndProc
 * ====================================================================== */

LRESULT WINAPI WndProc(HWND hWnd, UINT msg, WPARAM wParam, LPARAM lParam)
{
    if (ImGui_ImplWin32_WndProcHandler(hWnd, msg, wParam, lParam))
        return true;

    switch (msg) {
    case WM_SIZE:
        if (g_pd3dDevice && wParam != SIZE_MINIMIZED) {
            CleanupRenderTarget();
            g_pSwapChain->ResizeBuffers(
                0, (UINT)LOWORD(lParam), (UINT)HIWORD(lParam),
                DXGI_FORMAT_UNKNOWN, 0);
            CreateRenderTarget();
        }
        return 0;
    case WM_SYSCOMMAND:
        if ((wParam & 0xfff0) == SC_KEYMENU) return 0;  /* disable ALT menu */
        break;
    case WM_DESTROY:
        PostQuitMessage(0);
        return 0;
    }
    return DefWindowProcW(hWnd, msg, wParam, lParam);
}

/* ======================================================================
 * WinMain
 * ====================================================================== */

int WINAPI WinMain(HINSTANCE hInstance, HINSTANCE /*hPrevInstance*/,
                   LPSTR /*lpCmdLine*/, int nCmdShow)
{
    /* ---- Install crash handler for diagnostics ---- */
    SetUnhandledExceptionFilter(CrashHandler);

    /* ---- Initialize NtDLL (global, once) ---- */
    if (!Ext_InitNtdll()) {
        MessageBoxA(nullptr, "Failed to initialize NtDLL functions.", "DINKR", MB_ICONERROR);
        return 1;
    }

    CreateDirectoryA("C:\\mods", NULL);

    /* ---- Session manager will start per-process threads dynamically ---- */
    g_appRunning = 1;

    /* ---- Register window class ---- */
    WNDCLASSEXW wc = {};
    wc.cbSize        = sizeof(wc);
    wc.style         = CS_CLASSDC;
    wc.lpfnWndProc   = WndProc;
    wc.hInstance     = hInstance;
    wc.hCursor       = LoadCursor(nullptr, IDC_ARROW);
    wc.hIcon         = (HICON)LoadImageA(hInstance, "IDI_APPICON", IMAGE_ICON, 0, 0, LR_DEFAULTSIZE);
    wc.hIconSm       = (HICON)LoadImageA(hInstance, "IDI_APPICON", IMAGE_ICON, 16, 16, LR_DEFAULTSIZE);
    wc.lpszClassName = L"DinkrWindow";
    RegisterClassExW(&wc);

    /* ---- Create window ---- */
    HWND hwnd = CreateWindowW(
        L"DinkrWindow",
        L"DINKR",
        WS_OVERLAPPEDWINDOW,
        100, 100, 900, 800,
        nullptr, nullptr, hInstance, nullptr);

    /* ---- Init Direct3D ---- */
    if (!CreateDeviceD3D(hwnd)) {
        CleanupDeviceD3D();
        UnregisterClassW(L"DinkrWindow", hInstance);
        g_appRunning = 0;
        return 1;
    }

    /* Dark title bar (Windows 10 1809+ / Windows 11) */
    BOOL useDarkMode = TRUE;
    DwmSetWindowAttribute(hwnd, 20 /* DWMWA_USE_IMMERSIVE_DARK_MODE */, &useDarkMode, sizeof(useDarkMode));

    ShowWindow(hwnd, nCmdShow);
    UpdateWindow(hwnd);

    /* ---- Init ImGui ---- */
    IMGUI_CHECKVERSION();
    ImGui::CreateContext();

    ImGuiIO& io = ImGui::GetIO();
    io.ConfigFlags |= ImGuiConfigFlags_NavEnableKeyboard;
    io.IniFilename = nullptr;  /* disable imgui.ini persistence (stale column order) */

    /* Load embedded FiraSans font (baked into exe at compile time) */
    ImFontConfig fontCfg;
    fontCfg.OversampleH = 3;
    fontCfg.OversampleV = 2;
    fontCfg.PixelSnapH  = true;
    fontCfg.RasterizerDensity = 1.0f;
    fontCfg.FontDataOwnedByAtlas = false;  /* we own the static data */
    ImFont* font = io.Fonts->AddFontFromMemoryTTF(
        (void*)dinkr_font_data, dinkr_font_size, 18.0f, &fontCfg);
    (void)font;  /* ImGui uses it as default automatically */

    SetupImGuiStyle();

    ImGui_ImplWin32_Init(hwnd);
    ImGui_ImplDX11_Init(g_pd3dDevice, g_pd3dDeviceContext);

    /* ---- Init render state ---- */
    InitRenderState();

    /* ---- Main loop ---- */
    bool done = false;
    while (!done) {
        MSG msg;
        while (PeekMessage(&msg, nullptr, 0U, 0U, PM_REMOVE)) {
            TranslateMessage(&msg);
            DispatchMessage(&msg);
            if (msg.message == WM_QUIT) done = true;
        }
        if (done) break;

        if (!g_pd3dDevice || !g_pd3dDeviceContext || !g_pSwapChain || !g_mainRenderTargetView) {
            Sleep(100);
            continue;
        }

        /* ---- Session scanning (every 3s) ---- */
        {
            DWORD now = GetTickCount();
            if (now - g_lastScanTick >= 3000) {
                g_lastScanTick = now;

                DWORD pids[32];
                int found = Ext_ScanWowProcesses(pids, 32);

                for (int i = 0; i < found; i++) {
                    /* Check if we already have a session for this PID */
                    bool exists = false;
                    for (auto* s : g_sessions) {
                        if (s->pid == pids[i]) { exists = true; break; }
                    }
                    if (exists) continue;

                    /* New process — create session */
                    WowSession* s = Session_Create(pids[i], g_nextIndex++);
                    if (!s) continue;

                    s->hWorkerThread = CreateThread(nullptr, 0,
                        SessionWorkerThread, s, 0, nullptr);

                    g_sessions.push_back(s);

                    char buf[128];
                    snprintf(buf, sizeof(buf), "new session: PID %lu (#%d)",
                             (unsigned long)pids[i], s->index);
                    IpcHost_Log("[gui]", buf);

                    if (!g_activeSession)
                        g_activeSession = s;
                }
            }
        }

        /* ---- ImGui frame ---- */
        ImGui_ImplDX11_NewFrame();
        ImGui_ImplWin32_NewFrame();
        ImGui::NewFrame();

        /* ---- Tab bar (if multiple sessions) ---- */
        if (!g_sessions.empty()) {
            ImGuiIO& io2 = ImGui::GetIO();
            ImGui::SetNextWindowPos(ImVec2(0, 0));
            ImGui::SetNextWindowSize(io2.DisplaySize);

            ImGuiWindowFlags rootFlags =
                ImGuiWindowFlags_NoTitleBar | ImGuiWindowFlags_NoResize |
                ImGuiWindowFlags_NoMove | ImGuiWindowFlags_NoBringToFrontOnFocus |
                ImGuiWindowFlags_NoNavFocus | ImGuiWindowFlags_NoScrollbar |
                ImGuiWindowFlags_NoScrollWithMouse;

            ImGui::Begin("##Root", nullptr, rootFlags);

            if (g_sessions.size() > 1 && ImGui::BeginTabBar("##SessionTabs")) {
                for (int si = 0; si < (int)g_sessions.size(); si++) {
                    WowSession* s = g_sessions[si];

                    /* Dead tab: reddish styling */
                    bool dead = !s->alive;
                    if (dead)
                        ImGui::PushStyleColor(ImGuiCol_Tab, ImVec4(0.5f, 0.15f, 0.15f, 1.0f));

                    char tabLabel[64];
                    snprintf(tabLabel, sizeof(tabLabel), "WoW #%d (%lu)%s###tab%d",
                             s->index, (unsigned long)s->pid,
                             dead ? " [DEAD]" : "", s->index);

                    bool open = true;
                    ImGuiTabItemFlags flags = 0;

                    if (ImGui::BeginTabItem(tabLabel, &open, flags)) {
                        g_activeSession = s;
                        ImGui::EndTabItem();
                    }

                    if (dead)
                        ImGui::PopStyleColor();

                    /* User closed tab */
                    if (!open) {
                        s->userClosed = true;
                        InterlockedExchange(&s->running, 0);
                        if (s->hWorkerThread) {
                            WaitForSingleObject(s->hWorkerThread, 3000);
                            CloseHandle(s->hWorkerThread);
                            s->hWorkerThread = NULL;
                        }
                        IpcHost_DestroyForSession(s);
                        Ext_DetachSession(s);
                        Session_Destroy(s);
                        g_sessions.erase(g_sessions.begin() + si);
                        si--;
                        if (g_activeSession == s) {
                            g_activeSession = g_sessions.empty() ? nullptr : g_sessions[0];
                        }
                        continue;
                    }
                }
                ImGui::EndTabBar();
            }

            /* Render active session content */
            if (g_activeSession) {
                RenderUI(g_activeSession);
            } else {
                ImGui::TextDisabled("Scanning for WoW processes...");
            }

            ImGui::End();
        } else {
            /* No sessions yet — show waiting screen */
            ImGuiIO& io2 = ImGui::GetIO();
            ImGui::SetNextWindowPos(ImVec2(0, 0));
            ImGui::SetNextWindowSize(io2.DisplaySize);
            ImGui::Begin("##WaitRoot", nullptr,
                ImGuiWindowFlags_NoTitleBar | ImGuiWindowFlags_NoResize |
                ImGuiWindowFlags_NoMove);
            ImGui::TextDisabled("Scanning for WoW processes...");
            ImGui::End();
        }

        /* Present */
        ImGui::Render();
        const float clear[4] = { 0.067f, 0.067f, 0.082f, 1.00f };
        g_pd3dDeviceContext->OMSetRenderTargets(1, &g_mainRenderTargetView, nullptr);
        g_pd3dDeviceContext->ClearRenderTargetView(g_mainRenderTargetView, clear);
        ImGui_ImplDX11_RenderDrawData(ImGui::GetDrawData());

        HRESULT hr = g_pSwapChain->Present(1, 0);  /* VSync on */
        if (hr == DXGI_ERROR_DEVICE_REMOVED || hr == DXGI_ERROR_DEVICE_RESET) {
            /* GPU device lost — rebuild everything */
            IpcHost_Log("[gui]", "D3D11 device lost, rebuilding...");
            CleanupRenderTarget();
            CleanupDeviceD3D();
            if (!CreateDeviceD3D(hwnd)) {
                IpcHost_Log("[gui]", "FATAL: D3D11 device rebuild failed");
                done = true;
                break;
            }
            ImGui_ImplDX11_Shutdown();
            ImGui_ImplDX11_Init(g_pd3dDevice, g_pd3dDeviceContext);
            IpcHost_Log("[gui]", "D3D11 device recovered");
            continue;  /* skip this frame, re-render next */
        }
    }

    /* ---- Cleanup ---- */
    g_appRunning = 0;

    /* Stop all session worker threads */
    for (auto* s : g_sessions) {
        InterlockedExchange(&s->running, 0);
    }
    for (auto* s : g_sessions) {
        if (s->hWorkerThread) {
            WaitForSingleObject(s->hWorkerThread, 5000);
            CloseHandle(s->hWorkerThread);
            s->hWorkerThread = NULL;
        }
        IpcHost_DestroyForSession(s);
        Ext_DetachSession(s);
        Session_Destroy(s);
    }
    g_sessions.clear();
    g_activeSession = nullptr;

    CleanupRenderState();
    ImGui_ImplDX11_Shutdown();
    ImGui_ImplWin32_Shutdown();
    ImGui::DestroyContext();
    CleanupDeviceD3D();
    DestroyWindow(hwnd);
    UnregisterClassW(L"DinkrWindow", hInstance);

    return 0;
}
