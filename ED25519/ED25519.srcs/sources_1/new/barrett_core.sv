module barrett_core (
    input  logic       clk,
    input  logic       rst_n,
    input  logic       start_seq,
    input  logic [2:0] seq_id, // Drive with 3'b001 for Barrett
    
    output logic       seq_done,
    output logic       math_error
);

    // --- Internal Traces (Wires) ---
    logic [3:0]   a_sel, b_sel, dest_sel;
    logic         reg_we, sel_hi, cmp_flag, mult_done;
    logic [2:0]   alu_op;
    logic [255:0] src_a, src_b, alu_result;
    logic         mult_kick;

    // 1. The Brain
    micro_sequencer u_seq (
        .clk        (clk),
        .rst_n      (rst_n),
        .start_seq  (start_seq),
        .seq_id     (seq_id),
        .mult_done  (mult_done),
        .cmp_flag   (cmp_flag),
        .a_sel      (a_sel),
        .b_sel      (b_sel),
        .dest_sel   (dest_sel),
        .reg_we     (reg_we),
        .seq_done   (seq_done),
        .math_error (math_error),
        .alu_op     (alu_op),
        .mult_kick(mult_kick),
        .sel_hi     (sel_hi)
    );

    // 2. The Memory
    reg_file u_regs (
        .clk        (clk),
        .rst_n      (rst_n),
        .wr_enable  (reg_we),
        .wr_addr    (dest_sel),
        .data_in    (alu_result),
        .A_select   (a_sel),
        .A_out      (src_a),
        .B_select   (b_sel),
        .B_out      (src_b)
    );

    // 3. The Muscle
    alu_top u_alu (
        .clk        (clk),
        .rst_n      (rst_n),
        .src_a      (src_a),
        .src_b      (src_b),
        .alu_op     (alu_op),
        .sel_hi     (sel_hi),
        .alu_result (alu_result),
        .cmp_flag   (cmp_flag),
        .mult_done  (mult_done),
        .mult_kick  (mult_kick)
    );

endmodule