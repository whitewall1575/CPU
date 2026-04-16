`timescale 1ns / 1ps

`include "defines.vh"

module ALU (
    input  wire         clk,
    input  wire         rst,
    input  wire [ 4:0]  alu_op,
    input  wire [31:0]  A     ,
    input  wire [31:0]  B     ,
    output reg  [31:0]  C     ,
    output reg          f     ,
    input  wire         valid_in,
    output wire         muldiv_suspend,
    output wire         muldiv_done
);
   
    wire real_div = valid_in &((alu_op == `ALU_DIV   )| 
                              ( alu_op == `ALU_DIVU  )| 
                              ( alu_op == `ALU_MOD   )| 
                              ( alu_op == `ALU_MODU  ));

    wire real_mul = valid_in &((alu_op == `ALU_MUL   )| 
                              ( alu_op == `ALU_MULH  )| 
                              ( alu_op == `ALU_MULHU));

    wire is_unsigned = (alu_op == `ALU_MULHU) | (alu_op == `ALU_DIVU) | (alu_op == `ALU_MODU);

    wire [32:0] mul_ip_A = is_unsigned ? {1'b0, A} : {A[31], A};
    wire [32:0] mul_ip_B = is_unsigned ? {1'b0, B} : {B[31], B};

    wire [39:0] div_ip_A = is_unsigned ? {8'b0, A} : {{8{A[31]}}, A};
    wire [39:0] div_ip_B = is_unsigned ? {8'b0, B} : {{8{B[31]}}, B};

    wire [65:0] mul_res_66;
    
    // 例化乘法器 IP 核 (配置要求：Signed, 33位 x 33位, Pipeline Stages = 2)
    mult_gen_0 u_mult (
        .CLK (clk), 
        .A   (mul_ip_A), 
        .B   (mul_ip_B), 
        .P   (mul_res_66)
    );

    reg [1:0] mul_cnt;
    always @(posedge clk) begin
        if (rst) begin
            mul_cnt <= 2'b00;
        end else if (real_mul) begin
            if (mul_cnt != 2'd2)
                mul_cnt <= mul_cnt + 1'b1;
        end else begin
            mul_cnt <= 2'b00; // 状态自恢复
        end
    end
    
    wire mul_done = (mul_cnt == 2'd2); 

    // 4. 除法器实现 (AXI-Stream 单脉冲握手)

    reg div_started; 
    always @(posedge clk) begin
        if (rst) begin
            div_started <= 1'b0;
        end else if (real_div && !div_started) begin
            div_started <= 1'b1; // 记录投币状态
        end else if (!real_div) begin
            div_started <= 1'b0; // 状态自恢复
        end
    end

    wire div_start = real_div && !div_started; // 仅产生1拍的启动脉冲
    
    wire div_tvalid;
    wire [79:0] div_res_80;

    // 例化除法器 IP 核 (配置要求：High Radix/Radix-2, 40位 / 40位, Signed)
    div_gen_0 u_div (
        .aclk                   (clk),
        .s_axis_dividend_tvalid (div_start), 
        .s_axis_dividend_tdata  (div_ip_A),
        .s_axis_divisor_tvalid  (div_start), 
        .s_axis_divisor_tdata   (div_ip_B),
        .m_axis_dout_tvalid     (div_tvalid),
        .m_axis_dout_tdata      (div_res_80)
    );

    // 结果抓取与锁存
    reg [79:0] div_res_latch;
    reg div_done;
    
    always @(posedge clk) begin
        if (rst) begin
            div_res_latch <= 80'b0;
            div_done      <= 1'b0;
        end else if (div_tvalid) begin
            div_res_latch <= div_res_80; // 捕获瞬间的闪烁数据
            div_done      <= 1'b1;       // 标记计算完成
        end else if (!real_div) begin
            div_done      <= 1'b0;       // 状态自恢复
        end
    end

    
    assign muldiv_suspend = (real_mul && !mul_done) || (real_div && !div_done);
    assign muldiv_done    = (real_mul && mul_done)  || (real_div && div_done);
  
    reg [31:0] normal_res;
    always @(*) begin
        case (alu_op)
            `ALU_ADD  : normal_res = A + B;
            `ALU_SUB  : normal_res = A - B;
            `ALU_SLT  : normal_res = ($signed(A) < $signed(B)) ? 32'b1 : 32'b0;
            `ALU_SLTU : normal_res = (A < B) ? 32'b1 : 32'b0;
            `ALU_AND  : normal_res = A & B;
            `ALU_OR   : normal_res = A | B;
            `ALU_XOR  : normal_res = A ^ B;
            `ALU_NOR  : normal_res = ~(A | B);
            `ALU_SLL  : normal_res = A << B[4:0];                
            `ALU_SRL  : normal_res = A >> B[4:0];                
            `ALU_SRA  : normal_res = $signed(A) >>> B[4:0];      
            `ALU_LUI  : normal_res = B;
            `ALU_EQ   : normal_res = (A == B) ? 32'd1 : 32'd0;                   // BEQ
            `ALU_NE   : normal_res = (A != B) ? 32'd1 : 32'd0;                   // BNE  
            `ALU_LT   : normal_res = ($signed(A) < $signed(B))  ? 32'd1 : 32'd0; // BLT  
            `ALU_GE   : normal_res = ($signed(A) >= $signed(B)) ? 32'd1 : 32'd0; // BGE  
            `ALU_LTU  : normal_res = (A < B)                    ? 32'd1 : 32'd0; // BLTU 
            `ALU_GEU  : normal_res = (A >= B)                   ? 32'd1 : 32'd0; // BGEU 
            default   : normal_res = 32'h87654321;
        endcase
    end

    always @(*) begin
        if (real_div) begin
            if (alu_op == `ALU_MOD || alu_op == `ALU_MODU)
                C = div_res_latch[31:0];  // 余数：取 80 位的低 32 位
            else
                C = div_res_latch[71:40]; // 商：取 80 位的高半段 (根据 AXI 字节对齐规则)
        end else if (real_mul) begin
            if (alu_op == `ALU_MULH || alu_op == `ALU_MULHU)
                C = mul_res_66[63:32];    // 乘高位：取 66 位的中间段
            else
                C = mul_res_66[31:0];     // 乘低位：取 66 位的低 32 位
        end else begin
            C = normal_res;               // 其他指令输出普通结果
        end
    end

    always @(*) begin
        case (alu_op)
            default  : f = 1'b0;
        endcase
    end

endmodule
