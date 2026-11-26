// Pmod ALS rev. A, ADC081S021 (8 bit), Nexys A7 JC1=CS, JC3=MISO, JC4=SCLK.
// 100 MHz system clock, 1 MHz mode 3 SPI. A tick requests one published sample.
// The first request after reset includes one discarded power-up conversion.
//
// 照度表为名义估算，尚无本板实测数据。假设 VCC=3.3 V、R1=10 kOhm；
// TEMT6000X01 在 25 °C、标准 A 光源、VCE=5 V 时典型光电流为 50 uA/100 lx。
// 未饱和区以 lux ≈ ADC * 660 / 256 取整生成下列五个节点，节点间线性插值。
// 上板后用同位置照度计的读数替换节点；标定方法和资料见本模块 README。
module light_sensor (
    input  wire        clk,
    input  wire        rst,
    input  wire        sample_tick,
    output wire        als_cs,
    output wire        als_sclk,
    input  wire        als_miso,
    output reg  [11:0] adc_raw,
    output reg  [15:0] lux,
    output reg  [7:0]  status,
    output reg         valid
);
    localparam integer LUX_AT_0   = 0,   LUX_AT_64  = 165, LUX_AT_128 = 330,
                       LUX_AT_192 = 495, LUX_AT_255 = 657;

    function integer interpolate;
        input integer offset, span, low_lux, high_lux;
        begin
            interpolate = low_lux + ((high_lux - low_lux) * offset + span/2) / span;
        end
    endfunction

    // Constant initialization builds a 256-entry ROM at synthesis time.
    reg [15:0] lux_table [0:255];
    integer i;
    initial begin
        for (i = 0; i < 256; i = i + 1) begin
            if (i < 64)
                lux_table[i] = interpolate(i,       64, LUX_AT_0,   LUX_AT_64);
            else if (i < 128)
                lux_table[i] = interpolate(i - 64,  64, LUX_AT_64,  LUX_AT_128);
            else if (i < 192)
                lux_table[i] = interpolate(i - 128, 64, LUX_AT_128, LUX_AT_192);
            else
                lux_table[i] = interpolate(i - 192, 63, LUX_AT_192, LUX_AT_255);
        end
    end

    localparam [1:0] IDLE = 0, TRANSFER = 1, FINISH = 2, WARMUP_GAP = 3;
    localparam [5:0] HALF_PERIOD_LAST = 6'd49;  // 50 * 10 ns = 500 ns
    reg [1:0] state;
    reg [5:0] divider;
    reg [3:0] bit_index;  // zero-based index of the next rising-edge sample
    reg [7:0] sample_bits;
    reg       bad_padding;
    reg       cs_n, sclk;
    assign als_cs   = cs_n;
    assign als_sclk = sclk;

    always @(posedge clk) begin
        if (rst) begin
            state       <= IDLE;
            divider     <= 0;
            bit_index   <= 0;
            sample_bits <= 0;
            bad_padding <= 0;
            cs_n        <= 1;
            sclk        <= 1;
            adc_raw     <= 0;
            lux         <= 0;
            status      <= 8'h08;   // ST_BUSY until power-up conversion completes
            valid       <= 0;
        end else begin
            valid <= 0;
            case (state)
                IDLE: if (sample_tick) begin
                    cs_n  <= 0;
                    state <= TRANSFER;
                end

                TRANSFER: if (divider == HALF_PERIOD_LAST) begin
                    divider <= 0;
                    sclk    <= ~sclk;
                    if (!sclk) begin
                        // ADC changes on falling edges. Rising edges 4..11 carry D7..D0.
                        // Rising edges 1..3 and 12..15 carry zeros; edge 16 is high-Z.
                        if (bit_index >= 3 && bit_index <= 10)
                            sample_bits <= {sample_bits[6:0], als_miso};
                        else if (bit_index != 15 && als_miso)
                            bad_padding <= 1;

                        bit_index <= bit_index + 1'b1;
                        if (bit_index == 15)
                            state <= FINISH;
                    end
                end else begin
                    divider <= divider + 1'b1;
                end

                FINISH: begin
                    cs_n        <= 1;
                    bad_padding <= 0;
                    if (status[3]) begin
                        status[3] <= 0;
                        state     <= WARMUP_GAP;
                    end else begin
                        status[1] <= bad_padding;
                        if (!bad_padding) begin
                            adc_raw   <= {4'b0000, sample_bits};
                            lux       <= lux_table[sample_bits];
                            status[0] <= 1;    // ST_VALID stays set until reset
                            valid     <= 1;
                        end
                        state <= IDLE;
                    end
                end

                // Leave CS high for 500 ns before the first usable conversion.
                WARMUP_GAP: if (divider == HALF_PERIOD_LAST) begin
                    divider <= 0;
                    cs_n    <= 0;
                    state   <= TRANSFER;
                end else begin
                    divider <= divider + 1'b1;
                end
            endcase
        end
    end
endmodule
