// One entry per alarm evaluation. Capture the compared snapshot first, then the
// registered alarm result on the following 100 MHz edge. Byte 0 is the LSB.
module env_log_queue (
    input wire clk, rst, active, sample_tick,
    input wire [31:0] uptime_s,
    input wire signed [15:0] temp_x10,
    input wire [15:0] humi_x10, lux,
    input wire [11:0] adc_raw,
    input wire [7:0] sensor_status,
    input wire data_ok,
    input wire [3:0] alarm_level, alarm_src,
    input wire pop,
    output wire valid,
    output wire [127:0] data,
    output reg overflow
);
    reg pending;
    reg [31:0] seconds_q;
    reg [15:0] temp_q, humi_q, lux_q;
    reg [11:0] adc_q;
    reg [7:0] status_q;
    reg ok_q;
    reg [127:0] entries [0:31];
    reg [4:0] rd, wr;
    reg [5:0] count;
    wire take = pop && valid;
    wire put = pending && (count != 6'd32 || take);
    assign valid = count != 0;
    assign data = entries[rd];

    always @(posedge clk) begin
        if (rst || !active) begin
            pending <= 0;
            rd <= 0;
            wr <= 0;
            count <= 0;
            overflow <= 0;
        end else begin
            pending <= sample_tick;
            if (sample_tick) begin
                seconds_q <= uptime_s;
                temp_q <= temp_x10;
                humi_q <= humi_x10;
                lux_q <= lux;
                adc_q <= adc_raw;
                status_q <= sensor_status;
                ok_q <= data_ok;
            end
            if (put) begin
                entries[wr] <= {4'b0, adc_q, 7'b0, ok_q, 4'b0, alarm_src,
                                4'b0, alarm_level, status_q, lux_q, humi_q, temp_q, seconds_q};
                wr <= wr + 1'b1;
            end else if (pending) begin
                overflow <= 1;
            end
            if (take) rd <= rd + 1'b1;
            case ({put,take})
                2'b10: count <= count + 1'b1;
                2'b01: count <= count - 1'b1;
                default: count <= count;
            endcase
        end
    end
endmodule
