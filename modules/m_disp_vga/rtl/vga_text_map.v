// ============================================================================
//  modules/m_disp_vga/rtl/vga_text_map.v
//  VGA 640x480 全屏文字坐标映射引擎（成员C）
//
//  功能：
//    根据当前扫描坐标 (x, y) 以及菜单页签 (tab_id)、焦点项 (item_idx)、
//    锁存 BCD 数据与状态，纯组合逻辑（无除法、无锁存器）输出：
//      - txt_en     : 当前像素是否位于某个文字单元格内
//      - char_code  : 对应 ASCII 码（送 vga_font）
//      - font_row   : 字内行号 0..7
//      - font_col   : 字内列号 0..7
//      - text_role  : 文字色彩角色编码（供 vga_disp 着色）
//
//  缩放档位（全部为 2 的幂，仅用位切片实现）：
//    - 1x (8x8)   : 坐标轴刻度与紧凑副标
//    - 1x2 (8x16) : 菜单栏、卡片标题、表格正文、底部提示栏
//    - 2x2 (16x16): 顶部系统主标题
//    - 2x4 (16x32): 01 OVERVIEW 超大号传感器读数
// ============================================================================
`default_nettype none

module vga_text_map (
    input  wire [9:0]  x,
    input  wire [9:0]  y,
    input  wire [1:0]  tab_id,
    input  wire [1:0]  item_idx,
    input  wire [3:0]  alarm_level,
    input  wire [3:0]  alarm_src,
    input  wire [7:0]  sensor_status,
    input  wire [15:0] sw,

    // ---- 来自 vga_bcd 的锁存数字 ----
    input  wire        t_neg,
    input  wire [3:0]  t_d2, t_d1, t_d0,
    input  wire [3:0]  h_d2, h_d1, h_d0,
    input  wire [3:0]  l_d3, l_d2, l_d1, l_d0,
    input  wire        min_neg,
    input  wire [3:0]  min_d3, min_d2, min_d1, min_d0,
    input  wire        max_neg,
    input  wire [3:0]  max_d3, max_d2, max_d1, max_d0,
    input  wire [3:0]  th_t_d1, th_t_d0,
    input  wire [3:0]  th_h_d2, th_h_d1, th_h_d0,
    input  wire [3:0]  th_l_d2, th_l_d1, th_l_d0,

    // ---- 输出到字库与着色级 ----
    output reg         txt_en,
    output reg  [7:0]  char_code,
    output reg  [2:0]  font_row,
    output reg  [2:0]  font_col,
    output reg  [3:0]  text_role
);

    // ---------------- 文字色彩角色编码 ----------------
    localparam [3:0] TR_MAIN   = 4'd0,   // 主题主文字（深色白 / 浅色深黑）
                     TR_MUTED  = 4'd1,   // 次要灰蓝文字
                     TR_ACCENT = 4'd2,   // 高亮青/蓝
                     TR_WHITE  = 4'd3,   // 强制纯白（用于深色顶栏/徽标/底栏）
                     TR_OK     = 4'd4,   // 正常绿
                     TR_WARN   = 4'd5,   // 警告黄
                     TR_ERR    = 4'd6,   // 报警红
                     TR_TEMP   = 4'd7,   // 温度橙
                     TR_HUMI   = 4'd8,   // 湿度青
                     TR_LUX    = 4'd9,   // 光照黄
                     TR_FOOTER = 4'd10;  // 底栏提示亮青

    wire th_ok   = sensor_status[0] && !sensor_status[2];
    wire ls_ok   = sensor_status[1] && !sensor_status[3];
    wire fault   = !th_ok || !ls_ok;
    wire hot     = alarm_src[0];
    wire wet     = alarm_src[1];
    wire dark    = alarm_src[2];
    wire buzz_en = sw[10];
    wire mute_on = sw[11];
    wire buzz_on = (alarm_level >= 4'd2) && buzz_en && !mute_on;

    // ---------------- 数字 / 十六进制 转 ASCII ----------------
    function [7:0] d2a;
        input [3:0] d;
        begin
            d2a = 8'h30 + {4'd0, d};
        end
    endfunction

    function [7:0] h2a;
        input [3:0] h;
        begin
            h2a = (h < 4'd10) ? (8'h30 + {4'd0, h}) : (8'h37 + {4'd0, h});
        end
    endfunction

    // ---------------- 局部偏移变量 ----------------
    reg [9:0] dx;
    reg [9:0] dy;
    reg [6:0] cidx;
    reg [1:0] ridx;

    always @(*) begin
        txt_en    = 1'b0;
        char_code = 8'h20;
        font_row  = 3'd0;
        font_col  = 3'd0;
        text_role = TR_MAIN;
        dx        = 10'd0;
        dy        = 10'd0;
        cidx      = 7'd0;
        ridx      = 2'd0;

        // ====================================================================
        // ZONE 1: 顶部标题栏 (y = 0 .. 47)
        // ====================================================================
        if (y < 10'd48) begin
            // 左侧主标题: "ENV MONITOR PANEL" (17 chars, 16x16 @ x=16..287, y=16..31)
            if (x >= 10'd16 && x < 10'd288 && y >= 10'd16 && y < 10'd32) begin
                dx        = x - 10'd16;
                dy        = y - 10'd16;
                cidx      = dx[8:4];
                font_col  = dx[3:1];
                font_row  = dy[3:1];
                txt_en    = 1'b1;
                text_role = TR_WHITE;
                case (cidx[4:0])
                    5'd0 : char_code = "E";
                    5'd1 : char_code = "N";
                    5'd2 : char_code = "V";
                    5'd3 : char_code = " ";
                    5'd4 : char_code = "M";
                    5'd5 : char_code = "O";
                    5'd6 : char_code = "N";
                    5'd7 : char_code = "I";
                    5'd8 : char_code = "T";
                    5'd9 : char_code = "O";
                    5'd10: char_code = "R";
                    5'd11: char_code = " ";
                    5'd12: char_code = "P";
                    5'd13: char_code = "A";
                    5'd14: char_code = "N";
                    5'd15: char_code = "E";
                    5'd16: char_code = "L";
                    default: char_code = " ";
                endcase
            end
            // 右侧报警状态徽标 (12 chars, 8x16 @ x=496..591, y=16..31)
            else if (x >= 10'd496 && x < 10'd592 && y >= 10'd16 && y < 10'd32) begin
                dx        = x - 10'd496;
                dy        = y - 10'd16;
                cidx      = dx[7:3];
                font_col  = dx[2:0];
                font_row  = dy[3:1];
                txt_en    = 1'b1;
                text_role = TR_WHITE;
                if (alarm_level >= 4'd3 || fault) begin
                    case (cidx[3:0])
                        4'd0 : char_code = "S"; 4'd1 : char_code = "E";
                        4'd2 : char_code = "N"; 4'd3 : char_code = "S";
                        4'd4 : char_code = "O"; 4'd5 : char_code = "R";
                        4'd6 : char_code = " "; 4'd7 : char_code = "F";
                        4'd8 : char_code = "A"; 4'd9 : char_code = "I";
                        4'd10: char_code = "L"; default: char_code = " ";
                    endcase
                end else if (alarm_level == 4'd2) begin
                    case (cidx[3:0])
                        4'd0 : char_code = "A"; 4'd1 : char_code = "L";
                        4'd2 : char_code = "A"; 4'd3 : char_code = "R";
                        4'd4 : char_code = "M"; 4'd5 : char_code = "!";
                        4'd6 : char_code = " "; 4'd7 : char_code = "L";
                        4'd8 : char_code = "V"; 4'd9 : char_code = ":";
                        4'd10: char_code = "2"; default: char_code = " ";
                    endcase
                end else if (alarm_level == 4'd1) begin
                    case (cidx[3:0])
                        4'd0 : char_code = "C"; 4'd1 : char_code = "A";
                        4'd2 : char_code = "U"; 4'd3 : char_code = "T";
                        4'd4 : char_code = "I"; 4'd5 : char_code = "O";
                        4'd6 : char_code = "N"; 4'd7 : char_code = " ";
                        4'd8 : char_code = "L"; 4'd9 : char_code = "V";
                        4'd10: char_code = ":"; 4'd11: char_code = "1";
                        default: char_code = " ";
                    endcase
                end else begin
                    case (cidx[3:0])
                        4'd0 : char_code = "S"; 4'd1 : char_code = "T";
                        4'd2 : char_code = "A"; 4'd3 : char_code = "T";
                        4'd4 : char_code = "U"; 4'd5 : char_code = "S";
                        4'd6 : char_code = ":"; 4'd7 : char_code = " ";
                        4'd8 : char_code = "O"; 4'd9 : char_code = "K";
                        default: char_code = " ";
                    endcase
                end
            end
        end

        // ====================================================================
        // ZONE 2: 控制菜单导航栏 (y = 48 .. 87)
        // ====================================================================
        else if (y >= 10'd48 && y < 10'd88) begin
            if (y >= 10'd60 && y < 10'd76) begin
                dy       = y - 10'd60;
                font_row = dy[3:1];
                // 4 等分，每格 160 px，文字在格内偏移 24..119 (12 chars, 8x16)
                if (x >= 10'd24 && x < 10'd120) begin
                    dx = x - 10'd24; cidx = dx[7:3]; font_col = dx[2:0];
                    txt_en = 1'b1; text_role = (tab_id == 2'd0) ? TR_MAIN : TR_MUTED;
                    case (cidx[3:0])
                        4'd0: char_code="0"; 4'd1: char_code="1"; 4'd2: char_code=" ";
                        4'd3: char_code="O"; 4'd4: char_code="V"; 4'd5: char_code="E";
                        4'd6: char_code="R"; 4'd7: char_code="V"; 4'd8: char_code="I";
                        4'd9: char_code="E"; 4'd10: char_code="W"; default: char_code=" ";
                    endcase
                end else if (x >= 10'd184 && x < 10'd280) begin
                    dx = x - 10'd184; cidx = dx[7:3]; font_col = dx[2:0];
                    txt_en = 1'b1; text_role = (tab_id == 2'd1) ? TR_MAIN : TR_MUTED;
                    case (cidx[3:0])
                        4'd0: char_code="0"; 4'd1: char_code="2"; 4'd2: char_code=" ";
                        4'd3: char_code="C"; 4'd4: char_code="U"; 4'd5: char_code="R";
                        4'd6: char_code="V"; 4'd7: char_code="E"; 4'd8: char_code="S";
                        default: char_code=" ";
                    endcase
                end else if (x >= 10'd344 && x < 10'd440) begin
                    dx = x - 10'd344; cidx = dx[7:3]; font_col = dx[2:0];
                    txt_en = 1'b1; text_role = (tab_id == 2'd2) ? TR_MAIN : TR_MUTED;
                    case (cidx[3:0])
                        4'd0: char_code="0"; 4'd1: char_code="3"; 4'd2: char_code=" ";
                        4'd3: char_code="A"; 4'd4: char_code="L"; 4'd5: char_code="A";
                        4'd6: char_code="R"; 4'd7: char_code="M"; 4'd8: char_code="/";
                        4'd9: char_code="C"; 4'd10: char_code="F"; 4'd11: char_code="G";
                        default: char_code=" ";
                    endcase
                end else if (x >= 10'd504 && x < 10'd600) begin
                    dx = x - 10'd504; cidx = dx[7:3]; font_col = dx[2:0];
                    txt_en = 1'b1; text_role = (tab_id == 2'd3) ? TR_MAIN : TR_MUTED;
                    case (cidx[3:0])
                        4'd0: char_code="0"; 4'd1: char_code="4"; 4'd2: char_code=" ";
                        4'd3: char_code="D"; 4'd4: char_code="I"; 4'd5: char_code="A";
                        4'd6: char_code="G"; default: char_code=" ";
                    endcase
                end
            end
        end

        // ====================================================================
        // ZONE 4: 底部操作提示与 OLED 同步状态栏 (y = 432 .. 479)
        // ====================================================================
        else if (y >= 10'd432) begin
            if (y >= 10'd448 && y < 10'd464) begin
                dy       = y - 10'd448;
                font_row = dy[3:1];
                // 左侧按键提示 (35 chars @ x=16..295)
                if (x >= 10'd16 && x < 10'd296) begin
                    dx = x - 10'd16; cidx = dx[8:3]; font_col = dx[2:0];
                    txt_en = 1'b1; text_role = TR_FOOTER;
                    case (cidx[5:0])
                        6'd0 : char_code="["; 6'd1 : char_code="L"; 6'd2 : char_code="/";
                        6'd3 : char_code="R"; 6'd4 : char_code="]"; 6'd5 : char_code="T";
                        6'd6 : char_code="A"; 6'd7 : char_code="B"; 6'd8 : char_code=" ";
                        6'd9 : char_code=" "; 6'd10: char_code="["; 6'd11: char_code="U";
                        6'd12: char_code="/"; 6'd13: char_code="D"; 6'd14: char_code="]";
                        6'd15: char_code="V"; 6'd16: char_code="I"; 6'd17: char_code="E";
                        6'd18: char_code="W"; 6'd19: char_code=" "; 6'd20: char_code=" ";
                        6'd21: char_code="["; 6'd22: char_code="S"; 6'd23: char_code="W";
                        6'd24: char_code="1"; 6'd25: char_code="5"; 6'd26: char_code="]";
                        6'd27: char_code="T"; 6'd28: char_code="H"; 6'd29: char_code="E";
                        6'd30: char_code="M"; 6'd31: char_code="E";
                        default: char_code=" ";
                    endcase
                end
                // 右侧精简读数 (28 chars @ x=400..623): "T:+25.3 H:55.0 L:0320 ALM:0"
                else if (x >= 10'd400 && x < 10'd624) begin
                    dx = x - 10'd400; cidx = dx[8:3]; font_col = dx[2:0];
                    txt_en = 1'b1; text_role = TR_WHITE;
                    case (cidx[4:0])
                        5'd0 : char_code="T"; 5'd1 : char_code=":";
                        5'd2 : char_code=th_ok ? (t_neg ? "-" : "+") : "-";
                        5'd3 : char_code=th_ok ? d2a(t_d2) : "-";
                        5'd4 : char_code=th_ok ? d2a(t_d1) : "-";
                        5'd5 : char_code=".";
                        5'd6 : char_code=th_ok ? d2a(t_d0) : "-";
                        5'd7 : char_code=" ";
                        5'd8 : char_code="H"; 5'd9 : char_code=":";
                        5'd10: char_code=th_ok ? d2a(h_d2) : "-";
                        5'd11: char_code=th_ok ? d2a(h_d1) : "-";
                        5'd12: char_code=".";
                        5'd13: char_code=th_ok ? d2a(h_d0) : "-";
                        5'd14: char_code=" ";
                        5'd15: char_code="L"; 5'd16: char_code=":";
                        5'd17: char_code=ls_ok ? d2a(l_d3) : "-";
                        5'd18: char_code=ls_ok ? d2a(l_d2) : "-";
                        5'd19: char_code=ls_ok ? d2a(l_d1) : "-";
                        5'd20: char_code=ls_ok ? d2a(l_d0) : "-";
                        5'd21: char_code=" ";
                        5'd22: char_code="A"; 5'd23: char_code="L"; 5'd24: char_code="M";
                        5'd25: char_code=":"; 5'd26: char_code=d2a(alarm_level);
                        default: char_code=" ";
                    endcase
                end
            end
        end

        // ====================================================================
        // ZONE 3: 主工作区 (y = 88 .. 431)
        // ====================================================================
        else begin
            case (tab_id)
                // ------------------------------------------------------------
                // PAGE 0: 01 OVERVIEW (3 张卡片 + 右侧实时迷你曲线)
                // ------------------------------------------------------------
                2'd0: begin
                    if ((y >= 10'd100 && y < 10'd198) ||
                        (y >= 10'd208 && y < 10'd306) ||
                        (y >= 10'd316 && y < 10'd414)) begin
                        if (y < 10'd198) begin
                            ridx = 2'd0; dy = y - 10'd100;
                        end else if (y < 10'd306) begin
                            ridx = 2'd1; dy = y - 10'd208;
                        end else begin
                            ridx = 2'd2; dy = y - 10'd316;
                        end

                        // 卡片标题 (14 chars, 8x16 @ x=44..155, dy=10..25)
                        if (x >= 10'd44 && x < 10'd156 && dy >= 10'd10 && dy < 10'd26) begin
                            dx = x - 10'd44; cidx = dx[7:3]; font_col = dx[2:0];
                            font_row = (dy - 10'd10) >> 1;
                            txt_en = 1'b1;
                            text_role = (item_idx == ridx) ? TR_ACCENT : TR_MUTED;
                            if (cidx == 7'd0) begin
                                char_code = (item_idx == ridx) ? ">" : " ";
                            end else if (cidx == 7'd1) begin
                                char_code = " ";
                            end else if (ridx == 2'd0) begin
                                case (cidx[3:0])
                                    4'd2: char_code="T"; 4'd3: char_code="E"; 4'd4: char_code="M";
                                    4'd5: char_code="P"; 4'd6: char_code="E"; 4'd7: char_code="R";
                                    4'd8: char_code="A"; 4'd9: char_code="T"; 4'd10: char_code="U";
                                    4'd11: char_code="R"; 4'd12: char_code="E"; default: char_code=" ";
                                endcase
                            end else if (ridx == 2'd1) begin
                                case (cidx[3:0])
                                    4'd2: char_code="H"; 4'd3: char_code="U"; 4'd4: char_code="M";
                                    4'd5: char_code="I"; 4'd6: char_code="D"; 4'd7: char_code="I";
                                    4'd8: char_code="T"; 4'd9: char_code="Y"; default: char_code=" ";
                                endcase
                            end else begin
                                case (cidx[3:0])
                                    4'd2: char_code="I"; 4'd3: char_code="L"; 4'd4: char_code="L";
                                    4'd5: char_code="U"; 4'd6: char_code="M"; 4'd7: char_code="I";
                                    4'd8: char_code="N"; 4'd9: char_code="A"; 4'd10: char_code="N";
                                    4'd11: char_code="C"; 4'd12: char_code="E"; default: char_code=" ";
                                endcase
                            end
                        end
                        // 超大号数值 (9 chars, 16x32 @ x=28..171, dy=34..65)
                        else if (x >= 10'd28 && x < 10'd172 && dy >= 10'd34 && dy < 10'd66) begin
                            dx = x - 10'd28; cidx = dx[8:4]; font_col = dx[3:1];
                            font_row = (dy - 10'd34) >> 2;
                            txt_en = 1'b1;
                            if (ridx == 2'd0) begin
                                text_role = (hot || !th_ok) ? TR_ERR : TR_MAIN;
                                case (cidx[3:0])
                                    4'd0: char_code = th_ok ? (t_neg ? "-" : "+") : "-";
                                    4'd1: char_code = th_ok ? d2a(t_d2) : "-";
                                    4'd2: char_code = th_ok ? d2a(t_d1) : "-";
                                    4'd3: char_code = ".";
                                    4'd4: char_code = th_ok ? d2a(t_d0) : "-";
                                    4'd5: char_code = " ";
                                    4'd6: char_code = "C";
                                    default: char_code = " ";
                                endcase
                            end else if (ridx == 2'd1) begin
                                text_role = (wet || !th_ok) ? TR_ERR : TR_MAIN;
                                case (cidx[3:0])
                                    4'd0: char_code = th_ok ? d2a(h_d2) : "-";
                                    4'd1: char_code = th_ok ? d2a(h_d1) : "-";
                                    4'd2: char_code = ".";
                                    4'd3: char_code = th_ok ? d2a(h_d0) : "-";
                                    4'd4: char_code = " ";
                                    4'd5: char_code = "%";
                                    4'd6: char_code = "R";
                                    4'd7: char_code = "H";
                                    default: char_code = " ";
                                endcase
                            end else begin
                                text_role = (dark || !ls_ok) ? TR_ERR : TR_MAIN;
                                case (cidx[3:0])
                                    4'd0: char_code = ls_ok ? d2a(l_d3) : "-";
                                    4'd1: char_code = ls_ok ? d2a(l_d2) : "-";
                                    4'd2: char_code = ls_ok ? d2a(l_d1) : "-";
                                    4'd3: char_code = ls_ok ? d2a(l_d0) : "-";
                                    4'd4: char_code = " ";
                                    4'd5: char_code = "l";
                                    4'd6: char_code = "x";
                                    default: char_code = " ";
                                endcase
                            end
                        end
                        // 底部阈值提示 (10 chars, 8x16 @ x=28..107, dy=74..89)
                        else if (x >= 10'd28 && x < 10'd108 && dy >= 10'd74 && dy < 10'd90) begin
                            dx = x - 10'd28; cidx = dx[7:3]; font_col = dx[2:0];
                            font_row = (dy - 10'd74) >> 1;
                            txt_en = 1'b1; text_role = TR_MUTED;
                            if (ridx == 2'd0) begin
                                case (cidx[3:0])
                                    4'd0: char_code="H"; 4'd1: char_code="I"; 4'd2: char_code=":";
                                    4'd3: char_code=d2a(th_t_d1); 4'd4: char_code=d2a(th_t_d0);
                                    4'd5: char_code="."; 4'd6: char_code="0"; 4'd7: char_code="C";
                                    default: char_code=" ";
                                endcase
                            end else if (ridx == 2'd1) begin
                                case (cidx[3:0])
                                    4'd0: char_code="H"; 4'd1: char_code="I"; 4'd2: char_code=":";
                                    4'd3: char_code=d2a(th_h_d2); 4'd4: char_code=d2a(th_h_d1);
                                    4'd5: char_code=d2a(th_h_d0); 4'd6: char_code="%";
                                    default: char_code=" ";
                                endcase
                            end else begin
                                case (cidx[3:0])
                                    4'd0: char_code="L"; 4'd1: char_code="O"; 4'd2: char_code=":";
                                    4'd3: char_code=d2a(th_l_d2); 4'd4: char_code=d2a(th_l_d1);
                                    4'd5: char_code=d2a(th_l_d0); 4'd6: char_code="l"; 4'd7: char_code="x";
                                    default: char_code=" ";
                                endcase
                            end
                        end
                        // 底部通道正常/报警标志 (8 chars, 8x16 @ x=124..187, dy=74..89)
                        else if (x >= 10'd124 && x < 10'd188 && dy >= 10'd74 && dy < 10'd90) begin
                            dx = x - 10'd124; cidx = dx[7:3]; font_col = dx[2:0];
                            font_row = (dy - 10'd74) >> 1;
                            txt_en = 1'b1;
                            if ((ridx == 2'd0 && (!th_ok || hot)) ||
                                (ridx == 2'd1 && (!th_ok || wet)) ||
                                (ridx == 2'd2 && (!ls_ok || dark))) begin
                                text_role = TR_ERR;
                                case (cidx[2:0])
                                    3'd0: char_code="A"; 3'd1: char_code="L"; 3'd2: char_code="E";
                                    3'd3: char_code="R"; 3'd4: char_code="T"; 3'd5: char_code="!";
                                    default: char_code=" ";
                                endcase
                            end else begin
                                text_role = TR_OK;
                                case (cidx[2:0])
                                    3'd0: char_code="N"; 3'd1: char_code="O"; 3'd2: char_code="R";
                                    3'd3: char_code="M"; 3'd4: char_code="A"; 3'd5: char_code="L";
                                    default: char_code=" ";
                                endcase
                            end
                        end
                        // 迷你曲线左侧量程小刻度 (4 chars, 8x8 @ x=304..335)
                        else if (x >= 10'd304 && x < 10'd336 && dy >= 10'd13 && dy < 10'd21) begin
                            dx = x - 10'd304; cidx = dx[6:3]; font_col = dx[2:0];
                            font_row = dy - 10'd13;
                            txt_en = 1'b1; text_role = TR_MUTED;
                            if (ridx == 2'd0) begin
                                case (cidx[1:0]) 2'd0: char_code=" "; 2'd1: char_code="6"; 2'd2: char_code="0"; default: char_code="C"; endcase
                            end else if (ridx == 2'd1) begin
                                case (cidx[1:0]) 2'd0: char_code="1"; 2'd1: char_code="0"; 2'd2: char_code="0"; default: char_code="%"; endcase
                            end else begin
                                case (cidx[1:0]) 2'd0: char_code="1"; 2'd1: char_code="0"; 2'd2: char_code="0"; default: char_code="0"; endcase
                            end
                        end else if (x >= 10'd304 && x < 10'd336 && dy >= 10'd76 && dy < 10'd84) begin
                            dx = x - 10'd304; cidx = dx[6:3]; font_col = dx[2:0];
                            font_row = dy - 10'd76;
                            txt_en = 1'b1; text_role = TR_MUTED;
                            if (ridx == 2'd0) begin
                                case (cidx[1:0]) 2'd0: char_code="-"; 2'd1: char_code="1"; 2'd2: char_code="0"; default: char_code="C"; endcase
                            end else if (ridx == 2'd1) begin
                                case (cidx[1:0]) 2'd0: char_code=" "; 2'd1: char_code=" "; 2'd2: char_code="0"; default: char_code="%"; endcase
                            end else begin
                                case (cidx[1:0]) 2'd0: char_code=" "; 2'd1: char_code="0"; 2'd2: char_code="l"; default: char_code="x"; endcase
                            end
                        end
                        // 传感器掉线时在迷你曲线中央提示 OFFLINE
                        else if (x >= 10'd416 && x < 10'd528 && dy >= 10'd41 && dy < 10'd57 &&
                                 ((ridx < 2'd2 && !th_ok) || (ridx == 2'd2 && !ls_ok))) begin
                            dx = x - 10'd416; cidx = dx[7:3]; font_col = dx[2:0];
                            font_row = (dy - 10'd41) >> 1;
                            txt_en = 1'b1; text_role = TR_ERR;
                            case (cidx[3:0])
                                4'd0: char_code="S"; 4'd1: char_code="E"; 4'd2: char_code="N";
                                4'd3: char_code="S"; 4'd4: char_code="O"; 4'd5: char_code="R";
                                4'd6: char_code=" "; 4'd7: char_code="O"; 4'd8: char_code="F";
                                4'd9: char_code="F"; 4'd10: char_code="L"; 4'd11: char_code="I";
                                4'd12: char_code="N"; 4'd13: char_code="E"; default: char_code=" ";
                            endcase
                        end
                    end
                end

                // ------------------------------------------------------------
                // PAGE 1: 02 CURVES (子视图选择条 + 三轨同屏 / 单路放大)
                // ------------------------------------------------------------
                2'd1: begin
                    // 子视图选择条 (y = 94 .. 117, 4 个按钮 x=16/170/324/478, 8x16 @ y=98..113)
                    if (y >= 10'd98 && y < 10'd114) begin
                        font_row = (y - 10'd98) >> 1;
                        if (x >= 10'd24 && x < 10'd152) begin
                            dx = x - 10'd24; cidx = dx[7:3]; font_col = dx[2:0];
                            txt_en = 1'b1; text_role = (item_idx == 2'd0) ? TR_MAIN : TR_MUTED;
                            case (cidx[3:0])
                                4'd0: char_code=(item_idx==2'd0)?">":" "; 4'd1: char_code="A";
                                4'd2: char_code="L"; 4'd3: char_code="L"; 4'd4: char_code=" ";
                                4'd5: char_code="3"; 4'd6: char_code=" "; 4'd7: char_code="C";
                                4'd8: char_code="H"; 4'd9: char_code="A"; 4'd10: char_code="N";
                                4'd11: char_code="N"; 4'd12: char_code="E"; 4'd13: char_code="L";
                                4'd14: char_code="S"; default: char_code=" ";
                            endcase
                        end else if (x >= 10'd178 && x < 10'd306) begin
                            dx = x - 10'd178; cidx = dx[7:3]; font_col = dx[2:0];
                            txt_en = 1'b1; text_role = (item_idx == 2'd1) ? TR_TEMP : TR_MUTED;
                            case (cidx[3:0])
                                4'd0: char_code=(item_idx==2'd1)?">":" "; 4'd1: char_code=" ";
                                4'd2: char_code="T"; 4'd3: char_code="E"; 4'd4: char_code="M";
                                4'd5: char_code="P"; 4'd6: char_code=" "; 4'd7: char_code="D";
                                4'd8: char_code="E"; 4'd9: char_code="T"; 4'd10: char_code="A";
                                4'd11: char_code="I"; 4'd12: char_code="L"; default: char_code=" ";
                            endcase
                        end else if (x >= 10'd332 && x < 10'd460) begin
                            dx = x - 10'd332; cidx = dx[7:3]; font_col = dx[2:0];
                            txt_en = 1'b1; text_role = (item_idx == 2'd2) ? TR_HUMI : TR_MUTED;
                            case (cidx[3:0])
                                4'd0: char_code=(item_idx==2'd2)?">":" "; 4'd1: char_code=" ";
                                4'd2: char_code="H"; 4'd3: char_code="U"; 4'd4: char_code="M";
                                4'd5: char_code="I"; 4'd6: char_code=" "; 4'd7: char_code="D";
                                4'd8: char_code="E"; 4'd9: char_code="T"; 4'd10: char_code="A";
                                4'd11: char_code="I"; 4'd12: char_code="L"; default: char_code=" ";
                            endcase
                        end else if (x >= 10'd486 && x < 10'd614) begin
                            dx = x - 10'd486; cidx = dx[7:3]; font_col = dx[2:0];
                            txt_en = 1'b1; text_role = (item_idx == 2'd3) ? TR_LUX : TR_MUTED;
                            case (cidx[3:0])
                                4'd0: char_code=(item_idx==2'd3)?">":" "; 4'd1: char_code=" ";
                                4'd2: char_code="L"; 4'd3: char_code="U"; 4'd4: char_code="X";
                                4'd5: char_code=" "; 4'd6: char_code="D"; 4'd7: char_code="E";
                                4'd8: char_code="T"; 4'd9: char_code="A"; 4'd10: char_code="I";
                                4'd11: char_code="L"; default: char_code=" ";
                            endcase
                        end
                    end

                    // --- 子视图 0: 三轨同屏 (T/H/L) ---
                    else if (item_idx == 2'd0) begin
                        if ((y >= 10'd124 && y < 10'd216) ||
                            (y >= 10'd222 && y < 10'd314) ||
                            (y >= 10'd320 && y < 10'd412)) begin
                            if (y < 10'd216) begin
                                ridx = 2'd0; dy = y - 10'd124;
                            end else if (y < 10'd314) begin
                                ridx = 2'd1; dy = y - 10'd222;
                            end else begin
                                ridx = 2'd2; dy = y - 10'd320;
                            end

                            // 通道名 (4 chars, 8x16 @ x=34..65, dy=8..23)
                            if (x >= 10'd34 && x < 10'd66 && dy >= 10'd8 && dy < 10'd24) begin
                                dx = x - 10'd34; cidx = dx[6:3]; font_col = dx[2:0];
                                font_row = (dy - 10'd8) >> 1;
                                txt_en = 1'b1;
                                if (ridx == 2'd0) begin
                                    text_role = TR_TEMP;
                                    case (cidx[1:0]) 2'd0: char_code="T"; 2'd1: char_code="E"; 2'd2: char_code="M"; default: char_code="P"; endcase
                                end else if (ridx == 2'd1) begin
                                    text_role = TR_HUMI;
                                    case (cidx[1:0]) 2'd0: char_code="H"; 2'd1: char_code="U"; 2'd2: char_code="M"; default: char_code="I"; endcase
                                end else begin
                                    text_role = TR_LUX;
                                    case (cidx[1:0]) 2'd0: char_code="L"; 2'd1: char_code="U"; 2'd2: char_code="X"; default: char_code=" "; endcase
                                end
                            end
                            // 当前数值 (7 chars, 8x16 @ x=24..79, dy=30..45)
                            else if (x >= 10'd24 && x < 10'd80 && dy >= 10'd30 && dy < 10'd46) begin
                                dx = x - 10'd24; cidx = dx[6:3]; font_col = dx[2:0];
                                font_row = (dy - 10'd30) >> 1;
                                txt_en = 1'b1;
                                if (ridx == 2'd0) begin
                                    text_role = (hot || !th_ok) ? TR_ERR : TR_MAIN;
                                    case (cidx[2:0])
                                        3'd0: char_code=th_ok?(t_neg?"-":"+"): "-";
                                        3'd1: char_code=th_ok?d2a(t_d2):"-";
                                        3'd2: char_code=th_ok?d2a(t_d1):"-";
                                        3'd3: char_code=".";
                                        3'd4: char_code=th_ok?d2a(t_d0):"-";
                                        3'd5: char_code="C";
                                        default: char_code=" ";
                                    endcase
                                end else if (ridx == 2'd1) begin
                                    text_role = (wet || !th_ok) ? TR_ERR : TR_MAIN;
                                    case (cidx[2:0])
                                        3'd0: char_code=th_ok?d2a(h_d2):"-";
                                        3'd1: char_code=th_ok?d2a(h_d1):"-";
                                        3'd2: char_code=".";
                                        3'd3: char_code=th_ok?d2a(h_d0):"-";
                                        3'd4: char_code="%";
                                        default: char_code=" ";
                                    endcase
                                end else begin
                                    text_role = (dark || !ls_ok) ? TR_ERR : TR_MAIN;
                                    case (cidx[2:0])
                                        3'd0: char_code=ls_ok?d2a(l_d3):"-";
                                        3'd1: char_code=ls_ok?d2a(l_d2):"-";
                                        3'd2: char_code=ls_ok?d2a(l_d1):"-";
                                        3'd3: char_code=ls_ok?d2a(l_d0):"-";
                                        3'd4: char_code="l";
                                        3'd5: char_code="x";
                                        default: char_code=" ";
                                    endcase
                                end
                            end
                            // 阈值小字 (8 chars, 8x8 @ x=24..87, dy=54..61)
                            else if (x >= 10'd24 && x < 10'd88 && dy >= 10'd54 && dy < 10'd62) begin
                                dx = x - 10'd24; cidx = dx[6:3]; font_col = dx[2:0];
                                font_row = dy - 10'd54;
                                txt_en = 1'b1; text_role = TR_ERR;
                                if (ridx == 2'd0) begin
                                    case (cidx[2:0])
                                        3'd0: char_code="H"; 3'd1: char_code="I"; 3'd2: char_code=":";
                                        3'd3: char_code=d2a(th_t_d1); 3'd4: char_code=d2a(th_t_d0);
                                        3'd5: char_code="C"; default: char_code=" ";
                                    endcase
                                end else if (ridx == 2'd1) begin
                                    case (cidx[2:0])
                                        3'd0: char_code="H"; 3'd1: char_code="I"; 3'd2: char_code=":";
                                        3'd3: char_code=d2a(th_h_d2); 3'd4: char_code=d2a(th_h_d1);
                                        3'd5: char_code=d2a(th_h_d0); 3'd6: char_code="%";
                                        default: char_code=" ";
                                    endcase
                                end else begin
                                    case (cidx[2:0])
                                        3'd0: char_code="L"; 3'd1: char_code="O"; 3'd2: char_code=":";
                                        3'd3: char_code=d2a(th_l_d2); 3'd4: char_code=d2a(th_l_d1);
                                        3'd5: char_code=d2a(th_l_d0); default: char_code=" ";
                                    endcase
                                end
                            end
                            // 量程小字 (8 chars, 8x8 @ x=24..87, dy=72..79)
                            else if (x >= 10'd24 && x < 10'd88 && dy >= 10'd72 && dy < 10'd80) begin
                                dx = x - 10'd24; cidx = dx[6:3]; font_col = dx[2:0];
                                font_row = dy - 10'd72;
                                txt_en = 1'b1; text_role = TR_MUTED;
                                if (ridx == 2'd0) begin
                                    case (cidx[2:0])
                                        3'd0: char_code="-"; 3'd1: char_code="1"; 3'd2: char_code="0";
                                        3'd3: char_code="."; 3'd4: char_code="."; 3'd5: char_code="6";
                                        3'd6: char_code="0"; default: char_code="C";
                                    endcase
                                end else if (ridx == 2'd1) begin
                                    case (cidx[2:0])
                                        3'd0: char_code="0"; 3'd1: char_code="."; 3'd2: char_code=".";
                                        3'd3: char_code="1"; 3'd4: char_code="0"; 3'd5: char_code="0";
                                        3'd6: char_code="%"; default: char_code=" ";
                                    endcase
                                end else begin
                                    case (cidx[2:0])
                                        3'd0: char_code="0"; 3'd1: char_code="."; 3'd2: char_code=".";
                                        3'd3: char_code="1"; 3'd4: char_code="0"; 3'd5: char_code="0";
                                        3'd6: char_code="0"; default: char_code=" ";
                                    endcase
                                end
                            end
                            // 掉线中央提示
                            else if (x >= 10'd304 && x < 10'd416 && dy >= 10'd38 && dy < 10'd54 &&
                                     ((ridx < 2'd2 && !th_ok) || (ridx == 2'd2 && !ls_ok))) begin
                                dx = x - 10'd304; cidx = dx[7:3]; font_col = dx[2:0];
                                font_row = (dy - 10'd38) >> 1;
                                txt_en = 1'b1; text_role = TR_ERR;
                                case (cidx[3:0])
                                    4'd0: char_code="S"; 4'd1: char_code="E"; 4'd2: char_code="N";
                                    4'd3: char_code="S"; 4'd4: char_code="O"; 4'd5: char_code="R";
                                    4'd6: char_code=" "; 4'd7: char_code="O"; 4'd8: char_code="F";
                                    4'd9: char_code="F"; 4'd10: char_code="L"; 4'd11: char_code="I";
                                    4'd12: char_code="N"; 4'd13: char_code="E"; default: char_code=" ";
                                endcase
                            end
                        end
                        // 底部时间轴标注 (8x8 @ y=418..425)
                        else if (y >= 10'd418 && y < 10'd426) begin
                            font_row = y - 10'd418;
                            if (x >= 10'd104 && x < 10'd144) begin
                                dx = x - 10'd104; cidx = dx[6:3]; font_col = dx[2:0];
                                txt_en = 1'b1; text_role = TR_MUTED;
                                case (cidx[2:0]) 3'd0: char_code="-"; 3'd1: char_code="1"; 3'd2: char_code="2"; 3'd3: char_code="8"; default: char_code="s"; endcase
                            end else if (x >= 10'd344 && x < 10'd376) begin
                                dx = x - 10'd344; cidx = dx[6:3]; font_col = dx[2:0];
                                txt_en = 1'b1; text_role = TR_MUTED;
                                case (cidx[1:0]) 2'd0: char_code="-"; 2'd1: char_code="6"; 2'd2: char_code="4"; default: char_code="s"; endcase
                            end else if (x >= 10'd544 && x < 10'd616) begin
                                dx = x - 10'd544; cidx = dx[6:3]; font_col = dx[2:0];
                                txt_en = 1'b1; text_role = TR_ACCENT;
                                case (cidx[3:0])
                                    4'd0: char_code="N"; 4'd1: char_code="O"; 4'd2: char_code="W";
                                    4'd3: char_code=" "; 4'd4: char_code="("; 4'd5: char_code="1";
                                    4'd6: char_code="H"; 4'd7: char_code="z"; 4'd8: char_code=")";
                                    default: char_code=" ";
                                endcase
                            end
                        end
                    end

                    // --- 子视图 1/2/3: 单路放大监控曲线 ---
                    else begin
                        // 统计头栏第 1 行：曲线标题 (36 chars, 8x8 @ x=28..315, y=132..139)
                        if (x >= 10'd28 && x < 10'd316 && y >= 10'd132 && y < 10'd140) begin
                            dx = x - 10'd28; cidx = dx[8:3]; font_col = dx[2:0];
                            font_row = y - 10'd132;
                            txt_en = 1'b1;
                            text_role = (item_idx == 2'd1) ? TR_TEMP :
                                        (item_idx == 2'd2) ? TR_HUMI : TR_LUX;
                            if (item_idx == 2'd1) begin
                                case (cidx[5:0])
                                    6'd0: char_code="T"; 6'd1: char_code="E"; 6'd2: char_code="M"; 6'd3: char_code="P";
                                    6'd4: char_code="E"; 6'd5: char_code="R"; 6'd6: char_code="A"; 6'd7: char_code="T";
                                    6'd8: char_code="U"; 6'd9: char_code="R"; 6'd10: char_code="E"; 6'd11: char_code=" ";
                                    6'd12: char_code="M"; 6'd13: char_code="O"; 6'd14: char_code="N"; 6'd15: char_code="I";
                                    6'd16: char_code="T"; 6'd17: char_code="O"; 6'd18: char_code="R"; 6'd19: char_code="I";
                                    6'd20: char_code="N"; 6'd21: char_code="G"; 6'd22: char_code=" "; 6'd23: char_code="C";
                                    6'd24: char_code="U"; 6'd25: char_code="R"; 6'd26: char_code="V"; 6'd27: char_code="E";
                                    6'd28: char_code=" "; 6'd29: char_code="("; 6'd30: char_code="1"; 6'd31: char_code="2";
                                    6'd32: char_code="8"; 6'd33: char_code="s"; 6'd34: char_code=")";
                                    default: char_code=" ";
                                endcase
                            end else if (item_idx == 2'd2) begin
                                case (cidx[5:0])
                                    6'd0: char_code="H"; 6'd1: char_code="U"; 6'd2: char_code="M"; 6'd3: char_code="I";
                                    6'd4: char_code="D"; 6'd5: char_code="I"; 6'd6: char_code="T"; 6'd7: char_code="Y";
                                    6'd8: char_code=" "; 6'd9: char_code="M"; 6'd10: char_code="O"; 6'd11: char_code="N";
                                    6'd12: char_code="I"; 6'd13: char_code="T"; 6'd14: char_code="O"; 6'd15: char_code="R";
                                    6'd16: char_code="I"; 6'd17: char_code="N"; 6'd18: char_code="G"; 6'd19: char_code=" ";
                                    6'd20: char_code="C"; 6'd21: char_code="U"; 6'd22: char_code="R"; 6'd23: char_code="V";
                                    6'd24: char_code="E"; 6'd25: char_code=" "; 6'd26: char_code="("; 6'd27: char_code="1";
                                    6'd28: char_code="2"; 6'd29: char_code="8"; 6'd30: char_code="s"; 6'd31: char_code=")";
                                    default: char_code=" ";
                                endcase
                            end else begin
                                case (cidx[5:0])
                                    6'd0: char_code="I"; 6'd1: char_code="L"; 6'd2: char_code="L"; 6'd3: char_code="U";
                                    6'd4: char_code="M"; 6'd5: char_code="I"; 6'd6: char_code="N"; 6'd7: char_code="A";
                                    6'd8: char_code="N"; 6'd9: char_code="C"; 6'd10: char_code="E"; 6'd11: char_code=" ";
                                    6'd12: char_code="M"; 6'd13: char_code="O"; 6'd14: char_code="N"; 6'd15: char_code="I";
                                    6'd16: char_code="T"; 6'd17: char_code="O"; 6'd18: char_code="R"; 6'd19: char_code="I";
                                    6'd20: char_code="N"; 6'd21: char_code="G"; 6'd22: char_code=" "; 6'd23: char_code="C";
                                    6'd24: char_code="U"; 6'd25: char_code="R"; 6'd26: char_code="V"; 6'd27: char_code="E";
                                    6'd28: char_code=" "; 6'd29: char_code="("; 6'd30: char_code="1"; 6'd31: char_code="2";
                                    6'd32: char_code="8"; 6'd33: char_code="s"; 6'd34: char_code=")";
                                    default: char_code=" ";
                                endcase
                            end
                        end
                        // 统计头栏第 2 行：NOW / MIN / MAX / LIM (8x16 @ y=148..163)
                        else if (y >= 10'd148 && y < 10'd164 && x >= 10'd28 && x < 10'd612) begin
                            dx = x - 10'd28; cidx = dx[9:3]; font_col = dx[2:0];
                            font_row = (y - 10'd148) >> 1;
                            txt_en = 1'b1;
                            if (cidx < 7'd16)      text_role = TR_MAIN;
                            else if (cidx < 7'd48) text_role = TR_MUTED;
                            else                   text_role = TR_ERR;

                            if (item_idx == 2'd1) begin
                                // "NOW:+25.3C      MIN:+21.0C      MAX:+28.5C      LIM:<=30.0C"
                                case (cidx)
                                    7'd0: char_code="N"; 7'd1: char_code="O"; 7'd2: char_code="W"; 7'd3: char_code=":";
                                    7'd4: char_code=th_ok?(t_neg?"-":"+"): "-";
                                    7'd5: char_code=th_ok?d2a(t_d2):"-"; 7'd6: char_code=th_ok?d2a(t_d1):"-";
                                    7'd7: char_code="."; 7'd8: char_code=th_ok?d2a(t_d0):"-"; 7'd9: char_code="C";
                                    7'd16: char_code="M"; 7'd17: char_code="I"; 7'd18: char_code="N"; 7'd19: char_code=":";
                                    7'd20: char_code=min_neg?"-":"+";
                                    7'd21: char_code=d2a(min_d2); 7'd22: char_code=d2a(min_d1);
                                    7'd23: char_code="."; 7'd24: char_code=d2a(min_d0); 7'd25: char_code="C";
                                    7'd32: char_code="M"; 7'd33: char_code="A"; 7'd34: char_code="X"; 7'd35: char_code=":";
                                    7'd36: char_code=max_neg?"-":"+";
                                    7'd37: char_code=d2a(max_d2); 7'd38: char_code=d2a(max_d1);
                                    7'd39: char_code="."; 7'd40: char_code=d2a(max_d0); 7'd41: char_code="C";
                                    7'd48: char_code="L"; 7'd49: char_code="I"; 7'd50: char_code="M"; 7'd51: char_code=":";
                                    7'd52: char_code="<"; 7'd53: char_code="=";
                                    7'd54: char_code=d2a(th_t_d1); 7'd55: char_code=d2a(th_t_d0);
                                    7'd56: char_code="."; 7'd57: char_code="0"; 7'd58: char_code="C";
                                    default: char_code=" ";
                                endcase
                            end else if (item_idx == 2'd2) begin
                                case (cidx)
                                    7'd0: char_code="N"; 7'd1: char_code="O"; 7'd2: char_code="W"; 7'd3: char_code=":";
                                    7'd4: char_code=th_ok?d2a(h_d2):"-"; 7'd5: char_code=th_ok?d2a(h_d1):"-";
                                    7'd6: char_code="."; 7'd7: char_code=th_ok?d2a(h_d0):"-"; 7'd8: char_code="%";
                                    7'd16: char_code="M"; 7'd17: char_code="I"; 7'd18: char_code="N"; 7'd19: char_code=":";
                                    7'd20: char_code=d2a(min_d2); 7'd21: char_code=d2a(min_d1);
                                    7'd22: char_code="."; 7'd23: char_code=d2a(min_d0); 7'd24: char_code="%";
                                    7'd32: char_code="M"; 7'd33: char_code="A"; 7'd34: char_code="X"; 7'd35: char_code=":";
                                    7'd36: char_code=d2a(max_d2); 7'd37: char_code=d2a(max_d1);
                                    7'd38: char_code="."; 7'd39: char_code=d2a(max_d0); 7'd40: char_code="%";
                                    7'd48: char_code="L"; 7'd49: char_code="I"; 7'd50: char_code="M"; 7'd51: char_code=":";
                                    7'd52: char_code="<"; 7'd53: char_code="=";
                                    7'd54: char_code=d2a(th_h_d2); 7'd55: char_code=d2a(th_h_d1);
                                    7'd56: char_code=d2a(th_h_d0); 7'd57: char_code="%";
                                    default: char_code=" ";
                                endcase
                            end else begin
                                case (cidx)
                                    7'd0: char_code="N"; 7'd1: char_code="O"; 7'd2: char_code="W"; 7'd3: char_code=":";
                                    7'd4: char_code=ls_ok?d2a(l_d3):"-"; 7'd5: char_code=ls_ok?d2a(l_d2):"-";
                                    7'd6: char_code=ls_ok?d2a(l_d1):"-"; 7'd7: char_code=ls_ok?d2a(l_d0):"-";
                                    7'd8: char_code="l"; 7'd9: char_code="x";
                                    7'd16: char_code="M"; 7'd17: char_code="I"; 7'd18: char_code="N"; 7'd19: char_code=":";
                                    7'd20: char_code=d2a(min_d3); 7'd21: char_code=d2a(min_d2);
                                    7'd22: char_code=d2a(min_d1); 7'd23: char_code=d2a(min_d0);
                                    7'd24: char_code="l"; 7'd25: char_code="x";
                                    7'd32: char_code="M"; 7'd33: char_code="A"; 7'd34: char_code="X"; 7'd35: char_code=":";
                                    7'd36: char_code=d2a(max_d3); 7'd37: char_code=d2a(max_d2);
                                    7'd38: char_code=d2a(max_d1); 7'd39: char_code=d2a(max_d0);
                                    7'd40: char_code="l"; 7'd41: char_code="x";
                                    7'd48: char_code="L"; 7'd49: char_code="I"; 7'd50: char_code="M"; 7'd51: char_code=":";
                                    7'd52: char_code=">"; 7'd53: char_code="=";
                                    7'd54: char_code=d2a(th_l_d2); 7'd55: char_code=d2a(th_l_d1);
                                    7'd56: char_code=d2a(th_l_d0); 7'd57: char_code="l"; 7'd58: char_code="x";
                                    default: char_code=" ";
                                endcase
                            end
                        end
                        // Y 轴 5 档刻度 (4 chars, 8x8 @ x=36..67, y=192/240/288/336/384)
                        else if (x >= 10'd36 && x < 10'd68 &&
                                 ((y >= 10'd192 && y < 10'd200) || (y >= 10'd240 && y < 10'd248) ||
                                  (y >= 10'd288 && y < 10'd296) || (y >= 10'd336 && y < 10'd344) ||
                                  (y >= 10'd384 && y < 10'd392))) begin
                            dx = x - 10'd36; cidx = dx[5:3]; font_col = dx[2:0];
                            txt_en = 1'b1; text_role = TR_MUTED;
                            if (y < 10'd200) begin
                                font_row = y - 10'd192;
                                if (item_idx == 2'd1) begin
                                    case (cidx[1:0]) 2'd0: char_code="+"; 2'd1: char_code="6"; 2'd2: char_code="0"; default: char_code="C"; endcase
                                end else if (item_idx == 2'd2) begin
                                    case (cidx[1:0]) 2'd0: char_code="1"; 2'd1: char_code="0"; 2'd2: char_code="0"; default: char_code="%"; endcase
                                end else begin
                                    case (cidx[1:0]) 2'd0: char_code="1"; 2'd1: char_code="0"; 2'd2: char_code="0"; default: char_code="0"; endcase
                                end
                            end else if (y < 10'd248) begin
                                font_row = y - 10'd240;
                                if (item_idx == 2'd1) begin
                                    case (cidx[1:0]) 2'd0: char_code="+"; 2'd1: char_code="4"; 2'd2: char_code="2"; default: char_code="C"; endcase
                                end else if (item_idx == 2'd2) begin
                                    case (cidx[1:0]) 2'd0: char_code=" "; 2'd1: char_code="7"; 2'd2: char_code="5"; default: char_code="%"; endcase
                                end else begin
                                    case (cidx[1:0]) 2'd0: char_code=" "; 2'd1: char_code="7"; 2'd2: char_code="5"; default: char_code="0"; endcase
                                end
                            end else if (y < 10'd296) begin
                                font_row = y - 10'd288;
                                if (item_idx == 2'd1) begin
                                    case (cidx[1:0]) 2'd0: char_code="+"; 2'd1: char_code="2"; 2'd2: char_code="5"; default: char_code="C"; endcase
                                end else if (item_idx == 2'd2) begin
                                    case (cidx[1:0]) 2'd0: char_code=" "; 2'd1: char_code="5"; 2'd2: char_code="0"; default: char_code="%"; endcase
                                end else begin
                                    case (cidx[1:0]) 2'd0: char_code=" "; 2'd1: char_code="5"; 2'd2: char_code="0"; default: char_code="0"; endcase
                                end
                            end else if (y < 10'd344) begin
                                font_row = y - 10'd336;
                                if (item_idx == 2'd1) begin
                                    case (cidx[1:0]) 2'd0: char_code="+"; 2'd1: char_code="0"; 2'd2: char_code="8"; default: char_code="C"; endcase
                                end else if (item_idx == 2'd2) begin
                                    case (cidx[1:0]) 2'd0: char_code=" "; 2'd1: char_code="2"; 2'd2: char_code="5"; default: char_code="%"; endcase
                                end else begin
                                    case (cidx[1:0]) 2'd0: char_code=" "; 2'd1: char_code="2"; 2'd2: char_code="5"; default: char_code="0"; endcase
                                end
                            end else begin
                                font_row = y - 10'd384;
                                if (item_idx == 2'd1) begin
                                    case (cidx[1:0]) 2'd0: char_code="-"; 2'd1: char_code="1"; 2'd2: char_code="0"; default: char_code="C"; endcase
                                end else if (item_idx == 2'd2) begin
                                    case (cidx[1:0]) 2'd0: char_code=" "; 2'd1: char_code=" "; 2'd2: char_code="0"; default: char_code="%"; endcase
                                end else begin
                                    case (cidx[1:0]) 2'd0: char_code=" "; 2'd1: char_code=" "; 2'd2: char_code=" "; default: char_code="0"; endcase
                                end
                            end
                        end
                        // X 轴 5 档时间刻度 (8x8 @ y=402..409)
                        else if (y >= 10'd402 && y < 10'd410) begin
                            font_row = y - 10'd402;
                            if (x >= 10'd84 && x < 10'd124) begin
                                dx = x - 10'd84; cidx = dx[6:3]; font_col = dx[2:0];
                                txt_en = 1'b1; text_role = TR_MUTED;
                                case (cidx[2:0]) 3'd0: char_code="-"; 3'd1: char_code="1"; 3'd2: char_code="2"; 3'd3: char_code="8"; default: char_code="s"; endcase
                            end else if (x >= 10'd212 && x < 10'd244) begin
                                dx = x - 10'd212; cidx = dx[5:3]; font_col = dx[2:0];
                                txt_en = 1'b1; text_role = TR_MUTED;
                                case (cidx[1:0]) 2'd0: char_code="-"; 2'd1: char_code="9"; 2'd2: char_code="6"; default: char_code="s"; endcase
                            end else if (x >= 10'd340 && x < 10'd372) begin
                                dx = x - 10'd340; cidx = dx[5:3]; font_col = dx[2:0];
                                txt_en = 1'b1; text_role = TR_MUTED;
                                case (cidx[1:0]) 2'd0: char_code="-"; 2'd1: char_code="6"; 2'd2: char_code="4"; default: char_code="s"; endcase
                            end else if (x >= 10'd468 && x < 10'd500) begin
                                dx = x - 10'd468; cidx = dx[5:3]; font_col = dx[2:0];
                                txt_en = 1'b1; text_role = TR_MUTED;
                                case (cidx[1:0]) 2'd0: char_code="-"; 2'd1: char_code="3"; 2'd2: char_code="2"; default: char_code="s"; endcase
                            end else if (x >= 10'd572 && x < 10'd596) begin
                                dx = x - 10'd572; cidx = dx[5:3]; font_col = dx[2:0];
                                txt_en = 1'b1; text_role = TR_ACCENT;
                                case (cidx[1:0]) 2'd0: char_code="N"; 2'd1: char_code="O"; default: char_code="W"; endcase
                            end
                        end
                        // 单路大图掉线提示
                        else if (x >= 10'd284 && x < 10'd396 && y >= 10'd284 && y < 10'd300 &&
                                 ((item_idx != 2'd3 && !th_ok) || (item_idx == 2'd3 && !ls_ok))) begin
                            dx = x - 10'd284; cidx = dx[7:3]; font_col = dx[2:0];
                            font_row = (y - 10'd284) >> 1;
                            txt_en = 1'b1; text_role = TR_ERR;
                            case (cidx[3:0])
                                4'd0: char_code="S"; 4'd1: char_code="E"; 4'd2: char_code="N";
                                4'd3: char_code="S"; 4'd4: char_code="O"; 4'd5: char_code="R";
                                4'd6: char_code=" "; 4'd7: char_code="O"; 4'd8: char_code="F";
                                4'd9: char_code="F"; 4'd10: char_code="L"; 4'd11: char_code="I";
                                4'd12: char_code="N"; 4'd13: char_code="E"; default: char_code=" ";
                            endcase
                        end
                    end
                end

                // ------------------------------------------------------------
                // PAGE 2: 03 ALARM/CFG (阈值解析 + 4 路报警源矩阵 + 蜂鸣状态)
                // ------------------------------------------------------------
                2'd2: begin
                    // 顶部小标题 (52 chars, 8x16 @ x=20..435, y=96..111)
                    if (y >= 10'd96 && y < 10'd112 && x >= 10'd20 && x < 10'd436) begin
                        dx = x - 10'd20; cidx = dx[8:3]; font_col = dx[2:0];
                        font_row = (y - 10'd96) >> 1;
                        txt_en = 1'b1; text_role = TR_MUTED;
                        case (cidx[5:0])
                            6'd0: char_code="T"; 6'd1: char_code="H"; 6'd2: char_code="R"; 6'd3: char_code="E";
                            6'd4: char_code="S"; 6'd5: char_code="H"; 6'd6: char_code="O"; 6'd7: char_code="L";
                            6'd8: char_code="D"; 6'd9: char_code="S"; 6'd10: char_code=" "; 6'd11: char_code="(";
                            6'd12: char_code="S"; 6'd13: char_code="W"; 6'd14: char_code="["; 6'd15: char_code="9";
                            6'd16: char_code=":"; 6'd17: char_code="0"; 6'd18: char_code="]"; 6'd19: char_code=")";
                            6'd20: char_code=" "; 6'd21: char_code="/"; 6'd22: char_code=" "; 6'd23: char_code="A";
                            6'd24: char_code="L"; 6'd25: char_code="A"; 6'd26: char_code="R"; 6'd27: char_code="M";
                            6'd28: char_code=" "; 6'd29: char_code="M"; 6'd30: char_code="A"; 6'd31: char_code="T";
                            6'd32: char_code="R"; 6'd33: char_code="I"; 6'd34: char_code="X";
                            default: char_code=" ";
                        endcase
                    end
                    // 4 行报警矩阵卡片 (y=120/178/236/294, 文字行 y+17..y+32)
                    else if ((y >= 10'd137 && y < 10'd153) || (y >= 10'd195 && y < 10'd211) ||
                             (y >= 10'd253 && y < 10'd269) || (y >= 10'd311 && y < 10'd327)) begin
                        if (y < 10'd153) begin ridx = 2'd0; dy = y - 10'd137; end
                        else if (y < 10'd211) begin ridx = 2'd1; dy = y - 10'd195; end
                        else if (y < 10'd269) begin ridx = 2'd2; dy = y - 10'd253; end
                        else begin ridx = 2'd3; dy = y - 10'd311; end
                        font_row = dy[3:1];

                        // 卡片主文 (58 chars, 8x16 @ x=30..493)
                        if (x >= 10'd30 && x < 10'd494) begin
                            dx = x - 10'd30; cidx = dx[8:3]; font_col = dx[2:0];
                            txt_en = 1'b1;
                            if (cidx < 7'd24)      text_role = (item_idx == ridx) ? TR_ACCENT : TR_MAIN;
                            else if (cidx < 7'd38) text_role = TR_ACCENT;
                            else                   text_role = TR_MUTED;

                            if (cidx == 7'd0) char_code = (item_idx == ridx) ? ">" : " ";
                            else if (cidx == 7'd1) char_code = " ";
                            else if (ridx == 2'd0) begin
                                case (cidx[5:0])
                                    6'd2: char_code="T"; 6'd3: char_code="E"; 6'd4: char_code="M"; 6'd5: char_code="P";
                                    6'd6: char_code=" "; 6'd7: char_code="L"; 6'd8: char_code="I"; 6'd9: char_code="M";
                                    6'd10: char_code="I"; 6'd11: char_code="T"; 6'd12: char_code=" ";
                                    6'd13: char_code="S"; 6'd14: char_code="W"; 6'd15: char_code="["; 6'd16: char_code="3";
                                    6'd17: char_code=":"; 6'd18: char_code="0"; 6'd19: char_code="]";
                                    6'd24: char_code="<"; 6'd25: char_code="="; 6'd26: char_code=d2a(th_t_d1);
                                    6'd27: char_code=d2a(th_t_d0); 6'd28: char_code="."; 6'd29: char_code="0"; 6'd30: char_code="C";
                                    6'd38: char_code="N"; 6'd39: char_code="O"; 6'd40: char_code="W"; 6'd41: char_code=":";
                                    6'd42: char_code=th_ok?(t_neg?"-":"+"): "-";
                                    6'd43: char_code=th_ok?d2a(t_d2):"-"; 6'd44: char_code=th_ok?d2a(t_d1):"-";
                                    6'd45: char_code="."; 6'd46: char_code=th_ok?d2a(t_d0):"-"; 6'd47: char_code="C";
                                    default: char_code=" ";
                                endcase
                            end else if (ridx == 2'd1) begin
                                case (cidx[5:0])
                                    6'd2: char_code="H"; 6'd3: char_code="U"; 6'd4: char_code="M"; 6'd5: char_code="I";
                                    6'd6: char_code=" "; 6'd7: char_code="L"; 6'd8: char_code="I"; 6'd9: char_code="M";
                                    6'd10: char_code="I"; 6'd11: char_code="T"; 6'd12: char_code=" ";
                                    6'd13: char_code="S"; 6'd14: char_code="W"; 6'd15: char_code="["; 6'd16: char_code="7";
                                    6'd17: char_code=":"; 6'd18: char_code="4"; 6'd19: char_code="]";
                                    6'd24: char_code="<"; 6'd25: char_code="="; 6'd26: char_code=d2a(th_h_d2);
                                    6'd27: char_code=d2a(th_h_d1); 6'd28: char_code=d2a(th_h_d0); 6'd29: char_code="%";
                                    6'd38: char_code="N"; 6'd39: char_code="O"; 6'd40: char_code="W"; 6'd41: char_code=":";
                                    6'd42: char_code=th_ok?d2a(h_d2):"-"; 6'd43: char_code=th_ok?d2a(h_d1):"-";
                                    6'd44: char_code="."; 6'd45: char_code=th_ok?d2a(h_d0):"-"; 6'd46: char_code="%";
                                    default: char_code=" ";
                                endcase
                            end else if (ridx == 2'd2) begin
                                case (cidx[5:0])
                                    6'd2: char_code="L"; 6'd3: char_code="U"; 6'd4: char_code="X"; 6'd5: char_code=" ";
                                    6'd6: char_code=" "; 6'd7: char_code="L"; 6'd8: char_code="I"; 6'd9: char_code="M";
                                    6'd10: char_code="I"; 6'd11: char_code="T"; 6'd12: char_code=" ";
                                    6'd13: char_code="S"; 6'd14: char_code="W"; 6'd15: char_code="["; 6'd16: char_code="9";
                                    6'd17: char_code=":"; 6'd18: char_code="8"; 6'd19: char_code="]";
                                    6'd24: char_code=">"; 6'd25: char_code="="; 6'd26: char_code=d2a(th_l_d2);
                                    6'd27: char_code=d2a(th_l_d1); 6'd28: char_code=d2a(th_l_d0);
                                    6'd29: char_code="l"; 6'd30: char_code="x";
                                    6'd38: char_code="N"; 6'd39: char_code="O"; 6'd40: char_code="W"; 6'd41: char_code=":";
                                    6'd42: char_code=ls_ok?d2a(l_d3):"-"; 6'd43: char_code=ls_ok?d2a(l_d2):"-";
                                    6'd44: char_code=ls_ok?d2a(l_d1):"-"; 6'd45: char_code=ls_ok?d2a(l_d0):"-";
                                    6'd46: char_code="l"; 6'd47: char_code="x";
                                    default: char_code=" ";
                                endcase
                            end else begin
                                case (cidx[5:0])
                                    6'd2: char_code="S"; 6'd3: char_code="E"; 6'd4: char_code="N"; 6'd5: char_code="S";
                                    6'd6: char_code="O"; 6'd7: char_code="R"; 6'd8: char_code=" "; 6'd9: char_code="L";
                                    6'd10: char_code="I"; 6'd11: char_code="N"; 6'd12: char_code="K";
                                    6'd24: char_code="T"; 6'd25: char_code="H"; 6'd26: char_code=":";
                                    6'd27: char_code=th_ok?"O":"E"; 6'd28: char_code=th_ok?"K":"R";
                                    6'd38: char_code="L"; 6'd39: char_code="S"; 6'd40: char_code=":";
                                    6'd41: char_code=ls_ok?"O":"E"; 6'd42: char_code=ls_ok?"K":"R";
                                    default: char_code=" ";
                                endcase
                            end
                        end
                        // 右侧状态徽标文字 (7 chars @ x=528..583)
                        else if (x >= 10'd528 && x < 10'd584) begin
                            dx = x - 10'd528; cidx = dx[6:3]; font_col = dx[2:0];
                            txt_en = 1'b1; text_role = TR_WHITE;
                            if ((ridx == 2'd0 && hot) || (ridx == 2'd1 && wet) ||
                                (ridx == 2'd2 && dark) || (ridx == 2'd3 && (alarm_src[3] || fault))) begin
                                case (cidx[2:0])
                                    3'd0: char_code="A"; 3'd1: char_code="C"; 3'd2: char_code="T";
                                    3'd3: char_code="I"; 3'd4: char_code="V"; 3'd5: char_code="E";
                                    3'd6: char_code="!"; default: char_code=" ";
                                endcase
                            end else begin
                                case (cidx[2:0])
                                    3'd0: char_code=" "; 3'd1: char_code="C"; 3'd2: char_code="L";
                                    3'd3: char_code="E"; 3'd4: char_code="A"; 3'd5: char_code="R";
                                    default: char_code=" ";
                                endcase
                            end
                        end
                    end
                    // 底部蜂鸣器汇总栏 (y=379..394, x=36..595)
                    else if (y >= 10'd379 && y < 10'd395 && x >= 10'd36 && x < 10'd596) begin
                        dx = x - 10'd36; cidx = dx[9:3]; font_col = dx[2:0];
                        font_row = (y - 10'd379) >> 1;
                        txt_en = 1'b1;
                        if (cidx < 7'd24)      text_role = buzz_en ? TR_OK : TR_MUTED;
                        else if (cidx < 7'd48) text_role = mute_on ? TR_WARN : TR_MUTED;
                        else                   text_role = buzz_on ? TR_ERR : TR_OK;
                        case (cidx)
                            7'd0: char_code="S"; 7'd1: char_code="W"; 7'd2: char_code="1"; 7'd3: char_code="0";
                            7'd4: char_code=" "; 7'd5: char_code="B"; 7'd6: char_code="U"; 7'd7: char_code="Z";
                            7'd8: char_code="Z"; 7'd9: char_code=":";
                            7'd10: char_code=buzz_en?"O":"O"; 7'd11: char_code=buzz_en?"N":"F"; 7'd12: char_code=buzz_en?" ":"F";

                            7'd24: char_code="S"; 7'd25: char_code="W"; 7'd26: char_code="1"; 7'd27: char_code="1";
                            7'd28: char_code=" "; 7'd29: char_code="M"; 7'd30: char_code="U"; 7'd31: char_code="T";
                            7'd32: char_code="E"; 7'd33: char_code=":";
                            7'd34: char_code=mute_on?"M":"O"; 7'd35: char_code=mute_on?"U":"F";
                            7'd36: char_code=mute_on?"T":"F"; 7'd37: char_code=mute_on?"E":" ";

                            7'd48: char_code="O"; 7'd49: char_code="U"; 7'd50: char_code="T"; 7'd51: char_code=":";
                            7'd52: char_code=buzz_on?"R":"S"; 7'd53: char_code=buzz_on?"I":"I";
                            7'd54: char_code=buzz_on?"N":"L"; 7'd55: char_code=buzz_on?"G":"E";
                            7'd56: char_code=buzz_on?"I":"N"; 7'd57: char_code=buzz_on?"N":"T";
                            7'd58: char_code=buzz_on?"G":" "; 7'd59: char_code=buzz_on?"!":" ";
                            default: char_code=" ";
                        endcase
                    end
                end

                // ------------------------------------------------------------
                // PAGE 3: 04 DIAG (硬件接口与曲线缓冲诊断)
                // ------------------------------------------------------------
                default: begin
                    // 顶部小标题 (48 chars @ x=20..403, y=96..111)
                    if (y >= 10'd96 && y < 10'd112 && x >= 10'd20 && x < 10'd404) begin
                        dx = x - 10'd20; cidx = dx[8:3]; font_col = dx[2:0];
                        font_row = (y - 10'd96) >> 1;
                        txt_en = 1'b1; text_role = TR_MUTED;
                        case (cidx[5:0])
                            6'd0: char_code="H"; 6'd1: char_code="A"; 6'd2: char_code="R"; 6'd3: char_code="D";
                            6'd4: char_code="W"; 6'd5: char_code="A"; 6'd6: char_code="R"; 6'd7: char_code="E";
                            6'd8: char_code=" "; 6'd9: char_code="D"; 6'd10: char_code="I"; 6'd11: char_code="A";
                            6'd12: char_code="G"; 6'd13: char_code="N"; 6'd14: char_code="O"; 6'd15: char_code="S";
                            6'd16: char_code="T"; 6'd17: char_code="I"; 6'd18: char_code="C"; 6'd19: char_code="S";
                            6'd20: char_code=" "; 6'd21: char_code="("; 6'd22: char_code="V"; 6'd23: char_code="1";
                            6'd24: char_code="."; 6'd25: char_code="3"; 6'd26: char_code=")";
                            default: char_code=" ";
                        endcase
                    end
                    // 4 张诊断卡片 (y=124/196/268/340, 文字行 y+22..y+37)
                    else if ((y >= 10'd146 && y < 10'd162) || (y >= 10'd218 && y < 10'd234) ||
                             (y >= 10'd290 && y < 10'd306) || (y >= 10'd362 && y < 10'd378)) begin
                        if (y < 10'd162) begin ridx = 2'd0; dy = y - 10'd146; end
                        else if (y < 10'd234) begin ridx = 2'd1; dy = y - 10'd218; end
                        else if (y < 10'd306) begin ridx = 2'd2; dy = y - 10'd290; end
                        else begin ridx = 2'd3; dy = y - 10'd362; end
                        font_row = dy[3:1];

                        if (x >= 10'd32 && x < 10'd608) begin
                            dx = x - 10'd32; cidx = dx[9:3]; font_col = dx[2:0];
                            txt_en = 1'b1;
                            if (cidx < 7'd30) begin
                                text_role = (item_idx == ridx) ? TR_ACCENT : TR_MUTED;
                            end else if (ridx == 2'd0) begin
                                text_role = th_ok ? TR_OK : TR_ERR;
                            end else if (ridx == 2'd1) begin
                                text_role = ls_ok ? TR_OK : TR_ERR;
                            end else begin
                                text_role = TR_MAIN;
                            end

                            if (cidx == 7'd0) char_code = (item_idx == ridx) ? ">" : " ";
                            else if (cidx == 7'd1) char_code = " ";
                            else if (ridx == 2'd0) begin
                                case (cidx)
                                    7'd2: char_code="P"; 7'd3: char_code="M"; 7'd4: char_code="O"; 7'd5: char_code="D";
                                    7'd6: char_code=" "; 7'd7: char_code="J"; 7'd8: char_code="B"; 7'd9: char_code=" ";
                                    7'd10: char_code="H"; 7'd11: char_code="D"; 7'd12: char_code="C"; 7'd13: char_code="1";
                                    7'd14: char_code="0"; 7'd15: char_code="8"; 7'd16: char_code="0"; 7'd17: char_code=" ";
                                    7'd18: char_code="("; 7'd19: char_code="T"; 7'd20: char_code="H"; 7'd21: char_code=")";
                                    7'd30: char_code=th_ok?"O":"O"; 7'd31: char_code=th_ok?"N":"F";
                                    7'd32: char_code=th_ok?"L":"F"; 7'd33: char_code=th_ok?"I":"L";
                                    7'd34: char_code=th_ok?"N":"I"; 7'd35: char_code=th_ok?"E":"N";
                                    7'd36: char_code=th_ok?" ":"E"; 7'd37: char_code=th_ok?"(":" ";
                                    7'd38: char_code=th_ok?"I":"/"; 7'd39: char_code=th_ok?"2":" ";
                                    7'd40: char_code=th_ok?"C":"S"; 7'd41: char_code=th_ok?" ":"T";
                                    7'd42: char_code=th_ok?"0":"A"; 7'd43: char_code=th_ok?"x":"L";
                                    7'd44: char_code=th_ok?"4":"E"; 7'd45: char_code=th_ok?"0":" ";
                                    7'd46: char_code=th_ok?")":" ";
                                    default: char_code=" ";
                                endcase
                            end else if (ridx == 2'd1) begin
                                case (cidx)
                                    7'd2: char_code="P"; 7'd3: char_code="M"; 7'd4: char_code="O"; 7'd5: char_code="D";
                                    7'd6: char_code=" "; 7'd7: char_code="J"; 7'd8: char_code="C"; 7'd9: char_code=" ";
                                    7'd10: char_code="A"; 7'd11: char_code="L"; 7'd12: char_code="S"; 7'd13: char_code=" ";
                                    7'd14: char_code="("; 7'd15: char_code="L"; 7'd16: char_code="I"; 7'd17: char_code="G";
                                    7'd18: char_code="H"; 7'd19: char_code="T"; 7'd20: char_code=")";
                                    7'd30: char_code=ls_ok?"O":"O"; 7'd31: char_code=ls_ok?"N":"F";
                                    7'd32: char_code=ls_ok?"L":"F"; 7'd33: char_code=ls_ok?"I":"L";
                                    7'd34: char_code=ls_ok?"N":"I"; 7'd35: char_code=ls_ok?"E":"N";
                                    7'd36: char_code=ls_ok?" ":"E"; 7'd37: char_code=ls_ok?"(":" ";
                                    7'd38: char_code=ls_ok?"S":"/"; 7'd39: char_code=ls_ok?"P":" ";
                                    7'd40: char_code=ls_ok?"I":"S"; 7'd41: char_code=ls_ok?" ":"T";
                                    7'd42: char_code=ls_ok?"8":"A"; 7'd43: char_code=ls_ok?"b":"L";
                                    7'd44: char_code=ls_ok?" ":"E"; 7'd45: char_code=ls_ok?"O":" ";
                                    7'd46: char_code=ls_ok?"K":" "; 7'd47: char_code=ls_ok?")":" ";
                                    default: char_code=" ";
                                endcase
                            end else if (ridx == 2'd2) begin
                                case (cidx)
                                    7'd2: char_code="S"; 7'd3: char_code="E"; 7'd4: char_code="N"; 7'd5: char_code="S";
                                    7'd6: char_code="O"; 7'd7: char_code="R"; 7'd8: char_code="_"; 7'd9: char_code="S";
                                    7'd10: char_code="T"; 7'd11: char_code="A"; 7'd12: char_code="T"; 7'd13: char_code="U";
                                    7'd14: char_code="S"; 7'd15: char_code=" "; 7'd16: char_code="/"; 7'd17: char_code=" ";
                                    7'd18: char_code="S"; 7'd19: char_code="W";
                                    7'd30: char_code="S"; 7'd31: char_code="T"; 7'd32: char_code="=";
                                    7'd33: char_code="0"; 7'd34: char_code="x";
                                    7'd35: char_code=h2a(sensor_status[7:4]);
                                    7'd36: char_code=h2a(sensor_status[3:0]);
                                    7'd40: char_code="S"; 7'd41: char_code="W"; 7'd42: char_code="=";
                                    7'd43: char_code="0"; 7'd44: char_code="x";
                                    7'd45: char_code=h2a(sw[15:12]);
                                    7'd46: char_code=h2a(sw[11:8]);
                                    7'd47: char_code=h2a(sw[7:4]);
                                    7'd48: char_code=h2a(sw[3:0]);
                                    default: char_code=" ";
                                endcase
                            end else begin
                                case (cidx)
                                    7'd2: char_code="C"; 7'd3: char_code="U"; 7'd4: char_code="R"; 7'd5: char_code="V";
                                    7'd6: char_code="E"; 7'd7: char_code=" "; 7'd8: char_code="R"; 7'd9: char_code="I";
                                    7'd10: char_code="N"; 7'd11: char_code="G"; 7'd12: char_code=" "; 7'd13: char_code="B";
                                    7'd14: char_code="U"; 7'd15: char_code="F"; 7'd16: char_code="F"; 7'd17: char_code="E";
                                    7'd18: char_code="R";
                                    7'd30: char_code="3"; 7'd31: char_code="C"; 7'd32: char_code="H"; 7'd33: char_code=" ";
                                    7'd34: char_code="x"; 7'd35: char_code=" "; 7'd36: char_code="1"; 7'd37: char_code="2";
                                    7'd38: char_code="8"; 7'd39: char_code="P"; 7'd40: char_code="T"; 7'd41: char_code="S";
                                    7'd42: char_code=" "; 7'd43: char_code="x"; 7'd44: char_code=" "; 7'd45: char_code="7";
                                    7'd46: char_code="b"; 7'd47: char_code=" "; 7'd48: char_code="@"; 7'd49: char_code="1";
                                    7'd50: char_code="H"; 7'd51: char_code="z";
                                    default: char_code=" ";
                                endcase
                            end
                        end
                    end
                end
            endcase
        end
    end

endmodule

`default_nettype wire
