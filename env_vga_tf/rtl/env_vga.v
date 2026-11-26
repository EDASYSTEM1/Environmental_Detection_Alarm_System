// 640 x 480, RGB444 video. Each BRAM pixel covers a 2 x 2 screen block.
// Existing logic and the two BRAM ports share the board's 100 MHz clock.
module env_vga (
    input wire clk, rst,
    input wire bg_we,
    input wire [16:0] bg_waddr,
    input wire [7:0] bg_wdata,
    input wire bg_ready,
    input wire signed [15:0] temp_x10,
    input wire [15:0] humi_x10, lux,
    input wire [7:0] sensor_status,
    input wire [3:0] alarm_level,
    output reg [3:0] vga_r, vga_g, vga_b,
    output reg vga_hs, vga_vs
);
    wire [9:0] x, y;
    wire pix_en, visible, hs, vs;
    vga_timing timing (.clk(clk), .rst(rst), .pix_en(pix_en), .x(x), .y(y),
                       .hs(hs), .vs(vs), .video_on(visible));

    // No reset on the inferred RAM. The fallback picture masks unfilled RAM.
    (* ram_style = "block" *) reg [7:0] background [0:76799];
    reg [7:0] background_q;
    wire [16:0] row320 = {1'b0,y[8:1],8'b0} + {3'b0,y[8:1],6'b0};
    wire [16:0] read_address = row320 + x[9:1];
    always @(posedge clk) begin
        if (bg_we) background[bg_waddr] <= bg_wdata;
        if (visible) background_q <= background[read_address];
    end

    // Capture all three inputs during vertical blank, then convert them in
    // 48 clocks with one shared shift/add-3 binary-to-decimal unit.
    reg active_bg, th_ok, light_ok, negative;
    reg [3:0] level;
    reg [15:0] humidity_hold, lux_hold, binary_shift;
    reg [19:0] decimal_shift, temp_bcd, humi_bcd, lux_bcd;
    reg [3:0] step;
    reg [1:0] field;
    reg converting;
    function [19:0] add_threes;
        input [19:0] n;
        integer d;
        begin
            add_threes = n;
            for (d=0; d<5; d=d+1)
                if (n[4*d+:4] >= 5) add_threes[4*d+:4] = n[4*d+:4] + 4'd3;
        end
    endfunction
    wire [19:0] adjusted = add_threes(decimal_shift);
    wire [19:0] next_digits = {adjusted[18:0],binary_shift[15]};
    always @(posedge clk) begin
        if (rst) begin
            active_bg <= 0; th_ok <= 0; light_ok <= 0; negative <= 0; level <= 0;
            converting <= 0; field <= 0; step <= 0;
            humidity_hold <= 0; lux_hold <= 0; binary_shift <= 0;
            decimal_shift <= 0; temp_bcd <= 0; humi_bcd <= 0; lux_bcd <= 0;
        end else if (pix_en && x==0 && y==480) begin
            active_bg <= bg_ready;
            th_ok <= sensor_status[0] && !sensor_status[2];
            light_ok <= sensor_status[1] && !sensor_status[3];
            level <= alarm_level;
            negative <= temp_x10[15];
            binary_shift <= temp_x10[15] ? (~temp_x10 + 16'd1) : temp_x10;
            humidity_hold <= humi_x10; lux_hold <= lux;
            decimal_shift <= 0; field <= 0; step <= 0; converting <= 1;
        end else if (converting) begin
            if (step == 15) begin
                case (field)
                    0: begin temp_bcd <= next_digits; binary_shift <= humidity_hold; end
                    1: begin humi_bcd <= next_digits; binary_shift <= lux_hold; end
                    2: begin lux_bcd <= next_digits; converting <= 0; end
                endcase
                field <= field + 1'b1; decimal_shift <= 0; step <= 0;
            end else begin
                binary_shift <= {binary_shift[14:0],1'b0};
                decimal_shift <= next_digits;
                step <= step + 1'b1;
            end
        end
    end

    // Character positions left to right; signed fixed-point values have one
    // fractional digit. Handle the entire 16-bit inputs, including -3276.8.
    function [79:0] fixed_line;
        input [19:0] digits;
        input minus, fresh;
        input [7:0] units;
        reg [79:0] line;
        integer i, first;
        begin
            line = "          ";
            first = 5;
            for (i=0; i<4; i=i+1) begin
                if ((i==3) || (digits >> (4*(4-i))) != 0) begin
                    line[(7-i)*8+:8] = {4'h3,digits[(4-i)*4+:4]};
                    if (2+i < first) first = 2+i;
                end
            end
            if (minus) line[(10-first)*8+:8] = "-";
            line[31:24] = "."; line[23:16] = {4'h3,digits[3:0]};
            if (!fresh) line = "    --.-  ";
            line[7:0] = units;
            fixed_line = line;
        end
    endfunction
    function [79:0] light_line;
        input [19:0] digits;
        input fresh;
        reg [79:0] line;
        integer i;
        begin
            line = "        lx";
            for (i=0; i<5; i=i+1)
                if (i==4 || (digits >> (4*(4-i))) != 0)
                    line[(7-i)*8+:8] = {4'h3,digits[(4-i)*4+:4]};
            if (!fresh) line = "     -- lx";
            light_line = line;
        end
    endfunction
    reg [79:0] temp_text,humi_text,light_text;
    reg format_pending;
    always @(posedge clk) begin
        if (rst) begin
            temp_text <= "    --.- C";
            humi_text <= "    --.- %";
            light_text <= "     -- lx";
            format_pending <= 0;
        end else begin
            format_pending <= converting && field==2 && step==15;
            if (format_pending) begin
                temp_text <= fixed_line(temp_bcd,negative,th_ok,"C");
                humi_text <= fixed_line(humi_bcd,1'b0,th_ok,"%");
                light_text <= light_line(lux_bcd,light_ok);
            end
        end
    end

    // Each data cell is 24 x 32 (8 columns * 3, 8 rows * 4). Horizontal
    // counters avoid dividing a pixel coordinate by three in the video path.
    reg [3:0] cell_no;
    reg [2:0] cell_col;
    reg [1:0] repeat_col;
    always @(posedge clk) begin
        if (rst || (pix_en && x==63)) begin
            cell_no <= 0; cell_col <= 0; repeat_col <= 0;
        end else if (pix_en && x>=64 && x<304) begin
            if (repeat_col==2) begin
                repeat_col <= 0; cell_col <= cell_col + 1'b1;
                if (cell_col==7) cell_no <= cell_no + 1'b1;
            end else repeat_col <= repeat_col + 1'b1;
        end
    end
    wire t_row = y>=112 && y<144;
    wire h_row = y>=224 && y<256;
    wire l_row = y>=336 && y<368;
    wire number_area = x>=64 && x<304;
    wire show_bg = active_bg && bg_ready;
    wire fallback_label = !show_bg && x>=32 && x<48;
    wire [79:0] line_text = t_row ? temp_text : h_row ? humi_text : light_text;
    wire [4:0] local_y = y[4:0] - (h_row ? 5'd0 : 5'd16);
    reg [7:0] character_q;
    reg [2:0] font_col_q, font_row_q;
    reg text_hit_q, glyph_on;
    wire [7:0] font_bits;
    font_rom font (.ch(character_q),.col(font_col_q),.bits(font_bits));
    always @(posedge clk) begin
        character_q <= fallback_label ? (t_row ? "T" : h_row ? "H" : "L") :
                                        line_text[(9-cell_no)*8+:8];
        font_col_q <= fallback_label ? x[3:1] : cell_col;
        font_row_q <= local_y[4:2];
        text_hit_q <= (t_row || h_row || l_row) && (number_area || fallback_label);
        glyph_on <= text_hit_q && font_bits[font_row_q];
    end
    // Replicate MSBs when widening 3:3:2 color into the board's 4:4:4 DAC.
    wire [11:0] image_rgb = {background_q[7:5],background_q[7],
                             background_q[4:2],background_q[4],
                             background_q[1:0],background_q[1:0]};
    wire panel = x>=16 && x<624 && ((y>=96 && y<160) ||
                 (y>=208 && y<272) || (y>=320 && y<384));
    wire [11:0] base = show_bg ? image_rgb : (panel ? 12'h235 : 12'h123);
    wire bright = base[7] && (base[11] || base[3]);
    wire [11:0] ink = (level>=2) ? (bright ? 12'h700 : 12'hfc4)
                                 : (bright ? 12'h112 : 12'hfff);
    // x,y are stable for four clocks. At pix_en, background_q and glyph_on
    // both correspond to these coordinates. Register sync with the same pixel.
    always @(posedge clk) begin
        if (rst) begin
            {vga_r,vga_g,vga_b} <= 0; vga_hs <= 1; vga_vs <= 1;
        end else if (pix_en) begin
            {vga_r,vga_g,vga_b} <= !visible ? 12'h000 : glyph_on ? ink : base;
            vga_hs <= hs; vga_vs <= vs;
        end
    end
endmodule
