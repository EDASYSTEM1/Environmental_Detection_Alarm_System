@echo off
chcp 65001 >nul
rem ===========================================================================
rem  run_wave.bat —— 重新生成 docs/waveforms 里的波形图（UART / OLED SPI）
rem
rem  原理：Icarus 仿真 → 输出 .vcd → Python(Pillow) 把 VCD 画成 PNG
rem  不需要装 GTKWave，也不需要 Vivado（本机 Vivado 没 xsim）
rem
rem  依赖：C:\iverilog\bin、Python + Pillow
rem  用法：双击，或在仓库根目录执行 tools\wave\run_wave.bat
rem ===========================================================================
setlocal
cd /d "%~dp0..\.."

set "IV=C:\iverilog\bin\iverilog.exe"
set "VVP=C:\iverilog\bin\vvp.exe"
rem ---- 找一个带 Pillow 的 Python（本机系统 Python 没装 Pillow，退回 DSH 自带的）----
set "PY=python"
"%PY%" -c "import PIL" >nul 2>&1
if not errorlevel 1 goto have_py
set "PY=C:\Users\lenovo\.dsh\dsh-runtimes\dsh-primary-runtime\dependencies\python\python.exe"
"%PY%" -c "import PIL" >nul 2>&1
if not errorlevel 1 goto have_py
echo 需要一个带 Pillow 的 Python：pip install pillow
exit /b 1
:have_py

if not exist "%IV%" set "IV=iverilog"
if not exist "%VVP%" set "VVP=vvp"

set "R=%~dp0..\..\"
set "W=%~dp0"

echo.
echo ===== [1/2] UART 8N1 位时序 =====
"%IV%" -g2012 -s tb_wave_uart -o "%W%wave_uart.vvp" "%R%modules\m_uart\rtl\uart_tx.v" "%W%tb_wave_uart.v"
if errorlevel 1 goto fail
pushd "%W%" && "%VVP%" wave_uart.vvp && popd
if errorlevel 1 goto fail

echo.
echo ===== [2/2] OLED SPI 时序 =====
"%IV%" -g2012 -s tb_wave_oled -o "%W%wave_oled.vvp" "%R%modules\m_disp_oled\rtl\oled_spi.v" "%W%tb_wave_oled.v"
if errorlevel 1 goto fail
pushd "%W%" && "%VVP%" wave_oled.vvp && popd
if errorlevel 1 goto fail

echo.
echo ===== 生成可交互波形（浏览器打开）=====
"%PY%" "%W%vcd2html.py" "%W%wave_uart.vcd" "%W%uart.html" "UART 8N1 位时序（0xA5）"
if errorlevel 1 goto fail
"%PY%" "%W%vcd2html.py" "%W%wave_oled.vcd" "%W%oled.html" "Pmod OLED SPI 初始化时序"
if errorlevel 1 goto fail
echo.
echo.
echo ===== 渲染成 PNG =====
"%PY%" "%W%vcd_wave.py"
if errorlevel 1 goto fail

echo.
echo ===== DONE: 图片在 tools\wave\ 下（*.png），
echo      要自己看波形：双击 tools\wave\uart.html 或 oled.html =====
endlocal
exit /b 0

:fail
echo.
echo *** 失败，检查 iverilog / python / Pillow 是否可用 ***
endlocal
exit /b 1
