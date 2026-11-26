// ============================================================================
//  common/sensor_snapshot.v —— 传感器数据快照（显示/报警的共用数据源）
//
//  为什么要有它：
//    两个传感器各自在"采完那一刻"更新数值，而 OLED / VGA / 报警是异步在跑的。
//    如果直接让它们去读传感器的寄存器，就会出现"显示到一半数值变了"的撕裂。
//    这里把两路数据在 valid 那拍锁存住，下游一律读这个快照 → 数据永远稳定。
//
//  另外它还负责"数据新鲜度"：连续 STALE_TICKS 个采样周期没收到 valid，
//    就判为 stale（传感器掉线），报警模块据此报"传感器故障"。
// ============================================================================
module sensor_snapshot #(
    parameter integer STALE_TICKS = 3          // 连续几拍没数据就判掉线
) (
    input  wire               clk,
    input  wire               rst,
    input  wire               sample_tick,     // 1 Hz

    // ---- 来自 th_sensor（温湿度）----
    input  wire signed [15:0] th_temp_x10,
    input  wire        [15:0] th_humi_x10,
    input  wire        [7:0]  th_status,
    input  wire               th_valid,

    // ---- 来自 light_sensor（光照）----
    input  wire        [15:0] ls_lux,
    input  wire        [11:0] ls_adc_raw,
    input  wire        [7:0]  ls_status,
    input  wire               ls_valid,

    // ---- 对外快照 ----
    output reg  signed [15:0] temp_x10,
    output reg         [15:0] humi_x10,
    output reg         [15:0] lux,
    output reg         [11:0] adc_raw,
    output reg         [7:0]  raw_status,      // 原始状态字拼在一起，调试用
    output wire        [7:0]  status,          // 汇总状态，见 docs/接口协议.md 第三节
    output wire               data_ok
);

    reg       th_ok, ls_ok;
    reg       th_stale, ls_stale;
    reg [7:0] th_miss, ls_miss;

    always @(posedge clk) begin
        if (rst) begin
            temp_x10   <= 16'sd0;
            humi_x10   <= 16'd0;
            lux        <= 16'd0;
            adc_raw    <= 12'd0;
            raw_status <= 8'h0;
            th_ok      <= 1'b0;
            ls_ok      <= 1'b0;
            th_stale   <= 1'b1;      // 上电还没有数据，先当掉线
            ls_stale   <= 1'b1;
            th_miss    <= 8'd0;
            ls_miss    <= 8'd0;
        end else begin
            // ---------------- 温湿度通道 ----------------
            raw_status[7:4] <= th_status[3:0];
            th_ok <= (th_status[3:0] == 4'b0001);
            if (th_valid) begin
                temp_x10   <= th_temp_x10;
                humi_x10   <= th_humi_x10;
                th_miss    <= 8'd0;
            end else if (sample_tick) begin
                if (th_miss < STALE_TICKS)
                    th_miss <= th_miss + 8'd1;
            end

            // ---------------- 光照通道 ----------------
            if (ls_valid) begin
                lux        <= ls_lux;
                adc_raw    <= ls_adc_raw;
                raw_status[3:0] <= ls_status[3:0];
                // bit 0 records a successful frame; bits 3:1 report busy/errors.
                ls_ok      <= (ls_status[3:1] == 3'b000);
                ls_miss    <= 8'd0;
            end else if (sample_tick) begin
                if (ls_miss < STALE_TICKS)
                    ls_miss <= ls_miss + 8'd1;
            end

            // ---------------- 新鲜度 ----------------
            th_stale <= (th_miss >= STALE_TICKS);
            ls_stale <= (ls_miss >= STALE_TICKS);
        end
    end

    // 汇总状态：bit0 th_ok / bit1 ls_ok / bit2 th_stale / bit3 ls_stale
    assign status  = {4'b0000, ls_stale, th_stale, ls_ok, th_ok};
    assign data_ok = th_ok & ls_ok & ~th_stale & ~ls_stale;

endmodule
