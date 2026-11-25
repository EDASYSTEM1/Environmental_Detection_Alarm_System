# ============================================================================
#  serial_check.ps1 —— 串口上报自动检查（不用装 pyserial，走 .NET 自带 SerialPort）
#
#  用法（在仓库根目录）：
#     powershell -NoProfile -ExecutionPolicy Bypass -File tools\serial_check.ps1
#     powershell ... -File tools\serial_check.ps1 -Port COM19 -Seconds 3
#
#  做什么：
#     1) 自动找 FTDI 的 UART 串口（Nexys A7 板载 FTDI 的通道 B）；
#     2) 打开 115200 8N1，收 N 秒；
#     3) 逐行用正则校验帧格式，打印样本、帧率、是否全部合格。
#
#  为什么不用 pc_monitor.py：python 需要 pip install pyserial，
#  而这个脚本用 Windows 自带的 .NET 串口类，交作业/同学电脑上直接能跑。
# ============================================================================
param(
    [string]$Port = "",
    [int]$Seconds = 3,
    [int]$Baud = 115200
)

$ErrorActionPreference = "Stop"

# ---- 没指定串口就自动找 FTDI 的 ----
if (-not $Port) {
    $ftdi = Get-CimInstance Win32_PnPEntity -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -match 'USB Serial Port \((COM\d+)\)' } |
            Select-Object -First 1
    if ($ftdi) {
        if ($ftdi.Name -match '\((COM\d+)\)') { $Port = $Matches[1] }
    }
    if (-not $Port) {
        $ports = [System.IO.Ports.SerialPort]::GetPortNames()
        if ($ports.Count -eq 1) { $Port = $ports[0] }
        else {
            Write-Host "找到多个串口：$($ports -join ', ')" -ForegroundColor Yellow
            Write-Host "请用 -Port COMxx 指定（板子那颗 FTDI 的描述是 'USB Serial Port'）"
            exit 1
        }
    }
}
Write-Host "串口：$Port  波特率：$Baud  采集：${Seconds}s" -ForegroundColor Cyan

$sp = New-Object System.IO.Ports.SerialPort
$sp.PortName  = $Port
$sp.BaudRate  = $Baud
$sp.Parity    = 'None'
$sp.DataBits  = 8
$sp.StopBits  = 'One'
$sp.ReadTimeout = 1500
$sp.NewLine   = "`n"

$lines = New-Object System.Collections.ArrayList
try {
    $sp.Open()
    $sw = [Diagnostics.Stopwatch]::StartNew()
    while ($sw.Elapsed.TotalSeconds -lt $Seconds) {
        try {
            $l = $sp.ReadLine()
            if ($l) { [void]$lines.Add($l.Trim()) }
        } catch { }
    }
} catch {
    Write-Host "打开串口失败：$($_.Exception.Message)" -ForegroundColor Red
    Write-Host "  常见原因：串口被别的软件占用（串口助手/Keil），先关掉它"
    exit 1
} finally {
    if ($sp.IsOpen) { $sp.Close() }
}

if ($lines.Count -eq 0) {
    Write-Host "没收到任何数据。" -ForegroundColor Red
    Write-Host "  检查：bit 是否已经下载？板子是否上电？串口是不是选错了（不是蓝牙那个）？"
    exit 1
}

$pattern = '^\$ENV,T=[+-]\d\d\.\d,H=\d\d\.\d,L=\d{4},A=\d,S=[0-9A-F]{2}$'
$ok = ($lines | Where-Object { $_ -match $pattern }).Count
$rate = [math]::Round($lines.Count / $Seconds, 2)

Write-Host ""
Write-Host "收到 $($lines.Count) 帧，约 $rate 帧/秒（设计值 10 帧/秒）"
Write-Host "合格 $ok / $($lines.Count) 帧"
Write-Host ""
Write-Host "样本：" -ForegroundColor Cyan
$lines | Select-Object -First 3 | ForEach-Object { Write-Host "  $_" }
$uniq = $lines | Select-Object -Unique
Write-Host ""
Write-Host "不同内容 $($uniq.Count) 种：" -ForegroundColor Cyan
$uniq | Select-Object -First 5 | ForEach-Object { Write-Host "  $_" }

if ($ok -eq $lines.Count) {
    Write-Host ""
    Write-Host "==== SERIAL CHECK PASSED ====" -ForegroundColor Green
    exit 0
} else {
    Write-Host ""
    Write-Host "==== SERIAL CHECK FAILED ====" -ForegroundColor Red
    exit 1
}
