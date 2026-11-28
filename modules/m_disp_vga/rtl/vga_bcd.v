// ============================================================================
//  modules/m_disp_vga/rtl/vga_bcd.v
//  VGA 场消隐期二进制转 BCD 单元 + 拨码阈值查表解码（成员C）
//
//  为什么在场消隐期串行转 BCD：
//    1) 严禁在 100 MHz 下写 16 位组合除法 (/10, %10)，会破坏建立时间；
//    2) 使用共享的 16 步移位加三 (Double Dabble) 状态机，5 路数据（温度/湿度/
//       光照/单路曲线 MIN/单路曲线 MAX）仅需约 85 拍 (0.85 us) 即可全部转完，
//       远小于 640x480 的场消隐窗口 (1.44 ms)，且整帧显示期间数值锁存不变、无撕裂。
//    3) SW[9:0] 的三路阈值仅有 16 / 16 / 4 种档位，直接用组合查表零延迟输出 BCD，
//       公式严格对齐 docs/接口协议.md v1.3 与 alarm_ctrl.v。
// ============================================================================
`default_nettype none

module vga_bcd (
    input  wire               clk,
    input  wire               rst,
    input  wire               frame_start,   // 场消隐首拍脉冲 (y==480 && x==0 && pix_en)
    input  wire signed [15:0] temp_x10,      // 0.1 C 有符号
    input  wire        [15:0] humi_x10,      // 0.1 %RH 无符号
    input  wire        [15:0] lux,           // 1 lx 无符号
    input  wire signed [15:0] stat_min,      // 当前单路大图统计最小值
    input  wire signed [15:0] stat_max,      // 当前单路大图统计最大值
    input  wire               stat_signed,   // 1=有符号(温度), 0=无符号(湿度/光照)
    input  wire        [9:0]  sw_thresh,     // SW[9:0]

    // ---- 锁存后的实时传感器 BCD ----
    output reg                t_neg,
    output reg         [3:0]  t_d2, t_d1, t_d0,        // XX.X C
    output reg         [3:0]  h_d2, h_d1, h_d0,        // XX.X %
    output reg         [3:0]  l_d3, l_d2, l_d1, l_d0,  // XXXX lx

    // ---- 锁存后的单路曲线 MIN/MAX BCD ----
    output reg                min_neg,
    output reg         [3:0]  min_d3, min_d2, min_d1, min_d0,
    output reg                max_neg,
    output reg         [3:0]  max_d3, max_d2, max_d1, max_d0,

    // ---- 拨码开关解码阈值 BCD（与 alarm_ctrl.v 严格同步）----
    output reg         [3:0]  th_t_d1, th_t_d0,        // 20..50 C (小数位恒 0)
    output reg         [3:0]  th_h_d2, th_h_d1, th_h_d0, // 040..115 %
    output reg         [3:0]  th_l_d2, th_l_d1, th_l_d0  // 020/040/080/160 lx
);

    // ---------------- 拨码阈值查表（无除法）----------------
    // 温度上限 = 20 + SW[3:0] * 2  (20..50 C)
    always @(*) begin
        case (sw_thresh[3:0])
            4'd0 : begin th_t_d1 = 4'd2; th_t_d0 = 4'd0; end
            4'd1 : begin th_t_d1 = 4'd2; th_t_d0 = 4'd2; end
            4'd2 : begin th_t_d1 = 4'd2; th_t_d0 = 4'd4; end
            4'd3 : begin th_t_d1 = 4'd2; th_t_d0 = 4'd6; end
            4'd4 : begin th_t_d1 = 4'd2; th_t_d0 = 4'd8; end
            4'd5 : begin th_t_d1 = 4'd3; th_t_d0 = 4'd0; end
            4'd6 : begin th_t_d1 = 4'd3; th_t_d0 = 4'd2; end
            4'd7 : begin th_t_d1 = 4'd3; th_t_d0 = 4'd4; end
            4'd8 : begin th_t_d1 = 4'd3; th_t_d0 = 4'd6; end
            4'd9 : begin th_t_d1 = 4'd3; th_t_d0 = 4'd8; end
            4'd10: begin th_t_d1 = 4'd4; th_t_d0 = 4'd0; end
            4'd11: begin th_t_d1 = 4'd4; th_t_d0 = 4'd2; end
            4'd12: begin th_t_d1 = 4'd4; th_t_d0 = 4'd4; end
            4'd13: begin th_t_d1 = 4'd4; th_t_d0 = 4'd6; end
            4'd14: begin th_t_d1 = 4'd4; th_t_d0 = 4'd8; end
            default: begin th_t_d1 = 4'd5; th_t_d0 = 4'd0; end
        endcase
    end

    // 湿度上限 = 40 + SW[7:4] * 5  (40..115 %RH)
    always @(*) begin
        case (sw_thresh[7:4])
            4'd0 : begin th_h_d2 = 4'd0; th_h_d1 = 4'd4; th_h_d0 = 4'd0; end
            4'd1 : begin th_h_d2 = 4'd0; th_h_d1 = 4'd4; th_h_d0 = 4'd5; end
            4'd2 : begin th_h_d2 = 4'd0; th_h_d1 = 4'd5; th_h_d0 = 4'd0; end
            4'd3 : begin th_h_d2 = 4'd0; th_h_d1 = 4'd5; th_h_d0 = 4'd5; end
            4'd4 : begin th_h_d2 = 4'd0; th_h_d1 = 4'd6; th_h_d0 = 4'd0; end
            4'd5 : begin th_h_d2 = 4'd0; th_h_d1 = 4'd6; th_h_d0 = 4'd5; end
            4'd6 : begin th_h_d2 = 4'd0; th_h_d1 = 4'd7; th_h_d0 = 4'd0; end
            4'd7 : begin th_h_d2 = 4'd0; th_h_d1 = 4'd7; th_h_d0 = 4'd5; end
            4'd8 : begin th_h_d2 = 4'd0; th_h_d1 = 4'd8; th_h_d0 = 4'd0; end
            4'd9 : begin th_h_d2 = 4'd0; th_h_d1 = 4'd8; th_h_d0 = 4'd5; end
            4'd10: begin th_h_d2 = 4'd0; th_h_d1 = 4'd9; th_h_d0 = 4'd0; end
            4'd11: begin th_h_d2 = 4'd0; th_h_d1 = 4'd9; th_h_d0 = 4'd5; end
            4'd12: begin th_h_d2 = 4'd1; th_h_d1 = 4'd0; th_h_d0 = 4'd0; end
            4'd13: begin th_h_d2 = 4'd1; th_h_d1 = 4'd0; th_h_d0 = 4'd5; end
            4'd14: begin th_h_d2 = 4'd1; th_h_d1 = 4'd1; th_h_d0 = 4'd0; end
            default: begin th_h_d2 = 4'd1; th_h_d1 = 4'd1; th_h_d0 = 4'd5; end
        endcase
    end

    // 光照下限 = 20 << SW[9:8]  (20 / 40 / 80 / 160 lx)
    always @(*) begin
        case (sw_thresh[9:8])
            2'd0: begin th_l_d2 = 4'd0; th_l_d1 = 4'd2; th_l_d0 = 4'd0; end
            2'd1: begin th_l_d2 = 4'd0; th_l_d1 = 4'd4; th_l_d0 = 4'd0; end
            2'd2: begin th_l_d2 = 4'd0; th_l_d1 = 4'd8; th_l_d0 = 4'd0; end
            default: begin th_l_d2 = 4'd1; th_l_d1 = 4'd6; th_l_d0 = 4'd0; end
        endcase
    end

    // ---------------- 共享移位加三 BCD 转换器 ----------------
    // 钳位并取绝对值
    wire        t_is_neg = temp_x10[15];
    wire [15:0] t_abs    = t_is_neg ? (~temp_x10 + 16'd1) : temp_x10;
    wire [15:0] t_clamp  = (t_abs > 16'd999) ? 16'd999 : t_abs;
    wire [15:0] h_clamp  = (humi_x10 > 16'd999) ? 16'd999 : humi_x10;
    wire [15:0] l_clamp  = (lux > 16'd4095) ? 16'd4095 : lux;

    wire        smin_neg = stat_signed && stat_min[15];
    wire [15:0] smin_abs = smin_neg ? (~stat_min + 16'd1) : stat_min;
    wire [15:0] smin_cl  = (smin_abs > 16'd4095) ? 16'd4095 : smin_abs;

    wire        smax_neg = stat_signed && stat_max[15];
    wire [15:0] smax_abs = smax_neg ? (~stat_max + 16'd1) : stat_max;
    wire [15:0] smax_cl  = (smax_abs > 16'd4095) ? 16'd4095 : smax_abs;

    reg        busy;
    reg        started;
    reg [2:0]  pass;      // 0:T, 1:H, 2:L, 3:MIN, 4:MAX
    reg [3:0]  bit_cnt;   // 0..15
    reg [15:0] bin_sr;
    reg [15:0] bcd_sr;    // 4 位 BCD (0..9999)
    reg [15:0] h_hold, l_hold, min_hold, max_hold;

    function [15:0] add3_nibbles;
        input [15:0] v;
        reg [3:0] n0, n1, n2, n3;
        begin
            n0 = (v[3:0]   >= 4'd5) ? (v[3:0]   + 4'd3) : v[3:0];
            n1 = (v[7:4]   >= 4'd5) ? (v[7:4]   + 4'd3) : v[7:4];
            n2 = (v[11:8]  >= 4'd5) ? (v[11:8]  + 4'd3) : v[11:8];
            n3 = (v[15:12] >= 4'd5) ? (v[15:12] + 4'd3) : v[15:12];
            add3_nibbles = {n3, n2, n1, n0};
        end
    endfunction

    wire [15:0] bcd_adj  = add3_nibbles(bcd_sr);
    wire [15:0] bcd_next = {bcd_adj[14:0], bin_sr[15]};

    always @(posedge clk) begin
        if (rst) begin
            busy     <= 1'b0;
            started  <= 1'b0;
            pass     <= 3'd0;
            bit_cnt  <= 4'd0;
            bin_sr   <= 16'd0;
            bcd_sr   <= 16'd0;
            h_hold   <= 16'd0;
            l_hold   <= 16'd0;
            min_hold <= 16'd0;
            max_hold <= 16'd0;
            t_neg    <= 1'b0;
            t_d2 <= 4'd0; t_d1 <= 4'd0; t_d0 <= 4'd0;
            h_d2 <= 4'd0; h_d1 <= 4'd0; h_d0 <= 4'd0;
            l_d3 <= 4'd0; l_d2 <= 4'd0; l_d1 <= 4'd0; l_d0 <= 4'd0;
            min_neg <= 1'b0;
            min_d3 <= 4'd0; min_d2 <= 4'd0; min_d1 <= 4'd0; min_d0 <= 4'd0;
            max_neg <= 1'b0;
            max_d3 <= 4'd0; max_d2 <= 4'd0; max_d1 <= 4'd0; max_d0 <= 4'd0;
        end else if (!busy) begin
            // 上电后立刻触发一次，之后每帧场消隐首拍触发
            if (frame_start || !started) begin
                started  <= 1'b1;
                busy     <= 1'b1;
                pass     <= 3'd0;
                bit_cnt  <= 4'd0;
                bcd_sr   <= 16'd0;
                t_neg    <= t_is_neg;
                min_neg  <= smin_neg;
                max_neg  <= smax_neg;
                bin_sr   <= t_clamp;
                h_hold   <= h_clamp;
                l_hold   <= l_clamp;
                min_hold <= smin_cl;
                max_hold <= smax_cl;
            end
        end else begin
            if (bit_cnt == 4'd15) begin
                bit_cnt <= 4'd0;
                bcd_sr  <= 16'd0;
                case (pass)
                    3'd0: begin
                        t_d2   <= bcd_next[11:8];
                        t_d1   <= bcd_next[7:4];
                        t_d0   <= bcd_next[3:0];
                        bin_sr <= h_hold;
                        pass   <= 3'd1;
                    end
                    3'd1: begin
                        h_d2   <= bcd_next[11:8];
                        h_d1   <= bcd_next[7:4];
                        h_d0   <= bcd_next[3:0];
                        bin_sr <= l_hold;
                        pass   <= 3'd2;
                    end
                    3'd2: begin
                        l_d3   <= bcd_next[15:12];
                        l_d2   <= bcd_next[11:8];
                        l_d1   <= bcd_next[7:4];
                        l_d0   <= bcd_next[3:0];
                        bin_sr <= min_hold;
                        pass   <= 3'd3;
                    end
                    3'd3: begin
                        min_d3 <= bcd_next[15:12];
                        min_d2 <= bcd_next[11:8];
                        min_d1 <= bcd_next[7:4];
                        min_d0 <= bcd_next[3:0];
                        bin_sr <= max_hold;
                        pass   <= 3'd4;
                    end
                    default: begin
                        max_d3 <= bcd_next[15:12];
                        max_d2 <= bcd_next[11:8];
                        max_d1 <= bcd_next[7:4];
                        max_d0 <= bcd_next[3:0];
                        busy   <= 1'b0;
                        pass   <= 3'd0;
                    end
                endcase
            end else begin
                bit_cnt <= bit_cnt + 4'd1;
                bin_sr  <= {bin_sr[14:0], 1'b0};
                bcd_sr  <= bcd_next;
            end
        end
    end

endmodule

`default_nettype wire
