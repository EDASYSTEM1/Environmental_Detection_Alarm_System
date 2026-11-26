`timescale 1ns/1ps
// Sector-level integration test. FAT32 media is sparse: the unused tail of
// the declared volume is never read. Cluster chains deliberately have holes.
module tb_fat32_store;
    reg clk=0; always #5 clk=~clk;
    reg rst=1, card_ready=0, blk_done=0, blk_error=0;
    wire cmd_valid,cmd_write;
    wire [31:0] cmd_lba;
    reg busy=0, fail_write=0;
    wire cmd_ready=!busy;
    wire [8:0] buf_addr;
    wire buf_we; wire [7:0] buf_wdata;
    reg [7:0] buf_rdata;
    reg [7:0] ram[0:511];
    reg [7:0] disk[0:799*512-1];
    reg log_valid=0; reg [127:0] log_data=128'h100f0e0d0c0b0a090807060504030201;
    wire bmp_start,bmp_end,bmp_valid,log_pop,fs_ready,log_full,fs_error,bg_missing;
    wire [7:0] bmp_data;
    fat32_store dut(clk,rst,card_ready,cmd_valid,cmd_write,cmd_lba,cmd_ready,
        blk_done,blk_error,buf_addr,buf_rdata,buf_we,buf_wdata,
        bmp_valid,bmp_data,bmp_start,bmp_end,log_valid,log_data,log_pop,
        fs_ready,log_full,fs_error,bg_missing);

    integer k, block, latency; reg writing;
    integer writes=0, bytes_seen=0, pictures=0, pops=0, ticks=0;
    reg picture_open=0;
    always @(posedge clk) begin
        ticks=ticks+1;
        if(ticks>250000) $fatal(1,"FAT test timeout, state=%d op=%d",dut.state,dut.op);
        if(buf_we) ram[buf_addr]<=buf_wdata;
        buf_rdata<=ram[buf_addr];
        blk_done<=0;blk_error<=0;
        if(cmd_valid && cmd_ready) begin
            if(cmd_lba>=799) $fatal(1,"unexpected physical LBA %d",cmd_lba);
            block<=cmd_lba;writing<=cmd_write;latency<=4;busy<=1;
        end
        if(busy) begin
            if(latency!=0) latency<=latency-1;
            else begin
                if(writing && fail_write) blk_error<=1;
                else begin
                    for(k=0;k<512;k=k+1)
                        if(writing) disk[block*512+k]<=ram[k];
                        else ram[k]<=disk[block*512+k];
                    blk_done<=1;
                    if(writing) writes=writes+1;
                end
                busy<=0;
            end
        end
        if(bmp_start) begin bytes_seen=0;picture_open=1;end
        if(bmp_valid) begin
            if(!picture_open || bmp_data!==((bytes_seen*7+29)&255))
                $fatal(1,"fragmented image byte mismatch at %d: %h",bytes_seen,bmp_data);
            bytes_seen=bytes_seen+1;
        end
        if(bmp_end) begin
            if(bytes_seen!=527 || !bmp_valid) $fatal(1,"wrong BMP length");
            pictures=pictures+1;picture_open=0;
        end
        if(log_pop)pops=pops+1;
    end
    integer vol0, first_fat, data_base, sectors_per_cluster;
    function integer cl_lba;
        input integer cl;
        begin cl_lba=data_base+(cl-2)*sectors_per_cluster;end
    endfunction
    task put32;
        input integer off; input [31:0] v;
        begin
            disk[off]=v[7:0];disk[off+1]=v[15:8];disk[off+2]=v[23:16];disk[off+3]=v[31:24];
        end
    endtask
    task fat;
        input integer cl,n;
        begin put32(first_fat*512+4*cl,n);end
    endtask
    task entry;
        input integer lba,slot; input [87:0] name; input [7:0] att;
        input integer cl,sz;
        integer o,j;
        begin
            o=lba*512+slot*32;
            for(j=0;j<11;j=j+1)disk[o+j]=name[87-j*8 -: 8];
            disk[o+11]=att; disk[o+20]=cl>>16;disk[o+21]=cl>>24;
            disk[o+26]=cl; disk[o+27]=cl>>8;put32(o+28,sz);
        end
    endtask
    task prepare;
        input integer partition_base,spc_value;
        integer i,t,b,m;
        begin
            vol0=partition_base;sectors_per_cluster=spc_value;first_fat=vol0+8;data_base=first_fat+600;
            for(i=0;i<799*512;i=i+1)disk[i]=0;
            if(vol0!=0)begin
                // A non-FAT partition precedes the actual FAT32 partition.
                disk[450]=8'h83;put32(454,1);put32(458,5);
                disk[466]=8'h0c;put32(470,vol0);put32(474,136000);
                disk[510]=8'h55;disk[511]=8'haa;
            end
            b=vol0*512;disk[b]=8'heb;disk[b+12]=2;disk[b+13]=spc_value;
            disk[b+14]=8;disk[b+16]=1;put32(b+32,68000*spc_value);
            put32(b+36,600);put32(b+44,2);disk[b+510]=8'h55;disk[b+511]=8'haa;
            fat(2,6);fat(6,32'h0fffffff);fat(4,32'h0ffffff8);fat(5,32'h0fffffff);
            fat(9,7);fat(7,32'h0fffffff);fat(11,13);fat(13,17);fat(17,32'h0fffffff);
            for(t=0;t<spc_value;t=t+1)
                for(i=0;i<16;i=i+1)disk[(cl_lba(2)+t)*512+i*32]=8'he5;
            entry(cl_lba(2),2,"LOGS       ",8'h0f,24,0);
            entry(cl_lba(6),0,"IMAGES     ",8'h10,4,0);
            entry(cl_lba(6),1,"LOGS       ",8'h10,5,0);
            entry(cl_lba(4),0,"BG      BMP",8'h20,9,527);
            entry(cl_lba(5),0,"ENVLOG  BIN",8'h20,11,1536);
            for(i=0;i<527;i=i+1)begin
                m=(i>=512 && spc_value==1) ? cl_lba(7)*512+i-512 : cl_lba(9)*512+i;
                disk[m]=(i*7+29)&255;
            end
            // Last byte only is non-zero: this torn sector must never be overwritten.
            disk[cl_lba(11)*512+511]=8'h71;
        end
    endtask
    task remount;
        begin
            @(negedge clk);card_ready=0;log_valid=0;rst=1;repeat(4)@(negedge clk);
            rst=0;card_ready=1;
        end
    endtask
    task write_once;
        begin
            @(negedge clk);log_valid=1;
            wait(log_pop);@(negedge clk);log_valid=0;@(negedge clk);
        end
    endtask
    task check_record;
        input integer lba;
        integer o,i,j;reg [15:0] c;
        begin
            o=lba*512;
            if({disk[o],disk[o+1],disk[o+2],disk[o+3]}!="ENV1")$fatal(1,"missing magic in LBA %d",lba);
            for(i=0;i<16;i=i+1)if(disk[o+4+i]!==log_data[i*8 +: 8])$fatal(1,"payload %d",i);
            c=16'hffff;
            for(i=0;i<20;i=i+1)for(j=7;j>=0;j=j-1)
                c=(c[15]^disk[o+i][j]) ? ((c<<1)^16'h1021) : (c<<1);
            if({disk[o+509],disk[o+508]}!==c || disk[o+510]!==8'ha5 || disk[o+511]!==8'h5a)
                $fatal(1,"bad CRC/trailer");
        end
    endtask
    integer count_before;
    initial begin
        prepare(7,1);remount();wait(fs_ready || fs_error);
        if(fs_error || pictures!=1 || bg_missing) $fatal(1,"MBR mount failed");
        write_once();check_record(cl_lba(13));
        if(writes!=1 || disk[cl_lba(11)*512+511]!=8'h71)$fatal(1,"torn sector overwritten");
        remount();wait(fs_ready || fs_error);if(fs_error || pictures!=2)$fatal(1,"remount failed");
        log_data=~log_data;write_once();check_record(cl_lba(17));wait(log_full);
        if(writes!=2 || pops!=2)$fatal(1,"wrong append/full handling");
        // Remount a full file must not write, even with pending data.
        remount();log_valid=1;wait(log_full || fs_error);if(fs_error || writes!=2)$fatal(1,"full file overwrite");
        @(negedge clk);card_ready=0;log_valid=0;
        prepare(0,2);remount();wait(fs_ready||fs_error);if(fs_error)$fatal(1,"superfloppy, two-sector clusters");
        write_once();check_record(cl_lba(11)+1);
        // Fail the next SD write: FIFO head must be retained.
        fail_write=1;count_before=pops;
        @(negedge clk);log_valid=1;wait(fs_error);repeat(3)@(negedge clk);
        if(pops!=count_before || disk[cl_lba(13)*512]!=0)$fatal(1,"failed write consumed data");
        fail_write=0;card_ready=0;log_valid=0;
        // An optional missing image still permits logging. A broken file chain must fail closed.
        prepare(0,1);disk[cl_lba(4)*512]=0;fat(11,32'h0fffffff);
        remount();wait(fs_error);if(!bg_missing)$fatal(1,"missing image status");
        if(writes!=3)$fatal(1,"unexpected write to truncated file");
        $display("FAT32_STORE TEST PASSED");$finish;
    end
endmodule
