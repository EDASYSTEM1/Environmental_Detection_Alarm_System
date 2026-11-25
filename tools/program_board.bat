@echo off
rem ===========================================================================
rem  program_board.bat - download bitstream\top.bit to the Nexys A7 board
rem
rem  Steps:
rem    1) plug USB into the "PROG/UART" microUSB port, power switch ON
rem    2) double-click this file, wait for DONE
rem    3) expected: LED shows alarm level, VGA/OLED blank for now (skeleton)
rem
rem  Notes:
rem    - close Vivado Hardware Manager first (target is exclusive)
rem    - this machine cannot program the on-board QSPI flash, so the
rem      bitstream is lost after power off (about 40 s to reload)
rem ===========================================================================
setlocal
cd /d "%~dp0.."

set "VIVADO=E:\vivado\2026.1\Vivado\bin\vivado.bat"
if not exist "%VIVADO%" (
  echo ERROR: Vivado not found at %VIVADO%
  pause
  exit /b 1
)

if not exist bitstream\top.bit (
  echo ERROR: bitstream\top.bit not found
  echo        run scripts\build_bitstream.bat first
  pause
  exit /b 1
)

if not exist logs mkdir logs

echo ============================================================
echo   Downloading to the board, about 30-40 s (do not unplug)
echo ============================================================
call "%VIVADO%" -mode batch -source tools\hw_program.tcl -log logs\program_board.log -journal logs\program_board.jou

findstr /C:"PROGRAM_OK" logs\program_board.log >nul 2>&1
if errorlevel 1 (
  echo.
  echo *** DOWNLOAD FAILED ***
  echo   check: board powered? USB in PROG/UART? Hardware Manager closed?
  echo   log  : logs\program_board.log
  pause
  exit /b 1
)

echo.
echo ============================================================
echo   DONE. Board should show:
echo     - LED[3:0] : alarm level 0..3
echo     - LED[7:4] : alarm source (temp/humidity/light/fault)
echo     - 7-seg    : blank (display skeleton, not implemented yet)
echo     - OLED     : black (display skeleton, not implemented yet)
echo     - VGA      : black (member C, not implemented yet)
echo ============================================================
pause
