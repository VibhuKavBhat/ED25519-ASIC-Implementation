// =============================================================================
// Module:      reg_file.sv
// Project:     ED25519 Hardware Accelerator
// Description: 16 x 256-bit Register File
//              - Synchronous read (SRAM macro compatible)
//              - Single write port, dual read port
//              - No reset on storage array (SRAM compatible)
//              - Reset only on output registers and control logic
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
    
    //read A
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            A_out <= '0;
        else
            A_out <= mem[A_select];
    end

    //read B
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            B_out <= '0;
        else
            B_out <= mem[B_select];
    end
    

    // =========================================================================
    // Assertions - synthesizable SVA properties
    // These fire during simulation to catch protocol violations
    // =========================================================================
 
    /*`ifndef SYNTHESIS
    
    // One cycle delay flag after reset deasserts
        // Prevents false X assertion firing on first read after reset
        // (first read pulls from uninitialized mem[] into output FF)
        logic rst_done;
        always_ff @(posedge clk or negedge rst_n)
            if (!rst_n) rst_done <= 1'b0;
            else        rst_done <= 1'b1;
 
    // A_out should never be X after reset deasserts
    property no_x_on_A_out;
        @(posedge clk) disable iff (!rst_n || !rst_done)
        !$isunknown(A_out);
    endproperty
    assert_no_x_A: assert property (no_x_on_A_out)
        else $error("[REG_FILE] X detected on A_out at time %0t", $time);
 
    // B_out should never be X after reset deasserts
    property no_x_on_B_out;
        @(posedge clk) disable iff (!rst_n || !rst_done)
        !$isunknown(B_out);
    endproperty
    assert_no_x_B: assert property (no_x_on_B_out)
        else $error("[REG_FILE] X detected on B_out at time %0t", $time);
 
    // Write address must be within valid range when wr_enable is high
    property valid_wr_addr;
        @(posedge clk) disable iff (!rst_n)
        wr_enable |-> (wr_addr < DEPTH);
    endproperty
    assert_wr_addr: assert property (valid_wr_addr)
        else $error("[REG_FILE] wr_addr %0d out of range at time %0t",
                     wr_addr, $time);
 
    // Read addresses must be within valid range
    property valid_rd_addr_A;
        @(posedge clk) disable iff (!rst_n)
        (A_select < DEPTH);
    endproperty
    assert_rd_addr_A: assert property (valid_rd_addr_A)
        else $error("[REG_FILE] A_select %0d out of range at time %0t",
                     A_select, $time);
 
    property valid_rd_addr_B;
        @(posedge clk) disable iff (!rst_n)
        (B_select < DEPTH);
    endproperty
    assert_rd_addr_B: assert property (valid_rd_addr_B)
        else $error("[REG_FILE] B_select %0d out of range at time %0t",
                     B_select, $time);
 
    
    `endif
    */
    
    
endmodule
