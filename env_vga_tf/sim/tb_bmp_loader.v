`timescale 1ns/1ps
module tb_bmp_loader;
    reg clk=0, rst=1, start=0, valid=0, last=0;
    reg [7:0] data=0;
    wire we,ready,error;
    wire [16:0] address;
    wire [7:0] pixel;
    bmp_loader dut(.clk(clk),.rst(rst),.bmp_start(start),.bmp_valid(valid),
                   .bmp_data(data),.bmp_end(last),.bg_we(we),.bg_waddr(address),
                   .bg_wdata(pixel),.bg_ready(ready),.bmp_error(error));
    always #5 clk=~clk;
    reg top_down, checking;
    integer writes, row, col;
    reg [7:0] red,green,blue;
    always @(posedge clk) if (we) begin
        if (!checking) $fatal(1,"write on unsupported BMP");
        row=writes/320;
        col=writes%320;
        red=col^row; green=row; blue=col;
        if (address !== ((top_down? row:239-row)*320+col) ||
            pixel !== {red[7:5],green[7:5],blue[7:6]})
            $fatal(1,"incorrect pixel %0d addr %0d rgb %02x",writes,address,pixel);
        writes=writes+1;
    end
    task send_bmp;
        input orientation;
        input integer depth, cutoff;
        input simultaneous_eof;
        integer p, total, ip, x, y, h, value;
        begin
            total=70+320*240*3; h=orientation?-240:240;
            top_down=orientation; checking=(depth==24); writes=0;
            for(p=0;p<cutoff;p=p+1) begin
                @(negedge clk);
                start=(p==0);valid=1;last=simultaneous_eof && p==cutoff-1;
                value=0;
                case(p)
                    0:value="B";1:value="M";
                    2,3,4,5:value=total>>(8*(p-2));
                    10:value=70;
                    14:value=40;
                    18:value=320;19:value=1;
                    22,23,24,25:value=h>>(8*(p-22));
                    26:value=1;28:value=depth;
                endcase
                if (p>=70) begin
                    ip=(p-70)/3;x=ip%320;y=ip/320;
                    case((p-70)%3)
                        0:value=x;1:value=y;2:value=x^y;
                    endcase
                end
                data=value;
                if ((p%617)==111 && !last) begin
                    @(negedge clk);start=0;valid=0;
                end
            end
            @(negedge clk);start=0;valid=0;last=!simultaneous_eof;
            @(negedge clk);last=0;
        end
    endtask
    initial begin
        repeat(3) @(negedge clk);rst=0;
        send_bmp(0,24,230470,1);
        if(!ready || error || writes!=76800) $fatal(1,"bottom-up EOF");
        send_bmp(1,24,230470,0);
        if(!ready || error || writes!=76800) $fatal(1,"top-down EOF");
        send_bmp(1,24,895,1);
        if(ready || !error || writes!=275) $fatal(1,"truncated BMP");
        send_bmp(0,32,888,1);
        if(ready || !error || writes!=0) $fatal(1,"unsupported bit depth");
        $display("PASS bmp_loader: both BMP row orders, all 153600 pixels, header gap, EOF, format checks");
        $finish;
    end
endmodule
