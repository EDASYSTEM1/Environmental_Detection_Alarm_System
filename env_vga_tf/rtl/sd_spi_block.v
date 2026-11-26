// SPI mode 0, single-block SDHC/SDXC access, 512 bytes per LBA.
// The caller owns the host RAM port between transactions. A completed read is
// usable only when blk_done is high and blk_error is low. A write completes
// after the card releases busy and CMD13 reports clean programming status.
module sd_spi_block #(
    parameter integer POWERUP_CYCLES = 1_000_000, // 10 ms at 100 MHz
    parameter integer INIT_HALF_DIV = 128,       // 390.625 kHz
    parameter integer DATA_HALF_DIV = 8,         // 6.25 MHz
    parameter integer INIT_TRIES = 4096,
    parameter integer DATA_WAIT_BYTES = 262144,
    parameter integer BUSY_WAIT_BYTES = 1048576
) (
    input wire clk, input wire rst,
    output reg sd_cs, output reg sd_sck, output reg sd_mosi, input wire sd_miso,
    output reg card_ready, output reg init_error,
    input wire cmd_valid, input wire cmd_write, input wire [31:0] cmd_lba,
    output wire cmd_ready, output reg blk_done, output reg blk_error,
    input wire [8:0] buf_addr, output reg [7:0] buf_rdata,
    input wire buf_we, input wire [7:0] buf_wdata
);
    localparam [4:0] POWERUP=0, CLOCKS=1, COMMAND_GAP=2, COMMAND_BYTES=3,
        RESPONSE=4, EXT_RESPONSE=5, INIT_GAP=6, IDLE=7, WAIT_READ_TOKEN=8,
        READ_DATA=9, READ_CRC_HI=10, READ_CRC_LO=11, WRITE_GAP=12,
        WRITE_TOKEN=13, WRITE_FETCH=14, WRITE_DATA=15, WRITE_CRC_HI=16,
        WRITE_CRC_LO=17, WRITE_RESPONSE=18, WRITE_BUSY=19, CARD_STATUS=20,
        FINISH=21, INIT_FAILED=22;
    reg [4:0] state;
    reg [5:0] command;
    reg [31:0] argument;
    reg [39:0] command_shift;
    reg [2:0] command_byte;
    reg [6:0] command_crc;
    reg [1:0] ext_count;
    reg [23:0] ext_shift;
    reg [8:0] data_index;
    reg [15:0] data_crc;
    reg [7:0] crc_hi;
    reg [31:0] wait_count;
    reg [15:0] init_attempt;
    reg [4:0] response_wait;
    reg failed_block;
    assign cmd_ready = (state == IDLE);

    // Bit-serial CRCs folded over one byte. SD CRC16 uses initial state zero.
    function [6:0] crc7_byte;
        input [6:0] old_crc;
        input [7:0] value;
        integer k;
        reg [6:0] c;
        begin
            c = old_crc;
            for (k=7; k>=0; k=k-1)
                c = {c[5:0],1'b0} ^ ((c[6] ^ value[k]) ? 7'h09 : 7'h00);
            crc7_byte = c;
        end
    endfunction
    function [15:0] crc16_byte;
        input [15:0] old_crc;
        input [7:0] value;
        integer k;
        reg [15:0] c;
        begin
            c = old_crc;
            for (k=7; k>=0; k=k-1)
                c = {c[14:0],1'b0} ^ ((c[15] ^ value[k]) ? 16'h1021 : 16'h0000);
            crc16_byte = c;
        end
    endfunction

    reg request_byte, shifting, byte_done;
    reg [7:0] next_byte, tx_shift, rx_shift, rx_byte;
    reg [2:0] bit_index;
    reg [15:0] divider;
    wire [15:0] half_last = card_ready ? DATA_HALF_DIV-1 : INIT_HALF_DIV-1;
    wire [31:0] extended_value = {ext_shift, rx_byte};
    reg [7:0] sector [0:511];
    reg [7:0] card_read;
    always @(posedge clk) begin
        if (buf_we) sector[buf_addr] <= buf_wdata;
        buf_rdata <= sector[buf_addr];
    end
    always @(posedge clk) begin
        if (state == READ_DATA && byte_done) sector[data_index] <= rx_byte;
        card_read <= sector[data_index];
    end
    always @* begin
        request_byte = 1'b1;
        next_byte = 8'hff;
        case (state)
            CLOCKS, COMMAND_GAP, RESPONSE, EXT_RESPONSE, INIT_GAP,
            WAIT_READ_TOKEN, READ_DATA, READ_CRC_HI, READ_CRC_LO,
            WRITE_GAP, WRITE_RESPONSE, WRITE_BUSY, CARD_STATUS, FINISH: ;
            COMMAND_BYTES: next_byte = command_byte == 5 ?
                {command_crc,1'b1} : command_shift[39:32];
            WRITE_TOKEN: next_byte = 8'hfe;
            WRITE_DATA: next_byte = card_read;
            WRITE_CRC_HI: next_byte = data_crc[15:8];
            WRITE_CRC_LO: next_byte = data_crc[7:0];
            default: request_byte = 1'b0;
        endcase
    end
    // MOSI is presented before the rising edge; MISO is sampled on that edge.
    always @(posedge clk) begin
        if (rst) begin
            sd_sck <= 0; sd_mosi <= 1; shifting <= 0; byte_done <= 0;
            divider <= 0; bit_index <= 0; tx_shift <= 0; rx_shift <= 0; rx_byte <= 0;
        end else begin
            byte_done <= 0;
            if (!shifting) begin
                if (request_byte && !byte_done) begin
                    shifting <= 1; divider <= 0; bit_index <= 0;
                    tx_shift <= next_byte; sd_mosi <= next_byte[7];
                end
            end else if (divider != half_last) begin
                divider <= divider + 1'b1;
            end else begin
                divider <= 0;
                if (!sd_sck) begin
                    sd_sck <= 1;
                    rx_shift <= {rx_shift[6:0],sd_miso};
                end else begin
                    sd_sck <= 0;
                    if (bit_index == 7) begin
                        shifting <= 0; byte_done <= 1;
                        rx_byte <= rx_shift; sd_mosi <= 1;
                    end else begin
                        bit_index <= bit_index + 1'b1;
                        tx_shift <= {tx_shift[6:0],1'b1}; sd_mosi <= tx_shift[6];
                    end
                end
            end
        end
    end

    task queue_command;
        input [5:0] index;
        input [31:0] arg;
        begin
            command <= index; argument <= arg;
            // CS high with eight extra clocks releases the previous command.
            sd_cs <= 1; state <= COMMAND_GAP;
        end
    endtask
    task finish_block;
        input bad;
        begin
            failed_block <= bad; sd_cs <= 1; state <= FINISH;
        end
    endtask
    task fail_init;
        begin
            init_error <= 1; card_ready <= 0; sd_cs <= 1; state <= INIT_FAILED;
        end
    endtask
    always @(posedge clk) begin
        if (rst) begin
            state <= POWERUP; sd_cs <= 1; card_ready <= 0; init_error <= 0;
            blk_done <= 0; blk_error <= 0; failed_block <= 0;
            command <= 0; argument <= 0; command_shift <= 0; command_byte <= 0;
            command_crc <= 0; ext_count <= 0; ext_shift <= 0; data_index <= 0;
            data_crc <= 0; crc_hi <= 0; wait_count <= 0; init_attempt <= 0;
            response_wait <= 0;
        end else begin
            blk_done <= 0; blk_error <= 0;
            case (state)
                POWERUP: if (wait_count >= POWERUP_CYCLES-1) begin
                    wait_count <= 0; state <= CLOCKS;
                end else wait_count <= wait_count + 1'b1;
                CLOCKS: if (byte_done) begin
                    if (wait_count == 9) queue_command(0,0);
                    else wait_count <= wait_count + 1'b1;
                end
                COMMAND_GAP: if (byte_done) begin
                    sd_cs <= 0; command_crc <= 0; command_byte <= 0;
                    command_shift <= {2'b01,command,argument}; state <= COMMAND_BYTES;
                end
                COMMAND_BYTES: if (byte_done) begin
                    if (command_byte == 5) begin
                        response_wait <= 0; state <= RESPONSE;
                    end else begin
                        command_crc <= crc7_byte(command_crc,command_shift[39:32]);
                        command_shift <= {command_shift[31:0],8'hff};
                        command_byte <= command_byte + 1'b1;
                    end
                end
                RESPONSE: if (byte_done) begin
                    if (rx_byte[7]) begin
                        if (response_wait != 15) response_wait <= response_wait + 1'b1;
                        else if (card_ready) finish_block(1);
                        else if (command == 0 && init_attempt < 31) begin
                            init_attempt <= init_attempt + 1'b1; queue_command(0,0);
                        end else fail_init;
                    end else case (command)
                        0: if (rx_byte == 1) begin
                            init_attempt <= 0; queue_command(8,32'h1aa);
                        end else fail_init;
                        8,58: if (rx_byte == ((command==8) ? 1 : 0)) begin
                            ext_count <= 0; ext_shift <= 0; state <= EXT_RESPONSE;
                        end else fail_init;
                        55: if (rx_byte == 1 || rx_byte == 0) queue_command(41,32'h40000000);
                            else fail_init;
                        41: if (rx_byte == 0) queue_command(58,0);
                            else if (rx_byte == 1 && init_attempt < INIT_TRIES-1) begin
                                init_attempt <= init_attempt + 1'b1; queue_command(55,0);
                            end else fail_init;
                        17,24: if (rx_byte == 0) begin
                            wait_count <= 0; data_index <= 0; data_crc <= 0;
                            state <= (command == 17) ? WAIT_READ_TOKEN : WRITE_GAP;
                        end else finish_block(1);
                        13: if (rx_byte == 0) state <= CARD_STATUS;
                            else finish_block(1);
                        default: fail_init;
                    endcase
                end
                EXT_RESPONSE: if (byte_done) begin
                    ext_shift <= extended_value[23:0];
                    if (ext_count != 3) ext_count <= ext_count + 1'b1;
                    else if (command == 8) begin
                        if (extended_value[11:0] == 12'h1aa) queue_command(55,0);
                        else fail_init;
                    end else if (extended_value[31:30] == 2'b11 && |extended_value[21:20]) begin
                        sd_cs <= 1; state <= INIT_GAP;
                    end else fail_init;
                end
                INIT_GAP: if (byte_done) begin card_ready <= 1; state <= IDLE; end
                IDLE: if (cmd_valid) queue_command(cmd_write ? 6'd24 : 6'd17,cmd_lba);
                WAIT_READ_TOKEN: if (byte_done) begin
                    if (rx_byte == 8'hfe) state <= READ_DATA;
                    else if (rx_byte != 8'hff || wait_count >= DATA_WAIT_BYTES-1) finish_block(1);
                    else wait_count <= wait_count + 1'b1;
                end
                READ_DATA: if (byte_done) begin
                    data_crc <= crc16_byte(data_crc,rx_byte);
                    if (data_index == 511) state <= READ_CRC_HI;
                    else data_index <= data_index + 1'b1;
                end
                READ_CRC_HI: if (byte_done) begin crc_hi <= rx_byte; state <= READ_CRC_LO; end
                READ_CRC_LO: if (byte_done) finish_block({crc_hi,rx_byte} != data_crc);
                WRITE_GAP: if (byte_done) state <= WRITE_TOKEN;
                WRITE_TOKEN: if (byte_done) state <= WRITE_FETCH;
                WRITE_FETCH: state <= WRITE_DATA; // synchronous RAM prefetch
                WRITE_DATA: if (byte_done) begin
                    data_crc <= crc16_byte(data_crc,card_read);
                    if (data_index == 511) state <= WRITE_CRC_HI;
                    else begin data_index <= data_index + 1'b1; state <= WRITE_FETCH; end
                end
                WRITE_CRC_HI: if (byte_done) state <= WRITE_CRC_LO;
                WRITE_CRC_LO: if (byte_done) begin wait_count <= 0; state <= WRITE_RESPONSE; end
                WRITE_RESPONSE: if (byte_done) begin
                    if (rx_byte[4:0] == 5'b00101) begin wait_count <= 0; state <= WRITE_BUSY; end
                    else if (rx_byte != 8'hff || wait_count >= 63) finish_block(1);
                    else wait_count <= wait_count + 1'b1;
                end
                WRITE_BUSY: if (byte_done) begin
                    if (rx_byte == 8'hff) queue_command(13,0);
                    else if (wait_count >= BUSY_WAIT_BYTES-1) finish_block(1);
                    else wait_count <= wait_count + 1'b1;
                end
                CARD_STATUS: if (byte_done) finish_block(rx_byte != 0);
                FINISH: if (byte_done) begin
                    blk_done <= 1; blk_error <= failed_block; state <= IDLE;
                end
                INIT_FAILED: ; // Retry on card removal/insertion or system reset.
                default: fail_init;
            endcase
        end
    end
endmodule
