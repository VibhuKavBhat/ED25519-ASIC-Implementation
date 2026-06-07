`timescale 1ns / 1ps

module tb_fpga_demo_top;

    // -------------------------------------------------------------------------
    // Clock & Reset
    // -------------------------------------------------------------------------
    logic clk = 0;
    logic rst_n = 0;
    
    always #5 clk = ~clk; // 100 MHz clock

    // -------------------------------------------------------------------------
    // DUT Signals
    // -------------------------------------------------------------------------
    logic start_demo = 0;
    logic demo_done;
    logic signature_valid;

    // -------------------------------------------------------------------------
    // Instantiate the Top Module (The Orchestrator)
    // -------------------------------------------------------------------------
    fpga_demo_top dut (
        .clk             (clk),
        .rst_n           (rst_n),
        .start_demo      (start_demo),
        .demo_done       (demo_done),
        .signature_valid (signature_valid)
    );

    // -------------------------------------------------------------------------
    // Timeout Watchdog
    // -------------------------------------------------------------------------
    // The Math takes ~200k cycles, plus SHA-512 feeding. 
    // 5 Million cycles is plenty of time before assuming the FSM hung.
    localparam integer TIMEOUT_CYCLES = 5_000_000;
    integer cycle_count = 0;
    always @(posedge clk) begin
        cycle_count <= cycle_count + 1;
        if (cycle_count >= TIMEOUT_CYCLES) begin
            $display("\n[FATAL] Simulation exceeded %0d cycles! An FSM is likely hung.", TIMEOUT_CYCLES);
            $stop;
        end
    end

    // -------------------------------------------------------------------------
    // Main Stimulus
    // -------------------------------------------------------------------------
    initial begin
        $display("=============================================================");
        $display("  Starting Full System Simulation (fpga_demo_top)...");
        $display("=============================================================");

        // 1. Apply Reset
        rst_n = 0;
        start_demo = 0;
        repeat(10) @(posedge clk);
        rst_n = 1;
        $display("[%0t] System Reset Released.", $time);
        repeat(10) @(posedge clk);

        // 2. Pulse Start Demo (Acts like pressing the button on the FPGA)
        $display("[%0t] Pulsing start_demo...", $time);
        start_demo = 1;
        @(posedge clk);
        start_demo = 0;

        // 3. Wait for the Orchestrator to finish
        $display("[%0t] Waiting for hardware to complete hashing and math...", $time);
        wait (demo_done === 1'b1);
        @(posedge clk); // Let signals settle

        // 4. Check Results
        $display("\n=============================================================");
        if (signature_valid === 1'b1) begin
            $display("  🏆 [PASS] INTEGRATION SUCCESSFUL 🏆");
            $display("     The Orchestrator correctly read the BRAM, fed the SHA,");
            $display("     bootloaded the constants, and verified the firmware.");
        end else begin
            $display("  ❌ [FAIL] INTEGRATION FAILED ❌");
            $display("     The signature was flagged as INVALID. Check your byte-swaps");
            $display("     or ensure the constants loaded correctly.");
        end
        $display("  Total Clock Cycles Elapsed: %0d", cycle_count);
        $display("=============================================================\n");

        $finish;
    end

    // -------------------------------------------------------------------------
    // Optional Waveform Dump
    // -------------------------------------------------------------------------
    initial begin
        $dumpfile("tb_fpga_demo_top.vcd");
        $dumpvars(0, tb_fpga_demo_top);
    end

endmodule