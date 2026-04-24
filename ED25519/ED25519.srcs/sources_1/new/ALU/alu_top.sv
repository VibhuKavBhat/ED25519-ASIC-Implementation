module alu_top (
    input  logic         clk,
    input  logic         rst_n,
    input  logic [255:0] src_a,
    input  logic [255:0] src_b,
    input  logic [2:0]   alu_op,
    input  logic         sel_hi,
    
    output logic [255:0] alu_result,
    output logic         cmp_flag,
    output logic         mult_done
);

    // Internal routing wires
    logic         mult_start_level;
    logic [511:0] mult_product;

    // --- The Combinational Math Engine ---
    alu u_comb_alu (
        .src_a        (src_a),
        .src_b        (src_b),
        .mult_product (mult_product),
        .alu_op       (alu_op),
        .sel_hi       (sel_hi),
        .alu_result   (alu_result),
        .cmp_flag     (cmp_flag),
        .mult_start   (mult_start_level) // Continuous high signal from ALU
    );

    // --- The Pulse Generator ---
    // Converts the continuous 'mult_start' into a 1-cycle pulse
    // so the multiplier doesn't get stuck in a constant restart loop.
    // --- The 0-Latency Edge Detector ---
    logic mult_start_r;
    
    // 1. Remember the state from the PREVIOUS clock cycle
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) mult_start_r <= 1'b0;
        else        mult_start_r <= mult_start_level;
    end
    
    // 2. Fire INSTANTLY when the level goes high, before the flop catches up
    logic mult_start_pulse;
    assign mult_start_pulse = mult_start_level & ~mult_start_r;
    
    
    // --- The 18-Cycle Iterative Multiplier ---
    mult u_booth_mult (
        .clk   (clk),
        .rst_n (rst_n),
        .start (mult_start_pulse), 
        .a     (src_a),
        .b     (src_b),
        .done  (mult_done), // Routes back to the Micro-Sequencer
        .p     (mult_product)
    );

endmodule