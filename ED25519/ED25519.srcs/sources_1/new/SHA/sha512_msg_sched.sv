import sha512_pkg::*;

// this module recives preprocessed data from source and writes the hash back to it
module sha512_msg_sched (
    input  logic        clk,
    input  logic        rst_n,
    
    // Source interface ports
    input  logic [3:0]  wr_idx_i,   // Which of the 16 words (64-bit)
    input  logic        wr_low_i,   // Write to [31:0]
    input  logic        wr_high_i,  // Write to [63:32]
    input  logic [31:0] wr_data_i,  // the data to be written
    
    input  logic        en,         // enable  left shift of array (to be done only in WORK state)
    output word_t       w_out       // current round w
);

    word_t w [16]; // array of 16 words, w[15] stores the newest computed word, w[0] stores the current operation word
    word_t w_next; // newest computed word

    // w_next = sigma1(w[14]) + w[9] + sigma0(w[1]) + w[0]
    csa_t stage1, stage2;
    always_comb begin
        stage1 = csa64(lower_sigma1(w[14]), w[9], lower_sigma0(w[1]));
        stage2 = csa64(stage1.sum, {stage1.carry[62:0], 1'b0}, w[0]);
        w_next = stage2.sum + {stage2.carry[62:0], 1'b0};
    end

    always_ff @(posedge clk or negedge rst_n) begin // receive 32 bits at both clock edges to get one complete word in one cycle
        if (!rst_n) for (int i=0; i<16; i++) w[i] <= 64'h0;
        else if (wr_low_i)  w[wr_idx_i][31:0]  <= wr_data_i;
        else if (wr_high_i) w[wr_idx_i][63:32] <= wr_data_i;
        else if (en) begin
            for (int i=0; i<15; i++) w[i] <= w[i+1]; // shift the array left by 1
            w[15] <= w_next; // w[15] is newest computed word
        end
    end

    assign w_out = w[0]; // current operation word is w[0]

endmodule