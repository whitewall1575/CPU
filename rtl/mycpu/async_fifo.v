`timescale 1ns / 1ps

module async_fifo #(
    parameter DATA_WIDTH = 32,
    parameter FIFO_DEPTH = 4    // 2^n
) (
    input  wire         rstn,
    // Write Port
    input  wire         wr_clk,
    input  wire         wr_en,
    input  wire [DATA_WIDTH-1:0] din,
    output wire         full,
    // Read Port
    input  wire         rd_clk,
    input  wire         rd_en,
    output wire [DATA_WIDTH-1:0] dout,
    output wire         empty
);

    localparam ADDR_WIDTH = $clog2(FIFO_DEPTH);

    reg [DATA_WIDTH-1:0] mem [0:FIFO_DEPTH-1];
    reg [DATA_WIDTH-1:0] dout_fwft, dout_hold;

    reg [ADDR_WIDTH:0] wr_ptr_bin, wr_ptr_gray;
    reg [ADDR_WIDTH:0] rd_ptr_bin, rd_ptr_gray;

    reg [ADDR_WIDTH:0] wr_ptr_gray_rdclk1, wr_ptr_gray_rdclk2;
    reg [ADDR_WIDTH:0] rd_ptr_gray_wrclk1, rd_ptr_gray_wrclk2;

    reg full_r, empty_r;

    wire        wr_adv = wr_en && !full_r;
    wire        rd_adv = rd_en && !empty_r;
    wire [ADDR_WIDTH:0] wr_ptr_bin_next  = wr_ptr_bin + wr_adv;
    wire [ADDR_WIDTH:0] wr_ptr_gray_next = (wr_ptr_bin_next >> 1) ^ wr_ptr_bin_next;
    wire [ADDR_WIDTH:0] rd_ptr_bin_next  = rd_ptr_bin + rd_adv;
    wire [ADDR_WIDTH:0] rd_ptr_gray_next = (rd_ptr_bin_next >> 1) ^ rd_ptr_bin_next;

    wire full_next  = (wr_ptr_gray_next == {~rd_ptr_gray_wrclk2[ADDR_WIDTH:ADDR_WIDTH-1], rd_ptr_gray_wrclk2[ADDR_WIDTH-2:0]});
    wire empty_next = (rd_ptr_gray_next == wr_ptr_gray_rdclk2);

    assign full  = full_r;
    assign empty = empty_r;

    integer i;
    always @(posedge wr_clk or negedge rstn) begin
        if (!rstn) begin
            wr_ptr_bin  <= 0;
            wr_ptr_gray <= 0;
            full_r      <= 1'b0;
            for (i = 0; i < FIFO_DEPTH; i = i + 1)
                mem[i] <= {DATA_WIDTH{1'b0}};
        end else begin
            wr_ptr_bin  <= wr_ptr_bin_next;
            wr_ptr_gray <= wr_ptr_gray_next;
            full_r      <= full_next;
            if (wr_adv)
                mem[wr_ptr_bin[ADDR_WIDTH-1:0]] <= din;
        end
    end

    always @(posedge rd_clk or negedge rstn) begin
        if (!rstn)
            dout_fwft <= {DATA_WIDTH{1'b0}};
        else
            dout_fwft <= mem[rd_ptr_bin[ADDR_WIDTH-1:0]];
    end

    always @(posedge rd_clk or negedge rstn) begin
        if (!rstn)
            dout_hold <= {DATA_WIDTH{1'b0}};
        else if (rd_adv)
            dout_hold <= dout_fwft;
    end

    assign dout = rd_adv ? dout_fwft : dout_hold;

    always @(posedge rd_clk or negedge rstn) begin
        if (!rstn) begin
            rd_ptr_bin  <= 0;
            rd_ptr_gray <= 0;
            empty_r     <= 1'b1;
        end else begin
            rd_ptr_bin  <= rd_ptr_bin_next;
            rd_ptr_gray <= rd_ptr_gray_next;
            empty_r     <= empty_next;
        end
    end

    always @(posedge rd_clk or negedge rstn) begin
        if (!rstn) begin
            wr_ptr_gray_rdclk1 <= 0;
            wr_ptr_gray_rdclk2 <= 0;
        end else begin
            wr_ptr_gray_rdclk1 <= wr_ptr_gray;
            wr_ptr_gray_rdclk2 <= wr_ptr_gray_rdclk1;
        end
    end

    always @(posedge wr_clk or negedge rstn) begin
        if (!rstn) begin
            rd_ptr_gray_wrclk1 <= 0;
            rd_ptr_gray_wrclk2 <= 0;
        end else begin
            rd_ptr_gray_wrclk1 <= rd_ptr_gray;
            rd_ptr_gray_wrclk2 <= rd_ptr_gray_wrclk1;
        end
    end

endmodule
