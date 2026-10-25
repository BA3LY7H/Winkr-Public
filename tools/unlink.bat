@echo off
setlocal EnableDelayedExpansion
REM ============================================================================
REM unlink.bat -- remove the junctions link.bat created: the C:\projects root link
REM               and our own folders under AddOns.
REM
REM Only reparse points are removed, and only with plain `rmdir`, which deletes
REM the link and nothing else. A real folder at one of these paths is left
REM completely alone.
REM
REM   NEVER use `rmdir /s` or PowerShell's `Remove-Item -Recurse` on a junction:
REM   they follow the link and delete the repo's files on the other side.
REM
REM After this runs, the DLL's runtime output has nowhere to go until you link
REM again -- it writes to C:\projects unconditionally and will recreate it as a
REM plain folder on the next injection.
REM
REM Usage:  unlink.bat                                use the default WoW path
REM         unlink.bat "D:\Games\World of Warcraft"   use a different install
REM ============================================================================

set "REPO=%~dp0"
if "%REPO:~-1%"=="\" set "REPO=%REPO:~0,-1%"

set "PROJECTS=C:\projects"
set "WOW=E:\Games\World of Warcraft"
if not "%~1"=="" set "WOW=%~1"
set "ADDONS=%WOW%\_classic_era_\Interface\AddOns"

echo projects : %PROJECTS%
echo addons   : %ADDONS%
echo.

set /a gone=0, left=0

echo === projects ^(root^) ===
call :unlink "%PROJECTS%"
echo.
echo === addons ===
for /d %%D in ("%REPO%\Addons\*") do call :unlink "%ADDONS%\%%~nxD"

echo.
echo %gone% unlinked, %left% left in place
exit /b 0

REM --------------------------------------------------------------------------
REM :unlink <destination>
:unlink
set "DST=%~1"
set "NAME=%~nx1"
if "%NAME%"=="" set "NAME=%DST%"

if not exist "%DST%" (
    echo   --    %NAME%  -- not there
    exit /b 0
)

call :islink "%DST%"
if errorlevel 1 (
    echo   KEEP  %NAME%  -- a real folder, not a link
    set /a left+=1
    exit /b 0
)

rmdir "%DST%"
if exist "%DST%" (
    echo   FAIL  %NAME%
    set /a left+=1
    exit /b 0
)
echo   rm    %NAME%
set /a gone+=1
exit /b 0

REM --------------------------------------------------------------------------
REM :islink <path>   exits 0 when the path is a reparse point, 1 when it is a
REM                  real directory.
:islink
dir /a:l /b "%~dp1." 2>nul | findstr /x /i /c:"%~nx1" >nul
exit /b %errorlevel%
