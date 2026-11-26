// Streaming 320 x 240 Windows BMP decoder. The SD filesystem supplies the
// complete file, including its header, gaps before the pixels, and any trailer.
// BMP rows are multiples of four bytes; 320 * 3 already meets that alignment.
module bmp_loader (
    input wire clk, rst,
    input wire bmp_start, bmp_valid,
    input wire [7:0] bmp_data,
    input wire bmp_end,
    output reg bg_we,
    output reg [16:0] bg_waddr,
    output reg [7:0] bg_wdata,
    output reg bg_ready, bmp_error
);
    localparam [31:0] PIXEL_BYTES = 32'd230400;
    reg active, header_ok, input_bad, image_complete;
    reg [31:0] position, file_size, pixel_offset, dib_size, width, height, compression;
    reg [15:0] planes, bpp;
    reg [8:0] column;
    reg [7:0] row;
    reg [16:0] row_address;
    reg [1:0] channel;
    reg [1:0] blue;
    reg [2:0] green;

    wire top_down = (height == 32'hffffff10);     // -240
    wire supported = !input_bad && dib_size >= 40 && pixel_offset >= 54
                  && dib_size <= pixel_offset - 14 && file_size >= pixel_offset
                  && file_size - pixel_offset >= PIXEL_BYTES
                  && width == 320 && (height == 240 || top_down)
                  && planes == 1 && bpp == 24 && compression == 0;
    wire pixel_byte = bmp_valid && header_ok && position >= pixel_offset && !image_complete;
    wire last_now = pixel_byte && row == 239 && column == 319 && channel == 2;
    // position counts previously accepted bytes, so EOF may coincide with
    // the final valid byte or follow it on a separate cycle.
    wire [32:0] bytes_at_end = {1'b0,position} + (bmp_valid ? 33'd1 : 33'd0);

    always @(posedge clk) begin
        bg_we <= 0;
        if (rst || bmp_start) begin
            active <= !rst && !bmp_end;
            header_ok <= 0;
            input_bad <= !rst && bmp_valid && bmp_data != "B";
            image_complete <= 0;
            position <= (!rst && bmp_valid) ? 1 : 0;
            file_size <= 0;
            pixel_offset <= 0;
            dib_size <= 0;
            width <= 0;
            height <= 0;
            planes <= 0;
            bpp <= 0;
            compression <= 0;
            column <= 0;
            row <= 0;
            row_address <= 0;
            channel <= 0;
            blue <= 0;
            green <= 0;
            bg_ready <= 0;
            bmp_error <= !rst && bmp_end;
            bg_waddr <= 0;
            bg_wdata <= 0;
        end else if (active) begin
            if (bmp_valid) begin
                if (position != 32'hffffffff)
                    position <= position + 1'b1;
                case (position)
                    0: if (bmp_data != "B") input_bad <= 1;
                    1: if (bmp_data != "M") input_bad <= 1;
                    2,3,4,5: file_size <= {bmp_data,file_size[31:8]};
                    10,11,12,13: pixel_offset <= {bmp_data,pixel_offset[31:8]};
                    14,15,16,17: dib_size <= {bmp_data,dib_size[31:8]};
                    18,19,20,21: width <= {bmp_data,width[31:8]};
                    22,23,24,25: height <= {bmp_data,height[31:8]};
                    26,27: planes <= {bmp_data,planes[15:8]};
                    28,29: bpp <= {bmp_data,bpp[15:8]};
                    30,31,32,33: compression <= {bmp_data,compression[31:8]};
                    53: begin
                        header_ok <= supported;
                        if (!supported) bmp_error <= 1;
                        row_address <= top_down ? 17'd0 : 17'd76480;
                    end
                endcase
                if (pixel_byte) begin
                    case (channel)
                        0: begin blue <= bmp_data[7:6]; channel <= 1; end
                        1: begin green <= bmp_data[7:5]; channel <= 2; end
                        2: begin
                            channel <= 0;
                            bg_we <= 1;
                            bg_waddr <= row_address + column;
                            bg_wdata <= {bmp_data[7:5],green,blue};
                            if (column == 319) begin
                                column <= 0;
                                row <= row + 1'b1;
                                row_address <= top_down ? row_address + 17'd320
                                                        : row_address - 17'd320;
                                if (row == 239) image_complete <= 1;
                            end else column <= column + 1'b1;
                        end
                    endcase
                end
            end
            if (bmp_end) begin
                active <= 0;
                bg_ready <= header_ok && (image_complete || last_now) && bytes_at_end >= file_size;
                bmp_error <= !(header_ok && (image_complete || last_now) && bytes_at_end >= file_size);
            end
        end
    end
endmodule
