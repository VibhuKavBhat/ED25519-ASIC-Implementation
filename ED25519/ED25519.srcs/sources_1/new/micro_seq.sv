module micro_sequencer (
    input  logic        clk, rst_n, start_seq, mult_done, cmp_flag,
    input  logic [2:0]  seq_id,
    output logic [3:0]  a_sel, b_sel, dest_sel,
    output logic        reg_we, seq_done, math_error,
    output logic [2:0]  alu_op,
    output logic        sel_hi
);

    typedef enum logic [1:0] { S_IDLE, S_FETCH, S_EXE, S_WRITE } sub_step_t;
    sub_step_t sub_step;
    logic [4:0] step_counter;
    logic [2:0] alu_op_r;

    // --- State Machine ---
   always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            step_counter <= 0;
            sub_step     <= S_IDLE;
            alu_op_r     <= 3'b0;
        end else begin
            case (sub_step)
                S_IDLE: begin
                    if (start_seq) begin
                        step_counter <= 0;
                        sub_step     <= S_FETCH;
                    end
                end
                
                S_FETCH: begin
                    alu_op_r <= alu_op; // Registered capture, no combinational loop
                    sub_step <= S_EXE;
                end
                
                S_EXE: begin
                    if (alu_op_r != 3'b010 || mult_done) 
                        sub_step <= S_WRITE;
                end
                
                S_WRITE: begin
                    if (seq_done) sub_step <= S_IDLE; // Hold here until start_seq clears
                    else begin
                        step_counter <= step_counter + 1;
                        sub_step     <= S_FETCH;
                    end
                end
            endcase
        end
    end

    // --- Instruction ROM ---
    always_comb begin
        {a_sel, b_sel, dest_sel, reg_we, alu_op, sel_hi, seq_done, math_error} = '0;
        

        if (seq_id == 3'b001) begin // RAW 512-BIT BARRETT SEQUENCE
            case (step_counter)
                
                // STEP 0: H_hi * mu_hi -> Save Low Half
                5'd0: begin
                    a_sel = 4'd9; 
                    b_sel = 4'd10; 
                    alu_op = 3'b010; 
                    sel_hi = 1'b0; 
                    dest_sel = 4'd15; 
                    reg_we = (sub_step == S_WRITE);
                end

                // STEP 1: H_hi * mu_lo -> Save High Half
                5'd1: begin
                    a_sel = 4'd9; 
                    b_sel = 4'd12; 
                    alu_op = 3'b010; 
                    sel_hi = 1'b1; 
                    dest_sel = 4'd13; 
                    reg_we = (sub_step == S_WRITE);
                end

                // STEP 2: Accumulate Cross Term 1
                5'd2: begin
                    a_sel = 4'd15; 
                    b_sel = 4'd13; 
                    alu_op = 3'b000; 
                    dest_sel = 4'd15; 
                    reg_we = (sub_step == S_WRITE);
                end
                
                // STEP 3: H_lo * mu_hi -> Save High Half
                5'd3: begin
                    a_sel = 4'd8; 
                    b_sel = 4'd10; 
                    alu_op = 3'b010; 
                    sel_hi = 1'b1; 
                    dest_sel = 4'd13; 
                    reg_we = (sub_step == S_WRITE);
                end

                // STEP 4: Build q0 (Overflow naturally drops)
                5'd4: begin
                    a_sel = 4'd15; 
                    b_sel = 4'd13; 
                    alu_op = 3'b000; 
                    dest_sel = 4'd9; 
                    reg_we = (sub_step == S_WRITE);
                end

                // STEP 5: q0 * q (Lower 256 bits)
                5'd5: begin
                    a_sel = 4'd9; 
                    b_sel = 4'd11; 
                    alu_op = 3'b010; 
                    sel_hi = 1'b0; 
                    dest_sel = 4'd15; 
                    reg_we = (sub_step == S_WRITE);
                end

                // STEP 6: r = H_lo - q0*q (Raw Subtraction)
                5'd6: begin
                    a_sel = 4'd8; 
                    b_sel = 4'd15; 
                    alu_op = 3'b101; 
                    dest_sel = 4'd15; 
                    reg_we = (sub_step == S_WRITE);
                end 
                
                // STEPS 7-9: Correction Loops (Conditional Sub)
                5'd7, 5'd8, 5'd9: begin
                    a_sel = 4'd15; 
                    b_sel = 4'd11; 
                    alu_op = 3'b001; 
                    dest_sel = 4'd15; 
                    reg_we = (sub_step == S_WRITE);
                end

                // STEP 10: Final Check
                5'd10: begin
                    a_sel = 4'd15; 
                    b_sel = 4'd11; 
                    alu_op = 3'b011; 
                    dest_sel = 4'd12; 
                    reg_we = (sub_step == S_WRITE);
                    seq_done = (sub_step == S_WRITE);
                    math_error = cmp_flag; // Panic if r >= q
                end 
                
                default: seq_done = 1'b0;
            endcase
        end
    end
endmodule