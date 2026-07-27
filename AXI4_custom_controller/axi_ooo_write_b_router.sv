`include "axi_include_top.vh"
import axi_pkg::*;

module axi_ooo_write_b_router #(
    parameter int DATA_WIDTH = 32,
    parameter int ID_WIDTH = 4,
    parameter int NUM_WRITE_ORDER_QUEUE_AW = 4
) (
    input [ID_WIDTH-1:0] i_AWID,
    input [DATA_WIDTH/8-1:0] i_WSTRB,
    input i_WLAST,
    input i_WVALID,
    output i_WREADY,

    input [ID_WIDTH-1:0] i_BID,
    input [1:0] i_BRESP,
    input i_BVALID,
    output i_BREADY,

    input aw_scheduler_fire,
    output aw_scheduler_ready,

    input ACLK,
    input ARESETn,

    output [ID_WIDTH-1:0] o_BID,
    output [1:0] o_BRESP,
    output o_BVALID,
    input o_BREADY

);
    localparam [1:0] BRESP_OKAY = 2'b00;
    localparam [1:0] BRESP_SLVERR = 2'b10;
    localparam int B_FIFO_DEPTH = NUM_WRITE_ORDER_QUEUE_AW;
    localparam int B_INDEX_WIDTH = (B_FIFO_DEPTH <= 1) ? 1 : $clog2(B_FIFO_DEPTH);

    reg [ID_WIDTH-1:0] reg_AWID[0:B_FIFO_DEPTH-1];
    reg reg_WSTRB_ERR[0:B_FIFO_DEPTH-1];
    reg [B_INDEX_WIDTH-1:0] aw_rd_ptr;
    reg [B_INDEX_WIDTH-1:0] aw_wr_ptr;
    reg [B_INDEX_WIDTH-1:0] w_rd_ptr;
    reg [B_INDEX_WIDTH:0] aw_cnt;

    reg [ID_WIDTH-1:0] reg_BID[0:B_FIFO_DEPTH-1];
    reg [1:0] reg_BRESP[0:B_FIFO_DEPTH-1];
    reg [B_INDEX_WIDTH-1:0] rd_ptr;
    reg [B_INDEX_WIDTH-1:0] wr_ptr;
    reg [B_INDEX_WIDTH:0] b_cnt;

    wire aw_fifo_full = (aw_cnt == B_FIFO_DEPTH);
    wire aw_fifo_empty = (aw_cnt == '0);
    wire b_fifo_full = (b_cnt == B_FIFO_DEPTH);
    wire b_fifo_empty = (b_cnt == '0);
    wire w_fire = i_WVALID && i_WREADY;
    wire aw_push = aw_scheduler_fire && aw_scheduler_ready;
    wire aw_done = w_fire && i_WLAST && !aw_fifo_empty;
    wire slave_b_fire = i_BVALID && i_BREADY;
    wire master_b_push = slave_b_fire && !b_fifo_full;
    wire master_b_pop = o_BVALID && o_BREADY;
    wire wstrb_err = (i_WSTRB == '0);
    wire bid_mismatch = (i_BID != reg_AWID[aw_rd_ptr]);
    wire routed_slverr = reg_WSTRB_ERR[aw_rd_ptr] ||
                         (aw_done && (w_rd_ptr == aw_rd_ptr) && wstrb_err) ||
                         bid_mismatch;
    wire [1:0] routed_bresp = routed_slverr ? BRESP_SLVERR : i_BRESP;

    assign i_WREADY = !aw_fifo_empty;
    assign i_BREADY = !b_fifo_full && !aw_fifo_empty;
    assign aw_scheduler_ready = !aw_fifo_full;

    assign o_BVALID = !b_fifo_empty;
    assign o_BID = (o_BVALID) ? reg_BID[rd_ptr] : '0;
    assign o_BRESP = (o_BVALID) ? reg_BRESP[rd_ptr] : BRESP_OKAY;

    always @(posedge ACLK or negedge ARESETn) begin
        if (!ARESETn) begin
            aw_rd_ptr <= '0;
            aw_wr_ptr <= '0;
            w_rd_ptr <= '0;
            aw_cnt <= '0;
            rd_ptr <= '0;
            wr_ptr <= '0;
            b_cnt <= '0;

            for (int i=0; i<B_FIFO_DEPTH; i++) begin
                reg_AWID[i] <= '0;
                reg_WSTRB_ERR[i] <= OFF;
                reg_BID[i] <= '0;
                reg_BRESP[i] <= BRESP_OKAY;
            end
        end
        else begin
            case ({aw_push, slave_b_fire})
                2'b01: begin
                    if (aw_cnt != '0) aw_cnt <= aw_cnt - 1'b1;
                end
                2'b10: begin
                    if (aw_cnt != B_FIFO_DEPTH) aw_cnt <= aw_cnt + 1'b1;
                end
                default: aw_cnt <= aw_cnt;
            endcase

            case ({master_b_push, master_b_pop})
                2'b01: begin
                    if (b_cnt != '0) b_cnt <= b_cnt - 1'b1;
                end
                2'b10: begin
                    if (b_cnt != B_FIFO_DEPTH) b_cnt <= b_cnt + 1'b1;
                end
                default: b_cnt <= b_cnt;
            endcase

            if (slave_b_fire) begin
                if (aw_rd_ptr == B_INDEX_WIDTH'(B_FIFO_DEPTH-1)) aw_rd_ptr <= '0;
                else aw_rd_ptr <= aw_rd_ptr + 1'b1;
            end

            if (aw_done) begin
                if (w_rd_ptr == B_INDEX_WIDTH'(B_FIFO_DEPTH-1)) w_rd_ptr <= '0;
                else w_rd_ptr <= w_rd_ptr + 1'b1;
            end

            if (aw_push) begin
                reg_AWID[aw_wr_ptr] <= i_AWID;
                reg_WSTRB_ERR[aw_wr_ptr] <= OFF;

                if (aw_wr_ptr == B_INDEX_WIDTH'(B_FIFO_DEPTH-1)) aw_wr_ptr <= '0;
                else aw_wr_ptr <= aw_wr_ptr + 1'b1;
            end

            if (w_fire) begin
                reg_WSTRB_ERR[w_rd_ptr] <= reg_WSTRB_ERR[w_rd_ptr] || wstrb_err;
            end

            if (master_b_pop) begin
                if (rd_ptr == B_INDEX_WIDTH'(B_FIFO_DEPTH-1)) rd_ptr <= '0;
                else rd_ptr <= rd_ptr + 1'b1;
            end

            if (master_b_push) begin
                reg_BID[wr_ptr] <= reg_AWID[aw_rd_ptr];
                reg_BRESP[wr_ptr] <= routed_bresp;

                if (wr_ptr == B_INDEX_WIDTH'(B_FIFO_DEPTH-1)) wr_ptr <= '0;
                else wr_ptr <= wr_ptr + 1'b1;
            end
        end
    end

    `ifdef INITIAL_REG_RESET
        initial begin
            aw_rd_ptr = '0;
            aw_wr_ptr = '0;
            w_rd_ptr = '0;
            aw_cnt = '0;
            rd_ptr = '0;
            wr_ptr = '0;
            b_cnt = '0;

            for (int i=0; i<B_FIFO_DEPTH; i++) begin
                reg_AWID[i] = '0;
                reg_WSTRB_ERR[i] = OFF;
                reg_BID[i] = '0;
                reg_BRESP[i] = BRESP_OKAY;
            end
        end
    `endif

endmodule
