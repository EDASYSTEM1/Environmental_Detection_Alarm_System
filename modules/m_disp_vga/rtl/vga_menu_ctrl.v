// ============================================================================
//  modules/m_disp_vga/rtl/vga_menu_ctrl.v
//  VGA 控制面板菜单导航控制器（成员C）
//
//  功能：
//    1) 对板载 4 个方向键（btn[4:1] = {BTNR, BTNL, BTND, BTNU}，已消抖高有效）
//       做上升沿检测，防止按住不放连续跳页；
//    2) BTNL / BTNR 循环切换顶部 4 个菜单页签：
//         0: 01 OVERVIEW  （总览卡片 + 三路实时迷你曲线）
//         1: 02 CURVES    （专属监控曲线：三轨同屏 / 温 / 湿 / 光单路大图）
//         2: 03 ALARM/CFG （拨码阈值解析 + 4 路报警源矩阵 + 蜂鸣门控）
//         3: 04 DIAG      （Pmod 在线诊断 + 状态字/开关十六进制 + 缓冲信息）
//    3) BTNU / BTND 切换当前页面内高亮条目 / 曲线子视图；
//    4) 严格保留 btn[0] (BTNC) 不占用，留给组长 alarm_ctrl 报警确认/消音；
//    5) 兼容协议 v1.3 预留拨码 SW[14:13]：拨动 SW[14:13] 也可直接切页；
//       SW[15] 切换深色仪表主题(0) / 高对比浅色主题(1)。
// ============================================================================
`default_nettype none

module vga_menu_ctrl (
    input  wire        clk,
    input  wire        rst,
    input  wire [4:0]  btn,         // {BTNR, BTNL, BTND, BTNU, BTNC} 高有效
    input  wire [15:0] sw,
    output reg  [1:0]  tab_id,      // 0..3 当前菜单页签
    output reg  [1:0]  item_idx,    // 0..3 页内焦点 / 曲线子视图
    output wire        theme_light  // 0=深色仪表主题, 1=高对比浅色主题
);

    reg [4:0] btn_d;
    reg [1:0] sw_tab_d;
    reg       sw_sync_done;

    // Page 0 (OVERVIEW) 有 3 张卡片 (0..2)，其余 3 页各有 4 项 (0..3)
    wire [1:0] max_item = (tab_id == 2'd0) ? 2'd2 : 2'd3;

    always @(posedge clk) begin
        if (rst) begin
            btn_d        <= 5'b00000;
            sw_tab_d     <= 2'd0;
            sw_sync_done <= 1'b0;
            tab_id       <= 2'd0;
            item_idx     <= 2'd0;
        end else begin
            btn_d        <= btn;
            sw_tab_d     <= sw[14:13];
            sw_sync_done <= 1'b1;

            if (btn[3] && !btn_d[3]) begin
                tab_id   <= tab_id - 2'd1;
                item_idx <= 2'd0;
            end else if (btn[4] && !btn_d[4]) begin
                tab_id   <= tab_id + 2'd1;
                item_idx <= 2'd0;
            end else if (btn[1] && !btn_d[1]) begin
                item_idx <= (item_idx == 2'd0) ? max_item : (item_idx - 2'd1);
            end else if (btn[2] && !btn_d[2]) begin
                item_idx <= (item_idx == max_item) ? 2'd0 : (item_idx + 2'd1);
            end else if (sw_sync_done && (sw[14:13] != sw_tab_d)) begin
                // 拨动 SW[14:13] 兼容切页
                tab_id   <= sw[14:13];
                item_idx <= 2'd0;
            end
        end
    end

    assign theme_light = sw[15];

endmodule

`default_nettype wire
