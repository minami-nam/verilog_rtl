`include "axi_include_top.vh"
import axi_pkg::*;

module axi_write_ooo #(
    parameter int ADDR_WIDTH = 32,
    parameter int DATA_WIDTH = 32,
    parameter int ID_WIDTH = 4,
    parameter int LEN_WIDTH = 8,
    parameter int NUM_WRITE_AWQUEUE = 4,
    parameter int NUM_WRITE_SCHEDULER = 4,
    parameter int NUM_WRITE_ORDER_QUEUE_AW = 4,
    parameter int WRITE_KEEP_MAX_LENGTH = 8,
    parameter int WRITE_MAX_BURST_BEATS = 8,
    parameter int WRITE_SEQ_WIDTH = 16
) (
    input  wire ACLK,
    input  wire ARESETn,

    //==================================================
    // From external AXI master
    // Controller exposes a slave-side AXI interface
    //==================================================

    // AW Channel
    input  wire [ID_WIDTH-1:0]     S_AXI_AWID,
    input  wire [ADDR_WIDTH-1:0]   S_AXI_AWADDR,
    input  wire [LEN_WIDTH-1:0]    S_AXI_AWLEN,
    input  wire [2:0]              S_AXI_AWSIZE,
    input  wire [1:0]              S_AXI_AWBURST,
    input  wire                    S_AXI_AWVALID,
    output wire                    S_AXI_AWREADY,

    // W Channel
    input  wire [DATA_WIDTH-1:0]   S_AXI_WDATA,
    input  wire [DATA_WIDTH/8-1:0] S_AXI_WSTRB,
    input  wire                    S_AXI_WLAST,
    input  wire                    S_AXI_WVALID,
    output wire                    S_AXI_WREADY,

    // B Channel
    output wire [ID_WIDTH-1:0]     S_AXI_BID,
    output wire [1:0]              S_AXI_BRESP,
    output wire                    S_AXI_BVALID,
    input  wire                    S_AXI_BREADY,

    //==================================================
    // To external AXI slave
    // Controller exposes a master-side AXI interface
    //==================================================

    // AW Channel
    output wire [ID_WIDTH-1:0]     M_AXI_AWID,
    output wire [ADDR_WIDTH-1:0]   M_AXI_AWADDR,
    output wire [LEN_WIDTH-1:0]    M_AXI_AWLEN,
    output wire [2:0]              M_AXI_AWSIZE,
    output wire [1:0]              M_AXI_AWBURST,
    output wire                    M_AXI_AWVALID,
    input  wire                    M_AXI_AWREADY,

    // W Channel
    output wire [DATA_WIDTH-1:0]   M_AXI_WDATA,
    output wire [DATA_WIDTH/8-1:0] M_AXI_WSTRB,
    output wire                    M_AXI_WLAST,
    output wire                    M_AXI_WVALID,
    input  wire                    M_AXI_WREADY,

    // B Channel
    input  wire [ID_WIDTH-1:0]     M_AXI_BID,
    input  wire [1:0]              M_AXI_BRESP,
    input  wire                    M_AXI_BVALID,
    output wire                    M_AXI_BREADY
);

    // AW request path: S_AXI -> aw_queue -> scheduler -> M_AXI
    wire [ID_WIDTH-1:0]   queue_o_awid;
    wire [ADDR_WIDTH-1:0] queue_o_awaddr;
    wire [LEN_WIDTH-1:0]  queue_o_awlen;
    wire [2:0]            queue_o_awsize;
    wire [1:0]            queue_o_awburst;
    wire                  queue_o_awvalid;
    wire                  queue_o_awready;
    wire                  sched_i_awready;

    wire [ID_WIDTH-1:0]   sched_o_awid;
    wire [ADDR_WIDTH-1:0] sched_o_awaddr;
    wire [LEN_WIDTH-1:0]  sched_o_awlen;
    wire [2:0]            sched_o_awsize;
    wire [1:0]            sched_o_awburst;
    wire                  sched_o_awvalid;
    wire                  sched_o_awready;

    wire                  order_aw_queue_ready;
    wire                  order_aw_scheduler_ready;
    wire                  b_aw_scheduler_ready;
    wire                  aw_queue_fire;
    wire                  aw_scheduler_fire;

    // W order path: S_AXI -> order_queue -> M_AXI
    wire [DATA_WIDTH-1:0]   order_o_wdata;
    wire [DATA_WIDTH/8-1:0] order_o_wstrb;
    wire                    order_o_wlast;
    wire                    order_o_wvalid;
    wire                    order_o_wready;
    wire                    b_wready;

    assign queue_o_awready = sched_i_awready && order_aw_queue_ready;
    assign sched_o_awready = M_AXI_AWREADY && order_aw_scheduler_ready && b_aw_scheduler_ready;
    assign aw_queue_fire = queue_o_awvalid && queue_o_awready;
    assign aw_scheduler_fire = sched_o_awvalid && sched_o_awready;

    assign M_AXI_AWID = sched_o_awid;
    assign M_AXI_AWADDR = sched_o_awaddr;
    assign M_AXI_AWLEN = sched_o_awlen;
    assign M_AXI_AWSIZE = sched_o_awsize;
    assign M_AXI_AWBURST = sched_o_awburst;
    assign M_AXI_AWVALID = sched_o_awvalid && order_aw_scheduler_ready && b_aw_scheduler_ready;

    assign order_o_wready = M_AXI_WREADY && b_wready;
    assign M_AXI_WDATA = order_o_wdata;
    assign M_AXI_WSTRB = order_o_wstrb;
    assign M_AXI_WLAST = order_o_wlast;
    assign M_AXI_WVALID = order_o_wvalid && b_wready;

    axi_ooo_aw_queue #(
        .ADDR_WIDTH(ADDR_WIDTH),
        .ID_WIDTH(ID_WIDTH),
        .LEN_WIDTH(LEN_WIDTH),
        .NUM_WRITE_AWQUEUE(NUM_WRITE_AWQUEUE)
    ) u_write_aw_queue (
        .i_AWID(S_AXI_AWID),
        .i_AWADDR(S_AXI_AWADDR),
        .i_AWLEN(S_AXI_AWLEN),
        .i_AWSIZE(S_AXI_AWSIZE),
        .i_AWBURST(S_AXI_AWBURST),

        .i_AWVALID(S_AXI_AWVALID),
        .i_AWREADY(S_AXI_AWREADY),

        .ACLK(ACLK),
        .ARESETn(ARESETn),

        .o_AWID(queue_o_awid),
        .o_AWADDR(queue_o_awaddr),
        .o_AWLEN(queue_o_awlen),
        .o_AWSIZE(queue_o_awsize),
        .o_AWBURST(queue_o_awburst),

        .o_AWREADY(queue_o_awready),
        .o_AWVALID(queue_o_awvalid)
    );

    axi_ooo_aw_scheduler #(
        .ADDR_WIDTH(ADDR_WIDTH),
        .ID_WIDTH(ID_WIDTH),
        .LEN_WIDTH(LEN_WIDTH),
        .NUM_WRITE_SCHEDULER(NUM_WRITE_SCHEDULER),
        .WRITE_KEEP_MAX_LENGTH(WRITE_KEEP_MAX_LENGTH)
    ) u_write_aw_scheduler (
        .ACLK(ACLK),
        .ARESETn(ARESETn),

        .i_AWID(queue_o_awid),
        .i_AWADDR(queue_o_awaddr),
        .i_AWLEN(queue_o_awlen),
        .i_AWSIZE(queue_o_awsize),
        .i_AWBURST(queue_o_awburst),

        .i_AWVALID(queue_o_awvalid && order_aw_queue_ready),
        .i_AWREADY(sched_i_awready),

        .o_AWID(sched_o_awid),
        .o_AWADDR(sched_o_awaddr),
        .o_AWLEN(sched_o_awlen),
        .o_AWSIZE(sched_o_awsize),
        .o_AWBURST(sched_o_awburst),

        .o_AWREADY(sched_o_awready),
        .o_AWVALID(sched_o_awvalid)
    );

    axi_ooo_aw_write_order_queue #(
        .DATA_WIDTH(DATA_WIDTH),
        .ID_WIDTH(ID_WIDTH),
        .LEN_WIDTH(LEN_WIDTH),
        .NUM_WRITE_ORDER_QUEUE_AW(NUM_WRITE_ORDER_QUEUE_AW),
        .WRITE_MAX_BURST_BEATS(WRITE_MAX_BURST_BEATS),
        .WRITE_SEQ_WIDTH(WRITE_SEQ_WIDTH)
    ) u_write_order_queue (
        .ACLK(ACLK),
        .ARESETn(ARESETn),

        .aw_queue_fire(aw_queue_fire),
        .aw_queue_ready(order_aw_queue_ready),
        .i_queue_AWID(queue_o_awid),
        .i_queue_AWLEN(queue_o_awlen),
        .i_queue_AWSIZE(queue_o_awsize),
        .i_queue_AWBURST(queue_o_awburst),

        .i_WVALID(S_AXI_WVALID),
        .i_WREADY(S_AXI_WREADY),
        .i_WDATA(S_AXI_WDATA),
        .i_WSTRB(S_AXI_WSTRB),
        .i_WLAST(S_AXI_WLAST),

        .aw_scheduler_fire(aw_scheduler_fire),
        .aw_scheduler_ready(order_aw_scheduler_ready),
        .i_AWID(sched_o_awid),
        .i_AWLEN(sched_o_awlen),
        .i_AWSIZE(sched_o_awsize),
        .i_AWBURST(sched_o_awburst),

        .o_WDATA(order_o_wdata),
        .o_WSTRB(order_o_wstrb),
        .o_WLAST(order_o_wlast),
        .o_WVALID(order_o_wvalid),
        .o_WREADY(order_o_wready)
    );

    axi_ooo_write_b_router #(
        .DATA_WIDTH(DATA_WIDTH),
        .ID_WIDTH(ID_WIDTH),
        .NUM_WRITE_ORDER_QUEUE_AW(NUM_WRITE_ORDER_QUEUE_AW)
    ) u_write_b_router (
        .i_AWID(sched_o_awid),
        .i_WSTRB(order_o_wstrb),
        .i_WLAST(order_o_wlast),
        .i_WVALID(order_o_wvalid && M_AXI_WREADY),
        .i_WREADY(b_wready),

        .i_BID(M_AXI_BID),
        .i_BRESP(M_AXI_BRESP),
        .i_BVALID(M_AXI_BVALID),
        .i_BREADY(M_AXI_BREADY),

        .aw_scheduler_fire(aw_scheduler_fire),
        .aw_scheduler_ready(b_aw_scheduler_ready),

        .ACLK(ACLK),
        .ARESETn(ARESETn),

        .o_BID(S_AXI_BID),
        .o_BRESP(S_AXI_BRESP),
        .o_BVALID(S_AXI_BVALID),
        .o_BREADY(S_AXI_BREADY)
    );

endmodule
