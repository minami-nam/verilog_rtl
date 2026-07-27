`include "axi_include_top.vh"
import axi_pkg::*;

module axi_ooo_read_queue_cache #(
    parameter int ADDR_WIDTH = 32,
    parameter int ID_WIDTH = 4,
    parameter int LEN_WIDTH = 8,
    parameter int NUM_READ_IDTABLE = 4
) (
    input [ID_WIDTH-1:0] i_id,
    input [ADDR_WIDTH-1:0] i_addr,
    input [LEN_WIDTH-1:0] i_len,
    input [2:0] i_size,
    input [1:0] i_burst,

    input ACLK,
    input ARESETn,
    input data_in_valid,
    input data_out_ready,

    output [ID_WIDTH-1:0] o_id,
    output [ADDR_WIDTH-1:0] o_addr,
    output [LEN_WIDTH-1:0] o_len,
    output [2:0] o_size,
    output [1:0] o_burst,
    output data_in_ready,
    output data_out_valid
);
    // reg 정의

    reg [ID_WIDTH-1:0] reg_id[0:NUM_READ_IDTABLE-1];
    reg [ADDR_WIDTH-1:0] reg_addr[0:NUM_READ_IDTABLE-1];
    reg [LEN_WIDTH-1:0] reg_len[0:NUM_READ_IDTABLE-1];
    reg [2:0] reg_size[0:NUM_READ_IDTABLE-1];
    reg [1:0] reg_burst[0:NUM_READ_IDTABLE-1];
    reg [$clog2(NUM_READ_IDTABLE)-1:0] cnt;

    // 데이터 입출력 조건
    wire data_in = data_in_valid&data_in_ready;
    wire data_out = data_out_valid&data_out_ready;

    assign data_in_ready = (cnt<NUM_READ_IDTABLE) ? ON : OFF;
    assign data_out_valid = (cnt!=0) ? ON : OFF;

    // cnt 관련
    always @(posedge ACLK or negedge ARESETn) begin
        if (!ARESETn) cnt <= '0;
        
        else begin
            case({data_in, data_out})
                2'b00 : cnt <= cnt; // data in out 발생 X 
                2'b01 : begin   // data out만 발생
                    if (cnt!=0) cnt <= cnt-1;
                end
                2'b10 : begin   // data in만 발생
                    if (cnt<NUM_READ_IDTABLE) cnt <= cnt+1;
                end
                2'b11 : cnt <= cnt; // data in out 동시 발생
            endcase
        end
    end

    // data in과 data out 발생 시 FIFO 동작 구현
    always @(posedge ACLK or negedge ARESETn) begin
        if (!ARESETn) begin
            for (int i=0; i<NUM_READ_IDTABLE; i++) begin
                reg_id[i] <= '0;
                reg_addr[i] <= '0;
                reg_burst[i] <= '0;
                reg_len[i] <= '0;
                reg_size[i] <= '0;
            end           
        
        end
        else begin
            if (data_in) begin
                reg_id[cnt] <= i_id;
                reg_addr[cnt] <= i_addr;
                reg_burst[cnt] <= i_burst;
                reg_len[cnt] <= i_len;
                reg_size[cnt] <= i_size;
            end
            else if (data_out) begin
                for (int i=1; i<NUM_READ_IDTABLE; i++) begin
                    reg_id[i-1] <= reg_id[i];
                    reg_addr[i-1] <= reg_addr[i];
                    reg_burst[i-1] <= reg_burst[i];
                    reg_len[i-1] <= reg_len[i];
                    reg_size[i-1] <= reg_size[i];
                end
            end
            else begin
                reg_id[cnt] <= reg_id[cnt];
                reg_addr[cnt] <= reg_addr[cnt];
                reg_burst[cnt] <= reg_burst[cnt];
                reg_len[cnt] <= reg_len[cnt];
                reg_size[cnt] <= reg_size[cnt];
            end
        end
    end

    assign o_id = (data_out_valid) ? reg_id[0] : '0;
    assign o_addr = (data_out_valid) ? reg_addr[0] : '0;
    assign o_len = (data_out_valid) ? reg_len[0] : '0;
    assign o_size = (data_out_valid) ? reg_size[0] : '0;
    assign o_burst = (data_out_valid) ? reg_burst[0] : '0;

    

    `ifdef INITIAL_REG_RESET
        initial begin
            for (int i=0; i<NUM_READ_IDTABLE; i++) begin
                reg_id[i] = '0;
                reg_addr[i] = '0;
                reg_burst[i] = '0;
                reg_len[i] = '0;
                reg_size[i] = '0;
            end  
            cnt = '0;
        end
    `endif

endmodule
