// Vivado Block Design wrapper for the fixed 3-master/3-slave controller.
// Lane 0 occupies the least-significant slice of every packed core port.
module axi_controller_wrapper #(
    parameter int NUM_CACHE  = 16,
    parameter int ADDR_WIDTH = 32,
    parameter int DATA_WIDTH = 32,
    parameter int ID_WIDTH   = 4,
    parameter int STRB_WIDTH = DATA_WIDTH / 8,
    parameter logic [3*ADDR_WIDTH-1:0] BASE_ADDR = {
        ADDR_WIDTH'(32'h0000_0000),
        ADDR_WIDTH'(32'h4000_0000),
        ADDR_WIDTH'(32'hA000_0000)
    },
    parameter logic [3*ADDR_WIDTH-1:0] END_ADDR = {
        ADDR_WIDTH'(32'h3FFF_FFFF),
        ADDR_WIDTH'(32'h9FFF_FFFF),
        ADDR_WIDTH'(32'hFFFF_FFFF)
    }
) (
    (* X_INTERFACE_INFO = "xilinx.com:signal:clock:1.0 ACLK CLK",
       X_INTERFACE_PARAMETER = "XIL_INTERFACENAME ACLK, ASSOCIATED_BUSIF S00_AXI:S01_AXI:S02_AXI:M00_AXI:M01_AXI:M02_AXI, ASSOCIATED_RESET ARESETn" *)
    input wire ACLK,

    (* X_INTERFACE_INFO = "xilinx.com:signal:reset:1.0 ARESETn RST",
       X_INTERFACE_PARAMETER = "XIL_INTERFACENAME ARESETn, POLARITY ACTIVE_LOW" *)
    input wire ARESETn,

    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S00_AXI AWID",
       X_INTERFACE_MODE = "slave",
       X_INTERFACE_PARAMETER = "XIL_INTERFACENAME S00_AXI, PROTOCOL AXI4, READ_WRITE_MODE READ_WRITE, HAS_BURST 1, HAS_LOCK 1, HAS_CACHE 1, HAS_QOS 1, HAS_WSTRB 1, HAS_BRESP 1, HAS_RRESP 1, SUPPORTS_NARROW_BURST 1, NUM_READ_OUTSTANDING 1, NUM_WRITE_OUTSTANDING 1, MAX_BURST_LENGTH 256" *)
    input  wire [ID_WIDTH-1:0] s00_axi_awid,

    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S00_AXI AWADDR" *)
    input  wire [ADDR_WIDTH-1:0] s00_axi_awaddr,

    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S00_AXI AWLEN" *)
    input  wire [8-1:0] s00_axi_awlen,

    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S00_AXI AWSIZE" *)
    input  wire [3-1:0] s00_axi_awsize,

    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S00_AXI AWBURST" *)
    input  wire [2-1:0] s00_axi_awburst,

    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S00_AXI AWLOCK" *)
    input  wire s00_axi_awlock,

    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S00_AXI AWCACHE" *)
    input  wire [4-1:0] s00_axi_awcache,

    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S00_AXI AWPROT" *)
    input  wire [3-1:0] s00_axi_awprot,

    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S00_AXI AWQOS" *)
    input  wire [4-1:0] s00_axi_awqos,

    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S00_AXI AWVALID" *)
    input  wire s00_axi_awvalid,

    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S00_AXI AWREADY" *)
    output wire s00_axi_awready,

    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S00_AXI WDATA" *)
    input  wire [DATA_WIDTH-1:0] s00_axi_wdata,

    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S00_AXI WSTRB" *)
    input  wire [STRB_WIDTH-1:0] s00_axi_wstrb,

    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S00_AXI WLAST" *)
    input  wire s00_axi_wlast,

    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S00_AXI WVALID" *)
    input  wire s00_axi_wvalid,

    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S00_AXI WREADY" *)
    output wire s00_axi_wready,

    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S00_AXI BID" *)
    output wire [ID_WIDTH-1:0] s00_axi_bid,

    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S00_AXI BRESP" *)
    output wire [2-1:0] s00_axi_bresp,

    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S00_AXI BVALID" *)
    output wire s00_axi_bvalid,

    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S00_AXI BREADY" *)
    input  wire s00_axi_bready,

    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S00_AXI ARID" *)
    input  wire [ID_WIDTH-1:0] s00_axi_arid,

    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S00_AXI ARADDR" *)
    input  wire [ADDR_WIDTH-1:0] s00_axi_araddr,

    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S00_AXI ARLEN" *)
    input  wire [8-1:0] s00_axi_arlen,

    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S00_AXI ARSIZE" *)
    input  wire [3-1:0] s00_axi_arsize,

    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S00_AXI ARBURST" *)
    input  wire [2-1:0] s00_axi_arburst,

    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S00_AXI ARLOCK" *)
    input  wire s00_axi_arlock,

    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S00_AXI ARCACHE" *)
    input  wire [4-1:0] s00_axi_arcache,

    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S00_AXI ARPROT" *)
    input  wire [3-1:0] s00_axi_arprot,

    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S00_AXI ARQOS" *)
    input  wire [4-1:0] s00_axi_arqos,

    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S00_AXI ARVALID" *)
    input  wire s00_axi_arvalid,

    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S00_AXI ARREADY" *)
    output wire s00_axi_arready,

    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S00_AXI RID" *)
    output wire [ID_WIDTH-1:0] s00_axi_rid,

    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S00_AXI RDATA" *)
    output wire [DATA_WIDTH-1:0] s00_axi_rdata,

    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S00_AXI RRESP" *)
    output wire [2-1:0] s00_axi_rresp,

    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S00_AXI RLAST" *)
    output wire s00_axi_rlast,

    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S00_AXI RVALID" *)
    output wire s00_axi_rvalid,

    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S00_AXI RREADY" *)
    input  wire s00_axi_rready,

    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S01_AXI AWID",
       X_INTERFACE_MODE = "slave",
       X_INTERFACE_PARAMETER = "XIL_INTERFACENAME S01_AXI, PROTOCOL AXI4, READ_WRITE_MODE READ_WRITE, HAS_BURST 1, HAS_LOCK 1, HAS_CACHE 1, HAS_QOS 1, HAS_WSTRB 1, HAS_BRESP 1, HAS_RRESP 1, SUPPORTS_NARROW_BURST 1, NUM_READ_OUTSTANDING 1, NUM_WRITE_OUTSTANDING 1, MAX_BURST_LENGTH 256" *)
    input  wire [ID_WIDTH-1:0] s01_axi_awid,

    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S01_AXI AWADDR" *)
    input  wire [ADDR_WIDTH-1:0] s01_axi_awaddr,

    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S01_AXI AWLEN" *)
    input  wire [8-1:0] s01_axi_awlen,

    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S01_AXI AWSIZE" *)
    input  wire [3-1:0] s01_axi_awsize,

    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S01_AXI AWBURST" *)
    input  wire [2-1:0] s01_axi_awburst,

    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S01_AXI AWLOCK" *)
    input  wire s01_axi_awlock,

    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S01_AXI AWCACHE" *)
    input  wire [4-1:0] s01_axi_awcache,

    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S01_AXI AWPROT" *)
    input  wire [3-1:0] s01_axi_awprot,

    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S01_AXI AWQOS" *)
    input  wire [4-1:0] s01_axi_awqos,

    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S01_AXI AWVALID" *)
    input  wire s01_axi_awvalid,

    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S01_AXI AWREADY" *)
    output wire s01_axi_awready,

    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S01_AXI WDATA" *)
    input  wire [DATA_WIDTH-1:0] s01_axi_wdata,

    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S01_AXI WSTRB" *)
    input  wire [STRB_WIDTH-1:0] s01_axi_wstrb,

    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S01_AXI WLAST" *)
    input  wire s01_axi_wlast,

    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S01_AXI WVALID" *)
    input  wire s01_axi_wvalid,

    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S01_AXI WREADY" *)
    output wire s01_axi_wready,

    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S01_AXI BID" *)
    output wire [ID_WIDTH-1:0] s01_axi_bid,

    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S01_AXI BRESP" *)
    output wire [2-1:0] s01_axi_bresp,

    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S01_AXI BVALID" *)
    output wire s01_axi_bvalid,

    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S01_AXI BREADY" *)
    input  wire s01_axi_bready,

    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S01_AXI ARID" *)
    input  wire [ID_WIDTH-1:0] s01_axi_arid,

    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S01_AXI ARADDR" *)
    input  wire [ADDR_WIDTH-1:0] s01_axi_araddr,

    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S01_AXI ARLEN" *)
    input  wire [8-1:0] s01_axi_arlen,

    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S01_AXI ARSIZE" *)
    input  wire [3-1:0] s01_axi_arsize,

    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S01_AXI ARBURST" *)
    input  wire [2-1:0] s01_axi_arburst,

    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S01_AXI ARLOCK" *)
    input  wire s01_axi_arlock,

    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S01_AXI ARCACHE" *)
    input  wire [4-1:0] s01_axi_arcache,

    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S01_AXI ARPROT" *)
    input  wire [3-1:0] s01_axi_arprot,

    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S01_AXI ARQOS" *)
    input  wire [4-1:0] s01_axi_arqos,

    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S01_AXI ARVALID" *)
    input  wire s01_axi_arvalid,

    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S01_AXI ARREADY" *)
    output wire s01_axi_arready,

    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S01_AXI RID" *)
    output wire [ID_WIDTH-1:0] s01_axi_rid,

    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S01_AXI RDATA" *)
    output wire [DATA_WIDTH-1:0] s01_axi_rdata,

    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S01_AXI RRESP" *)
    output wire [2-1:0] s01_axi_rresp,

    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S01_AXI RLAST" *)
    output wire s01_axi_rlast,

    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S01_AXI RVALID" *)
    output wire s01_axi_rvalid,

    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S01_AXI RREADY" *)
    input  wire s01_axi_rready,

    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S02_AXI AWID",
       X_INTERFACE_MODE = "slave",
       X_INTERFACE_PARAMETER = "XIL_INTERFACENAME S02_AXI, PROTOCOL AXI4, READ_WRITE_MODE READ_WRITE, HAS_BURST 1, HAS_LOCK 1, HAS_CACHE 1, HAS_QOS 1, HAS_WSTRB 1, HAS_BRESP 1, HAS_RRESP 1, SUPPORTS_NARROW_BURST 1, NUM_READ_OUTSTANDING 1, NUM_WRITE_OUTSTANDING 1, MAX_BURST_LENGTH 256" *)
    input  wire [ID_WIDTH-1:0] s02_axi_awid,

    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S02_AXI AWADDR" *)
    input  wire [ADDR_WIDTH-1:0] s02_axi_awaddr,

    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S02_AXI AWLEN" *)
    input  wire [8-1:0] s02_axi_awlen,

    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S02_AXI AWSIZE" *)
    input  wire [3-1:0] s02_axi_awsize,

    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S02_AXI AWBURST" *)
    input  wire [2-1:0] s02_axi_awburst,

    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S02_AXI AWLOCK" *)
    input  wire s02_axi_awlock,

    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S02_AXI AWCACHE" *)
    input  wire [4-1:0] s02_axi_awcache,

    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S02_AXI AWPROT" *)
    input  wire [3-1:0] s02_axi_awprot,

    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S02_AXI AWQOS" *)
    input  wire [4-1:0] s02_axi_awqos,

    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S02_AXI AWVALID" *)
    input  wire s02_axi_awvalid,

    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S02_AXI AWREADY" *)
    output wire s02_axi_awready,

    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S02_AXI WDATA" *)
    input  wire [DATA_WIDTH-1:0] s02_axi_wdata,

    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S02_AXI WSTRB" *)
    input  wire [STRB_WIDTH-1:0] s02_axi_wstrb,

    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S02_AXI WLAST" *)
    input  wire s02_axi_wlast,

    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S02_AXI WVALID" *)
    input  wire s02_axi_wvalid,

    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S02_AXI WREADY" *)
    output wire s02_axi_wready,

    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S02_AXI BID" *)
    output wire [ID_WIDTH-1:0] s02_axi_bid,

    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S02_AXI BRESP" *)
    output wire [2-1:0] s02_axi_bresp,

    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S02_AXI BVALID" *)
    output wire s02_axi_bvalid,

    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S02_AXI BREADY" *)
    input  wire s02_axi_bready,

    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S02_AXI ARID" *)
    input  wire [ID_WIDTH-1:0] s02_axi_arid,

    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S02_AXI ARADDR" *)
    input  wire [ADDR_WIDTH-1:0] s02_axi_araddr,

    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S02_AXI ARLEN" *)
    input  wire [8-1:0] s02_axi_arlen,

    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S02_AXI ARSIZE" *)
    input  wire [3-1:0] s02_axi_arsize,

    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S02_AXI ARBURST" *)
    input  wire [2-1:0] s02_axi_arburst,

    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S02_AXI ARLOCK" *)
    input  wire s02_axi_arlock,

    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S02_AXI ARCACHE" *)
    input  wire [4-1:0] s02_axi_arcache,

    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S02_AXI ARPROT" *)
    input  wire [3-1:0] s02_axi_arprot,

    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S02_AXI ARQOS" *)
    input  wire [4-1:0] s02_axi_arqos,

    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S02_AXI ARVALID" *)
    input  wire s02_axi_arvalid,

    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S02_AXI ARREADY" *)
    output wire s02_axi_arready,

    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S02_AXI RID" *)
    output wire [ID_WIDTH-1:0] s02_axi_rid,

    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S02_AXI RDATA" *)
    output wire [DATA_WIDTH-1:0] s02_axi_rdata,

    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S02_AXI RRESP" *)
    output wire [2-1:0] s02_axi_rresp,

    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S02_AXI RLAST" *)
    output wire s02_axi_rlast,

    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S02_AXI RVALID" *)
    output wire s02_axi_rvalid,

    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 S02_AXI RREADY" *)
    input  wire s02_axi_rready,

    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M00_AXI AWID",
       X_INTERFACE_MODE = "master",
       X_INTERFACE_PARAMETER = "XIL_INTERFACENAME M00_AXI, PROTOCOL AXI4, READ_WRITE_MODE READ_WRITE, HAS_BURST 1, HAS_LOCK 1, HAS_CACHE 1, HAS_QOS 1, HAS_WSTRB 1, HAS_BRESP 1, HAS_RRESP 1, SUPPORTS_NARROW_BURST 1, NUM_READ_OUTSTANDING 1, NUM_WRITE_OUTSTANDING 1, MAX_BURST_LENGTH 256" *)
    output wire [ID_WIDTH-1:0] m00_axi_awid,

    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M00_AXI AWADDR" *)
    output wire [ADDR_WIDTH-1:0] m00_axi_awaddr,

    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M00_AXI AWLEN" *)
    output wire [8-1:0] m00_axi_awlen,

    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M00_AXI AWSIZE" *)
    output wire [3-1:0] m00_axi_awsize,

    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M00_AXI AWBURST" *)
    output wire [2-1:0] m00_axi_awburst,

    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M00_AXI AWLOCK" *)
    output wire m00_axi_awlock,

    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M00_AXI AWCACHE" *)
    output wire [4-1:0] m00_axi_awcache,

    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M00_AXI AWPROT" *)
    output wire [3-1:0] m00_axi_awprot,

    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M00_AXI AWQOS" *)
    output wire [4-1:0] m00_axi_awqos,

    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M00_AXI AWVALID" *)
    output wire m00_axi_awvalid,

    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M00_AXI AWREADY" *)
    input  wire m00_axi_awready,

    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M00_AXI WDATA" *)
    output wire [DATA_WIDTH-1:0] m00_axi_wdata,

    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M00_AXI WSTRB" *)
    output wire [STRB_WIDTH-1:0] m00_axi_wstrb,

    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M00_AXI WLAST" *)
    output wire m00_axi_wlast,

    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M00_AXI WVALID" *)
    output wire m00_axi_wvalid,

    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M00_AXI WREADY" *)
    input  wire m00_axi_wready,

    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M00_AXI BID" *)
    input  wire [ID_WIDTH-1:0] m00_axi_bid,

    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M00_AXI BRESP" *)
    input  wire [2-1:0] m00_axi_bresp,

    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M00_AXI BVALID" *)
    input  wire m00_axi_bvalid,

    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M00_AXI BREADY" *)
    output wire m00_axi_bready,

    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M00_AXI ARID" *)
    output wire [ID_WIDTH-1:0] m00_axi_arid,

    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M00_AXI ARADDR" *)
    output wire [ADDR_WIDTH-1:0] m00_axi_araddr,

    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M00_AXI ARLEN" *)
    output wire [8-1:0] m00_axi_arlen,

    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M00_AXI ARSIZE" *)
    output wire [3-1:0] m00_axi_arsize,

    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M00_AXI ARBURST" *)
    output wire [2-1:0] m00_axi_arburst,

    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M00_AXI ARLOCK" *)
    output wire m00_axi_arlock,

    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M00_AXI ARCACHE" *)
    output wire [4-1:0] m00_axi_arcache,

    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M00_AXI ARPROT" *)
    output wire [3-1:0] m00_axi_arprot,

    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M00_AXI ARQOS" *)
    output wire [4-1:0] m00_axi_arqos,

    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M00_AXI ARVALID" *)
    output wire m00_axi_arvalid,

    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M00_AXI ARREADY" *)
    input  wire m00_axi_arready,

    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M00_AXI RID" *)
    input  wire [ID_WIDTH-1:0] m00_axi_rid,

    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M00_AXI RDATA" *)
    input  wire [DATA_WIDTH-1:0] m00_axi_rdata,

    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M00_AXI RRESP" *)
    input  wire [2-1:0] m00_axi_rresp,

    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M00_AXI RLAST" *)
    input  wire m00_axi_rlast,

    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M00_AXI RVALID" *)
    input  wire m00_axi_rvalid,

    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M00_AXI RREADY" *)
    output wire m00_axi_rready,

    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M01_AXI AWID",
       X_INTERFACE_MODE = "master",
       X_INTERFACE_PARAMETER = "XIL_INTERFACENAME M01_AXI, PROTOCOL AXI4, READ_WRITE_MODE READ_WRITE, HAS_BURST 1, HAS_LOCK 1, HAS_CACHE 1, HAS_QOS 1, HAS_WSTRB 1, HAS_BRESP 1, HAS_RRESP 1, SUPPORTS_NARROW_BURST 1, NUM_READ_OUTSTANDING 1, NUM_WRITE_OUTSTANDING 1, MAX_BURST_LENGTH 256" *)
    output wire [ID_WIDTH-1:0] m01_axi_awid,

    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M01_AXI AWADDR" *)
    output wire [ADDR_WIDTH-1:0] m01_axi_awaddr,

    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M01_AXI AWLEN" *)
    output wire [8-1:0] m01_axi_awlen,

    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M01_AXI AWSIZE" *)
    output wire [3-1:0] m01_axi_awsize,

    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M01_AXI AWBURST" *)
    output wire [2-1:0] m01_axi_awburst,

    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M01_AXI AWLOCK" *)
    output wire m01_axi_awlock,

    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M01_AXI AWCACHE" *)
    output wire [4-1:0] m01_axi_awcache,

    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M01_AXI AWPROT" *)
    output wire [3-1:0] m01_axi_awprot,

    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M01_AXI AWQOS" *)
    output wire [4-1:0] m01_axi_awqos,

    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M01_AXI AWVALID" *)
    output wire m01_axi_awvalid,

    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M01_AXI AWREADY" *)
    input  wire m01_axi_awready,

    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M01_AXI WDATA" *)
    output wire [DATA_WIDTH-1:0] m01_axi_wdata,

    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M01_AXI WSTRB" *)
    output wire [STRB_WIDTH-1:0] m01_axi_wstrb,

    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M01_AXI WLAST" *)
    output wire m01_axi_wlast,

    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M01_AXI WVALID" *)
    output wire m01_axi_wvalid,

    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M01_AXI WREADY" *)
    input  wire m01_axi_wready,

    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M01_AXI BID" *)
    input  wire [ID_WIDTH-1:0] m01_axi_bid,

    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M01_AXI BRESP" *)
    input  wire [2-1:0] m01_axi_bresp,

    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M01_AXI BVALID" *)
    input  wire m01_axi_bvalid,

    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M01_AXI BREADY" *)
    output wire m01_axi_bready,

    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M01_AXI ARID" *)
    output wire [ID_WIDTH-1:0] m01_axi_arid,

    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M01_AXI ARADDR" *)
    output wire [ADDR_WIDTH-1:0] m01_axi_araddr,

    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M01_AXI ARLEN" *)
    output wire [8-1:0] m01_axi_arlen,

    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M01_AXI ARSIZE" *)
    output wire [3-1:0] m01_axi_arsize,

    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M01_AXI ARBURST" *)
    output wire [2-1:0] m01_axi_arburst,

    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M01_AXI ARLOCK" *)
    output wire m01_axi_arlock,

    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M01_AXI ARCACHE" *)
    output wire [4-1:0] m01_axi_arcache,

    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M01_AXI ARPROT" *)
    output wire [3-1:0] m01_axi_arprot,

    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M01_AXI ARQOS" *)
    output wire [4-1:0] m01_axi_arqos,

    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M01_AXI ARVALID" *)
    output wire m01_axi_arvalid,

    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M01_AXI ARREADY" *)
    input  wire m01_axi_arready,

    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M01_AXI RID" *)
    input  wire [ID_WIDTH-1:0] m01_axi_rid,

    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M01_AXI RDATA" *)
    input  wire [DATA_WIDTH-1:0] m01_axi_rdata,

    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M01_AXI RRESP" *)
    input  wire [2-1:0] m01_axi_rresp,

    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M01_AXI RLAST" *)
    input  wire m01_axi_rlast,

    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M01_AXI RVALID" *)
    input  wire m01_axi_rvalid,

    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M01_AXI RREADY" *)
    output wire m01_axi_rready,

    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M02_AXI AWID",
       X_INTERFACE_MODE = "master",
       X_INTERFACE_PARAMETER = "XIL_INTERFACENAME M02_AXI, PROTOCOL AXI4, READ_WRITE_MODE READ_WRITE, HAS_BURST 1, HAS_LOCK 1, HAS_CACHE 1, HAS_QOS 1, HAS_WSTRB 1, HAS_BRESP 1, HAS_RRESP 1, SUPPORTS_NARROW_BURST 1, NUM_READ_OUTSTANDING 1, NUM_WRITE_OUTSTANDING 1, MAX_BURST_LENGTH 256" *)
    output wire [ID_WIDTH-1:0] m02_axi_awid,

    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M02_AXI AWADDR" *)
    output wire [ADDR_WIDTH-1:0] m02_axi_awaddr,

    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M02_AXI AWLEN" *)
    output wire [8-1:0] m02_axi_awlen,

    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M02_AXI AWSIZE" *)
    output wire [3-1:0] m02_axi_awsize,

    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M02_AXI AWBURST" *)
    output wire [2-1:0] m02_axi_awburst,

    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M02_AXI AWLOCK" *)
    output wire m02_axi_awlock,

    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M02_AXI AWCACHE" *)
    output wire [4-1:0] m02_axi_awcache,

    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M02_AXI AWPROT" *)
    output wire [3-1:0] m02_axi_awprot,

    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M02_AXI AWQOS" *)
    output wire [4-1:0] m02_axi_awqos,

    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M02_AXI AWVALID" *)
    output wire m02_axi_awvalid,

    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M02_AXI AWREADY" *)
    input  wire m02_axi_awready,

    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M02_AXI WDATA" *)
    output wire [DATA_WIDTH-1:0] m02_axi_wdata,

    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M02_AXI WSTRB" *)
    output wire [STRB_WIDTH-1:0] m02_axi_wstrb,

    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M02_AXI WLAST" *)
    output wire m02_axi_wlast,

    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M02_AXI WVALID" *)
    output wire m02_axi_wvalid,

    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M02_AXI WREADY" *)
    input  wire m02_axi_wready,

    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M02_AXI BID" *)
    input  wire [ID_WIDTH-1:0] m02_axi_bid,

    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M02_AXI BRESP" *)
    input  wire [2-1:0] m02_axi_bresp,

    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M02_AXI BVALID" *)
    input  wire m02_axi_bvalid,

    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M02_AXI BREADY" *)
    output wire m02_axi_bready,

    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M02_AXI ARID" *)
    output wire [ID_WIDTH-1:0] m02_axi_arid,

    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M02_AXI ARADDR" *)
    output wire [ADDR_WIDTH-1:0] m02_axi_araddr,

    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M02_AXI ARLEN" *)
    output wire [8-1:0] m02_axi_arlen,

    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M02_AXI ARSIZE" *)
    output wire [3-1:0] m02_axi_arsize,

    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M02_AXI ARBURST" *)
    output wire [2-1:0] m02_axi_arburst,

    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M02_AXI ARLOCK" *)
    output wire m02_axi_arlock,

    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M02_AXI ARCACHE" *)
    output wire [4-1:0] m02_axi_arcache,

    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M02_AXI ARPROT" *)
    output wire [3-1:0] m02_axi_arprot,

    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M02_AXI ARQOS" *)
    output wire [4-1:0] m02_axi_arqos,

    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M02_AXI ARVALID" *)
    output wire m02_axi_arvalid,

    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M02_AXI ARREADY" *)
    input  wire m02_axi_arready,

    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M02_AXI RID" *)
    input  wire [ID_WIDTH-1:0] m02_axi_rid,

    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M02_AXI RDATA" *)
    input  wire [DATA_WIDTH-1:0] m02_axi_rdata,

    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M02_AXI RRESP" *)
    input  wire [2-1:0] m02_axi_rresp,

    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M02_AXI RLAST" *)
    input  wire m02_axi_rlast,

    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M02_AXI RVALID" *)
    input  wire m02_axi_rvalid,

    (* X_INTERFACE_INFO = "xilinx.com:interface:aximm:1.0 M02_AXI RREADY" *)
    output wire m02_axi_rready
);

    axi_controller_unit #(
        .NUM_CACHE  (NUM_CACHE),
        .ADDR_WIDTH (ADDR_WIDTH),
        .DATA_WIDTH (DATA_WIDTH),
        .ID_WIDTH   (ID_WIDTH),
        .NUM_MASTER (3),
        .NUM_SLAVE  (3),
        .STRB_WIDTH (STRB_WIDTH),
        .BASE_ADDR  (BASE_ADDR),
        .END_ADDR   (END_ADDR)
    ) u_controller (
        .ACLK    (ACLK),
        .ARESETn (ARESETn),
        .s_axi_awid ({s02_axi_awid, s01_axi_awid, s00_axi_awid}),
        .s_axi_awaddr ({s02_axi_awaddr, s01_axi_awaddr, s00_axi_awaddr}),
        .s_axi_awlen ({s02_axi_awlen, s01_axi_awlen, s00_axi_awlen}),
        .s_axi_awsize ({s02_axi_awsize, s01_axi_awsize, s00_axi_awsize}),
        .s_axi_awburst ({s02_axi_awburst, s01_axi_awburst, s00_axi_awburst}),
        .s_axi_awlock ({s02_axi_awlock, s01_axi_awlock, s00_axi_awlock}),
        .s_axi_awcache ({s02_axi_awcache, s01_axi_awcache, s00_axi_awcache}),
        .s_axi_awprot ({s02_axi_awprot, s01_axi_awprot, s00_axi_awprot}),
        .s_axi_awqos ({s02_axi_awqos, s01_axi_awqos, s00_axi_awqos}),
        .s_axi_awvalid ({s02_axi_awvalid, s01_axi_awvalid, s00_axi_awvalid}),
        .s_axi_awready ({s02_axi_awready, s01_axi_awready, s00_axi_awready}),
        .s_axi_wdata ({s02_axi_wdata, s01_axi_wdata, s00_axi_wdata}),
        .s_axi_wstrb ({s02_axi_wstrb, s01_axi_wstrb, s00_axi_wstrb}),
        .s_axi_wlast ({s02_axi_wlast, s01_axi_wlast, s00_axi_wlast}),
        .s_axi_wvalid ({s02_axi_wvalid, s01_axi_wvalid, s00_axi_wvalid}),
        .s_axi_wready ({s02_axi_wready, s01_axi_wready, s00_axi_wready}),
        .s_axi_bid ({s02_axi_bid, s01_axi_bid, s00_axi_bid}),
        .s_axi_bresp ({s02_axi_bresp, s01_axi_bresp, s00_axi_bresp}),
        .s_axi_bvalid ({s02_axi_bvalid, s01_axi_bvalid, s00_axi_bvalid}),
        .s_axi_bready ({s02_axi_bready, s01_axi_bready, s00_axi_bready}),
        .s_axi_arid ({s02_axi_arid, s01_axi_arid, s00_axi_arid}),
        .s_axi_araddr ({s02_axi_araddr, s01_axi_araddr, s00_axi_araddr}),
        .s_axi_arlen ({s02_axi_arlen, s01_axi_arlen, s00_axi_arlen}),
        .s_axi_arsize ({s02_axi_arsize, s01_axi_arsize, s00_axi_arsize}),
        .s_axi_arburst ({s02_axi_arburst, s01_axi_arburst, s00_axi_arburst}),
        .s_axi_arlock ({s02_axi_arlock, s01_axi_arlock, s00_axi_arlock}),
        .s_axi_arcache ({s02_axi_arcache, s01_axi_arcache, s00_axi_arcache}),
        .s_axi_arprot ({s02_axi_arprot, s01_axi_arprot, s00_axi_arprot}),
        .s_axi_arqos ({s02_axi_arqos, s01_axi_arqos, s00_axi_arqos}),
        .s_axi_arvalid ({s02_axi_arvalid, s01_axi_arvalid, s00_axi_arvalid}),
        .s_axi_arready ({s02_axi_arready, s01_axi_arready, s00_axi_arready}),
        .s_axi_rid ({s02_axi_rid, s01_axi_rid, s00_axi_rid}),
        .s_axi_rdata ({s02_axi_rdata, s01_axi_rdata, s00_axi_rdata}),
        .s_axi_rresp ({s02_axi_rresp, s01_axi_rresp, s00_axi_rresp}),
        .s_axi_rlast ({s02_axi_rlast, s01_axi_rlast, s00_axi_rlast}),
        .s_axi_rvalid ({s02_axi_rvalid, s01_axi_rvalid, s00_axi_rvalid}),
        .s_axi_rready ({s02_axi_rready, s01_axi_rready, s00_axi_rready}),
        .m_axi_awid ({m02_axi_awid, m01_axi_awid, m00_axi_awid}),
        .m_axi_awaddr ({m02_axi_awaddr, m01_axi_awaddr, m00_axi_awaddr}),
        .m_axi_awlen ({m02_axi_awlen, m01_axi_awlen, m00_axi_awlen}),
        .m_axi_awsize ({m02_axi_awsize, m01_axi_awsize, m00_axi_awsize}),
        .m_axi_awburst ({m02_axi_awburst, m01_axi_awburst, m00_axi_awburst}),
        .m_axi_awlock ({m02_axi_awlock, m01_axi_awlock, m00_axi_awlock}),
        .m_axi_awcache ({m02_axi_awcache, m01_axi_awcache, m00_axi_awcache}),
        .m_axi_awprot ({m02_axi_awprot, m01_axi_awprot, m00_axi_awprot}),
        .m_axi_awqos ({m02_axi_awqos, m01_axi_awqos, m00_axi_awqos}),
        .m_axi_awvalid ({m02_axi_awvalid, m01_axi_awvalid, m00_axi_awvalid}),
        .m_axi_awready ({m02_axi_awready, m01_axi_awready, m00_axi_awready}),
        .m_axi_wdata ({m02_axi_wdata, m01_axi_wdata, m00_axi_wdata}),
        .m_axi_wstrb ({m02_axi_wstrb, m01_axi_wstrb, m00_axi_wstrb}),
        .m_axi_wlast ({m02_axi_wlast, m01_axi_wlast, m00_axi_wlast}),
        .m_axi_wvalid ({m02_axi_wvalid, m01_axi_wvalid, m00_axi_wvalid}),
        .m_axi_wready ({m02_axi_wready, m01_axi_wready, m00_axi_wready}),
        .m_axi_bid ({m02_axi_bid, m01_axi_bid, m00_axi_bid}),
        .m_axi_bresp ({m02_axi_bresp, m01_axi_bresp, m00_axi_bresp}),
        .m_axi_bvalid ({m02_axi_bvalid, m01_axi_bvalid, m00_axi_bvalid}),
        .m_axi_bready ({m02_axi_bready, m01_axi_bready, m00_axi_bready}),
        .m_axi_arid ({m02_axi_arid, m01_axi_arid, m00_axi_arid}),
        .m_axi_araddr ({m02_axi_araddr, m01_axi_araddr, m00_axi_araddr}),
        .m_axi_arlen ({m02_axi_arlen, m01_axi_arlen, m00_axi_arlen}),
        .m_axi_arsize ({m02_axi_arsize, m01_axi_arsize, m00_axi_arsize}),
        .m_axi_arburst ({m02_axi_arburst, m01_axi_arburst, m00_axi_arburst}),
        .m_axi_arlock ({m02_axi_arlock, m01_axi_arlock, m00_axi_arlock}),
        .m_axi_arcache ({m02_axi_arcache, m01_axi_arcache, m00_axi_arcache}),
        .m_axi_arprot ({m02_axi_arprot, m01_axi_arprot, m00_axi_arprot}),
        .m_axi_arqos ({m02_axi_arqos, m01_axi_arqos, m00_axi_arqos}),
        .m_axi_arvalid ({m02_axi_arvalid, m01_axi_arvalid, m00_axi_arvalid}),
        .m_axi_arready ({m02_axi_arready, m01_axi_arready, m00_axi_arready}),
        .m_axi_rid ({m02_axi_rid, m01_axi_rid, m00_axi_rid}),
        .m_axi_rdata ({m02_axi_rdata, m01_axi_rdata, m00_axi_rdata}),
        .m_axi_rresp ({m02_axi_rresp, m01_axi_rresp, m00_axi_rresp}),
        .m_axi_rlast ({m02_axi_rlast, m01_axi_rlast, m00_axi_rlast}),
        .m_axi_rvalid ({m02_axi_rvalid, m01_axi_rvalid, m00_axi_rvalid}),
        .m_axi_rready ({m02_axi_rready, m01_axi_rready, m00_axi_rready})
    );

endmodule

