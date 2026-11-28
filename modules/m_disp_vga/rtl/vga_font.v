// ============================================================================
//  modules/m_disp_vga/rtl/vga_font.v
//  VGA 扩展 8x8 ASCII 点阵字库（行主序，成员C 独立维护，不触碰 common/）
//
//  说明：common/font_rom.v 仅含 33 个字符（面向 OLED 4 行精简文本），
//        本模块补齐控制面板菜单栏所需的全部大写字母、数字、标点及单位小写。
//  布局：5x7 点阵居中置于 8x8 格内（col 1..5 有效，row 0..6 有效），
//        输出 row_bits[7:0]，其中 bit7 对应最左列 col=0，bit0 对应 col=7。
// ============================================================================
`default_nettype none

module vga_font (
    input  wire [7:0] ch,        // ASCII 字符编码
    input  wire [2:0] row,       // 字内行号 0..7（0 为顶部）
    output reg  [7:0] row_bits   // 该行 8 像素（bit7=左 col0 .. bit0=右 col7）
);

    reg [55:0] glyph_rows; // 7 行 x 8 bit（row 0 在最高字节 [55:48]）

    always @(*) begin
        case (ch)
            8'h20: glyph_rows = 56'h00000000000000; // ' '
            8'h21: glyph_rows = 56'h10101010100010; // '!'
            8'h25: glyph_rows = 56'h646810202C4C00; // '%'
            8'h28: glyph_rows = 56'h08102020201008; // '('
            8'h29: glyph_rows = 56'h20100808081020; // ')'
            8'h2B: glyph_rows = 56'h0010107C101000; // '+'
            8'h2C: glyph_rows = 56'h00000000101020; // ','
            8'h2D: glyph_rows = 56'h0000007C000000; // '-'
            8'h2E: glyph_rows = 56'h00000000003030; // '.'
            8'h2F: glyph_rows = 56'h04080810202040; // '/'
            8'h30: glyph_rows = 56'h38444C54644438; // '0'
            8'h31: glyph_rows = 56'h10301010101038; // '1'
            8'h32: glyph_rows = 56'h3844041820407C; // '2'
            8'h33: glyph_rows = 56'h38440418044438; // '3'
            8'h34: glyph_rows = 56'h081828487C0808; // '4'
            8'h35: glyph_rows = 56'h7C407804044438; // '5'
            8'h36: glyph_rows = 56'h38407844444438; // '6'
            8'h37: glyph_rows = 56'h7C040810202020; // '7'
            8'h38: glyph_rows = 56'h38444438444438; // '8'
            8'h39: glyph_rows = 56'h3844443C040838; // '9'
            8'h3A: glyph_rows = 56'h00101000101000; // ':'
            8'h3C: glyph_rows = 56'h08102040201008; // '<'
            8'h3D: glyph_rows = 56'h00007C007C0000; // '='
            8'h3E: glyph_rows = 56'h20100804081020; // '>'
            8'h40: glyph_rows = 56'h38445854584038; // '@'
            8'h41: glyph_rows = 56'h3844447C444444; // 'A'
            8'h42: glyph_rows = 56'h78444478444478; // 'B'
            8'h43: glyph_rows = 56'h38444040404438; // 'C'
            8'h44: glyph_rows = 56'h78444444444478; // 'D'
            8'h45: glyph_rows = 56'h7C40407840407C; // 'E'
            8'h46: glyph_rows = 56'h7C404078404040; // 'F'
            8'h47: glyph_rows = 56'h3844405C444438; // 'G'
            8'h48: glyph_rows = 56'h4444447C444444; // 'H'
            8'h49: glyph_rows = 56'h38101010101038; // 'I'
            8'h4A: glyph_rows = 56'h1C080808084830; // 'J'
            8'h4B: glyph_rows = 56'h44485060504844; // 'K'
            8'h4C: glyph_rows = 56'h4040404040407C; // 'L'
            8'h4D: glyph_rows = 56'h446C5454444444; // 'M'
            8'h4E: glyph_rows = 56'h4464544C444444; // 'N'
            8'h4F: glyph_rows = 56'h38444444444438; // 'O'
            8'h50: glyph_rows = 56'h78444478404040; // 'P'
            8'h51: glyph_rows = 56'h38444444544834; // 'Q'
            8'h52: glyph_rows = 56'h78444478504844; // 'R'
            8'h53: glyph_rows = 56'h38444038044438; // 'S'
            8'h54: glyph_rows = 56'h7C101010101010; // 'T'
            8'h55: glyph_rows = 56'h44444444444438; // 'U'
            8'h56: glyph_rows = 56'h44444444442810; // 'V'
            8'h57: glyph_rows = 56'h44444454546C44; // 'W'
            8'h58: glyph_rows = 56'h44442810284444; // 'X'
            8'h59: glyph_rows = 56'h44442810101010; // 'Y'
            8'h5A: glyph_rows = 56'h7C04081020407C; // 'Z'
            8'h5B: glyph_rows = 56'h38202020202038; // '['
            8'h5D: glyph_rows = 56'h38080808080838; // ']'
            8'h5F: glyph_rows = 56'h0000000000007C; // '_'
            8'h62: glyph_rows = 56'h40407844444478; // 'b'
            8'h6B: glyph_rows = 56'h40404850605048; // 'k'
            8'h6C: glyph_rows = 56'h30101010101038; // 'l'
            8'h73: glyph_rows = 56'h00003C40380478; // 's'
            8'h78: glyph_rows = 56'h00004428102844; // 'x'
            8'h7A: glyph_rows = 56'h00007C0810207C; // 'z'
            default: glyph_rows = 56'h00000000000000;
        endcase
    end

    always @(*) begin
        case (row)
            3'd0: row_bits = glyph_rows[55:48];
            3'd1: row_bits = glyph_rows[47:40];
            3'd2: row_bits = glyph_rows[39:32];
            3'd3: row_bits = glyph_rows[31:24];
            3'd4: row_bits = glyph_rows[23:16];
            3'd5: row_bits = glyph_rows[15:8];
            3'd6: row_bits = glyph_rows[7:0];
            default: row_bits = 8'h00;
        endcase
    end

endmodule

`default_nettype wire
