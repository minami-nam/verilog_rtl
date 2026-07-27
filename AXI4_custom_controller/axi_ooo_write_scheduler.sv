`include "axi_include_top.vh"
import axi_pkg::*;

module axi_ooo_aw_scheduler #(
    parameter int ADDR_WIDTH = 32,
    parameter int ID_WIDTH = 4,
    parameter int LEN_WIDTH = 8,
    parameter int NUM_WRITE_SCHEDULER = 4,
    parameter int WRITE_KEEP_MAX_LENGTH = 8
) (
    input ACLK,
    input ARESETn,
    
    input [ID_WIDTH-1:0] i_AWID,
    input [ADDR_WIDTH-1:0] i_AWADDR,
    input [LEN_WIDTH-1:0] i_AWLEN,
    input [2:0] i_AWSIZE,
    input [1:0] i_AWBURST,

    input i_AWVALID,
    output i_AWREADY,

    output [ID_WIDTH-1:0] o_AWID,
    output [ADDR_WIDTH-1:0] o_AWADDR,
    output [LEN_WIDTH-1:0] o_AWLEN,
    output [2:0] o_AWSIZE,
    output [1:0] o_AWBURST,
   

    input o_AWREADY,
    output o_AWVALID
);
    `ifdef WRITE_MINAMI_CUSTOM
        localparam KEEP_MAX_LENGTH = WRITE_KEEP_MAX_LENGTH;
        localparam CNT_WIDTH = $clog2(KEEP_MAX_LENGTH);
        localparam ID_MAX = (1<<ID_WIDTH);
        localparam INDEX_WIDTH = (NUM_WRITE_SCHEDULER <= 1) ? 1 : $clog2(NUM_WRITE_SCHEDULER);


        wire aw_in = i_AWVALID & i_AWREADY;
        wire aw_out = o_AWREADY & o_AWVALID;
        

        reg [CNT_WIDTH:0] cnt_awid_ocheck[0:ID_MAX-1];
        reg [CNT_WIDTH:0] cnt_awid_icheck[0:ID_MAX-1];
        reg [ID_WIDTH-1:0] previous_o_awid;

        reg [ID_WIDTH-1:0] reg_AWID[0:NUM_WRITE_SCHEDULER-1];
        reg [ADDR_WIDTH-1:0] reg_AWADDR[0:NUM_WRITE_SCHEDULER-1];
        reg [LEN_WIDTH-1:0] reg_AWLEN[0:NUM_WRITE_SCHEDULER-1];
        reg [2:0] reg_AWSIZE[0:NUM_WRITE_SCHEDULER-1];
        reg [1:0] reg_AWBURST[0:NUM_WRITE_SCHEDULER-1];
        reg reg_valid[0:NUM_WRITE_SCHEDULER-1];

        reg cache_has_empty;
        reg cache_has_valid;
        reg has_same_id;
        reg has_other_id;
        reg max_count_found;
        reg [INDEX_WIDTH-1:0] fill_index;
        reg [INDEX_WIDTH-1:0] same_id_index;
        reg [INDEX_WIDTH-1:0] max_count_index;
        reg [CNT_WIDTH:0] max_count_value;

        wire [INDEX_WIDTH-1:0] issue_index;
        wire [INDEX_WIDTH-1:0] write_index;

        wire limit_reached = (cnt_awid_ocheck[previous_o_awid] >= KEEP_MAX_LENGTH);
        wire is_ocnt_max = (cnt_awid_ocheck[o_AWID]==KEEP_MAX_LENGTH) ? ON : OFF;
        
        // 각 ID 별로 몇 번 Data Out이 진행되었는지 체크 + previous 값도 체크

        assign i_AWREADY = cache_has_empty || aw_out;
        assign o_AWVALID = cache_has_valid;
        assign o_AWID = (o_AWVALID) ? reg_AWID[issue_index] : '0;
        assign o_AWADDR = (o_AWVALID) ? reg_AWADDR[issue_index] : '0;
        assign o_AWLEN = (o_AWVALID) ? reg_AWLEN[issue_index] : '0;
        assign o_AWSIZE = (o_AWVALID) ? reg_AWSIZE[issue_index] : '0;
        assign o_AWBURST = (o_AWVALID) ? reg_AWBURST[issue_index] : '0;
        assign issue_index = (limit_reached && has_other_id) ? max_count_index :
                             (has_same_id) ? same_id_index : max_count_index;
        assign write_index = (!cache_has_empty && aw_out) ? issue_index : fill_index;

        // state 판별을 위한 logic

        // 수정 1. seq하게 분리함.
        always @(posedge ACLK or negedge ARESETn) begin
            if (!ARESETn) begin
                cache_has_empty <= OFF;
                fill_index <= '0;
            end
            else begin
                for (int i=0; i<NUM_WRITE_SCHEDULER; i++) begin
                    if (!reg_valid[i] && !cache_has_empty) begin
                        cache_has_empty <= ON;
                        fill_index <= INDEX_WIDTH'(i);
                    end
                end
            end
        end


        always  @(posedge ACLK or negedge ARESETn) begin
            if (!ARESETn) begin
                cache_has_valid <= OFF;
                max_count_found <= OFF;
                max_count_value <= '0;
                max_count_index <= '0;
                has_same_id <= OFF;
                has_other_id <= OFF;
            end
            else begin
                for (int i=0; i<NUM_WRITE_SCHEDULER; i++) begin
                    if (reg_valid[i]) begin
                        cache_has_valid <= ON;
                        if ((reg_AWID[i] == previous_o_awid) && !has_same_id) begin
                            has_same_id <= ON;
                            same_id_index <= INDEX_WIDTH'(i);
                        end

                        if (reg_AWID[i] != previous_o_awid) begin   // 현재 출력과 previous 출력이 다른 경우 cnt를 초기화 시키는 방향으로 가야함.
                            if (!has_other_id || (cnt_awid_icheck[reg_AWID[i]] > max_count_value)) begin
                                max_count_found <= ON;
                                max_count_value <= cnt_awid_icheck[reg_AWID[i]];
                                max_count_index <= INDEX_WIDTH'(i);
                            end
                            has_other_id <= ON;
                        end
                        else if (!has_other_id && (!max_count_found || (cnt_awid_icheck[reg_AWID[i]] > max_count_value))) begin 
                            max_count_found <= ON;
                            max_count_value <= cnt_awid_icheck[reg_AWID[i]];
                            max_count_index <= INDEX_WIDTH'(i);  // 이런 방식으로 index를 구할 수 있다는 것 참조하기.
                        end
                        else begin
                            max_count_found <= OFF;
                            max_count_value <= '0;
                            max_count_index <= '0;
                        end
                    end
                    else begin
                        cache_has_valid <= OFF;
                    end
                end
            end
        end


        // Previous AWID Checker
        always @(posedge ACLK or negedge ARESETn) begin
            if (!ARESETn) previous_o_awid <= '0;
            else if (aw_out) previous_o_awid <= o_AWID;
        end

        // Data out Counter
        

        always @(posedge ACLK or negedge ARESETn) begin
            if (!ARESETn) begin
                for (int i=0; i<ID_MAX; i++) begin : reset_reg_ocheck
                    cnt_awid_ocheck[i] <= '0;
                end
            end
            else begin
                if (aw_out && (previous_o_awid != o_AWID)) begin
                    cnt_awid_ocheck[o_AWID] <= 1'b1;
                end
                else if ((aw_out)&(!is_ocnt_max)) begin   // 아직 cnt가 KEEP_MAX_LENGTH 값에 도달하지 않았을 경우
                    cnt_awid_ocheck[o_AWID] <= cnt_awid_ocheck[o_AWID] + 1'b1;
                end
                else if ((aw_out)&is_ocnt_max) begin  // cnt가 KEEP_MAX_LENGTH 값에 도달한 경우
                    cnt_awid_ocheck[o_AWID] <= '0;
                end
            end
        end

        // Current Data Counter
        always @(posedge ACLK or negedge ARESETn) begin
            if (!ARESETn) begin
                for (int i=0; i<ID_MAX; i++) begin : reset_reg_icheck
                    cnt_awid_icheck[i] <= '0;
                end
            end
            else begin
                case({aw_in, aw_out})
                    2'b00 : begin
                        cnt_awid_icheck[i_AWID] <= cnt_awid_icheck[i_AWID];
                        cnt_awid_icheck[o_AWID] <= cnt_awid_icheck[o_AWID];
                    end
                    2'b01 : begin
                        if (cnt_awid_icheck[o_AWID]!=0) begin
                            cnt_awid_icheck[o_AWID] <= cnt_awid_icheck[o_AWID] - 1;
                        end
                    end
                    2'b10 : begin
                        if (cnt_awid_icheck[i_AWID]<KEEP_MAX_LENGTH) begin
                            cnt_awid_icheck[i_AWID] <= cnt_awid_icheck[i_AWID] + 1'b1;
                        end
                    end
                    2'b11 : begin
                        if (i_AWID==o_AWID) begin
                            cnt_awid_icheck[o_AWID] <= cnt_awid_icheck[o_AWID];
                        end
                        else begin
                            if (cnt_awid_icheck[o_AWID]!=0) cnt_awid_icheck[o_AWID] <= cnt_awid_icheck[o_AWID] - 1;
                            else cnt_awid_icheck[o_AWID] <= '0;
                            if (cnt_awid_icheck[i_AWID]<KEEP_MAX_LENGTH) cnt_awid_icheck[i_AWID] <= cnt_awid_icheck[i_AWID] + 1'b1;
                            else cnt_awid_icheck[i_AWID] <= KEEP_MAX_LENGTH;
                        end
                    end
                endcase
            end
        end

        // 해당 조건들을 사용하여 Starvation 방지를 위한 Policy Logic 설계. 

        always @(posedge ACLK or negedge ARESETn) begin
            if (!ARESETn) begin
                for (int i=0; i<NUM_WRITE_SCHEDULER; i++) begin : reset_aw_cache
                    reg_AWID[i] <= '0;
                    reg_AWADDR[i] <= '0;
                    reg_AWLEN[i] <= '0;
                    reg_AWSIZE[i] <= '0;
                    reg_AWBURST[i] <= '0;
                    reg_valid[i] <= OFF;
                end
            end
            else begin
                if (aw_out) begin
                    reg_valid[issue_index] <= OFF;
                end

                if (aw_in) begin
                    reg_AWID[write_index] <= i_AWID;
                    reg_AWADDR[write_index] <= i_AWADDR;
                    reg_AWLEN[write_index] <= i_AWLEN;
                    reg_AWSIZE[write_index] <= i_AWSIZE;
                    reg_AWBURST[write_index] <= i_AWBURST;
                    reg_valid[write_index] <= ON;
                end
            end
        end



        `ifdef INITIAL_REG_RESET
            initial begin
                for (int i=0; i<ID_MAX; i++) begin
                    cnt_awid_ocheck[i] = '0;
                    cnt_awid_icheck[i] = '0;
                end

                for (int i=0; i<NUM_WRITE_SCHEDULER; i++) begin
                    reg_AWID[i] = '0;
                    reg_AWADDR[i] = '0;
                    reg_AWLEN[i] = '0;
                    reg_AWSIZE[i] = '0;
                    reg_AWBURST[i] = '0;
                    reg_valid[i] = OFF;
                end

                previous_o_awid = '0;
                cache_has_empty = OFF;
                cache_has_valid = OFF;
                has_same_id = OFF;
                has_other_id = OFF;
                max_count_found = OFF;
                fill_index = '0;
                same_id_index = '0;
                max_count_index = '0;
                max_count_value = '0;
            end
        `endif

    `elsif CUSTOM_POLICY_WRITE

    `endif

endmodule
