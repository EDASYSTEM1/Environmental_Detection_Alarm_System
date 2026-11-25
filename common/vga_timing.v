// ============================================================================
//  common/vga_timing.v —— VGA 640×480@60Hz 时序基座（不产生新时钟）
//
//  为什么不用 clk_wiz 出 25.175 MHz：
//    1) 全系统约定"只有一个时钟"，派生时钟会绕过时序分析；
//    2) 少一个 IP 核，组员拉代码不用再生成 .xci。
//  做法：仍然在 100 MHz 时钟域里跑，只是每 4 个时钟才推进一个像素
//        （pix_en 使能），等效像素率 25 MHz → 刷新率 25M/800/525 = 59.5 Hz，
//        在 VGA 标准的 60 Hz ±1 Hz 容差内，绝大多数显示器能锁。
//
//  用法（vga_disp 里）：
//      wire pix_en, video_on;  wire [9:0] x, y;
//      vga_timing u_timing (.clk(clk), .rst(rst), .pix_en(pix_en),
//                           .x(x), .y(y), .hs(vga_hs), .vs(vga_vs),
//                           .video_on(video_on));
//      always @(posedge clk) if (pix_en) begin
//          vga_r <= (x < 320) ? 4'hF : 4'h0;     // 按 x/y 上色即可
//      end
//
//  注意：像素数据比 x 计数晚 1 个像素（可以忽略；要精确对齐就在 pix_en 出现
//        的前一拍算颜色），不影响显示效果。
// ============================================================================
module vga_timing (
    input  wire       clk,          // 100 MHz
    input  wire       rst,
    output wire       pix_en,       // 25 MHz 像素使能（每 4 拍 1 拍）
    output wire [9:0] x,            // 当前像素列 0..799
    output wire [9:0] y,            // 当前行     0..524
    output wire       hs,           // 行同步（低有效）
    output wire       vs,           // 场同步（低有效）
    output wire       video_on      // 1 = 在 640×480 有效显示区内
);

    // ---- 640×480@60 标准参数 ------------------------------------------------
    localparam [9:0] H_VIS   = 10'd640,   // 可见列
                     H_FP    = 10'd16,    // 前肩
                     H_SYNC  = 10'd96,    // 行同步宽度
                     H_BP    = 10'd48,    // 后肩
                     H_TOTAL = 10'd800,   // 一行总像素

                     V_VIS   = 10'd480,   // 可见行
                     V_FP    = 10'd10,    // 前肩
                     V_SYNC  = 10'd2,     // 场同步宽度
                     V_BP    = 10'd33,    // 后肩
                     V_TOTAL = 10'd525;   // 一场总行数

    reg [1:0] pdiv;      // 0..3，每 4 拍推进一个像素
    reg [9:0] x_r;
    reg [9:0] y_r;

    always @(posedge clk) begin
        if (rst) begin
            pdiv <= 2'd0;
            x_r  <= 10'd0;
            y_r  <= 10'd0;
        end else begin
            pdiv <= pdiv + 2'd1;
            if (pdiv == 2'd3) begin
                if (x_r == H_TOTAL - 10'd1) begin
                    x_r <= 10'd0;
                    y_r <= (y_r == V_TOTAL - 10'd1) ? 10'd0 : (y_r + 10'd1);
                end else begin
                    x_r <= x_r + 10'd1;
                end
            end
        end
    end

    assign pix_en = (pdiv == 2'd3);
    assign x      = x_r;
    assign y      = y_r;

    // 标准 VGA 是负极性同步：同步期间为 0
    assign hs = ~((x_r >= H_VIS + H_FP) && (x_r < H_VIS + H_FP + H_SYNC));
    assign vs = ~((y_r >= V_VIS + V_FP) && (y_r < V_VIS + V_FP + V_SYNC));

    assign video_on = (x_r < H_VIS) && (y_r < V_VIS);

endmodule
