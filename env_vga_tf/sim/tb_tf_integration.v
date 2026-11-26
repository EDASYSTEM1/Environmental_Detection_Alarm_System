`timescale 1ns/1ps
// Run the unmodified storage subsystem all the way down to the card pins.
// Only the external card is modeled. Sparse FAT32 data clusters are 512 B.
module tb_tf_integration;
    reg clk=0, rst=1, cd_n=1, miso=1, tick=0;
    always #5 clk=~clk;
    reg signed [15:0] temp=253;
    reg [3:0] alarm=0, source=0;
    wire cs,sck,mosi,card_power,bg_write,bg_ready;
    wire [16:0] bg_addr;
    wire [7:0] bg_byte;
    wire [6:0] led;
    env_storage #(.CLK_HZ(1000)) storage (
        .clk(clk),.rst(rst),.sample_tick(tick),.sd_cd_n(cd_n),.sd_miso(miso),
        .sd_cs_n(cs),.sd_sck(sck),.sd_mosi(mosi),.sd_reset(card_power),
        .temp_x10(temp),.humi_x10(16'd550),.lux(16'd320),.adc_raw(12'd124),
        .sensor_status(8'h03),.data_ok(1'b1),.alarm_level(alarm),.alarm_src(source),
        .bg_we(bg_write),.bg_ready(bg_ready),.bg_waddr(bg_addr),.bg_wdata(bg_byte),
        .status_led(led)
    );
    defparam storage.u_sd.POWERUP_CYCLES=5, storage.u_sd.INIT_HALF_DIV=2,
             storage.u_sd.DATA_HALF_DIV=2;
    localparam BOOT=0, FAT=1, ROOT=2, LOGDIR=3, LOG_FIRST=4, LOG_SECOND=5;
    reg [7:0] disk [0:6*512-1];
    function integer slot;
        input [31:0] lba;
        begin case(lba)
            0: slot=BOOT; 8: slot=FAT; 608: slot=ROOT; 610: slot=LOGDIR;
            611: slot=LOG_FIRST; 613: slot=LOG_SECOND; default: slot=-1;
        endcase end
    endfunction
    task put32;
        input integer off; input [31:0] value;
        integer j;
        begin for(j=0;j<4;j=j+1) disk[off+j]=value[j*8 +: 8];end
    endtask
    task directory_entry;
        input integer file; input[87:0] name;input[7:0] attr;input integer cluster,bytes;
        integer idx,j;
        begin
            idx=file*512;
            for(j=0;j<11;j=j+1) disk[idx+j]=name[(10-j)*8 +: 8];
            disk[idx+11]=attr; disk[idx+26]=cluster;put32(idx+28,bytes);
        end
    endtask
    function [15:0] add_crc;
        input [15:0] old;input [7:0] value;
        reg [15:0] c;integer i;
        begin
            c=old^{value,8'h00};
            for(i=0;i<8;i=i+1)c=c[15]? (c<<1)^16'h1021 : (c<<1);
            add_crc=c;
        end
    endfunction
    task get_byte;
        output [7:0] b;integer i;
        begin for(i=7;i>=0;i=i-1)begin @(posedge sck);b[i]=mosi;end end
    endtask
    task put_byte;
        input[7:0] b;integer i;
        begin for(i=7;i>=0;i=i-1)begin @(negedge sck);miso=b[i];@(posedge sck);end end
    endtask
    always @(posedge cs) miso=1;
    integer writes=0, sessions=0;
    initial begin : spi_card
        reg [47:0] cmd;
        reg [7:0] b;
        reg [15:0] crc,from_host;
        integer i,sector;
        forever begin
            @(negedge cs);
            for(i=0;i<6;i=i+1)begin get_byte(b);cmd={cmd[39:0],b};end
            case(cmd[45:40])
                0: begin put_byte(1);sessions=sessions+1;end
                8: begin put_byte(1);put_byte(0);put_byte(0);put_byte(1);put_byte(8'haa);end
                55: put_byte(1);
                41: put_byte(0);
                58: begin put_byte(0);put_byte(8'hc0);put_byte(8'hff);put_byte(8'h80);put_byte(0);end
                13: begin put_byte(0);put_byte(0);end
                17: begin
                    sector=slot(cmd[39:8]);if(sector<0)$fatal(1,"read outside sparse volume, LBA %d",cmd[39:8]);
                    put_byte(0);put_byte(8'hfe);crc=0;
                    for(i=0;i<512;i=i+1)begin
                        b=disk[sector*512+i];put_byte(b);crc=add_crc(crc,b);
                    end
                    put_byte(crc[15:8]);put_byte(crc[7:0]);
                end
                24: begin
                    sector=slot(cmd[39:8]);
                    if(sector!=LOG_FIRST+writes||writes>=2)$fatal(1,"overwriting/incorrect target LBA %d",cmd[39:8]);
                    put_byte(0);get_byte(b);get_byte(b);
                    if(b!=8'hfe)$fatal(1,"missing SPI write token");
                    crc=0;
                    for(i=0;i<512;i=i+1)begin get_byte(b);disk[sector*512+i]=b;crc=add_crc(crc,b);end
                    get_byte(b);from_host[15:8]=b;get_byte(b);from_host[7:0]=b;
                    if(crc!==from_host)$fatal(1,"write payload CRC16");
                    put_byte(8'h05);put_byte(0);put_byte(8'hff);writes=writes+1;
                end
                default: $fatal(1,"unexpected SPI command %d",cmd[45:40]);
            endcase
        end
    end
    task sample;
        input signed [15:0] t;input [3:0] a,src;
        begin
            @(negedge clk);temp=t;alarm=0;source=0;tick=1;
            @(negedge clk);tick=0;alarm=a;source=src;temp=16'sd999;
            wait(storage.log_pop);
        end
    endtask
    task check_record;
        input integer file;input signed [15:0] t;input[3:0] a,src;
        integer base,i;reg [15:0] crc;
        begin
            base=file*512;
            if({disk[base],disk[base+1],disk[base+2],disk[base+3]}!=="ENV1" ||
               {disk[base+7],disk[base+6],disk[base+5],disk[base+4]}!==32'd1 ||
               {disk[base+9],disk[base+8]}!==t ||
               {disk[base+11],disk[base+10]}!==16'd550 ||
               {disk[base+13],disk[base+12]}!==16'd320 ||
               disk[base+14]!==8'h03 || disk[base+15]!=={4'b0,a} ||
               disk[base+16]!=={4'b0,src} || disk[base+17]!==8'd1 ||
               {disk[base+19],disk[base+18]}!==16'd124)
                $fatal(1,"sensor snapshot or pipelined alarm does not match sector %d",file);
            crc=16'hffff;
            for(i=0;i<20;i=i+1)crc=add_crc(crc,disk[base+i]);
            if({disk[base+509],disk[base+508]}!==crc ||
               {disk[base+510],disk[base+511]}!==16'ha55a)$fatal(1,"record CRC or commit marker");
        end
    endtask
    task boot_board;
        begin
            @(negedge clk);rst=1;cd_n=1;repeat(8)@(negedge clk);
            rst=0;cd_n=0;wait(storage.fs_ready || storage.fs_error);
            if(storage.fs_error || !storage.bg_missing || bg_ready || card_power)
                $fatal(1,"mount/optional missing image status");
        end
    endtask
    integer k;
    initial begin
        for(k=0;k<6*512;k=k+1)disk[k]=0;
        disk[0]=8'heb;disk[12]=2;disk[13]=1;disk[14]=8;disk[16]=1;
        put32(32,68000);put32(36,600);put32(44,2);disk[510]=8'h55;disk[511]=8'haa;
        put32(512+2*4,32'h0fffffff);put32(512+4*4,32'h0fffffff);
        put32(512+5*4,7);put32(512+7*4,32'h0fffffff);
        directory_entry(ROOT,"LOGS       ",8'h10,4,0);
        directory_entry(LOGDIR,"ENVLOG  BIN",8'h20,5,1024);
        boot_board;sample(16'sd253,4'd2,4'd1);check_record(LOG_FIRST,16'sd253,4'd2,4'd1);
        boot_board;sample(-16'sd75,4'd3,4'd8);check_record(LOG_SECOND,-16'sd75,4'd3,4'd8);
        check_record(LOG_FIRST,16'sd253,4'd2,4'd1);
        wait(storage.log_full);if(sessions!=2 || writes!=2)$fatal(1,"append/remount");
        $display("TF INTEGRATION TEST PASSED: two records over SPI with FAT32 remount");$finish;
    end
    initial begin #30_000_000;$fatal(1,"integration timed out");end
endmodule
