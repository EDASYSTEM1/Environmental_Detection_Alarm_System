// Bus-level HDC1080 model for both the driver and system tests.
// The model only observes the two pins. It checks address, configuration,
// conversion delay, byte order, 9th bits, STOP, and SCL period.
`timescale 1ns / 1ps
module hdc1080_model #(
    parameter integer BIT_NS = 10_000,
    parameter integer POWER_NS = 100_000_000,
    parameter integer CONVERSION_NS = 7_000_000
) (
    input wire scl, inout wire sda,
    input wire [15:0] temp_raw, humi_raw,
    input wire nack_write_address, nack_humidity_read
);
    reg drive_low = 0;
    assign sda = drive_low ? 1'b0 : 1'bz;

    task receive_byte;
        output [7:0] value;
        integer bit_no;
        time previous_rise;
        begin
            for (bit_no = 7; bit_no >= 0; bit_no = bit_no - 1) begin
                @(posedge scl);
                if (bit_no != 7 && $time - previous_rise != BIT_NS)
                    $fatal(1, "Wrong SCL period at %t", $time);
                previous_rise = $time;
                value[bit_no] = sda;
                @(negedge scl);
            end
        end
    endtask

    task reply_ack;
        input accept;
        begin
            drive_low = accept;
            @(posedge scl);
            if (sda !== !accept) $fatal(1, "Master did not release ACK slot");
            @(negedge scl);
            drive_low = 0;
        end
    endtask

    task send_byte;
        input [7:0] value;
        input last;
        integer bit_no;
        begin
            for (bit_no = 7; bit_no >= 0; bit_no = bit_no - 1) begin
                drive_low = !value[bit_no];
                @(posedge scl);
                if (sda !== value[bit_no]) $fatal(1, "SDA contention in read");
                @(negedge scl);
            end
            drive_low = 0;
            @(posedge scl);
            if (sda !== last) $fatal(1, "Expected ACK on MSB and NACK on LSB");
            @(negedge scl);
        end
    endtask

    task expect_stop;
        begin
            @(posedge scl);
            if (sda !== 0) $fatal(1, "Invalid STOP setup");
            @(posedge sda);
            if (scl !== 1) $fatal(1, "Expected STOP");
        end
    endtask

    reg [7:0] address_byte, pointer, config_byte;
    reg configured = 0, triggered = 0;
    reg [15:0] result;
    time trigger_time, start_time;
    always begin : transaction
        @(negedge sda);
        if (scl === 1) begin
            start_time = $time;
            // A stuck SDA can be released before any clock pulse (empty START/STOP).
            @(negedge scl or posedge sda);
            if (scl !== 0) disable transaction;
            if (start_time < POWER_NS) $fatal(1, "I2C before power-up delay");
            receive_byte(address_byte);
            case (address_byte)
                8'h80: begin
                    reply_ack(!nack_write_address);
                    if (nack_write_address) begin
                        expect_stop;
                        configured = 0;
                    end else begin
                        receive_byte(pointer);
                        reply_ack(1);
                        case (pointer)
                            8'h02: begin
                                repeat (2) begin
                                    receive_byte(config_byte);
                                    if (config_byte !== 0) $fatal(1, "Expected config 0x0000");
                                    reply_ack(1);
                                end
                                expect_stop;
                                configured = 1;
                                triggered = 0;
                            end
                            8'h00, 8'h01: begin
                                if (!configured) $fatal(1, "Missing configuration");
                                expect_stop;
                                trigger_time = $time;
                                triggered = 1;
                            end
                            default: $fatal(1, "Unexpected pointer %h", pointer);
                        endcase
                    end
                end
                8'h81: begin
                    if (!triggered || start_time - trigger_time < CONVERSION_NS)
                        $fatal(1, "Read before conversion completed");
                    triggered = 0;
                    if (pointer == 1 && nack_humidity_read) begin
                        reply_ack(0);
                        expect_stop;
                        configured = 0;
                    end else begin
                        reply_ack(1);
                        result = pointer == 1 ? humi_raw : temp_raw;
                        send_byte(result[15:8], 0);
                        send_byte(result[7:0], 1);
                        expect_stop;
                    end
                end
                default: $fatal(1, "Unexpected I2C address %h", address_byte);
            endcase
        end
    end
endmodule
