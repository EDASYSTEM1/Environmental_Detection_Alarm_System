// ============================================================================
//  modules/m_disp_oled/sim/tb_text_engine.v —— 文本缓冲内容仿真
//
//  不模拟 OLED 的 SPI 线，直接按 (page, idx) 把 64 个字符读出来，
//  和期望的 4 行文字逐字符比对——这样测的是"排版和数字格式对不对"。
//
//  测两种情况：
//    1) 25.3℃ / 55.0% / 320lux / 报警 2 / 传感器正常  → 显示 ALARM!
//    2) -5.2℃ / 99.9% / 4000lux / 报警 0 / 传感器故障 → 显示 SENSOR FAIL
// ============================================================================
`timescale 1ns / 1ps

module tb_text_engine;

    reg clk = 1'b0;
    always #5 clk = ~clk;

    reg rst = 1'b1;

    reg signed [15:0] temp_x10      = 16'sd253;
    reg        [15:0] humi_x10      = 16'd550;
    reg        [15:0] lux           = 16'd320;
    reg        [3:0]  alarm_level   = 4'd2;
    reg        [3:0]  alarm_src     = 4'b0001;
    reg        [7:0]  sensor_status = 8'b0000_0011;
    reg               refresh       = 1'b0;

    reg  [1:0] page = 2'd0;
    reg  [3:0] idx  = 4'd0;
    wire [7:0] ch;

    text_engine dut (
        .clk           (clk),
        .rst           (rst),
        .refresh_tick  (refresh),
        .temp_x10      (temp_x10),
        .humi_x10      (humi_x10),
        .lux           (lux),
        .alarm_level   (alarm_level),
        .alarm_src     (alarm_src),
        .sensor_status (sensor_status),
        .page          (page),
        .idx           (idx),
        .ch            (ch)
    );

    // 期望画面（4 行 x 16 字符 = 64 字符）
    reg [8*64-1:0] exp_str;
    reg [8*64-1:0] got_str;

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

    integer i;

    task do_refresh;
        begin
            @(negedge clk); refresh = 1'b1;
            @(negedge clk); refresh = 1'b0;
            // 等 3 个值都拆完 + 64 个字符填完（最多约 200 拍，给足 400 拍）
            repeat (400) @(posedge clk);
        end
    endtask

    task compare_screen;
        begin
            got_str = 64'b0;
            for (i = 0; i < 64; i = i + 1) begin
                @(negedge clk);
                page = i / 16;
                idx  = i % 16;
                #1;
                got_str = {got_str[8*64-9:0], ch};  // 左移 8 位再把新字符放到最低字节
            end
            if (got_str !== exp_str) begin
                $display("  [FAIL] screen content mismatch");
                $display("     want: %0s", exp_str);
                $display("     got : %0s", got_str);
                errors = errors + 1;
            end else begin
                $display("  [ ok ] screen: %0s", got_str);
            end
        end
    endtask

    initial begin
        $display("=====================================================");
        $display(" tb_text_engine : OLED 文本缓冲");
        $display("=====================================================");

        repeat (5) @(posedge clk);
        rst = 1'b0;
        repeat (5) @(posedge clk);

        // ---------- 情况 1：正常读数 + 报警 2 ----------
        temp_x10      = 16'sd253;
        humi_x10      = 16'd550;
        lux           = 16'd320;
        alarm_level   = 4'd2;
        sensor_status = 8'b0000_0011;

        exp_str = "ENV MONITOR     T:+25.3C H:55.0%L:0320lx ALM:2  ALARM!          ";
        do_refresh;
        compare_screen;

        // ---------- 情况 2：负温 + 传感器故障 ----------
        temp_x10      = -16'sd52;
        humi_x10      = 16'd999;
        lux           = 16'd4000;
        alarm_level   = 4'd0;
        sensor_status = 8'b0000_0000;      // th_ok=0 → 故障

        exp_str = "ENV MONITOR     T:-05.2C H:99.9%L:4000lx ALM:0  SENSOR FAIL     ";
        do_refresh;
        compare_screen;

        $display("=====================================================");
        if (errors == 0)
            $display("==== TEXT TEST PASSED ====");
        else
            $display("==== TEXT TEST FAILED : %0d error(s) ====", errors);
        $display("=====================================================");
        $finish;
    end

    initial begin
        #2_000_000;
        $display("==== TEXT TEST TIMEOUT ====");
        $finish;
    end

endmodule
