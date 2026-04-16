`timescale 1ns / 1ps

`include "defines.vh"

module ICache (
    input  wire         cpu_rstn,
    input  wire         cpu_clk,
    input  wire         inst_rreq,
    input  wire [31:0]  inst_addr,
    output reg          inst_valid,
    output reg  [31:0]  inst_out,
    input  wire         pred_error,
    input  wire         dev_rrdy,
    output reg  [ 3:0]  cpu_ren,
    output reg  [31:0]  cpu_raddr,
    input  wire         dev_rvalid,
    input  wire [31:0]  dev_rdata
);

`ifdef ENABLE_ICACHE

    localparam NLINES = 32;
    localparam NWORDS = 8;

    reg              ic_valid [0:NLINES-1];
    reg [21:0]       ic_tag   [0:NLINES-1];
    reg [31:0]       ic_data  [0:NLINES-1][0:NWORDS-1];

    wire [21:0] a_tag = inst_addr[31:10];
    wire [ 4:0] a_idx = inst_addr[ 9: 5];
    wire [ 2:0] a_off = inst_addr[ 4: 2];
    wire        a_hit = ic_valid[a_idx] & (ic_tag[a_idx] == a_tag);

    reg  [31:0] redir_addr;
    reg         redir_pending;
    reg         fill_abort;

    wire [21:0] r_tag = redir_addr[31:10];
    wire [ 4:0] r_idx = redir_addr[ 9: 5];
    wire [ 2:0] r_off = redir_addr[ 4: 2];

    reg ren0;
    always @(*) cpu_ren = {4{ren0}};

    localparam S_IDLE = 2'd0;
    localparam S_WAIT = 2'd1;
    localparam S_FILL = 2'd2;
    localparam S_DONE = 2'd3;
    localparam REFILL = S_FILL;

    wire [1:0] current_state = state;

    reg [ 1:0] state;
    reg [ 2:0] fill_cnt;
    reg [ 2:0] s_off;
    reg [ 4:0] s_idx;
    reg [21:0] s_tag;
    reg [31:0] s_blk;

    wire saved_hit      = ic_valid[s_idx] & (ic_tag[s_idx] == s_tag);
    wire fill_abort_now = fill_abort | pred_error;

    integer k;
    always @(posedge cpu_clk or negedge cpu_rstn) begin
        if (!cpu_rstn) begin
            state         <= S_IDLE;
            fill_cnt      <= 3'h0;
            ren0          <= 1'b0;
            inst_valid    <= 1'b0;
            inst_out      <= 32'h0;
            redir_pending <= 1'b0;
            fill_abort    <= 1'b0;
            for (k = 0; k < NLINES; k = k + 1)
                ic_valid[k] <= 1'b0;
        end else begin
            inst_valid <= 1'b0;
            ren0       <= 1'b0;

            case (state)
                S_IDLE: begin
                    if (inst_rreq) begin
                        s_off <= a_off;
                        s_idx <= a_idx;
                        s_tag <= a_tag;
                        s_blk <= {inst_addr[31:5], 5'h0};

                        if (a_hit) begin
                            state <= S_DONE;
                        end else if (dev_rrdy) begin
                            ren0          <= 1'b1;
                            cpu_raddr     <= {inst_addr[31:5], 5'h0};
                            fill_cnt      <= 3'h0;
                            fill_abort    <= 1'b0;
                            redir_pending <= 1'b0;
                            state         <= S_FILL;
                        end else begin
                            state <= S_WAIT;
                        end
                    end
                end

                S_WAIT: begin
                    if (pred_error) begin
                        s_off <= a_off;
                        s_idx <= a_idx;
                        s_tag <= a_tag;
                        s_blk <= {inst_addr[31:5], 5'h0};

                        if (a_hit) begin
                            state <= S_DONE;
                        end else if (dev_rrdy) begin
                            ren0          <= 1'b1;
                            cpu_raddr     <= {inst_addr[31:5], 5'h0};
                            fill_cnt      <= 3'h0;
                            fill_abort    <= 1'b0;
                            redir_pending <= 1'b0;
                            state         <= S_FILL;
                        end else begin
                            state <= S_WAIT;
                        end
                    end else if (saved_hit) begin
                        state <= S_DONE;
                    end else if (dev_rrdy) begin
                        ren0          <= 1'b1;
                        cpu_raddr     <= s_blk;
                        fill_cnt      <= 3'h0;
                        fill_abort    <= 1'b0;
                        redir_pending <= 1'b0;
                        state         <= S_FILL;
                    end
                end

                S_FILL: begin
                    if (pred_error) begin
                        redir_pending <= 1'b1;
                        redir_addr    <= inst_addr;
                        fill_abort    <= 1'b1;
                    end

                    if (dev_rvalid) begin
                        if (!fill_abort_now)
                            ic_data[s_idx][fill_cnt] <= dev_rdata;

                        if (fill_cnt == NWORDS - 1) begin
                            if (!fill_abort_now) begin
                                ic_valid[s_idx] <= 1'b1;
                                ic_tag  [s_idx] <= s_tag;
                                state           <= S_DONE;
                            end else begin
                                s_off <= pred_error ? a_off : r_off;
                                s_idx <= pred_error ? a_idx : r_idx;
                                s_tag <= pred_error ? a_tag : r_tag;
                                s_blk <= pred_error ? {inst_addr[31:5], 5'h0} : {redir_addr[31:5], 5'h0};
                                redir_pending <= 1'b0;
                                fill_abort    <= 1'b0;
                                state         <= S_WAIT;
                            end
                            fill_cnt <= 3'h0;
                        end else begin
                            fill_cnt <= fill_cnt + 3'h1;
                        end
                    end
                end

                S_DONE: begin
                    if (pred_error) begin
                        s_off <= a_off;
                        s_idx <= a_idx;
                        s_tag <= a_tag;
                        s_blk <= {inst_addr[31:5], 5'h0};

                        if (a_hit) begin
                            state <= S_DONE;
                        end else if (dev_rrdy) begin
                            ren0          <= 1'b1;
                            cpu_raddr     <= {inst_addr[31:5], 5'h0};
                            fill_cnt      <= 3'h0;
                            fill_abort    <= 1'b0;
                            redir_pending <= 1'b0;
                            state         <= S_FILL;
                        end else begin
                            state <= S_WAIT;
                        end
                    end else begin
                        inst_valid <= 1'b1;
                        inst_out   <= ic_data[s_idx][s_off];
                        state      <= S_IDLE;
                    end
                end
            endcase
        end
    end

`else

    localparam IDLE  = 2'b00;
    localparam STAT0 = 2'b01;
    localparam STAT1 = 2'b11;
    reg [1:0] state, nstat;
    reg       dev_rvalid_r;
    wire      dev_rvalid_pos = !dev_rvalid_r & dev_rvalid;

    always @(posedge cpu_clk or negedge cpu_rstn) begin
        state        <= !cpu_rstn ? IDLE : nstat;
        dev_rvalid_r <= !cpu_rstn ? 1'b0 : dev_rvalid;
    end

    always @(*) begin
        case (state)
            IDLE   : nstat = inst_rreq ? (dev_rrdy ? STAT1 : STAT0) : IDLE;
            STAT0  : nstat = dev_rrdy ? STAT1 : STAT0;
            STAT1  : nstat = inst_rreq ? (dev_rrdy ? STAT1 : STAT0) : (dev_rvalid_pos ? IDLE : STAT1);
            default: nstat = IDLE;
        endcase
    end

    reg cpu_ren0;
    always @(posedge cpu_clk or negedge cpu_rstn) begin
        if (!cpu_rstn) begin
            inst_valid <= 1'b0;
            cpu_ren0   <= 1'b0;
        end else begin
            case (state)
                IDLE: begin
                    inst_valid <= 1'b0;
                    cpu_ren0   <= (inst_rreq & dev_rrdy) ? 1'b1 : 1'b0;
                    cpu_raddr  <= inst_rreq ? inst_addr : 32'h0;
                end
                STAT0: begin
                    cpu_ren0   <= dev_rrdy ? 1'b1 : 1'b0;
                end
                STAT1: begin
                    cpu_ren0   <= (inst_rreq & dev_rrdy) ? 1'b1 : 1'b0;
                    cpu_raddr  <= inst_rreq ? inst_addr : 32'h0;
                    inst_valid <= dev_rvalid_pos ? 1'b1 : 1'b0;
                    inst_out   <= dev_rdata;
                end
                default: begin
                    inst_valid <= 1'b0;
                    cpu_ren0   <= 1'b0;
                end
            endcase
        end
    end

    always @(*) cpu_ren = {4{cpu_ren0 & !inst_rreq}};

`endif

endmodule
