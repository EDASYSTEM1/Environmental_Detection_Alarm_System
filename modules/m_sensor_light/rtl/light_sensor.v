// ============================================================================
//  modules/m_sensor_light/rtl/light_sensor.v
//  Pmod ALS 光照传感器驱动（SPI + 12 位 ADC）—— 【空壳 Stub，成员B 负责实现】
//  负责人：成员B        接口协议：docs/接口协议.md 第 4.2 节（端口已冻结）
//
//  当前行为：恒输出 320 lux / adc_raw = 0，status = 0，sample_tick 后拉一拍 valid。
//            CS 保持高、SCLK 低，不会误触发 ADC。
//
//  ---------------------------------------------------------------- 实现指引
//  硬件（已按 Digilent 官方手册核对）：
//    Pmod ALS 是 **6 针**模块，引脚：1=~CS 2=NC 3=MISO 4=SCLK 5=GND 6=VCC
//    本工程插 JC 口：CS=JC[1]=K1，MISO=JC[3]=J2，SCLK=JC[4]=G6
//    板载 ADC = **ADC081S021（8 位，200 kSPS，不是 12 位）**，光敏管是 TEMT6000X01
//
//  SPI 时序（ADC081S021）：
//    1) CS 拉低；
//    2) 给 16 个 SCLK（上限 4 MHz，建议 1 MHz）：8 位结果 MSB 先出，之后补 0；
//       数据在 SCLK 下降沿移出，FPGA 在**上升沿**采样最稳；
//    3) CS 拉高结束一次转换。
//    所以 adc_raw 只有低 8 位有意义，高 4 位填 0（端口保持 12 位，方便以后换模块）。
//
//  从 adc_raw 换算 lux：ALS 是"光敏管 + 固定电阻"分压进 ADC，**不是线性**，
//    没有唯一解析式。做法：实测标定一张表（adc → lux），用 case 或 ROM 查表，
//    并在本模块文件头写清楚标定环境和拟合公式（报告里要画曲线）。
// ============================================================================
module light_sensor (
    input  wire        clk,
    input  wire        rst,
    input  wire        sample_tick,
    output wire        als_cs,        // 低有效片选
    output wire        als_sclk,      // SPI 时钟
    input  wire        als_miso,      // ADC 数据输出
    output reg  [11:0] adc_raw,
    output reg  [15:0] lux,
    output reg  [7:0]  status,
    output reg         valid
);

    // ---------------- 空壳占位（成员B 实现时整段替换）----------------
    localparam [15:0] STUB_LUX     = 16'd320;
    localparam [11:0] STUB_ADC_RAW = 12'd0;

    assign als_cs   = 1'b1;
    assign als_sclk = 1'b0;

    always @(posedge clk) begin
        if (rst) begin
            adc_raw <= STUB_ADC_RAW;
            lux     <= STUB_LUX;
            status  <= 8'h00;
            valid   <= 1'b0;
        end else begin
            valid <= sample_tick;
            if (sample_tick) begin
                adc_raw <= STUB_ADC_RAW;
                lux     <= STUB_LUX;
                status  <= 8'h00;
            end
        end
    end
    // ---------------- 空壳结束 ----------------

endmodule
