`timescale 1ns / 1ps

`include "defines.vh"

`define BHT_IDX_W 10
`define BHT_ENTRY (1 << `BHT_IDX_W)    // 1024 项
`define BHT_TAG_W 8

// ============================================================
//  Branch Prediction Unit — 大道至简（稳定最终版）
//
//  核心思想：
//  1. 放弃脆弱的 IF 阶段投机更新，回归坚如磐石的 EX 阶段真实更新。
//  2. 完全免疫 Cache Miss、Load-Use 等导致的流水线冲刷污染。
//  3. 增加 ras_sp != 0 的防溢出保护。
// ============================================================

module BPU (
    input  wire         cpu_clk    ,
    input  wire         cpu_rstn   ,
    input  wire [31:0]  if_pc      ,
    input  wire         if_valid   ,
    input  wire         id_valid   ,
    input  wire         pl_suspend ,
    input  wire         pause_ifetch,
    // 预测输出
    output wire [31:0]  pred_target,
    output wire         pred_error ,
    // EX 阶段反馈
    input  wire         ex_valid   ,
    input  wire         ex_is_bj   ,
    input  wire [31:0]  ex_pc      ,
    input  wire         real_taken ,
    input  wire [31:0]  real_target,
    input  wire         ex_is_call ,
    input  wire         ex_is_ret
);

`ifdef ENABLE_BPU

    // --------------------------------------------------------
    //  BHT / BTB 存储
    // --------------------------------------------------------
    reg [`BHT_TAG_W-1:0] tag      [`BHT_ENTRY-1:0];
    reg [`BHT_ENTRY-1:0] valid;
    reg [           1:0] history  [`BHT_ENTRY-1:0];
    reg [          31:0] target   [`BHT_ENTRY-1:0];
    reg [`BHT_ENTRY-1:0] btb_is_ret;
    reg [`BHT_ENTRY-1:0] btb_is_call;

    // --------------------------------------------------------
    //  RAS (纯架构级状态，毫无投机污染)
    // --------------------------------------------------------
    reg [31:0] ras [0:15];
    reg [ 3:0] ras_sp;

    // --------------------------------------------------------
    //  IF 阶段：只读，绝对不修改任何状态！
    // --------------------------------------------------------
    wire [31:0]           pc_hash = if_pc ^ (if_pc >> 8) ^ (if_pc >> 16);
    wire [`BHT_IDX_W-1:0] index   = pc_hash[`BHT_IDX_W+1:2];
    wire [`BHT_TAG_W-1:0] if_tag  = if_pc[`BHT_TAG_W + `BHT_IDX_W + 1 : `BHT_IDX_W + 2];
    wire [`BHT_TAG_W-1:0] ex_tag  = ex_pc[`BHT_TAG_W + `BHT_IDX_W + 1 : `BHT_IDX_W + 2];

    wire bht_hit    = valid[index] & (tag[index] == if_tag);
    wire pred_taken = bht_hit & history[index][1];

    // 💡 目标预测：遇到 Ret，只要栈不空就读栈，否则读 BTB
    assign pred_target = pred_taken
        ? (btb_is_ret[index] ? ((ras_sp != 4'd0) ? ras[ras_sp - 1] : if_pc + 32'h4)
                             : target[index])
        : (if_pc + 32'h4);

    // --------------------------------------------------------
    //  预测信息流水（IF → ID → EX）
    // --------------------------------------------------------
    reg [`BHT_IDX_W-1:0] id_index      , ex_index      ;
    reg                  id_pred_taken , ex_pred_taken ;
    reg [          31:0] id_pred_target, ex_pred_target;

    wire if_advance = if_valid & !pl_suspend;
    wire id_advance = id_valid & !pl_suspend & !pause_ifetch;

    always @(posedge cpu_clk or negedge cpu_rstn) begin
        if (!cpu_rstn) begin
            id_index <= 0; id_pred_taken <= 0; id_pred_target <= 0;
            ex_index <= 0; ex_pred_taken <= 0; ex_pred_target <= 0;
        end else begin
            if (if_advance) begin
                id_index       <= index;
                id_pred_taken  <= pred_taken;
                id_pred_target <= pred_target;
            end
            if (id_advance) begin
                ex_index       <= id_index;
                ex_pred_taken  <= id_pred_taken;
                ex_pred_target <= id_pred_target;
            end
        end
    end

    // --------------------------------------------------------
    //  预测错误检测
    // --------------------------------------------------------
    wire taken_error  = ex_is_bj & ((!ex_pred_taken &  real_taken)
                                  | ( ex_pred_taken & !real_taken));
    wire target_error = ex_is_bj &   ex_pred_taken & (ex_pred_target != real_target);
    assign pred_error = ex_valid & (taken_error | target_error);

    // --------------------------------------------------------
    //  EX 阶段真实更新 (RAS & BTB) —— 绝对稳定
    // --------------------------------------------------------
    wire ex_advance   = ex_valid & !pl_suspend;
    wire add_entry    = ex_advance & ex_is_bj & (!valid[ex_index] | (tag[ex_index] != ex_tag));
    wire update_entry = ex_advance & ex_is_bj &  valid[ex_index] & (tag[ex_index] == ex_tag);

    integer i;
    always @(posedge cpu_clk or negedge cpu_rstn) begin
        if (!cpu_rstn) begin
            ras_sp     <= 4'd0;
            valid      <= {`BHT_ENTRY{1'b0}};
            btb_is_ret <= {`BHT_ENTRY{1'b0}};
            for (i = 0; i < `BHT_ENTRY; i = i + 1) history[i] <= 2'b10;
        end else if (ex_advance) begin
            
            // 💡 1. 真实 RAS 更新 (不搞投机，稳如老狗)
            if (ex_is_call & real_taken & ras_sp != 4'd15) begin
                ras[ras_sp] <= ex_pc + 32'd4;
                ras_sp      <= ras_sp + 1;
            end else if (ex_is_ret & real_taken & ras_sp != 4'd0) begin
                ras_sp      <= ras_sp - 1;
            end

            // 💡 2. 真实 BTB 更新
            if (add_entry) begin
                valid[ex_index]       <= 1'b1;
                tag[ex_index]         <= ex_tag;
                history[ex_index]     <= real_taken ? 2'b10 : 2'b01;
                target[ex_index]      <= real_target;
                btb_is_ret[ex_index]  <= ex_is_ret;
                btb_is_call[ex_index] <= ex_is_call;
            end else if (update_entry) begin
                case (history[ex_index])
                    2'b00: history[ex_index] <= real_taken ? 2'b01 : 2'b00;
                    2'b01: history[ex_index] <= real_taken ? 2'b10 : 2'b00;
                    2'b10: history[ex_index] <= real_taken ? 2'b11 : 2'b01;
                    2'b11: history[ex_index] <= real_taken ? 2'b11 : 2'b10;
                endcase
                if (real_taken)
                    target[ex_index] <= real_target;
                btb_is_ret[ex_index]  <= ex_is_ret;
                btb_is_call[ex_index] <= ex_is_call;
            end
        end
    end

`else   // ── 无 BPU 模式 ──
    assign pred_target = if_pc + 32'h4;
    wire taken_error   = ex_is_bj & real_taken;
    wire target_error  = 1'b0;
    assign pred_error  = ex_valid & (taken_error | target_error);
`endif

endmodule