// ============================================================================
//  modules/m_uart/sim/tb_report.v —— 上报帧内容仿真
//
//  不模拟串口线电平，而是"抓握手"：每当 uart 接受一个字节
//  （tx_valid && tx_ready），就把 tx_data 存进数组，最后和期望字符串逐字节比对。
//  这样测的是"格式化对不对"（小数点、补零、符号、状态字大小写）。
//
//  测两帧：
//    1) 25.3℃ / 55.0% / 320lux / 报警2 / 状态03
//    2) -5.2℃ / 1234%（会被钳到 99.9%）/ 4000lux / 报警0 / 状态00
// ============================================================================
`timescale 1ns / 1ps

module tb_report;

    reg clk = 1'b0;
    always #5 clk = ~clk;

    reg rst = 1'b1;

    reg signed [15:0] temp_x10      = 16'sd253;
    reg        [15:0] humi_x10      = 16'd550;
    reg        [15:0] lux           = 16'd320;
    reg        [3:0]  alarm_level   = 4'd2;
    reg        [7:0]  sensor_status = 8'h03;
    reg               tick          = 1'b0;

    wire txd;

    // 每比特 10 个时钟
    report_tx #(.CLK_HZ(10), .BAUD(1)) dut (
        .clk           (clk),
        .rst           (rst),
        .report_tick   (tick),
        .temp_x10      (temp_x10),
        .humi_x10      (humi_x10),
        .lux           (lux),
        .alarm_level   (alarm_level),
        .sensor_status (sensor_status),
        .uart_txd      (txd)
    );

    reg [7:0] cap [0:36];
    integer   ncap = 0;

    always @(posedge clk) begin
        if (!rst && dut.tx_valid && dut.tx_ready) begin
            cap[ncap] = dut.tx_data;
            ncap      = ncap + 1;
        end
    end

    reg [7:0] exp [0:36];

    integer errors = 0;
    integer i;

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

    task send_frame;
        begin
            @(negedge clk); tick = 1'b1;
            @(negedge clk); tick = 1'b0;
            wait (ncap >= 37);
            repeat (5) @(posedge clk);
        end
    endtask

    task cmp_frame;
        input [255:0] name;
        integer k;
        begin
            for (k = 0; k < 37; k = k + 1) begin
                if (cap[k] !== exp[k]) begin
                    $display("  [FAIL] %0s byte %0d: got 0x%02h want 0x%02h",
                             name, k, cap[k], exp[k]);
                    errors = errors + 1;
                end
            end
        end
    endtask

    task show_frame;
        integer k;
        begin
            $write("  [info] ");
            for (k = 0; k < 37; k = k + 1) $write("%c", cap[k]);
            $write("\n");
        end
    endtask

    initial begin
        $display("=====================================================");
        $display(" tb_report : UART 上报帧格式");
        $display("=====================================================");

        // ---------- 第一帧期望：25.3℃ / 55.0% / 0320 / 2 / 03 ----------
        exp[0]  = "$"; exp[1]  = "E"; exp[2]  = "N"; exp[3]  = "V"; exp[4]  = ",";
        exp[5]  = "T"; exp[6]  = "="; exp[7]  = "+"; exp[8]  = "2"; exp[9]  = "5";
        exp[10] = "."; exp[11] = "3";
        exp[12] = ","; exp[13] = "H"; exp[14] = "="; exp[15] = "5"; exp[16] = "5";
        exp[17] = "."; exp[18] = "0";
        exp[19] = ","; exp[20] = "L"; exp[21] = "="; exp[22] = "0"; exp[23] = "3";
        exp[24] = "2"; exp[25] = "0";
        exp[26] = ","; exp[27] = "A"; exp[28] = "="; exp[29] = "2";
        exp[30] = ","; exp[31] = "S"; exp[32] = "="; exp[33] = "0"; exp[34] = "3";
        exp[35] = 8'h0D; exp[36] = 8'h0A;

        repeat (5) @(posedge clk);
        rst = 1'b0;
        repeat (5) @(posedge clk);

        send_frame;
        check("frame1 length = 37", ncap >= 37);
        show_frame;
        cmp_frame("frame1 content");

        // ---------- 第二帧期望：-5.2℃ / 99.9%（钳位）/ 4000 / 0 / 00 ----------
        ncap = 0;
        temp_x10      = -16'sd52;
        humi_x10      = 16'd1234;          // 超过 99.9 → 应被钳到 999
        lux           = 16'd4000;
        alarm_level   = 4'd0;
        sensor_status = 8'h00;

        exp[0]  = "$"; exp[1]  = "E"; exp[2]  = "N"; exp[3]  = "V"; exp[4]  = ",";
        exp[5]  = "T"; exp[6]  = "="; exp[7]  = "-"; exp[8]  = "0"; exp[9]  = "5";
        exp[10] = "."; exp[11] = "2";
        exp[12] = ","; exp[13] = "H"; exp[14] = "="; exp[15] = "9"; exp[16] = "9";
        exp[17] = "."; exp[18] = "9";
        exp[19] = ","; exp[20] = "L"; exp[21] = "="; exp[22] = "4"; exp[23] = "0";
        exp[24] = "0"; exp[25] = "0";
        exp[26] = ","; exp[27] = "A"; exp[28] = "="; exp[29] = "0";
        exp[30] = ","; exp[31] = "S"; exp[32] = "="; exp[33] = "0"; exp[34] = "0";
        exp[35] = 8'h0D; exp[36] = 8'h0A;

        send_frame;
        check("frame2 length = 37", ncap >= 37);
        show_frame;
        cmp_frame("frame2 content");

        $display("=====================================================");
        if (errors == 0)
            $display("==== REPORT TEST PASSED ====");
        else
            $display("==== REPORT TEST FAILED : %0d error(s) ====", errors);
        $display("=====================================================");
        $finish;
    end

    initial begin
        #2_000_000;
        $display("==== REPORT TEST TIMEOUT ====");
        $finish;
    end

endmodule
