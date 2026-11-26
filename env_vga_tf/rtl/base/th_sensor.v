// Pmod HYGRO rev. A (TI HDC1080), Nexys A7 JB3=SCL and JB4=SDA.
// Enable both JP1 pull-ups. Both lines are open drain; only clk clocks the logic.
module th_sensor #(
    parameter integer QUARTER_CYCLES      = 250,   // 100 MHz / (4 * 100 kHz)
    parameter integer POWERUP_QUARTERS    = 40000, // 100 ms
    parameter integer CONVERSION_QUARTERS = 2800,  // 7 ms per channel
    parameter integer BUS_TIMEOUT_QUARTERS = 400   // 1 ms for SDA to be released
) (
    input  wire               clk,
    input  wire               rst,
    input  wire               sample_tick,
    output wire               scl,
    inout  wire               sda,
    output reg  signed [15:0] temp_x10,
    output reg         [15:0] humi_x10,
    output reg         [7:0]  status,
    output reg                valid
);
    localparam [1:0] CONFIGURE = 0, TRIGGER = 1, READ_RESULT = 2;
    localparam [3:0] POWER_UP = 0, IDLE = 1, START_WAIT = 2, START_HOLD = 3,
                     START_LOW = 4, BIT_SETUP = 5, BIT_RISE = 6, BIT_SAMPLE = 7,
                     BIT_FALL = 8, STOP_SETUP = 9, STOP_RISE = 10, STOP_HOLD = 11,
                     STOP_RELEASE = 12, STOP_WAIT = 13, CONVERT = 14;

    reg scl_low, sda_low;
    assign scl = scl_low ? 1'b0 : 1'bz;
    assign sda = sda_low ? 1'b0 : 1'bz;
    (* ASYNC_REG = "TRUE" *) reg [1:0] sda_sync;

    localparam integer DIV_WIDTH = QUARTER_CYCLES > 1 ? $clog2(QUARTER_CYCLES) : 1;
    reg [DIV_WIDTH-1:0] divider;
    wire quarter_tick = (divider == QUARTER_CYCLES - 1);
    always @(posedge clk) begin
        if (rst) begin
            divider  <= 0;
            sda_sync <= 2'b11;
        end else begin
            divider  <= quarter_tick ? 0 : divider + 1'b1;
            sda_sync <= {sda_sync[0], sda};
        end
    end

    localparam integer MAX_WAIT = (POWERUP_QUARTERS > CONVERSION_QUARTERS)
                                ? POWERUP_QUARTERS : CONVERSION_QUARTERS;
    localparam integer WAIT_WIDTH = $clog2(1 + ((MAX_WAIT > BUS_TIMEOUT_QUARTERS)
                                             ? MAX_WAIT : BUS_TIMEOUT_QUARTERS));
    reg [WAIT_WIDTH-1:0] wait_left;
    reg [3:0] state;
    reg [1:0] operation, byte_index;
    reg [2:0] bit_index;
    reg humidity, pending, ack_slot, nack;
    reg [15:0] raw_word, raw_temp;

    // CONFIGURE: 80 02 00 00. TRIGGER: 80 00/01. READ_RESULT: 81 MSB LSB.
    wire receiving = operation == READ_RESULT && byte_index != 0;
    wire [1:0] last_byte = (operation == CONFIGURE) ? 3 : (operation == TRIGGER) ? 1 : 2;
    reg [7:0] tx_byte;
    always @* begin
        case (byte_index)
            0: tx_byte = {7'h40, operation == READ_RESULT};
            1: tx_byte = (operation == CONFIGURE) ? 8'h02 : {7'b0, humidity};
            default: tx_byte = 8'h00;
        endcase
    end

    // Keep the unsigned products wide, round to nearest tenth, then apply the signed offset.
    wire [31:0] temp_scaled = raw_temp * 16'd1650 + 32'd32768;
    wire [31:0] humi_scaled = raw_word * 16'd1000 + 32'd32768;

    always @(posedge clk) begin
        if (rst) begin
            state      <= POWER_UP;
            wait_left  <= POWERUP_QUARTERS;
            operation  <= CONFIGURE;
            scl_low    <= 0;
            sda_low    <= 0;
            pending    <= 0;
            humidity   <= 0;
            byte_index <= 0;
            bit_index  <= 7;
            ack_slot   <= 0;
            nack       <= 0;
            raw_word   <= 0;
            raw_temp   <= 0;
            temp_x10   <= 0;
            humi_x10   <= 0;
            status     <= 8'h08;
            valid      <= 0;
        end else begin
            valid <= 0;
            if (sample_tick)
                pending <= 1;

            if (quarter_tick) begin
                case (state)
                    POWER_UP: if (wait_left == 1) begin
                        wait_left <= BUS_TIMEOUT_QUARTERS;
                        state <= START_WAIT;  // write configuration once after power-up
                    end else wait_left <= wait_left - 1'b1;

                    IDLE: if (pending || sample_tick) begin
                        // An unplugged sensor may power up with its default mode on reconnect.
                        // Keep the request pending across reconfiguration.
                        operation <= status[3] ? CONFIGURE : TRIGGER;
                        pending <= status[3];
                        humidity <= 0;
                        wait_left <= BUS_TIMEOUT_QUARTERS;
                        state <= START_WAIT;
                    end

                    // Wait for a free bus before START and verify release after STOP.
                    START_WAIT, STOP_WAIT: begin
                        if (!sda_sync[1]) begin
                            if (wait_left == 1) begin
                                status[3:1] <= 3'b110;  // needs config, bus timeout
                                pending <= 0;
                                state <= IDLE;
                            end else wait_left <= wait_left - 1'b1;
                        end else if (state == START_WAIT) begin
                            sda_low <= 1;
                            byte_index <= 0;
                            bit_index <= 7;
                            ack_slot <= 0;
                            nack <= 0;
                            state <= START_HOLD;
                        end else if (nack) begin
                            status[3:1] <= 3'b101;      // needs config, NACK
                            pending <= 0;
                            state <= IDLE;
                        end else begin
                            case (operation)
                                CONFIGURE: begin
                                    status[3] <= 0;
                                    state <= IDLE;
                                end
                                TRIGGER: begin
                                    wait_left <= CONVERSION_QUARTERS;
                                    state <= CONVERT;
                                end
                                READ_RESULT: if (!humidity) begin
                                    raw_temp <= raw_word;
                                    humidity <= 1;
                                    operation <= TRIGGER;
                                    wait_left <= BUS_TIMEOUT_QUARTERS;
                                    state <= START_WAIT;
                                end else begin
                                    temp_x10 <= $signed(temp_scaled[31:16]) - 16'sd400;
                                    humi_x10 <= humi_scaled[31:16];
                                    status <= 8'h01;   // a good frame has been seen
                                    valid <= 1;
                                    state <= IDLE;
                                end
                            endcase
                        end
                    end

                    START_HOLD: state <= START_LOW;
                    START_LOW: begin
                        scl_low <= 1;
                        state <= BIT_SETUP;
                    end

                    // Four quarter-ticks per bit, including the ninth (ACK/NACK) bit.
                    BIT_SETUP: begin
                        if (ack_slot)
                            sda_low <= receiving && byte_index != last_byte;
                        else
                            sda_low <= !receiving && !tx_byte[bit_index];
                        state <= BIT_RISE;
                    end
                    BIT_RISE: begin
                        scl_low <= 0;
                        state <= BIT_SAMPLE;
                    end
                    BIT_SAMPLE: begin
                        if (ack_slot && !receiving)
                            nack <= sda_sync[1];
                        if (!ack_slot && receiving)
                            raw_word <= {raw_word[14:0], sda_sync[1]};
                        state <= BIT_FALL;
                    end
                    BIT_FALL: begin
                        scl_low <= 1;
                        state <= BIT_SETUP;
                        if (ack_slot) begin
                            ack_slot <= 0;
                            bit_index <= 7;
                            if (nack || byte_index == last_byte)
                                state <= STOP_SETUP;
                            else
                                byte_index <= byte_index + 1'b1;
                        end else if (bit_index == 0)
                            ack_slot <= 1;
                        else
                            bit_index <= bit_index - 1'b1;
                    end

                    STOP_SETUP: begin
                        sda_low <= 1;
                        state <= STOP_RISE;
                    end
                    STOP_RISE: begin
                        scl_low <= 0;
                        state <= STOP_HOLD;
                    end
                    STOP_HOLD: state <= STOP_RELEASE;
                    STOP_RELEASE: begin
                        sda_low <= 0;
                        wait_left <= BUS_TIMEOUT_QUARTERS;
                        state <= STOP_WAIT;
                    end

                    CONVERT: if (wait_left == 1) begin
                        operation <= READ_RESULT;
                        wait_left <= BUS_TIMEOUT_QUARTERS;
                        state <= START_WAIT;
                    end else wait_left <= wait_left - 1'b1;
                endcase
            end
        end
    end
endmodule
