module micro_sequencer (
    input  logic        clk, rst_n, start_seq, mult_done, cmp_flag,
    input  logic [2:0]  seq_id,

    output logic [3:0]  a_sel, b_sel, dest_sel,
    output logic        reg_we, seq_done, math_error,
    output logic [2:0]  alu_op,
    output logic        sel_hi,
    output logic        mult_kick
);
    // --- ALU Opcodes ---
    localparam OP_ADD     = 3'b000;
    localparam OP_SUB_CND = 3'b001;
    localparam OP_MULT    = 3'b010;
    localparam OP_CMP     = 3'b011;
    localparam OP_PASS    = 3'b100;
    localparam OP_SUB_RAW = 3'b101;

    typedef enum logic [2:0] { S_IDLE, S_START, S_WAIT_DROP, S_EXE, S_WRITE } sub_step_t;
    sub_step_t sub_step;
    logic [4:0] step_counter;


    // --- Internal Wires & Registers ---
    logic rom_is_last_step;
    logic rom_panic;
    
    logic seq_done_reg;
    logic math_error_reg;

    // Drive outputs from clean flip-flops
    assign seq_done   = seq_done_reg;
    assign math_error = math_error_reg;

    // =========================================================================
    // 1. THE BRAIN (Strictly Flip-Flops)
    // =========================================================================
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            step_counter   <= 0;
            sub_step       <= S_IDLE;
            reg_we         <= 1'b0;
            seq_done_reg   <= 1'b0;
            math_error_reg <= 1'b0;
        end else begin
            reg_we <= 1'b0; // Default clear

            case (sub_step)
                S_IDLE: begin
                    seq_done_reg   <= 1'b0;
                    math_error_reg <= 1'b0;
                    if (start_seq) begin
                        step_counter <= 0;
                        sub_step     <= S_START;
                    end
                end
                
                S_START: begin
                    // If it's a multiply, go to the new wait state so 'done' can fall.
                    // If combinational, skip directly to EXE to save cycles!
                    if (rom_alu_op == 3'b010) sub_step <= S_WAIT_DROP; 
                    else                      sub_step <= S_EXE;       
                end
                
                S_WAIT_DROP: begin
                    // The multiplier has now safely pulled 'done' to 0.
                    sub_step <= S_EXE; 
                end
                
                S_EXE: begin
                    // Now we safely wait for 'done' to rise back to 1.
                    if (rom_alu_op != 3'b010 || mult_done) begin
                        sub_step <= S_WRITE;
                        reg_we   <= 1'b1;
                    end
                end
                
                S_WRITE: begin
                    if (rom_is_last_step || rom_panic) begin
                        seq_done_reg   <= 1'b1;
                        math_error_reg <= rom_panic ? 1'b1 : cmp_flag; 
                        sub_step       <= S_IDLE;
                    end else begin
                        step_counter <= step_counter + 1;
                        sub_step     <= S_START;
                    end
                end
                
                default: sub_step <= S_IDLE;
            endcase
        end
    end

    // =========================================================================
    // 2. THE INSTRUCTION BOOK (Pure Combinational ROM)
    // =========================================================================
    // Notice: sub_step is NO LONGER in this block. No combinational loops!
    logic [2:0] rom_alu_op; // Add this temporary wire

    always_comb begin
        // Defaults to prevent latches
        a_sel = '0; b_sel = '0; dest_sel = '0; sel_hi = '0;
        rom_alu_op = OP_PASS; // Drive the temporary wire
        rom_is_last_step = 1'b0;
        rom_panic        = 1'b0;
        
        if (seq_id == 3'b001) begin // BARRETT SEQUENCE
            case (step_counter)
                // UPDATE THESE TO DRIVE rom_alu_op INSTEAD OF alu_op
                5'd0:  begin a_sel = 4'd9;  b_sel = 4'd10; rom_alu_op = OP_MULT;    sel_hi = 1'b0; dest_sel = 4'd15; end
                5'd1:  begin a_sel = 4'd9;  b_sel = 4'd12; rom_alu_op = OP_MULT;    sel_hi = 1'b1; dest_sel = 4'd13; end
                5'd2:  begin a_sel = 4'd15; b_sel = 4'd13; rom_alu_op = OP_ADD;     sel_hi = 1'b0; dest_sel = 4'd15; end
                5'd3:  begin a_sel = 4'd8;  b_sel = 4'd10; rom_alu_op = OP_MULT;    sel_hi = 1'b1; dest_sel = 4'd13; end
                5'd4:  begin a_sel = 4'd15; b_sel = 4'd13; rom_alu_op = OP_ADD;     sel_hi = 1'b0; dest_sel = 4'd9;  end
                5'd5:  begin a_sel = 4'd9;  b_sel = 4'd11; rom_alu_op = OP_MULT;    sel_hi = 1'b0; dest_sel = 4'd15; end
                5'd6:  begin a_sel = 4'd8;  b_sel = 4'd15; rom_alu_op = OP_SUB_RAW; sel_hi = 1'b0; dest_sel = 4'd15; end
                5'd7:  begin a_sel = 4'd15; b_sel = 4'd11; rom_alu_op = OP_SUB_CND; sel_hi = 1'b0; dest_sel = 4'd15; end
                5'd8:  begin a_sel = 4'd15; b_sel = 4'd11; rom_alu_op = OP_SUB_CND; sel_hi = 1'b0; dest_sel = 4'd15; end
                5'd9:  begin a_sel = 4'd15; b_sel = 4'd11; rom_alu_op = OP_SUB_CND; sel_hi = 1'b0; dest_sel = 4'd15; end
                5'd10: begin 
                    a_sel = 4'd15; b_sel = 4'd11; rom_alu_op = OP_CMP; sel_hi = 1'b0; dest_sel = 4'd13; 
                    rom_is_last_step = 1'b1; 
                end
                default: begin 
                    rom_alu_op = OP_PASS; 
                    rom_is_last_step = 1'b1; 
                    rom_panic = 1'b1; 
                end
            endcase
        end
    end

    // THE FIX: Only send the opcode to the ALU during S_EXE!
    // During S_WRITE or S_IDLE, force it to OP_PASS to reset the edge detector.
    assign alu_op = rom_alu_op;
    assign mult_kick = (sub_step == S_WAIT_DROP);

endmodule