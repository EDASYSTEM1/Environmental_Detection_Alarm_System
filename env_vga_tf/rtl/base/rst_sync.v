// ============================================================================
//  common/rst_sync.v —— 复位同步器（异步置位 / 同步释放）
//
//  板载 CPU_RESETN 是"低有效 + 异步"的按键信号。直接拿它当复位用，松开的那一
//  刻各个触发器退出的时间点会不一致（亚稳态），表现为偶发的"上电计数乱跳"。
//
//  统一处理成：
//     按下（异步）  → 立刻复位，保证按下去系统一定停住
//     松开（同步）  → 经过 2 个时钟再释放，所有寄存器同一拍退出复位
//
//  全系统约定：内部只用 rst（**高有效**）。
// ============================================================================
module rst_sync (
    input  wire clk,
    input  wire arst_n,      // 板载按键，低有效、异步
    output wire rst          // 内部复位：高有效、同步释放
);

    // Configuration INIT asserts reset on power-up, even when the board's
    // reset button was never pressed.
    (* ASYNC_REG = "TRUE" *) reg [1:0] sync_q = 2'b11;

    always @(posedge clk or negedge arst_n) begin
        if (!arst_n)
            sync_q <= 2'b11;              // 异步置位：立刻进入复位
        else
            sync_q <= {sync_q[0], 1'b0};  // 两级同步：2 拍后释放
    end

    assign rst = sync_q[1];

endmodule
