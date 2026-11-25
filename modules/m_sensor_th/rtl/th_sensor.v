// ============================================================================
//  modules/m_sensor_th/rtl/th_sensor.v
//  Pmod HYGRO 温湿度传感器驱动（I2C）—— 【空壳 Stub，成员B 负责实现】
//  负责人：成员B        接口协议：docs/接口协议.md 第 4.1 节（端口已冻结）
//
//  当前行为（让上板第一天就有画面）：
//    恒输出 25.3 ℃ / 55.0 %RH，status = 0（正常），每来一个 sample_tick 拉一拍 valid。
//    SCL 保持高、SDA 释放（高阻），不会干扰总线。
//
//  ---------------------------------------------------------------- 实现指引
//  硬件（已按 Digilent 官方手册核对）：
//    Pmod HYGRO 是 **6 针**模块，J1 引脚：1=NC 2=NC 3=SCL 4=SDA 5=GND 6=VCC
//    ⚠️ SCL/SDA 不在 1/2 脚！本工程插 JB 口：SCL=JB[3]=G16，SDA=JB[4]=H14
//    板载传感器：SHTC3（Sensirion），I2C 7 位地址 **0x70**，模块自带上拉
//
//  板载 SHTC3 标准流程：
//    1) 上电等 ≥ 100 ms；
//    2) 发测量命令：0x7CA2（T 先出）或 0x7866（RH 先出）；
//       命令后必须等测量完成：T-first 约 12.1 ms，RH-first 约 10.8 ms；
//    3) 读 6 字节：T_MSB, T_LSB, T_CRC, RH_MSB, RH_LSB, RH_CRC（每字节后要发 ACK）；
//    4) 换算（以 datasheet 为准）：
//         T(℃)  = -45 + 175 * T_raw / 65536
//         RH(%) = 100 * RH_raw / 65536
//       本模块输出定点：temp_x10 = T*10（有符号），humi_x10 = RH*10。
//    5) 校验不过/无应答/超时 → 置 status[1] 或 status[2]，数值保持上一次的值。
//
//  I2C 时序要求：SCL 100 kHz，由 100 MHz 分频得到（不要用分频器当时钟！）。
//  SDA 是**开漏双向**：写 0 时驱动低，写 1 时释放（1'bz），读时直接采样引脚。
// ============================================================================
module th_sensor (
    input  wire               clk,
    input  wire               rst,
    input  wire               sample_tick,     // 1 Hz 单周期脉冲
    output wire               scl,
    inout  wire               sda,
    output reg  signed [15:0] temp_x10,        // 0.1 ℃（有符号）
    output reg         [15:0] humi_x10,        // 0.1 %RH
    output reg         [7:0]  status,          // 0 = 正常
    output reg                valid            // 采完一帧的 1 拍脉冲
);

    // ---------------- 空壳占位（成员B 实现时整段替换）----------------
    localparam signed [15:0] STUB_TEMP_X10 = 16'sd253;   // 25.3 ℃
    localparam        [15:0] STUB_HUMI_X10 = 16'd550;    // 55.0 %RH

    assign scl = 1'b1;      // 总线空闲
    assign sda = 1'bz;      // 释放 SDA（模块自带上拉）

    always @(posedge clk) begin
        if (rst) begin
            temp_x10 <= STUB_TEMP_X10;
            humi_x10 <= STUB_HUMI_X10;
            status   <= 8'h01;   // 0x01 = 已拿到过有效数据、无错误
            valid    <= 1'b0;
        end else begin
            valid <= sample_tick;      // 先占位：采样节拍到就算"采完一帧"
            if (sample_tick) begin
                temp_x10 <= STUB_TEMP_X10;
                humi_x10 <= STUB_HUMI_X10;
                status   <= 8'h01;   // 0x01 = 已拿到过有效数据、无错误
            end
        end
    end
    // ---------------- 空壳结束 ----------------

endmodule
