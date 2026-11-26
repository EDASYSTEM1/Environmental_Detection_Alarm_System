// FAT32 reader with in-place, bounded logging. The host owns the FAT and all
// directory entries. Only an all-zero data sector inside the preallocated
// /LOGS/ENVLOG.BIN is ever eligible for a write.
module fat32_store (
    input wire clk, rst, card_ready,
    output reg cmd_valid, cmd_write,
    output reg [31:0] cmd_lba,
    input wire cmd_ready, blk_done, blk_error,
    output reg [8:0] buf_addr,
    input wire [7:0] buf_rdata,
    output reg buf_we,
    output reg [7:0] buf_wdata,
    output reg bmp_valid,
    output reg [7:0] bmp_data,
    output reg bmp_start, bmp_end,
    input wire log_valid,
    input wire [127:0] log_data,
    output reg log_pop, fs_ready, log_full, fs_error, bg_missing
);
    localparam START=0, ISSUE=1, WAIT_IO=2, PRIME=3, STREAM=4,
        BOOT_CHECK=5, GEOMETRY=6, GEOMETRY_CHECK=7, BEGIN_DIR=8,
        READ_DATA=9, ENTRY_FOUND=10, NOT_FOUND=11, ADVANCE=12,
        FAT_DONE=13, LOG_SLOT=14, FILL_LOG=15, SUBMIT_LOG=16,
        LOG_SCANNED=17, STOPPED=18, FAIL=19, CHECK_EXTENT=20,
        FORM_BASES=21, COUNT_CLUSTERS=22, LAST_CLUSTER=23,
        SCALE_CLUSTER=24, ADD_DATA_BASE=25, ISSUE_DATA=26;
    localparam OP_BOOT=0, OP_DIR=1, OP_IMAGE=2, OP_LOG=3, OP_FAT=4;
    localparam FIND_IMAGES=0, FIND_BG=1, FIND_LOGS=2, FIND_LOG=3;
    reg [4:0] state;
    reg [2:0] op, data_op;
    reg [1:0] target;
    reg [8:0] ix;
    reg [31:0] volume_start, partition_sectors;
    reg partitioned, part_found;
    reg [7:0] part_type, jump, spc, fats, attributes;
    reg [31:0] part_lba, part_len, total, fat_size, root;
    reg [15:0] bytes_per_sector, reserved, root_entries, fat16, total16, boot_sig, flags;
    reg [2:0] cluster_shift;
    reg [31:0] fat_lba, data_lba, max_cluster, cluster, dir_start;
    reg [31:0] cluster_budget, remaining, next_cluster;
    reg [32:0] relative_data_start, absolute_end, partition_stop;
    reg [31:0] first_fat_lba, data_sectors, cluster_count;
    reg [31:0] cluster_index, sector_offset, cluster_start_lba;
    reg [7:0] sec_in_cluster;
    reg [87:0] short_name;
    reg [31:0] entry_cluster, entry_size;
    reg any_byte;
    reg [31:0] available_lba;
    reg [127:0] record;
    reg [15:0] crc;

    wire [87:0] expected_name = (target==FIND_IMAGES) ? "IMAGES     " :
                                 (target==FIND_BG) ? "BG      BMP" :
                                 (target==FIND_LOGS) ? "LOGS       " : "ENVLOG  BIN";
    wire need_directory = target==FIND_IMAGES || target==FIND_LOGS;
    wire spc_ok = spc!=0 && ((spc & (spc-8'd1))==0);
    wire [32:0] fat_area = (fats==2) ? {fat_size,1'b0} : {1'b0,fat_size};
    wire [8:0] fat_offset = {cluster[6:0],2'b00};
    wire [3:0] mbr_offset = ix[3:0]-4'd14; // entries start at 446

    function [15:0] crc_byte;
        input [15:0] old;
        input [7:0] value;
        integer i;
        reg [15:0] c;
        begin
            c=old ^ {value,8'h0};
            for(i=0;i<8;i=i+1) c=c[15] ? ((c<<1)^16'h1021) : (c<<1);
            crc_byte=c;
        end
    endfunction
    reg [7:0] out_byte;
    always @* begin
        case(ix)
            0: out_byte="E";
            1: out_byte="N";
            2: out_byte="V";
            3: out_byte="1";
            508: out_byte=crc[7:0];
            509: out_byte=crc[15:8];
            510: out_byte=8'ha5;
            511: out_byte=8'h5a;
            default: out_byte=(ix>=4 && ix<20) ? record[7:0] : 8'h00;
        endcase
    end

    task read_sector;
        input [31:0] address;
        input [2:0] purpose;
        begin
            cmd_lba<=address; cmd_write<=0; cmd_valid<=1;
            op<=purpose; state<=ISSUE;
        end
    endtask
    task start_directory;
        input [31:0] start_cl;
        input [1:0] name_to_find;
        begin
            target<=name_to_find; dir_start<=start_cl; state<=BEGIN_DIR;
        end
    endtask

    always @(posedge clk) begin
        buf_we<=0; bmp_start<=0; bmp_valid<=0; bmp_end<=0; log_pop<=0;
        if(rst || !card_ready) begin
            state<=START; cmd_valid<=0; cmd_write<=0; cmd_lba<=0;
            fs_ready<=0; fs_error<=0; log_full<=0; bg_missing<=0;
            volume_start<=0; partition_sectors<=0; partitioned<=0;
            part_found<=0; buf_addr<=0; buf_wdata<=0; bmp_data<=0;
        end else case(state)
            START: read_sector(0,OP_BOOT);
            ISSUE: if(cmd_ready) begin cmd_valid<=0; state<=WAIT_IO; end
            WAIT_IO: begin
                if(blk_error) state<=FAIL;
                else if(blk_done) begin
                    if(cmd_write) begin
                        log_pop<=1;
                        if(remaining==512) begin log_full<=1; state<=STOPPED; end
                        else begin remaining<=remaining-512; state<=ADVANCE; end
                    end else begin
                        ix<=0; buf_addr<=0; any_byte<=0; state<=PRIME;
                    end
                end
            end
            // Registered BRAM read. While consuming byte i, BRAM is sampling
            // address i+1. The registered address output is driven to i+2.
            PRIME: begin buf_addr<=1; state<=STREAM; end
            STREAM: begin
                ix<=ix+1'b1;
                buf_addr<=buf_addr+1'b1;
                case(op)
                    OP_BOOT: begin
                        case(ix)
                            0: jump<=buf_rdata;
                            11: bytes_per_sector[7:0]<=buf_rdata;
                            12: bytes_per_sector[15:8]<=buf_rdata;
                            13: spc<=buf_rdata;
                            14: reserved[7:0]<=buf_rdata;
                            15: reserved[15:8]<=buf_rdata;
                            16: fats<=buf_rdata;
                            17: root_entries[7:0]<=buf_rdata;
                            18: root_entries[15:8]<=buf_rdata;
                            19: total16[7:0]<=buf_rdata;
                            20: total16[15:8]<=buf_rdata;
                            22: fat16[7:0]<=buf_rdata;
                            23: fat16[15:8]<=buf_rdata;
                            32,33,34,35: total<={buf_rdata,total[31:8]};
                            36,37,38,39: fat_size<={buf_rdata,fat_size[31:8]};
                            40: flags[7:0]<=buf_rdata;
                            41: flags[15:8]<=buf_rdata;
                            44,45,46,47: root<={buf_rdata,root[31:8]};
                            510: boot_sig[7:0]<=buf_rdata;
                            511: begin boot_sig[15:8]<=buf_rdata; state<=BOOT_CHECK; end
                        endcase
                        if(!partitioned && ix>=446 && ix<510) begin
                            case(mbr_offset)
                                4: part_type<=buf_rdata;
                                8,9,10,11: part_lba<={buf_rdata,part_lba[31:8]};
                                12,13,14: part_len<={buf_rdata,part_len[31:8]};
                                15: if(!part_found && (part_type==8'h0b || part_type==8'h0c ||
                                     part_type==8'h1b || part_type==8'h1c) && part_lba!=0) begin
                                    // Keep the selected partition independent of later entries.
                                    partition_sectors<={buf_rdata,part_len[31:8]};
                                    dir_start<=part_lba; part_found<=1;
                                end
                            endcase
                        end
                    end
                    OP_DIR: begin
                        if(ix[4:0]<=10) short_name<={short_name[79:0],buf_rdata};
                        case(ix[4:0])
                            0: if(buf_rdata==0) state<=NOT_FOUND;
                            11: attributes<=buf_rdata;
                            20: entry_cluster[23:16]<=buf_rdata;
                            21: entry_cluster[31:24]<={4'b0,buf_rdata[3:0]};
                            26: entry_cluster[7:0]<=buf_rdata;
                            27: entry_cluster[15:8]<=buf_rdata;
                            28,29,30: entry_size<={buf_rdata,entry_size[31:8]};
                            31: begin
                                entry_size<={buf_rdata,entry_size[31:8]};
                                if(short_name==expected_name && !attributes[3] &&
                                   attributes[4]==need_directory) state<=ENTRY_FOUND;
                                else if(ix==511) state<=ADVANCE;
                            end
                        endcase
                    end
                    OP_IMAGE: begin
                        bmp_valid<=1; bmp_data<=buf_rdata;
                        if(remaining==1) begin
                            bmp_end<=1; start_directory(root,FIND_LOGS);
                        end else begin
                            remaining<=remaining-1;
                            if(ix==511) state<=ADVANCE;
                        end
                    end
                    OP_LOG: begin
                        any_byte<=any_byte | (buf_rdata!=0);
                        if(ix==511) state<=LOG_SCANNED;
                    end
                    OP_FAT: begin
                        if(ix[8:2]==fat_offset[8:2]) begin
                            case(ix[1:0])
                                0: next_cluster[7:0]<=buf_rdata;
                                1: next_cluster[15:8]<=buf_rdata;
                                2: next_cluster[23:16]<=buf_rdata;
                                3: begin next_cluster[31:24]<={4'b0,buf_rdata[3:0]}; state<=FAT_DONE; end
                            endcase
                        end
                    end
                endcase
            end
            BOOT_CHECK: begin
                if(boot_sig!=16'haa55) state<=FAIL;
                else if((jump==8'heb || jump==8'he9) && bytes_per_sector==512 &&
                         spc_ok && reserved!=0 && (fats==1 || fats==2) &&
                         root_entries==0 && fat16==0 && total16==0 &&
                         total!=0 && fat_size!=0) begin
                    case(spc)
                        1: cluster_shift<=0; 2: cluster_shift<=1;
                        4: cluster_shift<=2; 8: cluster_shift<=3;
                        16: cluster_shift<=4; 32: cluster_shift<=5;
                        64: cluster_shift<=6; default: cluster_shift<=7;
                    endcase
                    state<=GEOMETRY;
                end else if(!partitioned && part_found && partition_sectors!=0) begin
                    volume_start<=dir_start; partitioned<=1;
                    read_sector(dir_start,OP_BOOT);
                end else state<=FAIL;
            end
            GEOMETRY: begin
                // Separate carry chains, variable shifts and comparisons across clocks.
                // A few setup cycles are negligible compared with a sector transfer.
                relative_data_start<=fat_area+{17'b0,reserved};
                first_fat_lba<=volume_start+reserved;
                absolute_end<={1'b0,volume_start}+{1'b0,total};
                partition_stop<={1'b0,volume_start}+{1'b0,partition_sectors};
                state<=CHECK_EXTENT;
            end
            CHECK_EXTENT: begin
                if(relative_data_start>=total || absolute_end>33'h100000000 ||
                   (partitioned && (total>partition_sectors || partition_stop>33'h100000000)) ||
                   (flags[7] && flags[3:0]>=fats)) state<=FAIL;
                else state<=FORM_BASES;
            end
            FORM_BASES: begin
                fat_lba<=first_fat_lba+((flags[7] && flags[0])?fat_size:0);
                data_lba<=volume_start+relative_data_start[31:0];
                data_sectors<=total-relative_data_start[31:0];
                state<=COUNT_CLUSTERS;
            end
            COUNT_CLUSTERS: begin cluster_count<=data_sectors>>cluster_shift; state<=LAST_CLUSTER; end
            LAST_CLUSTER: begin max_cluster<=cluster_count+1; state<=GEOMETRY_CHECK; end
            GEOMETRY_CHECK: begin
                if(root<2 || root>max_cluster || max_cluster>=32'h0ffffff0 ||
                   (max_cluster>>7)>=fat_size) state<=FAIL;
                else start_directory(root,FIND_IMAGES);
            end
            BEGIN_DIR: begin
                cluster<=dir_start; sec_in_cluster<=0; cluster_budget<=max_cluster-1;
                data_op<=OP_DIR; state<=READ_DATA;
            end
            READ_DATA: begin cluster_index<=cluster-2; state<=SCALE_CLUSTER; end
            SCALE_CLUSTER: begin sector_offset<=cluster_index<<cluster_shift; state<=ADD_DATA_BASE; end
            ADD_DATA_BASE: begin cluster_start_lba<=data_lba+sector_offset; state<=ISSUE_DATA; end
            ISSUE_DATA: read_sector(cluster_start_lba+sec_in_cluster,data_op);
            ENTRY_FOUND: begin
                if(target==FIND_BG && entry_size==0) state<=NOT_FOUND;
                else if(entry_cluster<2 || entry_cluster>max_cluster) state<=FAIL;
                else case(target)
                    FIND_IMAGES: start_directory(entry_cluster,FIND_BG);
                    FIND_LOGS:   start_directory(entry_cluster,FIND_LOG);
                    default: begin
                        cluster<=entry_cluster; sec_in_cluster<=0; cluster_budget<=max_cluster-1;
                        remaining<=entry_size;
                        if(target==FIND_BG) begin bmp_start<=1; data_op<=OP_IMAGE; state<=READ_DATA; end
                        else if(entry_size<512 || entry_size[8:0]!=0 || attributes[0]) state<=FAIL;
                        else begin data_op<=OP_LOG; state<=READ_DATA; end
                    end
                endcase
            end
            NOT_FOUND: begin
                if(target==FIND_IMAGES || target==FIND_BG) begin
                    bg_missing<=1; start_directory(root,FIND_LOGS);
                end else state<=FAIL;
            end
            ADVANCE: begin
                if(sec_in_cluster+1'b1<spc) begin sec_in_cluster<=sec_in_cluster+1'b1; state<=READ_DATA; end
                else read_sector(fat_lba+(cluster>>7),OP_FAT);
            end
            FAT_DONE: begin
                if(next_cluster>=32'h0ffffff8 && data_op==OP_DIR) state<=NOT_FOUND;
                else if(next_cluster<2 || next_cluster>max_cluster || next_cluster==cluster ||
                        cluster_budget<=1) state<=FAIL;
                else begin cluster<=next_cluster; sec_in_cluster<=0; cluster_budget<=cluster_budget-1; state<=READ_DATA; end
            end
            LOG_SCANNED: begin
                if(!any_byte) begin available_lba<=cmd_lba; fs_ready<=1; state<=LOG_SLOT; end
                else if(remaining==512) begin fs_ready<=1; log_full<=1; state<=STOPPED; end
                else begin remaining<=remaining-512; state<=ADVANCE; end
            end
            LOG_SLOT: if(log_valid) begin record<=log_data; crc<=16'hffff; ix<=0; state<=FILL_LOG; end
            FILL_LOG: begin
                buf_addr<=ix; buf_we<=1; buf_wdata<=out_byte;
                if(ix<20) crc<=crc_byte(crc,out_byte);
                if(ix>=4 && ix<20) record<={8'b0,record[127:8]};
                ix<=ix+1'b1;
                if(ix==511) state<=SUBMIT_LOG;
            end
            SUBMIT_LOG: begin
                cmd_lba<=available_lba; cmd_write<=1; cmd_valid<=1; state<=ISSUE;
            end
            FAIL: begin fs_error<=1; fs_ready<=0; end
            STOPPED: begin end
            default: state<=FAIL;
        endcase
    end
endmodule
