module program_counter #(
    parameter int COUNTER_BIT = 32,
    parameter int PC_REMEMBER_NUM = 16,
    parameter int PC_PER_INCR = 4,
    parameter bit ENABLE_RETURN_STACK = 1'b0
)(
    input logic ACLK,
    input logic ARESETn,

    input logic req,
    input logic req_jump,
    input logic [COUNTER_BIT-1:0] jump_addr,
    input logic req_return,
    output logic err,

    output logic [COUNTER_BIT-1:0] o_addr
);  
    localparam int REMEMBER_CNT_WIDTH = $clog2(PC_REMEMBER_NUM);
    // counter 및 fifo 관련 
    reg [COUNTER_BIT-1:0] cnt;
    reg [COUNTER_BIT-1:0] remember_cnt[0:PC_REMEMBER_NUM-1];
    reg [REMEMBER_CNT_WIDTH-1:0] rem_cnt_fifo;

    always @(posedge ACLK or negedge ARESETn) begin
        if (!ARESETn) begin
            rem_cnt_fifo <= '0;
            err <= 1'b0;
        end
        else begin
            if (ENABLE_RETURN_STACK && req_jump) begin
                if (rem_cnt_fifo < PC_REMEMBER_NUM-1) rem_cnt_fifo <= rem_cnt_fifo + 1'b1;
                else err <= 1'b1;
            end
            else if (ENABLE_RETURN_STACK && req_return) begin
                if (rem_cnt_fifo > 0) rem_cnt_fifo <= rem_cnt_fifo - 1'b1;
                else err <= 1'b1;
            end
        end
    end

    always @(posedge ACLK or negedge ARESETn) begin
        if (!ARESETn) begin
            cnt <= 'h7000;
        end 
        else if (!err) begin
            if (req_jump) begin  // PC + JUMP
                cnt <= cnt + jump_addr;
                if (ENABLE_RETURN_STACK) begin
                    remember_cnt[rem_cnt_fifo] <= cnt;
                end
            end
            else if (req_return) begin  // RETURN PRIVIOUS PC VALUE
                cnt <= remember_cnt[rem_cnt_fifo];
            end
            else if (req) begin  // PC + PER_INCR
                cnt <= cnt + PC_PER_INCR;
            end
        end
    end

    assign o_addr = cnt;






endmodule