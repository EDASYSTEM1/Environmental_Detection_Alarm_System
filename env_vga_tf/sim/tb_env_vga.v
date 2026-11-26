`timescale 1ns/1ps
module tb_env_vga;
    reg clk=0,rst=1,bg_we=0,bg_ready=0;
    reg [16:0] wa=0;
    reg [7:0] wd=0,status=3;
    reg signed [15:0] temp=-53;
    reg [15:0] humi=1000,lux=320;
    reg [3:0] level=0;
    wire [3:0] r,g,b;
    wire hs,vs;
    env_vga dut(.clk(clk),.rst(rst),.bg_we(bg_we),.bg_waddr(wa),.bg_wdata(wd),
                .bg_ready(bg_ready),.temp_x10(temp),.humi_x10(humi),.lux(lux),
                .sensor_status(status),.alarm_level(level),.vga_r(r),.vga_g(g),
                .vga_b(b),.vga_hs(hs),.vga_vs(vs));
    always #5 clk=~clk;
    // Deposit timing counters for fast coverage, then let the real counters,
    // pixel enable, glyph counter and output pipeline run for the test line.
    task go_line;
        input integer y, x;
        begin
            @(negedge clk);
            dut.timing.x_r=x; dut.timing.y_r=y; dut.timing.pdiv=0;
        end
    endtask
    task frame_latch;
        begin go_line(480,0);repeat(58) @(negedge clk);end
    endtask
    task put_background;
        input integer a; input [7:0] color;
        begin @(negedge clk);bg_we=1;wa=a;wd=color;@(negedge clk);bg_we=0;end
    endtask
    task next_pixel;
        input [11:0] expected;
        begin
            repeat(4) @(negedge clk);
            if({r,g,b}!==expected)
                $fatal(1,"x=%0d y=%0d rgb=%03x expected=%03x",dut.x,dut.y,{r,g,b},expected);
        end
    endtask
    integer x,k;
    reg [11:0] expected;
    initial begin
        repeat(3) @(negedge clk);rst=0;
        frame_latch;
        if(dut.temp_text!=="    -5.3 C" || dut.humi_text!=="   100.0 %" || dut.light_text!=="    320 lx")
            $fatal(1,"format error /%s/ /%s/ /%s/",dut.temp_text,dut.humi_text,dut.light_text);
        status=4'b1111;frame_latch;
        if(dut.temp_text!=="    --.- C" || dut.light_text!=="     -- lx") $fatal(1,"stale indication");
        temp=16'sh8000;humi=65535;lux=65535;status=3;frame_latch;
        if(dut.temp_text!==" -3276.8 C" || dut.humi_text!=="  6553.5 %" || dut.light_text!=="  65535 lx")
            $fatal(1,"full-range conversion");
        // Basic fallback while there is no image.
        go_line(2,0);next_pixel(12'h123);
        put_background(0,8'he0);put_background(1,8'h1c);put_background(320,8'h03);
        bg_ready=1;frame_latch;
        go_line(0,0);next_pixel(12'hf00);next_pixel(12'hf00);next_pixel(12'h0f0);
        go_line(1,0);next_pixel(12'hf00);go_line(2,0);next_pixel(12'h00f);
        // Dark entire numeric strip, then check every physical pixel across
        // the top scanline of "     0.0 C" against independent glyph ROM data.
        for(k=0;k<160;k=k+1) put_background(56*320+k,0);
        temp=0;level=2;frame_latch;go_line(112,63);next_pixel(12'h000);
        for(x=64;x<304;x=x+1) begin
            expected=0;
            case((x-64)/24)
                5,7: if ((((x-64)%24)/3)>=2 && (((x-64)%24)/3)<=4) expected=12'hfc4;
                9: if ((((x-64)%24)/3)>=2 && (((x-64)%24)/3)<=4) expected=12'hfc4;
            endcase
            next_pixel(expected);
        end
        go_line(4,656);next_pixel(0);if(hs!==0 || vs!==1)$fatal(1,"H sync");
        go_line(490,10);next_pixel(0);if(hs!==1 || vs!==0)$fatal(1,"V sync");
        $display("PASS env_vga: full-range BCD, live/fault overlays, pixel glyphs, 2x RGB, fallback, blanking and sync");$finish;
    end
endmodule
