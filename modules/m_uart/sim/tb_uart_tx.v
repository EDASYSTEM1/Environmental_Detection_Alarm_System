// ============================================================================
//  modules/m_uart/sim/tb_uart_tx.v —— UART 发送器位时序仿真
//
//  做法：把分频比压到 DIV=10（CLK_HZ=10, BAUD=1），
//        在"起始位下降沿 + 1.5 个比特"处开始，每 10 个时钟采一位，
//        正好落在每个比特的中点（真实串口接收机就是这么采的）。
//  check() 消息用英文（中文字符串压进 reg 向量会变乱码）。
// ============================================================================
`timescale 1ns / 1ps

module tb_uart_tx;

    reg clk = 1'b0;
    always #5 clk = ~clk;

    reg        rst   = 1'b1;
    reg  [7:0] data  = 8'h00;
    reg        valid = 1'b0;

    wire ready;
    wire tx;

    // 每比特 10 个时钟
    uart_tx #(.CLK_HZ(10), .BAUD(1)) dut (
        .clk   (clk),
        .rst   (rst),
        .data  (data),
        .valid (valid),
        .ready (ready),
        .tx    (tx)
    );

    integer errors = 0;

    task check;
        input [255:0] name;
        input         cond;
        begin
            if (!cond) begin
                $display("  [FAIL] %0s", name);
                errors = errors + 1;
            end else begin
                $display("  [ ok ] %0s", name);
            end
        end
    endtask

    reg [7:0] cap;
    integer   i;

    initial begin
        $display("=====================================================");
        $display(" tb_uart_tx : UART 8N1 位时序");
        $display("=====================================================");

        repeat (5) @(posedge clk);
        rst = 1'b0;
        repeat (5) @(posedge clk);

        check("idle level high",      tx    == 1'b1);
        check("ready high when idle", ready == 1'b1);

        // 发 0xA5 = 1010_0101（LSB 先发：1 0 1 0 0 1 0 1）
        @(negedge clk); valid = 1'b1; data = 8'hA5;
        @(negedge clk); valid = 1'b0;

        check("ready low after start", ready == 1'b0);

        @(negedge tx);                 // 起始位开始
        repeat (15) @(posedge clk);    // 到 bit0 中点（1.5 比特）
        for (i = 0; i < 8; i = i + 1) begin
            cap[i] = tx;
            repeat (10) @(posedge clk);
        end

        check("stop bit level high", tx == 1'b1);
        check("data byte = 0xA5",    cap == 8'hA5);

        // 等发完，ready 应恢复
        repeat (10) @(posedge clk);
        check("ready back high",     ready == 1'b1);
        check("tx back to idle",     tx == 1'b1);

        $display("=====================================================");
        if (errors == 0)
            $display("==== UART TEST PASSED ====");
        else
            $display("==== UART TEST FAILED : %0d error(s) ====", errors);
        $display("=====================================================");
        $finish;
    end

    initial begin
        #500_000;
        $display("==== UART TEST TIMEOUT ====");
        $finish;
    end

endmodule
