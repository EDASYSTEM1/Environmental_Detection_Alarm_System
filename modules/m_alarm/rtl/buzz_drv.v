// ============================================================================
//  modules/m_alarm/rtl/buzz_drv.v —— Pmod 蜂鸣器驱动（自制模块，插 JD 口）
//  负责人：组长
//
//  为什么单独一个模块：
//    1) 蜂鸣器分"有源/无源"两种，驱动方式完全不同，单独隔离最省事；
//    2) 以后想换音调、加"滴滴"节奏，只改这一个文件，不碰报警逻辑。
//
//  两种蜂鸣器：
//    无源（passive）：模块里只有振膜，必须给方波才响 → 本模块产生 TONE_HZ 方波
//    有源（active） ：模块里自带振荡电路，给高电平就响 → 本模块直接输出电平
//
//  选择方式：改参数 ACTIVE_BUZZER（0 = 无源，1 = 有源），编译前改一行即可，
//            或者最简单的办法：先上板试，响不了再换另一种。
//
//  引脚：JD（丝印 JXADC）第 1 脚 = A14；第 2 脚 A13 备着，暂不驱动
//        （自制模块如果信号不在 1 脚，改 xdc 里那一行 PACKAGE_PIN 即可）。
// ============================================================================
module buzz_drv #(
    parameter integer CLK_HZ        = 100_000_000,
    parameter integer TONE_HZ       = 2000,
    parameter integer ACTIVE_BUZZER = 0        // 0 = 无源蜂鸣器，1 = 有源蜂鸣器
) (
    input  wire clk,
    input  wire rst,
    input  wire req,        // 1 = 要求响（来自报警判定）
    output reg  buzz        // 到 Pmod JD 第 1 脚
);

    // 方波半周期 = CLK_HZ / (2 × TONE_HZ)；小仿真时钟下至少为 1
    localparam integer HALF = (CLK_HZ / (2 * TONE_HZ) < 1) ? 1 : (CLK_HZ / (2 * TONE_HZ));

    generate
        if (ACTIVE_BUZZER == 0) begin : g_passive
            // ---- 无源：产生 TONE_HZ 方波 ----
            reg [31:0] cnt;

            always @(posedge clk) begin
                if (rst || !req) begin
                    cnt  <= 32'd0;
                    buzz <= 1'b0;
                end else if (cnt == HALF - 1) begin
                    cnt  <= 32'd0;
                    buzz <= ~buzz;
                end else begin
                    cnt  <= cnt + 32'd1;
                end
            end
        end else begin : g_active
            // ---- 有源：直接给电平 ----
            always @(posedge clk) begin
                if (rst)
                    buzz <= 1'b0;
                else
                    buzz <= req;
            end
        end
    endgenerate

endmodule
