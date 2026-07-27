
`include "axi_include_top.vh"
import axi_pkg::*;

module axi_ooo_controller #(
    parameter int FIFO_NUM = 8,
    parameter int ADDR_WIDTH = 32,
    parameter int DATA_WIDTH = 32,
    parameter int ID_WIDTH = 4,
    parameter int LEN_WIDTH = 8,
    parameter int NUM_READ_IDTABLE = 4,
    parameter int NUM_READ_SCHEDULER = 4,
    parameter int NUM_READ_REORDER = 4,
    parameter int NUM_BANK = 4,
    parameter int NUM_WRITE_AWQUEUE = 4,
    parameter int NUM_WRITE_SCHEDULER = 4,
    parameter int NUM_WRITE_ORDER_QUEUE_AW = 4,
    parameter int READ_BANK_BIT_START = 6,
    parameter int READ_REORDER_KEEP_OUT_TIMES = 8,
    parameter int WRITE_KEEP_MAX_LENGTH = 8,
    parameter int WRITE_MAX_BURST_BEATS = 8,
    parameter int WRITE_SEQ_WIDTH = 16
)
(
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

    // R Channel
    output wire [ID_WIDTH-1:0]     S_AXI_RID,
    output wire [DATA_WIDTH-1:0]   S_AXI_RDATA,
    output wire [1:0]              S_AXI_RRESP,
    output wire                    S_AXI_RLAST,
    output wire                    S_AXI_RVALID,
    input  wire                    S_AXI_RREADY,

    // B Channel
    output wire [ID_WIDTH-1:0]     S_AXI_BID,
    output wire [1:0]              S_AXI_BRESP,
    output wire                    S_AXI_BVALID,
    input  wire                    S_AXI_BREADY,

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

    // R Channel
    input  wire [ID_WIDTH-1:0]     M_AXI_RID,
    input  wire [DATA_WIDTH-1:0]   M_AXI_RDATA,
    input  wire [1:0]              M_AXI_RRESP,
    input  wire                    M_AXI_RLAST,
    input  wire                    M_AXI_RVALID,
    output wire                    M_AXI_RREADY,

    // B Channel
    input  wire [ID_WIDTH-1:0]     M_AXI_BID,
    input  wire [1:0]              M_AXI_BRESP,
    input  wire                    M_AXI_BVALID,
    output wire                    M_AXI_BREADY
);
    // Synthesis + Implementation 목적 BUFG Instance.
    wire filtered_clk = ACLK;

//    BUFG filter_clk (
//        .I(ACLK),
//        .O(filtered_clk)
//    );

    axi_read_ooo #(
        .ADDR_WIDTH(ADDR_WIDTH),
        .DATA_WIDTH(DATA_WIDTH),
        .ID_WIDTH(ID_WIDTH),
        .LEN_WIDTH(LEN_WIDTH),
        .NUM_READ_IDTABLE(NUM_READ_IDTABLE),
        .NUM_READ_SCHEDULER(NUM_READ_SCHEDULER),
        .NUM_READ_REORDER(NUM_READ_REORDER),
        .NUM_BANK(NUM_BANK),
        .READ_BANK_BIT_START(READ_BANK_BIT_START),
        .READ_REORDER_KEEP_OUT_TIMES(READ_REORDER_KEEP_OUT_TIMES)
    ) u_axi_read_ooo (
        .ACLK(filtered_clk),
        .ARESETn(ARESETn),

        .S_AXI_ARID(S_AXI_ARID),
        .S_AXI_ARADDR(S_AXI_ARADDR),
        .S_AXI_ARLEN(S_AXI_ARLEN),
        .S_AXI_ARSIZE(S_AXI_ARSIZE),
        .S_AXI_ARBURST(S_AXI_ARBURST),
        .S_AXI_ARVALID(S_AXI_ARVALID),
        .S_AXI_ARREADY(S_AXI_ARREADY),

        .S_AXI_RID(S_AXI_RID),
        .S_AXI_RDATA(S_AXI_RDATA),
        .S_AXI_RRESP(S_AXI_RRESP),
        .S_AXI_RLAST(S_AXI_RLAST),
        .S_AXI_RVALID(S_AXI_RVALID),
        .S_AXI_RREADY(S_AXI_RREADY),

        .M_AXI_ARID(M_AXI_ARID),
        .M_AXI_ARADDR(M_AXI_ARADDR),
        .M_AXI_ARLEN(M_AXI_ARLEN),
        .M_AXI_ARSIZE(M_AXI_ARSIZE),
        .M_AXI_ARBURST(M_AXI_ARBURST),
        .M_AXI_ARVALID(M_AXI_ARVALID),
        .M_AXI_ARREADY(M_AXI_ARREADY),

        .M_AXI_RID(M_AXI_RID),
        .M_AXI_RDATA(M_AXI_RDATA),
        .M_AXI_RRESP(M_AXI_RRESP),
        .M_AXI_RLAST(M_AXI_RLAST),
        .M_AXI_RVALID(M_AXI_RVALID),
        .M_AXI_RREADY(M_AXI_RREADY)
    );

    axi_write_ooo #(
        .ADDR_WIDTH(ADDR_WIDTH),
        .DATA_WIDTH(DATA_WIDTH),
        .ID_WIDTH(ID_WIDTH),
        .LEN_WIDTH(LEN_WIDTH),
        .NUM_WRITE_AWQUEUE(NUM_WRITE_AWQUEUE),
        .NUM_WRITE_SCHEDULER(NUM_WRITE_SCHEDULER),
        .NUM_WRITE_ORDER_QUEUE_AW(NUM_WRITE_ORDER_QUEUE_AW),
        .WRITE_KEEP_MAX_LENGTH(WRITE_KEEP_MAX_LENGTH),
        .WRITE_MAX_BURST_BEATS(WRITE_MAX_BURST_BEATS),
        .WRITE_SEQ_WIDTH(WRITE_SEQ_WIDTH)
    ) u_axi_write_ooo (
        .ACLK(filtered_clk),
        .ARESETn(ARESETn),

        .S_AXI_AWID(S_AXI_AWID),
        .S_AXI_AWADDR(S_AXI_AWADDR),
        .S_AXI_AWLEN(S_AXI_AWLEN),
        .S_AXI_AWSIZE(S_AXI_AWSIZE),
        .S_AXI_AWBURST(S_AXI_AWBURST),
        .S_AXI_AWVALID(S_AXI_AWVALID),
        .S_AXI_AWREADY(S_AXI_AWREADY),

        .S_AXI_WDATA(S_AXI_WDATA),
        .S_AXI_WSTRB(S_AXI_WSTRB),
        .S_AXI_WLAST(S_AXI_WLAST),
        .S_AXI_WVALID(S_AXI_WVALID),
        .S_AXI_WREADY(S_AXI_WREADY),

        .S_AXI_BID(S_AXI_BID),
        .S_AXI_BRESP(S_AXI_BRESP),
        .S_AXI_BVALID(S_AXI_BVALID),
        .S_AXI_BREADY(S_AXI_BREADY),

        .M_AXI_AWID(M_AXI_AWID),
        .M_AXI_AWADDR(M_AXI_AWADDR),
        .M_AXI_AWLEN(M_AXI_AWLEN),
        .M_AXI_AWSIZE(M_AXI_AWSIZE),
        .M_AXI_AWBURST(M_AXI_AWBURST),
        .M_AXI_AWVALID(M_AXI_AWVALID),
        .M_AXI_AWREADY(M_AXI_AWREADY),

        .M_AXI_WDATA(M_AXI_WDATA),
        .M_AXI_WSTRB(M_AXI_WSTRB),
        .M_AXI_WLAST(M_AXI_WLAST),
        .M_AXI_WVALID(M_AXI_WVALID),
        .M_AXI_WREADY(M_AXI_WREADY),

        .M_AXI_BID(M_AXI_BID),
        .M_AXI_BRESP(M_AXI_BRESP),
        .M_AXI_BVALID(M_AXI_BVALID),
        .M_AXI_BREADY(M_AXI_BREADY)
    );

endmodule
