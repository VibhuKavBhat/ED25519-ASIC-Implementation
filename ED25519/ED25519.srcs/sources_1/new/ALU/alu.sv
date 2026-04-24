module alu (
    input  logic [255:0] src_a,
    input  logic [255:0] src_b,
    input  logic [511:0] mult_product, // From the Booth block
    input  logic [2:0]   alu_op,
    input  logic         sel_hi,
    
    output logic [255:0] alu_result,
    output logic         cmp_flag,
    output logic         mult_start
);

    // Internal flags
    logic [256:0] sum_full;
    logic isolated_cmp_flag;
    assign isolated_cmp_flag = (src_a >= src_b);

    typedef enum logic [2:0] { 
        OP_ADD     = 3'b000, 
        OP_SUB_CND = 3'b001, // Conditional (A - B if A >= B)
        OP_MULT    = 3'b010, 
        OP_CMP     = 3'b011, 
        OP_PASS    = 3'b100,
        OP_SUB_RAW = 3'b101  // NEW: Unconditional wrap-around
    } alu_op_t;

        
    
    always_comb begin
        // Default values
        alu_result = 256'd0;
        sum_full   = 257'd0;
        cmp_flag   = 1'b0;
        mult_start = 1'b0;
        
        case (alu_op)
            OP_ADD: begin 
                alu_result = src_a + src_b;
            end
            
            OP_SUB_CND: begin 
                cmp_flag   = isolated_cmp_flag;
                // Lint-safe ternary operator
                alu_result = isolated_cmp_flag ? (src_a - src_b) : src_a;         
            end
            
            OP_MULT: begin 
                mult_start = 1'b1; 
                alu_result = sel_hi ? mult_product[511:256] : mult_product[255:0];
            end
            
            OP_CMP: begin 
                cmp_flag   = isolated_cmp_flag; // 1 if A >= B
                alu_result = src_a; 
            end
            
            OP_PASS: begin 
                alu_result = src_a;
            end

            OP_SUB_RAW: begin 
                sum_full   = {1'b0, src_a} - {1'b0, src_b};
                alu_result = sum_full[255:0]; 
                // Inverted so cmp_flag consistently means A >= B across all ops
                cmp_flag   = ~sum_full[256]; 
            end

            default: alu_result = 256'd0;
        endcase
    end
endmodule