// ============================================================================
//  modules/m_disp_oled/rtl/disp_ctrl.v —— OLED 仪表盘（OLED + 数码管）
//  负责人：组长
//
//  结构：
//      text_engine  4 行 × 16 字符文本缓冲（每 100 ms 重新格式化）
//          ↓ (page, idx) → ch
//      font_rom     8×8 字模（common/font_rom.v，由 tools/gen_font.py 生成）
//          ↓ (ch, char_col) → 8 个像素
//      oled_spi     SSD1306 初始化 + 每 100 ms 刷一帧（512 字节）
//
//  画面：
//      ENV MONITOR
//      T:+25.3C H:55.0%
//      L:0320lx ALM:2
//      OK
//
//  数码管（8 位）：本版暂未驱动（AN/SEG 全灭）。先把 OLED 这条硬件通路验掉，
//  数码管下一步补（`tick_1khz` 端口先留着给扫描用）。
// ============================================================================
module disp_ctrl (
    input  wire               clk,
    input  wire               rst,
    input  wire               tick_10hz,     // 刷新节拍：OLED 每 100 ms 一帧
    input  wire               tick_1khz,     // 数码管扫描节拍（本版未用）
    input  wire signed [15:0] temp_x10,
    input  wire        [15:0] humi_x10,
    input  wire        [15:0] lux,
    input  wire        [3:0]  alarm_level,
    input  wire        [3:0]  alarm_src,
    input  wire        [7:0]  sensor_status, // 快照汇总（判断 SENSOR FAIL）
    output wire               oled_cs,
    output wire               oled_sdin,
    output wire               oled_sclk,
    output wire               oled_dc,
    output wire               oled_res,
    output wire [7:0]         an,
    output wire [7:0]         seg
);

    // ---------------- 文本缓冲 ↔ 字模 ↔ OLED ----------------
    wire [1:0] page;
    wire [3:0] char_idx;
    wire [2:0] char_col;
    wire [7:0] ch;
    wire [7:0] pix;

    text_engine u_text (
        .clk           (clk),
        .rst           (rst),
        .refresh_tick  (tick_10hz),
        .temp_x10      (temp_x10),
        .humi_x10      (humi_x10),
        .lux           (lux),
        .alarm_level   (alarm_level),
        .alarm_src     (alarm_src),
        .sensor_status (sensor_status),
        .page          (page),
        .idx           (char_idx),
        .ch            (ch)
    );

    font_rom u_font (
        .ch   (ch),
        .col  (char_col),
        .bits (pix)
    );

    oled_spi u_oled (
        .clk       (clk),
        .rst       (rst),
        .frame_req (tick_10hz),
        .pix_byte  (pix),
        .page      (page),
        .char_idx  (char_idx),
        .char_col  (char_col),
        .oled_cs   (oled_cs),
        .oled_sdin (oled_sdin),
        .oled_sclk (oled_sclk),
        .oled_dc   (oled_dc),
        .oled_res  (oled_res)
    );

    // ---------------- 数码管：本版全灭（下一步实现）----------------
    assign an  = 8'hFF;
    assign seg = 8'hFF;

endmodule
