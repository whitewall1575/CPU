`timescale 1ns / 1ps

`include "defines.vh"

module DCache (
    input  wire         cpu_rstn,
    input  wire         cpu_clk,
    // CPU read interface
    input  wire [ 3:0]  data_ren,
    input  wire [31:0]  data_addr,
    output reg          data_valid,
    output reg  [31:0]  data_rdata,
    // CPU write interface
    input  wire [ 3:0]  data_wen,
    input  wire [31:0]  data_wdata,
    output reg          data_wresp,
    // Write-bus interface
    input  wire         dev_wrdy,
    output reg  [ 3:0]  cpu_wen,
    output reg  [31:0]  cpu_waddr,
    output reg  [31:0]  cpu_wdata,
    // Read-bus interface
    input  wire         dev_rrdy,
    output reg  [ 3:0]  cpu_ren,
    output reg  [31:0]  cpu_raddr,
    input  wire         dev_rvalid,
    input  wire [31:0]  dev_rdata
);

`ifdef ENABLE_DCACHE

    localparam NLINES    = 32;
    localparam NWORDS    = 8;
    localparam RAM_DEPTH = NLINES * NWORDS;
    localparam PERI_SEG = 16'hBFAF;

    reg [NLINES-1:0] dc_valid;
    (* ram_style = "distributed" *) reg [21:0] dc_tag  [0:NLINES-1];
    (* ram_style = "block" *)       reg [31:0] dc_data [0:RAM_DEPTH-1];

    wire        cacheable = (data_addr[31:16] != PERI_SEG);
    wire [21:0] a_tag     = data_addr[31:10];
    wire [ 4:0] a_idx     = data_addr[ 9: 5];
    wire [ 2:0] a_off     = data_addr[ 4: 2];
    wire        d_hit     = cacheable & dc_valid[a_idx] & (dc_tag[a_idx] == a_tag);
    wire [ 7:0] a_ram_addr = {a_idx, a_off};

    localparam RS_IDLE = 2'd0;
    localparam RS_WAIT = 2'd1;
    localparam RS_FILL = 2'd2;
    localparam RS_DONE = 2'd3;
    localparam REFILL = RS_FILL;

    reg [ 1:0] rs;
    wire [1:0] current_state = rs;

    reg [ 2:0] r_fcnt;
    reg [ 2:0] r_off;
    reg [ 4:0] r_idx;
    reg [21:0] r_tag;
    reg [31:0] r_base_addr;
    reg        r_is_peri;
    reg [31:0] dc_rd_data;
    reg [31:0] r_pick_data;
    reg        r_done_from_fill;

    reg r_ren0;
    always @(*) cpu_ren = {4{r_ren0}};

    localparam WS_IDLE  = 2'd0;
    localparam WS_WAIT  = 2'd1;
    localparam WS_WRITE = 2'd2;

    reg [1:0]  ws;
    reg [ 3:0] w_wen_r;
    reg [31:0] w_addr_r;
    reg [31:0] w_data_r;

    wire wr_resp = dev_wrdy & (cpu_wen == 4'h0);
    wire dc_fill_we   = (rs == RS_FILL) & dev_rvalid & !r_is_peri;
    wire dc_fill_last = dc_fill_we & (r_fcnt == NWORDS - 1);
    wire [7:0] dc_fill_addr = {r_idx, r_fcnt};
    wire dc_store_we = (ws == WS_IDLE) & (|data_wen) & d_hit;
    wire [7:0] dc_store_addr = {a_idx, a_off};
    wire dc_data_we = dc_fill_we | dc_store_we;
    wire [7:0] dc_data_waddr = dc_fill_we ? dc_fill_addr : dc_store_addr;
    wire [31:0] dc_data_wdata = dc_fill_we ? dev_rdata : data_wdata;
    wire [3:0] dc_data_wen = dc_fill_we ? 4'hf : data_wen;
    wire [7:0] dc_ram_raddr = (rs == RS_IDLE) ? a_ram_addr : {r_idx, r_off};

    always @(posedge cpu_clk) begin
        dc_rd_data <= dc_data[dc_ram_raddr];
        if (dc_data_we) begin
            if (dc_data_wen[0]) dc_data[dc_data_waddr][ 7: 0] <= dc_data_wdata[ 7: 0];
            if (dc_data_wen[1]) dc_data[dc_data_waddr][15: 8] <= dc_data_wdata[15: 8];
            if (dc_data_wen[2]) dc_data[dc_data_waddr][23:16] <= dc_data_wdata[23:16];
            if (dc_data_wen[3]) dc_data[dc_data_waddr][31:24] <= dc_data_wdata[31:24];
        end
        if (dc_fill_last)
            dc_tag[r_idx] <= r_tag;
    end

    always @(posedge cpu_clk or negedge cpu_rstn) begin
        if (!cpu_rstn) begin
            rs         <= RS_IDLE;
            ws         <= WS_IDLE;
            r_ren0     <= 1'b0;
            r_is_peri  <= 1'b0;
            data_valid <= 1'b0;
            data_wresp <= 1'b0;
            cpu_wen    <= 4'h0;
            r_pick_data <= 32'h0;
            r_done_from_fill <= 1'b0;
            dc_valid  <= {NLINES{1'b0}};
        end else begin
            data_valid <= 1'b0;
            data_wresp <= 1'b0;
            cpu_wen    <= 4'h0;
            r_ren0     <= 1'b0;

            case (rs)
                RS_IDLE: begin
                    if (|data_ren) begin
                        if (d_hit) begin
                            r_off <= a_off;
                            r_idx <= a_idx;
                            r_done_from_fill <= 1'b0;
                            rs    <= RS_DONE;
                        end else begin
                            r_off       <= a_off;
                            r_idx       <= a_idx;
                            r_tag       <= a_tag;
                            r_is_peri   <= !cacheable;
                            r_base_addr <= cacheable ? {data_addr[31:5], 5'h0} : data_addr;

                            if (dev_rrdy) begin
                                r_ren0    <= 1'b1;
                                cpu_raddr <= cacheable ? {data_addr[31:5], 5'h0} : data_addr;
                                r_fcnt    <= 3'h0;
                                rs        <= RS_FILL;
                            end else begin
                                rs <= RS_WAIT;
                            end
                        end
                    end
                end

                RS_WAIT: begin
                    if (dev_rrdy) begin
                        r_ren0    <= 1'b1;
                        cpu_raddr <= r_base_addr;
                        r_fcnt    <= 3'h0;
                        rs        <= RS_FILL;
                    end
                end

                RS_FILL: begin
                    if (dev_rvalid) begin
                        if (r_is_peri) begin
                            data_valid <= 1'b1;
                            data_rdata <= dev_rdata;
                            rs         <= RS_IDLE;
                        end else begin
                            if (r_fcnt == r_off)
                                r_pick_data <= dev_rdata;

                            if (r_fcnt == NWORDS - 1) begin
                                dc_valid[r_idx]    <= 1'b1;
                                r_done_from_fill   <= 1'b1;
                                rs                 <= RS_DONE;
                            end else begin
                                r_fcnt <= r_fcnt + 3'h1;
                            end
                        end
                    end
                end

                RS_DONE: begin
                    data_valid <= 1'b1;
                    data_rdata <= r_done_from_fill ? r_pick_data : dc_rd_data;
                    rs         <= RS_IDLE;
                end
                default: begin
                    rs <= RS_IDLE;
                end
            endcase

            case (ws)
                WS_IDLE: begin
                    if (|data_wen) begin
                        w_addr_r <= data_addr;
                        w_data_r <= data_wdata;
                        w_wen_r  <= data_wen;

                        if (dev_wrdy) begin
                            cpu_wen   <= data_wen;
                            cpu_waddr <= data_addr;
                            cpu_wdata <= data_wdata;
                            ws        <= WS_WRITE;
                        end else begin
                            ws <= WS_WAIT;
                        end
                    end
                end

                WS_WAIT: begin
                    if (dev_wrdy) begin
                        cpu_wen   <= w_wen_r;
                        cpu_waddr <= w_addr_r;
                        cpu_wdata <= w_data_r;
                        ws        <= WS_WRITE;
                    end
                end

                WS_WRITE: begin
                    data_wresp <= wr_resp;
                    if (wr_resp)
                        ws <= WS_IDLE;
                end
                default: begin
                    ws <= WS_IDLE;
                end
            endcase
        end
    end

`else
    
    localparam R_IDLE  = 2'b00;
    localparam R_STAT0 = 2'b01;
    localparam R_STAT1 = 2'b11;
    reg [1:0] r_state, r_nstat;
    reg [3:0] ren_r;

    always @(posedge cpu_clk or negedge cpu_rstn) begin
        r_state <= !cpu_rstn ? R_IDLE : r_nstat;
    end

    always @(*) begin
        case (r_state)
            R_IDLE:  r_nstat = (|data_ren) ? (dev_rrdy ? R_STAT1 : R_STAT0) : R_IDLE;
            R_STAT0: r_nstat = dev_rrdy ? R_STAT1 : R_STAT0;
            R_STAT1: r_nstat = dev_rvalid ? R_IDLE : R_STAT1;
            default: r_nstat = R_IDLE;
        endcase
    end

    always @(posedge cpu_clk or negedge cpu_rstn) begin
        if (!cpu_rstn) begin
            data_valid <= 1'b0;
            cpu_ren    <= 4'h0;
        end else begin
            case (r_state)
                R_IDLE: begin
                    data_valid <= 1'b0;

                    if (|data_ren) begin
                        if (dev_rrdy)
                            cpu_ren <= data_ren;
                        else
                            ren_r   <= data_ren;

                        cpu_raddr <= data_addr;
                    end else
                        cpu_ren   <= 4'h0;
                end
                R_STAT0: begin
                    cpu_ren    <= dev_rrdy ? ren_r : 4'h0;
                end   
                R_STAT1: begin
                    cpu_ren    <= 4'h0;
                    data_valid <= dev_rvalid ? 1'b1 : 1'b0;
                    data_rdata <= dev_rvalid ? dev_rdata : 32'h0;
                end
                default: begin
                    data_valid <= 1'b0;
                    cpu_ren    <= 4'h0;
                end 
            endcase
        end
    end

    localparam W_IDLE  = 2'b00;
    localparam W_STAT0 = 2'b01;
    localparam W_STAT1 = 2'b11;
    reg  [1:0] w_state, w_nstat;
    reg  [3:0] wen_r;
    wire       wr_resp = dev_wrdy & (cpu_wen == 4'h0) ? 1'b1 : 1'b0;

    always @(posedge cpu_clk or negedge cpu_rstn) begin
        w_state <= !cpu_rstn ? W_IDLE : w_nstat;
    end

    always @(*) begin
        case (w_state)
            W_IDLE:  w_nstat = (|data_wen) ? (dev_wrdy ? W_STAT1 : W_STAT0) : W_IDLE;
            W_STAT0: w_nstat = dev_wrdy ? W_STAT1 : W_STAT0;
            W_STAT1: w_nstat = wr_resp ? W_IDLE : W_STAT1;
            default: w_nstat = W_IDLE;
        endcase
    end

    always @(posedge cpu_clk or negedge cpu_rstn) begin
        if (!cpu_rstn) begin
            data_wresp <= 1'b0;
            cpu_wen    <= 4'h0;
        end else begin
            case (w_state)
                W_IDLE: begin
                    data_wresp <= 1'b0;

                    if (|data_wen) begin
                        if (dev_wrdy)
                            cpu_wen <= data_wen;
                        else
                            wen_r   <= data_wen;
                        
                        cpu_waddr  <= data_addr;
                        cpu_wdata  <= data_wdata;
                    end else
                        cpu_wen    <= 4'h0;
                end
                W_STAT0: begin
                    cpu_wen    <= dev_wrdy ? wen_r : 4'h0;
                end
                W_STAT1: begin
                    cpu_wen    <= 4'h0;
                    data_wresp <= wr_resp ? 1'b1 : 1'b0;
                end
                default: begin
                    data_wresp <= 1'b0;
                    cpu_wen    <= 4'h0;
                end
            endcase
        end
    end

`endif

endmodule


