`timescale 1ns / 1ps

`include "defines.vh"

module ID_stage (
    input  wire         cpu_rstn,
    input  wire         cpu_clk,
    // pipeline control
    input  wire         pl_suspend,
    input  wire         pred_error,
    input  wire         load_use_stall,
    input  wire         fd_rD1_sel,
    input  wire [31:0]  fd_rD1,
    input  wire         fd_rD2_sel,
    input  wire [31:0]  fd_rD2,
    // From IF and WB
    input  wire         if_valid,
    input  wire [31:0]  if_pc,
    input  wire [31:0]  if_npc,
    input  wire         wb_rf_we,
    input  wire [ 4:0]  wb_wR,
    input  wire [31:0]  wb_wd,
    // To IF
    output wire         id_is_ld_st,
    output wire         id_is_muldiv,
    // To EX
    output wire         id_valid,
    output wire [31:0]  id_pc,
    output wire [ 1:0]  id_npc_op,
    output wire [31:0]  id_ext,
    output wire [31:0]  id_real_rD1,
    output wire [31:0]  id_real_rD2,
    output wire [ 4:0]  id_alu_op,
    output wire         id_alua_sel,
    output wire         id_alub_sel,
    output wire         id_rf_we,
    output wire [ 4:0]  id_wR,
    output wire [ 1:0]  id_wd_sel,
    output wire [ 3:0]  id_ram_we,
    output wire [ 2:0]  id_ram_ext_op,
    output wire         id_is_br_jmp,
    output wire         id_is_call,
    output wire         id_is_ret,
    // Data Forward
    output wire [ 4:0]  id_rR1,
    output wire         id_rR1_re,
    output wire [ 4:0]  id_rR2,
    output wire         id_rR2_re,
    // Instruction Fetch Interface
    input  wire         ifetch_valid,
    input  wire [31:0]  ifetch_inst
);

    assign      id_valid = ifetch_valid & !pred_error & !load_use_stall;
    wire [31:0] id_inst  = ifetch_inst;
    wire [ 2:0] id_ext_op;
    wire        id_r2_sel, id_wr_sel;

    assign id_rR1 = id_inst[9:5];
    assign id_rR2 = id_r2_sel ? id_inst[14:10] : id_inst[4:0];
    assign id_wR  = id_wr_sel ? id_inst[4:0] : 5'h1;

    wire [31:0] id_rD1, id_rD2;
    assign id_real_rD1 = fd_rD1_sel ? fd_rD1 : id_rD1;
    assign id_real_rD2 = fd_rD2_sel ? fd_rD2 : id_rD2;

    assign id_is_ld_st = id_valid & (id_wd_sel == `WD_RAM);
    assign id_is_muldiv = id_valid & ((id_alu_op == `ALU_MUL  ) |
                                      (id_alu_op == `ALU_MULH ) |
                                      (id_alu_op == `ALU_MULHU) |
                                      (id_alu_op == `ALU_DIV  ) |
                                      (id_alu_op == `ALU_DIVU ) |
                                      (id_alu_op == `ALU_MOD  ) |
                                      (id_alu_op == `ALU_MODU));

    assign id_is_call = id_valid & id_is_br_jmp & (id_wR == 5'd1);
    assign id_is_ret  = id_valid & id_is_br_jmp & (id_rR1 == 5'd1) & !id_is_call;

    IF_ID u_IF_ID (
        .cpu_clk  (cpu_clk),
        .cpu_rstn (cpu_rstn),
        .suspend  (pl_suspend | load_use_stall),
        .valid_in (if_valid),
        .pc_in    (if_pc),
        .pc_out   (id_pc)
    );

    CU u_CU (
        .inst_31_15 (id_inst[31:15]),
        .npc_op     (id_npc_op),
        .is_br_jmp  (id_is_br_jmp),
        .ext_op     (id_ext_op),
        .r2_sel     (id_r2_sel),
        .rR1_re     (id_rR1_re),
        .rR2_re     (id_rR2_re),
        .alua_sel   (id_alua_sel),
        .alub_sel   (id_alub_sel),
        .alu_op     (id_alu_op),
        .ram_ext_op (id_ram_ext_op),
        .ram_we     (id_ram_we),
        .rf_we      (id_rf_we),
        .wr_sel     (id_wr_sel),
        .wd_sel     (id_wd_sel)
    );

    RF u_RF (
        .cpu_clk (cpu_clk),
        .rR1     (id_rR1),
        .rR2     (id_rR2),
        .we      (wb_rf_we),
        .wR      (wb_wR),
        .wD      (wb_wd),
        .rD1     (id_rD1),
        .rD2     (id_rD2)
    );

    EXT u_EXT (
        .ext_op (id_ext_op),
        .din    (id_inst[25:0]),
        .ext    (id_ext)
    );

endmodule
