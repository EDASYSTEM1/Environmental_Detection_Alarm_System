// ============================================================================
//  modules/m_alarm/sim/tb_alarm.v —— 报警判定单元仿真
//
//  覆盖 4 种判定：正常 / 注意 / 警告（超阈值）/ 严重（传感器故障），
//  外加蜂鸣器门控（SW[10] 使能、SW[11] 静音）和 LED 映射。
//  check() 消息用英文（中文压进 reg 向量会变乱码）。
// ============================================================================
`timescale 1ns / 1ps

module tb_alarm;

    reg clk = 1'b0;
    always #5 clk = ~clk;

    reg rst          = 1'b1;
    reg sample_tick  = 1'b0;

    reg signed [15:0] temp_x10      = 16'sd0;
    reg        [15:0] humi_x10      = 16'd0;
    reg        [15:0] lux           = 16'd0;
    reg        [7:0]  sensor_status = 8'b0000_0011;   // th_ok=1 ls_ok=1
    reg        [15:0] sw            = 16'h0000;
    reg        [4:0]  btn           = 5'b00000;

    wire [3:0]  alarm_level;
    wire [3:0]  alarm_src;
    wire [15:0] led;
    wire        aud_pwm;
    wire        aud_sd;

    alarm_ctrl dut (
        .clk           (clk),
        .rst           (rst),
        .sample_tick   (sample_tick),
        .temp_x10      (temp_x10),
        .humi_x10      (humi_x10),
        .lux           (lux),
        .sensor_status (sensor_status),
        .sw            (sw),
        .btn           (btn),
        .alarm_level   (alarm_level),
        .alarm_src     (alarm_src),
        .led           (led),
        .aud_pwm       (aud_pwm),
        .aud_sd        (aud_sd)
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

    // 打一个采样节拍，让报警模块更新一次判定
    task do_tick;
        begin
            @(negedge clk); sample_tick = 1'b1;
            @(negedge clk); sample_tick = 1'b0;
            @(negedge clk);
        end
    endtask

    initial begin
        $display("=====================================================");
        $display(" tb_alarm : 报警判定");
        $display("=====================================================");

        repeat (5) @(posedge clk);
        rst = 1'b0;
        repeat (5) @(posedge clk);
        check("reset -> level 0", alarm_level == 4'd0);

        // --- 1: 一切正常（25.0C / 50.0% / 500lux）---
        // 阈值：SW[3:0]=D → 温度上限 46.0C；SW[7:4]=F → 湿度上限 115%
        sw       = 16'h00FD;
        temp_x10 = 16'sd250;
        humi_x10 = 16'd500;
        lux      = 16'd500;
        do_tick;
        check("normal -> level 0",   alarm_level == 4'd0);
        check("normal -> src 0",     alarm_src == 4'b0000);

        // --- 2: 超温（上限 46C，实测 48C）---
        temp_x10 = 16'sd480;
        do_tick;
        check("over temp -> level 2",  alarm_level == 4'd2);
        check("over temp -> src bit0", alarm_src == 4'b0001);

        // --- 3: 接近阈值（44.5C，离上限 1.5C）---
        temp_x10 = 16'sd445;
        do_tick;
        check("near limit -> level 1", alarm_level == 4'd1);

        // --- 4: 传感器故障优先（th_ok=0）---
        temp_x10      = 16'sd250;
        sensor_status = 8'b0000_0010;      // th_ok=0, ls_ok=1
        do_tick;
        check("sensor fault -> level 3",  alarm_level == 4'd3);
        check("sensor fault -> src bit3", alarm_src == 4'b1000);

        // --- 5: 蜂鸣器门控 ---
        sensor_status = 8'b0000_0011;
        temp_x10      = 16'sd480;          // 回到超温（等级 2）
        sw            = 16'h04FD;          // SW[10]=1 允许蜂鸣
        do_tick;
        check("level2 + buzz on -> LED[8]=1", led[8] == 1'b1);

        sw = 16'h0CFD;                     // SW[11]=1 静音
        do_tick;
        check("muted -> LED[8]=0", led[8] == 1'b0);

        check("AUD_SD always 1", aud_sd == 1'b1);

        $display("=====================================================");
        if (errors == 0)
            $display("==== ALARM TEST PASSED ====");
        else
            $display("==== ALARM TEST FAILED : %0d error(s) ====", errors);
        $display("=====================================================");
        $finish;
    end

    initial begin
        #1_000_000;
        $display("==== ALARM TEST TIMEOUT ====");
        $finish;
    end

endmodule
