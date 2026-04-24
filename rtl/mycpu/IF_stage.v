`timescale 1ns / 1ps

module IF_stage (
    input  wire         cpu_rstn,
    input  wire         cpu_clk,
    // pipeline control
    input  wire         pause_ifetch,
    input  wire         resume_ifetch,
    input  wire         pl_suspend,
    // From BPU
    input  wire         pred_error,
    input  wire [31:0]  pred_target,
    // From other stages
    input  wire         id_valid,
    input  wire         ex_valid,
    input  wire [ 1:0]  ex_npc_op,
    input  wire [31:0]  ex_pc,
    input  wire [31:0]  ex_rD1,
    input  wire [31:0]  ex_ext,
    input  wire         ex_alu_f,
    input  wire         ex_br_jmp_f,
    // To ID
    output wire         if_valid,
    output wire [31:0]  if_pc,
    output wire [31:0]  if_npc,
    // Instruction Fetch Interface
    output wire         ifetch_rreq,
    output wire [31:0]  ifetch_addr,
    input  wire         ifetch_valid
);

    reg rstn_r;
    wire first_req = !rstn_r & cpu_rstn;
    always @(posedge cpu_clk) rstn_r <= cpu_rstn;

    wire [31:0] pc_reg;
    assign if_pc = pred_error ? if_npc : pc_reg;

    assign ifetch_rreq = !pause_ifetch &
                          (first_req | ifetch_valid | pred_error | resume_ifetch);
    assign ifetch_addr = if_pc;
    assign if_valid    = ifetch_rreq;

    PC u_PC (
        .cpu_clk  (cpu_clk),
        .cpu_rstn (cpu_rstn),
        .suspend  (pl_suspend),
        .if_valid (if_valid),
        .din      (pred_target),
        .pc       (pc_reg)
    );

    NPC u_NPC (
        .cpu_clk     (cpu_clk),
        .cpu_rstn    (cpu_rstn),
        .id_valid    (id_valid),
        .ex_valid    (ex_valid),
        .npc_op      (ex_npc_op),
        .ex_pc       (ex_pc),
        .rj          (ex_rD1),
        .offset      (ex_ext),
        .br          (ex_br_jmp_f),
        .npc         (if_npc)
    );

endmodule
