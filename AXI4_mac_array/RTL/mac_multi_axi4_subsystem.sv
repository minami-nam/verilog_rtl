module mac_multi_axi4_subsystem #(
    parameter int NUM_MAC = 3,
    parameter int NUM_MEMORY = 3,
    parameter int NUM_CACHE = 16,
    parameter int ARRAY_H_SIZE = 4,
    parameter int ARRAY_K_SIZE = 4,
    parameter int ARRAY_W_SIZE = 4,
    parameter int DATA_WIDTH_IN = 8,
    parameter int ACC_WIDTH = 2 * DATA_WIDTH_IN,
    parameter int AXI_ADDR_WIDTH = 32,
    parameter int AXI_DATA_WIDTH = 64,
    parameter int AXI_ID_WIDTH = 4,
    parameter int AXI_STRB_WIDTH = AXI_DATA_WIDTH / 8,
    parameter int MEMORY_BYTES = 64 * 1024,
    parameter logic [NUM_MEMORY*AXI_ADDR_WIDTH-1:0] MEMORY_BASE_ADDR = {
        AXI_ADDR_WIDTH'(32'h8000_0000),
        AXI_ADDR_WIDTH'(32'h4000_0000),
        AXI_ADDR_WIDTH'(32'h0000_0000)
    },
    parameter logic [NUM_MEMORY*AXI_ADDR_WIDTH-1:0] MEMORY_END_ADDR = {
        AXI_ADDR_WIDTH'(32'h8000_FFFF),
        AXI_ADDR_WIDTH'(32'h4000_FFFF),
        AXI_ADDR_WIDTH'(32'h0000_FFFF)
    }
)(
    input  logic ACLK,
    input  logic ARESETn,

    input  logic [NUM_MAC-1:0] start,
    input  logic [NUM_MAC-1:0] clear_request,
    input  logic [NUM_MAC*AXI_ADDR_WIDTH-1:0] a_base_addr,
    input  logic [NUM_MAC*AXI_ADDR_WIDTH-1:0] b_base_addr,
    input  logic [NUM_MAC*AXI_ADDR_WIDTH-1:0] c_base_addr,

    output logic [NUM_MAC-1:0] busy,
    output logic [NUM_MAC-1:0] done,
    output logic [NUM_MAC-1:0] error
);
    // Packed lane 0 occupies the least-significant slice on every AXI bus.
    wire [NUM_MAC*AXI_ID_WIDTH-1:0]      s_axi_awid;
    wire [NUM_MAC*AXI_ADDR_WIDTH-1:0]    s_axi_awaddr;
    wire [NUM_MAC*8-1:0]                 s_axi_awlen;
    wire [NUM_MAC*3-1:0]                 s_axi_awsize;
    wire [NUM_MAC*2-1:0]                 s_axi_awburst;
    wire [NUM_MAC-1:0]                   s_axi_awlock;
    wire [NUM_MAC*4-1:0]                 s_axi_awcache;
    wire [NUM_MAC*3-1:0]                 s_axi_awprot;
    wire [NUM_MAC*4-1:0]                 s_axi_awqos;
    wire [NUM_MAC-1:0]                   s_axi_awvalid;
    wire [NUM_MAC-1:0]                   s_axi_awready;

    wire [NUM_MAC*AXI_DATA_WIDTH-1:0]    s_axi_wdata;
    wire [NUM_MAC*AXI_STRB_WIDTH-1:0]    s_axi_wstrb;
    wire [NUM_MAC-1:0]                   s_axi_wlast;
    wire [NUM_MAC-1:0]                   s_axi_wvalid;
    wire [NUM_MAC-1:0]                   s_axi_wready;

    wire [NUM_MAC*AXI_ID_WIDTH-1:0]      s_axi_bid;
    wire [NUM_MAC*2-1:0]                 s_axi_bresp;
    wire [NUM_MAC-1:0]                   s_axi_bvalid;
    wire [NUM_MAC-1:0]                   s_axi_bready;

    wire [NUM_MAC*AXI_ID_WIDTH-1:0]      s_axi_arid;
    wire [NUM_MAC*AXI_ADDR_WIDTH-1:0]    s_axi_araddr;
    wire [NUM_MAC*8-1:0]                 s_axi_arlen;
    wire [NUM_MAC*3-1:0]                 s_axi_arsize;
    wire [NUM_MAC*2-1:0]                 s_axi_arburst;
    wire [NUM_MAC-1:0]                   s_axi_arlock;
    wire [NUM_MAC*4-1:0]                 s_axi_arcache;
    wire [NUM_MAC*3-1:0]                 s_axi_arprot;
    wire [NUM_MAC*4-1:0]                 s_axi_arqos;
    wire [NUM_MAC-1:0]                   s_axi_arvalid;
    wire [NUM_MAC-1:0]                   s_axi_arready;

    wire [NUM_MAC*AXI_ID_WIDTH-1:0]      s_axi_rid;
    wire [NUM_MAC*AXI_DATA_WIDTH-1:0]    s_axi_rdata;
    wire [NUM_MAC*2-1:0]                 s_axi_rresp;
    wire [NUM_MAC-1:0]                   s_axi_rlast;
    wire [NUM_MAC-1:0]                   s_axi_rvalid;
    wire [NUM_MAC-1:0]                   s_axi_rready;

    wire [NUM_MEMORY*AXI_ID_WIDTH-1:0]   m_axi_awid;
    wire [NUM_MEMORY*AXI_ADDR_WIDTH-1:0] m_axi_awaddr;
    wire [NUM_MEMORY*8-1:0]              m_axi_awlen;
    wire [NUM_MEMORY*3-1:0]              m_axi_awsize;
    wire [NUM_MEMORY*2-1:0]              m_axi_awburst;
    wire [NUM_MEMORY-1:0]                m_axi_awlock;
    wire [NUM_MEMORY*4-1:0]              m_axi_awcache;
    wire [NUM_MEMORY*3-1:0]              m_axi_awprot;
    wire [NUM_MEMORY*4-1:0]              m_axi_awqos;
    wire [NUM_MEMORY-1:0]                m_axi_awvalid;
    wire [NUM_MEMORY-1:0]                m_axi_awready;

    wire [NUM_MEMORY*AXI_DATA_WIDTH-1:0] m_axi_wdata;
    wire [NUM_MEMORY*AXI_STRB_WIDTH-1:0] m_axi_wstrb;
    wire [NUM_MEMORY-1:0]                m_axi_wlast;
    wire [NUM_MEMORY-1:0]                m_axi_wvalid;
    wire [NUM_MEMORY-1:0]                m_axi_wready;

    wire [NUM_MEMORY*AXI_ID_WIDTH-1:0]   m_axi_bid;
    wire [NUM_MEMORY*2-1:0]              m_axi_bresp;
    wire [NUM_MEMORY-1:0]                m_axi_bvalid;
    wire [NUM_MEMORY-1:0]                m_axi_bready;

    wire [NUM_MEMORY*AXI_ID_WIDTH-1:0]   m_axi_arid;
    wire [NUM_MEMORY*AXI_ADDR_WIDTH-1:0] m_axi_araddr;
    wire [NUM_MEMORY*8-1:0]              m_axi_arlen;
    wire [NUM_MEMORY*3-1:0]              m_axi_arsize;
    wire [NUM_MEMORY*2-1:0]              m_axi_arburst;
    wire [NUM_MEMORY-1:0]                m_axi_arlock;
    wire [NUM_MEMORY*4-1:0]              m_axi_arcache;
    wire [NUM_MEMORY*3-1:0]              m_axi_arprot;
    wire [NUM_MEMORY*4-1:0]              m_axi_arqos;
    wire [NUM_MEMORY-1:0]                m_axi_arvalid;
    wire [NUM_MEMORY-1:0]                m_axi_arready;

    wire [NUM_MEMORY*AXI_ID_WIDTH-1:0]   m_axi_rid;
    wire [NUM_MEMORY*AXI_DATA_WIDTH-1:0] m_axi_rdata;
    wire [NUM_MEMORY*2-1:0]              m_axi_rresp;
    wire [NUM_MEMORY-1:0]                m_axi_rlast;
    wire [NUM_MEMORY-1:0]                m_axi_rvalid;
    wire [NUM_MEMORY-1:0]                m_axi_rready;

    genvar mac_index;
    generate
        for (mac_index = 0; mac_index < NUM_MAC; mac_index = mac_index + 1) begin : gen_mac_masters
            wire unused_a_loaded;
            wire unused_b_loaded;
            wire unused_input_read_error;
            wire unused_mac_clear_done;
            wire unused_result_buffer_full;
            wire unused_write_data_done;

            mac_axi4_full_wrapper #(
                .ARRAY_H_SIZE(ARRAY_H_SIZE),
                .ARRAY_K_SIZE(ARRAY_K_SIZE),
                .ARRAY_W_SIZE(ARRAY_W_SIZE),
                .DATA_WIDTH_IN(DATA_WIDTH_IN),
                .ACC_WIDTH(ACC_WIDTH),
                .AXI_DATA_WIDTH(AXI_DATA_WIDTH),
                .AXI_ADDR_WIDTH(AXI_ADDR_WIDTH),
                .AXI_ID_WIDTH(AXI_ID_WIDTH),
                .AXI_STRB_WIDTH(AXI_STRB_WIDTH),
                .AXI_ID(mac_index)
            ) u_mac_master (
                .ACLK(ACLK),
                .ARESETn(ARESETn),
                .start(start[mac_index]),
                .clear_request(clear_request[mac_index]),
                .a_base_addr(a_base_addr[mac_index*AXI_ADDR_WIDTH +: AXI_ADDR_WIDTH]),
                .b_base_addr(b_base_addr[mac_index*AXI_ADDR_WIDTH +: AXI_ADDR_WIDTH]),
                .c_base_addr(c_base_addr[mac_index*AXI_ADDR_WIDTH +: AXI_ADDR_WIDTH]),
                .busy(busy[mac_index]),
                .done(done[mac_index]),
                .error(error[mac_index]),
                .a_loaded(unused_a_loaded),
                .b_loaded(unused_b_loaded),
                .input_read_error(unused_input_read_error),
                .mac_clear_done(unused_mac_clear_done),
                .result_buffer_full(unused_result_buffer_full),
                .write_data_done(unused_write_data_done),

                .m_axi_awid(s_axi_awid[mac_index*AXI_ID_WIDTH +: AXI_ID_WIDTH]),
                .m_axi_awaddr(s_axi_awaddr[mac_index*AXI_ADDR_WIDTH +: AXI_ADDR_WIDTH]),
                .m_axi_awlen(s_axi_awlen[mac_index*8 +: 8]),
                .m_axi_awsize(s_axi_awsize[mac_index*3 +: 3]),
                .m_axi_awburst(s_axi_awburst[mac_index*2 +: 2]),
                .m_axi_awlock(s_axi_awlock[mac_index]),
                .m_axi_awcache(s_axi_awcache[mac_index*4 +: 4]),
                .m_axi_awprot(s_axi_awprot[mac_index*3 +: 3]),
                .m_axi_awqos(s_axi_awqos[mac_index*4 +: 4]),
                .m_axi_awvalid(s_axi_awvalid[mac_index]),
                .m_axi_awready(s_axi_awready[mac_index]),

                .m_axi_wdata(s_axi_wdata[mac_index*AXI_DATA_WIDTH +: AXI_DATA_WIDTH]),
                .m_axi_wstrb(s_axi_wstrb[mac_index*AXI_STRB_WIDTH +: AXI_STRB_WIDTH]),
                .m_axi_wlast(s_axi_wlast[mac_index]),
                .m_axi_wvalid(s_axi_wvalid[mac_index]),
                .m_axi_wready(s_axi_wready[mac_index]),

                .m_axi_bid(s_axi_bid[mac_index*AXI_ID_WIDTH +: AXI_ID_WIDTH]),
                .m_axi_bresp(s_axi_bresp[mac_index*2 +: 2]),
                .m_axi_bvalid(s_axi_bvalid[mac_index]),
                .m_axi_bready(s_axi_bready[mac_index]),

                .m_axi_arid(s_axi_arid[mac_index*AXI_ID_WIDTH +: AXI_ID_WIDTH]),
                .m_axi_araddr(s_axi_araddr[mac_index*AXI_ADDR_WIDTH +: AXI_ADDR_WIDTH]),
                .m_axi_arlen(s_axi_arlen[mac_index*8 +: 8]),
                .m_axi_arsize(s_axi_arsize[mac_index*3 +: 3]),
                .m_axi_arburst(s_axi_arburst[mac_index*2 +: 2]),
                .m_axi_arlock(s_axi_arlock[mac_index]),
                .m_axi_arcache(s_axi_arcache[mac_index*4 +: 4]),
                .m_axi_arprot(s_axi_arprot[mac_index*3 +: 3]),
                .m_axi_arqos(s_axi_arqos[mac_index*4 +: 4]),
                .m_axi_arvalid(s_axi_arvalid[mac_index]),
                .m_axi_arready(s_axi_arready[mac_index]),

                .m_axi_rid(s_axi_rid[mac_index*AXI_ID_WIDTH +: AXI_ID_WIDTH]),
                .m_axi_rdata(s_axi_rdata[mac_index*AXI_DATA_WIDTH +: AXI_DATA_WIDTH]),
                .m_axi_rresp(s_axi_rresp[mac_index*2 +: 2]),
                .m_axi_rlast(s_axi_rlast[mac_index]),
                .m_axi_rvalid(s_axi_rvalid[mac_index]),
                .m_axi_rready(s_axi_rready[mac_index])
            );
        end
    endgenerate

    axi_controller_unit #(
        .NUM_CACHE(NUM_CACHE),
        .ADDR_WIDTH(AXI_ADDR_WIDTH),
        .DATA_WIDTH(AXI_DATA_WIDTH),
        .ID_WIDTH(AXI_ID_WIDTH),
        .NUM_MASTER(NUM_MAC),
        .NUM_SLAVE(NUM_MEMORY),
        .STRB_WIDTH(AXI_STRB_WIDTH),
        .BASE_ADDR(MEMORY_BASE_ADDR),
        .END_ADDR(MEMORY_END_ADDR)
    ) u_axi_interconnect (
        .ACLK(ACLK),
        .ARESETn(ARESETn),

        .s_axi_awid(s_axi_awid),
        .s_axi_awaddr(s_axi_awaddr),
        .s_axi_awlen(s_axi_awlen),
        .s_axi_awsize(s_axi_awsize),
        .s_axi_awburst(s_axi_awburst),
        .s_axi_awlock(s_axi_awlock),
        .s_axi_awcache(s_axi_awcache),
        .s_axi_awprot(s_axi_awprot),
        .s_axi_awqos(s_axi_awqos),
        .s_axi_awvalid(s_axi_awvalid),
        .s_axi_awready(s_axi_awready),
        .s_axi_wdata(s_axi_wdata),
        .s_axi_wstrb(s_axi_wstrb),
        .s_axi_wlast(s_axi_wlast),
        .s_axi_wvalid(s_axi_wvalid),
        .s_axi_wready(s_axi_wready),
        .s_axi_bid(s_axi_bid),
        .s_axi_bresp(s_axi_bresp),
        .s_axi_bvalid(s_axi_bvalid),
        .s_axi_bready(s_axi_bready),
        .s_axi_arid(s_axi_arid),
        .s_axi_araddr(s_axi_araddr),
        .s_axi_arlen(s_axi_arlen),
        .s_axi_arsize(s_axi_arsize),
        .s_axi_arburst(s_axi_arburst),
        .s_axi_arlock(s_axi_arlock),
        .s_axi_arcache(s_axi_arcache),
        .s_axi_arprot(s_axi_arprot),
        .s_axi_arqos(s_axi_arqos),
        .s_axi_arvalid(s_axi_arvalid),
        .s_axi_arready(s_axi_arready),
        .s_axi_rid(s_axi_rid),
        .s_axi_rdata(s_axi_rdata),
        .s_axi_rresp(s_axi_rresp),
        .s_axi_rlast(s_axi_rlast),
        .s_axi_rvalid(s_axi_rvalid),
        .s_axi_rready(s_axi_rready),

        .m_axi_awid(m_axi_awid),
        .m_axi_awaddr(m_axi_awaddr),
        .m_axi_awlen(m_axi_awlen),
        .m_axi_awsize(m_axi_awsize),
        .m_axi_awburst(m_axi_awburst),
        .m_axi_awlock(m_axi_awlock),
        .m_axi_awcache(m_axi_awcache),
        .m_axi_awprot(m_axi_awprot),
        .m_axi_awqos(m_axi_awqos),
        .m_axi_awvalid(m_axi_awvalid),
        .m_axi_awready(m_axi_awready),
        .m_axi_wdata(m_axi_wdata),
        .m_axi_wstrb(m_axi_wstrb),
        .m_axi_wlast(m_axi_wlast),
        .m_axi_wvalid(m_axi_wvalid),
        .m_axi_wready(m_axi_wready),
        .m_axi_bid(m_axi_bid),
        .m_axi_bresp(m_axi_bresp),
        .m_axi_bvalid(m_axi_bvalid),
        .m_axi_bready(m_axi_bready),
        .m_axi_arid(m_axi_arid),
        .m_axi_araddr(m_axi_araddr),
        .m_axi_arlen(m_axi_arlen),
        .m_axi_arsize(m_axi_arsize),
        .m_axi_arburst(m_axi_arburst),
        .m_axi_arlock(m_axi_arlock),
        .m_axi_arcache(m_axi_arcache),
        .m_axi_arprot(m_axi_arprot),
        .m_axi_arqos(m_axi_arqos),
        .m_axi_arvalid(m_axi_arvalid),
        .m_axi_arready(m_axi_arready),
        .m_axi_rid(m_axi_rid),
        .m_axi_rdata(m_axi_rdata),
        .m_axi_rresp(m_axi_rresp),
        .m_axi_rlast(m_axi_rlast),
        .m_axi_rvalid(m_axi_rvalid),
        .m_axi_rready(m_axi_rready)
    );

    genvar memory_index;
    generate
        for (memory_index = 0;
             memory_index < NUM_MEMORY;
             memory_index = memory_index + 1) begin : gen_memories
            axi4_full_memory #(
                .AXI_ADDR_WIDTH(AXI_ADDR_WIDTH),
                .AXI_DATA_WIDTH(AXI_DATA_WIDTH),
                .AXI_ID_WIDTH(AXI_ID_WIDTH),
                .AXI_STRB_WIDTH(AXI_STRB_WIDTH),
                .MEM_BYTES(MEMORY_BYTES),
                .BASE_ADDR(MEMORY_BASE_ADDR[
                    memory_index*AXI_ADDR_WIDTH +: AXI_ADDR_WIDTH]),
                .ZERO_INIT(1'b1)
            ) u_memory (
                .ACLK(ACLK),
                .ARESETn(ARESETn),

                .s_axi_awid(m_axi_awid[memory_index*AXI_ID_WIDTH +: AXI_ID_WIDTH]),
                .s_axi_awaddr(m_axi_awaddr[memory_index*AXI_ADDR_WIDTH +: AXI_ADDR_WIDTH]),
                .s_axi_awlen(m_axi_awlen[memory_index*8 +: 8]),
                .s_axi_awsize(m_axi_awsize[memory_index*3 +: 3]),
                .s_axi_awburst(m_axi_awburst[memory_index*2 +: 2]),
                .s_axi_awlock(m_axi_awlock[memory_index]),
                .s_axi_awcache(m_axi_awcache[memory_index*4 +: 4]),
                .s_axi_awprot(m_axi_awprot[memory_index*3 +: 3]),
                .s_axi_awqos(m_axi_awqos[memory_index*4 +: 4]),
                .s_axi_awvalid(m_axi_awvalid[memory_index]),
                .s_axi_awready(m_axi_awready[memory_index]),

                .s_axi_wdata(m_axi_wdata[memory_index*AXI_DATA_WIDTH +: AXI_DATA_WIDTH]),
                .s_axi_wstrb(m_axi_wstrb[memory_index*AXI_STRB_WIDTH +: AXI_STRB_WIDTH]),
                .s_axi_wlast(m_axi_wlast[memory_index]),
                .s_axi_wvalid(m_axi_wvalid[memory_index]),
                .s_axi_wready(m_axi_wready[memory_index]),

                .s_axi_bid(m_axi_bid[memory_index*AXI_ID_WIDTH +: AXI_ID_WIDTH]),
                .s_axi_bresp(m_axi_bresp[memory_index*2 +: 2]),
                .s_axi_bvalid(m_axi_bvalid[memory_index]),
                .s_axi_bready(m_axi_bready[memory_index]),

                .s_axi_arid(m_axi_arid[memory_index*AXI_ID_WIDTH +: AXI_ID_WIDTH]),
                .s_axi_araddr(m_axi_araddr[memory_index*AXI_ADDR_WIDTH +: AXI_ADDR_WIDTH]),
                .s_axi_arlen(m_axi_arlen[memory_index*8 +: 8]),
                .s_axi_arsize(m_axi_arsize[memory_index*3 +: 3]),
                .s_axi_arburst(m_axi_arburst[memory_index*2 +: 2]),
                .s_axi_arlock(m_axi_arlock[memory_index]),
                .s_axi_arcache(m_axi_arcache[memory_index*4 +: 4]),
                .s_axi_arprot(m_axi_arprot[memory_index*3 +: 3]),
                .s_axi_arqos(m_axi_arqos[memory_index*4 +: 4]),
                .s_axi_arvalid(m_axi_arvalid[memory_index]),
                .s_axi_arready(m_axi_arready[memory_index]),

                .s_axi_rid(m_axi_rid[memory_index*AXI_ID_WIDTH +: AXI_ID_WIDTH]),
                .s_axi_rdata(m_axi_rdata[memory_index*AXI_DATA_WIDTH +: AXI_DATA_WIDTH]),
                .s_axi_rresp(m_axi_rresp[memory_index*2 +: 2]),
                .s_axi_rlast(m_axi_rlast[memory_index]),
                .s_axi_rvalid(m_axi_rvalid[memory_index]),
                .s_axi_rready(m_axi_rready[memory_index])
            );
        end
    endgenerate

endmodule
