# 波形图（报告插图）

这里放从**仿真真实跑出来的 VCD** 渲染成的波形图，用于课程设计报告，不需要装 GTKWave。

| 图片 | 内容 | 说明 |
|---|---|---|
| `uart_8n1.png` | UART 8N1 发送 0xA5 的位时序 | 起始位 0 → 8 个数据位 `1 0 1 0 0 1 0 1`（LSB 先发）→ 停止位 1；虚线是比特边界（每 100 ns） |
| `oled_spi.png` | Pmod OLED（SSD1306）SPI 初始化时序 | CS 低有效、D/C=0 发命令、SCLK 空闲低/上升沿采样、MSB 先出 |

## 怎么重新生成

```bat
tools\wave\run_wave.bat
```

流程：Icarus 仿真 → 生成 `.vcd` → `tools\wave\vcd_wave.py` 用 Pillow 画成 PNG。

- 测试平台：`tools\wave\tb_wave_uart.v`、`tools\wave\tb_wave_oled.v`
- 渲染器：`tools\wave\vcd_wave.py`（会自动读 VCD 的 `$timescale` 换算成 ns）

> 为什么不用 Vivado 看波形：本机 Vivado 是 BASIC 授权，**没有 xsim**，点 Run Simulation 会报 license 错误。
> 这里的波形全部来自 Icarus Verilog（免费、开源），和功能仿真用的是同一个仿真器。

## 改图

- 想看别的信号：改 `tb_wave_*.v` 里的 `$dumpvars`，再改 `vcd_wave.py` 末尾 `render(...)` 里的信号列表；
- 想加别的场景（比如系统级 tick→valid→报警）：照抄一个 tb，编译时把对应 RTL 一起传进去即可。
