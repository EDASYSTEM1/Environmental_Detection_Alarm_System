@echo off
chcp 65001 >nul
rem ===========================================================================
rem  sim_iverilog.bat - run all testbenches with Icarus Verilog
rem
rem  Why: local Vivado 2026.1 uses a BASIC license (no xsim simulator),
rem       so functional simulation goes through Icarus Verilog instead.
rem
rem  Usage: double-click, or run  scripts\sim_iverilog.bat
rem  Pass : six lines "==== XXX TEST PASSED ===="
rem ===========================================================================
setlocal
cd /d "%~dp0.."

set "IV=C:\iverilog\bin\iverilog.exe"
set "VVP=C:\iverilog\bin\vvp.exe"
if not exist "%IV%"  set "IV=iverilog"
if not exist "%VVP%" set "VVP=vvp"

rem ---- RTL sources (add new modules here) ----
set "RTL=top\sys_top.v common\rst_sync.v common\tick_gen.v common\debounce.v common\sensor_snapshot.v common\vga_timing.v modules\m_sensor_th\rtl\th_sensor.v modules\m_sensor_light\rtl\light_sensor.v modules\m_alarm\rtl\alarm_ctrl.v modules\m_alarm\rtl\buzz_drv.v modules\m_disp_oled\rtl\disp_ctrl.v modules\m_disp_vga\rtl\vga_disp.v modules\m_uart\rtl\uart_tx.v modules\m_uart\rtl\report_tx.v"

if not exist work_iverilog mkdir work_iverilog

echo.
echo ===== [1/6] tb_th_sensor : temperature/humidity module =====
"%IV%" -g2012 -s tb_th_sensor -o work_iverilog\tb_th.vvp %RTL% modules\m_sensor_th\sim\tb_th_sensor.v
if errorlevel 1 goto fail
"%VVP%" work_iverilog\tb_th.vvp
if errorlevel 1 goto fail

echo.
echo ===== [2/6] tb_light_sensor : light sensor module =====
"%IV%" -g2012 -s tb_light_sensor -o work_iverilog\tb_light.vvp %RTL% modules\m_sensor_light\sim\tb_light_sensor.v
if errorlevel 1 goto fail
"%VVP%" work_iverilog\tb_light.vvp
if errorlevel 1 goto fail

echo.
echo ===== [3/6] tb_alarm : alarm decision =====
"%IV%" -g2012 -s tb_alarm -o work_iverilog\tb_alarm.vvp %RTL% modules\m_alarm\sim\tb_alarm.v
if errorlevel 1 goto fail
"%VVP%" work_iverilog\tb_alarm.vvp
if errorlevel 1 goto fail

echo.
echo ===== [4/6] tb_uart_tx : UART 8N1 bit timing =====
"%IV%" -g2012 -s tb_uart_tx -o work_iverilog\tb_uart.vvp %RTL% modules\m_uart\sim\tb_uart_tx.v
if errorlevel 1 goto fail
"%VVP%" work_iverilog\tb_uart.vvp
if errorlevel 1 goto fail

echo.
echo ===== [5/6] tb_report : UART report frame format =====
"%IV%" -g2012 -s tb_report -o work_iverilog\tb_report.vvp %RTL% modules\m_uart\sim\tb_report.v
if errorlevel 1 goto fail
"%VVP%" work_iverilog\tb_report.vvp
if errorlevel 1 goto fail

echo.
echo ===== [6/6] sys_tb : full system smoke test =====
"%IV%" -g2012 -s sys_tb -o work_iverilog\tb_sys.vvp %RTL% top\sys_tb.v
if errorlevel 1 goto fail
"%VVP%" work_iverilog\tb_sys.vvp
if errorlevel 1 goto fail

echo.
echo ===== DONE: you should see 6 x "TEST PASSED" above =====
endlocal
exit /b 0

:fail
echo.
echo *** compile or simulation FAILED, see errors above ***
endlocal
exit /b 1
