@echo off
setlocal EnableDelayedExpansion
REM ============================================================================
REM link.bat -- junction the repo into the places the loader and the game read
REM             from. Two different shapes on purpose:
REM
REM   projects\        ->  C:\projects                     (ROOT link, one junction)
REM   Addons\<name>    ->  <WoW>\...\Interface\AddOns\<name>   (one per folder)
REM
REM Why the difference: C:\projects belongs entirely to this project, so the
REM whole folder is linked and the DLL's runtime output (livemesh\, navmesh\,
REM dinkr_*.txt, taco_settings.lua) lands in projects\ and is gitignored there.
REM AddOns is NOT ours -- Questie, Prat, BugSack and friends live alongside ours
REM -- so root linking it would delete them. Only our own addon folders are linked.
REM
REM Junctions rather than symlinks on purpose: no admin rights needed, and they
REM work across drive letters (C: -> E:).
REM
REM Usage:  link.bat                                use the default WoW path
REM         link.bat "D:\Games\World of Warcraft"   use a different install
REM ============================================================================

set "REPO=%~dp0"
if "%REPO:~-1%"=="\" set "REPO=%REPO:~0,-1%"

set "PROJECTS=C:\projects"
set "WOW=E:\Games\World of Warcraft"
if not "%~1"=="" set "WOW=%~1"
set "ADDONS=%WOW%\_classic_era_\Interface\AddOns"

REM Addon folders that must NEVER be junctioned. RXPGuides is a paid RestedXP
REM product managed by its own updater, and that updater replaces the addon
REM folder wholesale -- which silently destroys a junction and leaves a stale
REM copy behind. See the note at Addons/RXPGuides/ in .gitignore.
set "ADDON_SKIP=RXPGuides"

echo repo     : %REPO%
echo projects : %PROJECTS%
echo addons   : %ADDONS%
echo.

if not exist "%ADDONS%" (
    echo !! AddOns folder not found: %ADDONS%
    echo    pass your WoW folder as an argument, e.g.
    echo        link.bat "D:\Games\World of Warcraft"
    exit /b 1
)

set /a made=0, skipped=0

echo === projects ^(root^) ===
call :link "%REPO%\projects" "%PROJECTS%"
echo.
echo === addons ===
for /d %%D in ("%REPO%\Addons\*") do call :addon "%%~fD" "%%~nxD"

echo.
echo %made% linked, %skipped% skipped
if %skipped% gtr 0 echo move or delete the skipped folders yourself, then run this again.
exit /b 0

REM --------------------------------------------------------------------------
REM :addon <folder-in-repo> <name>   honour the skip list, then link
:addon
for %%S in (%ADDON_SKIP%) do if /i "%%S"=="%~2" (
    echo   skip  %~2  -- managed by its own updater, never junction
    exit /b 0
)
call :link "%~1" "%ADDONS%\%~2"
exit /b 0

REM --------------------------------------------------------------------------
REM :link <folder-in-repo> <destination>
REM Re-links unconditionally: rmdir on a junction removes the link only, so the
REM repo copy on the other side is never touched.
:link
set "SRC=%~1"
set "DST=%~2"
set "NAME=%~nx2"

if exist "%DST%" (
    call :islink "%DST%"
    if errorlevel 1 (
        echo   SKIP  %NAME%  -- a real folder is already there
        set /a skipped+=1
        exit /b 0
    )
    rmdir "%DST%"
    if exist "%DST%" (
        echo   FAIL  %NAME%  -- could not remove the old link
        set /a skipped+=1
        exit /b 0
    )
)

mklink /J "%DST%" "%SRC%" >nul
if errorlevel 1 (
    echo   FAIL  %NAME%
    set /a skipped+=1
    exit /b 0
)
echo   link  %NAME%
set /a made+=1
exit /b 0

REM --------------------------------------------------------------------------
REM :islink <path>   exits 0 when the path is a reparse point, 1 when it is a
REM                  real directory.
:islink
dir /a:l /b "%~dp1." 2>nul | findstr /x /i /c:"%~nx1" >nul
exit /b %errorlevel%
