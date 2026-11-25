// ============================================================================
//  modules/m_sensor_light/sim/tb_light_sensor.v —— 光照模块单元仿真（模板）
//
//  空壳阶段验证接口语义（valid / 数值更新 / CS、SCLK 空闲电平）。
//  成员B 实现真驱动后，建议在本文件里加一个 ADCS7476 行为模型：
//      reg [11:0] adc_model = 12'd2048;
//      在 CS 低期间每个 SCLK 上升沿把 adc_model 逐位送到 als_miso，
//  然后检查 adc_raw 是否等于 adc_model（这就是"抓字节"式验证）。
//
//  注意：check() 的消息用英文（中文压进 reg 向量会变乱码）。
// ============================================================================
`timescale 1ns / 1ps

module tb_light_sensor;

    reg clk = 1'b0;
    always #5 clk = ~clk;

    reg  rst         = 1'b1;
    reg  sample_tick = 1'b0;
    reg  als_miso    = 1'b0;

    wire        als_cs;
    wire        als_sclk;
    wire [11:0] adc_raw;
    wire [15:0] lux;
    wire [7:0]  status;
    wire        valid;

    light_sensor dut (
        .clk         (clk),
        .rst         (rst),
        .sample_tick (sample_tick),
        .als_cs      (als_cs),
        .als_sclk    (als_sclk),
        .als_miso    (als_miso),
        .adc_raw     (adc_raw),
        .lux         (lux),
        .status      (status),
        .valid       (valid)
    );

    integer errors    = 0;
    integer valid_cnt = 0;

    always @(posedge clk)
        if (valid) valid_cnt = valid_cnt + 1;

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

    initial begin
        $display("=====================================================");
        $display(" tb_light_sensor : 光照模块（空壳接口语义）");
        $display("=====================================================");

        repeat (5) @(posedge clk);
        rst = 1'b0;
        repeat (5) @(posedge clk);

        check("CS idle high",   als_cs == 1'b1);
        check("SCLK idle low",  als_sclk == 1'b0);

        for (i = 0; i < 3; i = i + 1) begin
            @(negedge clk); sample_tick = 1'b1;
            @(negedge clk); sample_tick = 1'b0;
            repeat (4) @(posedge clk);
        end

        check("lux = 320",      lux == 16'd320);
        check("adc_raw = 0",    adc_raw == 12'd0);
        check("status = 0",     status == 8'h00);
        check("valid pulse x3", valid_cnt == 3);

        $display("=====================================================");
        if (errors == 0)
            $display("==== LIGHT TEST PASSED ====");
        else
            $display("==== LIGHT TEST FAILED : %0d error(s) ====", errors);
        $display("=====================================================");
        $finish;
    end

    initial begin
        #1_000_000;
        $display("==== LIGHT TEST TIMEOUT ====");
        $finish;
    end

endmodule
