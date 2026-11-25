// ============================================================================
//  modules/m_uart/rtl/report_tx.v —— 环境数据上报（UART，给上位机/串口助手）
//  负责人：组长
//
//  每 100 ms（tick_10hz）发一行固定长度 ASCII，格式写死 37 字节：
//
//      $ENV,T=+25.3,H=55.0,L=0320,A=2,S=03\r\n
//           │  │      │      │       │    └ 传感器状态字（16 进制，00 正常）
//           │  │      │      │       └────── 报警等级 0~3
//           │  │      │      └────────────── 光照（4 位，左补 0）
//           │  │      └───────────────────── 湿度（%RH，1 位小数）
//           │  └──────────────────────────── 温度（℃，1 位小数，带符号）
//           └─────────────────────────────── 帧头 $ENV,
//
//  ⚠️ 为什么数字要用"减法计数"算（别改回除法和乘法）：
//      第一版写 d_th <= t_clamp/100：Vivado 综合出 16 级"移位-减法"链，实测 WNS -0.36 ns；
//      第二版拆成 3 拍流水，单级 16 位常数除法仍然要 10.5 ns（16 级逻辑），还是不收敛；
//      现在改成：每个值用"减 1000 / 减 100 / 减 10"的循环数数，一共约 80 拍（0.8 µs，
//      而我们每 100 ms 才发一帧，时间绰绰有余），路径只剩一两级减法 → 时序轻松过。
//
//      状态机：
//        S_IDLE  : 等上报节拍，锁存符号，acc = 温度值
//        S_DIG   : acc >= 1000 就减 1000 并 +1；否则 >=100 减 100；否则 >=10 减 10；否则余数就是个位
//        S_STORE : 把 4 个数位存到当前值对应的 d_* 寄存器；换下一个值（温度→湿度→光照）
//        S_SEND  : 逐字节发
//
//  发送速率：37 字节 × 10 bit / 115200 ≈ 3.2 ms，远小于 100 ms，不会丢帧。
// ============================================================================
module report_tx #(
    parameter integer CLK_HZ = 100_000_000,
    parameter integer BAUD   = 115200
) (
    input  wire               clk,
    input  wire               rst,
    input  wire               report_tick,     // 100 ms 上报节拍
    input  wire signed [15:0] temp_x10,
    input  wire        [15:0] humi_x10,
    input  wire        [15:0] lux,
    input  wire        [3:0]  alarm_level,
    input  wire        [7:0]  sensor_status,
    output wire               uart_txd         // 到板载 USB-UART（D4）
);

    localparam integer LEN = 37;               // 一帧字节数

    // ---------------- 数值钳位（防止格式溢出）----------------
    wire [15:0] t_abs   = (temp_x10 < 16'sd0) ? (-temp_x10) : temp_x10;
    wire [15:0] t_clamp = (t_abs    > 16'd999)  ? 16'd999  : t_abs;    // 99.9 ℃
    wire [15:0] h_clamp = (humi_x10 > 16'd999)  ? 16'd999  : humi_x10; // 99.9 %RH
    wire [15:0] l_clamp = (lux      > 16'd4095) ? 16'd4095 : lux;      // 4 位

    // ---------------- 减法计数用的寄存器 ----------------
    reg [15:0] acc;                    // 当前剩下的数值
    reg [3:0]  dv_k, dv_h, dv_t, dv_u; // 正在数的四位（千/百/十/个）
    reg [1:0]  pass;                   // 0=温度 1=湿度 2=光照

    reg [7:0]  d_sign;                         // 帧头锁存
    reg [3:0]  d_th, d_tt, d_tu;
    reg [3:0]  d_hh, d_ht, d_hu;
    reg [3:0]  d_lk, d_lh, d_lt, d_lu;
    reg [3:0]  d_a;
    reg [3:0]  d_sh, d_sl;

    reg [1:0] st;
    reg [5:0] idx;

    localparam [1:0] S_IDLE  = 2'd0,
                     S_DIG   = 2'd1,
                     S_STORE = 2'd2,
                     S_SEND  = 2'd3;

    // ---------------- 数字 → ASCII ----------------
    function [7:0] hex2asc;
        input [3:0] v;
        begin
            hex2asc = (v < 4'd10) ? (8'h30 + {4'd0, v})     // '0'..'9'
                                  : (8'h37 + {4'd0, v});    // 'A'..'F'
        end
    endfunction

    // ---------------- 第 k 个字节发什么（整帧格式就写在这张表里）----------------
    function [7:0] char_of;
        input [5:0] k;
        begin
            case (k)
                6'd0 : char_of = "$";
                6'd1 : char_of = "E";
                6'd2 : char_of = "N";
                6'd3 : char_of = "V";
                6'd4 : char_of = ",";
                6'd5 : char_of = "T";
                6'd6 : char_of = "=";
                6'd7 : char_of = d_sign;
                6'd8 : char_of = hex2asc(d_th);
                6'd9 : char_of = hex2asc(d_tt);
                6'd10: char_of = ".";
                6'd11: char_of = hex2asc(d_tu);
                6'd12: char_of = ",";
                6'd13: char_of = "H";
                6'd14: char_of = "=";
                6'd15: char_of = hex2asc(d_hh);
                6'd16: char_of = hex2asc(d_ht);
                6'd17: char_of = ".";
                6'd18: char_of = hex2asc(d_hu);
                6'd19: char_of = ",";
                6'd20: char_of = "L";
                6'd21: char_of = "=";
                6'd22: char_of = hex2asc(d_lk);
                6'd23: char_of = hex2asc(d_lh);
                6'd24: char_of = hex2asc(d_lt);
                6'd25: char_of = hex2asc(d_lu);
                6'd26: char_of = ",";
                6'd27: char_of = "A";
                6'd28: char_of = "=";
                6'd29: char_of = hex2asc(d_a);
                6'd30: char_of = ",";
                6'd31: char_of = "S";
                6'd32: char_of = "=";
                6'd33: char_of = hex2asc(d_sh);
                6'd34: char_of = hex2asc(d_sl);
                6'd35: char_of = 8'h0D;      // '\r'
                6'd36: char_of = 8'h0A;      // '\n'
                default: char_of = 8'h20;    // 空格（不应出现）
            endcase
        end
    endfunction

    // ---------------- 字节流 → UART ----------------
    wire [7:0] tx_data  = char_of(idx);
    wire       tx_ready;
    wire       tx_valid = (st == S_SEND) && tx_ready;   // uart 空闲那拍才给

    uart_tx #(.CLK_HZ(CLK_HZ), .BAUD(BAUD)) u_uart (
        .clk   (clk),
        .rst   (rst),
        .data  (tx_data),
        .valid (tx_valid),
        .ready (tx_ready),
        .tx    (uart_txd)
    );

    // ---------------- 主状态机 ----------------
    always @(posedge clk) begin
        if (rst) begin
            st     <= S_IDLE;
            idx    <= 6'd0;
            acc    <= 16'd0;
            dv_k   <= 4'd0; dv_h <= 4'd0; dv_t <= 4'd0; dv_u <= 4'd0;
            pass   <= 2'd0;
            d_sign <= "+";
            d_th   <= 4'd0; d_tt <= 4'd0; d_tu <= 4'd0;
            d_hh   <= 4'd0; d_ht <= 4'd0; d_hu <= 4'd0;
            d_lk   <= 4'd0; d_lh <= 4'd0; d_lt <= 4'd0; d_lu <= 4'd0;
            d_a    <= 4'd0;
            d_sh   <= 4'd0; d_sl <= 4'd0;
        end else begin
            case (st)
                // ---------- 等节拍：锁符号，从温度开始拆 ----------
                S_IDLE: begin
                    if (report_tick) begin
                        d_sign <= (temp_x10 < 16'sd0) ? "-" : "+";
                        acc    <= t_clamp;
                        pass   <= 2'd0;
                        dv_k   <= 4'd0; dv_h <= 4'd0; dv_t <= 4'd0; dv_u <= 4'd0;
                        st     <= S_DIG;
                    end
                end

                // ---------- 减法计数：减 1000 / 100 / 10，数出各位 ----------
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
                        dv_u <= acc[3:0];       // 剩下的就是个位
                        st   <= S_STORE;
                    end
                end

                // ---------- 存进对应值的数字，然后换下一个值 ----------
                S_STORE: begin
                    case (pass)
                        2'd0: begin d_th <= dv_h; d_tt <= dv_t; d_tu <= dv_u; end
                        2'd1: begin d_hh <= dv_h; d_ht <= dv_t; d_hu <= dv_u; end
                        2'd2: begin d_lk <= dv_k; d_lh <= dv_h; d_lt <= dv_t; d_lu <= dv_u; end
                    endcase
                    dv_k <= 4'd0; dv_h <= 4'd0; dv_t <= 4'd0; dv_u <= 4'd0;

                    if (pass == 2'd2) begin
                        d_a  <= alarm_level;
                        d_sh <= sensor_status[7:4];
                        d_sl <= sensor_status[3:0];
                        idx  <= 6'd0;
                        st   <= S_SEND;
                    end else begin
                        pass <= pass + 2'd1;
                        acc  <= (pass == 2'd0) ? h_clamp : l_clamp;
                        st   <= S_DIG;
                    end
                end

                // ---------- 逐字节发出 ----------
                S_SEND: begin
                    if (tx_ready) begin
                        if (idx == LEN - 1)
                            st <= S_IDLE;
                        else
                            idx <= idx + 6'd1;
                    end
                end

                default: st <= S_IDLE;
            endcase
        end
    end

endmodule
