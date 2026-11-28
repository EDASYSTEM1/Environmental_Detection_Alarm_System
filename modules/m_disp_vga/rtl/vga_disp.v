// ============================================================================
//  modules/m_disp_vga/rtl/vga_disp.v
//  VGA 640x480@60Hz 控制面板菜单栏 + 温/湿/光监控曲线图顶层（成员C）
//
//  严格遵守接口协议 v1.3 与团队硬规范：
//    1) 全模块单一 100 MHz clk，复用 common/vga_timing.v 的 25 MHz pix_en，
//       不派生时钟、不例化第二个 vga_timing；
//    2) RGB444 全部在 pix_en 拍寄存输出，消隐期强制全黑 12'h000；
//    3) 利用 4 拍/像素（100 MHz vs 25 MHz pix_en）构建 4 级像素流水线
//       （S1 几何/字符预译码 -> S2 共享曲线引擎/字库 -> S3 图文合成 -> pix_en 输出），
//       在零水平错位前提下满足 100 MHz 单周期时序收敛；
//    4) 相对接口协议 v1.3 仅最小化增补 1 个方向键端口 btn[4:0]（用于 BTNL/R
//       切 4 页菜单、BTNU/D 切页内焦点与曲线放大视图，不占用 BTNC 报警消音键）；
//       同时兼容 SW[14:13] 切页与 SW[15] 深浅配色主题切换。
// ============================================================================
`default_nettype none

module vga_disp #(
    parameter integer SAMPLE_FRAMES = 60       // 每 60 帧 (≈1s) 采集 1 个曲线点
) (
    input  wire               clk,             // 100 MHz
    input  wire               rst,             // 高有效同步复位
    input  wire signed [15:0] temp_x10,        // 0.1 C 有符号
    input  wire        [15:0] humi_x10,        // 0.1 %RH 无符号
    input  wire        [15:0] lux,             // 1 lx 无符号
    input  wire        [3:0]  alarm_level,     // 0 正常 / 1 注意 / 2 警告 / 3 严重
    input  wire        [3:0]  alarm_src,       // {故障, 光照, 湿度, 温度}
    input  wire        [7:0]  sensor_status,   // 快照汇总
    input  wire        [15:0] sw,              // 16 位拨码开关
    input  wire        [4:0]  btn,             // {BTNR, BTNL, BTND, BTNU, BTNC} 高有效
    output reg  [3:0]         vga_r,
    output reg  [3:0]         vga_g,
    output reg  [3:0]         vga_b,
    output wire               vga_hs,
    output wire               vga_vs
);

    // ========================================================================
    // 1. VGA 640x480@60Hz 时序基座（共享基础设施，不派生时钟）
    // ========================================================================
    wire       pix_en;
    wire [9:0] x;
    wire [9:0] y;
    wire       video_on;

    vga_timing u_vga_timing (
        .clk      (clk),
        .rst      (rst),
        .pix_en   (pix_en),
        .x        (x),
        .y        (y),
        .hs       (vga_hs),
        .vs       (vga_vs),
        .video_on (video_on)
    );

    // 场消隐首拍脉冲（每帧一次，触发 BCD 转换与历史曲线采样）
    wire frame_start = pix_en && (x == 10'd0) && (y == 10'd480);

    // ========================================================================
    // 2. 菜单导航控制器（方向键 + SW[14:13] 兼容 + SW[15] 主题）
    // ========================================================================
    wire [1:0] tab_id;
    wire [1:0] item_idx;
    wire       theme_light;

    vga_menu_ctrl u_menu_ctrl (
        .clk         (clk),
        .rst         (rst),
        .btn         (btn),
        .sw          (sw),
        .tab_id      (tab_id),
        .item_idx    (item_idx),
        .theme_light (theme_light)
    );

    // ========================================================================
    // 3. 三路监控曲线环形缓冲（3 x 128 x 7b + MIN/MAX + 阈值红线高度）
    // ========================================================================
    // 根据当前页签计算历史点读下标 rd_idx (0..127)，纯位移零除法
    reg [6:0] rd_idx;
    always @(*) begin
        if (tab_id == 2'd0) begin
            // 01 OVERVIEW 迷你曲线区 x=344..599 (256px = 128 * 2px)
            if (x >= 10'd344 && x < 10'd600)
                rd_idx = (x - 10'd344) >> 1;
            else
                rd_idx = 7'd0;
        end else if (tab_id == 2'd1 && item_idx == 2'd0) begin
            // 02 CURVES 三轨同屏 x=104..615 (512px = 128 * 4px)
            if (x >= 10'd104 && x < 10'd616)
                rd_idx = (x - 10'd104) >> 2;
            else
                rd_idx = 7'd0;
        end else if (tab_id == 2'd1 && item_idx != 2'd0) begin
            // 02 CURVES 单路放大 x=84..595 (512px = 128 * 4px)
            if (x >= 10'd84 && x < 10'd596)
                rd_idx = (x - 10'd84) >> 2;
            else
                rd_idx = 7'd0;
        end else begin
            rd_idx = 7'd0;
        end
    end

    wire [6:0]         t_cur_q, t_prev_q;
    wire [6:0]         h_cur_q, h_prev_q;
    wire [6:0]         l_cur_q, l_prev_q;
    wire [6:0]         th_t_q, th_h_q, th_l_q;
    wire signed [15:0] t_min, t_max;
    wire        [15:0] h_min, h_max;
    wire        [15:0] l_min, l_max;

    vga_history #(
        .SAMPLE_FRAMES (SAMPLE_FRAMES)
    ) u_history (
        .clk           (clk),
        .rst           (rst),
        .frame_start   (frame_start),
        .temp_x10      (temp_x10),
        .humi_x10      (humi_x10),
        .lux           (lux),
        .sensor_status (sensor_status),
        .sw_thresh     (sw[9:0]),
        .rd_idx        (rd_idx),
        .t_cur_q       (t_cur_q),
        .t_prev_q      (t_prev_q),
        .h_cur_q       (h_cur_q),
        .h_prev_q      (h_prev_q),
        .l_cur_q       (l_cur_q),
        .l_prev_q      (l_prev_q),
        .th_t_q        (th_t_q),
        .th_h_q        (th_h_q),
        .th_l_q        (th_l_q),
        .t_min         (t_min),
        .t_max         (t_max),
        .h_min         (h_min),
        .h_max         (h_max),
        .l_min         (l_min),
        .l_max         (l_max)
    );

    // ========================================================================
    // 4. 场消隐期 BCD 转换 + 拨码阈值查表
    // ========================================================================
    wire signed [15:0] stat_min_sel = (item_idx == 2'd1) ? t_min :
                                      (item_idx == 2'd2) ? $signed(h_min) : $signed(l_min);
    wire signed [15:0] stat_max_sel = (item_idx == 2'd1) ? t_max :
                                      (item_idx == 2'd2) ? $signed(h_max) : $signed(l_max);
    wire               stat_signed  = (item_idx == 2'd1);

    wire       t_neg;
    wire [3:0] t_d2, t_d1, t_d0;
    wire [3:0] h_d2, h_d1, h_d0;
    wire [3:0] l_d3, l_d2, l_d1, l_d0;
    wire       min_neg, max_neg;
    wire [3:0] min_d3, min_d2, min_d1, min_d0;
    wire [3:0] max_d3, max_d2, max_d1, max_d0;
    wire [3:0] th_t_d1, th_t_d0;
    wire [3:0] th_h_d2, th_h_d1, th_h_d0;
    wire [3:0] th_l_d2, th_l_d1, th_l_d0;

    vga_bcd u_bcd (
        .clk         (clk),
        .rst         (rst),
        .frame_start (frame_start),
        .temp_x10    (temp_x10),
        .humi_x10    (humi_x10),
        .lux         (lux),
        .stat_min    (stat_min_sel),
        .stat_max    (stat_max_sel),
        .stat_signed (stat_signed),
        .sw_thresh   (sw[9:0]),
        .t_neg       (t_neg),
        .t_d2        (t_d2),    .t_d1 (t_d1),    .t_d0 (t_d0),
        .h_d2        (h_d2),    .h_d1 (h_d1),    .h_d0 (h_d0),
        .l_d3        (l_d3),    .l_d2 (l_d2),    .l_d1 (l_d1),    .l_d0 (l_d0),
        .min_neg     (min_neg),
        .min_d3      (min_d3),  .min_d2 (min_d2), .min_d1 (min_d1), .min_d0 (min_d0),
        .max_neg     (max_neg),
        .max_d3      (max_d3),  .max_d2 (max_d2), .max_d1 (max_d1), .max_d0 (max_d0),
        .th_t_d1     (th_t_d1), .th_t_d0 (th_t_d0),
        .th_h_d2     (th_h_d2), .th_h_d1 (th_h_d1), .th_h_d0 (th_h_d0),
        .th_l_d2     (th_l_d2), .th_l_d1 (th_l_d1), .th_l_d0 (th_l_d0)
    );

    // ========================================================================
    // 5. 全屏文字映射 + 流水级 1 寄存（对齐 u_history 同步读出）
    // ========================================================================
    wire       txt_en_w;
    wire [7:0] char_code_w;
    wire [2:0] font_row_w;
    wire [2:0] font_col_w;
    wire [3:0] text_role_w;

    vga_text_map u_text_map (
        .x             (x),
        .y             (y),
        .tab_id        (tab_id),
        .item_idx      (item_idx),
        .alarm_level   (alarm_level),
        .alarm_src     (alarm_src),
        .sensor_status (sensor_status),
        .sw            (sw),
        .t_neg         (t_neg),
        .t_d2          (t_d2),    .t_d1 (t_d1),    .t_d0 (t_d0),
        .h_d2          (h_d2),    .h_d1 (h_d1),    .h_d0 (h_d0),
        .l_d3          (l_d3),    .l_d2 (l_d2),    .l_d1 (l_d1),    .l_d0 (l_d0),
        .min_neg       (min_neg),
        .min_d3        (min_d3),  .min_d2 (min_d2), .min_d1 (min_d1), .min_d0 (min_d0),
        .max_neg       (max_neg),
        .max_d3        (max_d3),  .max_d2 (max_d2), .max_d1 (max_d1), .max_d0 (max_d0),
        .th_t_d1       (th_t_d1), .th_t_d0 (th_t_d0),
        .th_h_d2       (th_h_d2), .th_h_d1 (th_h_d1), .th_h_d0 (th_h_d0),
        .th_l_d2       (th_l_d2), .th_l_d1 (th_l_d1), .th_l_d0 (th_l_d0),
        .txt_en        (txt_en_w),
        .char_code     (char_code_w),
        .font_row      (font_row_w),
        .font_col      (font_col_w),
        .text_role     (text_role_w)
    );

    reg       txt_en_s1;
    reg [7:0] char_code_s1;
    reg [2:0] font_row_s1;
    reg [2:0] font_col_s1;
    reg [3:0] text_role_s1;

    always @(posedge clk) begin
        if (rst) begin
            txt_en_s1    <= 1'b0;
            char_code_s1 <= 8'h20;
            font_row_s1  <= 3'd0;
            font_col_s1  <= 3'd0;
            text_role_s1 <= 4'd0;
        end else begin
            txt_en_s1    <= txt_en_w;
            char_code_s1 <= char_code_w;
            font_row_s1  <= font_row_w;
            font_col_s1  <= font_col_w;
            text_role_s1 <= text_role_w;
        end
    end

    // 字库点阵查询（Stage 1 -> Stage 2）
    wire [7:0] font_row_bits;
    vga_font u_font (
        .ch       (char_code_s1),
        .row      (font_row_s1),
        .row_bits (font_row_bits)
    );
    wire font_pix_s1 = txt_en_s1 && font_row_bits[3'd7 - font_col_s1];

    // ========================================================================
    // 6. RGB444 调色板（支持 SW[15] 切换深色仪表 / 高对比浅色主题）
    // ========================================================================
    wire th_ok = sensor_status[0] && !sensor_status[2];
    wire ls_ok = sensor_status[1] && !sensor_status[3];
    wire fault = !th_ok || !ls_ok;
    wire hot   = alarm_src[0];
    wire wet   = alarm_src[1];
    wire dark  = alarm_src[2];

    wire [11:0] c_bg          = theme_light ? 12'hDEF : 12'h112;
    wire [11:0] c_header      = (alarm_level >= 4'd3 || fault) ? (theme_light ? 12'h900 : 12'h700) :
                                (alarm_level == 4'd2)          ? (theme_light ? 12'hB40 : 12'h830) :
                                (alarm_level == 4'd1)          ? (theme_light ? 12'h860 : 12'h540) :
                                                                 (theme_light ? 12'h136 : 12'h124);
    wire [11:0] c_badge       = (alarm_level >= 4'd2 || fault) ? 12'hF32 :
                                (alarm_level == 4'd1)          ? 12'hDA0 : 12'h2A4;
    wire [11:0] c_menu_bg     = theme_light ? 12'hBCE : 12'h123;
    wire [11:0] c_tab_act     = theme_light ? 12'hFFF : 12'h247;
    wire [11:0] c_accent      = theme_light ? 12'h05C : 12'h3DF;
    wire [11:0] c_card_bg     = theme_light ? 12'hFFF : 12'h123;
    wire [11:0] c_card_focus  = theme_light ? 12'hEEF : 12'h235;
    wire [11:0] c_border      = theme_light ? 12'h89B : 12'h346;
    wire [11:0] c_plot_bg     = theme_light ? 12'hF8F : 12'h012; // 浅色极淡灰蓝 / 深色示波黑蓝
    wire [11:0] c_plot_bg_ok  = theme_light ? 12'hEFF : 12'h012;
    wire [11:0] c_grid        = theme_light ? 12'hCDE : 12'h124;
    wire [11:0] c_footer_bg   = theme_light ? 12'h124 : 12'h011;
    wire [11:0] c_text_main   = theme_light ? 12'h112 : 12'hFFF;
    wire [11:0] c_text_muted  = theme_light ? 12'h457 : 12'h8AC;
    wire [11:0] c_ok          = theme_light ? 12'h083 : 12'h3E6;
    wire [11:0] c_warn        = theme_light ? 12'hB70 : 12'hFC2;
    wire [11:0] c_err         = theme_light ? 12'hC11 : 12'hF43;
    wire [11:0] c_temp        = theme_light ? 12'hD40 : 12'hF83;
    wire [11:0] c_humi        = theme_light ? 12'h07C : 12'h3CF;
    wire [11:0] c_lux         = theme_light ? 12'hB70 : 12'hFD3;
    wire [11:0] c_fill_norm   = theme_light ? 12'hCEF : 12'h123;
    wire [11:0] c_fill_err    = theme_light ? 12'hFCC : 12'h311;

    // 避免未使用的 c_plot_bg 告警
    wire [11:0] c_plot = (c_plot_bg & 12'h000) | c_plot_bg_ok;

    // 文字角色解码成 RGB444
    reg [11:0] text_rgb;
    always @(*) begin
        case (text_role_s1)
            4'd0 : text_rgb = c_text_main;
            4'd1 : text_rgb = c_text_muted;
            4'd2 : text_rgb = c_accent;
            4'd3 : text_rgb = 12'hFFF;
            4'd4 : text_rgb = c_ok;
            4'd5 : text_rgb = c_warn;
            4'd6 : text_rgb = c_err;
            4'd7 : text_rgb = c_temp;
            4'd8 : text_rgb = c_humi;
            4'd9 : text_rgb = c_lux;
            4'd10: text_rgb = 12'h9CF;
            default: text_rgb = c_text_main;
        endcase
    end

    // ========================================================================
    // 7. 图形层 + 监控曲线 3 级流水引擎（复用 4 拍/像素窗口，零水平错位）
    //    - Stage 0 -> S1 (pdiv=0->1)：非曲线底图/网格 + 曲线区几何/通道预译码，
    //      与 u_history 同步读出及 u_text_map 寄存严格同拍对齐；
    //    - Stage 1 -> S2 (pdiv=1->2)：共享单路曲线判定引擎（无 9 份重复展开、
    //      无 min/max 串行进位链），与 vga_font 点阵查表并行；
    //    - Stage 2 -> S3 (pdiv=2->3)：曲线颜色覆写 + 文字前景合成进 rgb_s3；
    //    - Stage 3 -> Out (pdiv=3->0, pix_en=1)：消隐全黑 + RGB444 寄存输出。
    // ========================================================================
    wire [9:0] p192_dx = x - 10'd84;
    wire [9:0] p192_dy = y - 10'd190;

    reg [11:0] gfx_base_w;
    reg [1:0]  plot_mode_w;      // 0: 非曲线区, 1: plot64 迷你, 2: plot64 三轨, 3: plot192 单路放大
    reg [1:0]  plot_ch_w;        // 0: 温度, 1: 湿度, 2: 光照
    reg [2:0]  plot_dx_w;        // (x - bx)[2:0]
    reg [9:0]  plot_y_bot_w;     // 波形基线纵坐标 (plot64: by+69, plot192: 387)
    reg        plot_above_bad_w; // 1: > 阈值报警(温湿), 0: < 阈值报警(光照)
    reg        plot_offline_w;
    reg [11:0] plot_ch_color_w;

    reg [9:0]  cy;
    reg [1:0]  c_idx;
    reg        is_focus, is_bad;
    reg [11:0] ch_color;

    always @(*) begin
        gfx_base_w       = c_bg;
        plot_mode_w      = 2'd0;
        plot_ch_w        = 2'd0;
        plot_dx_w        = 3'd0;
        plot_y_bot_w     = 10'd180;
        plot_above_bad_w = 1'b1;
        plot_offline_w   = 1'b0;
        plot_ch_color_w  = c_temp;
        cy               = 10'd0;
        c_idx            = 2'd0;
        is_focus         = 1'b0;
        is_bad           = 1'b0;
        ch_color         = c_temp;

        // ===== ZONE 1: 顶部标题栏 (y = 0..47) =====
        if (y < 10'd48) begin
            gfx_base_w = c_header;
            // 右侧报警徽标 (x=464..623, y=10..37)
            if (x >= 10'd464 && x < 10'd624 && y >= 10'd10 && y < 10'd38) begin
                if (x == 10'd464 || x == 10'd623 || y == 10'd10 || y == 10'd37)
                    gfx_base_w = 12'hFFF;
                else
                    gfx_base_w = c_badge;
            end
        end

        // ===== ZONE 2: 控制菜单导航栏 (y = 48..87) =====
        else if (y >= 10'd48 && y < 10'd88) begin
            if (x < 10'd160)      c_idx = 2'd0;
            else if (x < 10'd320) c_idx = 2'd1;
            else if (x < 10'd480) c_idx = 2'd2;
            else                  c_idx = 2'd3;

            gfx_base_w = (tab_id == c_idx) ? c_tab_act : c_menu_bg;
            // 选中页签底部 4px 青色激活条
            if ((tab_id == c_idx) && (y >= 10'd84))
                gfx_base_w = c_accent;
            // 页签间竖向分隔线
            if ((x == 10'd159 || x == 10'd319 || x == 10'd479) && (y >= 10'd52 && y < 10'd84))
                gfx_base_w = c_border;
        end

        // ===== ZONE 4: 底部栏 (y = 432..479) =====
        else if (y >= 10'd432) begin
            gfx_base_w = (y < 10'd434) ? c_border : c_footer_bg;
        end

        // ===== ZONE 3: 主工作区 (y = 88..431) =====
        else begin
            case (tab_id)
                // ------------------------------------------------------------
                // PAGE 0: 01 OVERVIEW（3 卡片 + 迷你监控曲线）
                // ------------------------------------------------------------
                2'd0: begin
                    if (x >= 10'd16 && x < 10'd624 &&
                        ((y >= 10'd100 && y < 10'd198) ||
                         (y >= 10'd208 && y < 10'd306) ||
                         (y >= 10'd316 && y < 10'd414))) begin
                        if (y < 10'd198) begin
                            c_idx = 2'd0; cy = 10'd100; is_bad = hot || !th_ok; ch_color = c_temp;
                        end else if (y < 10'd306) begin
                            c_idx = 2'd1; cy = 10'd208; is_bad = wet || !th_ok; ch_color = c_humi;
                        end else begin
                            c_idx = 2'd2; cy = 10'd316; is_bad = dark || !ls_ok; ch_color = c_lux;
                        end
                        is_focus = (item_idx == c_idx);

                        // 卡片底色、边框与左侧 5px 焦点条
                        gfx_base_w = is_focus ? c_card_focus : c_card_bg;
                        if (x == 10'd16 || x == 10'd623 || y == cy || y == cy + 10'd97)
                            gfx_base_w = is_focus ? c_accent : (is_bad ? c_err : c_border);
                        if (is_focus && x < 10'd21)
                            gfx_base_w = c_accent;
                        // 标题左侧通道色块
                        if (x >= 10'd28 && x < 10'd36 && y >= cy + 10'd12 && y < cy + 10'd24)
                            gfx_base_w = ch_color;

                        // 右侧实时迷你曲线框 (x=344..599, y=cy+11..cy+86)
                        if (x >= 10'd344 && x < 10'd600 && y >= cy + 10'd11 && y < cy + 10'd87) begin
                            if (x == 10'd344 || x == 10'd599 || y == cy + 10'd11 || y == cy + 10'd86) begin
                                gfx_base_w = c_border;
                            end else begin
                                gfx_base_w = c_plot;
                                // 迷你虚线网格 (中线 + 四等分竖线)
                                if ((y == cy + 10'd49 && x[1:0] < 2'd2) ||
                                    ((x == 10'd408 || x == 10'd472 || x == 10'd536) && y[1:0] < 2'd2))
                                    gfx_base_w = c_grid;

                                // 交给 Stage 2 共享曲线引擎 (bx=344=43*8 -> dx[2:0]=x[2:0], by+69=cy+80)
                                plot_mode_w      = 2'd1;
                                plot_ch_w        = c_idx;
                                plot_dx_w        = x[2:0];
                                plot_y_bot_w     = cy + 10'd80;
                                plot_above_bad_w = (c_idx != 2'd2);
                                plot_offline_w   = (c_idx == 2'd2) ? !ls_ok : !th_ok;
                                plot_ch_color_w  = ch_color;
                            end
                        end
                    end
                end

                // ------------------------------------------------------------
                // PAGE 1: 02 CURVES（子视图选择条 + 三轨同屏 / 单路放大）
                // ------------------------------------------------------------
                2'd1: begin
                    // 子视图选择按钮条 (y = 94..117)
                    if (y >= 10'd94 && y < 10'd118) begin
                        if ((x >= 10'd16  && x < 10'd162) ||
                            (x >= 10'd170 && x < 10'd316) ||
                            (x >= 10'd324 && x < 10'd470) ||
                            (x >= 10'd478 && x < 10'd624)) begin
                            if (x < 10'd162)      c_idx = 2'd0;
                            else if (x < 10'd316) c_idx = 2'd1;
                            else if (x < 10'd470) c_idx = 2'd2;
                            else                  c_idx = 2'd3;
                            is_focus = (item_idx == c_idx);
                            gfx_base_w = is_focus ? c_tab_act : c_card_bg;
                            if (y == 10'd94 || y == 10'd117 ||
                                x == 10'd16  || x == 10'd161 ||
                                x == 10'd170 || x == 10'd315 ||
                                x == 10'd324 || x == 10'd469 ||
                                x == 10'd478 || x == 10'd623)
                                gfx_base_w = is_focus ? c_accent : c_border;
                        end
                    end
                    // --- 子视图 0: 三轨同屏 ---
                    else if (item_idx == 2'd0) begin
                        if (x >= 10'd16 && x < 10'd624 &&
                            ((y >= 10'd124 && y < 10'd216) ||
                             (y >= 10'd222 && y < 10'd314) ||
                             (y >= 10'd320 && y < 10'd412))) begin
                            if (y < 10'd216) begin
                                c_idx = 2'd0; cy = 10'd124; is_bad = hot || !th_ok; ch_color = c_temp;
                            end else if (y < 10'd314) begin
                                c_idx = 2'd1; cy = 10'd222; is_bad = wet || !th_ok; ch_color = c_humi;
                            end else begin
                                c_idx = 2'd2; cy = 10'd320; is_bad = dark || !ls_ok; ch_color = c_lux;
                            end

                            gfx_base_w = c_card_bg;
                            if (x == 10'd16 || x == 10'd623 || y == cy || y == cy + 10'd91)
                                gfx_base_w = is_bad ? c_err : c_border;
                            // 左侧通道色标
                            if (x >= 10'd24 && x < 10'd30 && y >= cy + 10'd8 && y < cy + 10'd22)
                                gfx_base_w = ch_color;

                            // 512px 宽示波区 (x=104..615, y=cy+8..cy+83)
                            if (x >= 10'd104 && x < 10'd616 && y >= cy + 10'd8 && y < cy + 10'd84) begin
                                if (x == 10'd104 || x == 10'd615 || y == cy + 10'd8 || y == cy + 10'd83) begin
                                    gfx_base_w = c_border;
                                end else begin
                                    gfx_base_w = c_plot;
                                    // 网格线
                                    if ((y == cy + 10'd46 && x[1:0] < 2'd2) ||
                                        ((x == 10'd232 || x == 10'd360 || x == 10'd488) && y[1:0] < 2'd2))
                                        gfx_base_w = c_grid;

                                    // 交给 Stage 2 共享曲线引擎 (bx=104=13*8 -> dx[2:0]=x[2:0], by+69=cy+77)
                                    plot_mode_w      = 2'd2;
                                    plot_ch_w        = c_idx;
                                    plot_dx_w        = x[2:0];
                                    plot_y_bot_w     = cy + 10'd77;
                                    plot_above_bad_w = (c_idx != 2'd2);
                                    plot_offline_w   = (c_idx == 2'd2) ? !ls_ok : !th_ok;
                                    plot_ch_color_w  = ch_color;
                                end
                            end
                        end
                    end
                    // --- 子视图 1/2/3: 单路放大监控曲线 ---
                    else begin
                        ch_color = (item_idx == 2'd1) ? c_temp :
                                   (item_idx == 2'd2) ? c_humi : c_lux;
                        is_bad   = (item_idx == 2'd1) ? (hot || !th_ok) :
                                   (item_idx == 2'd2) ? (wet || !th_ok) : (dark || !ls_ok);

                        // 顶部统计栏卡片 (x=16..623, y=126..171)
                        if (x >= 10'd16 && x < 10'd624 && y >= 10'd126 && y < 10'd172) begin
                            gfx_base_w = c_card_bg;
                            if (x == 10'd16 || x == 10'd623 || y == 10'd126 || y == 10'd171)
                                gfx_base_w = is_bad ? c_err : ch_color;
                        end
                        // 大图主卡片 (x=16..623, y=180..421)
                        else if (x >= 10'd16 && x < 10'd624 && y >= 10'd180 && y < 10'd422) begin
                            gfx_base_w = c_card_bg;
                            if (x == 10'd16 || x == 10'd623 || y == 10'd180 || y == 10'd421)
                                gfx_base_w = c_border;

                            // 512x204 示波区 (x=84..595, y=190..393)
                            if (x >= 10'd84 && x < 10'd596 && y >= 10'd190 && y < 10'd394) begin
                                if (x == 10'd84 || x == 10'd595 || y == 10'd190 || y == 10'd393) begin
                                    gfx_base_w = c_border;
                                end else begin
                                    gfx_base_w = c_plot;
                                    // 虚线网格 (横线 240/288/336，竖线每 64px)
                                    if (((y == 10'd240 || y == 10'd288 || y == 10'd336) && p192_dx[1:0] < 2'd2) ||
                                        ((p192_dx[5:0] == 6'd0) && (p192_dx != 10'd0) && p192_dy[1:0] < 2'd2))
                                        gfx_base_w = c_grid;

                                    // 交给 Stage 2 共享曲线引擎 (192px 有效高度, 基线 y=387)
                                    plot_mode_w      = 2'd3;
                                    plot_ch_w        = (item_idx == 2'd1) ? 2'd0 :
                                                       (item_idx == 2'd2) ? 2'd1 : 2'd2;
                                    plot_dx_w        = p192_dx[2:0];
                                    plot_y_bot_w     = 10'd387;
                                    plot_above_bad_w = (item_idx != 2'd3);
                                    plot_offline_w   = (item_idx == 2'd3) ? !ls_ok : !th_ok;
                                    plot_ch_color_w  = ch_color;
                                end
                            end
                        end
                    end
                end

                // ------------------------------------------------------------
                // PAGE 2: 03 ALARM/CFG
                // ------------------------------------------------------------
                2'd2: begin
                    if (x >= 10'd20 && x < 10'd620 &&
                        ((y >= 10'd120 && y < 10'd170) || (y >= 10'd178 && y < 10'd228) ||
                         (y >= 10'd236 && y < 10'd286) || (y >= 10'd294 && y < 10'd344))) begin
                        if (y < 10'd170) begin c_idx = 2'd0; cy = 10'd120; is_bad = hot; end
                        else if (y < 10'd228) begin c_idx = 2'd1; cy = 10'd178; is_bad = wet; end
                        else if (y < 10'd286) begin c_idx = 2'd2; cy = 10'd236; is_bad = dark; end
                        else begin c_idx = 2'd3; cy = 10'd294; is_bad = alarm_src[3] || fault; end
                        is_focus = (item_idx == c_idx);

                        gfx_base_w = is_focus ? c_card_focus : c_card_bg;
                        if (x == 10'd20 || x == 10'd619 || y == cy || y == cy + 10'd49)
                            gfx_base_w = is_focus ? c_accent : (is_bad ? c_err : c_border);
                        if (is_focus && x < 10'd25)
                            gfx_base_w = c_accent;

                        // 右侧状态徽标块 (x=512..603, y=cy+12..cy+37)
                        if (x >= 10'd512 && x < 10'd604 && y >= cy + 10'd12 && y < cy + 10'd38)
                            gfx_base_w = is_bad ? c_err : c_ok;
                    end
                    // 底部蜂鸣器汇总卡片 (x=20..619, y=358..415)
                    else if (x >= 10'd20 && x < 10'd620 && y >= 10'd358 && y < 10'd416) begin
                        gfx_base_w = c_card_bg;
                        if (x == 10'd20 || x == 10'd619 || y == 10'd358 || y == 10'd415)
                            gfx_base_w = c_border;
                    end
                end

                // ------------------------------------------------------------
                // PAGE 3: 04 DIAG
                // ------------------------------------------------------------
                default: begin
                    if (x >= 10'd20 && x < 10'd620 &&
                        ((y >= 10'd124 && y < 10'd184) || (y >= 10'd196 && y < 10'd256) ||
                         (y >= 10'd268 && y < 10'd328) || (y >= 10'd340 && y < 10'd400))) begin
                        if (y < 10'd184) begin c_idx = 2'd0; cy = 10'd124; is_bad = !th_ok; end
                        else if (y < 10'd256) begin c_idx = 2'd1; cy = 10'd196; is_bad = !ls_ok; end
                        else if (y < 10'd328) begin c_idx = 2'd2; cy = 10'd268; is_bad = 1'b0; end
                        else begin c_idx = 2'd3; cy = 10'd340; is_bad = 1'b0; end
                        is_focus = (item_idx == c_idx);

                        gfx_base_w = is_focus ? c_card_focus : c_card_bg;
                        if (x == 10'd20 || x == 10'd619 || y == cy || y == cy + 10'd59)
                            gfx_base_w = is_focus ? c_accent : (is_bad ? c_err : c_border);
                        if (is_focus && x < 10'd25)
                            gfx_base_w = c_accent;
                    end
                end
            endcase
        end
    end

    // 将相对波形基线高度在 Stage 0 预先算好（h_pix = y_bot - y），消除 Stage 1 的 y 减法链
    wire signed [10:0] plot_h_pix_w    = $signed({1'b0, plot_y_bot_w}) - $signed({1'b0, y});
    wire signed [10:0] plot_h_pix_p1_w = $signed({1'b0, plot_y_bot_w}) + 11'sd1 - $signed({1'b0, y});
    wire               plot_fill_ok_w  = (y <= 10'd391) && (x[1:0] == 2'd0) && (y[1:0] == 2'd0);

    // ---- Stage 1 寄存（与 u_history 输出及 *_s1 文本信息同拍对齐）----
    reg [11:0]        gfx_base_s1;
    reg [1:0]         plot_mode_s1;
    reg [1:0]         plot_ch_s1;
    reg [2:0]         plot_dx_s1;
    reg signed [10:0] plot_h_pix_s1;
    reg signed [10:0] plot_h_pix_p1_s1;
    reg               plot_fill_ok_s1;
    reg               plot_above_bad_s1;
    reg               plot_offline_s1;
    reg [11:0]        plot_ch_color_s1;

    always @(posedge clk) begin
        if (rst) begin
            gfx_base_s1       <= 12'h000;
            plot_mode_s1      <= 2'd0;
            plot_ch_s1        <= 2'd0;
            plot_dx_s1        <= 3'd0;
            plot_h_pix_s1     <= 11'sd0;
            plot_h_pix_p1_s1  <= 11'sd0;
            plot_fill_ok_s1   <= 1'b0;
            plot_above_bad_s1 <= 1'b1;
            plot_offline_s1   <= 1'b0;
            plot_ch_color_s1  <= 12'h000;
        end else begin
            gfx_base_s1       <= gfx_base_w;
            plot_mode_s1      <= plot_mode_w;
            plot_ch_s1        <= plot_ch_w;
            plot_dx_s1        <= plot_dx_w;
            plot_h_pix_s1     <= plot_h_pix_w;
            plot_h_pix_p1_s1  <= plot_h_pix_p1_w;
            plot_fill_ok_s1   <= plot_fill_ok_w;
            plot_above_bad_s1 <= plot_above_bad_w;
            plot_offline_s1   <= plot_offline_w;
            plot_ch_color_s1  <= plot_ch_color_w;
        end
    end

    // ---- Stage 1 -> Stage 2：共享单路曲线判定（并行比较，无 min/max 串行级联）----
    reg [6:0] q_cur_s1, q_prev_s1, q_th_s1;
    always @(*) begin
        case (plot_ch_s1)
            2'd0: begin
                q_cur_s1  = t_cur_q;
                q_prev_s1 = t_prev_q;
                q_th_s1   = th_t_q;
            end
            2'd1: begin
                q_cur_s1  = h_cur_q;
                q_prev_s1 = h_prev_q;
                q_th_s1   = th_h_q;
            end
            default: begin
                q_cur_s1  = l_cur_q;
                q_prev_s1 = l_prev_q;
                q_th_s1   = th_l_q;
            end
        endcase
    end

    wire       is_p192_s1    = (plot_mode_s1 == 2'd3);
    wire [7:0] s_cur_s1      = is_p192_s1 ? ({1'b0, q_cur_s1}  + {2'd0, q_cur_s1[6:1]})  : {2'd0, q_cur_s1[6:1]};
    wire [7:0] s_prev_s1     = is_p192_s1 ? ({1'b0, q_prev_s1} + {2'd0, q_prev_s1[6:1]}) : {2'd0, q_prev_s1[6:1]};
    wire [7:0] s_th_s1       = is_p192_s1 ? ({1'b0, q_th_s1}   + {2'd0, q_th_s1[6:1]})   : {2'd0, q_th_s1[6:1]};

    wire signed [10:0] s_cur_ext  = {3'b000, s_cur_s1};
    wire signed [10:0] s_prev_ext = {3'b000, s_prev_s1};
    wire signed [10:0] s_th_ext   = {3'b000, s_th_s1};

    // 代数等价：h <= max(a,b) <=> (h<=a)||(h<=b)；h >= min(a,b) <=> (h>=a)||(h>=b)
    wire le_cur    = (plot_h_pix_s1 <= s_cur_ext);
    wire le_prev   = (plot_h_pix_s1 <= s_prev_ext);
    wire ge_cur    = (plot_h_pix_s1 >= s_cur_ext);
    wire ge_prev   = (plot_h_pix_s1 >= s_prev_ext);
    wire gep1_cur  = (plot_h_pix_p1_s1 >= s_cur_ext);
    wire gep1_prev = (plot_h_pix_p1_s1 >= s_prev_ext);

    wire hit_span_1px = (le_cur || le_prev) && (ge_cur || ge_prev);
    wire hit_span_2px = (le_cur || le_prev) && (gep1_cur || gep1_prev);
    wire hit_cur_1px  = (plot_h_pix_s1 == s_cur_ext);
    wire hit_cur_2px  = le_cur && gep1_cur;
    wire hit_th_1px   = (plot_h_pix_s1 == s_th_ext);
    wire hit_th_2px   = hit_th_1px || (plot_h_pix_p1_s1 == s_th_ext);
    wire hit_fill_192 = plot_fill_ok_s1 && (plot_h_pix_p1_s1 < s_cur_ext);
    wire plot_alert_s1 = plot_above_bad_s1 ? (q_cur_s1 > q_th_s1) : (q_cur_s1 < q_th_s1);

    // 曲线像素覆写码：0=保持底图/网格, 1=阈值红虚线, 2=正常曲线, 3=越限红曲线, 4=正常点阵底纹, 5=越限点阵底纹
    reg [2:0] plot_code_w;
    always @(*) begin
        plot_code_w = 3'd0;
        case (plot_mode_s1)
            2'd1: begin // 64px 迷你曲线 (1px 细线)
                if (hit_th_1px && (plot_dx_s1 < 3'd5))
                    plot_code_w = 3'd1;
                if (!plot_offline_s1 &&
                    (((plot_dx_s1[0] == 1'b0) && hit_span_1px) || hit_cur_1px))
                    plot_code_w = plot_alert_s1 ? 3'd3 : 3'd2;
            end
            2'd2: begin // 64px 三轨同屏曲线 (2px 粗线)
                if (hit_th_1px && (plot_dx_s1 < 3'd5))
                    plot_code_w = 3'd1;
                if (!plot_offline_s1 &&
                    (((plot_dx_s1[1:0] < 2'd2) && hit_span_2px) || hit_cur_2px))
                    plot_code_w = plot_alert_s1 ? 3'd3 : 3'd2;
            end
            2'd3: begin // 192px 单路放大曲线 (点阵底纹 + 2px 红虚线 + 2px 粗曲线)
                if (!plot_offline_s1 && hit_fill_192)
                    plot_code_w = plot_alert_s1 ? 3'd5 : 3'd4;
                if (hit_th_2px && (plot_dx_s1 < 3'd5))
                    plot_code_w = 3'd1;
                if (!plot_offline_s1 &&
                    (((plot_dx_s1[1:0] < 2'd2) && hit_span_2px) || hit_cur_2px))
                    plot_code_w = plot_alert_s1 ? 3'd3 : 3'd2;
            end
            default: begin
                plot_code_w = 3'd0;
            end
        endcase
    end

    // ---- Stage 2 寄存（字库点阵与曲线判定结果在此对齐）----
    reg        font_pix_s2;
    reg [11:0] text_rgb_s2;
    reg [2:0]  plot_code_s2;
    reg [11:0] gfx_base_s2;
    reg [11:0] plot_ch_color_s2;

    always @(posedge clk) begin
        if (rst) begin
            font_pix_s2      <= 1'b0;
            text_rgb_s2      <= 12'h000;
            plot_code_s2     <= 3'd0;
            gfx_base_s2      <= 12'h000;
            plot_ch_color_s2 <= 12'h000;
        end else begin
            font_pix_s2      <= font_pix_s1;
            text_rgb_s2      <= text_rgb;
            plot_code_s2     <= plot_code_w;
            gfx_base_s2      <= gfx_base_s1;
            plot_ch_color_s2 <= plot_ch_color_s1;
        end
    end

    // ========================================================================
    // 8. 流水级 3（图文颜色合成）-> 流水级 4（pix_en 寄存输出，消隐全黑）
    //    4 拍/像素内 (pdiv=0->1->2->3) 完成 S1->S2->S3->Out，与 hsync/vsync/de 零错位
    // ========================================================================
    reg [11:0] gfx_rgb_s2;
    always @(*) begin
        case (plot_code_s2)
            3'd1:    gfx_rgb_s2 = c_err;
            3'd2:    gfx_rgb_s2 = plot_ch_color_s2;
            3'd3:    gfx_rgb_s2 = c_err;
            3'd4:    gfx_rgb_s2 = c_fill_norm;
            3'd5:    gfx_rgb_s2 = c_fill_err;
            default: gfx_rgb_s2 = gfx_base_s2;
        endcase
    end

    reg [11:0] rgb_s3;

    always @(posedge clk) begin
        if (rst) begin
            rgb_s3 <= 12'h000;
        end else begin
            rgb_s3 <= font_pix_s2 ? text_rgb_s2 : gfx_rgb_s2;
        end
    end

    always @(posedge clk) begin
        if (rst) begin
            vga_r <= 4'h0;
            vga_g <= 4'h0;
            vga_b <= 4'h0;
        end else if (pix_en) begin
            if (!video_on) begin
                vga_r <= 4'h0;
                vga_g <= 4'h0;
                vga_b <= 4'h0;
            end else begin
                vga_r <= rgb_s3[11:8];
                vga_g <= rgb_s3[7:4];
                vga_b <= rgb_s3[3:0];
            end
        end
    end

endmodule

`default_nettype wire
