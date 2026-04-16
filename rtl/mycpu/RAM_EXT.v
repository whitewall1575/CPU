`timescale 1ns / 1ps

`include "defines.vh"

module RAM_EXT (
    input  wire [ 2:0]  ram_ext_op ,
    input  wire [ 1:0]  byte_offset,
    input  wire [31:0]  din        ,
    output reg  [31:0]  ext_out    
);

    always @(*) begin
        case (ram_ext_op)
            `RAM_EXT_B: begin
                case (byte_offset)
                    2'b00: ext_out = {{24{din[7]}}, din[7:0]};
                    2'b01: ext_out = {{24{din[15]}}, din[15:8]};
                    2'b10: ext_out = {{24{din[23]}}, din[23:16]};
                    default: ext_out = {{24{din[31]}}, din[31:24]};
                endcase
            end
            `RAM_EXT_BU: begin
                case (byte_offset)
                    2'b00: ext_out = {24'h0, din[7:0]};
                    2'b01: ext_out = {24'h0, din[15:8]};
                    2'b10: ext_out = {24'h0, din[23:16]};
                    default: ext_out = {24'h0, din[31:24]};
                endcase
            end
            `RAM_EXT_H : ext_out = byte_offset[1] ? {{16{din[31]}}, din[31:16]} : {{16{din[15]}}, din[15:0]};
            `RAM_EXT_HU: ext_out = byte_offset[1] ? {16'h0, din[31:16]} : {16'h0, din[15:0]};
            default    : ext_out = din;
        endcase
    end

endmodule
