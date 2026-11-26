`timescale 1ns/1ps
// Run from the project root, or pass +BMP=/path/to/320x240.bmp to vvp.
// Exercise the data path using the actual card asset. Only the SD block device
// and sensor conversion results are modeled; the production FS, BMP, VGA,
// snapshot, alarm and log queue are all instantiated below.
module tb_dashboard_pipeline;
    reg clk=0,rst=1; always #5 clk=~clk;
    reg th_valid=0,ls_valid=0,tick=0;
    wire signed [15:0] temp;
    wire [15:0] humi,lux;
    wire [11:0] adc;
    wire [7:0] status;
    wire data_ok;
    wire [3:0] level,src;
    sensor_snapshot snap(.clk(clk),.rst(rst),.sample_tick(tick),
        .th_temp_x10(16'sd253),.th_humi_x10(16'd550),.th_status(8'h01),.th_valid(th_valid),
        .ls_lux(16'd320),.ls_adc_raw(12'd124),.ls_status(8'h01),.ls_valid(ls_valid),
        .temp_x10(temp),.humi_x10(humi),.lux(lux),.adc_raw(adc),.raw_status(),.status(status),.data_ok(data_ok));
    alarm_ctrl alarm(.clk(clk),.rst(rst),.sample_tick(tick),.temp_x10(temp),.humi_x10(humi),
        .lux(lux),.sensor_status(status),.sw(16'h00f0),.btn(5'b0),
        .alarm_level(level),.alarm_src(src),.led(),.buzz());
    wire queued,pop,overflow;
    wire [127:0] payload;
    env_log_queue logger(.clk(clk),.rst(rst),.active(!rst),.sample_tick(tick),.uptime_s(32'd42),
        .temp_x10(temp),.humi_x10(humi),.lux(lux),.adc_raw(adc),.sensor_status(status),
        .data_ok(data_ok),.alarm_level(level),.alarm_src(src),.pop(pop),.valid(queued),
        .data(payload),.overflow(overflow));
    wire cmd_valid,cmd_write,buf_we,bs,bv,be,fs_ready,full,fs_error,missing;
    wire [31:0] lba;
    wire [8:0] buf_addr;
    wire [7:0] buf_wdata,byte_value;
    reg [7:0] buf_rdata;
    reg done=0;
    fat32_store fs(.clk(clk),.rst(rst),.card_ready(!rst),
        .cmd_valid(cmd_valid),.cmd_write(cmd_write),.cmd_lba(lba),.cmd_ready(1'b1),
        .blk_done(done),.blk_error(1'b0),.buf_addr(buf_addr),.buf_rdata(buf_rdata),
        .buf_we(buf_we),.buf_wdata(buf_wdata),.bmp_start(bs),.bmp_valid(bv),.bmp_data(byte_value),.bmp_end(be),
        .log_valid(queued),.log_data(payload),.log_pop(pop),.fs_ready(fs_ready),
        .log_full(full),.fs_error(fs_error),.bg_missing(missing));
    wire bg_we,bg_ready,bmp_error;
    wire [7:0] wd;
    wire [16:0] wa;
    bmp_loader loader(.clk(clk),.rst(rst),.bmp_start(bs),.bmp_valid(bv),.bmp_data(byte_value),
        .bmp_end(be),.bg_we(bg_we),.bg_waddr(wa),.bg_wdata(wd),.bg_ready(bg_ready),.bmp_error(bmp_error));
    wire [3:0] r,g,b;
    wire hs,vs;
    env_vga screen(.clk(clk),.rst(rst),.bg_we(bg_we),.bg_waddr(wa),.bg_wdata(wd),
        .bg_ready(bg_ready),.temp_x10(temp),.humi_x10(humi),.lux(lux),.sensor_status(status),
        .alarm_level(level),.vga_r(r),.vga_g(g),.vga_b(b),.vga_hs(hs),.vga_vs(vs));

    // 8 sectors/cluster; root=2, IMAGES=3, LOGS=4, ENVLOG.BIN=5 and BG.BMP=10.
    // The test stores only the used front portion of a 540,000-sector volume.
    localparam FAT=32, DATA=632, FILE0=(DATA+8*8)*512, LOG0=(DATA+3*8)*512, LIMIT=1600;
    reg [7:0] disk[0:LIMIT*512-1],sram[0:511];
    reg [8*512-1:0] path;
    integer fd,sz,off,height,clusters,i,j,n,rendered=0,committed=0,cycles=0;
    always @(posedge clk) begin
        cycles=cycles+1;
        if(cycles>500000)$fatal(1,"dashboard timeout");
        if(fs_error || bmp_error || missing || overflow)$fatal(1,"pipeline fault");
        done<=0;
        if(buf_we)sram[buf_addr]<=buf_wdata;
        buf_rdata<=sram[buf_addr];
        if(cmd_valid)begin
            if(lba>=LIMIT)$fatal(1,"read beyond simulated extent: LBA %d",lba);
            if(cmd_write && lba!=LOG0/512)$fatal(1,"unexpected write LBA %d",lba);
            for(j=0;j<512;j=j+1)
                if(cmd_write)disk[lba*512+j]<=sram[j];
                else sram[j]<=disk[lba*512+j];
            if(cmd_write) committed=committed+1;
            done<=1;
        end
        if(bg_we)rendered=rendered+1;
    end
    task le32;
        input integer pos,value;
        begin
            disk[pos]=value;disk[pos+1]=value>>8;disk[pos+2]=value>>16;disk[pos+3]=value>>24;
        end
    endtask
    function integer read32;
        input integer pos;
        begin read32={disk[pos+3],disk[pos+2],disk[pos+1],disk[pos]};end
    endfunction
    task dirent;
        input integer pos;input [87:0] name;input integer att,cl,length;
        integer k;
        begin
            for(k=0;k<11;k=k+1)disk[pos+k]=name[87-k*8 -: 8];
            disk[pos+11]=att;disk[pos+26]=cl;le32(pos+28,length);
        end
    endtask
    function [7:0] golden;
        input integer x,y;
        integer p;
        begin
            p=FILE0+off+3*((height>0 ? 239-y : y)*320+x);
            golden={disk[p+2][7:5],disk[p+1][7:5],disk[p][7:6]};
        end
    endfunction
    function [11:0] rgb;
        input [7:0] c;
        begin rgb={c[7:5],c[7],c[4:2],c[4],c[1:0],c[1:0]};end
    endfunction
    task scan_from;
        input integer x,y;
        begin @(negedge clk);screen.timing.x_r=x;screen.timing.y_r=y;screen.timing.pdiv=0;end
    endtask
    task check_pixel;
        input [11:0] expected;
        begin
            repeat(4)@(negedge clk);
            if({r,g,b}!==expected)$fatal(1,"VGA %03x expected %03x near (%d,%d)",{r,g,b},expected,screen.x,screen.y);
        end
    endtask
    reg [15:0] crc;
    reg [11:0] base,ink;
    integer colored,px,bitn;
    initial begin
        if(!$value$plusargs("BMP=%s",path))path="tf_card/IMAGES/BG.BMP";
        fd=$fopen(path,"rb");if(!fd)$fatal(1,"cannot open BMP: %0s, set +BMP=<path>",path);
        for(i=0;i<LIMIT*512;i=i+1)disk[i]=0;
        sz=$fread(disk,fd,FILE0,LIMIT*512-FILE0);$fclose(fd);
        if(sz<230454 || {disk[FILE0],disk[FILE0+1]}!="BM")$fatal(1,"bad fixture BMP");
        off=read32(FILE0+10);height=read32(FILE0+22);
        if(read32(FILE0+18)!=320 || (height!=240 && height!=-240) || sz-off<230400)
            $fatal(1,"fixture image has unsupported size");
        disk[0]=8'heb;disk[12]=2;disk[13]=8;disk[14]=32;disk[16]=1;
        le32(32,540000);le32(36,600);le32(44,2);disk[510]=8'h55;disk[511]=8'haa;
        for(i=2;i<=5;i=i+1)le32(FAT*512+4*i,32'h0fffffff);
        clusters=(sz+4095)/4096;
        for(i=0;i<clusters;i=i+1)le32(FAT*512+4*(10+i),(i==clusters-1)?32'h0fffffff:11+i);
        dirent(DATA*512,"IMAGES     ",16,3,0);dirent(DATA*512+32,"LOGS       ",16,4,0);
        dirent((DATA+8)*512,"BG      BMP",32,10,sz);dirent((DATA+16)*512,"ENVLOG  BIN",32,5,1024);

        repeat(5)@(negedge clk);rst=0;
        // The sensors finish at different times. Queue the paired snapshot
        // while the card is still busy streaming the background.
        @(negedge clk);th_valid=1;@(negedge clk);th_valid=0;
        repeat(6)@(negedge clk);ls_valid=1;@(negedge clk);ls_valid=0;
        repeat(3)@(negedge clk);tick=1;@(negedge clk);tick=0;
        wait(queued);if(status!=3 || level!=2 || src!=1)$fatal(1,"snapshot/alarm mismatch");
        wait(pop);repeat(3)@(negedge clk);
        if(!bg_ready || !fs_ready || full || rendered!=76800 || committed!=1 || queued)
            $fatal(1,"image/log completion failed");
        // Every stored RGB332 pixel is checked against the original file bytes.
        colored=0;
        for(n=0;n<76800;n=n+1)begin
            if(screen.background[n]!==golden(n%320,n/320))$fatal(1,"BRAM mismatch at %d",n);
            if(screen.background[n]!=0)colored=colored+1;
        end
        if(colored==0)$fatal(1,"delivered background contains no visible colors");
        if({disk[LOG0],disk[LOG0+1],disk[LOG0+2],disk[LOG0+3]}!="ENV1" ||
           read32(LOG0+4)!=42 || {disk[LOG0+9],disk[LOG0+8]}!=253 ||
           {disk[LOG0+11],disk[LOG0+10]}!=550 || {disk[LOG0+13],disk[LOG0+12]}!=320 ||
           disk[LOG0+14]!=3 || disk[LOG0+15]!=2 || disk[LOG0+16]!=1 || disk[LOG0+17]!=1 ||
           {disk[LOG0+19],disk[LOG0+18]}!=124)$fatal(1,"sensor values in ENVLOG.BIN");
        crc=16'hffff;
        for(i=0;i<20;i=i+1)for(bitn=7;bitn>=0;bitn=bitn-1)
            crc=(crc[15]^disk[LOG0+i][bitn]) ? ((crc<<1)^16'h1021) : (crc<<1);
        if({disk[LOG0+509],disk[LOG0+508]}!==crc || {disk[LOG0+510],disk[LOG0+511]}!=16'ha55a)
            $fatal(1,"log block CRC or commit mark");
        // Jump to vblank to avoid simulating an entire idle frame; the real
        // scan counters and pixel/BRAM pipelines still run during each line.
        scan_from(0,480);repeat(60)@(negedge clk);
        if(screen.temp_text!=="    25.3 C" || screen.humi_text!=="    55.0 %" ||
           screen.light_text!=="    320 lx")$fatal(1,"live numeric formatting");
        scan_from(24,30);check_pixel(rgb(golden(12,15)));check_pixel(rgb(golden(12,15)));
        scan_from(24,31);check_pixel(rgb(golden(12,15)));
        scan_from(63,112);
        for(px=63;px<=168;px=px+1)begin
            base=rgb(golden(px/2,56));
            ink=(base[7] && (base[11]||base[3])) ? 12'h700 : 12'hfc4;
            // At y=112 the fourth character (x=160..183) is the first digit
            // '2'. Its first foreground pixel is column 2 (x=166).
            check_pixel(px>=166 ? ink : base);
        end
        $display("DASHBOARD_PIPELINE TEST PASSED: %0d file bytes, 76800 BRAM pixels, VGA overlay and logged sensor CRC",sz);
        $finish;
    end
endmodule
