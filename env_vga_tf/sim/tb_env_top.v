`timescale 1ns / 1ps

module tb_env_top;

    // ---------------- 时钟：100 MHz（10 ns 周期）----------------
    reg clk = 1'b0;
    always #5 clk = ~clk;

    // ---------------- 激励 ----------------
    reg         arst_n = 1'b0;
    // 湿度上限拨到最大（SW[7:4]=F → 115 %RH），只让"超温"参与判定，
    // 否则默认 55 %RH 会一直超过 40 %RH 的默认上限，测不出单一路报警。
    reg  [15:0] sw     = 16'h00F0;
    reg  [4:0]  btn    = 5'b00000;

    // ---------------- 观测 ----------------
    wire [15:0] led;
    wire [7:0]  an, seg;
    wire        oled_cs, oled_sdin, oled_sclk, oled_dc, oled_res;
    tri1        hygro_scl, hygro_sda;
    reg         fail_humidity = 0;
    // Compress I2C delays to fit the accelerated 1000-cycle sampling period.
    defparam dut.u_th_sensor.QUARTER_CYCLES = 2,
             dut.u_th_sensor.POWERUP_QUARTERS = 40,
             dut.u_th_sensor.CONVERSION_QUARTERS = 8;
    hdc1080_model #(.BIT_NS(80), .POWER_NS(800), .CONVERSION_NS(160)) hygro (
        .scl(hygro_scl), .sda(hygro_sda),
        .temp_raw(16'h654c), .humi_raw(16'h8ccc),
        .nack_write_address(1'b0), .nack_humidity_read(fail_humidity)
    );
    wire        als_cs, als_sclk;
    // Mode 3 reply: ADC code 124 corresponds to 320 lx in the nominal table.
    localparam [15:0] ALS_REPLY = {3'b000, 8'd124, 4'b0000, 1'bz};
    reg         als_miso = 1'bz;
    integer     als_bit;
    always begin
        @(negedge als_cs);
        for (als_bit = 15; als_bit >= 0; als_bit = als_bit - 1) begin
            @(negedge als_sclk);
            als_miso <= #40 ALS_REPLY[als_bit];
        end
    end
    wire [3:0]  vga_r, vga_g, vga_b;
    wire        vga_hs, vga_vs;
    wire        buzz;
    wire        uart_txd;

    integer errors       = 0;
    integer buzz_toggles = 0;
    reg     buzz_q       = 1'b0;

    // 串口在上报时是一直在发的，不能断言"空闲为高"，改成断言"确实有翻转"
    integer uart_toggles = 0;
    reg     uart_q       = 1'b1;

    always @(posedge clk) begin
        buzz_q <= buzz;
        if (buzz != buzz_q) buzz_toggles = buzz_toggles + 1;
        uart_q <= uart_txd;
        if (uart_txd != uart_q) uart_toggles = uart_toggles + 1;
    end

    // ---------------- 待测设计 ----------------
    env_vga_tf_top #(.CLK_HZ(1000)) dut (
        .CLK100MHZ (clk),
        .CPU_RESETN(arst_n),
        .SW        (sw),
        .BTN       (btn),
        .LED       (led),
        .AN        (an),
        .SEG       (seg),
        .OLED_CS   (oled_cs),
        .OLED_SDIN (oled_sdin),
        .OLED_SCLK (oled_sclk),
        .OLED_DC   (oled_dc),
        .OLED_RES  (oled_res),
        .HYGRO_SCL (hygro_scl),
        .HYGRO_SDA (hygro_sda),
        .ALS_CS    (als_cs),
        .ALS_SCLK  (als_sclk),
        .ALS_MISO  (als_miso),
        .VGA_R     (vga_r),
        .VGA_G     (vga_g),
        .VGA_B     (vga_b),
        .VGA_HS    (vga_hs),
        .VGA_VS    (vga_vs),
        .BUZZ      (buzz),
        .SD_CD(1'b1), .SD_MISO(1'b1), .UART_TXD  (uart_txd)
    );

    // ---------------- 检查任务 ----------------
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

    // ---------------- 主流程 ----------------
    integer   i;
    reg [3:0] level_now;

    initial begin
        $display("=====================================================");
        $display(" sys_tb : 系统骨架联调仿真");
        $display("=====================================================");

        // 1) 复位
        #200;
        arst_n = 1'b1;
        repeat (10) @(posedge clk);
        check("rst released",            dut.rst == 1'b0);
        check("level 0 after reset",     dut.alarm_level == 4'd0);

        // 2) 等几次 1 Hz 节拍
        for (i = 0; i < 5; i = i + 1) begin
            @(posedge dut.tick_1hz);
            repeat (5) @(posedge clk);
        end

        // 3) 传感器数据是否进了快照
        check("temp snapshot 25.3C",     dut.temp_x10 == 16'sd253);
        check("humi snapshot 55.0%",     dut.humi_x10 == 16'd550);
        check("ALS snapshot code 124",   dut.adc_raw == 12'd124);
        check("lux snapshot 320lx",      dut.lux == 16'd320);
        check("sensor_status ok",        dut.sensor_status == 8'b0000_0011);
        check("data_ok high",            dut.data_ok == 1'b1);

        // 4) 报警判定：温度上限 20.0C，25.3C 已超 → 等级 2、来源 bit0
        level_now = dut.alarm_level;
        $display("  [info] alarm_level=%0d src=%b led=0x%04h", level_now, dut.alarm_src, led);
        check("over-temp -> level 2",    level_now == 4'd2);
        check("over-temp -> src temp",   dut.alarm_src == 4'b0001);
        check("LED[3:0] = level",        led[3:0] == 4'd2);
        check("LED[7:4] = src",          led[7:4] == 4'b0001);
        check("buzzer silent by default", buzz == 1'b0);
        check("uart reporting (line toggles)", uart_toggles > 0);

        // 5) 按键消抖：按住 BTNC
        btn[0] = 1'b1;
        repeat (30) @(posedge clk);      // 消抖 10 个时钟（CLK_HZ=1000）
        check("btn debounce out = 1",    dut.btn_db[0] == 1'b1);

        // 6) 打开蜂鸣器：SW[10]=1 且等级 2 → 允许响
        sw[10] = 1'b1;
        repeat (3) @(posedge dut.tick_1hz);
        repeat (20) @(posedge clk);
        check("buzzer enabled -> LED[8]=1", led[8] == 1'b1);
        check("buzzer really toggling",     buzz_toggles > 0);

        // 7) 抬高温度上限到 50.0C（SW[3:0]=15）→ 25.3C 不再报警
        sw[3:0] = 4'hF;
        repeat (3) @(posedge dut.tick_1hz);
        repeat (5) @(posedge clk);
        check("limit 50C -> no alarm",   dut.alarm_level == 4'd0);

        // A failed second conversion must reach the fault display without a valid pulse.
        fail_humidity = 1;
        wait (dut.th_status[1] === 1'b1);
        repeat (2) @(negedge clk);
        check("TH fault in snapshot",    dut.sensor_status[0] === 1'b0);
        check("TH fault holds last pair", dut.temp_x10 === 16'sd253 && dut.humi_x10 === 16'd550);
        repeat (4) @(posedge dut.tick_1hz);
        repeat (5) @(negedge clk);
        check("missing TH frames stale", dut.sensor_status[2] === 1'b1);
        fail_humidity = 0;
        @(posedge dut.th_valid);
        repeat (4) @(negedge clk);
        check("recovered TH snapshot",   dut.data_ok === 1'b1);

        // ---------------- 汇总 ----------------
        $display("=====================================================");
        if (errors == 0)
            $display("==== SYS TEST PASSED ====");
        else
            $display("==== SYS TEST FAILED : %0d error(s) ====", errors);
        $display("=====================================================");
        $finish;
    end

    // 超时保护：仿真不该跑过 5 ms（CLK_HZ=1000 时早就结束了）
    initial begin
        #5_000_000;
        $display("==== SYS TEST TIMEOUT ====");
        $finish;
    end

endmodule
