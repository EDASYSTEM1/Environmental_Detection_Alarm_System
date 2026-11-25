// ============================================================================
//  modules/m_disp_oled/rtl/oled_spi.v —— Pmod OLED（SSD1306，128×32）SPI 驱动
//  负责人：组长
//
//  时序与初始化序列完全沿用 v2（`v2_oled_time_display/src/oled_ctrl.v`）
//  那份已经在同一块板子上实测点亮过，这里只把"画面内容"从硬编码的 TIME
//  改成"从外部按页/字符取字"：
//
//      oled_spi 输出 page / char_idx / char_col
//          → text_engine 给出该字符的 ASCII
//          → font_rom 给出该列的 8 个像素
//          → 回到 oled_spi 当数据字节发出去
//
//  SSD1306 要点（写报告可讲）：
//    - 128×32 分 4 页，每页 8 行；一帧 = 4×128 = 512 字节；
//    - 每字节 = 某一列的 8 个像素，bit0 在最上面；
//    - D/C=0 发命令，D/C=1 发数据；SCLK 空闲低，上升沿采样，MSB 先出；
//    - 上电等 100 ms → RES 低 1 ms → 高 1 ms → 26 条初始化命令 → 每帧 6 条定位命令 + 512 字节。
// ============================================================================
module oled_spi #(
    parameter integer PWR_WAIT = 10_000_000,  // 上电等待：10M × 10ns = 100 ms
    parameter integer RES_WAIT = 100_000,     // RES 电平保持：1 ms
    parameter integer SPI_HALF = 25,          // SCLK 半周期：25 × 10ns = 250 ns → 2 MHz
    parameter integer GAP_CYC  = 20           // 字节间隔
) (
    input  wire       clk,
    input  wire       rst,
    input  wire       frame_req,     // 1 拍：请求刷新一帧
    input  wire [7:0] pix_byte,      // 当前列的 8 个像素（来自 font_rom）

    output wire [1:0] page,          // 当前页 0~3
    output wire [3:0] char_idx,      // 当前页内第几个字符 0~15
    output wire [2:0] char_col,      // 字符内第几列 0~7

    output reg        oled_cs,
    output reg        oled_sdin,
    output reg        oled_sclk,
    output reg        oled_dc,
    output reg        oled_res
);

    // ---------------- SSD1306 初始化命令（26 字节）----------------
    localparam integer INIT_LEN = 26;

    reg [7:0] init_rom [0:31];
    initial begin
        init_rom[ 0] = 8'hAE;                       // 关显示
        init_rom[ 1] = 8'hD5; init_rom[ 2] = 8'h80; // 时钟分频
        init_rom[ 3] = 8'hA8; init_rom[ 4] = 8'h1F; // 复用率 1/32
        init_rom[ 5] = 8'hD3; init_rom[ 6] = 8'h00; // 显示偏移 0
        init_rom[ 7] = 8'h40;                       // 起始行 0
        init_rom[ 8] = 8'h8D; init_rom[ 9] = 8'h14; // 打开电荷泵
        init_rom[10] = 8'h20; init_rom[11] = 8'h00; // 水平寻址
        init_rom[12] = 8'hA1;                       // 段重映射
        init_rom[13] = 8'hC8;                       // COM 扫描方向
        init_rom[14] = 8'hDA; init_rom[15] = 8'h02; // COM 引脚配置
        init_rom[16] = 8'h81; init_rom[17] = 8'h8F; // 对比度
        init_rom[18] = 8'hD9; init_rom[19] = 8'hF1; // 预充电
        init_rom[20] = 8'hDB; init_rom[21] = 8'h40; // VCOMH
        init_rom[22] = 8'hA4;                       // 跟随 RAM
        init_rom[23] = 8'hA6;                       // 正常显示
        init_rom[24] = 8'h2E;                       // 关滚动
        init_rom[25] = 8'hAF;                       // 开显示
    end

    // 每帧开头的 6 条命令：列 0~127、页 0~3
    reg [7:0] frame_cmd [0:5];
    initial begin
        frame_cmd[0] = 8'h21; frame_cmd[1] = 8'h00; frame_cmd[2] = 8'h7F;
        frame_cmd[3] = 8'h22; frame_cmd[4] = 8'h00; frame_cmd[5] = 8'h03;
    end

    localparam integer FRAME_LEN = 512;

    // ---------------- 当前字节的坐标 ----------------
    reg  [1:0] phase;
    reg  [4:0] init_idx;
    reg  [2:0] cmd_idx;
    reg  [8:0] data_idx;

    localparam [1:0] PH_INIT = 2'd0,
                     PH_CMD  = 2'd1,
                     PH_DATA = 2'd2;

    // data_idx → page / char_idx / char_col
    wire [8:0] didx = data_idx;
    assign page     = didx[8:7];        // 4 页，每页 128 字节
    wire   [6:0] col = didx[6:0];       // 页内列 0~127
    assign char_idx = col[6:3];         // 每字符 8 列 → 16 字符/行
    assign char_col = col[2:0];

    // ---------------- 当前该发的字节 ----------------
    reg [7:0] cur_byte;
    reg       cur_dc;
    always @(*) begin
        case (phase)
            PH_INIT: begin cur_byte = init_rom[init_idx]; cur_dc = 1'b0; end
            PH_CMD:  begin cur_byte = frame_cmd[cmd_idx]; cur_dc = 1'b0; end
            default: begin cur_byte = pix_byte;            cur_dc = 1'b1; end
        endcase
    end

    // ---------------- 主状态机 ----------------
    reg [3:0]  state;
    reg [24:0] big_cnt;
    reg [5:0]  tmr;
    reg [4:0]  bitcnt;
    reg [7:0]  shreg;

    localparam [3:0] ST_PWR   = 4'd0,
                     ST_RES_L = 4'd1,
                     ST_RES_H = 4'd2,
                     ST_BYTE  = 4'd3,
                     ST_SETUP = 4'd4,
                     ST_HIGH  = 4'd5,
                     ST_LOW   = 4'd6,
                     ST_GAP   = 4'd7,
                     ST_NEXT  = 4'd8,
                     ST_WAIT  = 4'd9;

    always @(posedge clk) begin
        if (rst) begin
            state     <= ST_PWR;
            phase     <= PH_INIT;
            init_idx  <= 5'd0;
            cmd_idx   <= 3'd0;
            data_idx  <= 9'd0;
            bitcnt    <= 5'd0;
            shreg     <= 8'h00;
            big_cnt   <= 25'd0;
            tmr       <= 6'd0;
            oled_cs   <= 1'b1;
            oled_sclk <= 1'b0;
            oled_sdin <= 1'b0;
            oled_dc   <= 1'b0;
            oled_res  <= 1'b1;
        end else begin
            case (state)
                ST_PWR: begin
                    oled_cs  <= 1'b1;
                    oled_res <= 1'b1;
                    if (big_cnt == PWR_WAIT - 1) begin
                        big_cnt <= 25'd0;
                        state   <= ST_RES_L;
                    end else begin
                        big_cnt <= big_cnt + 1'b1;
                    end
                end

                ST_RES_L: begin
                    oled_res <= 1'b0;
                    if (big_cnt == RES_WAIT - 1) begin
                        big_cnt <= 25'd0;
                        state   <= ST_RES_H;
                    end else begin
                        big_cnt <= big_cnt + 1'b1;
                    end
                end

                ST_RES_H: begin
                    oled_res <= 1'b1;
                    if (big_cnt == RES_WAIT - 1) begin
                        big_cnt  <= 25'd0;
                        phase    <= PH_INIT;
                        init_idx <= 5'd0;
                        state    <= ST_BYTE;
                    end else begin
                        big_cnt <= big_cnt + 1'b1;
                    end
                end

                ST_BYTE: begin
                    oled_cs   <= 1'b0;
                    oled_dc   <= cur_dc;
                    oled_sclk <= 1'b0;
                    oled_sdin <= cur_byte[7];
                    shreg     <= cur_byte;
                    bitcnt    <= 5'd7;
                    tmr       <= 6'd0;
                    state     <= ST_SETUP;
                end

                ST_SETUP: begin
                    oled_sclk <= 1'b0;
                    if (tmr == SPI_HALF - 1) begin
                        tmr   <= 6'd0;
                        state <= ST_HIGH;
                    end else begin
                        tmr <= tmr + 1'b1;
                    end
                end

                ST_HIGH: begin
                    oled_sclk <= 1'b1;
                    if (tmr == SPI_HALF - 1) begin
                        tmr       <= 6'd0;
                        oled_sclk <= 1'b0;
                        state     <= ST_LOW;
                    end else begin
                        tmr <= tmr + 1'b1;
                    end
                end

                ST_LOW: begin
                    oled_sclk <= 1'b0;
                    if (bitcnt == 5'd0) begin
                        state <= ST_GAP;
                        tmr   <= 6'd0;
                    end else begin
                        bitcnt    <= bitcnt - 1'b1;
                        shreg     <= {shreg[6:0], 1'b0};
                        oled_sdin <= shreg[6];
                        tmr       <= 6'd0;
                        state     <= ST_SETUP;
                    end
                end

                ST_GAP: begin
                    oled_sclk <= 1'b0;
                    if (tmr == GAP_CYC - 1) begin
                        tmr   <= 6'd0;
                        state <= ST_NEXT;
                    end else begin
                        tmr <= tmr + 1'b1;
                    end
                end

                ST_NEXT: begin
                    if (phase == PH_INIT) begin
                        if (init_idx == INIT_LEN - 1) begin
                            phase   <= PH_CMD;
                            cmd_idx <= 3'd0;
                            state   <= ST_BYTE;
                        end else begin
                            init_idx <= init_idx + 1'b1;
                            state    <= ST_BYTE;
                        end
                    end else if (phase == PH_CMD) begin
                        if (cmd_idx == 3'd5) begin
                            phase    <= PH_DATA;
                            data_idx <= 9'd0;
                            state    <= ST_BYTE;
                        end else begin
                            cmd_idx <= cmd_idx + 1'b1;
                            state   <= ST_BYTE;
                        end
                    end else begin
                        if (data_idx == FRAME_LEN - 1) begin
                            phase   <= PH_CMD;
                            cmd_idx <= 3'd0;
                            oled_cs <= 1'b1;
                            state   <= ST_WAIT;
                        end else begin
                            data_idx <= data_idx + 1'b1;
                            state    <= ST_BYTE;
                        end
                    end
                end

                ST_WAIT: begin
                    oled_cs   <= 1'b1;
                    oled_sclk <= 1'b0;
                    if (frame_req) begin
                        phase    <= PH_CMD;
                        cmd_idx  <= 3'd0;
                        data_idx <= 9'd0;
                        state    <= ST_BYTE;
                    end
                end

                default: state <= ST_PWR;
            endcase
        end
    end

endmodule
