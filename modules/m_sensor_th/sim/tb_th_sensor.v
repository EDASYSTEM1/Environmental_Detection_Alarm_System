// ============================================================================
//  modules/m_sensor_th/sim/tb_th_sensor.v —— 温湿度模块单元仿真（模板）
//
//  空壳阶段它验证的是"接口语义"：sample_tick 之后 valid 拉一拍、数值更新。
//  成员B 写完真驱动后，把下面的检查换成你自己的（I2C 时序、CRC、超时…），
//  这个文件的结构（时钟/复位/自检/汇总）可以直接沿用。
//
//  注意：check() 的消息用英文。Verilog 把字符串压进 reg 向量时是按字节的，
//        多字节中文会被打散成乱码，英文最省事。
// ============================================================================
`timescale 1ns / 1ps

module tb_th_sensor;

    reg clk = 1'b0;
    always #5 clk = ~clk;          // 100 MHz

    reg  rst         = 1'b1;
    reg  sample_tick = 1'b0;

    wire               scl;
    wire               sda;
    wire signed [15:0] temp_x10;
    wire        [15:0] humi_x10;
    wire        [7:0]  status;
    wire               valid;

    th_sensor dut (
        .clk         (clk),
        .rst         (rst),
        .sample_tick (sample_tick),
        .scl         (scl),
        .sda         (sda),
        .temp_x10    (temp_x10),
        .humi_x10    (humi_x10),
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
        $display(" tb_th_sensor : 温湿度模块（空壳接口语义）");
        $display("=====================================================");

        repeat (5) @(posedge clk);
        rst = 1'b0;
        repeat (5) @(posedge clk);

        check("SCL idle high",          scl == 1'b1);
        check("SDA released (z)",       sda === 1'bz);
        check("status = 0",             status == 8'h01);

        // 打 3 个采样节拍
        for (i = 0; i < 3; i = i + 1) begin
            @(negedge clk); sample_tick = 1'b1;
            @(negedge clk); sample_tick = 1'b0;
            repeat (4) @(posedge clk);
        end

        check("temp = 25.3C",           temp_x10 == 16'sd253);
        check("humi = 55.0%",           humi_x10 == 16'd550);
        check("status = 0",             status == 8'h01);
        check("valid pulse x3",         valid_cnt == 3);

        $display("=====================================================");
        if (errors == 0)
            $display("==== TH TEST PASSED ====");
        else
            $display("==== TH TEST FAILED : %0d error(s) ====", errors);
        $display("=====================================================");
        $finish;
    end

    initial begin
        #1_000_000;
        $display("==== TH TEST TIMEOUT ====");
        $finish;
    end

endmodule
