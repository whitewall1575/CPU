`timescale 1ns / 1ps

`include "mycpu_inst.vh"
`include "defines.vh"

module CU (
    input  wire [31:15] inst_31_15,
    output wire [ 1: 0] npc_op    ,
    output wire         is_br_jmp ,
    output wire [ 2: 0] ext_op    ,
    output wire         r2_sel    ,
    output wire         rR1_re    ,
    output wire         rR2_re    ,
    output wire         alua_sel  ,
    output wire         alub_sel  ,
    output wire [ 4: 0] alu_op    ,
    output wire [ 2: 0] ram_ext_op,
    output wire [ 3: 0] ram_we    ,
    output wire         rf_we     ,
    output wire         wr_sel    ,
    output wire [ 1: 0] wd_sel    
);

    wire ADD_W     = (inst_31_15[31:15] == 17'h00020);
    wire SUB_W     = (inst_31_15[31:15] == 17'h00022);
    wire SLT       = (inst_31_15[31:15] == 17'h00024); 
    wire SLTU      = (inst_31_15[31:15] == 17'h00025);
    wire AND       = (inst_31_15[31:15] == 17'h00029);
    wire OR        = (inst_31_15[31:15] == 17'h0002A);
    wire XOR       = (inst_31_15[31:15] == 17'h0002B);
    wire NOR       = (inst_31_15[31:15] == 17'h00028);
    wire SLL_W     = (inst_31_15[31:15] == 17'h0002E);
    wire SRL_W     = (inst_31_15[31:15] == 17'h0002F);
    wire SRA_W     = (inst_31_15[31:15] == 17'h00030);
    wire MUL_W     = (inst_31_15[31:15] == 17'h00038);
    wire MULH_W    = (inst_31_15[31:15] == 17'h00039);
    wire MULH_WU   = (inst_31_15[31:15] == 17'h0003a);
    wire DIV_W     = (inst_31_15[31:15] == 17'h00040);
    wire MOD_W     = (inst_31_15[31:15] == 17'h00041);
    wire DIV_WU    = (inst_31_15[31:15] == 17'h00042);
    wire MOD_WU    = (inst_31_15[31:15] == 17'h00043);

    wire SLLI_W    = (inst_31_15[31:15] == 17'h00081); 
    wire SRLI_W    = (inst_31_15[31:15] == 17'h00089);
    wire SRAI_W    = (inst_31_15[31:15] == 17'h00091);

    wire LU12I_W   = (inst_31_15[31:25] == 7'h0A    );
    wire PCADDU12I = (inst_31_15[31:25] == 7'h0E    );

    wire ADDI_W    = (inst_31_15[31:22] == 10'h00A  ); 
    wire ANDI      = (inst_31_15[31:22] == 10'h00D  ); 
    wire ORI       = (inst_31_15[31:22] == 10'h00E  ); 
    wire XORI      = (inst_31_15[31:22] == 10'h00F  ); 
    wire SLTI      = (inst_31_15[31:22] == 10'h008  ); 
    wire SLTUI     = (inst_31_15[31:22] == 10'h009  ); 
    wire LD_B      = (inst_31_15[31:22] == 10'h0A0  );
    wire LD_H      = (inst_31_15[31:22] == 10'h0A1  );
    wire LD_W      = (inst_31_15[31:22] == 10'h0A2  );
    wire ST_B      = (inst_31_15[31:22] == 10'h0A4  );
    wire ST_H      = (inst_31_15[31:22] == 10'h0A5  );
    wire ST_W      = (inst_31_15[31:22] == 10'h0A6  );
    wire LD_BU     = (inst_31_15[31:22] == 10'h0A8  );
    wire LD_HU     = (inst_31_15[31:22] == 10'h0A9  );

    wire BEQ       = (inst_31_15[31:26] == 6'h16    ); 
    wire BNE       = (inst_31_15[31:26] == 6'h17    );
    wire BL        = (inst_31_15[31:26] == 6'h15    );
    wire JIRL      = (inst_31_15[31:26] == 6'h13    );
    wire B         = (inst_31_15[31:26] == 6'h14    ); 
    wire BLT       = (inst_31_15[31:26] == 6'h18    );
    wire BGE       = (inst_31_15[31:26] == 6'h19    ); 
    wire BLTU      = (inst_31_15[31:26] == 6'h1a    ); 
    wire BGEU      = (inst_31_15[31:26] == 6'h1b    ); 

    wire TYPE_3R     = ADD_W | SUB_W | SLT | SLTU | AND | OR | XOR | NOR | SLL_W | SRL_W | SRA_W | MUL_W | MULH_W | MULH_WU | DIV_W | MOD_W | DIV_WU | MOD_WU;
    wire TYPE_2RI5   = SLLI_W | SRLI_W | SRAI_W;
    wire TYPE_I_SIGN = ADDI_W | SLTI | SLTUI; 
    wire TYPE_I_ZERO = ANDI | ORI | XORI;   
    wire TYPE_2RI12  = TYPE_I_SIGN | TYPE_I_ZERO; 
    wire LOAD        = LD_B | LD_H | LD_W | LD_BU | LD_HU;
    wire STORE       = ST_B | ST_H | ST_W;

    wire is_branch   = BEQ | BNE | BLT | BGE | BLTU | BGEU;  
    wire is_jump     = BL | JIRL | B;  

    wire NPC_OP_PC4  = TYPE_3R | PCADDU12I | LOAD | STORE | TYPE_2RI5 | TYPE_2RI12 | LU12I_W;
    wire NPC_OP_B    = is_branch | BL | B;
    wire NPC_OP_JIRL = JIRL;

    wire EXT_OP_12   = LOAD | STORE | TYPE_I_SIGN;
    wire EXT_OP_12_Z = TYPE_I_ZERO;
    wire EXT_OP_20   = PCADDU12I | LU12I_W;
    wire EXT_OP_5    = TYPE_2RI5;
    wire EXT_OP_16   = is_branch | JIRL;  
    wire EXT_OP_26   = BL | B;

    wire ALU_OP_ADD   = ADD_W | ADDI_W | PCADDU12I | LOAD | STORE;
    wire ALU_OP_SUB   = SUB_W;
    wire ALU_OP_SLT   = SLT   | SLTI;
    wire ALU_OP_SLTU  = SLTU  | SLTUI;
    wire ALU_OP_AND   = AND   | ANDI;
    wire ALU_OP_OR    = OR    | ORI;
    wire ALU_OP_XOR   = XOR   | XORI;
    wire ALU_OP_NOR   = NOR;
    wire ALU_OP_SLL   = SLL_W | SLLI_W;
    wire ALU_OP_SRL   = SRL_W | SRLI_W;
    wire ALU_OP_SRA   = SRA_W | SRAI_W;
    wire ALU_OP_MUL   = MUL_W;
    wire ALU_OP_MULH  = MULH_W;
    wire ALU_OP_MULHU = MULH_WU;
    wire ALU_OP_DIV   = DIV_W;
    wire ALU_OP_DIVU  = DIV_WU;
    wire ALU_OP_MOD   = MOD_W;
    wire ALU_OP_MODU  = MOD_WU;
    wire ALU_OP_EQ    = BEQ;
    wire ALU_OP_NE    = BNE;
    wire ALU_OP_LT    = BLT;
    wire ALU_OP_GE    = BGE;
    wire ALU_OP_LTU   = BLTU;
    wire ALU_OP_GEU   = BGEU;

    wire WD_SEL_ALU = TYPE_3R | PCADDU12I | TYPE_2RI5 | TYPE_2RI12 | LU12I_W;
    wire WD_SEL_RAM = LOAD | STORE;
    wire WD_SEL_PC4 = BL | JIRL;

    assign npc_op = ({2{NPC_OP_PC4 }} & `NPC_PC4 ) |
                    ({2{NPC_OP_B   }} & `NPC_B   ) |
                    ({2{NPC_OP_JIRL}} & `NPC_JIRL);

    assign is_br_jmp = is_branch | is_jump;

    assign ext_op = ({3{EXT_OP_12  }} & `EXT_12  ) |
                    ({3{EXT_OP_20  }} & `EXT_20  ) |
                    ({3{EXT_OP_12_Z}} & `EXT_12_Z) |
                    ({3{EXT_OP_5   }} & `EXT_5   ) |
                    ({3{EXT_OP_16  }} & `EXT_16  ) |
                    ({3{EXT_OP_26  }} & `EXT_26  );

    assign r2_sel = (STORE | is_branch) ? `R2_RD : `R2_RK;

    assign rR1_re = !(PCADDU12I | LU12I_W);

    assign rR2_re = TYPE_3R | STORE | is_branch;

    assign alua_sel = PCADDU12I ? `ALUA_PC : `ALUA_R1;

    assign alub_sel = (PCADDU12I | LOAD | STORE | TYPE_2RI5 | TYPE_2RI12 | LU12I_W) ? `ALUB_EXT : `ALUB_R2;

    assign alu_op = ({5{ALU_OP_ADD  }} & `ALU_ADD ) |
                    ({5{ALU_OP_SUB  }} & `ALU_SUB ) |
                    ({5{ALU_OP_SLT  }} & `ALU_SLT ) |
                    ({5{ALU_OP_SLTU }} & `ALU_SLTU) |
                    ({5{ALU_OP_AND  }} & `ALU_AND ) |
                    ({5{ALU_OP_OR   }} & `ALU_OR  ) |
                    ({5{ALU_OP_XOR  }} & `ALU_XOR ) |
                    ({5{ALU_OP_NOR  }} & `ALU_NOR ) |
                    ({5{ALU_OP_SLL  }} & `ALU_SLL ) |
                    ({5{ALU_OP_SRL  }} & `ALU_SRL ) |
                    ({5{ALU_OP_SRA  }} & `ALU_SRA ) |
                    ({5{LU12I_W     }} & `ALU_LUI ) |
                    ({5{ALU_OP_MUL  }} & `ALU_MUL ) |
                    ({5{ALU_OP_MULH }} & `ALU_MULH) |
                    ({5{ALU_OP_MULHU}} & `ALU_MULHU) |
                    ({5{ALU_OP_DIV  }} & `ALU_DIV ) |
                    ({5{ALU_OP_DIVU }} & `ALU_DIVU) |
                    ({5{ALU_OP_MOD  }} & `ALU_MOD ) |
                    ({5{ALU_OP_MODU }} & `ALU_MODU) |
                    ({5{ALU_OP_EQ   }} & `ALU_EQ  ) |
                    ({5{ALU_OP_NE   }} & `ALU_NE  ) |
                    ({5{ALU_OP_LT   }} & `ALU_LT  ) |
                    ({5{ALU_OP_GE   }} & `ALU_GE  ) |
                    ({5{ALU_OP_LTU  }} & `ALU_LTU ) |
                    ({5{ALU_OP_GEU  }} & `ALU_GEU );

    assign ram_ext_op = ({3{LD_B }} & `RAM_EXT_B ) |
                        ({3{LD_H }} & `RAM_EXT_H ) |
                        ({3{LD_W }} & `RAM_EXT_W ) |
                        ({3{LD_BU}} & `RAM_EXT_BU) |
                        ({3{LD_HU}} & `RAM_EXT_HU);

    assign ram_we = ({4{ST_B}} & `RAM_WE_B) |
                    ({4{ST_H}} & `RAM_WE_H) |
                    ({4{ST_W}} & `RAM_WE_W);

    assign rf_we = (NPC_OP_PC4 & !STORE) | TYPE_2RI5 | TYPE_2RI12 | LU12I_W | BL | JIRL;

    assign wr_sel = BL ? `WR_R1 : `WR_RD;

    assign wd_sel = ({2{WD_SEL_ALU}} & `WD_ALU) |
                    ({2{WD_SEL_RAM}} & `WD_RAM) |
                    ({2{WD_SEL_PC4}} & `WD_PC4);

endmodule
