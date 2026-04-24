module alu_top (
    input  logic         clk,
    input  logic         rst_n,
    input  logic [255:0] src_a,
    input  logic [255:0] src_b,
    input  logic [2:0]   alu_op,
    input  logic         sel_hi,
    input  logic         mult_kick,
    
    output logic [255:0] alu_result,
    output logic         cmp_flag,
    output logic         mult_done
);

    // Internal routing wires
    logic [511:0] mult_product;

    // --- The Combinational Math Engine ---
    alu u_comb_alu (
        .src_a        (src_a),
        .src_b        (src_b),
        .mult_product (mult_product),
        .alu_op       (alu_op),
        .sel_hi       (sel_hi),
        .alu_result   (alu_result),
        .cmp_flag     (cmp_flag)
    );

        
    
    // --- The 18-Cycle Iterative Multiplier ---
    mult u_booth_mult (
        .clk   (clk),
        .rst_n (rst_n),
        .start (mult_kick), 
        .a     (src_a),
        .b     (src_b),
        .done  (mult_done), // Routes back to the Micro-Sequencer
        .p     (mult_product)
    );

endmodule