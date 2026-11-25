@echo off
rem ===========================================================================
rem  build_bitstream.bat - synthesis -> implementation -> bitstream (3-5 min)
rem  Requires: run scripts\create_project.bat once before
rem  Output  : bitstream\top.bit / top.bin, reports\*.rpt
rem ===========================================================================
setlocal
cd /d "%~dp0.."

set "VIVADO=E:\vivado\2026.1\Vivado\bin\vivado.bat"
if not exist "%VIVADO%" (
  echo ERROR: Vivado not found at %VIVADO%
  pause
  exit /b 1
)

if not exist logs mkdir logs

echo ============================================================
echo   synth + impl + bitstream, about 3-5 minutes, do not close
echo ============================================================
call "%VIVADO%" -mode batch -source scripts\build_bitstream.tcl -log logs\build_bitstream.log -journal logs\build_bitstream.jou

findstr /C:"BUILD_DONE" logs\build_bitstream.log >nul 2>&1
if errorlevel 1 (
  echo.
  echo *** FAILED ***
  echo   see log: logs\build_bitstream.log
  echo   see reports: reports\
  pause
  exit /b 1
)

echo.
echo ============================================================
echo   OK. Output:
echo     bitstream\top.bit
echo     reports\utilization.rpt / timing_summary.rpt
echo   Next: double-click tools\program_board.bat to download
echo ============================================================
pause
