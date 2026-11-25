# 环境监测警报系统 · FPGA 框架（Nexys A7-100T）

> **课程**：FPGA 课程设计　**板卡**：Digilent Nexys A7-100T（Artix-7 **XC7A100T-1CSG324C**）
> **工具链**：Vivado 2026.1（`E:\vivado\2026.1\Vivado\bin\vivado.bat`）+ Icarus Verilog（`C:\iverilog\bin`）
> **仓库形态**：`main`（可交付）/ `develop`（集成）/ `feature/*`（各人）
> **当前状态**：🟡 **框架骨架**（2026-11-25）—— 全部模块已连线、可仿真、可综合，但传感器和显示还是空壳。

---

## 一、这是什么

三个人并行做同一个 FPGA 系统，最怕两件事：**接口对不上**和**改顶层互相冲突**。
所以这个仓库先把"总框架"搭好：模块怎么划分、端口叫什么、数据什么格式、谁的代码放哪里，
全部**定死**，然后三个人只在各自目录里填肉。

```
        ┌──────────────────────────────────────────────────────────────┐
        │  Pmod JB ─► th_sensor ──┐                                    │
        │  Pmod JC ─► light_sensor┤                                    │
        │                          ▼                                   │
 100 MHz ─► tick_gen ─►      sensor_snapshot ──► alarm_ctrl ──► LED/蜂鸣器
        │                          │                                   │
        │             SW[15:0] ────┘                                   │
        │                          ├──► disp_ctrl ──► Pmod OLED + 8 位数码管
        │                          └──► vga_disp  ──► 板载 VGA（外接显示器）
        └──────────────────────────────────────────────────────────────┘
```

## 二、现在有什么（骨架阶段）

| 模块 | 文件 | 负责人 | 状态 | 现在能看到什么 |
|---|---|---|---|---|
| `sys_top` | `top/sys_top.v` | 组长 | ✅ 已连线 | 整个系统综合通过（骨架版） |
| `rst_sync` / `tick_gen` / `debounce` / `sensor_snapshot` / `vga_timing` | `common/` | 组长 | ✅ 已实现 | 复位、1Hz/10Hz/1kHz 节拍、按键消抖、数据快照、VGA 时序 |
| `th_sensor` | `modules/m_sensor_th/rtl/` | 成员B | ⬜ **空壳** | 恒输出 25.3 ℃ / 55.0 %RH |
| `light_sensor` | `modules/m_sensor_light/rtl/` | 成员B | ⬜ **空壳** | 恒输出 320 lux |
| `alarm_ctrl` | `modules/m_alarm/rtl/` | 组长 | 🟢 简化版可用 | LED 显示报警等级/来源，**Pmod JD 蜂鸣器**出声 |
| `disp_ctrl` | `modules/m_disp_oled/rtl/` | 组长 | ⬜ **空壳** | OLED 黑屏、数码管全灭 |
| `vga_disp` | `modules/m_disp_vga/rtl/` | 成员C | ⬜ **空壳** | 显示器能锁上信号，画面全黑 |

**已通过**（本机 Icarus 12.0 实测）：

```
==== TH TEST PASSED ====      温湿度模块接口语义
==== LIGHT TEST PASSED ====   光照模块接口语义
==== ALARM TEST PASSED ====   报警 4 种判定 + 蜂鸣器门控
==== SYS TEST PASSED ====     系统联调：复位/节拍/快照/报警/按键
```

**还没做**（骨架阶段故意不做）：

- ❌ Vivado 综合/实现/时序（`WNS` 未知，等显示和传感器定稿后统一跑）；
- ❌ OLED/数码管/VGA 的实际画面；
- ❌ I2C/SPI 传感器真驱动；
- ❌ 上板验证（当前所有输出是"安全静态电平"，上板只会亮 LED）。

## 三、三步上手

```bash
# 1) 拿代码（仓库地址等组长给；现在只有本地 git 仓库）
git clone <仓库地址> fpga-env-monitor
cd fpga-env-monitor
git checkout develop

# 2) 先跑仿真，确认环境没问题（约 5 秒）
scripts\sim_iverilog.bat
#    看到 4 个 TEST PASSED 就对了

# 3) 生成 Vivado 工程
scripts\create_project.bat       # 约 30~60 秒
#    然后双击 work\sys_proj\sys_proj.xpr 打开
```

> ⚠️ **路径必须全英文**：Vivado 2026.1 在中文路径下综合会崩（0xC0000374），
> 所以克隆到 `E:\fpga_course_design\v3_env_monitor_framework` 这类纯 ASCII 路径下。

## 四、目录结构（每人在自己的格子里干活）

```
.
├── top/
│   ├── sys_top.v              ← 总连线（只有组长能改）
│   └── sys_tb.v               ← 系统级仿真
├── common/                    ← 共享基础设施（组长维护）
│   ├── rst_sync.v             复位同步（异步置位 / 同步释放）
│   ├── tick_gen.v             1kHz / 10Hz / 1Hz 节拍
│   ├── debounce.v             按键 10ms 消抖
│   ├── sensor_snapshot.v      数据快照 + 掉线检测
│   └── vga_timing.v           640×480@60 时序（像素使能，不派生时钟）
├── modules/
│   ├── m_sensor_th/           ← 成员B：温湿度
│   │   ├── rtl/th_sensor.v
│   │   └── sim/tb_th_sensor.v
│   ├── m_sensor_light/        ← 成员B：光照
│   │   ├── rtl/light_sensor.v
│   │   └── sim/tb_light_sensor.v
│   ├── m_alarm/               ← 组长：报警判定 + 蜂鸣器
│   │   ├── rtl/alarm_ctrl.v
│   │   ├── rtl/buzz_drv.v     蜂鸣器驱动（插 Pmod JD，无源/有源可切）
│   │   └── sim/tb_alarm.v
│   ├── m_disp_oled/           ← 组长：OLED + 数码管
│   │   └── rtl/disp_ctrl.v
│   └── m_disp_vga/            ← 成员C：VGA
│       └── rtl/vga_disp.v
├── xdc/sys_pins.xdc           ← 全部引脚（改引脚只改这里）
├── scripts/
│   ├── create_project.tcl/.bat  一键建工程（glob 自动收文件，新增 .v 不用改脚本）
│   ├── build_bitstream.tcl/.bat 综合+实现+bit
│   └── sim_iverilog.bat         跑全部仿真
├── tools/
│   ├── hw_program.tcl           下载 bit 到板子
│   └── program_board.bat        双击下载
├── docs/
│   ├── 接口协议.md            ★ 端口/数据格式/开关映射（唯一依据）
│   ├── 分工与流程.md          ★ 分支、PR、每日流程、三条红线
│   └── 引脚分配.md              引脚速查表
├── ip/                        共享 IP 核（暂空）
├── bitstream/                 生成的 bit/bin
├── logs/                      脚本日志
└── reports/                   时序/资源报告
```

## 五、接口一句话

- **一个时钟**：100 MHz `clk`，节奏用 `tick_1hz / tick_10hz / tick_1khz` 使能；
- **复位**：内部 `rst` 高有效、同步释放（`rst_sync` 统一处理）；
- **数据**：`temp_x10`（0.1 ℃，有符号）、`humi_x10`（0.1 %RH）、`lux`（1 lux），
  每 1 Hz 更新一次并配 `valid` 单脉冲；
- **谁也别碰**：`top/sys_top.v`、`xdc/sys_pins.xdc`、`docs/接口协议.md`（组长专属）。

详细端口表见 [docs/接口协议.md](docs/接口协议.md)。

## 六、给组员的下一步（照这个开工）

### 成员B（传感器）

1. 读 `docs/接口协议.md` 第 4.1 / 4.2 节，确认端口不动；
2. `m_sensor_th`：写 I2C 主机（100 kHz）→ SHTC3 读 6 字节 → 换算成 `temp_x10 / humi_x10`；
3. `m_sensor_light`：写 SPI 读 ADCS7476 → `adc_raw` → 标定成 `lux`；
4. 把 `sim/tb_th_sensor.v`、`tb_light_sensor.v` 改成真时序测试（建议加 I2C 从机模型 / ADC 模型）；
5. 分支 `feature/sensor_th`、`feature/sensor_light` 分别提 PR 到 `develop`。

### 成员C（VGA）

1. 读 `docs/接口协议.md` 第 4.5 节；`vga_timing` 已经给好，**不要自己造时钟**；
2. 先用 `vga_disp.v` 里注释掉的彩条验证显示器能出图；
3. 再做文字：`x` 坐标 ÷ 8 = 字符列，`y` ÷ 8 = 字符行，用 `common/font_rom.v`（下一步会加）画字；
4. 画面内容与 OLED 一致（第 2/3 行显示温湿度和光照，报警时背景变红/橙）。

### 组长（你）

1. 把 v2 已验证的 SSD1306 驱动拆成 `oled_spi` + `text_engine` + `screen_ram`，接到 `disp_ctrl`；
2. 数码管 8 位显示 `TT.T HH.H`；
3. 加 `common/font_rom.v`（从 v2 复制，两边显示共用同一套字模）；
4. 全部实现后跑 Vivado 综合/实现，记录 WNS 与资源，再上板。

## 七、已知限制（别踩）

| 限制 | 说明 |
|---|---|
| Vivado BASIC 授权没有 xsim | 仿真统一用 Icarus（`scripts\sim_iverilog.bat`），Vivado 里跑仿真会报 license 错 |
| 本机烧不了板载 QSPI Flash | 报 `Failure to set flash parameters`（试过 25+ 型号）。**断电后程序不保留**，每次上电要双击 `tools\program_board.bat` 重下载（约 40 秒） |
| 中文路径 | 会崩，仓库放纯英文路径 |
| SW[8]/SW[9] | 在 1.8 V bank，XDC 里必须 `LVCMOS18` |
| 蜂鸣器在 **Pmod JD**（丝印 JXADC） | 信号接 1 脚 = A14；自制模块如果信号在别的脚，改 xdc 那一行即可（对照表见 docs/引脚分配.md） |

## 八、和上一版（v2）的关系

`E:\fpga_course_design\v2_oled_time_display` 是"LED 流水灯 + 数码管 + OLED 时钟"的验证版，
**本版继承它的两个成果**：OLED 在 **JA 口**的引脚与驱动思路、脚本/下载流程。
按版本规则，v2 保持只读，本版是独立的新版本目录。

## 十、本组实际器件清单（已按课程动员 PPT + Digilent 手册核对）

| 器件 | 型号 / 规格 | 接法 | 用途 |
|---|---|---|---|
| 开发板 | Digilent **Nexys A7-100T**，XC7A100T-1CSG324C | — | 主控 |
| Pmod OLED | 128×32 单色 OLED（SSD1306，SPI） | **JA** | 主显示（组长） |
| Pmod HYGRO | SHTC3 温湿度（6 针 I2C，地址 0x70） | **JB**（SCL=G16, SDA=H14） | 温湿度（成员B） |
| Pmod ALS | TEMT6000 光敏管 + ADC081S021（6 针 SPI，**8 位** ADC） | **JC**（CS=K1, MISO=J2, SCLK=G6） | 光照（成员B） |
| 自制蜂鸣器 | 自制 Pmod 模块 | **JD**（丝印 JXADC，信号 A14） | 报警声（组长） |
| （可能附带）Pmod USBUART | USB 转串口 | 未使用 | 板上已有 FTDI USB-UART，不需要它 |

**课程清单里有、但本组没有发到的模块**（框架里也没有假设它们存在）：
Pmod AD2 / DA2 / AD5 / AMP3 / BLE / ESP32 / BT2 / CAM 5C / GYRO / MaxSonar / OLEDrgb / CDC1。
如果后面借到了，按接口协议新增模块即可，`sys_top.v` 加一条例化、xdc 加几行引脚。

**开发板自带、可以直接用的资源**（写报告和扩展功能时有用）：

- 16 拨码开关 + 16 LED + 5 按键；
- 8 位数码管（2 组 4 位，共阳极，低有效）；
- **12 位 VGA**（R/G/B 各 4 位）+ HS/VS；
- 板载单声道 PWM 音频口、板载麦克风、板载 ADT7420 温度传感器（I2C）；
- 128 MiB DDR2、16 MiB QSPI Flash、microSD、10/100M 以太网、USB HID Host；
- XADC 模拟信号 Pmod 口（就是 JD，本工程拿来做蜂鸣器了）。

## 十一、版本

| 日期 | 内容 |
|---|---|
| 2026-11-25 | 初始化框架：空壳模块 + 顶层连线 + XDC + 4 个脚本 + 3 份文档 + 4 个仿真全 PASS |
| 2026-11-25 | 蜂鸣器改到自制 Pmod（JD 口）；按 Digilent 官方手册修正 HYGRO/ALS 引脚与 ALS 8 位 ADC 说明 |
