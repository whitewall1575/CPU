`timescale 1ns / 1ps

`include "defines.vh"

module EX_stage (
    input  wire         cpu_rstn     ,
    input  wire         cpu_clk      ,

    // pipeline control
    input  wire         pl_suspend   ,      // 流水线暂停信号
    output reg          ldst_unalign ,      // 访存地址是否不满足对齐条件
    output wire         muldiv_suspend,
    output wire         muldiv_done   ,

    // From ID
    input  wire         id_valid     ,      // ID阶段有效信号
    input  wire [31:0]  id_pc        ,      // ID阶段PC值
    input  wire [ 1:0]  id_npc_op    ,      // ID阶段的npc_op，用于控制下一条指令PC值的生成
    input  wire [31:0]  id_ext       ,      // ID阶段的扩展后的立即数
    input  wire [31:0]  id_real_rD1  ,      // ID阶段的源操作数1的实际值
    input  wire [31:0]  id_real_rD2  ,      // ID阶段的源操作数2的实际值
    input  wire [ 4:0]  id_alu_op    ,      // ID阶段的alu_op，用于控制ALU进行何种运算
    input  wire         id_alua_sel  ,      // ID阶段的ALU操作数A选择信号（选择源寄存器1的值或扩展后的立即数或其他）
    input  wire         id_alub_sel  ,      // ID阶段的ALU操作数B选择信号（选择源寄存器2的值或扩展后的立即数或其他）
    input  wire         id_rf_we     ,      // ID阶段的寄存器写使能（指令需要写回时rf_we为1）
    input  wire [ 4:0]  id_wR        ,      // ID阶段的目标寄存器
    input  wire [ 1:0]  id_wd_sel    ,      // ID阶段的写回数据选择（选择ALU执行结果写回，或选择访存数据写回，etc.）
    input  wire [ 3:0]  id_ram_we    ,      // ID阶段的主存写使能信号（针对store指令）
    input  wire [ 2:0]  id_ram_ext_op,      // ID阶段的读主存数据扩展op，用于控制主存读回数据的扩展方式（针对load指令）
    input  wire         id_is_br_jmp ,      // ID阶段是否是条件分支或直接跳转指令
    input  wire         id_is_call   ,
    input  wire         id_is_ret    ,

    // To IF
    output wire [ 1:0]  ex_npc_op    ,      // EX阶段的npc_op，用于控制下一条指令PC值的生成
    output wire         ex_alu_f     ,      // EX阶段的标志位
    output wire         ex_is_ld_st  ,      // EX阶段是否是Load/Store指令
    output wire         ex_is_br_jmp ,      // EX阶段是否是条件分支或直接跳转指令
    output wire         ex_br_jmp_f  ,      // EX阶段分支跳转指令实际是否会发生跳转

    output wire         ex_is_call   ,
    output wire         ex_is_ret    ,

    // To MEM
    output wire         ex_valid     ,      // EX阶段有效信号
    output wire [31:0]  ex_pc        ,      // EX阶段PC值
    output wire [31:0]  ex_rD1       ,      // EX阶段的源寄存器1的值
    output wire [31:0]  ex_rD2       ,      // EX阶段的源寄存器2的值
    output wire [31:0]  ex_ext       ,      // EX阶段的扩展后的立即数
    output wire [31:0]  ex_alu_C     ,      // EX阶段的ALU运算结果
    output wire         ex_rf_we     ,      // EX阶段的寄存器写使能（指令需要写回时rf_we为1）
    output wire [ 4:0]  ex_wR        ,      // EX阶段的目的寄存器
    output wire [ 1:0]  ex_wd_sel    ,      // EX阶段的写回数据选择（选择ALU执行结果写回，或选择访存数据写回，etc.）
    output wire [ 3:0]  ex_ram_we    ,      // EX阶段的主存写使能信号（针对store指令）
    output wire [ 2:0]  ex_ram_ext_op,      // EX阶段的读主存数据扩展op，用于控制主存读回数据的扩展方式（针对load指令）

    // Data Forward
    output reg  [31:0]  ex_wd        ,      // EX阶段的待写回数据
    output wire         ex_sel_ram          // EX阶段是否是访存指令 (特指Load指令, 用于Load-Use处理)
);

    wire [ 4:0] ex_alu_op;
    wire        ex_alua_sel, ex_alub_sel;
    wire [31:0] ex_alu_A = ex_alua_sel ? ex_rD1 : ex_pc;
    wire [31:0] ex_alu_B = ex_alub_sel ? ex_rD2 : ex_ext;

    wire is_cond_branch = (ex_alu_op == `ALU_EQ ) |
                          (ex_alu_op == `ALU_NE ) |
                          (ex_alu_op == `ALU_LT ) |
                          (ex_alu_op == `ALU_GE ) |
                          (ex_alu_op == `ALU_LTU) |
                          (ex_alu_op == `ALU_GEU);

    assign ex_br_jmp_f = ex_valid & ex_is_br_jmp & ((is_cond_branch & ex_alu_C[0]) | (~is_cond_branch));
    assign ex_is_ld_st = ex_valid & (ex_wd_sel == `WD_RAM);
    assign ex_sel_ram  = ex_valid & (ex_wd_sel == `WD_RAM) & (ex_ram_we == `RAM_WE_N);

    wire       id_ex_valid_out;
    wire       id_ex_rf_we_out;
    wire [3:0] id_ex_ram_we_out;

    ID_EX u_ID_EX (
        .cpu_clk        (cpu_clk),
        .cpu_rstn       (cpu_rstn),
        .suspend        (pl_suspend),
        .valid_in       (id_valid),
        .wR_in          (id_wR),
        .pc_in          (id_pc),
        .rD1_in         (id_real_rD1),
        .rD2_in         (id_real_rD2),
        .ext_in         (id_ext),
        .npc_op_in      (id_npc_op),
        .rf_we_in       (id_rf_we & id_valid),
        .wd_sel_in      (id_wd_sel),
        .alu_op_in      (id_alu_op & {5{id_valid}}),
        .alua_sel_in    (id_alua_sel),
        .alub_sel_in    (id_alub_sel),
        .ram_we_in      (id_ram_we & {4{id_valid}}),
        .ram_ext_op_in  (id_ram_ext_op),
        .is_br_jmp_in   (id_is_br_jmp & id_valid),
        .is_call_in     (id_is_call),
        .is_ret_in      (id_is_ret),
        .valid_out      (id_ex_valid_out),
        .wR_out         (ex_wR),
        .pc_out         (ex_pc),
        .rD1_out        (ex_rD1),
        .rD2_out        (ex_rD2),
        .ext_out        (ex_ext),
        .npc_op_out     (ex_npc_op),
        .rf_we_out      (id_ex_rf_we_out),
        .wd_sel_out     (ex_wd_sel),
        .alu_op_out     (ex_alu_op),
        .alua_sel_out   (ex_alua_sel),
        .alub_sel_out   (ex_alub_sel),
        .ram_we_out     (id_ex_ram_we_out),
        .ram_ext_op_out (ex_ram_ext_op),
        .is_br_jmp_out  (ex_is_br_jmp),
        .is_call_out    (ex_is_call),
        .is_ret_out     (ex_is_ret)
    );

    assign ex_valid  = id_ex_valid_out & ~muldiv_suspend;
    assign ex_rf_we  = id_ex_rf_we_out & ~muldiv_suspend;
    assign ex_ram_we = id_ex_ram_we_out & {4{~muldiv_suspend}};

    ALU u_ALU (
        .clk            (cpu_clk),
        .rst            (~cpu_rstn),
        .valid_in       (id_ex_valid_out),
        .alu_op         (ex_alu_op),
        .A              (ex_alu_A),
        .B              (ex_alu_B),
        .C              (ex_alu_C),
        .f              (ex_alu_f),
        .muldiv_suspend (muldiv_suspend),
        .muldiv_done    (muldiv_done)
    );

    wire [31:0] ex_pc4 = ex_pc + 32'd4;

    always @(*) begin
        case (ex_wd_sel)
            `WD_ALU: ex_wd = ex_alu_C;
            `WD_RAM: ex_wd = 32'h0;
            `WD_PC4: ex_wd = ex_pc4;
            default: ex_wd = 32'h12345678;
        endcase
    end

    // 检查访存地址是否关于待访问数据大小对齐, 不对齐则不访存
    always @(*) begin
        ldst_unalign = 1'b0;
        if (ex_wd_sel == `WD_RAM) begin
            if ((ex_ram_we == `RAM_WE_W) || ((ex_ram_we == `RAM_WE_N) && (ex_ram_ext_op == `RAM_EXT_W)))
                ldst_unalign = (ex_alu_C[1:0] != 2'h0);
            else if ((ex_ram_we == `RAM_WE_H) || ((ex_ram_we == `RAM_WE_N) && ((ex_ram_ext_op == `RAM_EXT_H) || (ex_ram_ext_op == `RAM_EXT_HU))))
                ldst_unalign = ex_alu_C[0];
        end
    end
endmodule
