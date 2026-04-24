`timescale 1ns / 1ps

module tb_alu_top;

    // --- Clocks and Resets ---
    logic clk = 0;
    logic rst_n = 0;
    always #5 clk = ~clk; // 10ns period (100 MHz)

    // --- Signals connecting to DUT ---
    logic [255:0] src_a;
    logic [255:0] src_b;
    logic [2:0]   alu_op;
    logic         sel_hi;

    logic [255:0] alu_result;
    logic         cmp_flag;
    logic         mult_done;

    // --- ALU Opcodes ---
    localparam OP_ADD     = 3'b000;
    localparam OP_SUB_CND = 3'b001;
    localparam OP_MULT    = 3'b010;
    localparam OP_CMP     = 3'b011;
    localparam OP_PASS    = 3'b100;
    localparam OP_SUB_RAW = 3'b101;

    // --- Instantiate the DUT ---
    alu_top dut (
        .clk(clk),
        .rst_n(rst_n),
        .src_a(src_a),
        .src_b(src_b),
        .alu_op(alu_op),
        .sel_hi(sel_hi),
        .alu_result(alu_result),
        .cmp_flag(cmp_flag),
        .mult_done(mult_done)
    );

    int error_count = 0;

    // --- Task: Test Combinational Operations (0 Latency) ---
    task automatic check_comb(
        input string  test_name, 
        input [255:0] exp_res, 
        input         exp_cmp
    );
        // Wait 1 clock cycle to allow flip-flops to settle if needed
        @(posedge clk);
        #1; 
        
        if (alu_result !== exp_res || cmp_flag !== exp_cmp) begin
            $display("[FAIL] %s", test_name);
            $display("       Expected: Res=%h, Cmp=%b", exp_res, exp_cmp);
            $display("       Got     : Res=%h, Cmp=%b", alu_result, cmp_flag);
            error_count++;
        end else begin
            $display("[PASS] %s", test_name);
        end
    endtask

    // --- Task: Test Sequential Multiplication (18 Cycle Latency) ---
    task automatic check_mult(
        input string  test_name, 
        input [255:0] exp_res
    );
        int cycle_count = 0;

        // ---------------------------------------------------------
        // THE FIX: Wait 1 cycle for the start pulse to propagate 
        // and for the multiplier to pull 'done' LOW from the last run!
        // ---------------------------------------------------------
        @(posedge clk); 
        #1; 

        // Now we can safely wait for it to go high again
        while (!mult_done) begin
            @(posedge clk);
            #1;
            cycle_count++;
            if (cycle_count > 30) begin
                $display("[FATAL] %s - Timeout! Multiplier got stuck.", test_name);
                error_count++;
                return;
            end
        end
        
        if (alu_result !== exp_res) begin
            $display("[FAIL] %s (Took %0d cycles)", test_name, cycle_count + 1);
            $display("       Expected: %h", exp_res);
            $display("       Got     : %h", alu_result);
            error_count++;
        end else begin
            $display("[PASS] %s (Finished in %0d cycles)", test_name, cycle_count + 1);
        end

        // ---------------------------------------------------------
        // THE REVIEWER'S CLEANUP FIX
        // Drop opcode BEFORE the clock edge, just like real hardware
        // ---------------------------------------------------------
        alu_op = OP_PASS; 
        
        @(posedge clk); // RTL sees OP_PASS, starts clearing
        @(posedge clk); // mult_start_r is now fully 0. Safe to return.
    endtask

    // --- Test Vectors ---
    initial begin
        $display("========================================");
        $display(" Starting alu_top Simulation");
        $display("========================================");

        // 1. Reset the system
        src_a = '0; src_b = '0; alu_op = OP_PASS; sel_hi = 0;
        #20 rst_n = 1;
        @(posedge clk);

        // 2. Test Combinational Math (ADD)
        src_a = 256'd500; src_b = 256'd250; alu_op = OP_ADD;
        check_comb("COMB: 500 + 250", 256'd750, 1'b0);

        // 3. Test Sequential Math: A maxed 256-bit number multiplied by 2
        // A = 0xFFF...FFF (which is 2^256 - 1)
        // B = 2
        // True Product = 2 * (2^256 - 1) = (2^257 - 2)
        // Lower 256 bits = 0xFFF...FFE
        // Upper 256 bits = 0x000...001
        
        $display("--- Initiating 18-Cycle Multiplications ---");
        src_a = 256'hFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF;
        src_b = 256'd2;
        
        // 3a. Read the Lower Half
        alu_op = OP_MULT; sel_hi = 0;
        check_mult("MULT_LO: (Max * 2) Lower Half", 256'hFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFE);

        // 3b. Read the Upper Half
        src_a = 256'hFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF;
        src_b = 256'd2;
        alu_op = OP_MULT; sel_hi = 1;
        check_mult("MULT_HI: (Max * 2) Upper Half", 256'h0000000000000000000000000000000000000000000000000000000000000001);

        // ---------------------------------------------------------
        // Reviewer Item 4: Small known multiply
        // ---------------------------------------------------------
        $display("--- Testing Small Known Multiply ---");
        src_a = 256'd3; src_b = 256'd5; alu_op = OP_MULT; sel_hi = 0;
        check_mult("MULT_SMALL: 3 * 5", 256'd15);

        // ---------------------------------------------------------
        // Reviewer Item 5: Abort/Restart
        // ---------------------------------------------------------
        $display("--- Testing Abort/Restart ---");
        // Start a massive 100x100 multiplication
        src_a = 256'd100; src_b = 256'd100; alu_op = OP_MULT; sel_hi = 0;
        
        // Wait 5 clock cycles to simulate a mid-flight FSM abort
        repeat(5) @(posedge clk); 
        
        // Drop the opcode (simulating the FSM moving to a new state)
        alu_op = OP_PASS; 
        @(posedge clk); 
        
        // Immediately trigger a brand new multiplication
        src_a = 256'd7; src_b = 256'd6; alu_op = OP_MULT; 
        // This should safely overwrite the aborted 100x100 calculation
        check_mult("MULT_ABORT: Aborted mid-flight, calculated 7 * 6", 256'd42);

        // ---------------------------------------------------------
        // Reviewer Items 1, 2, 3: Combinational Edge Cases
        // ---------------------------------------------------------
        $display("--- Testing Combinational Edge Cases ---");
        
        // OP_SUB_CND branches
        src_a = 256'd10; src_b = 256'd20; alu_op = OP_SUB_CND;
        check_comb("SUB_CND (A < B): Pass A unchanged", 256'd10, 1'b0);
        
        src_a = 256'd20; src_b = 256'd10; alu_op = OP_SUB_CND;
        check_comb("SUB_CND (A >= B): Subtract B from A", 256'd10, 1'b1);
        
        // OP_SUB_RAW wrapping
        src_a = 256'd5; src_b = 256'd8; alu_op = OP_SUB_RAW;
        // 5 - 8 = -3. Underflow should drop cmp_flag to 0
        check_comb("SUB_RAW (Underflow): 5 - 8", -256'd3, 1'b0); 
        
        // OP_CMP polarities
        src_a = 256'd100; src_b = 256'd50; alu_op = OP_CMP;
        check_comb("CMP (A >= B): Flag should be 1", 256'd100, 1'b1);
        
        src_a = 256'd50; src_b = 256'd100; alu_op = OP_CMP;
        check_comb("CMP (A < B): Flag should be 0", 256'd50, 1'b0);
        
        $display("========================================");
        if (error_count == 0)
            $display(" [SUCCESS] alu_top Handshake and Math Verified!");
        else
            $display(" [WARNING] alu_top failed %0d tests.", error_count);
        $display("========================================");
        
        $finish;
    end
endmodule