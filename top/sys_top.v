// ============================================================================
//  top/sys_top.v —— 环境监测警报系统 · 系统顶层（组长专属，别人别改）
//
//  ┌──────────────────────────────────────────────────────────────────────┐
//  │  CLK100MHZ 100 MHz ──► rst_sync ──► tick_gen (1kHz / 10Hz / 1Hz)     │
//  │                                                                      │
//  │  Pmod JB ─► th_sensor  ──(temp/humi/valid)──┐                        │
//  │  Pmod JC ─► light_sensor ─(lux/adc/valid)───┤                        │
//  │                                             ▼                        │
//  │                                     sensor_snapshot  ← 数据快照       │
//  │                                             │                        │
//  │  SW[15:0] ─────────────────────────────────►│                        │
//  │                                     alarm_ctrl ──► LED / BUZZ(Pmod JD)│
//  │                                             │                        │
//  │                          ┌──────────────────┴────────────┐           │
//  │                          ▼                               ▼           │
//  │                    disp_ctrl (OLED+数码管)        vga_disp (VGA)      │
//  └──────────────────────────────────────────────────────────────────────┘
//
//  这一版是"骨架"：传感器/显示都是空壳，但连线、时钟、复位、引脚全部按最终
//  形态定死。组员把自己的模块内部填完，顶层**一行都不用改**。
//
//  唯一需要改这里的情况：新增模块、或接口协议变更（见 docs/接口协议.md 第七节）。
// ============================================================================
module sys_top #(
    parameter integer CLK_HZ = 100_000_000      // 仿真时改成 1000 可以跑得飞快
) (
    input  wire        CLK100MHZ,     // E3   100 MHz
    input  wire        CPU_RESETN,    // C12  复位，低有效
    input  wire [15:0] SW,            // 16 个拨码开关（阈值设定）
    input  wire [4:0]  BTN,           // 5 个按键 {BTNR,BTNL,BTND,BTNU,BTNC}
    output wire [15:0] LED,
    output wire [7:0]  AN,            // 数码管位选，低有效
    output wire [7:0]  SEG,           // 数码管段选，低有效

    // ---------------- Pmod JA：OLED（128×32，SPI）----------------
    output wire        OLED_CS,
    output wire        OLED_SDIN,
    output wire        OLED_SCLK,
    output wire        OLED_DC,
    output wire        OLED_RES,

    // ---------------- Pmod JB：HYGRO 温湿度（I2C）----------------
    output wire        HYGRO_SCL,
    inout  wire        HYGRO_SDA,

    // ---------------- Pmod JC：ALS 光照（SPI）----------------
    output wire        ALS_CS,
    output wire        ALS_SCLK,
    input  wire        ALS_MISO,

    // ---------------- 板载 VGA：12 位色（每通道 4 位）----------------
    output wire [3:0]  VGA_R,
    output wire [3:0]  VGA_G,
    output wire [3:0]  VGA_B,
    output wire        VGA_HS,
    output wire        VGA_VS,

    // ---------------- Pmod JD（丝印 JXADC）：自制蜂鸣器模块 ----------------
    output wire        BUZZ,

    // ---------------- 板载 USB-UART（串口上报给上位机）----------------
    output wire        UART_TXD
);

    // ========================================================================
    // 1. 复位与节拍
    // ========================================================================
    wire rst;

    rst_sync u_rst_sync (
        .clk    (CLK100MHZ),
        .arst_n (CPU_RESETN),
        .rst    (rst)                 // 高有效、同步释放
    );

    wire tick_1khz, tick_10hz, tick_1hz;

    tick_gen #(.CLK_HZ(CLK_HZ)) u_tick_gen (
        .clk       (CLK100MHZ),
        .rst       (rst),
        .tick_1khz (tick_1khz),
        .tick_10hz (tick_10hz),
        .tick_1hz  (tick_1hz)
    );

    // 按键消抖（10 ms）
    wire [4:0] btn_db;

    debounce #(.CLK_HZ(CLK_HZ), .MS(10), .WIDTH(5)) u_debounce (
        .clk  (CLK100MHZ),
        .rst  (rst),
        .din  (BTN),
        .dout (btn_db)
    );

    // ========================================================================
    // 2. 传感器（成员B 的领地）
    // ========================================================================
    wire signed [15:0] th_temp_x10;
    wire        [15:0] th_humi_x10;
    wire        [7:0]  th_status;
    wire               th_valid;

    th_sensor u_th_sensor (
        .clk         (CLK100MHZ),
        .rst         (rst),
        .sample_tick (tick_1hz),
        .scl         (HYGRO_SCL),
        .sda         (HYGRO_SDA),
        .temp_x10    (th_temp_x10),
        .humi_x10    (th_humi_x10),
        .status      (th_status),
        .valid       (th_valid)
    );

    wire        [15:0] ls_lux;
    wire        [11:0] ls_adc_raw;
    wire        [7:0]  ls_status;
    wire               ls_valid;

    light_sensor u_light_sensor (
        .clk         (CLK100MHZ),
        .rst         (rst),
        .sample_tick (tick_1hz),
        .als_cs      (ALS_CS),
        .als_sclk    (ALS_SCLK),
        .als_miso    (ALS_MISO),
        .adc_raw     (ls_adc_raw),
        .lux         (ls_lux),
        .status      (ls_status),
        .valid       (ls_valid)
    );

    // ========================================================================
    // 3. 数据快照（显示和报警都读这里，保证同一帧数据一致）
    // ========================================================================
    wire signed [15:0] temp_x10;
    wire        [15:0] humi_x10;
    wire        [15:0] lux;
    wire        [11:0] adc_raw;
    wire        [7:0]  raw_status;
    wire        [7:0]  sensor_status;
    wire               data_ok;

    sensor_snapshot u_snapshot (
        .clk          (CLK100MHZ),
        .rst          (rst),
        .sample_tick  (tick_1hz),
        .th_temp_x10  (th_temp_x10),
        .th_humi_x10  (th_humi_x10),
        .th_status    (th_status),
        .th_valid     (th_valid),
        .ls_lux       (ls_lux),
        .ls_adc_raw   (ls_adc_raw),
        .ls_status    (ls_status),
        .ls_valid     (ls_valid),
        .temp_x10     (temp_x10),
        .humi_x10     (humi_x10),
        .lux          (lux),
        .adc_raw      (adc_raw),
        .raw_status   (raw_status),
        .status       (sensor_status),
        .data_ok      (data_ok)
    );

    // ========================================================================
    // 4. 报警判定（组长 + 主程序）
    // ========================================================================
    wire [3:0] alarm_level;
    wire [3:0] alarm_src;

    alarm_ctrl #(
        .CLK_HZ        (CLK_HZ),
        .ACTIVE_BUZZER (0)              // 0 = 无源蜂鸣器(方波) / 1 = 有源(电平)
    ) u_alarm_ctrl (
        .clk           (CLK100MHZ),
        .rst           (rst),
        .sample_tick   (tick_1hz),
        .temp_x10      (temp_x10),
        .humi_x10      (humi_x10),
        .lux           (lux),
        .sensor_status (sensor_status),
        .sw            (SW),
        .btn           (btn_db),
        .alarm_level   (alarm_level),
        .alarm_src     (alarm_src),
        .led           (LED),
        .buzz          (BUZZ)
    );

    // ========================================================================
    // 5. 显示
    // ========================================================================
    // 5.1 OLED + 8 位数码管（组长）
    disp_ctrl u_disp_oled (
        .clk         (CLK100MHZ),
        .rst         (rst),
        .tick_10hz   (tick_10hz),
        .tick_1khz   (tick_1khz),
        .temp_x10    (temp_x10),
        .humi_x10    (humi_x10),
        .lux         (lux),
        .alarm_level (alarm_level),
        .alarm_src   (alarm_src),
        .sensor_status(sensor_status),
        .oled_cs     (OLED_CS),
        .oled_sdin   (OLED_SDIN),
        .oled_sclk   (OLED_SCLK),
        .oled_dc     (OLED_DC),
        .oled_res    (OLED_RES),
        .an          (AN),
        .seg         (SEG)
    );

    // 5.2 VGA 外接显示器（成员C）
    vga_disp u_disp_vga (
        .clk         (CLK100MHZ),
        .rst         (rst),
        .temp_x10    (temp_x10),
        .humi_x10    (humi_x10),
        .lux         (lux),
        .alarm_level (alarm_level),
        .alarm_src   (alarm_src),
        .sw          (SW),
        .vga_r       (VGA_R),
        .vga_g       (VGA_G),
        .vga_b       (VGA_B),
        .vga_hs      (VGA_HS),
        .vga_vs      (VGA_VS)
    );

    // ========================================================================
    // 6. 串口上报（每 100 ms 一行，给上位机 / 串口助手）
    //    115200 8N1，走板载 FTDI 的 UART 通道（和 JTAG 共用一根 USB 线）
    // ========================================================================
    report_tx #(
        .CLK_HZ (CLK_HZ),
        .BAUD   (115200)
    ) u_report_tx (
        .clk           (CLK100MHZ),
        .rst           (rst),
        .report_tick   (tick_10hz),
        .temp_x10      (temp_x10),
        .humi_x10      (humi_x10),
        .lux           (lux),
        .alarm_level   (alarm_level),
        .sensor_status (sensor_status),
        .uart_txd      (UART_TXD)
    );

endmodule
