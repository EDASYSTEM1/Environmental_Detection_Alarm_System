// OLED SPI 波形抓取：把上电等待/复位缩短，抓初始化前两个字节的 CS/SCLK/SDIN/DC
`timescale 1ns / 1ps

module tb_wave_oled;
    reg clk = 1'b0;
    always #5 clk = ~clk;

    reg        rst       = 1'b1;
    reg        frame_req = 1'b0;
    reg  [7:0] pix_byte  = 8'h5A;

    wire [1:0] page;
    wire [3:0] char_idx;
    wire [2:0] char_col;
    wire       oled_cs, oled_sdin, oled_sclk, oled_dc, oled_res;

    oled_spi #(
        .PWR_WAIT (20),
        .RES_WAIT (4),
        .SPI_HALF (3),
        .GAP_CYC  (2)
    ) dut (
        .clk       (clk),
        .rst       (rst),
        .frame_req (frame_req),
        .pix_byte  (pix_byte),
        .page      (page),
        .char_idx  (char_idx),
        .char_col  (char_col),
        .oled_cs   (oled_cs),
        .oled_sdin (oled_sdin),
        .oled_sclk (oled_sclk),
        .oled_dc   (oled_dc),
        .oled_res  (oled_res)
    );

    initial begin
        $dumpfile("wave_oled.vcd");
        $dumpvars(0, tb_wave_oled);
        rst = 1'b1;
        repeat (3) @(posedge clk);
        rst = 1'b0;
        repeat (150) @(posedge clk);   // 上电等待 + 复位 + 前两条初始化命令
        $finish;
    end
endmodule
