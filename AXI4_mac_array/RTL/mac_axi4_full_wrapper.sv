module mac_axi4_full_wrapper #(
    parameter int ARRAY_H_SIZE = 4,
    parameter int ARRAY_K_SIZE = 4,
    parameter int ARRAY_W_SIZE = 4,
    parameter int DATA_WIDTH_IN = 8,
    parameter int ACC_WIDTH = 2 * DATA_WIDTH_IN,
    parameter int AXI_DATA_WIDTH = 64,
    parameter int AXI_ADDR_WIDTH = 32,
    parameter int AXI_ID_WIDTH = 4,
    parameter int AXI_STRB_WIDTH = AXI_DATA_WIDTH / 8,
    parameter logic [AXI_ID_WIDTH-1:0] AXI_ID = '0
)(
    input  logic ACLK,
    input  logic ARESETn,

    // Host command/configuration
    input  logic start,
    input  logic clear_request,
    input  logic [AXI_ADDR_WIDTH-1:0] a_base_addr,
    input  logic [AXI_ADDR_WIDTH-1:0] b_base_addr,
    input  logic [AXI_ADDR_WIDTH-1:0] c_base_addr,

    output logic busy,
    output logic done,
    output logic error,

    // Optional datapath status visibility
    output logic a_loaded,
    output logic b_loaded,
    output logic input_read_error,
    output logic mac_clear_done,
    output logic result_buffer_full,
    output logic write_data_done,

    // AXI4 Full master write-address channel
    output logic [AXI_ID_WIDTH-1:0]   m_axi_awid,
    output logic [AXI_ADDR_WIDTH-1:0] m_axi_awaddr,
    output logic [7:0]                m_axi_awlen,
    output logic [2:0]                m_axi_awsize,
    output logic [1:0]                m_axi_awburst,
    output logic                      m_axi_awlock,
    output logic [3:0]                m_axi_awcache,
    output logic [2:0]                m_axi_awprot,
    output logic [3:0]                m_axi_awqos,
    output logic                      m_axi_awvalid,
    input  logic                      m_axi_awready,

    // AXI4 Full master write-data channel
    output logic [AXI_DATA_WIDTH-1:0] m_axi_wdata,
    output logic [AXI_STRB_WIDTH-1:0] m_axi_wstrb,
    output logic                      m_axi_wlast,
    output logic                      m_axi_wvalid,
    input  logic                      m_axi_wready,

    // AXI4 Full master write-response channel
    input  logic [AXI_ID_WIDTH-1:0] m_axi_bid,
    input  logic [1:0]              m_axi_bresp,
    input  logic                    m_axi_bvalid,
    output logic                    m_axi_bready,

    // AXI4 Full master read-address channel
    output logic [AXI_ID_WIDTH-1:0]   m_axi_arid,
    output logic [AXI_ADDR_WIDTH-1:0] m_axi_araddr,
    output logic [7:0]                m_axi_arlen,
    output logic [2:0]                m_axi_arsize,
    output logic [1:0]                m_axi_arburst,
    output logic                      m_axi_arlock,
    output logic [3:0]                m_axi_arcache,
    output logic [2:0]                m_axi_arprot,
    output logic [3:0]                m_axi_arqos,
    output logic                      m_axi_arvalid,
    input  logic                      m_axi_arready,

    // AXI4 Full master read-data channel
    input  logic [AXI_ID_WIDTH-1:0]   m_axi_rid,
    input  logic [AXI_DATA_WIDTH-1:0] m_axi_rdata,
    input  logic [1:0]                m_axi_rresp,
    input  logic                      m_axi_rlast,
    input  logic                      m_axi_rvalid,
    output logic                      m_axi_rready
);
    localparam logic [2:0] AXI_FULL_SIZE = $clog2(AXI_STRB_WIDTH);

    logic datapath_clear;
    logic read_request;
    logic matrix_select;
    logic write_start;

    logic                      read_cmd_valid;
    logic                      read_cmd_ready;
    logic [AXI_ADDR_WIDTH-1:0] read_cmd_addr;
    logic [7:0]                read_cmd_len;
    logic                      read_cmd_done;
    logic                      read_cmd_error;

    logic                      write_cmd_valid;
    logic                      write_cmd_ready;
    logic [AXI_ADDR_WIDTH-1:0] write_cmd_addr;
    logic [7:0]                write_cmd_len;
    logic                      write_response_done;
    logic                      write_response_error;

    // The accelerator issues one read and one write command at a time.
    // Address-channel payloads remain stable while VALID waits for READY.
    assign m_axi_arid    = AXI_ID;
    assign m_axi_araddr  = read_cmd_addr;
    assign m_axi_arlen   = read_cmd_len;
    assign m_axi_arsize  = AXI_FULL_SIZE;
    assign m_axi_arburst = 2'b01;
    assign m_axi_arlock  = 1'b0;
    assign m_axi_arcache = 4'b0011;
    assign m_axi_arprot  = 3'b000;
    assign m_axi_arqos   = 4'b0000;
    assign m_axi_arvalid = read_cmd_valid;
    assign read_cmd_ready = m_axi_arready;

    assign m_axi_awid    = AXI_ID;
    assign m_axi_awaddr  = write_cmd_addr;
    assign m_axi_awlen   = write_cmd_len;
    assign m_axi_awsize  = AXI_FULL_SIZE;
    assign m_axi_awburst = 2'b01;
    assign m_axi_awlock  = 1'b0;
    assign m_axi_awcache = 4'b0011;
    assign m_axi_awprot  = 3'b000;
    assign m_axi_awqos   = 4'b0000;
    assign m_axi_awvalid = write_cmd_valid;
    assign write_cmd_ready = m_axi_awready;

    assign m_axi_bready = 1'b1;

    assign read_cmd_done =
        m_axi_rvalid && m_axi_rready && m_axi_rlast;
    assign read_cmd_error =
        m_axi_rvalid && m_axi_rready && m_axi_rresp[1];

    assign write_response_done =
        m_axi_bvalid && m_axi_bready;
    assign write_response_error =
        m_axi_bvalid && m_axi_bready && m_axi_bresp[1];

    controller #(
        .ARRAY_H_SIZE(ARRAY_H_SIZE),
        .ARRAY_K_SIZE(ARRAY_K_SIZE),
        .ARRAY_W_SIZE(ARRAY_W_SIZE),
        .DATA_WIDTH_IN(DATA_WIDTH_IN),
        .ACC_WIDTH(ACC_WIDTH),
        .AXI_DATA_WIDTH(AXI_DATA_WIDTH),
        .AXI_ADDR_WIDTH(AXI_ADDR_WIDTH),
        .AXI_LEN_WIDTH(8),
        .AXI_STRB_WIDTH(AXI_STRB_WIDTH)
    ) u_controller (
        .ACLK(ACLK),
        .ARESETn(ARESETn),

        .start(start),
        .clear_request(clear_request),
        .a_base_addr(a_base_addr),
        .b_base_addr(b_base_addr),
        .c_base_addr(c_base_addr),

        .busy(busy),
        .done(done),
        .error(error),

        .datapath_clear(datapath_clear),
        .read_request(read_request),
        .matrix_select(matrix_select),
        .write_start(write_start),
        .a_loaded(a_loaded),
        .b_loaded(b_loaded),
        .input_read_error(input_read_error),
        .mac_clear_done(mac_clear_done),
        .result_buffer_full(result_buffer_full),
        .write_data_done(write_data_done),

        .axi_rdata(m_axi_rdata),
        .axi_rresp(m_axi_rresp),
        .axi_rlast(m_axi_rlast),
        .axi_rvalid(m_axi_rvalid),
        .axi_rready(m_axi_rready),

        .axi_wdata(m_axi_wdata),
        .axi_wstrb(m_axi_wstrb),
        .axi_wlast(m_axi_wlast),
        .axi_wvalid(m_axi_wvalid),
        .axi_wready(m_axi_wready),

        .read_cmd_valid(read_cmd_valid),
        .read_cmd_ready(read_cmd_ready),
        .read_cmd_addr(read_cmd_addr),
        .read_cmd_len(read_cmd_len),
        .read_cmd_done(read_cmd_done),
        .read_cmd_error(read_cmd_error),

        .write_cmd_valid(write_cmd_valid),
        .write_cmd_ready(write_cmd_ready),
        .write_cmd_addr(write_cmd_addr),
        .write_cmd_len(write_cmd_len),
        .write_response_done(write_response_done),
        .write_response_error(write_response_error)
    );

endmodule
