// ============================================================================
//  common/tick_gen.v —— 节拍（tick）发生器
//
//  从 100 MHz 主时钟产生三种"单周期使能脉冲"：
//      tick_1khz : 给数码管动态扫描用（每 1 ms 一拍）
//      tick_10hz : 给 OLED / VGA 刷新用（每 100 ms 一拍）
//      tick_1hz  : 给传感器采样、报警判定用（每 1 s 一拍）
//
//  注意：tick 是"使能"，不是时钟。下游写法：
//      always @(posedge clk) if (tick_1hz) ...;      ← 正确
//      always @(posedge tick_1hz) ...;               ← 错误！派生时钟，禁止
//
//  CLK_HZ 是参数：上板用 100_000_000，仿真时可以改小（如 1000）跑得快。
// ============================================================================
module tick_gen #(
    parameter integer CLK_HZ = 100_000_000
) (
    input  wire clk,
    input  wire rst,
    output reg  tick_1khz,
    output reg  tick_10hz,
    output reg  tick_1hz
);

    // ---- 1 kHz 分频常数 ------------------------------------------------------
    localparam integer N_1KHZ = (CLK_HZ / 1000 < 1) ? 1 : (CLK_HZ / 1000);
    localparam integer W_1KHZ = (N_1KHZ <= 1) ? 1 : $clog2(N_1KHZ);

    // ---- 十进制链：1 kHz → 10 Hz → 1 Hz --------------------------------------
    reg [W_1KHZ-1:0] cnt_1khz;   // 0 .. N_1KHZ-1
    reg [6:0]        cnt_10hz;   // 0 .. 99   （100 个 1 kHz = 10 Hz）
    reg [3:0]        cnt_1hz;    // 0 .. 9    （10 个 10 Hz = 1 Hz）

    wire fire_1khz = (cnt_1khz == N_1KHZ - 1);
    wire fire_10hz = fire_1khz && (cnt_10hz == 7'd99);
    wire fire_1hz  = fire_10hz && (cnt_1hz  == 4'd9);

    always @(posedge clk) begin
        if (rst) begin
            cnt_1khz  <= {W_1KHZ{1'b0}};
            cnt_10hz  <= 7'd0;
            cnt_1hz   <= 4'd0;
            tick_1khz <= 1'b0;
            tick_10hz <= 1'b0;
            tick_1hz  <= 1'b0;
        end else begin
            // tick 输出：打一拍，保证是干净的单周期脉冲
            tick_1khz <= fire_1khz;
            tick_10hz <= fire_10hz;
            tick_1hz  <= fire_1hz;

            if (fire_1khz) begin
                cnt_1khz <= {W_1KHZ{1'b0}};
                if (fire_10hz) begin
                    cnt_10hz <= 7'd0;
                    cnt_1hz  <= fire_1hz ? 4'd0 : (cnt_1hz + 4'd1);
                end else begin
                    cnt_10hz <= cnt_10hz + 7'd1;
                end
            end else begin
                cnt_1khz <= cnt_1khz + 1'b1;
            end
        end
    end

endmodule
