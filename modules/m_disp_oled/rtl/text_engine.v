// ============================================================================
//  modules/m_disp_oled/rtl/text_engine.v —— 4 行 × 16 字符文本缓冲（OLED 显存）
//  负责人：组长
//
//  作用：把温度/湿度/光照/报警等级/传感器状态格式化成 64 个 ASCII 字符，
//        存进一个 64×8 的缓冲区；oled_spi 按 (page, idx) 来取字符。
//
//  画面（每行 16 字符，对应 OLED 的 4 页）：
//      ENV MONITOR
//      T:+25.3C H:55.0%
//      L:0320lx ALM:2
//      OK
//
//  ⚠️ 数字拆分为什么用"减法计数"：见 report_tx.v 里的说明——16 位常数除法
//     在 100 MHz 下要 10.5 ns（16 级逻辑），会直接把时序打崩。这里同样用
//     减 1000 / 100 / 10 的循环数数，路径只剩一两级减法。
//
//  刷新：每来一个 tick_1hz 重新格式化一次（结构简单，1 秒一次完全够）。
// ============================================================================
module text_engine (
    input  wire               clk,
    input  wire               rst,
    input  wire               refresh_tick,   // 重新格式化的节拍（100 ms）
    input  wire signed [15:0] temp_x10,
    input  wire        [15:0] humi_x10,
    input  wire        [15:0] lux,
    input  wire        [3:0]  alarm_level,
    input  wire        [3:0]  alarm_src,
    input  wire        [7:0]  sensor_status,

    // ---- 读口：oled_spi 告诉我要哪个字符 ----
    input  wire        [1:0]  page,      // 0~3
    input  wire        [3:0]  idx,       // 页内第几个字符 0~15
    output wire        [7:0]  ch        // 该字符的 ASCII
);

    // ---------------- 64 字符缓冲 ----------------
    // 注意：变量名不能叫 buf —— buf 是 Verilog 内置的缓冲门原语，会报语法错误
    reg [7:0] line_buf [0:63];

    assign ch = line_buf[{page, idx}];

    // ---------------- 格式化用的寄存器 ----------------
    reg [7:0]  d_sign;                  // '+' / '-'
    reg [3:0]  d_th, d_tt, d_tu;        // 温度 百/十/个（0.1 ℃ 的整数部分）
    reg [3:0]  d_hh, d_ht, d_hu;        // 湿度
    reg [3:0]  d_lk, d_lh, d_lt, d_lu;  // 光照 千/百/十/个
    reg [3:0]  d_alm;                   // 报警等级
    reg [1:0]  d_stat;                  // 0=OK 1=ALARM! 2=SENSOR FAIL

    reg [15:0] acc;                     // 减法计数的余数
    reg [3:0]  dv_k, dv_h, dv_t, dv_u;  // 正在数的四位
    reg [1:0]  pass;                    // 0=温度 1=湿度 2=光照
    reg [5:0]  fi;                      // 填缓冲的下标
    reg        started;

    localparam [1:0] S_IDLE  = 2'd0,
                     S_DIG   = 2'd1,
                     S_STORE = 2'd2,
                     S_FILL  = 2'd3;

    reg [1:0] st;

    // ---------------- 数字 → ASCII ----------------
    function [7:0] d2a;
        input [3:0] v;
        begin
            d2a = 8'h30 + {4'd0, v};
        end
    endfunction

    // ---------------- 第 i 个字符显示什么（整屏布局就写在这张表里）----------------
    function [7:0] char_at;
        input [5:0] i;
        begin
            case (i)
                // ---- 第 0 行：ENV MONITOR ----
                6'd0 : char_at = "E";
                6'd1 : char_at = "N";
                6'd2 : char_at = "V";
                6'd3 : char_at = " ";
                6'd4 : char_at = "M";
                6'd5 : char_at = "O";
                6'd6 : char_at = "N";
                6'd7 : char_at = "I";
                6'd8 : char_at = "T";
                6'd9 : char_at = "O";
                6'd10: char_at = "R";

                // ---- 第 1 行：T:+25.3C H:55.0% ----
                6'd16: char_at = "T";
                6'd17: char_at = ":";
                6'd18: char_at = d_sign;
                6'd19: char_at = d2a(d_th);
                6'd20: char_at = d2a(d_tt);
                6'd21: char_at = ".";
                6'd22: char_at = d2a(d_tu);
                6'd23: char_at = "C";
                6'd24: char_at = " ";
                6'd25: char_at = "H";
                6'd26: char_at = ":";
                6'd27: char_at = d2a(d_hh);
                6'd28: char_at = d2a(d_ht);
                6'd29: char_at = ".";
                6'd30: char_at = d2a(d_hu);
                6'd31: char_at = "%";

                // ---- 第 2 行：L:0320lx ALM:2 ----
                6'd32: char_at = "L";
                6'd33: char_at = ":";
                6'd34: char_at = d2a(d_lk);
                6'd35: char_at = d2a(d_lh);
                6'd36: char_at = d2a(d_lt);
                6'd37: char_at = d2a(d_lu);
                6'd38: char_at = "l";
                6'd39: char_at = "x";
                6'd40: char_at = " ";
                6'd41: char_at = "A";
                6'd42: char_at = "L";
                6'd43: char_at = "M";
                6'd44: char_at = ":";
                6'd45: char_at = d2a(d_alm);

                // ---- 第 3 行：状态 ----
                6'd48: char_at = (d_stat == 2'd2) ? "S" : (d_stat == 2'd1) ? "A" : "O";
                6'd49: char_at = (d_stat == 2'd2) ? "E" : (d_stat == 2'd1) ? "L" : "K";
                6'd50: char_at = (d_stat == 2'd2) ? "N" : (d_stat == 2'd1) ? "A" : " ";
                6'd51: char_at = (d_stat == 2'd2) ? "S" : (d_stat == 2'd1) ? "R" : " ";
                6'd52: char_at = (d_stat == 2'd2) ? "O" : (d_stat == 2'd1) ? "M" : " ";
                6'd53: char_at = (d_stat == 2'd2) ? "R" : (d_stat == 2'd1) ? "!" : " ";
                6'd54: char_at = (d_stat == 2'd2) ? " " : " ";
                6'd55: char_at = (d_stat == 2'd2) ? "F" : " ";
                6'd56: char_at = (d_stat == 2'd2) ? "A" : " ";
                6'd57: char_at = (d_stat == 2'd2) ? "I" : " ";
                6'd58: char_at = (d_stat == 2'd2) ? "L" : " ";

                default: char_at = " ";      // 其余补空格
            endcase
        end
    endfunction

    // ---------------- 数值钳位 ----------------
    wire [15:0] t_abs   = (temp_x10 < 16'sd0) ? (-temp_x10) : temp_x10;
    wire [15:0] t_clamp = (t_abs    > 16'd999)  ? 16'd999  : t_abs;
    wire [15:0] h_clamp = (humi_x10 > 16'd999)  ? 16'd999  : humi_x10;
    wire [15:0] l_clamp = (lux      > 16'd4095) ? 16'd4095 : lux;

    wire fault = (sensor_status[0] == 1'b0) || (sensor_status[1] == 1'b0)
              || (sensor_status[2] == 1'b1) || (sensor_status[3] == 1'b1);

    // ---------------- 主状态机 ----------------
    always @(posedge clk) begin
        if (rst) begin
            st      <= S_IDLE;
            started <= 1'b0;
            acc     <= 16'd0;
            dv_k <= 4'd0; dv_h <= 4'd0; dv_t <= 4'd0; dv_u <= 4'd0;
            pass <= 2'd0;
            fi   <= 6'd0;
            d_sign <= "+";
            d_th <= 0; d_tt <= 0; d_tu <= 0;
            d_hh <= 0; d_ht <= 0; d_hu <= 0;
            d_lk <= 0; d_lh <= 0; d_lt <= 0; d_lu <= 0;
            d_alm <= 4'd0; d_stat <= 2'd0;
        end else begin
            case (st)
                // ---------- 等 1 Hz 节拍（复位后先来一次，避免屏幕上全是乱码）----------
                S_IDLE: begin
                    if (refresh_tick || !started) begin
                        started <= 1'b1;
                        d_sign  <= (temp_x10 < 16'sd0) ? "-" : "+";
                        d_alm   <= alarm_level;
                        d_stat  <= fault ? 2'd2 : (alarm_level >= 4'd2) ? 2'd1 : 2'd0;
                        acc     <= t_clamp;
                        pass    <= 2'd0;
                        dv_k <= 4'd0; dv_h <= 4'd0; dv_t <= 4'd0; dv_u <= 4'd0;
                        st   <= S_DIG;
                    end
                end

                // ---------- 减法计数 ----------
                S_DIG: begin
                    if (acc >= 16'd1000) begin
                        acc  <= acc - 16'd1000;
                        dv_k <= dv_k + 1'b1;
                    end else if (acc >= 16'd100) begin
                        acc  <= acc - 16'd100;
                        dv_h <= dv_h + 1'b1;
                    end else if (acc >= 16'd10) begin
                        acc  <= acc - 16'd10;
                        dv_t <= dv_t + 1'b1;
                    end else begin
                        dv_u <= acc[3:0];
                        st   <= S_STORE;
                    end
                end

                // ---------- 存数字，换下一个值 ----------
                S_STORE: begin
                    case (pass)
                        2'd0: begin d_th <= dv_h; d_tt <= dv_t; d_tu <= dv_u; end
                        2'd1: begin d_hh <= dv_h; d_ht <= dv_t; d_hu <= dv_u; end
                        2'd2: begin d_lk <= dv_k; d_lh <= dv_h; d_lt <= dv_t; d_lu <= dv_u; end
                    endcase
                    dv_k <= 4'd0; dv_h <= 4'd0; dv_t <= 4'd0; dv_u <= 4'd0;

                    if (pass == 2'd2) begin
                        fi <= 6'd0;
                        st <= S_FILL;
                    end else begin
                        pass <= pass + 2'd1;
                        acc  <= (pass == 2'd0) ? h_clamp : l_clamp;
                        st   <= S_DIG;
                    end
                end

                // ---------- 逐字符填缓冲（64 拍 = 0.64 µs）----------
                S_FILL: begin
                    line_buf[fi] <= char_at(fi);
                    if (fi == 6'd63) begin
                        st <= S_IDLE;
                    end else begin
                        fi <= fi + 6'd1;
                    end
                end

                default: st <= S_IDLE;
            endcase
        end
    end

endmodule
