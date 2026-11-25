// ============================================================================
//  top/sys_tb.v —— 系统级联调仿真（自检，Icarus 可跑）
//
//  目的：在没人写真实逻辑的情况下，验证"骨架本身"是活的：
//    1. 复位能正常释放；
//    2. tick_gen 的 1 Hz 节拍真的在跑；
//    3. 传感器空壳的假数据能进快照；
//    4. 报警判定按预期给出等级（25.3 ℃ 超过 20 ℃ 上限 → 警告）；
//    5. 按键消抖能把按下的键传出来。
//
//  仿真技巧：sys_top 的 CLK_HZ 参数设成 1000，1 Hz 节拍变成 1000 个时钟一次，
//            仿真跑几微秒就能看到多次采样，不用等 1 秒。
//  check() 消息用英文（中文压进 reg 向量会变乱码）。
// ============================================================================
`timescale 1ns / 1ps

module sys_tb;

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
    wire        hygro_scl, hygro_sda;
    wire        als_cs, als_sclk;
    reg         als_miso = 1'b0;
    wire [3:0]  vga_r, vga_g, vga_b;
    wire        vga_hs, vga_vs;
    wire        buzz;

    integer errors       = 0;
    integer buzz_toggles = 0;
    reg     buzz_q       = 1'b0;

    // 监视蜂鸣器有没有在翻转（有翻转 = 真的在响）
    always @(posedge clk) begin
        buzz_q <= buzz;
        if (buzz != buzz_q) buzz_toggles = buzz_toggles + 1;
    end

    // ---------------- 待测设计 ----------------
    sys_top #(.CLK_HZ(1000)) dut (
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
        .BUZZ      (buzz)
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

        // 3) 传感器假数据是否进了快照
        check("temp snapshot 25.3C",     dut.temp_x10 == 16'sd253);
        check("humi snapshot 55.0%",     dut.humi_x10 == 16'd550);
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
