@echo off
rem ===========================================================================
rem  create_project.bat - build the Vivado project (about 30-60 seconds)
rem  Output: work\sys_proj\sys_proj.xpr
rem ===========================================================================
setlocal
cd /d "%~dp0.."

set "VIVADO=E:\vivado\2026.1\Vivado\bin\vivado.bat"
if not exist "%VIVADO%" (
  echo ERROR: Vivado not found at %VIVADO%
  echo        edit the VIVADO path at the top of this bat
  pause
  exit /b 1
)

if not exist logs mkdir logs

echo ============================================================
echo   Creating Vivado project, please wait (30-60 s)...
echo ============================================================
call "%VIVADO%" -mode batch -source scripts\create_project.tcl -log logs\create_project.log -journal logs\create_project.jou

findstr /C:"project created" logs\create_project.log >nul 2>&1
if errorlevel 1 (
  echo.
  echo *** FAILED ***
  echo   see log: logs\create_project.log
  pause
  exit /b 1
)

echo.
echo ============================================================
echo   OK. Open the project:
echo     work\sys_proj\sys_proj.xpr
echo ============================================================
pause
