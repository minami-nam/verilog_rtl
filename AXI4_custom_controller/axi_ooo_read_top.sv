`include "axi_include_top.vh"
import axi_pkg::*;

module axi_read_ooo #(
    parameter int ADDR_WIDTH = 32,
    parameter int DATA_WIDTH = 32,
    parameter int ID_WIDTH = 4,
    parameter int LEN_WIDTH = 8,
    parameter int NUM_READ_IDTABLE = 4,
    parameter int NUM_READ_SCHEDULER = 4,
    parameter int NUM_READ_REORDER = 4,
    parameter int NUM_BANK = 4,
    parameter int READ_BANK_BIT_START = 6,
    parameter int READ_REORDER_KEEP_OUT_TIMES = 8
) (
    input  wire ACLK,
    input  wire ARESETn,

    //==================================================
    // From external AXI master
    // Controller exposes a slave-side AXI interface
    //==================================================

    // AR Channel
    input  wire [ID_WIDTH-1:0]     S_AXI_ARID,
    input  wire [ADDR_WIDTH-1:0]   S_AXI_ARADDR,
    input  wire [LEN_WIDTH-1:0]    S_AXI_ARLEN,
    input  wire [2:0]              S_AXI_ARSIZE,
    input  wire [1:0]              S_AXI_ARBURST,
    input  wire                    S_AXI_ARVALID,
    output wire                    S_AXI_ARREADY,
    // R Channel
    output wire [ID_WIDTH-1:0]     S_AXI_RID,
    output wire [DATA_WIDTH-1:0]   S_AXI_RDATA,
    output wire [1:0]              S_AXI_RRESP,
    output wire                    S_AXI_RLAST,
    output wire                    S_AXI_RVALID,
    input  wire                    S_AXI_RREADY,

    //==================================================
    // To external AXI slave
    // Controller exposes a master-side AXI interface
    //==================================================

    // AR Channel
    output wire [ID_WIDTH-1:0]     M_AXI_ARID,
    output wire [ADDR_WIDTH-1:0]   M_AXI_ARADDR,
    output wire [LEN_WIDTH-1:0]    M_AXI_ARLEN,
    output wire [2:0]              M_AXI_ARSIZE,
    output wire [1:0]              M_AXI_ARBURST,
    output wire                    M_AXI_ARVALID,
    input  wire                    M_AXI_ARREADY,

    // R Channel
    input  wire [ID_WIDTH-1:0]     M_AXI_RID,
    input  wire [DATA_WIDTH-1:0]   M_AXI_RDATA,
    input  wire [1:0]              M_AXI_RRESP,
    input  wire                    M_AXI_RLAST,
    input  wire                    M_AXI_RVALID,
    output wire                    M_AXI_RREADY

);

    // AR request path: S_AXI -> queue cache -> scheduler -> M_AXI
    wire [ID_WIDTH-1:0]   queue_o_id;
    wire [ADDR_WIDTH-1:0] queue_o_addr;
    wire [LEN_WIDTH-1:0]  queue_o_len;
    wire [2:0]            queue_o_size;
    wire [1:0]            queue_o_burst;
    wire                  queue_o_valid;

    wire [ID_WIDTH-1:0]   sched_o_id;
    wire [ADDR_WIDTH-1:0] sched_o_addr;
    wire [LEN_WIDTH-1:0]  sched_o_len;
    wire [2:0]            sched_o_size;
    wire [1:0]            sched_o_burst;
    wire                  sched_o_valid;
    wire                  sched_o_ready;

    axi_ooo_read_queue_cache #(
        .ADDR_WIDTH(ADDR_WIDTH),
        .ID_WIDTH(ID_WIDTH),
        .LEN_WIDTH(LEN_WIDTH),
        .NUM_READ_IDTABLE(NUM_READ_IDTABLE)
    ) u_read_queue_cache (
        .i_id(S_AXI_ARID),
        .i_addr(S_AXI_ARADDR),
        .i_len(S_AXI_ARLEN),
        .i_size(S_AXI_ARSIZE),
        .i_burst(S_AXI_ARBURST),

        .ACLK(ACLK),
        .ARESETn(ARESETn),
        .data_in_valid(S_AXI_ARVALID),
        .data_out_ready(sched_o_ready),

        .o_id(queue_o_id),
        .o_addr(queue_o_addr),
        .o_len(queue_o_len),
        .o_size(queue_o_size),
        .o_burst(queue_o_burst),
        .data_in_ready(S_AXI_ARREADY),
        .data_out_valid(queue_o_valid)
    );

    axi_ooo_read_scheduler #(
        .ADDR_WIDTH(ADDR_WIDTH),
        .ID_WIDTH(ID_WIDTH),
        .LEN_WIDTH(LEN_WIDTH),
        .NUM_READ_SCHEDULER(NUM_READ_SCHEDULER),
        .NUM_BANK(NUM_BANK),
        .READ_BANK_BIT_START(READ_BANK_BIT_START)
    ) u_read_scheduler (
        .i_id(queue_o_id),
        .i_addr(queue_o_addr),
        .i_len(queue_o_len),
        .i_size(queue_o_size),
        .i_burst(queue_o_burst),
        .i_valid(queue_o_valid),
        .o_ready(sched_o_ready),

        .ACLK(ACLK),
        .ARESETn(ARESETn),
        .i_ready(M_AXI_ARREADY),

        .o_id(sched_o_id),
        .o_addr(sched_o_addr),
        .o_len(sched_o_len),
        .o_size(sched_o_size),
        .o_burst(sched_o_burst),
        .o_valid(sched_o_valid)
    );

    assign M_AXI_ARID = sched_o_id;
    assign M_AXI_ARADDR = sched_o_addr;
    assign M_AXI_ARLEN = sched_o_len;
    assign M_AXI_ARSIZE = sched_o_size;
    assign M_AXI_ARBURST = sched_o_burst;
    assign M_AXI_ARVALID = sched_o_valid;

    // R response path: M_AXI -> reorder buffer -> S_AXI
    axi_ooo_read_reorder_buff #(
        .DATA_WIDTH(DATA_WIDTH),
        .ID_WIDTH(ID_WIDTH),
        .NUM_READ_IDTABLE(NUM_READ_IDTABLE),
        .NUM_READ_REORDER(NUM_READ_REORDER),
        .READ_REORDER_KEEP_OUT_TIMES(READ_REORDER_KEEP_OUT_TIMES)
    ) u_read_reorder_buff (
        .ACLK(ACLK),
        .ARESETn(ARESETn),

        .in_rid(M_AXI_RID),
        .in_rdata(M_AXI_RDATA),
        .in_rresp(M_AXI_RRESP),
        .in_rlast(M_AXI_RLAST),
        .in_rvalid(M_AXI_RVALID),
        .in_rready(M_AXI_RREADY),

        .out_rid(S_AXI_RID),
        .out_rdata(S_AXI_RDATA),
        .out_rresp(S_AXI_RRESP),
        .out_rlast(S_AXI_RLAST),
        .out_rvalid(S_AXI_RVALID),
        .out_rready(S_AXI_RREADY)
    );

    
    `ifdef SIM

    `endif

endmodule
