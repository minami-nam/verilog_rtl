`include "axi_include_top.vh"
import axi_pkg::*;

module axi_ooo_aw_queue #(
    parameter int ADDR_WIDTH = 32,
    parameter int ID_WIDTH = 4,
    parameter int LEN_WIDTH = 8,
    parameter int NUM_WRITE_AWQUEUE = 4
) (
    input [ID_WIDTH-1:0] i_AWID,
    input [ADDR_WIDTH-1:0] i_AWADDR,
    input [LEN_WIDTH-1:0] i_AWLEN,
    input [2:0] i_AWSIZE,
    input [1:0] i_AWBURST,

    input i_AWVALID,
    output i_AWREADY,

    input ACLK,
    input ARESETn,

    output [ID_WIDTH-1:0] o_AWID,
    output [ADDR_WIDTH-1:0] o_AWADDR,
    output [LEN_WIDTH-1:0] o_AWLEN,
    output [2:0] o_AWSIZE,
    output [1:0] o_AWBURST,
   

    input o_AWREADY,
    output o_AWVALID
);

    localparam int CNT_WIDTH = $clog2(NUM_WRITE_AWQUEUE);
    localparam int LAST_PTR = NUM_WRITE_AWQUEUE-1;

    // wire와 reg 미리 선언
    wire aw_in = i_AWVALID & i_AWREADY;
    wire aw_out = o_AWREADY & o_AWVALID;

    reg [ID_WIDTH-1:0] reg_AWID[0:NUM_WRITE_AWQUEUE-1];
    reg [ADDR_WIDTH-1:0] reg_AWADDR[0:NUM_WRITE_AWQUEUE-1];
    reg [LEN_WIDTH-1:0] reg_AWLEN[0:NUM_WRITE_AWQUEUE-1];

    reg [2:0] reg_AWSIZE[0:NUM_WRITE_AWQUEUE-1];
    reg [1:0] reg_AWBURST[0:NUM_WRITE_AWQUEUE-1];

    reg [CNT_WIDTH-1:0] cnt, rd_ptr, wr_ptr;

    // pointer, counter 관련 
    always @(posedge ACLK or negedge ARESETn) begin
        if (!ARESETn) begin
            rd_ptr <= '0;
            wr_ptr <= '0;
            cnt <= '0;
        end
        else begin
            case ({aw_in, aw_out})
                2'b00: cnt <= cnt;
                2'b01: cnt <= cnt - 1'b1;
                2'b10: cnt <= cnt + 1'b1;
                2'b11: cnt <= cnt;
            endcase

            if (aw_out) begin
                if (rd_ptr == LAST_PTR) rd_ptr <= '0;
                else rd_ptr <= rd_ptr + 1'b1;
            end

            if (aw_in) begin
                if (wr_ptr == LAST_PTR) wr_ptr <= '0;
                else wr_ptr <= wr_ptr + 1'b1;
            end
        end
    end

    // DATA IN
    always @(posedge ACLK or negedge ARESETn) begin
        if (!ARESETn) begin
            for (int i=0; i<NUM_WRITE_AWQUEUE; i++) begin
                reg_AWID[i] <= '0;
                reg_AWADDR[i] <= '0;
                reg_AWLEN[i] <= '0;
                reg_AWSIZE[i] <= '0;
                reg_AWBURST[i] <= '0;
            end
        end
        else begin
            if (aw_in) begin
                reg_AWID[wr_ptr] <= i_AWID;
                reg_AWADDR[wr_ptr] <= i_AWADDR;
                reg_AWLEN[wr_ptr] <= i_AWLEN;
                reg_AWSIZE[wr_ptr] <= i_AWSIZE;
                reg_AWBURST[wr_ptr] <= i_AWBURST;
            end
        end
    end

    assign i_AWREADY = (cnt!=LAST_PTR);

    // DATA OUT
    assign o_AWVALID = (cnt!=0);
    assign o_AWID = (o_AWVALID) ? reg_AWID[rd_ptr] : '0;
    assign o_AWADDR = (o_AWVALID) ? reg_AWADDR[rd_ptr] : '0;
    assign o_AWLEN = (o_AWVALID) ? reg_AWLEN[rd_ptr] : '0;
    assign o_AWSIZE = (o_AWVALID) ? reg_AWSIZE[rd_ptr] : '0;
    assign o_AWBURST = (o_AWVALID) ? reg_AWBURST[rd_ptr] : '0;



    `ifdef INITIAL_REG_RESET
        initial begin
            for (int i=0; i<NUM_WRITE_AWQUEUE; i++) begin
                reg_AWID[i] = '0;
                reg_AWADDR[i] = '0;
                reg_AWLEN[i] = '0;
                reg_AWSIZE[i] = '0;
                reg_AWBURST[i] = '0;
            end
            cnt = '0;
            rd_ptr = '0;
            wr_ptr = '0;
        end
    `endif




endmodule
