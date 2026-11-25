// ============================================================================
//  modules/m_uart/rtl/uart_tx.v —— UART 发送器（8N1，可配波特率）
//  负责人：组长
//
//  协议：8 数据位、无校验、1 停止位（8N1），LSB 先发，空闲为高。
//  参数：CLK_HZ / BAUD —— 在 100 MHz 下 115200 的分频比是 868
//        （实际 115200.5 bps，误差 0.006%，电脑串口助手能正常收）。
//
//  握手：ready=1 表示可以接受新字节；valid=1 且 ready=1 的那一拍，
//        data 被锁存并开始发送（valid 只需保持 1 拍）。
//
//  波形（发送 0xA5）：
//    idle ─┐ start ┌ bit0 ... bit7 ┐stop ┌ idle
//          0      1 0 1 0 0 1 0 1   1
// ============================================================================
module uart_tx #(
    parameter integer CLK_HZ = 100_000_000,
    parameter integer BAUD   = 115200
) (
    input  wire       clk,
    input  wire       rst,
    input  wire [7:0] data,      // 要发的字节
    input  wire       valid,     // 1 = 本拍 data 有效
    output wire       ready,     // 1 = 空闲，能接新字节
    output reg        tx         // 串行输出，空闲为高
);

    // 一个比特占多少个系统时钟
    localparam integer DIV = (CLK_HZ / BAUD < 1) ? 1 : (CLK_HZ / BAUD);
    localparam integer CW  = (DIV <= 2) ? 2 : $clog2(DIV + 1);

    localparam [1:0] S_IDLE  = 2'd0,
                     S_START = 2'd1,
                     S_DATA  = 2'd2,
                     S_STOP  = 2'd3;

    reg [1:0]    st;
    reg [CW-1:0] cnt;       // 位内计时 0..DIV-1
    reg [2:0]    bitcnt;    // 已发数据位 0..7
    reg [7:0]    shifter;   // 发送移位寄存器
    reg          ready_r;

    assign ready = ready_r;

    always @(posedge clk) begin
        if (rst) begin
            st      <= S_IDLE;
            tx      <= 1'b1;
            ready_r <= 1'b1;
            cnt     <= {CW{1'b0}};
            bitcnt  <= 3'd0;
            shifter <= 8'h00;
        end else begin
            case (st)
                // ---------------- 空闲 ----------------
                S_IDLE: begin
                    tx      <= 1'b1;
                    ready_r <= 1'b1;
                    cnt     <= {CW{1'b0}};
                    if (valid) begin
                        shifter <= data;
                        ready_r <= 1'b0;
                        st      <= S_START;
                    end
                end

                // ---------------- 起始位（低）----------------
                S_START: begin
                    tx <= 1'b0;
                    if (cnt == DIV - 1) begin
                        cnt    <= {CW{1'b0}};
                        bitcnt <= 3'd0;
                        st     <= S_DATA;
                    end else begin
                        cnt <= cnt + 1'b1;
                    end
                end

                // ---------------- 8 个数据位（LSB 先）----------------
                S_DATA: begin
                    tx <= shifter[0];
                    if (cnt == DIV - 1) begin
                        cnt <= {CW{1'b0}};
                        if (bitcnt == 3'd7) begin
                            st <= S_STOP;
                        end else begin
                            bitcnt  <= bitcnt + 1'b1;
                            shifter <= {1'b0, shifter[7:1]};
                        end
                    end else begin
                        cnt <= cnt + 1'b1;
                    end
                end

                // ---------------- 停止位（高）----------------
                S_STOP: begin
                    tx <= 1'b1;
                    if (cnt == DIV - 1) begin
                        cnt <= {CW{1'b0}};
                        st  <= S_IDLE;
                    end else begin
                        cnt <= cnt + 1'b1;
                    end
                end

                default: st <= S_IDLE;
            endcase
        end
    end

endmodule
