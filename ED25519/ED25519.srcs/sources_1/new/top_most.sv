module fpga_demo_top (
    input  logic clk,
    input  logic rst_n,
    input  logic start_demo,
    
    // Status Outputs (Drive to LEDs on Nexys 4)
    output logic demo_done,
    output logic signature_valid
);
  //  logic clk;
  //  clk_wiz_0 u_clock_divider (
  //      .clk_in1  (clk_100mhz), // Raw 100MHz from the board goes IN
  //      .clk_out1 (clk)         // The safe 20MHz clock comes OUT and takes over the "clk" name
  //  );

    // --------------------------------------------------------
    // Byte Swap Helper (Fixes Little-Endian requirements)
    // --------------------------------------------------------
    function automatic logic [31:0] bswap(input logic [31:0] v);
        return {v[7:0], v[15:8], v[23:16], v[31:24]};
    endfunction

    // --------------------------------------------------------
    // Internal Wires & Registers
    // --------------------------------------------------------
    logic [15:0] bram_addr;
    logic [31:0] bram_dout;
    
    logic [5:0]  sha_addr;
    logic        sha_wen;
    logic [31:0] sha_wdata;
    logic [31:0] sha_rdata;
    logic        sha_intr;
    
    logic        ed_start;
    logic        ed_done;
    logic        ed_valid;
    
    logic        ed_ext_we;
    logic [4:0]  ed_ext_dest_sel;
    logic [1:0]  ed_data_sel;
    logic [255:0] ed_ext_data_1;

    // Extracted Ed25519 Registers
    logic [511:0] hash_reg;
    logic [255:0] s_reg, r_reg, pubkey_reg;
    logic [31:0]  msg_length;
    logic [31:0]  words_sent;
    logic [4:0]   sha_read_idx;
    logic [3:0]   read_count;

    // --- Ed25519 Hardware Constants ---
    localparam logic [255:0] CONST_ZERO = 256'd0;
    localparam logic [255:0] CONST_ONE  = 256'd1;
    localparam logic [255:0] CURVE_D    = 256'h52036cee2b6ffe738cc740797779e89800700a4d4141d8ab75eb4dca135978a3;
    localparam logic [255:0] CURVE_2D   = 256'h2406d9dc56dffce7198e80f2eef3d13000e0149a8283b156ebd69b9426b2f159;
    localparam logic [255:0] SQRT_M1    = 256'h2b8324804fc1df0b2b4d00993dfbd7a72f431806ad2fe478c4ee1b274a0ea0b0;
    localparam logic [255:0] G_X        = 256'h216936d3cd6e53fec0a4e231fdd6dc5c692cc7609525a7b2c9562d608f25d51a;
    localparam logic [255:0] G_Y        = 256'h6666666666666666666666666666666666666666666666666666666666666658;
    localparam logic [255:0] G_Z        = 256'd1;
    localparam logic [255:0] G_T        = 256'h67875f0fd78b766566ea4e8e64abe37d20f09f80775152f56dde8ab3a5b7dda3;
    localparam logic [255:0] MU_HI      = 256'h000000000000000000000000000000000000000000000000000000000000000f;
    localparam logic [255:0] MU_LO      = 256'hffffffffffffffffffffffffffffffeb2106215d086329a7ed9ce5a30a2c131b;
    localparam logic [255:0] CURVE_L    = 256'h1000000000000000000000000000000014def9dea2f79cd65812631a5cf5d3ed;

    // A counter to step through the 12 constants
    logic [3:0] const_idx;

    // --------------------------------------------------------
    // FSM States
    // --------------------------------------------------------
    typedef enum logic [4:0] {
        ST_IDLE,
        ST_READ_LEN,       
        ST_LOAD_CONST_REQ,  
        ST_LOAD_CONST_ACK,  
        ST_WAIT_LEN,
        ST_READ_S_REQ,
        ST_READ_S_ACK,
        ST_CFG_SHA_LEN,
        ST_CFG_SHA_CTRL,
        ST_SHA_FEED_WAIT,
        ST_SHA_FEED_WRITE,
        ST_SHA_BRAM_DELAY,
        ST_WAIT_HASH,
        ST_READ_HASH_REQ,
        ST_READ_HASH_ACK,
        ST_LOAD_REG_S,
        ST_LOAD_REG_R,
        ST_LOAD_REG_A,
        ST_LOAD_REG_HLO,
        ST_LOAD_REG_HHI,
        ST_ED_START,
        ST_ED_WAIT,
        ST_DONE
    } sys_state_t;
    
    sys_state_t state;

    // --------------------------------------------------------
    // Sub-Module Instantiations
    // --------------------------------------------------------
    firmware_bram #(.INIT_FILE("firmware.mem")) u_bram (
        .clk  (clk),
        .addr (bram_addr),
        .dout (bram_dout)
    );

    sha512_top u_sha512 (
        .clk     (clk),
        .rst_n   (rst_n),
        .addr_i  (sha_addr),
        .wr_en_i (sha_wen),
        .wdata_i (sha_wdata),
        .rdata_o (sha_rdata),
        .intr_o  (sha_intr)
    );

    top_ed25519 u_ed25519 (
        .clk             (clk),
        .rst_n           (rst_n),
        .start_verify    (ed_start),
        
        .ext_data_1      (ed_ext_data_1),
        .ext_data_2      (256'd0), 
        .otp_data        (256'd0),
        .data_sel        (ed_data_sel),
        
        .ext_we          (ed_ext_we),        // Added external WE
        .ext_dest_sel    (ed_ext_dest_sel),  // Added external Dest
        
        .verify_done     (ed_done),
        .signature_valid (ed_valid)
    );

    // --------------------------------------------------------
    // Master System Orchestrator FSM
    // --------------------------------------------------------
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state           <= ST_IDLE;
            bram_addr       <= 16'd0;
            sha_addr        <= 6'd0;
            sha_wen         <= 1'b0;
            sha_wdata       <= 32'd0;
            ed_start        <= 1'b0;
            demo_done       <= 1'b0;
            signature_valid <= 1'b0;
            ed_ext_we       <= 1'b0;
            ed_ext_dest_sel <= 5'd0;
            ed_data_sel     <= 2'b00;
        end else begin
            case (state)
                ST_IDLE: begin
                    demo_done <= 1'b0;
                    ed_ext_we <= 1'b0;
                    if (start_demo) begin
                        const_idx <= 4'd0;         // Reset constant counter
                        state     <= ST_LOAD_CONST_REQ;
                    end
                end

                // --- 0. The Constants Bootloader ---
                ST_LOAD_CONST_REQ: begin
                    ed_ext_we   <= 1'b1;           // Turn on the external write override
                    ed_data_sel <= 2'b01;          // Route ext_data_1 into the register file
                    
                    // Route the correct constant to the correct register
                    case (const_idx)
                        4'd0:  begin ed_ext_dest_sel <= 5'd24; ed_ext_data_1 <= CONST_ZERO; end
                        4'd1:  begin ed_ext_dest_sel <= 5'd25; ed_ext_data_1 <= CONST_ONE;  end
                        4'd2:  begin ed_ext_dest_sel <= 5'd26; ed_ext_data_1 <= CURVE_D;    end
                        4'd3:  begin ed_ext_dest_sel <= 5'd27; ed_ext_data_1 <= CURVE_2D;   end
                        4'd4:  begin ed_ext_dest_sel <= 5'd28; ed_ext_data_1 <= SQRT_M1;    end
                        4'd5:  begin ed_ext_dest_sel <= 5'd4;  ed_ext_data_1 <= G_X;        end
                        4'd6:  begin ed_ext_dest_sel <= 5'd5;  ed_ext_data_1 <= G_Y;        end
                        4'd7:  begin ed_ext_dest_sel <= 5'd6;  ed_ext_data_1 <= G_Z;        end
                        4'd8:  begin ed_ext_dest_sel <= 5'd7;  ed_ext_data_1 <= G_T;        end
                        4'd9:  begin ed_ext_dest_sel <= 5'd10; ed_ext_data_1 <= MU_HI;      end
                        4'd10: begin ed_ext_dest_sel <= 5'd11; ed_ext_data_1 <= CURVE_L;    end
                        4'd11: begin ed_ext_dest_sel <= 5'd12; ed_ext_data_1 <= MU_LO;      end
                        default: begin ed_ext_dest_sel <= 5'd0; ed_ext_data_1 <= 256'd0;    end
                    endcase
                    
                    state <= ST_LOAD_CONST_ACK;
                end

                ST_LOAD_CONST_ACK: begin
                    if (const_idx == 4'd11) begin
                        ed_ext_we <= 1'b0;         // Turn off external write!
                        bram_addr <= 16'd0;        // Setup BRAM address 0
                        state     <= ST_READ_LEN;  // Move to the next phase
                    end else begin
                        const_idx <= const_idx + 1;
                        state     <= ST_LOAD_CONST_REQ;
                    end
                end

                ST_READ_LEN: state <= ST_WAIT_LEN; 

                ST_WAIT_LEN: begin
                    msg_length <= bram_dout;
                    bram_addr  <= 16'd1; // Address 1 is Start of S
                    read_count <= 4'd0;
                    state      <= ST_READ_S_REQ;
                end

                // --- 1. Extract Signature S ---
                ST_READ_S_REQ: state <= ST_READ_S_ACK;
                
                ST_READ_S_ACK: begin
                    // Byte-swap to preserve Little Endian
                    s_reg <= {bswap(bram_dout), s_reg[255:32]}; 
                    
                    if (read_count == 7) begin
                        bram_addr <= 16'd9; // Jump to R (Start of SHA hash)
                        state     <= ST_CFG_SHA_LEN;
                    end else begin
                        bram_addr <= bram_addr + 1;
                        read_count <= read_count + 1;
                        state <= ST_READ_S_REQ;
                    end
                end

                // --- 2. Configure SHA-512 ---
                ST_CFG_SHA_LEN: begin
                    sha_addr  <= 6'h32;
                    sha_wdata <= msg_length;
                    sha_wen   <= 1'b1;
                    state     <= ST_CFG_SHA_CTRL;
                end

                ST_CFG_SHA_CTRL: begin
                    sha_addr   <= 6'h20;
                    sha_wdata  <= 32'h03; 
                    sha_wen    <= 1'b1;
                    words_sent <= 32'd0;
                    state      <= ST_SHA_FEED_WAIT;
                end

                // --- 3. Feed BRAM Data & Strip R/PubKey ---
                ST_SHA_FEED_WAIT: begin
                    sha_wen <= 1'b0;
                    sha_addr <= 6'h21; 
                    if (sha_rdata[0] == 1'b1) state <= ST_SHA_FEED_WRITE;
                end

                ST_SHA_FEED_WRITE: begin
                    sha_addr  <= {1'b0, words_sent[4:0]}; 
                    sha_wdata <= bswap(bram_dout);               
                    sha_wen   <= 1'b1;
                    
                    // Sneakily capture R and PubKey while feeding SHA
                    if (bram_addr >= 9 && bram_addr <= 16)
                        r_reg <= {bswap(bram_dout), r_reg[255:32]};
                    if (bram_addr >= 17 && bram_addr <= 24)
                        pubkey_reg <= {bswap(bram_dout), pubkey_reg[255:32]};
                    
                    words_sent <= words_sent + 1;
                    bram_addr  <= bram_addr + 1;
                    
                    if (words_sent + 1 == msg_length)
                        state <= ST_WAIT_HASH;
                    else if ((words_sent + 1) % 32 == 0)
                        state <= ST_SHA_FEED_WAIT; 
                    else
                        state <= ST_SHA_BRAM_DELAY; 
                end

                ST_SHA_BRAM_DELAY: begin
                    sha_wen <= 1'b0;
                    state   <= ST_SHA_FEED_WRITE;
                end

                // --- 4. Extract 512-bit Hash ---
                ST_WAIT_HASH: begin
                    sha_wen <= 1'b0;
                    if (sha_intr) begin
                        sha_read_idx <= 5'd0;
                        state        <= ST_READ_HASH_REQ;
                    end
                end

                ST_READ_HASH_REQ: begin
                    sha_addr <= 6'h22 + sha_read_idx; 
                    state    <= ST_READ_HASH_ACK;
                end

                ST_READ_HASH_ACK: begin
                    // Byte-swap AND shift into MSB for proper Little-Endian formatting
                    hash_reg <= {bswap(sha_rdata), hash_reg[511:32]};
                    
                    if (sha_read_idx == 15) state <= ST_LOAD_REG_S;
                    else begin
                        sha_read_idx <= sha_read_idx + 1;
                        state        <= ST_READ_HASH_REQ;
                    end
                end

                // --- 5. Push Valid Data into Ed25519 Registers ---
                ST_LOAD_REG_S: begin
                    ed_ext_we       <= 1'b1;
                    ed_ext_dest_sel <= 5'd23;    // Reg 23 = S
                    ed_data_sel     <= 2'b01;    // Route from ext_data_1
                    ed_ext_data_1   <= s_reg;
                    state           <= ST_LOAD_REG_R;
                end
                ST_LOAD_REG_R: begin
                    ed_ext_dest_sel <= 5'd20;    // Reg 20 = R
                    ed_ext_data_1   <= r_reg;
                    state           <= ST_LOAD_REG_A;
                end
                ST_LOAD_REG_A: begin
                    ed_ext_dest_sel <= 5'd21;    // Reg 21 = PubKey
                    ed_ext_data_1   <= pubkey_reg;
                    state           <= ST_LOAD_REG_HLO;
                end
                ST_LOAD_REG_HLO: begin
                    ed_ext_dest_sel <= 5'd8;     // Reg 8 = Hash Low
                    ed_ext_data_1   <= hash_reg[255:0];
                    state           <= ST_LOAD_REG_HHI;
                end
                ST_LOAD_REG_HHI: begin
                    ed_ext_dest_sel <= 5'd9;     // Reg 9 = Hash High
                    ed_ext_data_1   <= hash_reg[511:256];
                    state           <= ST_ED_START;
                end

                // --- 6. Kick Off Verification ---
                ST_ED_START: begin
                    ed_ext_we <= 1'b0;  // Release override
                    ed_data_sel <= 2'b00;
                    ed_start  <= 1'b1;
                    state     <= ST_ED_WAIT;
                end

                ST_ED_WAIT: begin
                    ed_start <= 1'b0;
                    if (ed_done) begin
                        demo_done       <= 1'b1;
                        signature_valid <= ed_valid;
                        state           <= ST_DONE;
                    end
                end

                ST_DONE: begin
                    if (!start_demo) state <= ST_IDLE;
                end
                default: state <= ST_IDLE;
            endcase
        end
    end
endmodule