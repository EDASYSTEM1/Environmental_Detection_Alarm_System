`timescale 1ns/1ps
// Wire-level card stimulus; the card and host share no implementation state.
module tb_sd_spi_block;
    reg clk=0, rst=1, miso=1;
    always #5 clk = ~clk;
    wire cs,sck,mosi,card_ready,init_error,cmd_ready,done,error;
    reg valid=0,wr=0,we=0;
    reg [31:0] lba=0;
    reg [8:0] addr=0;
    reg [7:0] wdata=0;
    wire [7:0] rdata;
    sd_spi_block #(.POWERUP_CYCLES(7),.INIT_HALF_DIV(4),.DATA_HALF_DIV(2),
        .DATA_WAIT_BYTES(16),.BUSY_WAIT_BYTES(5)) dut (
        .clk(clk),.rst(rst),.sd_cs(cs),.sd_sck(sck),.sd_mosi(mosi),.sd_miso(miso),
        .card_ready(card_ready),.init_error(init_error),.cmd_ready(cmd_ready),
        .cmd_valid(valid),.cmd_write(wr),.cmd_lba(lba),.blk_done(done),.blk_error(error),
        .buf_addr(addr),.buf_wdata(wdata),.buf_we(we),.buf_rdata(rdata)
    );
    integer errors=0, startup_clocks=0;
    reg startup=1;
    always @(posedge sck) if (cs && startup) begin
        startup_clocks=startup_clocks+1;
        if (mosi!==1'b1) begin $display("MOSI during startup");errors=errors+1;end
    end
    always @(posedge cs) miso=1'b1;
    task check;
        input okay; input [319:0] why;
        begin if(okay!==1'b1) begin $display("FAIL: %0s",why); errors=errors+1; end end
    endtask
    function [7:0] pattern;
        input integer index;
        begin pattern=(index*29)^(index>>3)^8'ha5; end
    endfunction
    function [15:0] crc16;
        input [15:0] start; input [7:0] value;
        integer i; reg [15:0] crc;
        begin
            crc=start ^ {value,8'h00};
            for (i=0;i<8;i=i+1) crc=crc[15] ? (crc<<1)^16'h1021 : (crc<<1);
            crc16=crc;
        end
    endfunction
    function [7:0] crc7;
        input [39:0] cmd;
        reg [46:0] dividend; integer i;
        begin
            dividend={cmd,7'd0};
            for (i=46;i>=7;i=i-1)
                if (dividend[i]) dividend=dividend^(47'h89<<(i-7));
            crc7={dividend[6:0],1'b1};
        end
    endfunction
    task recv_byte;
        output [7:0] b; integer i;
        begin for(i=7;i>=0;i=i-1) begin @(posedge sck); b[i]=mosi; end end
    endtask
    task send_byte;
        input [7:0] b; integer i;
        begin
            for(i=7;i>=0;i=i-1) begin
                @(negedge sck); miso=b[i]; @(posedge sck);
            end
        end
    endtask
    task expect_command;
        input [5:0] index; input [31:0] argument;
        reg [47:0] pkt; reg [7:0] b; integer i;
        begin
            @(negedge cs);
            for(i=0;i<6;i=i+1) begin recv_byte(b); pkt={pkt[39:0],b}; end
            check(pkt[47:40]=={2'b01,index},"command index");
            check(pkt[39:8]==argument,"command LBA/argument");
            check(pkt[7:0]==crc7(pkt[47:8]),"command CRC7");
        end
    endtask
    task read_reply;
        input corrupt;
        reg [15:0] crc; reg [7:0] b; integer i;
        begin
            send_byte(8'hff);send_byte(0);send_byte(8'hff);send_byte(8'hfe);
            crc=0;
            for(i=0;i<512;i=i+1)begin
                b=pattern(i);send_byte(b);crc=crc16(crc,b);
            end
            send_byte(crc[15:8]);send_byte(crc[7:0]^{7'd0,corrupt});
        end
    endtask
    task receive_write;
        reg [15:0] crc; reg [7:0] b; integer i;
        begin
            send_byte(0);recv_byte(b);check(b==8'hff,"pre-write idle byte");
            recv_byte(b);check(b==8'hfe,"write token");
            crc=0;
            for(i=0;i<512;i=i+1)begin
                recv_byte(b);check(b===~pattern(i),"write bytes / RAM latency");crc=crc16(crc,b);
            end
            recv_byte(b);check(b==crc[15:8],"write CRC16 high");
            recv_byte(b);check(b==crc[7:0],"write CRC16 low");
        end
    endtask
    reg card_finished=0;
    initial begin : card
        expect_command(0,0);check(startup_clocks>=74,"power-up clocks");startup=0;send_byte(1);
        expect_command(8,32'h1aa);send_byte(1);send_byte(0);send_byte(0);send_byte(1);send_byte(8'haa);
        expect_command(55,0);send_byte(1);
        expect_command(41,32'h40000000);send_byte(1);
        expect_command(55,0);send_byte(1);
        expect_command(41,32'h40000000);send_byte(0);
        expect_command(58,0);send_byte(0);send_byte(8'hc0);send_byte(8'hff);send_byte(8'h80);send_byte(0);
        expect_command(17,32'h12345);read_reply(0);
        expect_command(24,32'h20002);receive_write;
        send_byte(8'h05);send_byte(0);send_byte(0);send_byte(8'hff);
        expect_command(13,0);send_byte(0);send_byte(0);
        expect_command(17,32'h12345);read_reply(1);
        expect_command(24,32'h20002);receive_write;send_byte(8'h0b); // CRC rejected
        expect_command(17,32'h0);send_byte(0);repeat(16) send_byte(8'hff); // token timeout
        expect_command(24,32'h20002);receive_write;send_byte(8'h05);repeat(5) send_byte(0);
        // Unsupported capacity: reject a legacy card after the next reset.
        expect_command(0,0);send_byte(1);expect_command(8,32'h1aa);send_byte(5);
        card_finished=1;
    end
    task transact;
        input is_write;input [31:0] sector;input should_fail;
        begin
            while(!cmd_ready) @(negedge clk);
            @(negedge clk);valid=1;wr=is_write;lba=sector;
            @(negedge clk);valid=0;
            while(!done) @(negedge clk);
            check(error===should_fail,"transaction completion/error");
        end
    endtask
    integer i;
    initial begin : host
        repeat(7) @(negedge clk);rst=0;
        wait(card_ready || init_error);check(card_ready && !init_error,"SDHC initialization");
        transact(0,32'h12345,0);
        for(i=0;i<512;i=i+1)begin
            @(negedge clk);addr=i;@(posedge clk);#1;
            check(rdata===pattern(i),"read bytes / host RAM latency");
        end
        for(i=0;i<512;i=i+1)begin
            @(negedge clk);addr=i;we=1;wdata=~pattern(i);
        end
        @(negedge clk);we=0;
        transact(1,32'h20002,0);
        transact(0,32'h12345,1);
        // A CRC-failed read overwrote RAM with untrusted bytes; refill before writing.
        for(i=0;i<512;i=i+1)begin
            @(negedge clk);addr=i;we=1;wdata=~pattern(i);
        end
        @(negedge clk);we=0;
        transact(1,32'h20002,1);
        transact(0,0,1);
        transact(1,32'h20002,1);
        @(negedge clk);rst=1;repeat(5)@(negedge clk);rst=0;
        wait(init_error);check(!card_ready && card_finished,"unsupported card rejected");
        if(errors) $fatal(1,"SD SPI TEST FAILED (%0d)",errors);
        $display("SD SPI TEST PASSED");$finish;
    end
    initial begin #5_000_000; $fatal(1,"SD SPI simulation timed out"); end
endmodule
