`timescale 1ns / 1ps

module tb_barrett_top;
    logic clk = 0, rst_n = 0;
    always #5 clk = ~clk;

    // DUT Signals
    logic start_seq, mult_done, cmp_flag, seq_done, math_error;
    logic [2:0] seq_id;
    logic [3:0] a_sel, b_sel, dest_sel;
    logic reg_we, sel_hi;
    logic [2:0] alu_op;
 
    // Instantiation
    micro_sequencer dut (.*);

    // Test Variables
    typedef struct {
        logic [255:0] h_lo;
        logic [255:0] h_hi;
        logic [255:0] expected;
        string name;
    } test_case_t;

    test_case_t tests [3];

    // 1. Mock the Register File Array
    logic [255:0] REG [15:0];

    initial begin
        // Hardcoded Edge Cases
        tests[0] = '{256'h0, 256'hFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF, 
                     256'h0c680db9a6a42217c98eb82f42a5bb0d9796e95ce3e1cbaf085ebbc6f40778c3, "Max H_hi, Zero H_lo"};
        tests[1] = '{256'h0, 256'h0, 
                     256'h0, "Zero Hash"};
        tests[2] = '{256'h1, 256'h0, 
                     256'h1, "One"};

        // Reset
        #20 rst_n = 1;

        foreach (tests[i]) begin
            $display("Running: %s", tests[i].name);
            
            // 2. Load the Mock Register File 
            REG[8]  = tests[i].h_lo;
            REG[9]  = tests[i].h_hi;
            // Note: In a real simulation, you'd wire a_sel/b_sel to output these REG values to the ALU
            
            // 3. Trigger Sequencer
            start_seq = 1; seq_id = 3'b001;
            #10 start_seq = 0;
            
            // 4. Wait for Done
            wait(seq_done);
            
            // 5. Verify Result (Replace the comments with the actual mock array)
            if (REG[12] === tests[i].expected && !math_error)
                $display("  [PASS] %s", tests[i].name);
            else
                $display("  [FAIL] %s - Got: %h", tests[i].name, REG[12]);
            
            #20; // Pause between tests
        end
        $finish;
    end
endmodule