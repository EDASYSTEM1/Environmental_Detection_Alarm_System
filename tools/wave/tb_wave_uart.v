// UART 波形抓取：发一个字节 0xA5，dump 出 tx 的位时序
// 分频比压到 10:1（DIV=10），所以 1 比特 = 10 个时钟 = 100 ns，方便看懂
`timescale 1ns / 1ps

module tb_wave_uart;
    reg clk = 1'b0;
    always #5 clk = ~clk;

    reg        rst   = 1'b1;
    reg  [7:0] data  = 8'h00;
    reg        valid = 1'b0;
    wire       ready;
    wire       tx;

    uart_tx #(.CLK_HZ(10), .BAUD(1)) dut (
        .clk   (clk),
        .rst   (rst),
        .data  (data),
        .valid (valid),
        .ready (ready),
        .tx    (tx)
    );

    initial begin
        $dumpfile("wave_uart.vcd");
        $dumpvars(0, tb_wave_uart);
        repeat (4) @(posedge clk);
        rst <= 1'b0;
        repeat (6) @(posedge clk);
        @(negedge clk); data <= 8'hA5; valid <= 1'b1;
        @(negedge clk); valid <= 1'b0;
        repeat (130) @(posedge clk);
        $finish;
    end
endmodule
