import sha512_pkg::*;

module sha512_top (
    input  logic        clk,
    input  logic        rst_n,

    input  logic [5:0]  addr_i,  
    // 0 to 31, valid address: indicates the current word: 0 or 1 is w[0], 2 or 3 is w[1] ...... 30 or 31 is w[15]
    // even indexed means lower order, odd indexed means higher order
    // 32 or 33: invalid address means it acts as control bus 
    // 34 to 49, points to H: 34 and 35 is H[0], 36 and 37 is H[1] ......... 48 and 49 is H[7]
    input  logic        wr_en_i,  
    // enable writing from source to sha
    input  logic [31:0] wdata_i, 
    // if addr_i is valid address (0-31), then its data from source to sha, 
    // else it is control signals
    // for addr_i = 32, 0th bit is start signal and 1th bit is initial signal (for first block)
    // for addr_i = 33, source begins reading rdata_o from sha
    
    output logic [31:0] rdata_o,  // output hash
    output logic        intr_o    // interrupt: hashing is done
);

    // FSM States
    typedef enum logic [1:0] {IDLE=2'b00, WORK=2'b01, ACCUM=2'b10} state_t;
    state_t state;
    logic [6:0] round_count;

    // Control Signals
    logic start, init_cmd; // to start each bloc, to start each message
    logic ready; // ready to receive data, asserted whenever FSM goes to IDLE
    
    // Hash State
    word_t a, b, c, d, e, f, g, h; // current hash regs regs
    word_t H [8]; // output regs

    // Round Wires
    word_t a_n, b_n, c_n, d_n, e_n, f_n, g_n, h_n; // carry next set of hash regs vals
    word_t sched_w_out; // combinational word from the scheduler
    word_t w_i, k_i; // current registered word and current registered round constant

    // source Interface Decoder 
    assign ready = (state == IDLE); // when in idle state, ready to accept new block

    logic sched_wr_low, sched_wr_high;
    assign sched_wr_low  = wr_en_i && ready && (addr_i < 32) && !addr_i[0];
    assign sched_wr_high = wr_en_i && ready && (addr_i < 32) &&  addr_i[0];
    // when write enabled and valid address, odd means higher 32 bits and even means lower 32 bits

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) {start, init_cmd} <= 2'b00;
        else begin
            start <= (wr_en_i && addr_i == 7'h20) ? wdata_i[0] : 1'b0;
            init_cmd <= (wr_en_i && addr_i == 7'h20) ? wdata_i[1] : init_cmd;
        end
    end
    // when addr_i = 32 (it carries control signals), 0th bit is start signal and 1th bit is initial signal (for first block)

    // Module Instances
    sha512_msg_sched u_sched (
        .clk        (clk),
        .rst_n      (rst_n),
        .wr_idx_i   (addr_i[4:1]),    // 0 to 15: points to w number
        .wr_low_i   (sched_wr_low),   // write to lower 32 bits
        .wr_high_i  (sched_wr_high),  // write to upper 32 bits
        .wr_data_i  (wdata_i),        // the data to be written
        .en         (state == WORK),  // left shifting of w array is enabled only in WORK state
        .w_out      (sched_w_out)     // w[0] is sent to pipeline register before operation
    );

    always_ff @(posedge clk) begin
        w_i <= sched_w_out;           // delay word by 1 cycle to align with constant
        k_i <= K[round_count];        // fetch current round's constant from the pkg (registered for BRAM)
    end

    sha512_round u_round (.*); // Connects a..h, w_i, k_i and a_n..h_n automatically (same named variables)

    // Control FSM
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= IDLE;       // reset state
            round_count <= 7'h0; // reset round count
            intr_o <= 1'b0;      // reset done signal
            {a, b, c, d, e, f, g, h} <= {64'h0, 64'h0, 64'h0, 64'h0, 64'h0, 64'h0, 64'h0, 64'h0}; // reset hash regs
            for (int i=0; i<8; i++) H[i] <= SHA512_IV[i]; // load initial values into has regs
        end else begin
            case (state)
                IDLE: begin
                    intr_o <= 1'b0; // hash is not done
                    if (start) begin // when start signal asserted, go to WORK
                        state <= WORK;
                        round_count <= 0; // hash is still not done
                        if (init_cmd) begin // asserted only in case of first block
                            {a,b,c,d,e,f,g,h} <= {SHA512_IV[0],SHA512_IV[1],SHA512_IV[2],SHA512_IV[3],
                                                 SHA512_IV[4],SHA512_IV[5],SHA512_IV[6],SHA512_IV[7]}; 
                                                 // initialize hash regs with initial values
                            for (int i=0; i<8; i++) H[i] <= SHA512_IV[i]; // initialize output regs with initial values
                        end 
                        else begin // if it is not the first block of 1024 bits
                            {a,b,c,d,e,f,g,h} <= {H[0],H[1],H[2],H[3],H[4],H[5],H[6],H[7]}; 
                            // initialize has regs with output of previous block
                        end
                    end
                end
                WORK: begin 
                    if (round_count < 80) begin
                        round_count <= round_count + 1; // every round, increment round count up to 80
                    end
                    if (round_count > 0) begin
                        {a,b,c,d,e,f,g,h} <= {a_n,b_n,c_n,d_n,e_n,f_n,g_n,h_n}; // load hash regs with next values (delayed by 1 cycle)
                    end
                    if (round_count == 80) state <= ACCUM; // after 80 rounds (plus 1 fetch cycle) move to accumulate stage
                end
                ACCUM: begin // after 80 rounds (on one block)
                    H[0] <= H[0] + a; 
                    H[1] <= H[1] + b;
                    H[2] <= H[2] + c; 
                    H[3] <= H[3] + d;
                    H[4] <= H[4] + e; 
                    H[5] <= H[5] + f;
                    H[6] <= H[6] + g; 
                    H[7] <= H[7] + h;
                    // output of the current block = initial values (in H) + output of the block (a-h) (for first block)
                    //                             = output of previous block + output of current block (subseqent block)
                    state <= IDLE; // go back to idle
                    intr_o <= 1'b1;// hash of 1 block is calculated
                end
            endcase
        end
    end

    // Read logic
    always_comb begin
        rdata_o = 32'h0;
        if (addr_i == 7'h21) rdata_o = {31'h0, ready}; 
        // when addr_i = 33, rdata_o[0] is asserted (if in IDLE) indicating that source should start reading
        else if (addr_i >= 7'h22 && addr_i <= 7'h31)
            rdata_o = addr_i[0] ? H[(addr_i-7'h22)>>1][63:32] : H[(addr_i-7'h22)>>1][31:0];
        // when addr_i = 34 to 49 rdata_o stores what should be read
        // (addr_i-34) = 0 to 15, >>1 = 0 to 7 indicates the H being read
        // even means lower 32 bits, odd means upper 32 bits
    end

endmodule