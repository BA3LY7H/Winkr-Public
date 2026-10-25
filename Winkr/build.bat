@echo off
setlocal enabledelayedexpansion

set "FAIL=0"
set "OBJ=build\obj"
set "CXXFLAGS=-w -O2 -DNDEBUG -std=c++17 -Ishared -Ivendor/imgui -Ivendor/imgui/backends"
set "GUI_CXXFLAGS=-Wall -O2 -DNDEBUG -std=c++17 -Ishared -Igui -Ivendor/imgui -Ivendor/imgui/backends"
set "CFLAGS=-Wall -O2 -DNDEBUG -Ishared -Idll"
rem Detour: no exceptions/RTTI keeps the injected DLL free of the C++ unwinder.
set "NAVFLAGS=-w -O2 -DNDEBUG -DDT_POLYREF64 -std=c++17 -fno-exceptions -fno-rtti -Ishared -Idll -Ivendor/detour/Include -Ivendor/recast/Include"

if not exist build mkdir build
if not exist %OBJ% mkdir %OBJ%

if "%1"=="clean" (
    echo === Cleaning ===
    if exist %OBJ% rd /s /q %OBJ%
    if exist build\dinkr.exe del build\dinkr.exe
    if exist build\dinkr.dll del build\dinkr.dll
    if exist build\dinkr_dump.dll del build\dinkr_dump.dll
    echo Clean complete.
    exit /b 0
)

echo.
echo ============================================
echo   DINKR Release Build
echo ============================================

rem ---- ImGui (7 files) ----
echo.
echo   [1/7] ImGui ...
g++ %CXXFLAGS% -c -o %OBJ%/imgui.o vendor/imgui/imgui.cpp || set "FAIL=1"
g++ %CXXFLAGS% -c -o %OBJ%/imgui_draw.o vendor/imgui/imgui_draw.cpp || set "FAIL=1"
g++ %CXXFLAGS% -c -o %OBJ%/imgui_tables.o vendor/imgui/imgui_tables.cpp || set "FAIL=1"
g++ %CXXFLAGS% -c -o %OBJ%/imgui_widgets.o vendor/imgui/imgui_widgets.cpp || set "FAIL=1"
g++ %CXXFLAGS% -c -o %OBJ%/imgui_demo.o vendor/imgui/imgui_demo.cpp || set "FAIL=1"
g++ %CXXFLAGS% -c -o %OBJ%/imgui_impl_win32.o vendor/imgui/backends/imgui_impl_win32.cpp || set "FAIL=1"
g++ %CXXFLAGS% -c -o %OBJ%/imgui_impl_dx11.o vendor/imgui/backends/imgui_impl_dx11.cpp || set "FAIL=1"

rem ---- GUI (10 files) ----
echo   [2/7] GUI ...
g++ %GUI_CXXFLAGS% -c -o %OBJ%/gui_main.o gui/app/gui_main.cpp || set "FAIL=1"
g++ %GUI_CXXFLAGS% -c -o %OBJ%/gui_crash.o gui/app/gui_crash.cpp || set "FAIL=1"
g++ %GUI_CXXFLAGS% -c -o %OBJ%/gui_worker.o gui/app/gui_worker.cpp || set "FAIL=1"
g++ %GUI_CXXFLAGS% -c -o %OBJ%/gui_theme.o gui/app/gui_theme.cpp || set "FAIL=1"
g++ %GUI_CXXFLAGS% -c -o %OBJ%/gui_render.o gui/render/gui_render.cpp || set "FAIL=1"
g++ %GUI_CXXFLAGS% -c -o %OBJ%/gui_external.o gui/process/gui_external.cpp || set "FAIL=1"
g++ %GUI_CXXFLAGS% -c -o %OBJ%/gui_injection.o gui/injection/gui_injection.cpp || set "FAIL=1"
g++ %GUI_CXXFLAGS% -c -o %OBJ%/gui_warden.o gui/injection/gui_warden.cpp || set "FAIL=1"
g++ %GUI_CXXFLAGS% -c -o %OBJ%/gui_ipc_host.o gui/ipc/gui_ipc_host.cpp || set "FAIL=1"
g++ %GUI_CXXFLAGS% -c -o %OBJ%/gui_dump.o gui/process/gui_dump.cpp || set "FAIL=1"

rem ---- DLL (14 files) ----
echo   [3/7] DLL ...
gcc -w -O2 -DNDEBUG -Ishared -Ivendor/lua/src -c -o %OBJ%/dll_wk_luaall.o dll/wk_luaall.c || set "FAIL=1"
gcc %CFLAGS% -c -o %OBJ%/dll_dinkr_ipc.o dll/ipc/dinkr_ipc.c || set "FAIL=1"
gcc %CFLAGS% -c -o %OBJ%/dll_dinkr_om.o dll/om/dinkr_om.c || set "FAIL=1"
gcc %CFLAGS% -c -o %OBJ%/dll_dinkr_stealth.o dll/security/dinkr_stealth.c || set "FAIL=1"
gcc %CFLAGS% -c -o %OBJ%/dll_dinkr_security.o dll/security/dinkr_security.c || set "FAIL=1"
gcc %CFLAGS% -Ivendor/lua/src -c -o %OBJ%/dll_dinkr_bridge_core.o dll/bridge/dinkr_bridge_core.c || set "FAIL=1"
gcc %CFLAGS% -Ivendor/lua/src -c -o %OBJ%/dll_dinkr_bridge_camera.o dll/bridge/dinkr_bridge_camera.c || set "FAIL=1"
gcc %CFLAGS% -Ivendor/lua/src -c -o %OBJ%/dll_dinkr_bridge_objects.o dll/bridge/dinkr_bridge_objects.c || set "FAIL=1"
gcc %CFLAGS% -Ivendor/lua/src -c -o %OBJ%/dll_dinkr_bridge_combat.o dll/bridge/dinkr_bridge_combat.c || set "FAIL=1"
gcc %CFLAGS% -Ivendor/lua/src -c -o %OBJ%/dll_dinkr_bridge_actions.o dll/bridge/dinkr_bridge_actions.c || set "FAIL=1"
gcc %CFLAGS% -Ivendor/lua/src -c -o %OBJ%/dll_dinkr_bridge_misc.o dll/bridge/dinkr_bridge_misc.c || set "FAIL=1"
gcc %CFLAGS% -c -o %OBJ%/dll_dinkr_om_enum.o dll/om/dinkr_om_enum.c || set "FAIL=1"
gcc %CFLAGS% -Ivendor/lua/src -c -o %OBJ%/dll_dinkr_mods.o dll/mods/dinkr_mods.c || set "FAIL=1"
gcc %CFLAGS% -Ivendor/lua/src -c -o %OBJ%/dll_dinkr_payload.o dll/core/dinkr_payload.c || set "FAIL=1"
gcc %CFLAGS% -c -o %OBJ%/dll_dinkr_scanner.o dll/core/dinkr_scanner.c || set "FAIL=1"
gcc %CFLAGS% -Ivendor/lua/src -c -o %OBJ%/dll_dinkr_selfheal.o dll/core/dinkr_selfheal.c || set "FAIL=1"
gcc %CFLAGS% -Ivendor/lua/src -Idll/nav -c -o %OBJ%/dll_dinkr_bridge_nav.o dll/bridge/dinkr_bridge_nav.c || set "FAIL=1"

rem ---- Detour navmesh (C++; DT_POLYREF64 required for maxTiles/maxPolys budget) ----
echo   [3b/7] Detour navmesh ...
gcc %NAVFLAGS% -c -o %OBJ%/dt_alloc.o vendor/detour/Source/DetourAlloc.cpp || set "FAIL=1"
gcc %NAVFLAGS% -c -o %OBJ%/dt_assert.o vendor/detour/Source/DetourAssert.cpp || set "FAIL=1"
gcc %NAVFLAGS% -c -o %OBJ%/dt_common.o vendor/detour/Source/DetourCommon.cpp || set "FAIL=1"
gcc %NAVFLAGS% -c -o %OBJ%/dt_navmesh.o vendor/detour/Source/DetourNavMesh.cpp || set "FAIL=1"
gcc %NAVFLAGS% -c -o %OBJ%/dt_navmeshbuilder.o vendor/detour/Source/DetourNavMeshBuilder.cpp || set "FAIL=1"
gcc %NAVFLAGS% -c -o %OBJ%/dt_navmeshquery.o vendor/detour/Source/DetourNavMeshQuery.cpp || set "FAIL=1"
gcc %NAVFLAGS% -c -o %OBJ%/dt_node.o vendor/detour/Source/DetourNode.cpp || set "FAIL=1"
gcc %NAVFLAGS% -Idll/nav -c -o %OBJ%/dll_dinkr_nav.o dll/nav/dinkr_nav.cpp || set "FAIL=1"

rem ---- Recast (navmesh GENERATION -- LiveMesh bakes tiles at runtime) ----
gcc %NAVFLAGS% -c -o %OBJ%/rc_Recast.o vendor/recast/Source/Recast.cpp || set "FAIL=1"
gcc %NAVFLAGS% -c -o %OBJ%/rc_RecastAlloc.o vendor/recast/Source/RecastAlloc.cpp || set "FAIL=1"
gcc %NAVFLAGS% -c -o %OBJ%/rc_RecastArea.o vendor/recast/Source/RecastArea.cpp || set "FAIL=1"
gcc %NAVFLAGS% -c -o %OBJ%/rc_RecastAssert.o vendor/recast/Source/RecastAssert.cpp || set "FAIL=1"
gcc %NAVFLAGS% -c -o %OBJ%/rc_RecastContour.o vendor/recast/Source/RecastContour.cpp || set "FAIL=1"
gcc %NAVFLAGS% -c -o %OBJ%/rc_RecastFilter.o vendor/recast/Source/RecastFilter.cpp || set "FAIL=1"
gcc %NAVFLAGS% -c -o %OBJ%/rc_RecastLayers.o vendor/recast/Source/RecastLayers.cpp || set "FAIL=1"
gcc %NAVFLAGS% -c -o %OBJ%/rc_RecastMesh.o vendor/recast/Source/RecastMesh.cpp || set "FAIL=1"
gcc %NAVFLAGS% -c -o %OBJ%/rc_RecastMeshDetail.o vendor/recast/Source/RecastMeshDetail.cpp || set "FAIL=1"
gcc %NAVFLAGS% -c -o %OBJ%/rc_RecastRasterization.o vendor/recast/Source/RecastRasterization.cpp || set "FAIL=1"
gcc %NAVFLAGS% -c -o %OBJ%/rc_RecastRegion.o vendor/recast/Source/RecastRegion.cpp || set "FAIL=1"
gcc %NAVFLAGS% -Idll/nav -c -o %OBJ%/dll_dinkr_livemesh.o dll/nav/dinkr_livemesh.cpp || set "FAIL=1"

rem ---- Resource ----
echo   [4/7] Resource ...
windres gui/assets/dinkr.rc -o %OBJ%/dinkr_res.o || set "FAIL=1"

if "!FAIL!"=="1" (
    echo.
    echo *** COMPILE FAILED — see errors above ***
    exit /b 1
)

rem ---- Link GUI (-s strips symbols for release) ----
echo   [5/7] Linking dinkr.exe ...
g++ -static -s -o build/dinkr.exe %OBJ%/imgui.o %OBJ%/imgui_draw.o %OBJ%/imgui_tables.o %OBJ%/imgui_widgets.o %OBJ%/imgui_demo.o %OBJ%/imgui_impl_win32.o %OBJ%/imgui_impl_dx11.o %OBJ%/gui_main.o %OBJ%/gui_crash.o %OBJ%/gui_worker.o %OBJ%/gui_theme.o %OBJ%/gui_render.o %OBJ%/gui_external.o %OBJ%/gui_injection.o %OBJ%/gui_warden.o %OBJ%/gui_ipc_host.o %OBJ%/gui_dump.o %OBJ%/dinkr_res.o -ld3d11 -ldxgi -ld3dcompiler -ldwmapi -lgdi32 -luser32 -lshell32 -lole32 -lpsapi -lntdll -lversion -mwindows
if errorlevel 1 (
    echo *** GUI LINK FAILED ***
    exit /b 1
)

rem ---- Link DLL (-s strips symbols for release) ----
echo   [6/7] Linking dinkr.dll ...
g++ -shared -static -s -o build/dinkr.dll %OBJ%/dll_dinkr_payload.o %OBJ%/dll_wk_luaall.o %OBJ%/dll_dinkr_ipc.o %OBJ%/dll_dinkr_om.o %OBJ%/dll_dinkr_stealth.o %OBJ%/dll_dinkr_security.o %OBJ%/dll_dinkr_bridge_core.o %OBJ%/dll_dinkr_bridge_camera.o %OBJ%/dll_dinkr_bridge_objects.o %OBJ%/dll_dinkr_bridge_combat.o %OBJ%/dll_dinkr_bridge_actions.o %OBJ%/dll_dinkr_bridge_misc.o %OBJ%/dll_dinkr_bridge_nav.o %OBJ%/dll_dinkr_om_enum.o %OBJ%/dll_dinkr_mods.o %OBJ%/dll_dinkr_scanner.o %OBJ%/dll_dinkr_selfheal.o %OBJ%/dll_dinkr_nav.o %OBJ%/dll_dinkr_livemesh.o %OBJ%/rc_Recast.o %OBJ%/rc_RecastAlloc.o %OBJ%/rc_RecastArea.o %OBJ%/rc_RecastAssert.o %OBJ%/rc_RecastContour.o %OBJ%/rc_RecastFilter.o %OBJ%/rc_RecastLayers.o %OBJ%/rc_RecastMesh.o %OBJ%/rc_RecastMeshDetail.o %OBJ%/rc_RecastRasterization.o %OBJ%/rc_RecastRegion.o %OBJ%/dt_alloc.o %OBJ%/dt_assert.o %OBJ%/dt_common.o %OBJ%/dt_navmesh.o %OBJ%/dt_navmeshbuilder.o %OBJ%/dt_navmeshquery.o %OBJ%/dt_node.o -Wl,-e,DinkrDllEntry -lkernel32 -lpsapi -lversion -lwinmm
if errorlevel 1 (
    echo *** DLL LINK FAILED ***
    exit /b 1
)

rem ---- Dump DLL (1 file) ----
echo   [7/7] Dump DLL ...
gcc %CFLAGS% -shared -static -s -o build/dinkr_dump.dll dll/dump/dinkr_dump.c -lkernel32 -lpsapi -lversion
if errorlevel 1 (
    echo *** DUMP DLL LINK FAILED ***
    exit /b 1
)

echo.
echo ============================================
echo   BUILD SUCCESS
echo   GUI:  build\dinkr.exe
echo   DLL:  build\dinkr.dll
echo   DUMP: build\dinkr_dump.dll
echo ============================================
