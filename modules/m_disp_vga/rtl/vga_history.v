// ============================================================================
//  modules/m_disp_vga/rtl/vga_history.v
//  温度 / 湿度 / 光照三路实时监控曲线环形缓冲与统计模块（成员C）
//
//  功能：
//    1) 复用场消隐脉冲 frame_start 计数，每 SAMPLE_FRAMES 帧（默认 60 帧 ≈ 1s）
//       将当前温/湿/光量化为 7-bit 高度值 (0..127) 写入 128 点环形缓冲；
//    2) 上电首次采样自动在 128 拍内预填充全部 128 个历史槽位，避免开机出现
//       从 0 拉起的假跳变；
//    3) 双读口同步返回相邻两个采样点 (cur_q 与 prev_q)，供像素引擎画无断点
//       垂直连线折线图，零除法、低资源（3 x 128 x 7b = 336 字节）；
//    4) 同步输出三路阈值量化高度 th_*_q（与 SW[9:0] 实时联动）以及开机以来
//       各通道 MIN / MAX 统计值。
//
//  量程约定（与设计草图 v2 严格对齐）：
//    - 温度：-10.0 C .. +60.0 C (temp_x10: -100 .. +600，跨度 700)
//    - 湿度：  0.0 % .. 100.0 % (humi_x10:    0 .. 1000，跨度 1000)
//    - 光照：   0 lx .. 1000 lx (lux:         0 .. 1000，跨度 1000)
// ============================================================================
`default_nettype none

module vga_history #(
    parameter integer SAMPLE_FRAMES = 60    // 每多少帧写入 1 个曲线点 (60 帧 ≈ 1 Hz)
) (
    input  wire               clk,
    input  wire               rst,
    input  wire               frame_start,  // 场消隐首拍脉冲
    input  wire signed [15:0] temp_x10,
    input  wire        [15:0] humi_x10,
    input  wire        [15:0] lux,
    input  wire        [7:0]  sensor_status,
    input  wire        [9:0]  sw_thresh,    // SW[9:0]

    // ---- 像素流水线读口 (rd_idx=0 最旧在左，127 最新在右) ----
    input  wire        [6:0]  rd_idx,
    output reg         [6:0]  t_cur_q,
    output reg         [6:0]  t_prev_q,
    output reg         [6:0]  h_cur_q,
    output reg         [6:0]  h_prev_q,
    output reg         [6:0]  l_cur_q,
    output reg         [6:0]  l_prev_q,

    // ---- 实时报警阈值红线量化高度 (0..127) ----
    output reg         [6:0]  th_t_q,
    output reg         [6:0]  th_h_q,
    output reg         [6:0]  th_l_q,

    // ---- 各通道统计极值（用于单路大图头部）----
    output reg  signed [15:0] t_min,
    output reg  signed [15:0] t_max,
    output reg         [15:0] h_min,
    output reg         [15:0] h_max,
    output reg         [15:0] l_min,
    output reg         [15:0] l_max
);

    // ---------------- 实时值量化函数（纯乘加移位，零除法）----------------
    // 温度 -100..600 -> 偏移 0..700 -> *187 >> 10 -> 0..127
    function [6:0] quant_temp;
        input signed [15:0] v;
        reg signed [16:0] shifted;
        reg        [10:0] clamped;
        reg        [18:0] prod;
        begin
            shifted = $signed({v[15], v}) + 17'sd100;
            if (shifted <= 17'sd0)
                clamped = 11'd0;
            else if (shifted >= 17'sd700)
                clamped = 11'd700;
            else
                clamped = shifted[10:0];
            // 187 = 128 + 32 + 16 + 8 + 2 + 1
            prod = ({8'd0, clamped} << 7) + ({8'd0, clamped} << 5)
                 + ({8'd0, clamped} << 4) + ({8'd0, clamped} << 3)
                 + ({8'd0, clamped} << 1) + {8'd0, clamped};
            quant_temp = (prod[18:10] >= 9'd127) ? 7'd127 : prod[16:10];
        end
    endfunction

    // 湿度/光照 0..1000 -> *131 >> 10 -> 0..127
    function [6:0] quant_1000;
        input [15:0] v;
        reg [10:0] clamped;
        reg [18:0] prod;
        begin
            clamped = (v >= 16'd1000) ? 11'd1000 : v[10:0];
            // 131 = 128 + 2 + 1
            prod = ({8'd0, clamped} << 7) + ({8'd0, clamped} << 1) + {8'd0, clamped};
            quant_1000 = (prod[18:10] >= 9'd127) ? 7'd127 : prod[16:10];
        end
    endfunction

    wire [6:0] cur_tq = quant_temp(temp_x10);
    wire [6:0] cur_hq = quant_1000(humi_x10);
    wire [6:0] cur_lq = quant_1000(lux);

    // ---------------- 拨码阈值红线量化高度查表（与 quant_* 完全一致）----------------
    // 温度上限 = 200 + SW[3:0]*20 (200..500 -> 偏移 300..600 -> q = round((off)*127/700))
    always @(*) begin
        case (sw_thresh[3:0])
            4'd0 : th_t_q = 7'd54;   // 20 C
            4'd1 : th_t_q = 7'd58;   // 22 C
            4'd2 : th_t_q = 7'd62;   // 24 C
            4'd3 : th_t_q = 7'd65;   // 26 C
            4'd4 : th_t_q = 7'd69;   // 28 C
            4'd5 : th_t_q = 7'd73;   // 30 C
            4'd6 : th_t_q = 7'd76;   // 32 C
            4'd7 : th_t_q = 7'd80;   // 34 C
            4'd8 : th_t_q = 7'd83;   // 36 C
            4'd9 : th_t_q = 7'd87;   // 38 C
            4'd10: th_t_q = 7'd91;   // 40 C
            4'd11: th_t_q = 7'd94;   // 42 C
            4'd12: th_t_q = 7'd98;   // 44 C
            4'd13: th_t_q = 7'd102;  // 46 C
            4'd14: th_t_q = 7'd105;  // 48 C
            default: th_t_q = 7'd109; // 50 C
        endcase
    end

    // 湿度上限 = 400 + SW[7:4]*50 (400..1150，超过 100% 钳位顶边 127)
    always @(*) begin
        case (sw_thresh[7:4])
            4'd0 : th_h_q = 7'd51;   // 40 %
            4'd1 : th_h_q = 7'd57;   // 45 %
            4'd2 : th_h_q = 7'd64;   // 50 %
            4'd3 : th_h_q = 7'd70;   // 55 %
            4'd4 : th_h_q = 7'd76;   // 60 %
            4'd5 : th_h_q = 7'd83;   // 65 %
            4'd6 : th_h_q = 7'd89;   // 70 %
            4'd7 : th_h_q = 7'd95;   // 75 %
            4'd8 : th_h_q = 7'd102;  // 80 %
            4'd9 : th_h_q = 7'd108;  // 85 %
            4'd10: th_h_q = 7'd114;  // 90 %
            4'd11: th_h_q = 7'd121;  // 95 %
            default: th_h_q = 7'd127; // >= 100 %
        endcase
    end

    // 光照下限 = 20 / 40 / 80 / 160 lx (量程 0..1000)
    always @(*) begin
        case (sw_thresh[9:8])
            2'd0: th_l_q = 7'd3;     // 20 lx
            2'd1: th_l_q = 7'd5;     // 40 lx
            2'd2: th_l_q = 7'd10;    // 80 lx
            default: th_l_q = 7'd20; // 160 lx
        endcase
    end

    // ---------------- 3 路 x 128 点环形缓冲 ----------------
    reg [6:0] mem_t [0:127];
    reg [6:0] mem_h [0:127];
    reg [6:0] mem_l [0:127];

    reg [6:0] wr_ptr;        // 指向下一个要写入的槽位（即最旧点位置）
    reg [7:0] frame_cnt;
    reg       primed;        // 0 = 正在上电预填 128 槽，1 = 正常运行
    reg [6:0] fill_ptr;
    reg       th_stat_init;
    reg       ls_stat_init;

    wire th_ok = sensor_status[0] && !sensor_status[2];
    wire ls_ok = sensor_status[1] && !sensor_status[3];

    always @(posedge clk) begin
        if (rst) begin
            wr_ptr       <= 7'd0;
            frame_cnt    <= 8'd0;
            primed       <= 1'b0;
            fill_ptr     <= 7'd0;
            th_stat_init <= 1'b0;
            ls_stat_init <= 1'b0;
            t_min        <= 16'sd0;
            t_max        <= 16'sd0;
            h_min        <= 16'd0;
            h_max        <= 16'd0;
            l_min        <= 16'd0;
            l_max        <= 16'd0;
        end else if (!primed) begin
            // 复位释放后 128 拍内把整个历史缓冲初始化为当前值（避免假跳变）
            mem_t[fill_ptr] <= cur_tq;
            mem_h[fill_ptr] <= cur_hq;
            mem_l[fill_ptr] <= cur_lq;
            if (fill_ptr == 7'd127) begin
                primed <= 1'b1;
                t_min  <= temp_x10;
                t_max  <= temp_x10;
                h_min  <= humi_x10;
                h_max  <= humi_x10;
                l_min  <= lux;
                l_max  <= lux;
                th_stat_init <= th_ok;
                ls_stat_init <= ls_ok;
            end else begin
                fill_ptr <= fill_ptr + 7'd1;
            end
        end else if (frame_start) begin
            if (frame_cnt + 8'd1 >= SAMPLE_FRAMES[7:0]) begin
                frame_cnt <= 8'd0;
                mem_t[wr_ptr] <= cur_tq;
                mem_h[wr_ptr] <= cur_hq;
                mem_l[wr_ptr] <= cur_lq;
                wr_ptr <= wr_ptr + 7'd1;

                // 仅在对应传感器在线时更新极值
                if (th_ok) begin
                    if (!th_stat_init) begin
                        th_stat_init <= 1'b1;
                        t_min <= temp_x10;
                        t_max <= temp_x10;
                        h_min <= humi_x10;
                        h_max <= humi_x10;
                    end else begin
                        if (temp_x10 < t_min) t_min <= temp_x10;
                        if (temp_x10 > t_max) t_max <= temp_x10;
                        if (humi_x10 < h_min) h_min <= humi_x10;
                        if (humi_x10 > h_max) h_max <= humi_x10;
                    end
                end
                if (ls_ok) begin
                    if (!ls_stat_init) begin
                        ls_stat_init <= 1'b1;
                        l_min <= lux;
                        l_max <= lux;
                    end else begin
                        if (lux < l_min) l_min <= lux;
                        if (lux > l_max) l_max <= lux;
                    end
                end
            end else begin
                frame_cnt <= frame_cnt + 8'd1;
            end
        end
    end

    // ---------------- 同步双点读口 (cur & prev) ----------------
    wire [6:0] addr_cur  = wr_ptr + rd_idx;
    wire [6:0] addr_prev = (rd_idx == 7'd0) ? addr_cur : (wr_ptr + rd_idx - 7'd1);

    always @(posedge clk) begin
        t_cur_q  <= mem_t[addr_cur];
        t_prev_q <= mem_t[addr_prev];
        h_cur_q  <= mem_h[addr_cur];
        h_prev_q <= mem_h[addr_prev];
        l_cur_q  <= mem_l[addr_cur];
        l_prev_q <= mem_l[addr_prev];
    end

endmodule

`default_nettype wire
