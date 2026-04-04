`timescale 1ns / 1ps

// =============================================================================
// Module:      tb_reg_file.sv
// Project:     ED25519 Hardware Accelerator
// Description: Self-checking testbench for reg_file.sv
//
// Test Cases:
//   1.  Reset behavior - outputs zero after reset
//   2.  Basic write then read - 1 cycle latency contract
//   3.  Simultaneous dual port read - port independence
//   4.  All 16 registers - no address aliasing
//   5.  Write enable gating - no write when wr_enable=0
//   6.  Back-to-back writes - last write wins
//   7.  Read-after-write timing - explicit 1 cycle latency
//   8.  Same address both ports - A and B independent
//   9.  ED25519 curve constants - REG[13] and REG[14]
//   10. Random stress - 1000 random write/read pairs vs shadow model
// =============================================================================

module tb_reg_file;

    // =========================================================================
    // Parameters
    // =========================================================================
    parameter WIDTH      = 256;
    parameter DEPTH      = 16;
    parameter ADDR_W     = 4;
    parameter CLK_PERIOD = 10; // 100MHz

    // =========================================================================
    // DUT Signals
    // =========================================================================
    logic                clk;
    logic                rst_n;
    logic                wr_enable;
    logic [ADDR_W-1:0]  wr_addr;
    logic [WIDTH-1:0]   data_in;
    logic [ADDR_W-1:0]  A_select;
    logic [ADDR_W-1:0]  B_select;
    logic [WIDTH-1:0]   A_out;
    logic [WIDTH-1:0]   B_out;

    // =========================================================================
    // Scoreboard - shadow memory mirrors expected DUT state
    // Updated every time we write, compared against DUT on every read
    // =========================================================================
    logic [WIDTH-1:0] shadow [0:DEPTH-1];

    // =========================================================================
    // Pass/Fail Counters
    // =========================================================================
    int pass_count = 0;
    int fail_count = 0;

    // =========================================================================
    // DUT
    // =========================================================================
    reg_file #(
        .WIDTH  (WIDTH),
        .DEPTH  (DEPTH),
        .ADDR_W (ADDR_W)
    ) dut (
        .clk       (clk),
        .rst_n     (rst_n),
        .wr_enable (wr_enable),
        .wr_addr   (wr_addr),
        .data_in   (data_in),
        .A_select  (A_select),
        .B_select  (B_select),
        .A_out     (A_out),
        .B_out     (B_out)
    );

    // =========================================================================
    // Clock - 100MHz
    // =========================================================================
    initial clk = 0;
    always #(CLK_PERIOD/2) clk = ~clk;

    // =========================================================================
    // Task: Apply reset
    // Async assert - drive rst_n low immediately, not on clock edge
    // Sync deassert - release on clock edge
    // =========================================================================
    task apply_reset();
        wr_enable = 0;
        wr_addr   = '0;
        data_in   = '0;
        A_select  = '0;
        B_select  = '0;

        // Assert asynchronously - mid cycle intentional
        rst_n = 0;
        #(CLK_PERIOD * 2.5);

        // Deassert synchronously - on rising edge
        @(posedge clk);
        #1;
        rst_n = 1;
                       
        $display("[TB] Reset complete at time %0t", $time);
    endtask

    // =========================================================================
    // Task: Write one register + update shadow
    // =========================================================================
    task write_reg(
        input logic [ADDR_W-1:0] addr,
        input logic [WIDTH-1:0]  data
    );
        @(negedge clk);
        wr_enable = 1;
        wr_addr   = addr;
        data_in   = data;
        @(posedge clk);        
        wr_enable = 0;
        shadow[addr] = data;
    endtask

    // =========================================================================
    // Task: Read port A, compare against expected
    // =========================================================================
    task read_check_A(
        input logic [ADDR_W-1:0] addr,
        input logic [WIDTH-1:0]  expected,
        input string             test_name
    );
        @(negedge clk);
        A_select = addr;
        @(posedge clk);
        @(posedge clk); // one cycle latency

        if (A_out === expected) begin
            pass_count++;
            $display("[PASS] %s | REG[%0d] A_out correct", test_name, addr);
        end else begin
            fail_count++;
            $display("[FAIL] %s | REG[%0d] A_out MISMATCH", test_name, addr);
            $display("       Expected : %h", expected);
            $display("       Got      : %h", A_out);
        end
    endtask

    // =========================================================================
    // Task: Read both ports simultaneously, compare both
    // =========================================================================
    task read_check_dual(
        input logic [ADDR_W-1:0] addr_a,
        input logic [ADDR_W-1:0] addr_b,
        input logic [WIDTH-1:0]  exp_a,
        input logic [WIDTH-1:0]  exp_b,
        input string             test_name
    );
        @(negedge clk);
        A_select = addr_a;
        B_select = addr_b;
        @(posedge clk);
        @(posedge clk);

        if (A_out === exp_a && B_out === exp_b) begin
            pass_count++;
            $display("[PASS] %s | Both ports correct", test_name);
        end else begin
            fail_count++;
            if (A_out !== exp_a) begin
                $display("[FAIL] %s | A_out MISMATCH REG[%0d]", test_name, addr_a);
                $display("       Expected : %h", exp_a);
                $display("       Got      : %h", A_out);
            end
            if (B_out !== exp_b) begin
                $display("[FAIL] %s | B_out MISMATCH REG[%0d]", test_name, addr_b);
                $display("       Expected : %h", exp_b);
                $display("       Got      : %h", B_out);
            end
        end
    endtask

    // =========================================================================
    // Main Test Sequence
    // =========================================================================
    initial begin
        $display("================================================");
        $display("  reg_file Testbench - ED25519 Accelerator      ");
        $display("================================================");

        foreach (shadow[i]) shadow[i] = '0;

        // -----------------------------------------------------------------
        // TEST 1: Reset Behavior
        // -----------------------------------------------------------------
        $display("\n--- TEST 1: Reset Behavior ---");
        apply_reset();

        @(negedge clk);
        A_select = '0;
        B_select = '0;
        @(posedge clk);
        @(posedge clk);

        if (A_out === '0 && B_out === '0) begin
            pass_count++;
            $display("[PASS] TEST 1 | Outputs zero after reset");
        end else begin
            fail_count++;
            $display("[FAIL] TEST 1 | Outputs not zero after reset");
            $display("       A_out=%h B_out=%h", A_out, B_out);
        end

        if (!$isunknown(A_out) && !$isunknown(B_out)) begin
            pass_count++;
            $display("[PASS] TEST 1 | No X on outputs after reset");
        end else begin
            fail_count++;
            $display("[FAIL] TEST 1 | X detected on outputs after reset");
        end

        // -----------------------------------------------------------------
        // TEST 2: Basic Write Then Read
        // -----------------------------------------------------------------
        $display("\n--- TEST 2: Basic Write Then Read ---");
        begin
            logic [WIDTH-1:0] test_val;
            test_val = 256'hDEADBEEFCAFEBABEDEADBEEFCAFEBABEDEADBEEFCAFEBABEDEADBEEFCAFEBABE;
            write_reg(4'd5, test_val);
            read_check_A(4'd5, test_val, "TEST 2");
        end

        // -----------------------------------------------------------------
        // TEST 3: Simultaneous Dual Port Read
        // -----------------------------------------------------------------
        $display("\n--- TEST 3: Simultaneous Dual Port Read ---");
        begin
            logic [WIDTH-1:0] val_r2, val_r7;
            val_r2 = 256'hAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA;
            val_r7 = 256'h5555555555555555555555555555555555555555555555555555555555555555;
            write_reg(4'd2, val_r2);
            write_reg(4'd7, val_r7);
            read_check_dual(4'd2, 4'd7, val_r2, val_r7, "TEST 3");
        end

        // -----------------------------------------------------------------
        // TEST 4: All 16 Registers No Aliasing
        // -----------------------------------------------------------------
        $display("\n--- TEST 4: All 16 Registers No Aliasing ---");
        begin
            logic [WIDTH-1:0] vals [0:15];
            for (int i = 0; i < DEPTH; i++) begin
                vals[i] = {32{8'(i + 1)}};
                write_reg(4'(i), vals[i]);
            end
            for (int i = 0; i < DEPTH; i++) begin
                read_check_A(4'(i), vals[i], $sformatf("TEST 4 REG[%0d]", i));
            end
        end

        // -----------------------------------------------------------------
        // TEST 5: Write Enable Gating
        // -----------------------------------------------------------------
        $display("\n--- TEST 5: Write Enable Gating ---");
        begin
            logic [WIDTH-1:0] protected_val;
            protected_val = 256'hC0FFEE00C0FFEE00C0FFEE00C0FFEE00C0FFEE00C0FFEE00C0FFEE00C0FFEE00;
            write_reg(4'd3, protected_val);

            wr_enable = 0;
            repeat (8) begin
                @(negedge clk);
                data_in = $urandom();
                wr_addr = 4'd3;
            end
            
            read_check_A(4'd3, protected_val, "TEST 5");
        end

        // -----------------------------------------------------------------
        // TEST 6: Back-to-Back Writes - Last Write Wins
        // -----------------------------------------------------------------
        $display("\n--- TEST 6: Back-to-Back Writes Same Register ---");
        begin
            logic [WIDTH-1:0] first_val, second_val;
            first_val  = 256'hFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF;
            second_val = 256'h0000000000000000000000000000000000000000000000000000000000000001;

            @(negedge clk);
            wr_enable = 1;
            wr_addr   = 4'd9;
            data_in   = first_val;
            @(posedge clk);
            
            data_in   = second_val;
            @(posedge clk);
            
            wr_enable = 0;
            shadow[9] = second_val;

            read_check_A(4'd9, second_val, "TEST 6 last write wins");
        end

        // -----------------------------------------------------------------
        // TEST 7: Explicit 1-Cycle Latency Verification
        // Confirm data NOT valid same cycle address presented
        // Confirm data IS valid one cycle later
        // -----------------------------------------------------------------
        $display("\n--- TEST 7: 1-Cycle Read Latency ---");
        begin
            logic [WIDTH-1:0] lat_val, captured_early, captured_late;
            lat_val = 256'hFEDCBA9876543210FEDCBA9876543210FEDCBA9876543210FEDCBA9876543210;

            // Write something different first so we know the old value
            write_reg(4'd11, 256'h0);
            shadow[11] = 256'h0;

            // Now write the new value
            write_reg(4'd11, lat_val);

            // Present address
            @(negedge clk);
            A_select = 4'd11;

            // Sample SAME cycle address presented
            @(posedge clk);
            captured_early = A_out;

            // Sample ONE cycle later
            @(posedge clk);
            captured_late = A_out;

            if (captured_late === lat_val) begin
                pass_count++;
                $display("[PASS] TEST 7 | Data valid 1 cycle after address");
            end else begin
                fail_count++;
                $display("[FAIL] TEST 7 | Data not valid after 1 cycle");
                $display("       Expected : %h", lat_val);
                $display("       Got      : %h", captured_late);
            end

            if (captured_early !== lat_val) begin
                pass_count++;
                $display("[PASS] TEST 7 | Read confirmed synchronous (not combinational)");
            end else begin
                fail_count++;
                $display("[FAIL] TEST 7 | Data appeared same cycle - read is ASYNC");
            end
        end

        // -----------------------------------------------------------------
        // TEST 8: Same Address on Both Ports
        // -----------------------------------------------------------------
        $display("\n--- TEST 8: Same Address Both Ports ---");
        begin
            logic [WIDTH-1:0] shared_val;
            shared_val = 256'hBEEFBEEFBEEFBEEFBEEFBEEFBEEFBEEFBEEFBEEFBEEFBEEFBEEFBEEFBEEFBEEF;
            write_reg(4'd6, shared_val);
            read_check_dual(4'd6, 4'd6, shared_val, shared_val, "TEST 8");
        end

        // -----------------------------------------------------------------
        // TEST 9: ED25519 Curve Constants
        // -----------------------------------------------------------------
        $display("\n--- TEST 9: ED25519 Curve Constants ---");
        begin
            logic [WIDTH-1:0] d_const, sqrt_m1_const;
            d_const       = 256'h52036cee2b6ffe738cc740797779e89800700a4d4141d8ab75eb4dca135978a3;
            sqrt_m1_const = 256'h2b8324804fc1df0b2b4d00993dfbd7a72f431806ad2fe478c4ee1b274a0ea0b0;

            write_reg(4'd13, d_const);
            write_reg(4'd14, sqrt_m1_const);
            read_check_dual(4'd13, 4'd14, d_const, sqrt_m1_const, "TEST 9");
        end

        // -----------------------------------------------------------------
        // TEST 10: Random Stress - 1000 Vectors vs Shadow Model
        // -----------------------------------------------------------------
        $display("\n--- TEST 10: Random Stress 1000 Vectors ---");
        begin
            logic [ADDR_W-1:0] rand_addr;
            logic [WIDTH-1:0]  rand_data;
            int stress_fail = 0;

            foreach (shadow[i]) shadow[i] = '0;

            // 1000 random writes
            repeat (1000) begin
                rand_addr = $urandom_range(0, DEPTH-1);
                rand_data = {$urandom(), $urandom(), $urandom(), $urandom(),
                             $urandom(), $urandom(), $urandom(), $urandom()};
                write_reg(rand_addr, rand_data);
            end

            // Read all 16 back, compare against shadow
            for (int i = 0; i < DEPTH; i++) begin
                @(negedge clk);
                A_select = 4'(i);
                @(posedge clk);
                @(posedge clk);

                if (A_out !== shadow[i]) begin
                    stress_fail++;
                    $display("[FAIL] TEST 10 | REG[%0d] mismatch", i);
                    $display("       Expected : %h", shadow[i]);
                    $display("       Got      : %h", A_out);
                end
            end

            if (stress_fail == 0) begin
                pass_count++;
                $display("[PASS] TEST 10 | All stress vectors passed");
            end else begin
                fail_count++;
                $display("[FAIL] TEST 10 | %0d stress failures", stress_fail);
            end
        end

        // -----------------------------------------------------------------
        // Final Report
        // -----------------------------------------------------------------
        $display("\n================================================");
        $display("  TESTBENCH COMPLETE");
        $display("  PASSED : %0d", pass_count);
        $display("  FAILED : %0d", fail_count);
        $display("------------------------------------------------");
        if (fail_count == 0)
            $display("  STATUS : ALL TESTS PASSED -- BLOCK VERIFIED");
        else
            $display("  STATUS : FAILURES DETECTED -- DO NOT PROCEED");
        $display("================================================");

        $finish;
    end

    // =========================================================================
    // Timeout Watchdog
    // =========================================================================
    initial begin
        #500000;
        $display("[TIMEOUT] Simulation exceeded limit");
        $finish;
    end

    // =========================================================================
    // Waveform Dump
    // =========================================================================
    initial begin
        $dumpfile("tb_reg_file.vcd");
        $dumpvars(0, tb_reg_file);
    end

endmodule