// ============================================================================
//  modules/m_alarm/rtl/alarm_ctrl.v —— 报警判定 + 人机交互（组长）
//  接口协议：docs/接口协议.md 第 4.3 节（端口已冻结）
//
//  本模块是"主程序"的核心：读快照数据 + 拨码开关，产出报警等级/来源，
//  并驱动 LED 和蜂鸣器（蜂鸣器驱动在子模块 buzz_drv 里，插 Pmod JD 口）。
//
//  判定规则（阈值全部由拨码开关实时设定，见 docs/接口协议.md 第五节）：
//    - 温度 > 温度上限            → 温度报警（alarm_src[0]）
//    - 湿度 > 湿度上限            → 湿度报警（alarm_src[1]）
//    - 光照 < 光照下限            → 太暗报警（alarm_src[2]）
//    - 传感器掉线/通信失败        → 故障报警（alarm_src[3]）
//  等级：
//    0 正常    三路都在阈值内
//    1 注意    接近阈值（温度差 2 ℃ 内 / 湿度差 5 % 内 / 光照差 20 lux 内）
//    2 警告    有任意一路越过阈值
//    3 严重    传感器故障（数据不可信，优先报故障）
//
//  ⚠️ 这是骨架期的简化实现：没有做"持续时间确认"（比如超阈值 3 秒才报警，
//     避免烧水壶蒸汽一瞬间误报），也没有做按键消音/确认。这些留给后续迭代。
// ============================================================================
module alarm_ctrl #(
    parameter integer CLK_HZ        = 100_000_000,
    parameter integer ACTIVE_BUZZER = 0        // 0 = 无源蜂鸣器，1 = 有源（见 buzz_drv.v）
) (
    input  wire               clk,
    input  wire               rst,
    input  wire               sample_tick,     // 1 Hz
    input  wire signed [15:0] temp_x10,
    input  wire        [15:0] humi_x10,
    input  wire        [15:0] lux,
    input  wire        [7:0]  sensor_status,   // 快照汇总状态
    input  wire        [15:0] sw,
    input  wire        [4:0]  btn,             // 已消抖（本版暂未使用）
    output reg  [3:0]  alarm_level,            // 0 正常 / 1 注意 / 2 警告 / 3 严重
    output reg  [3:0]  alarm_src,              // bit0 温度 / bit1 湿度 / bit2 光照 / bit3 故障
    output reg  [15:0] led,
    output wire               buzz             // 到 Pmod JD 第 1 脚（蜂鸣器）
);

    // ---------------- 阈值（拨码开关实时设定）----------------
    // 温度上限 = 20 ℃ + SW[3:0]×2 ℃   → 20 ~ 50 ℃
    wire        [15:0] temp_hi_u = 16'd200 + (sw[3:0] * 16'd20);
    wire signed [15:0] temp_hi   = $signed(temp_hi_u);
    // 湿度上限 = 40 % + SW[7:4]×5 %   → 40 ~ 115 %RH
    wire        [15:0] humi_hi   = 16'd400 + (sw[7:4] * 16'd50);
    // 光照下限 = 20 / 40 / 80 / 160 lux
    wire        [15:0] lux_lo    = (16'd20 << sw[9:8]);

    // ---------------- 三路越限判定 ----------------
    wire hot  = (temp_x10 > temp_hi);
    wire wet  = (humi_x10 > humi_hi);
    wire dark = (lux      < lux_lo);

    // ---------------- 传感器可用性 ----------------
    wire th_fault = (sensor_status[0] == 1'b0) || (sensor_status[2] == 1'b1);
    wire ls_fault = (sensor_status[1] == 1'b0) || (sensor_status[3] == 1'b1);
    wire fault    = th_fault || ls_fault;

    // ---------------- 注意区（离阈值还有一点点）----------------
    wire near_fire = (temp_x10 >  (temp_hi - 16'sd20))
                  || (humi_x10 >  (humi_hi - 16'd50))
                  || (lux      <  (lux_lo  + 16'd20));

    // ---------------- 报警等级 / 来源（1 Hz 更新）----------------
    always @(posedge clk) begin
        if (rst) begin
            alarm_level <= 4'd0;
            alarm_src   <= 4'd0;
        end else if (sample_tick) begin
            alarm_src <= {fault, dark, wet, hot};
            if (fault)
                alarm_level <= 4'd3;
            else if (hot || wet || dark)
                alarm_level <= 4'd2;
            else if (near_fire)
                alarm_level <= 4'd1;
            else
                alarm_level <= 4'd0;
        end
    end

    // ---------------- 蜂鸣器门控 ----------------
    // SW[10]=1 允许响；SW[11]=1 强制静音
    wire buzz_gate = (alarm_level >= 4'd2) && sw[10] && !sw[11];

    buzz_drv #(
        .CLK_HZ        (CLK_HZ),
        .TONE_HZ       (2000),
        .ACTIVE_BUZZER (ACTIVE_BUZZER)
    ) u_buzz_drv (
        .clk  (clk),
        .rst  (rst),
        .req  (buzz_gate),
        .buzz (buzz)
    );

    // ---------------- LED ----------------
    // {保留 7 位, 蜂鸣器在响, 报警来源 4 位, 报警等级 4 位}
    always @(*) begin
        led = {7'b0, buzz_gate, alarm_src, alarm_level};
    end

endmodule
