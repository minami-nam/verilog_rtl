// axi_features.vh 파일 내부에 정책 선택하는 define 있으니 확인.
`include "axi_include_top.vh"
import axi_pkg::*;

module axi_ooo_read_scheduler #(
    parameter int ADDR_WIDTH = 32,
    parameter int ID_WIDTH = 4,
    parameter int LEN_WIDTH = 8,
    parameter int NUM_READ_SCHEDULER = 4,
    parameter int NUM_BANK = 4,
    parameter int READ_BANK_BIT_START = 6
) (
    input [ID_WIDTH-1:0] i_id,
    input [ADDR_WIDTH-1:0] i_addr,
    input [LEN_WIDTH-1:0] i_len,
    input [2:0] i_size,
    input [1:0] i_burst,
    input i_valid,
    output o_ready,

    input ACLK,
    input ARESETn,
    input i_ready,

    output [ID_WIDTH-1:0] o_id,
    output [ADDR_WIDTH-1:0] o_addr,
    output [LEN_WIDTH-1:0] o_len,
    output [2:0] o_size,
    output [1:0] o_burst,
    output o_valid
   
);
    // 정책에 따라 scheduler 구성 변경. 정책에 맞게 세팅하기.

    `ifdef BANK_AWARE   // Bank 기반 Policy 결정
        localparam BANK_BITS = $clog2(NUM_BANK);
        localparam WHERE_BIT_START = READ_BANK_BIT_START; // Bank BIT MSB가 어느 자리인가?
        localparam INDEX_WIDTH = (NUM_READ_SCHEDULER <= 1) ? 1 : $clog2(NUM_READ_SCHEDULER);
        localparam MIN_TREE_LEVELS = $clog2(NUM_READ_SCHEDULER);
        localparam MIN_TREE_NUM_LEAF = 1 << MIN_TREE_LEVELS;
        localparam [BANK_BITS-1:0] MAX_BANK_VALUE = {BANK_BITS{1'b1}};

        // min 구하는 function 만들기
        function automatic [BANK_BITS-1:0] min_calc;
            input [BANK_BITS-1:0] a;
            input [BANK_BITS-1:0] b;
            begin
                min_calc = (a > b) ? b : a;
            end
        endfunction

        reg [ID_WIDTH-1:0] reg_id[0:NUM_READ_SCHEDULER-1];
        reg [ADDR_WIDTH-1:0] reg_addr[0:NUM_READ_SCHEDULER-1];
        reg [LEN_WIDTH-1:0] reg_len[0:NUM_READ_SCHEDULER-1];
        reg [2:0] reg_size[0:NUM_READ_SCHEDULER-1];
        reg [1:0] reg_burst[0:NUM_READ_SCHEDULER-1];
        reg reg_valid[0:NUM_READ_SCHEDULER-1];
        reg [ADDR_WIDTH-1:0] last_addr;

        wire [BANK_BITS-1:0] current_bank;
        wire [BANK_BITS-1:0] bank_value[0:NUM_READ_SCHEDULER-1];
        wire [BANK_BITS-1:0] bank_diff[0:NUM_READ_SCHEDULER-1];
        wire [BANK_BITS-1:0] min_tree[0:MIN_TREE_LEVELS][0:MIN_TREE_NUM_LEAF-1];
        wire [INDEX_WIDTH-1:0] min_index_tree[0:MIN_TREE_LEVELS][0:MIN_TREE_NUM_LEAF-1];
        wire [BANK_BITS-1:0] min_bank_diff;
        wire [INDEX_WIDTH-1:0] issue_index;

        wire data_in;
        wire data_out;
        reg cache_has_empty;
        reg cache_has_valid;
        reg [INDEX_WIDTH-1:0] fill_index;
        wire [INDEX_WIDTH-1:0] write_index;

        genvar i;
        genvar level;
        genvar node;

        assign o_ready = cache_has_empty || data_out;
        assign data_in = i_valid && o_ready;
        assign data_out = o_valid && i_ready;
        assign o_id = reg_id[issue_index];
        assign o_addr = reg_addr[issue_index];
        assign o_len = reg_len[issue_index];
        assign o_size = reg_size[issue_index];
        assign o_burst = reg_burst[issue_index];
        assign o_valid = cache_has_valid;
        assign current_bank = last_addr[WHERE_BIT_START -: BANK_BITS];
        assign min_bank_diff = min_tree[MIN_TREE_LEVELS][0];
        assign issue_index = min_index_tree[MIN_TREE_LEVELS][0];
        assign write_index = (!cache_has_empty && data_out) ? issue_index : fill_index;

        always @(*) begin
            cache_has_empty = OFF;
            cache_has_valid = OFF;
            fill_index = '0;

            for (int j=0; j<NUM_READ_SCHEDULER; j++) begin
                if (!reg_valid[j] && !cache_has_empty) begin
                    cache_has_empty = ON;
                    fill_index = INDEX_WIDTH'(j);
                end

                if (reg_valid[j]) begin
                    cache_has_valid = ON;
                end
            end
        end

        generate
            for (i=0; i<NUM_READ_SCHEDULER; i++) begin : BANK_AWARE_CACHE_ENTRY
                assign bank_value[i] = reg_addr[i][WHERE_BIT_START -: BANK_BITS];
                assign bank_diff[i] = current_bank - bank_value[i];
            end

            for (i=0; i<MIN_TREE_NUM_LEAF; i++) begin : MIN_TREE_LEAF
                if (i<NUM_READ_SCHEDULER) begin : VALID_LEAF
                    assign min_tree[0][i] = reg_valid[i] ? bank_diff[i] : MAX_BANK_VALUE;
                    assign min_index_tree[0][i] = INDEX_WIDTH'(i);
                end
                else begin : PAD_LEAF
                    assign min_tree[0][i] = MAX_BANK_VALUE;
                    assign min_index_tree[0][i] = '0;
                end
            end

            for (level=0; level<MIN_TREE_LEVELS; level++) begin : MIN_TREE_LEVEL
                for (node=0; node<(MIN_TREE_NUM_LEAF>>(level+1)); node++) begin : MIN_TREE_NODE
                    assign min_tree[level+1][node] =
                        min_calc(min_tree[level][2*node], min_tree[level][2*node+1]);
                    assign min_index_tree[level+1][node] =
                        (min_tree[level][2*node] > min_tree[level][2*node+1]) ?
                        min_index_tree[level][2*node+1] : min_index_tree[level][2*node];
                end
            end
        endgenerate
                    
        // DATA I/O
        always @(posedge ACLK or negedge ARESETn) begin
            if (!ARESETn) begin
                for (int i=0; i<NUM_READ_SCHEDULER; i++) begin
                    reg_id[i] <= '0;
                    reg_addr[i] <= '0;
                    reg_len[i] <= '0;
                    reg_size[i] <= '0;
                    reg_burst[i] <= '0;
                    reg_valid[i] <= OFF;
                end
                last_addr <= '0;
            end

            else begin
                if (data_out) begin
                    reg_valid[issue_index] <= OFF;
                    last_addr <= reg_addr[issue_index];
                end

                if (data_in) begin
                    reg_id[write_index] <= i_id;
                    reg_addr[write_index] <= i_addr;
                    reg_len[write_index] <= i_len;
                    reg_size[write_index] <= i_size;
                    reg_burst[write_index] <= i_burst;
                    reg_valid[write_index] <= ON;
                end
            end
        end

        `ifdef INITIAL_REG_RESET
            initial begin
                for (int i=0; i<NUM_READ_SCHEDULER; i++) begin
                    reg_id[i] = '0;
                    reg_addr[i] = '0;
                    reg_len[i] = '0;
                    reg_size[i] = '0;
                    reg_burst[i] = '0;
                    reg_valid[i] = OFF;
                end
                last_addr = '0;
                cache_has_empty = OFF;
                cache_has_valid = OFF;
                fill_index = '0;
            end
        `endif


    `elsif OOO_CUSTOM_POLICY1

    `elsif OOO_CUSTOM_POLICY2

    `endif





endmodule
