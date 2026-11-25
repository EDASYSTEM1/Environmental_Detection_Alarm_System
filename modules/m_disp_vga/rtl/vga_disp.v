// ============================================================================
//  modules/m_disp_vga/rtl/vga_disp.v
//  VGA 640×480 外接显示器仪表盘 —— 【空壳 Stub，成员C 负责实现】
//  负责人：成员C        接口协议：docs/接口协议.md 第 4.5 节（端口已冻结）
//
//  当前行为：显示器能锁上信号（hs/vs 由 vga_timing 正常产生），画面全黑。
//            没有画面不是 bug，是还没写渲染。
//
//  ---------------------------------------------------------------- 你要做的
//  1) 只用 pix_en 那一拍更新颜色（见下面注释里的彩条例子，复制出来改成文字）；
//  2) 文字用 common/font_rom.v 的 8×8 字模，放大 N 倍画（每字节 8 个像素纵向）；
//  3) 颜色 4 bit/通道：4'hF=最亮，4'h0=灭；报警时把背景刷成红/橙；
//  4) 画面内容与 OLED 完全一致（docs/接口协议.md 第六节），只是分辨率不同。
//
//  ⚠️ 三条禁令：
//    - 不许自己用分频器造 25 MHz 时钟（复用 vga_timing 的 pix_en）；
//    - 不许在 vga_disp 里例化第二个 vga_timing；
//    - RGB 必须**寄存器输出**（写在 always @(posedge clk) 里），不要组合输出，
//      否则会有毛刺导致屏幕出现竖条纹。
// ============================================================================
module vga_disp (
    input  wire               clk,            // 100 MHz
    input  wire               rst,
    input  wire signed [15:0] temp_x10,
    input  wire        [15:0] humi_x10,
    input  wire        [15:0] lux,
    input  wire        [3:0]  alarm_level,
    input  wire        [3:0]  alarm_src,
    input  wire        [7:0]  sensor_status, // 快照汇总（v1.3：用于显示 SENSOR FAIL）
    input  wire        [15:0] sw,
    output reg  [3:0]         vga_r,
    output reg  [3:0]         vga_g,
    output reg  [3:0]         vga_b,
    output wire               vga_hs,
    output wire               vga_vs
);

    // ---------------- 时序基座（不要动）----------------
    wire        pix_en;
    wire [9:0]  x;
    wire [9:0]  y;
    wire        video_on;

    vga_timing u_vga_timing (
        .clk      (clk),
        .rst      (rst),
        .pix_en   (pix_en),
        .x        (x),
        .y        (y),
        .hs       (vga_hs),
        .vs       (vga_vs),
        .video_on (video_on)
    );

    // ---------------- 空壳：黑屏 ----------------
    // 想看"信号通不通"，把下面这段换成注释里那段彩条，综合上板就能验证显示器。
    always @(posedge clk) begin
        if (rst) begin
            vga_r <= 4'h0;
            vga_g <= 4'h0;
            vga_b <= 4'h0;
        end else if (pix_en) begin
            vga_r <= 4'h0;
            vga_g <= 4'h0;
            vga_b <= 4'h0;
        end
    end

    // ---------------- 彩条示例（成员C 调试用，取消注释即可）----------------
    // always @(posedge clk) begin
    //     if (rst) begin
    //         vga_r <= 4'h0; vga_g <= 4'h0; vga_b <= 4'h0;
    //     end else if (pix_en) begin
    //         if (!video_on) begin
    //             vga_r <= 4'h0; vga_g <= 4'h0; vga_b <= 4'h0;   // 消隐区全黑
    //         end else if (x < 640/8) begin
    //             vga_r <= 4'hF; vga_g <= 4'hF; vga_b <= 4'hF;   // 白
    //         end else if (x < 640/4) begin
    //             vga_r <= 4'hF; vga_g <= 4'hF; vga_b <= 4'h0;   // 黄
    //         end else if (x < 640*3/8) begin
    //             vga_r <= 4'h0; vga_g <= 4'hF; vga_b <= 4'h0;   // 绿
    //         end else if (x < 640/2) begin
    //             vga_r <= 4'h0; vga_g <= 4'hF; vga_b <= 4'hF;   // 青
    //         end else if (x < 640*5/8) begin
    //             vga_r <= 4'h0; vga_g <= 4'h0; vga_b <= 4'hF;   // 蓝
    //         end else if (x < 640*3/4) begin
    //             vga_r <= 4'hF; vga_g <= 4'h0; vga_b <= 4'hF;   // 品红
    //         end else begin
    //             vga_r <= 4'hF; vga_g <= 4'h0; vga_b <= 4'h0;   // 红
    //         end
    //     end
    // end

endmodule
