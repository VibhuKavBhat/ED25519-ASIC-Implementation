// =============================================================================
// Module:      reg_file.sv
// Project:     ED25519 Hardware Accelerator
// Description: 16 x 256-bit Register File
//              - Asynchronous (combinational) read ports with write-through forwarding
//              - Single write port, dual read port
//              - No reset on storage array (SRAM compatible)
//              - No output registers (async read means zero read latency)
//              - Active low async assert, sync deassert reset             
//
// Register Map:
//   REG[0]  = X_acc        (accumulator X coordinate)
//   REG[1]  = Y_acc        (accumulator Y coordinate)
//   REG[2]  = Z_acc        (accumulator Z coordinate)
//   REG[3]  = T_acc        (accumulator T coordinate)
//   REG[4]  = X_operand    (second point X)
//   REG[5]  = Y_operand    (second point Y)
//   REG[6]  = Z_operand    (second point Z)
//   REG[7]  = T_operand    (second point T)
//   REG[8]  = temp_A       (ALU temporary A)
//   REG[9]  = temp_B       (ALU temporary B)
//   REG[10] = temp_C       (ALU temporary C)
//   REG[11] = temp_H       (ALU temporary H)
//   REG[12] = scalar       (s or h scalar value)
//   REG[13] = constant_d   (ED25519 curve constant d - loaded from ROM)
//   REG[14] = SQRT_M1      (sqrt(-1) mod p   - loaded from ROM)
//   REG[15] = scratch      (general purpose / result staging)
//
// We can always change the register mapping. There was also an idea of storing those constants in a ROM.
// =============================================================================

module reg_file #(
    parameter WIDTH = 256,
    parameter DEPTH = 16,
    parameter ADDR_W = $clog2(DEPTH)
)(
    input logic clk,
    input logic rst_n,
    
    //Write
    input logic wr_enable,
    input logic [ADDR_W-1:0] wr_addr,
    input logic [WIDTH-1:0] data_in,
    
    //Read port A
    input logic [ADDR_W-1:0] A_select,
    output logic [WIDTH-1:0] A_out,
    
    //Read port B
    input logic [ADDR_W-1:0] B_select,
    output logic [WIDTH-1:0] B_out  
    );
    
    //storage 
    logic [WIDTH-1:0] mem[0:DEPTH-1];
    
    always_ff @(posedge clk) begin
        if (wr_enable)
            mem[wr_addr] <= data_in;
    end
    
    // Read Port A (Asynchronous / Combinational)
    // If writing to the same address we are reading, forward the new data (write-through)
    assign A_out = (wr_enable && wr_addr == A_select) ? data_in : mem[A_select];

    // Read Port B (Asynchronous / Combinational)
    assign B_out = (wr_enable && wr_addr == B_select) ? data_in : mem[B_select];
    

       
endmodule
