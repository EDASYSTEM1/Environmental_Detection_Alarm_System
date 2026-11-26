module env_storage #(
    parameter integer CLK_HZ = 100_000_000
) (
    input wire clk, rst, sample_tick,
    input wire sd_cd_n, sd_miso,
    output wire sd_cs_n, sd_sck, sd_mosi, sd_reset,
    input wire signed [15:0] temp_x10,
    input wire [15:0] humi_x10, lux,
    input wire [11:0] adc_raw,
    input wire [7:0] sensor_status,
    input wire data_ok,
    input wire [3:0] alarm_level, alarm_src,
    output wire bg_we, bg_ready,
    output wire [16:0] bg_waddr,
    output wire [7:0] bg_wdata,
    output wire [6:0] status_led
);
    // J1's detect switch grounds CD when a card is present. Keep the slot powered.
    assign sd_reset = 1'b0;
    (* ASYNC_REG = "TRUE" *) reg [1:0] cd_sync;
    reg inserted;
    localparam integer FILTER_CYCLES = CLK_HZ/100 < 2 ? 2 : CLK_HZ/100;
    reg [$clog2(FILTER_CYCLES)-1:0] stable_count;
    always @(posedge clk) begin
        if (rst) cd_sync <= 2'b11;
        else cd_sync <= {cd_sync[0],sd_cd_n};
        if (rst || cd_sync[1]) begin
            inserted <= 0;
            stable_count <= 0;
        end else if (!inserted) begin
            if (stable_count == FILTER_CYCLES-1)
                inserted <= 1;
            else
                stable_count <= stable_count + 1'b1;
        end
    end
    wire media_rst = rst || !inserted;
    wire card_ready, init_error, cmd_valid, cmd_write, cmd_ready, blk_done, blk_error;
    wire [31:0] cmd_lba;
    wire [8:0] buf_addr;
    wire [7:0] buf_rdata, buf_wdata;
    wire buf_we;
    sd_spi_block u_sd (
        .clk(clk), .rst(media_rst), .sd_cs(sd_cs_n), .sd_sck(sd_sck), .sd_mosi(sd_mosi),
        .sd_miso(sd_miso), .card_ready(card_ready), .init_error(init_error),
        .cmd_valid(cmd_valid), .cmd_write(cmd_write), .cmd_lba(cmd_lba), .cmd_ready(cmd_ready),
        .blk_done(blk_done), .blk_error(blk_error), .buf_addr(buf_addr), .buf_rdata(buf_rdata),
        .buf_we(buf_we), .buf_wdata(buf_wdata)
    );
    wire bmp_start, bmp_end, bmp_valid, log_valid, log_pop, log_full, fs_error, bg_missing, fs_ready;
    wire [7:0] bmp_byte;
    wire [127:0] log_data;
    fat32_store u_files (
        .clk(clk), .rst(media_rst), .card_ready(card_ready),
        .cmd_valid(cmd_valid), .cmd_write(cmd_write), .cmd_lba(cmd_lba), .cmd_ready(cmd_ready),
        .blk_done(blk_done), .blk_error(blk_error), .buf_addr(buf_addr), .buf_rdata(buf_rdata),
        .buf_we(buf_we), .buf_wdata(buf_wdata),
        .bmp_start(bmp_start), .bmp_valid(bmp_valid), .bmp_data(bmp_byte), .bmp_end(bmp_end),
        .log_valid(log_valid), .log_data(log_data), .log_pop(log_pop),
        .fs_ready(fs_ready), .log_full(log_full), .fs_error(fs_error), .bg_missing(bg_missing)
    );
    wire bmp_error;
    bmp_loader u_image (
        .clk(clk), .rst(rst), .bmp_start(bmp_start), .bmp_valid(bmp_valid),
        .bmp_data(bmp_byte), .bmp_end(bmp_end), .bg_we(bg_we), .bg_waddr(bg_waddr),
        .bg_wdata(bg_wdata), .bg_ready(bg_ready), .bmp_error(bmp_error)
    );
    reg [31:0] uptime_s;
    always @(posedge clk) begin
        if (rst) uptime_s <= 0;
        else if (sample_tick) uptime_s <= uptime_s + 1'b1;
    end
    wire overflow;
    env_log_queue u_queue (
        .clk(clk), .rst(rst), .active(inserted && !log_full && !fs_error), .sample_tick(sample_tick),
        .uptime_s(uptime_s + 32'd1), .temp_x10(temp_x10), .humi_x10(humi_x10), .lux(lux),
        .adc_raw(adc_raw), .sensor_status(sensor_status), .data_ok(data_ok), .alarm_level(alarm_level),
        .alarm_src(alarm_src), .pop(log_pop), .valid(log_valid), .data(log_data), .overflow(overflow)
    );
    assign status_led = {init_error || fs_error || bmp_error || bg_missing, log_full, overflow,
                         fs_ready, bg_ready, card_ready, inserted};
endmodule
