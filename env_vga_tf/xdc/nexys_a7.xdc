## ============================================================================
##  xdc/sys_pins.xdc —— 环境监测警报系统 引脚约束
##
##  板卡：Digilent Nexys A7-100T（XC7A100T-1CSG324C）
##  引脚来源：Digilent 官方 Nexys-A7-100T-Master.xdc（v2 目录里存了完整模板）
##
##  ⚠️ 只改这个文件，不要改代码里的端口名；端口名与 docs/引脚分配.md 一一对应。
##  ⚠️ SW[8]/SW[9] 在 1.8 V bank，必须是 LVCMOS18，写成 33 会报 DRC 错。
## ============================================================================

## ---------------------------- 时钟 / 复位 ----------------------------
set_property -dict { PACKAGE_PIN E3    IOSTANDARD LVCMOS33 } [get_ports { CLK100MHZ }]
create_clock -add -name sys_clk_pin -period 10.00 -waveform {0 5} [get_ports { CLK100MHZ }]

set_property -dict { PACKAGE_PIN C12   IOSTANDARD LVCMOS33 } [get_ports { CPU_RESETN }]

## ---------------------------- 16 个拨码开关 ---------------------------
set_property -dict { PACKAGE_PIN J15   IOSTANDARD LVCMOS33 } [get_ports { SW[0] }]
set_property -dict { PACKAGE_PIN L16   IOSTANDARD LVCMOS33 } [get_ports { SW[1] }]
set_property -dict { PACKAGE_PIN M13   IOSTANDARD LVCMOS33 } [get_ports { SW[2] }]
set_property -dict { PACKAGE_PIN R15   IOSTANDARD LVCMOS33 } [get_ports { SW[3] }]
set_property -dict { PACKAGE_PIN R17   IOSTANDARD LVCMOS33 } [get_ports { SW[4] }]
set_property -dict { PACKAGE_PIN T18   IOSTANDARD LVCMOS33 } [get_ports { SW[5] }]
set_property -dict { PACKAGE_PIN U18   IOSTANDARD LVCMOS33 } [get_ports { SW[6] }]
set_property -dict { PACKAGE_PIN R13   IOSTANDARD LVCMOS33 } [get_ports { SW[7] }]
set_property -dict { PACKAGE_PIN T8    IOSTANDARD LVCMOS18 } [get_ports { SW[8] }]
set_property -dict { PACKAGE_PIN U8    IOSTANDARD LVCMOS18 } [get_ports { SW[9] }]
set_property -dict { PACKAGE_PIN R16   IOSTANDARD LVCMOS33 } [get_ports { SW[10] }]
set_property -dict { PACKAGE_PIN T13   IOSTANDARD LVCMOS33 } [get_ports { SW[11] }]
set_property -dict { PACKAGE_PIN H6    IOSTANDARD LVCMOS33 } [get_ports { SW[12] }]
set_property -dict { PACKAGE_PIN U12   IOSTANDARD LVCMOS33 } [get_ports { SW[13] }]
set_property -dict { PACKAGE_PIN U11   IOSTANDARD LVCMOS33 } [get_ports { SW[14] }]
set_property -dict { PACKAGE_PIN V10   IOSTANDARD LVCMOS33 } [get_ports { SW[15] }]

## ---------------------------- 5 个按键 -------------------------------
##  BTN[0]=BTNC  BTN[1]=BTNU  BTN[2]=BTND  BTN[3]=BTNL  BTN[4]=BTNR
set_property -dict { PACKAGE_PIN N17   IOSTANDARD LVCMOS33 } [get_ports { BTN[0] }]
set_property -dict { PACKAGE_PIN M18   IOSTANDARD LVCMOS33 } [get_ports { BTN[1] }]
set_property -dict { PACKAGE_PIN P18   IOSTANDARD LVCMOS33 } [get_ports { BTN[2] }]
set_property -dict { PACKAGE_PIN P17   IOSTANDARD LVCMOS33 } [get_ports { BTN[3] }]
set_property -dict { PACKAGE_PIN M17   IOSTANDARD LVCMOS33 } [get_ports { BTN[4] }]

## ---------------------------- 16 个 LED -------------------------------
set_property -dict { PACKAGE_PIN H17   IOSTANDARD LVCMOS33 } [get_ports { LED[0] }]
set_property -dict { PACKAGE_PIN K15   IOSTANDARD LVCMOS33 } [get_ports { LED[1] }]
set_property -dict { PACKAGE_PIN J13   IOSTANDARD LVCMOS33 } [get_ports { LED[2] }]
set_property -dict { PACKAGE_PIN N14   IOSTANDARD LVCMOS33 } [get_ports { LED[3] }]
set_property -dict { PACKAGE_PIN R18   IOSTANDARD LVCMOS33 } [get_ports { LED[4] }]
set_property -dict { PACKAGE_PIN V17   IOSTANDARD LVCMOS33 } [get_ports { LED[5] }]
set_property -dict { PACKAGE_PIN U17   IOSTANDARD LVCMOS33 } [get_ports { LED[6] }]
set_property -dict { PACKAGE_PIN U16   IOSTANDARD LVCMOS33 } [get_ports { LED[7] }]
set_property -dict { PACKAGE_PIN V16   IOSTANDARD LVCMOS33 } [get_ports { LED[8] }]
set_property -dict { PACKAGE_PIN T15   IOSTANDARD LVCMOS33 } [get_ports { LED[9] }]
set_property -dict { PACKAGE_PIN U14   IOSTANDARD LVCMOS33 } [get_ports { LED[10] }]
set_property -dict { PACKAGE_PIN T16   IOSTANDARD LVCMOS33 } [get_ports { LED[11] }]
set_property -dict { PACKAGE_PIN V15   IOSTANDARD LVCMOS33 } [get_ports { LED[12] }]
set_property -dict { PACKAGE_PIN V14   IOSTANDARD LVCMOS33 } [get_ports { LED[13] }]
set_property -dict { PACKAGE_PIN V12   IOSTANDARD LVCMOS33 } [get_ports { LED[14] }]
set_property -dict { PACKAGE_PIN V11   IOSTANDARD LVCMOS33 } [get_ports { LED[15] }]

## ------------------------ 8 位数码管：段选 ----------------------------
##  SEG = {DP, CG, CF, CE, CD, CC, CB, CA}，低有效
set_property -dict { PACKAGE_PIN T10   IOSTANDARD LVCMOS33 } [get_ports { SEG[0] }]
set_property -dict { PACKAGE_PIN R10   IOSTANDARD LVCMOS33 } [get_ports { SEG[1] }]
set_property -dict { PACKAGE_PIN K16   IOSTANDARD LVCMOS33 } [get_ports { SEG[2] }]
set_property -dict { PACKAGE_PIN K13   IOSTANDARD LVCMOS33 } [get_ports { SEG[3] }]
set_property -dict { PACKAGE_PIN P15   IOSTANDARD LVCMOS33 } [get_ports { SEG[4] }]
set_property -dict { PACKAGE_PIN T11   IOSTANDARD LVCMOS33 } [get_ports { SEG[5] }]
set_property -dict { PACKAGE_PIN L18   IOSTANDARD LVCMOS33 } [get_ports { SEG[6] }]
set_property -dict { PACKAGE_PIN H15   IOSTANDARD LVCMOS33 } [get_ports { SEG[7] }]

## ------------------------ 8 位数码管：位选 ----------------------------
##  AN0 = 最右边一位，低有效
set_property -dict { PACKAGE_PIN J17   IOSTANDARD LVCMOS33 } [get_ports { AN[0] }]
set_property -dict { PACKAGE_PIN J18   IOSTANDARD LVCMOS33 } [get_ports { AN[1] }]
set_property -dict { PACKAGE_PIN T9    IOSTANDARD LVCMOS33 } [get_ports { AN[2] }]
set_property -dict { PACKAGE_PIN J14   IOSTANDARD LVCMOS33 } [get_ports { AN[3] }]
set_property -dict { PACKAGE_PIN P14   IOSTANDARD LVCMOS33 } [get_ports { AN[4] }]
set_property -dict { PACKAGE_PIN T14   IOSTANDARD LVCMOS33 } [get_ports { AN[5] }]
set_property -dict { PACKAGE_PIN K2    IOSTANDARD LVCMOS33 } [get_ports { AN[6] }]
set_property -dict { PACKAGE_PIN U13   IOSTANDARD LVCMOS33 } [get_ports { AN[7] }]

## ============================================================================
##  Pmod JA —— Pmod OLED（SPI）：1=CS 2=SDIN 4=SCLK 7=D/C 8=RES（v2 已实测）
## ============================================================================
set_property -dict { PACKAGE_PIN C17   IOSTANDARD LVCMOS33 } [get_ports { OLED_CS }]
set_property -dict { PACKAGE_PIN D18   IOSTANDARD LVCMOS33 } [get_ports { OLED_SDIN }]
set_property -dict { PACKAGE_PIN G17   IOSTANDARD LVCMOS33 } [get_ports { OLED_SCLK }]
set_property -dict { PACKAGE_PIN D17   IOSTANDARD LVCMOS33 } [get_ports { OLED_DC }]
set_property -dict { PACKAGE_PIN E17   IOSTANDARD LVCMOS33 } [get_ports { OLED_RES }]

## ============================================================================
##  Pmod JB —— Pmod HYGRO 温湿度（6 针 I2C 模块）
##
##  ⚠️ 官方手册（Pmod HYGRO Reference Manual, J1 Pinout）：
##       1=NC  2=NC  3=SCL  4=SDA  5=GND  6=VCC
##     注意 SCL/SDA **不在 1/2 脚**，第一次配的时候我按 1/2 脚写是错的，已按手册修正。
##  6 针模块插在 12 针排针的 1~6 脚（上排），所以：
##       SCL = JB[3] = G16     SDA = JB[4] = H14
## ============================================================================
set_property -dict { PACKAGE_PIN G16   IOSTANDARD LVCMOS33 } [get_ports { HYGRO_SCL }]
set_property -dict { PACKAGE_PIN H14   IOSTANDARD LVCMOS33 } [get_ports { HYGRO_SDA }]

## ============================================================================
##  Pmod JC —— Pmod ALS 光照（6 针 SPI 模块，板载 ADC081S021，8 位）
##
##  ⚠️ 官方手册（Pmod ALS Reference Manual）：
##       1=~CS  2=NC  3=MISO  4=SCLK  5=GND  6=VCC
##       读一次 = CS 拉低 + 16 个 SCLK，SCLK 上限 4 MHz
##       MISO = JC[3] = J2      SCLK = JC[4] = G6      CS = JC[1] = K1
## ============================================================================
set_property -dict { PACKAGE_PIN K1    IOSTANDARD LVCMOS33 } [get_ports { ALS_CS }]
set_property -dict { PACKAGE_PIN G6    IOSTANDARD LVCMOS33 } [get_ports { ALS_SCLK }]
set_property -dict { PACKAGE_PIN J2    IOSTANDARD LVCMOS33 } [get_ports { ALS_MISO }]

## ============================================================================
##  板载 VGA（12 位色）：R[3:0] G[3:0] B[3:0] + HS + VS，全部负极性同步
## ============================================================================
set_property -dict { PACKAGE_PIN A3    IOSTANDARD LVCMOS33 } [get_ports { VGA_R[0] }]
set_property -dict { PACKAGE_PIN B4    IOSTANDARD LVCMOS33 } [get_ports { VGA_R[1] }]
set_property -dict { PACKAGE_PIN C5    IOSTANDARD LVCMOS33 } [get_ports { VGA_R[2] }]
set_property -dict { PACKAGE_PIN A4    IOSTANDARD LVCMOS33 } [get_ports { VGA_R[3] }]
set_property -dict { PACKAGE_PIN C6    IOSTANDARD LVCMOS33 } [get_ports { VGA_G[0] }]
set_property -dict { PACKAGE_PIN A5    IOSTANDARD LVCMOS33 } [get_ports { VGA_G[1] }]
set_property -dict { PACKAGE_PIN B6    IOSTANDARD LVCMOS33 } [get_ports { VGA_G[2] }]
set_property -dict { PACKAGE_PIN A6    IOSTANDARD LVCMOS33 } [get_ports { VGA_G[3] }]
set_property -dict { PACKAGE_PIN B7    IOSTANDARD LVCMOS33 } [get_ports { VGA_B[0] }]
set_property -dict { PACKAGE_PIN C7    IOSTANDARD LVCMOS33 } [get_ports { VGA_B[1] }]
set_property -dict { PACKAGE_PIN D7    IOSTANDARD LVCMOS33 } [get_ports { VGA_B[2] }]
set_property -dict { PACKAGE_PIN D8    IOSTANDARD LVCMOS33 } [get_ports { VGA_B[3] }]
set_property -dict { PACKAGE_PIN B11   IOSTANDARD LVCMOS33 } [get_ports { VGA_HS }]
set_property -dict { PACKAGE_PIN B12   IOSTANDARD LVCMOS33 } [get_ports { VGA_VS }]

## ============================================================================
##  Pmod JD（板上丝印是 JXADC，第 4 个 Pmod 口）—— 自制蜂鸣器模块
##
##  JXADC 的 8 根信号实际是 XA_N/XA_P[1..4]（bank 15，LVCMOS33），
##  当普通数字 IO 用完全没问题（只要别同时启用 XADC 原语）。
##
##  本工程只用 1 根线：
##      1 脚 = A14 (XA_N[1]) → BUZZ
##  2 脚 A13 (XA_P[1]) 留空；如果你们的模块信号不在 1 脚，
##  把下面那行的 A14 换成对应引脚即可（2脚=A13, 3脚=A16, 4脚=A15,
##  7脚=B17, 8脚=B16, 9脚=A18, 10脚=B18）。
## ============================================================================
set_property -dict { PACKAGE_PIN A14   IOSTANDARD LVCMOS33 } [get_ports { BUZZ }]

## ============================================================================
##  板载 USB-UART —— 串口上报（115200 8N1）
##
##  Nexys A7 的 FTDI 芯片有两个通道：A=JTAG（烧板），B=UART。
##  两个通道共用板子标着 "PROG/UART" 的那一个 microUSB 口，
##  所以在电脑上会同时出现"一个 JTAG 设备 + 一个 COM 口"，不需要额外接线。
##
##  注意方向：FTDI 侧的命名是 uart_rxd_out（FPGA 发出去）/ uart_txd_in（FPGA 收），
##  我们用到的发送脚是 uart_rxd_out = D4。
## ============================================================================
set_property -dict { PACKAGE_PIN D4    IOSTANDARD LVCMOS33 } [get_ports { UART_TXD }]

## ============================================================================
##  Bitstream 配置属性（板载 QSPI Flash：S25FL128S 16 MiB，Quad-SPI x4）
## ============================================================================
set_property CONFIG_VOLTAGE 3.3 [current_design]
set_property CFGBVS VCCO [current_design]
set_property BITSTREAM.CONFIG.SPI_BUSWIDTH 4 [current_design]

## J1 onboard microSD, SPI mode. SD_RESET low powers the card.
set_property -dict { PACKAGE_PIN A1 IOSTANDARD LVCMOS33 } [get_ports SD_CD]
set_property -dict { PACKAGE_PIN E2 IOSTANDARD LVCMOS33 } [get_ports SD_RESET]
set_property -dict { PACKAGE_PIN B1 IOSTANDARD LVCMOS33 } [get_ports SD_SCK]
set_property -dict { PACKAGE_PIN C1 IOSTANDARD LVCMOS33 } [get_ports SD_MOSI]
set_property -dict { PACKAGE_PIN C2 IOSTANDARD LVCMOS33 } [get_ports SD_MISO]
set_property -dict { PACKAGE_PIN D2 IOSTANDARD LVCMOS33 } [get_ports SD_CS_N]
