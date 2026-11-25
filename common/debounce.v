// ============================================================================
//  common/debounce.v —— 按键消抖（10 ms 稳定才认）
//
//  板载按键是机械触点，按下/松开瞬间会有几 ms 的抖动。直接进状态机会被识别成
//  连按多次，所以统一先过这个模块。
//
//  原理：某一位的电平和当前输出不同时开始计数，连续 MS 毫秒都不同才更新输出；
//        中途电平恢复就清零重来。（比"移位寄存器取多数"更省资源、更好讲）
//
//  极性：Nexys A7 的 5 个按键都是**按下为 1**，所以 dout=1 表示按下。
// ============================================================================
module debounce #(
    parameter integer CLK_HZ = 100_000_000,
    parameter integer MS     = 10,      // 稳定时间（毫秒）
    parameter integer WIDTH  = 5
) (
    input  wire             clk,
    input  wire             rst,
    input  wire [WIDTH-1:0] din,
    output wire [WIDTH-1:0] dout
);

    // MS 毫秒 = (CLK_HZ/1000)*MS 个时钟
    localparam integer N  = (CLK_HZ / 1000) * MS;
    localparam integer CW = (N <= 2) ? 2 : $clog2(N + 1);

    wire [WIDTH-1:0] dout_bits;

    genvar i;
    generate
        for (i = 0; i < WIDTH; i = i + 1) begin : g_bit
            reg [CW-1:0] cnt;
            reg          d;

            always @(posedge clk) begin
                if (rst) begin
                    cnt <= {CW{1'b0}};
                    d   <= 1'b0;
                end else if (din[i] != d) begin
                    if (cnt == N - 1) begin
                        d   <= din[i];        // 稳定够久了，认可新电平
                        cnt <= {CW{1'b0}};
                    end else begin
                        cnt <= cnt + 1'b1;
                    end
                end else begin
                    cnt <= {CW{1'b0}};        // 抖动/没变，重新计时
                end
            end

            assign dout_bits[i] = d;
        end
    endgenerate

    assign dout = dout_bits;

endmodule
