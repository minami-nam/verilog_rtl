module axi_controller_unit #(
    parameter int NUM_CACHE = 16,
    parameter int ADDR_WIDTH = 32,
    parameter int DATA_WIDTH = 32,
    parameter int ID_WIDTH   = 4,
    parameter int NUM_MASTER = 3,
    parameter int NUM_SLAVE  = 3,
    parameter int STRB_WIDTH = DATA_WIDTH / 8,
    parameter logic [NUM_SLAVE*ADDR_WIDTH-1:0] BASE_ADDR = {
        ADDR_WIDTH'(32'h0000_0000),
        ADDR_WIDTH'(32'h4000_0000),
        ADDR_WIDTH'(32'hA000_0000)
    },
    parameter logic [NUM_SLAVE*ADDR_WIDTH-1:0] END_ADDR = {
        ADDR_WIDTH'(32'h3FFF_FFFF),
        ADDR_WIDTH'(32'h9FFF_FFFF),
        ADDR_WIDTH'(32'hFFFF_FFFF)
    }
) (
    input  wire ACLK,
    input  wire ARESETn,

    // AXI4 full slave-side ports: connected to external masters.
    input  wire [NUM_MASTER*ID_WIDTH-1:0]      s_axi_awid,
    input  wire [NUM_MASTER*ADDR_WIDTH-1:0]    s_axi_awaddr,
    input  wire [NUM_MASTER*8-1:0]             s_axi_awlen,
    input  wire [NUM_MASTER*3-1:0]             s_axi_awsize,
    input  wire [NUM_MASTER*2-1:0]             s_axi_awburst,
    input  wire [NUM_MASTER-1:0]               s_axi_awlock,
    input  wire [NUM_MASTER*4-1:0]             s_axi_awcache,
    input  wire [NUM_MASTER*3-1:0]             s_axi_awprot,
    input  wire [NUM_MASTER*4-1:0]             s_axi_awqos,
    input  wire [NUM_MASTER-1:0]               s_axi_awvalid,
    output wire [NUM_MASTER-1:0]               s_axi_awready,

    input  wire [NUM_MASTER*DATA_WIDTH-1:0]    s_axi_wdata,
    input  wire [NUM_MASTER*STRB_WIDTH-1:0]    s_axi_wstrb,
    input  wire [NUM_MASTER-1:0]               s_axi_wlast,
    input  wire [NUM_MASTER-1:0]               s_axi_wvalid,
    output wire [NUM_MASTER-1:0]               s_axi_wready,

    output wire [NUM_MASTER*ID_WIDTH-1:0]      s_axi_bid,
    output wire [NUM_MASTER*2-1:0]             s_axi_bresp,
    output wire [NUM_MASTER-1:0]               s_axi_bvalid,
    input  wire [NUM_MASTER-1:0]               s_axi_bready,

    input  wire [NUM_MASTER*ID_WIDTH-1:0]      s_axi_arid,
    input  wire [NUM_MASTER*ADDR_WIDTH-1:0]    s_axi_araddr,
    input  wire [NUM_MASTER*8-1:0]             s_axi_arlen,
    input  wire [NUM_MASTER*3-1:0]             s_axi_arsize,
    input  wire [NUM_MASTER*2-1:0]             s_axi_arburst,
    input  wire [NUM_MASTER-1:0]               s_axi_arlock,
    input  wire [NUM_MASTER*4-1:0]             s_axi_arcache,
    input  wire [NUM_MASTER*3-1:0]             s_axi_arprot,
    input  wire [NUM_MASTER*4-1:0]             s_axi_arqos,
    input  wire [NUM_MASTER-1:0]               s_axi_arvalid,
    output wire [NUM_MASTER-1:0]               s_axi_arready,

    output wire [NUM_MASTER*ID_WIDTH-1:0]      s_axi_rid,
    output wire [NUM_MASTER*DATA_WIDTH-1:0]    s_axi_rdata,
    output wire [NUM_MASTER*2-1:0]             s_axi_rresp,
    output wire [NUM_MASTER-1:0]               s_axi_rlast,
    output wire [NUM_MASTER-1:0]               s_axi_rvalid,
    input  wire [NUM_MASTER-1:0]               s_axi_rready,

    // AXI4 full master-side ports: connected to external slaves.
    output wire [NUM_SLAVE*ID_WIDTH-1:0]       m_axi_awid,
    output wire [NUM_SLAVE*ADDR_WIDTH-1:0]     m_axi_awaddr,
    output wire [NUM_SLAVE*8-1:0]              m_axi_awlen,
    output wire [NUM_SLAVE*3-1:0]              m_axi_awsize,
    output wire [NUM_SLAVE*2-1:0]              m_axi_awburst,
    output wire [NUM_SLAVE-1:0]                m_axi_awlock,
    output wire [NUM_SLAVE*4-1:0]              m_axi_awcache,
    output wire [NUM_SLAVE*3-1:0]              m_axi_awprot,
    output wire [NUM_SLAVE*4-1:0]              m_axi_awqos,
    output wire [NUM_SLAVE-1:0]                m_axi_awvalid,
    input  wire [NUM_SLAVE-1:0]                m_axi_awready,

    output wire [NUM_SLAVE*DATA_WIDTH-1:0]     m_axi_wdata,
    output wire [NUM_SLAVE*STRB_WIDTH-1:0]     m_axi_wstrb,
    output wire [NUM_SLAVE-1:0]                m_axi_wlast,
    output wire [NUM_SLAVE-1:0]                m_axi_wvalid,
    input  wire [NUM_SLAVE-1:0]                m_axi_wready,

    input  wire [NUM_SLAVE*ID_WIDTH-1:0]       m_axi_bid,
    input  wire [NUM_SLAVE*2-1:0]              m_axi_bresp,
    input  wire [NUM_SLAVE-1:0]                m_axi_bvalid,
    output wire [NUM_SLAVE-1:0]                m_axi_bready,

    output wire [NUM_SLAVE*ID_WIDTH-1:0]       m_axi_arid,
    output wire [NUM_SLAVE*ADDR_WIDTH-1:0]     m_axi_araddr,
    output wire [NUM_SLAVE*8-1:0]              m_axi_arlen,
    output wire [NUM_SLAVE*3-1:0]              m_axi_arsize,
    output wire [NUM_SLAVE*2-1:0]              m_axi_arburst,
    output wire [NUM_SLAVE-1:0]                m_axi_arlock,
    output wire [NUM_SLAVE*4-1:0]              m_axi_arcache,
    output wire [NUM_SLAVE*3-1:0]              m_axi_arprot,
    output wire [NUM_SLAVE*4-1:0]              m_axi_arqos,
    output wire [NUM_SLAVE-1:0]                m_axi_arvalid,
    input  wire [NUM_SLAVE-1:0]                m_axi_arready,

    input  wire [NUM_SLAVE*ID_WIDTH-1:0]       m_axi_rid,
    input  wire [NUM_SLAVE*DATA_WIDTH-1:0]     m_axi_rdata,
    input  wire [NUM_SLAVE*2-1:0]              m_axi_rresp,
    input  wire [NUM_SLAVE-1:0]                m_axi_rlast,
    input  wire [NUM_SLAVE-1:0]                m_axi_rvalid,
    output wire [NUM_SLAVE-1:0]                m_axi_rready
);

    // AXI payload widths. VALID/READY are FIFO handshakes and are not stored.
    // localparam integer AW_PAYLOAD_WIDTH = ID_WIDTH + ADDR_WIDTH + 8 + 3 + 2 + 1 + 4 + 3 + 4;
    // localparam integer W_PAYLOAD_WIDTH  = DATA_WIDTH + STRB_WIDTH + 1;
    // localparam integer B_PAYLOAD_WIDTH  = ID_WIDTH + 2;
    // localparam integer AR_PAYLOAD_WIDTH = ID_WIDTH + ADDR_WIDTH + 8 + 3 + 2 + 1 + 4 + 3 + 4;
    // localparam integer R_PAYLOAD_WIDTH  = ID_WIDTH + DATA_WIDTH + 2 + 1;
    localparam integer MASTER_WIDTH = (NUM_MASTER <= 1) ? 1 : $clog2(NUM_MASTER);
    localparam integer SLAVE_WIDTH  = (NUM_SLAVE <= 1) ? 1 : $clog2(NUM_SLAVE);

    // 수정 1. AXI Payload Width 부분을 typedef struct packed로 선언하여 하나의 struct로 취급할 것.
    // 해당 struct들은 아래의 FIFO 포트 연결 시 사용할 것.
    typedef struct packed {
        logic [ID_WIDTH-1:0] id;
        logic [ADDR_WIDTH-1:0] addr;
        logic [7:0]            len;
        logic [2:0]            size;
        logic [1:0]            burst;
        logic                  lock;
        logic [3:0]            cache;
        logic [2:0]            prot;
        logic [3:0]            qos;   
    } axi_addr_payload_t;


    typedef struct packed {
        logic [DATA_WIDTH-1:0] data;
        logic [STRB_WIDTH-1:0] strb;
        logic                  last;
    } axi_w_payload_t;

    typedef struct packed {
        logic [ID_WIDTH-1:0] id;
        logic [1:0]          resp;
    } axi_b_payload_t;

    typedef struct packed {
        logic [ID_WIDTH-1:0]   id;
        logic [DATA_WIDTH-1:0] data;
        logic [1:0]            resp;
        logic                  last;
    } axi_r_payload_t;

    // 이후 Payload의 폭을 계산함.
    localparam int unsigned AW_PAYLOAD_WIDTH = $bits(axi_addr_payload_t);
    localparam int unsigned AR_PAYLOAD_WIDTH = $bits(axi_addr_payload_t);
    localparam int unsigned R_PAYLOAD_WIDTH = $bits(axi_r_payload_t);
    localparam int unsigned W_PAYLOAD_WIDTH = $bits(axi_w_payload_t);
    localparam int unsigned B_PAYLOAD_WIDTH = $bits(axi_b_payload_t);



    // Cached outputs toward the future arbitration/routing logic.
    // Payload order follows the order used in each concatenation below (MSB to LSB).
    wire [NUM_MASTER*ID_WIDTH-1:0]   s_aw_cached_id;
    wire [NUM_MASTER*ADDR_WIDTH-1:0] s_aw_cached_addr;
    wire [NUM_MASTER*8-1:0]          s_aw_cached_len;
    wire [NUM_MASTER*3-1:0]          s_aw_cached_size;
    wire [NUM_MASTER*2-1:0]          s_aw_cached_burst;
    wire [NUM_MASTER-1:0]            s_aw_cached_lock;
    wire [NUM_MASTER*4-1:0]          s_aw_cached_cache;
    wire [NUM_MASTER*3-1:0]          s_aw_cached_prot;
    wire [NUM_MASTER*4-1:0]          s_aw_cached_qos;

    wire [NUM_MASTER*W_PAYLOAD_WIDTH-1:0] s_w_cached_data;

    wire [NUM_MASTER*ID_WIDTH-1:0]   s_ar_cached_id;
    wire [NUM_MASTER*ADDR_WIDTH-1:0] s_ar_cached_addr;
    wire [NUM_MASTER*8-1:0]          s_ar_cached_len;
    wire [NUM_MASTER*3-1:0]          s_ar_cached_size;
    wire [NUM_MASTER*2-1:0]          s_ar_cached_burst;
    wire [NUM_MASTER-1:0]            s_ar_cached_lock;
    wire [NUM_MASTER*4-1:0]          s_ar_cached_cache;
    wire [NUM_MASTER*3-1:0]          s_ar_cached_prot;
    wire [NUM_MASTER*4-1:0]          s_ar_cached_qos;
    wire [NUM_MASTER-1:0]                  s_aw_cached_valid;
    wire [NUM_MASTER-1:0]                  s_w_cached_valid;
    wire [NUM_MASTER-1:0]                  s_ar_cached_valid;

    wire [NUM_SLAVE*B_PAYLOAD_WIDTH-1:0]   m_b_cached_data;
    wire [NUM_SLAVE*R_PAYLOAD_WIDTH-1:0]   m_r_cached_data;
    wire [NUM_SLAVE-1:0]                   m_b_cached_valid;
    wire [NUM_SLAVE-1:0]                   m_r_cached_valid;

    // AW/AR are consumed by the address decoder. W remains queued until
    // the write transaction tracker is connected.
    wire [NUM_MASTER-1:0] s_aw_cached_ready;
    wire [NUM_MASTER-1:0] s_w_cached_ready;
    wire [NUM_MASTER-1:0] s_ar_cached_ready;
    wire [NUM_SLAVE-1:0]  m_b_cached_ready;
    wire [NUM_SLAVE-1:0]  m_r_cached_ready;

    wire [NUM_MASTER*SLAVE_WIDTH-1:0]  s_aw_target;
    wire [NUM_MASTER*SLAVE_WIDTH-1:0]  s_ar_target;
    wire [NUM_MASTER*AW_PAYLOAD_WIDTH-1:0] aw_scheduler_input;
    wire [NUM_MASTER*AR_PAYLOAD_WIDTH-1:0] ar_scheduler_input;
    wire [NUM_SLAVE*AW_PAYLOAD_WIDTH-1:0]  aw_scheduler_output;
    wire [NUM_SLAVE*AR_PAYLOAD_WIDTH-1:0]  ar_scheduler_output;
    wire [NUM_SLAVE*MASTER_WIDTH-1:0]      aw_scheduled_master;
    wire [NUM_SLAVE*MASTER_WIDTH-1:0]      ar_scheduled_master;

    wire [NUM_SLAVE-1:0] aw_scheduler_valid;
    wire [NUM_SLAVE-1:0] aw_scheduler_ready;
    wire [NUM_SLAVE-1:0] ar_scheduler_valid;
    wire [NUM_SLAVE-1:0] ar_scheduler_ready;

    wire [NUM_SLAVE-1:0] tracker_aw_valid;
    wire [NUM_SLAVE-1:0] tracker_aw_ready;
    wire [NUM_SLAVE-1:0] tracker_aw_drop;
    wire [NUM_SLAVE*W_PAYLOAD_WIDTH-1:0] tracker_w_payload;
    wire [NUM_SLAVE-1:0] tracker_w_valid;
    wire [NUM_SLAVE*MASTER_WIDTH-1:0] local_b_master;
    wire [NUM_SLAVE*ID_WIDTH-1:0] local_b_id;
    wire [NUM_SLAVE*2-1:0] local_b_resp;
    wire [NUM_SLAVE-1:0] local_b_valid;
    wire [NUM_SLAVE-1:0] local_b_ready;
    wire [NUM_SLAVE*MASTER_WIDTH-1:0] write_commit_master;
    wire [NUM_SLAVE*ADDR_WIDTH-1:0] write_commit_addr;
    wire [NUM_SLAVE*8-1:0] write_commit_len;
    wire [NUM_SLAVE*3-1:0] write_commit_size;
    wire [NUM_SLAVE*2-1:0] write_commit_burst;
    wire [NUM_SLAVE-1:0] write_commit_valid;
    wire [NUM_SLAVE-1:0] w_early_last_error;
    wire [NUM_SLAVE-1:0] w_missing_last_error;

    wire [NUM_SLAVE-1:0] b_route_valid;
    wire [NUM_SLAVE-1:0] b_route_ready;
    wire [NUM_SLAVE-1:0] b_route_exclusive;
    wire [NUM_SLAVE-1:0] r_route_valid;
    wire [NUM_SLAVE-1:0] r_route_ready;
    wire [NUM_SLAVE-1:0] r_route_exclusive;
    wire [NUM_SLAVE-1:0] write_response_valid;
    wire [NUM_SLAVE-1:0] write_response_success;

    wire [NUM_SLAVE*ID_WIDTH-1:0] cached_bid;
    wire [NUM_SLAVE*2-1:0] cached_bresp;
    wire [NUM_SLAVE*ID_WIDTH-1:0] cached_rid;
    wire [NUM_SLAVE*DATA_WIDTH-1:0] cached_rdata;
    wire [NUM_SLAVE*2-1:0] cached_rresp;
    wire [NUM_SLAVE-1:0] cached_rlast;

    wire [NUM_SLAVE-1:0] exclusive_check_valid;
    wire [NUM_SLAVE-1:0] exclusive_check_ready;
    wire [NUM_SLAVE-1:0] exclusive_result_valid;
    wire [NUM_SLAVE-1:0] exclusive_result_ready;
    wire [NUM_SLAVE-1:0] exclusive_success;
    wire [NUM_SLAVE-1:0] exclusive_reserve_valid;
    wire [NUM_SLAVE-1:0] aw_transaction_fire;
    wire [NUM_SLAVE-1:0] ar_transaction_fire;

    genvar master_index;
    generate
        for (master_index=0; master_index<NUM_MASTER; master_index=master_index+1) begin : gen_master_input_fifos
            wire axi_addr_payload_t aw_input_payload;
            wire axi_addr_payload_t aw_output_payload;
            wire axi_w_payload_t    w_input_payload;
            wire axi_w_payload_t    w_output_payload;
            wire axi_addr_payload_t ar_input_payload;
            wire axi_addr_payload_t ar_output_payload;

            assign aw_input_payload.id    = s_axi_awid[master_index*ID_WIDTH +: ID_WIDTH];
            assign aw_input_payload.addr  = s_axi_awaddr[master_index*ADDR_WIDTH +: ADDR_WIDTH];
            assign aw_input_payload.len   = s_axi_awlen[master_index*8 +: 8];
            assign aw_input_payload.size  = s_axi_awsize[master_index*3 +: 3];
            assign aw_input_payload.burst = s_axi_awburst[master_index*2 +: 2];
            assign aw_input_payload.lock  = s_axi_awlock[master_index];
            assign aw_input_payload.cache = s_axi_awcache[master_index*4 +: 4];
            assign aw_input_payload.prot  = s_axi_awprot[master_index*3 +: 3];
            assign aw_input_payload.qos   = s_axi_awqos[master_index*4 +: 4];

            assign s_aw_cached_id[master_index*ID_WIDTH +: ID_WIDTH] = aw_output_payload.id;
            assign s_aw_cached_addr[master_index*ADDR_WIDTH +: ADDR_WIDTH] = aw_output_payload.addr;
            assign s_aw_cached_len[master_index*8 +: 8] = aw_output_payload.len;
            assign s_aw_cached_size[master_index*3 +: 3] = aw_output_payload.size;
            assign s_aw_cached_burst[master_index*2 +: 2] = aw_output_payload.burst;
            assign s_aw_cached_lock[master_index] = aw_output_payload.lock;
            assign s_aw_cached_cache[master_index*4 +: 4] = aw_output_payload.cache;
            assign s_aw_cached_prot[master_index*3 +: 3] = aw_output_payload.prot;
            assign s_aw_cached_qos[master_index*4 +: 4] = aw_output_payload.qos;

            assign w_input_payload.data = s_axi_wdata[master_index*DATA_WIDTH +: DATA_WIDTH];
            assign w_input_payload.strb = s_axi_wstrb[master_index*STRB_WIDTH +: STRB_WIDTH];
            assign w_input_payload.last = s_axi_wlast[master_index];
            assign s_w_cached_data[master_index*W_PAYLOAD_WIDTH +: W_PAYLOAD_WIDTH] =
                w_output_payload;

            assign ar_input_payload.id    = s_axi_arid[master_index*ID_WIDTH +: ID_WIDTH];
            assign ar_input_payload.addr  = s_axi_araddr[master_index*ADDR_WIDTH +: ADDR_WIDTH];
            assign ar_input_payload.len   = s_axi_arlen[master_index*8 +: 8];
            assign ar_input_payload.size  = s_axi_arsize[master_index*3 +: 3];
            assign ar_input_payload.burst = s_axi_arburst[master_index*2 +: 2];
            assign ar_input_payload.lock  = s_axi_arlock[master_index];
            assign ar_input_payload.cache = s_axi_arcache[master_index*4 +: 4];
            assign ar_input_payload.prot  = s_axi_arprot[master_index*3 +: 3];
            assign ar_input_payload.qos   = s_axi_arqos[master_index*4 +: 4];

            assign s_ar_cached_id[master_index*ID_WIDTH +: ID_WIDTH] = ar_output_payload.id;
            assign s_ar_cached_addr[master_index*ADDR_WIDTH +: ADDR_WIDTH] = ar_output_payload.addr;
            assign s_ar_cached_len[master_index*8 +: 8] = ar_output_payload.len;
            assign s_ar_cached_size[master_index*3 +: 3] = ar_output_payload.size;
            assign s_ar_cached_burst[master_index*2 +: 2] = ar_output_payload.burst;
            assign s_ar_cached_lock[master_index] = ar_output_payload.lock;
            assign s_ar_cached_cache[master_index*4 +: 4] = ar_output_payload.cache;
            assign s_ar_cached_prot[master_index*3 +: 3] = ar_output_payload.prot;
            assign s_ar_cached_qos[master_index*4 +: 4] = ar_output_payload.qos;

            fifo_cache #(
                .WIDTH     (AW_PAYLOAD_WIDTH),
                .NUM_CACHE (NUM_CACHE)
            ) u_aw_fifo (
                .ACLK        (ACLK),
                .ARESETn     (ARESETn),
                .input_data  (aw_input_payload),
                .i_valid     (s_axi_awvalid[master_index]),
                .i_ready     (s_axi_awready[master_index]),
                .output_data (aw_output_payload),
                .o_ready     (s_aw_cached_ready[master_index]),
                .o_valid     (s_aw_cached_valid[master_index])
            );

            fifo_cache #(
                .WIDTH     (W_PAYLOAD_WIDTH),
                .NUM_CACHE (NUM_CACHE)
            ) u_w_fifo (
                .ACLK        (ACLK),
                .ARESETn     (ARESETn),
                .input_data  (w_input_payload),
                .i_valid     (s_axi_wvalid[master_index]),
                .i_ready     (s_axi_wready[master_index]),
                .output_data (w_output_payload),
                .o_ready     (s_w_cached_ready[master_index]),
                .o_valid     (s_w_cached_valid[master_index])
            );

            fifo_cache #(
                .WIDTH     (AR_PAYLOAD_WIDTH),
                .NUM_CACHE (NUM_CACHE)
            ) u_ar_fifo (
                .ACLK        (ACLK),
                .ARESETn     (ARESETn),
                .input_data  (ar_input_payload),
                .i_valid     (s_axi_arvalid[master_index]),
                .i_ready     (s_axi_arready[master_index]),
                .output_data (ar_output_payload),
                .o_ready     (s_ar_cached_ready[master_index]),
                .o_valid     (s_ar_cached_valid[master_index])
            );
        end
    endgenerate

    genvar slave_index;
    generate
        for (slave_index=0; slave_index<NUM_SLAVE; slave_index=slave_index+1) begin : gen_slave_input_fifos
            wire axi_b_payload_t b_input_payload;
            wire axi_b_payload_t b_output_payload;
            wire axi_r_payload_t r_input_payload;
            wire axi_r_payload_t r_output_payload;

            assign b_input_payload.id   = m_axi_bid[slave_index*ID_WIDTH +: ID_WIDTH];
            assign b_input_payload.resp = m_axi_bresp[slave_index*2 +: 2];
            assign cached_bid[slave_index*ID_WIDTH +: ID_WIDTH] = b_output_payload.id;
            assign cached_bresp[slave_index*2 +: 2] = b_output_payload.resp;

            assign r_input_payload.id   = m_axi_rid[slave_index*ID_WIDTH +: ID_WIDTH];
            assign r_input_payload.data = m_axi_rdata[slave_index*DATA_WIDTH +: DATA_WIDTH];
            assign r_input_payload.resp = m_axi_rresp[slave_index*2 +: 2];
            assign r_input_payload.last = m_axi_rlast[slave_index];
            assign cached_rid[slave_index*ID_WIDTH +: ID_WIDTH] = r_output_payload.id;
            assign cached_rdata[slave_index*DATA_WIDTH +: DATA_WIDTH] = r_output_payload.data;
            assign cached_rresp[slave_index*2 +: 2] = r_output_payload.resp;
            assign cached_rlast[slave_index] = r_output_payload.last;

            fifo_cache #(
                .WIDTH     (B_PAYLOAD_WIDTH),
                .NUM_CACHE (NUM_CACHE)
            ) u_b_fifo (
                .ACLK        (ACLK),
                .ARESETn     (ARESETn),
                .input_data  (b_input_payload),
                .i_valid     (m_axi_bvalid[slave_index]),
                .i_ready     (m_axi_bready[slave_index]),
                .output_data (b_output_payload),
                .o_ready     (m_b_cached_ready[slave_index]),
                .o_valid     (m_b_cached_valid[slave_index])
            );

            fifo_cache #(
                .WIDTH     (R_PAYLOAD_WIDTH),
                .NUM_CACHE (NUM_CACHE)
            ) u_r_fifo (
                .ACLK        (ACLK),
                .ARESETn     (ARESETn),
                .input_data  (r_input_payload),
                .i_valid     (m_axi_rvalid[slave_index]),
                .i_ready     (m_axi_rready[slave_index]),
                .output_data (r_output_payload),
                .o_ready     (m_r_cached_ready[slave_index]),
                .o_valid     (m_r_cached_valid[slave_index])
            );
        end
    endgenerate

    addr_decoder #(
        .ADDR_WIDTH  (ADDR_WIDTH),
        .NUM_MASTER  (NUM_MASTER),
        .NUM_SLAVE   (NUM_SLAVE),
        .SLAVE_WIDTH (SLAVE_WIDTH),
        .BASE_ADDR   (BASE_ADDR),
        .END_ADDR    (END_ADDR)
    ) u_addr_decoder (
        .s_axi_awaddr   (s_aw_cached_addr),
        .s_axi_araddr   (s_ar_cached_addr),
        .s_axi_awtarget (s_aw_target),
        .s_axi_artarget (s_ar_target)
    );

    genvar scheduler_master_index;
    generate
        for (scheduler_master_index=0; scheduler_master_index<NUM_MASTER;
             scheduler_master_index=scheduler_master_index+1) begin : gen_scheduler_input
            assign aw_scheduler_input[
                scheduler_master_index*AW_PAYLOAD_WIDTH +: AW_PAYLOAD_WIDTH] = {
                    s_aw_cached_id[scheduler_master_index*ID_WIDTH +: ID_WIDTH],
                    s_aw_cached_addr[scheduler_master_index*ADDR_WIDTH +: ADDR_WIDTH],
                    s_aw_cached_len[scheduler_master_index*8 +: 8],
                    s_aw_cached_size[scheduler_master_index*3 +: 3],
                    s_aw_cached_burst[scheduler_master_index*2 +: 2],
                    s_aw_cached_lock[scheduler_master_index],
                    s_aw_cached_cache[scheduler_master_index*4 +: 4],
                    s_aw_cached_prot[scheduler_master_index*3 +: 3],
                    s_aw_cached_qos[scheduler_master_index*4 +: 4]};

            assign ar_scheduler_input[
                scheduler_master_index*AR_PAYLOAD_WIDTH +: AR_PAYLOAD_WIDTH] = {
                    s_ar_cached_id[scheduler_master_index*ID_WIDTH +: ID_WIDTH],
                    s_ar_cached_addr[scheduler_master_index*ADDR_WIDTH +: ADDR_WIDTH],
                    s_ar_cached_len[scheduler_master_index*8 +: 8],
                    s_ar_cached_size[scheduler_master_index*3 +: 3],
                    s_ar_cached_burst[scheduler_master_index*2 +: 2],
                    s_ar_cached_lock[scheduler_master_index],
                    s_ar_cached_cache[scheduler_master_index*4 +: 4],
                    s_ar_cached_prot[scheduler_master_index*3 +: 3],
                    s_ar_cached_qos[scheduler_master_index*4 +: 4]};
        end
    endgenerate

    genvar scheduler_slave_index;
    generate
        for (scheduler_slave_index=0; scheduler_slave_index<NUM_SLAVE;
             scheduler_slave_index=scheduler_slave_index+1) begin : gen_scheduler_output
            assign {m_axi_awid[scheduler_slave_index*ID_WIDTH +: ID_WIDTH],
                    m_axi_awaddr[scheduler_slave_index*ADDR_WIDTH +: ADDR_WIDTH],
                    m_axi_awlen[scheduler_slave_index*8 +: 8],
                    m_axi_awsize[scheduler_slave_index*3 +: 3],
                    m_axi_awburst[scheduler_slave_index*2 +: 2],
                    m_axi_awlock[scheduler_slave_index],
                    m_axi_awcache[scheduler_slave_index*4 +: 4],
                    m_axi_awprot[scheduler_slave_index*3 +: 3],
                    m_axi_awqos[scheduler_slave_index*4 +: 4]} =
                aw_scheduler_output[
                    scheduler_slave_index*AW_PAYLOAD_WIDTH +: AW_PAYLOAD_WIDTH];

            assign {m_axi_arid[scheduler_slave_index*ID_WIDTH +: ID_WIDTH],
                    m_axi_araddr[scheduler_slave_index*ADDR_WIDTH +: ADDR_WIDTH],
                    m_axi_arlen[scheduler_slave_index*8 +: 8],
                    m_axi_arsize[scheduler_slave_index*3 +: 3],
                    m_axi_arburst[scheduler_slave_index*2 +: 2],
                    m_axi_arlock[scheduler_slave_index],
                    m_axi_arcache[scheduler_slave_index*4 +: 4],
                    m_axi_arprot[scheduler_slave_index*3 +: 3],
                    m_axi_arqos[scheduler_slave_index*4 +: 4]} =
                ar_scheduler_output[
                    scheduler_slave_index*AR_PAYLOAD_WIDTH +: AR_PAYLOAD_WIDTH];
        end
    endgenerate

    axi_aw_scheduler #(
        .NUM_MASTER    (NUM_MASTER),
        .NUM_SLAVE     (NUM_SLAVE),
        .PAYLOAD_WIDTH (AW_PAYLOAD_WIDTH),
        .QOS_WIDTH     (4),
        .MASTER_WIDTH  (MASTER_WIDTH),
        .SLAVE_WIDTH   (SLAVE_WIDTH)
    ) u_aw_scheduler (
        .ACLK               (ACLK),
        .ARESETn            (ARESETn),
        .s_aw_payload       (aw_scheduler_input),
        .s_aw_target        (s_aw_target),
        .s_aw_qos           (s_aw_cached_qos),
        .s_aw_len           (s_aw_cached_len),
        .s_aw_valid         (s_aw_cached_valid),
        .s_aw_ready         (s_aw_cached_ready),
        .m_aw_payload       (aw_scheduler_output),
        .m_aw_source_master (aw_scheduled_master),
        .m_aw_valid         (aw_scheduler_valid),
        .m_aw_ready         (aw_scheduler_ready)
    );

    axi_ar_scheduler #(
        .NUM_MASTER    (NUM_MASTER),
        .NUM_SLAVE     (NUM_SLAVE),
        .PAYLOAD_WIDTH (AR_PAYLOAD_WIDTH),
        .QOS_WIDTH     (4),
        .MASTER_WIDTH  (MASTER_WIDTH),
        .SLAVE_WIDTH   (SLAVE_WIDTH)
    ) u_ar_scheduler (
        .ACLK               (ACLK),
        .ARESETn            (ARESETn),
        .s_ar_payload       (ar_scheduler_input),
        .s_ar_target        (s_ar_target),
        .s_ar_qos           (s_ar_cached_qos),
        .s_ar_len           (s_ar_cached_len),
        .s_ar_valid         (s_ar_cached_valid),
        .s_ar_ready         (s_ar_cached_ready),
        .m_ar_payload       (ar_scheduler_output),
        .m_ar_source_master (ar_scheduled_master),
        .m_ar_valid         (ar_scheduler_valid),
        .m_ar_ready         (ar_scheduler_ready)
    );


    // Atomic AW issue: a forwarded AW is accepted only when both the write
    // tracker and B-response route slot are available. Failed exclusive writes
    // are consumed internally and marked as drop transactions.
    genvar integration_slave_index;
    generate
        for (integration_slave_index=0; integration_slave_index<NUM_SLAVE;
             integration_slave_index=integration_slave_index+1) begin : gen_channel_integration
            wire aw_is_exclusive;
            wire aw_forward;

            assign aw_is_exclusive = m_axi_awlock[integration_slave_index];
            assign exclusive_check_valid[integration_slave_index] =
                aw_scheduler_valid[integration_slave_index] && aw_is_exclusive;
            assign aw_forward = !aw_is_exclusive ||
                (exclusive_result_valid[integration_slave_index] &&
                 exclusive_success[integration_slave_index]);
            assign tracker_aw_drop[integration_slave_index] =
                aw_is_exclusive && exclusive_result_valid[integration_slave_index] &&
                !exclusive_success[integration_slave_index];

            assign m_axi_awvalid[integration_slave_index] =
                aw_scheduler_valid[integration_slave_index] && aw_forward &&
                tracker_aw_ready[integration_slave_index] &&
                b_route_ready[integration_slave_index];

            assign aw_scheduler_ready[integration_slave_index] = aw_is_exclusive ?
                (exclusive_result_valid[integration_slave_index] &&
                    (exclusive_success[integration_slave_index] ?
                        (m_axi_awready[integration_slave_index] &&
                         tracker_aw_ready[integration_slave_index] &&
                         b_route_ready[integration_slave_index]) :
                        tracker_aw_ready[integration_slave_index])) :
                (m_axi_awready[integration_slave_index] &&
                 tracker_aw_ready[integration_slave_index] &&
                 b_route_ready[integration_slave_index]);

            assign aw_transaction_fire[integration_slave_index] =
                aw_scheduler_valid[integration_slave_index] &&
                aw_scheduler_ready[integration_slave_index];
            assign tracker_aw_valid[integration_slave_index] =
                aw_transaction_fire[integration_slave_index];
            assign b_route_valid[integration_slave_index] =
                aw_transaction_fire[integration_slave_index] && aw_forward;
            assign b_route_exclusive[integration_slave_index] =
                aw_is_exclusive && exclusive_success[integration_slave_index];
            assign exclusive_result_ready[integration_slave_index] =
                aw_transaction_fire[integration_slave_index] && aw_is_exclusive;

            assign m_axi_arvalid[integration_slave_index] =
                ar_scheduler_valid[integration_slave_index] &&
                r_route_ready[integration_slave_index];
            assign ar_scheduler_ready[integration_slave_index] =
                m_axi_arready[integration_slave_index] &&
                r_route_ready[integration_slave_index];
            assign ar_transaction_fire[integration_slave_index] =
                ar_scheduler_valid[integration_slave_index] &&
                ar_scheduler_ready[integration_slave_index];
            assign r_route_valid[integration_slave_index] =
                ar_transaction_fire[integration_slave_index];
            assign r_route_exclusive[integration_slave_index] =
                m_axi_arlock[integration_slave_index];
            assign exclusive_reserve_valid[integration_slave_index] =
                ar_transaction_fire[integration_slave_index] &&
                m_axi_arlock[integration_slave_index];

            assign {m_axi_wdata[integration_slave_index*DATA_WIDTH +: DATA_WIDTH],
                    m_axi_wstrb[integration_slave_index*STRB_WIDTH +: STRB_WIDTH],
                    m_axi_wlast[integration_slave_index]} =
                tracker_w_payload[
                    integration_slave_index*W_PAYLOAD_WIDTH +: W_PAYLOAD_WIDTH];
        end
    endgenerate

    write_transaction_tracker #(
        .NUM_MASTER      (NUM_MASTER),
        .NUM_SLAVE       (NUM_SLAVE),
        .ID_WIDTH        (ID_WIDTH),
        .ADDR_WIDTH      (ADDR_WIDTH),
        .LEN_WIDTH       (8),
        .SIZE_WIDTH      (3),
        .BURST_WIDTH     (2),
        .W_PAYLOAD_WIDTH (W_PAYLOAD_WIDTH),
        .RESP_WIDTH      (2),
        .MASTER_WIDTH    (MASTER_WIDTH)
    ) u_write_transaction_tracker (
        .ACLK                (ACLK),
        .ARESETn             (ARESETn),
        .s_aw_source_master  (aw_scheduled_master),
        .s_aw_id             (m_axi_awid),
        .s_aw_addr           (m_axi_awaddr),
        .s_aw_len            (m_axi_awlen),
        .s_aw_size           (m_axi_awsize),
        .s_aw_burst          (m_axi_awburst),
        .s_aw_drop           (tracker_aw_drop),
        .s_aw_valid          (tracker_aw_valid),
        .s_aw_ready          (tracker_aw_ready),
        .s_w_payload         (s_w_cached_data),
        .s_w_valid           (s_w_cached_valid),
        .s_w_ready           (s_w_cached_ready),
        .m_w_payload         (tracker_w_payload),
        .m_w_valid           (m_axi_wvalid),
        .m_w_ready           (m_axi_wready),
        .write_response_valid  (write_response_valid),
        .write_response_success(write_response_success),
        .local_b_master      (local_b_master),
        .local_b_id          (local_b_id),
        .local_b_resp        (local_b_resp),
        .local_b_valid       (local_b_valid),
        .local_b_ready       (local_b_ready),
        .write_commit_master (write_commit_master),
        .write_commit_addr   (write_commit_addr),
        .write_commit_len    (write_commit_len),
        .write_commit_size   (write_commit_size),
        .write_commit_burst  (write_commit_burst),
        .write_commit_valid  (write_commit_valid),
        .w_early_last_error  (w_early_last_error),
        .w_missing_last_error(w_missing_last_error)
    );

    exclusive_monitor #(
        .NUM_MASTER   (NUM_MASTER),
        .NUM_SLAVE    (NUM_SLAVE),
        .ADDR_WIDTH   (ADDR_WIDTH),
        .ID_WIDTH     (ID_WIDTH),
        .LEN_WIDTH    (8),
        .SIZE_WIDTH   (3),
        .BURST_WIDTH  (2),
        .MASTER_WIDTH (MASTER_WIDTH)
    ) u_exclusive_monitor (
        .ACLK               (ACLK),
        .ARESETn            (ARESETn),
        .reserve_master     (ar_scheduled_master),
        .reserve_id         (m_axi_arid),
        .reserve_addr       (m_axi_araddr),
        .reserve_len        (m_axi_arlen),
        .reserve_size       (m_axi_arsize),
        .reserve_burst      (m_axi_arburst),
        .reserve_valid      (exclusive_reserve_valid),
        .check_master       (aw_scheduled_master),
        .check_id           (m_axi_awid),
        .check_addr         (m_axi_awaddr),
        .check_len          (m_axi_awlen),
        .check_size         (m_axi_awsize),
        .check_burst        (m_axi_awburst),
        .check_valid        (exclusive_check_valid),
        .check_ready        (exclusive_check_ready),
        .result_valid       (exclusive_result_valid),
        .exclusive_success  (exclusive_success),
        .result_ready       (exclusive_result_ready),
        .write_commit_addr  (write_commit_addr),
        .write_commit_len   (write_commit_len),
        .write_commit_size  (write_commit_size),
        .write_commit_burst (write_commit_burst),
        .write_commit_valid (write_commit_valid)
    );

    axi_response_router #(
        .NUM_MASTER   (NUM_MASTER),
        .NUM_SLAVE    (NUM_SLAVE),
        .ID_WIDTH     (ID_WIDTH),
        .DATA_WIDTH   (DATA_WIDTH),
        .RESP_WIDTH   (2),
        .MASTER_WIDTH (MASTER_WIDTH),
        .SLAVE_WIDTH  (SLAVE_WIDTH)
    ) u_response_router (
        .ACLK              (ACLK),
        .ARESETn           (ARESETn),
        .b_route_master    (aw_scheduled_master),
        .b_route_id        (m_axi_awid),
        .b_route_exclusive (b_route_exclusive),
        .b_route_valid     (b_route_valid),
        .b_route_ready     (b_route_ready),
        .r_route_master    (ar_scheduled_master),
        .r_route_id        (m_axi_arid),
        .r_route_exclusive (r_route_exclusive),
        .r_route_valid     (r_route_valid),
        .r_route_ready     (r_route_ready),
        .s_axi_bid         (cached_bid),
        .s_axi_bresp       (cached_bresp),
        .s_axi_bvalid      (m_b_cached_valid),
        .s_axi_bready      (m_b_cached_ready),
        .write_response_valid  (write_response_valid),
        .write_response_success(write_response_success),
        .local_bid         (local_b_id),
        .local_bresp       (local_b_resp),
        .local_bmaster     (local_b_master),
        .local_bvalid      (local_b_valid),
        .local_bready      (local_b_ready),
        .m_axi_bid         (s_axi_bid),
        .m_axi_bresp       (s_axi_bresp),
        .m_axi_bvalid      (s_axi_bvalid),
        .m_axi_bready      (s_axi_bready),
        .s_axi_rid         (cached_rid),
        .s_axi_rdata       (cached_rdata),
        .s_axi_rresp       (cached_rresp),
        .s_axi_rlast       (cached_rlast),
        .s_axi_rvalid      (m_r_cached_valid),
        .s_axi_rready      (m_r_cached_ready),
        .m_axi_rid         (s_axi_rid),
        .m_axi_rdata       (s_axi_rdata),
        .m_axi_rresp       (s_axi_rresp),
        .m_axi_rlast       (s_axi_rlast),
        .m_axi_rvalid      (s_axi_rvalid),
        .m_axi_rready      (s_axi_rready)
    );

endmodule
