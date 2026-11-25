// ============================================================================
//  modules/m_disp_oled/rtl/disp_ctrl.v —— OLED + 8 位数码管显示（组长）
//  接口协议：docs/接口协议.md 第 4.4 节（端口已冻结）
//
//  【当前是空壳 Stub】
//    - OLED 五根线全部输出静态安全电平（CS=1 / SCLK=0 / SDIN=0 / DC=0 / RES=1）；
//    - 数码管 AN、SEG 全 1 = 全灭（共阳极、低有效）。
//    这样整个系统现在就能综合、能上板，只是屏幕上是黑的。
//
//  ---------------------------------------------------------------- 实现计划
//  不做"边算边发"（v2 那版是每来一个 tick 重新算一帧），改成：
//
//    text_engine ──► screen_ram (128×32，512 B，1 个 BRAM18) ──► oled_spi ──► 引脚
//        ▲                                                        │
//     temp/humi/lux/alarm                                    每 100 ms 刷一帧
//
//  1) text_engine：把数值格式化成字符（整数/一位小数/负号/单位），
//     用 common/font_rom.v 的 8×8 字模写进 screen_ram 对应页；
//  2) screen_ram：4 页 × 128 列，每字节 = 某列 8 个像素（bit0 在上）；
//  3) oled_spi：复用 v2 已验证的 SSD1306 初始化 + SPI 时序（2 MHz，CS/DC/RES 时序），
//     每帧先发 6 条定位命令再流 512 字节；
//  4) seg_disp：8 位数码管动态扫描（1 kHz/位，125 Hz 刷新），显示
//     "TT.T HH.H"：左边温度、右边湿度，中间两位留空或显示报警等级。
//
//  画面布局（16 字符 × 4 行，和 VGA 保持一致，见 docs/接口协议.md 第六节）：
//      ENV MONITOR
//      T:25.3C H:55.0%
//      L:320lx  ALM:2
//      OK
//
//  为什么先写显存再发：v2 是"发的时候现算"，只适合显示固定内容（时间）。
//  现在有 4 行文字 + 多组数字，必须先渲染到显存再一次发出去，SPI 速率才够。
// ============================================================================
module disp_ctrl (
    input  wire               clk,
    input  wire               rst,
    input  wire               tick_10hz,     // OLED 刷新节拍
    input  wire               tick_1khz,     // 数码管扫描节拍
    input  wire signed [15:0] temp_x10,
    input  wire        [15:0] humi_x10,
    input  wire        [15:0] lux,
    input  wire        [3:0]  alarm_level,
    input  wire        [3:0]  alarm_src,
    output wire               oled_cs,
    output wire               oled_sdin,
    output wire               oled_sclk,
    output wire               oled_dc,
    output wire               oled_res,
    output wire [7:0]         an,
    output wire [7:0]         seg
);

    // ---------------- 空壳：OLED 输出安全静态电平 ----------------
    assign oled_cs   = 1'b1;    // 片选无效
    assign oled_sdin = 1'b0;
    assign oled_sclk = 1'b0;
    assign oled_dc   = 1'b0;
    assign oled_res  = 1'b1;    // 不复位（低有效）

    // ---------------- 空壳：数码管全灭 ----------------
    assign an  = 8'hFF;         // 位选低有效 → 全 1 表示都不选
    assign seg = 8'hFF;         // 段选低有效 → 全 1 表示全灭

endmodule
