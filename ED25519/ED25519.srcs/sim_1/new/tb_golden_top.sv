`timescale 1ns / 1ps

// =============================================================================
// Testbench: tb_golden_top
// DUT:       top_ed25519
// Mode:      Automated 1,000-Vector Fuzzer / Stress Test
// =============================================================================

module tb_golden_top;

    // -------------------------------------------------------------------------
    // Clock & reset
    // -------------------------------------------------------------------------
    logic clk     = 0;
    logic rst_n   = 0;
    always #5 clk = ~clk;          // 100 MHz

    // -------------------------------------------------------------------------
    // DUT ports
    // -------------------------------------------------------------------------
    logic         start_verify = 0;
    logic [255:0] ext_data_1   = '0;
    logic [255:0] ext_data_2   = '0;
    logic [255:0] otp_data     = '0;
    logic [1:0]   data_sel     = 2'b00;
    logic         verify_done;
    logic         signature_valid;

    // -------------------------------------------------------------------------
    // DUT instantiation
    // -------------------------------------------------------------------------
    top_ed25519 dut (
        .clk             (clk),
        .rst_n           (rst_n),
        .start_verify    (start_verify),
        .ext_data_1      (ext_data_1),
        .ext_data_2      (ext_data_2),
        .otp_data        (otp_data),
        .data_sel        (data_sel),
        .verify_done     (verify_done),
        .signature_valid (signature_valid)
    );

    // -------------------------------------------------------------------------
    // Hierarchical shorthand for the register file memory array
    // -------------------------------------------------------------------------
    `define MEM dut.u_regs.mem

    // -------------------------------------------------------------------------
    // Constants (Untouched)
    // -------------------------------------------------------------------------

    // --- Curve / hardware constants ---
    localparam logic [255:0] CONST_ZERO  = 256'd0;
    localparam logic [255:0] CONST_ONE   = 256'd1;

    localparam logic [255:0] CURVE_D =
        256'h52036cee2b6ffe738cc740797779e89800700a4d4141d8ab75eb4dca135978a3;

    localparam logic [255:0] CURVE_2D =
        256'h2406d9dc56dffce7198e80f2eef3d13000e0149a8283b156ebd69b9426b2f159;

    localparam logic [255:0] SQRT_M1 =
        256'h2b8324804fc1df0b2b4d00993dfbd7a72f431806ad2fe478c4ee1b274a0ea0b0;

    // --- Base point G (extended coordinates, Z=1) ---
    localparam logic [255:0] G_X =
        256'h216936d3cd6e53fec0a4e231fdd6dc5c692cc7609525a7b2c9562d608f25d51a;

    localparam logic [255:0] G_Y =
        256'h6666666666666666666666666666666666666666666666666666666666666658;

    localparam logic [255:0] G_Z = 256'd1;

    localparam logic [255:0] G_T =
        256'h67875f0fd78b766566ea4e8e64abe37d20f09f80775152f56dde8ab3a5b7dda3;

    // --- Barrett reduction constants (mod L) ---
    localparam logic [255:0] BARRETT_MU_HI = 
        256'h000000000000000000000000000000000000000000000000000000000000000f;

    localparam logic [255:0] CURVE_ORDER_L = 
        256'h1000000000000000000000000000000014def9dea2f79cd65812631a5cf5d3ed;

    localparam logic [255:0] BARRETT_MU_LO = 
        256'hffffffffffffffffffffffffffffffeb2106215d086329a7ed9ce5a30a2c131b;

    // --- Endian-Corrected SystemVerilog Constants (TV3 left for reference) ---
    localparam logic [255:0] TV3_PUB_KEY =
        256'h34b2874065faed60e133913336601a5fdd7ac4b85a6f15ad584cfdda7ea0ac65;

    localparam logic [255:0] TV3_SIG_R =
        256'h68fade141a82a0b543f4e604f859eaf762d5424e8a685f5bceff373eb0b3062a;

    localparam logic [255:0] TV3_SIG_S =
        256'h0cace2f11636e7cec89e16f16885b2d251a77dc94a5d1c97fdd29ff5272ac5e0;

    localparam logic [255:0] HASH_LO =
        256'h12a1978f7120b69ef05568b740cc7146a52edcfa54db30fc8a5bffdd3032922b;

    localparam logic [255:0] HASH_HI =
        256'he11a90a7bb525edfeb720c914f32fe20dc4030105e758bf2c74fce71f783228b;

    // -------------------------------------------------------------------------
    // Timeout watchdog (Increased to 250M for 1000 vectors)
    // -------------------------------------------------------------------------
    localparam integer TIMEOUT_CYCLES = 250_000_000; 
    integer cycle_count = 0;

    always @(posedge clk) begin
        cycle_count <= cycle_count + 1;
        if (cycle_count >= TIMEOUT_CYCLES) begin
            $display("[TIMEOUT] Simulation exceeded %0d cycles — aborting.", TIMEOUT_CYCLES);
            $finish;
        end
    end

    // -------------------------------------------------------------------------
    // Stress Test Memory & Loop Variables
    // -------------------------------------------------------------------------
    // 1288 bits: [1287:1280] = Flag, [1279:1024] = PubKey, [1023:768] = R, 
    //            [767:512] = S, [511:256] = Hash_Lo, [255:0] = Hash_Hi
    logic [1287:0] vector_mem [0:999];
    logic          expected_valid;
    integer        i;

    // -------------------------------------------------------------------------
    // Main stimulus
    // -------------------------------------------------------------------------
    initial begin
        $readmemh("stress_vectors.mem", vector_mem);

        $display("=============================================================");
        $display("  Starting 1,000-Vector Stress Test Gauntlet...");
        $display("=============================================================");

        // ------------------------------------------------------------------
        // The 1,000-Vector Gauntlet
        // ------------------------------------------------------------------
        for (i = 0; i < 1000; i++) begin
            
            // 1. HARD RESET (Clears FSM states and verify_done flags)
            rst_n = 0;
            @(posedge clk); #1; 
            rst_n = 1;
            @(posedge clk); #1;

            // 2. RELOAD STATIC CONSTANTS (Reset likely wiped the register file)
            `MEM[24] = CONST_ZERO;       
            `MEM[25] = CONST_ONE;        
            `MEM[26] = CURVE_D;          
            `MEM[27] = CURVE_2D;         
            `MEM[28] = SQRT_M1;          
            `MEM[4]  = G_X;
            `MEM[5]  = G_Y;
            `MEM[6]  = G_Z;
            `MEM[7]  = G_T;
            `MEM[10] = BARRETT_MU_HI;
            `MEM[11] = CURVE_ORDER_L;
            `MEM[12] = BARRETT_MU_LO;

            // 3. LOAD DYNAMIC VECTOR DATA
            expected_valid = vector_mem[i][1280]; 
            `MEM[21] = vector_mem[i][1279:1024];  // pubKey
            `MEM[20] = vector_mem[i][1023:768];   // sig_R
            `MEM[23] = vector_mem[i][767:512];    // sig_S
            `MEM[8]  = vector_mem[i][511:256];    // HASH_LO
            `MEM[9]  = vector_mem[i][255:0];      // HASH_HI

            // 4. PULSE START
            @(posedge clk); #1;
            start_verify = 1;
            @(posedge clk); #1;
            start_verify = 0;

            // 5. WAIT FOR COMPUTATION
            wait (verify_done === 1'b1);
            @(posedge clk); 

            // 6. CHECK RESULTS
            if (signature_valid !== expected_valid) begin
                $display("\n=============================================================");
                $display("  [FATAL ERROR] Silicon Mismatch on Stress Vector %0d!", i);
                $display("  Expected valid = %0b | Hardware output = %0b", expected_valid, signature_valid);
                $display("=============================================================");
                $stop;
            end

            // Print progress
            if (i % 10 == 0 || i == 999) begin
                $display("  [%0t] Passed %0d / 1000 vectors...", $time, i + 1);
            end

            // Small delay before next vector resets
            repeat(5) @(posedge clk);
        end

        // ------------------------------------------------------------------
        // Report Final Victory
        // ------------------------------------------------------------------
        $display("\n=============================================================");
        $display("  🏆 [SUCCESS] TAPE-OUT READY 🏆");
        $display("  All 1,000 Positive & Negative Stress Vectors Passed.");
        $display("  Total cycles elapsed: %0d", cycle_count);
        $display("=============================================================\n");
        
        $finish;
    end

    // -------------------------------------------------------------------------
    // Optional waveform dump
    // -------------------------------------------------------------------------
    initial begin
        $dumpfile("tb_golden_top.vcd");
        $dumpvars(0, tb_golden_top);
    end

endmodule