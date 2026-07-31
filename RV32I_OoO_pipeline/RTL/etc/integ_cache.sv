module cache_reqmaker #(
    // Cache-side interface configuration
    parameter int unsigned WIDTH_INST = 32,
    parameter int unsigned NUM_CACHE = 48,
    parameter int unsigned WIDTH_DATA = 32,
    parameter int unsigned CACHE_LINE_BYTES = 16,
    parameter int unsigned CACHE_REQ_LEN_WIDTH = 8,
    parameter int unsigned CACHE_REQ_FIFO_DEPTH = 8,
    parameter int unsigned DATA_ID_WIDTH = 5,
    parameter int unsigned RD_AGE_WIDTH = 4,
    parameter int unsigned RD_AGE_THRESHOLD = 8,
    parameter bit          RD_SHORT_BURST_FIRST = 1'b1,

    // AXI4 Full interface configuration
    parameter int unsigned AXI_ADDR_WIDTH   = 32,
    parameter int unsigned AXI_DATA_WIDTH   = 64,
    parameter int unsigned AXI_ID_WIDTH     = 3,
    parameter int unsigned AXI_AWUSER_WIDTH = 1,
    parameter int unsigned AXI_WUSER_WIDTH  = 1,
    parameter int unsigned AXI_BUSER_WIDTH  = 1,
    parameter int unsigned AXI_ARUSER_WIDTH = 1,
    parameter int unsigned AXI_RUSER_WIDTH  = 1,

    localparam int unsigned AXI_STRB_WIDTH    = AXI_DATA_WIDTH / 8,
    localparam int unsigned CACHE_LINE_WIDTH  = CACHE_LINE_BYTES * 8,
    localparam int unsigned CACHE_STRB_WIDTH  = CACHE_LINE_BYTES,
    localparam int unsigned CACHE_LINE_BEATS  = CACHE_LINE_BYTES / AXI_STRB_WIDTH
) (
    input logic ACLK,
    input logic ARESETn,

    // AXI4 Full master write-address channel
    output logic [AXI_ID_WIDTH-1:0]     m_axi_awid,
    output logic [AXI_ADDR_WIDTH-1:0]   m_axi_awaddr,
    output logic [7:0]                  m_axi_awlen,
    output logic [2:0]                  m_axi_awsize,
    output logic [1:0]                  m_axi_awburst,
    output logic                        m_axi_awlock,
    output logic [3:0]                  m_axi_awcache,
    output logic [2:0]                  m_axi_awprot,
    output logic [3:0]                  m_axi_awqos,
    output logic [3:0]                  m_axi_awregion,
    output logic [AXI_AWUSER_WIDTH-1:0] m_axi_awuser,
    output logic                        m_axi_awvalid,
    input  logic                        m_axi_awready,

    // AXI4 Full master write-data channel
    output logic [AXI_DATA_WIDTH-1:0]   m_axi_wdata,
    output logic [AXI_STRB_WIDTH-1:0]    m_axi_wstrb,
    output logic                        m_axi_wlast,
    output logic [AXI_WUSER_WIDTH-1:0]  m_axi_wuser,
    output logic                        m_axi_wvalid,
    input  logic                        m_axi_wready,

    // AXI4 Full master write-response channel
    input  logic [AXI_ID_WIDTH-1:0]     m_axi_bid,
    input  logic [1:0]                  m_axi_bresp,
    input  logic [AXI_BUSER_WIDTH-1:0]  m_axi_buser,
    input  logic                        m_axi_bvalid,
    output logic                        m_axi_bready,

    // AXI4 Full master read-address channel
    output logic [AXI_ID_WIDTH-1:0]     m_axi_arid,
    output logic [AXI_ADDR_WIDTH-1:0]   m_axi_araddr,
    output logic [7:0]                  m_axi_arlen,
    output logic [2:0]                  m_axi_arsize,
    output logic [1:0]                  m_axi_arburst,
    output logic                        m_axi_arlock,
    output logic [3:0]                  m_axi_arcache,
    output logic [2:0]                  m_axi_arprot,
    output logic [3:0]                  m_axi_arqos,
    output logic [3:0]                  m_axi_arregion,
    output logic [AXI_ARUSER_WIDTH-1:0] m_axi_aruser,
    output logic                        m_axi_arvalid,
    input  logic                        m_axi_arready,

    // AXI4 Full master read-data channel
    input  logic [AXI_ID_WIDTH-1:0]     m_axi_rid,
    input  logic [AXI_DATA_WIDTH-1:0]   m_axi_rdata,
    input  logic [1:0]                  m_axi_rresp,
    input  logic                        m_axi_rlast,
    input  logic [AXI_RUSER_WIDTH-1:0]  m_axi_ruser,
    input  logic                        m_axi_rvalid,
    output logic                        m_axi_rready,

    // Inst. Cache - Cache_reqmaker read request channel
    input  logic                        i_req_valid,
    output logic                        i_req_ready,
    input  logic [AXI_ADDR_WIDTH-1:0]   i_req_addr,
    input  logic [CACHE_REQ_LEN_WIDTH-1:0] i_req_len,

    // Inst. Cache - Cache_reqmaker read response channel
    output logic                        i_resp_valid,
    input  logic                        i_resp_ready,
    output logic [CACHE_LINE_WIDTH-1:0] i_resp_data,
    output logic [1:0]                  i_resp_status,
    output logic                        i_resp_last,

    // Data Cache - Cache_reqmaker request channel
    input  logic                        d_req_valid,
    output logic                        d_req_ready,
    input  logic                        d_req_write,
    input  logic [AXI_ADDR_WIDTH-1:0]   d_req_addr,
    input  logic [CACHE_REQ_LEN_WIDTH-1:0] d_req_len,
    input  logic [CACHE_LINE_WIDTH-1:0] d_req_wdata,
    input  logic [CACHE_STRB_WIDTH-1:0] d_req_wstrb,
    input  logic [DATA_ID_WIDTH-1:0]     d_req_id,

    // Data Cache - Cache_reqmaker response channel
    output logic                        d_resp_valid,
    input  logic                        d_resp_ready,
    output logic [CACHE_LINE_WIDTH-1:0] d_resp_rdata,
    output logic [1:0]                  d_resp_status,
    output logic                        d_resp_last,
    output logic [DATA_ID_WIDTH-1:0]     d_resp_id

);


    localparam logic READ_SRC_INST = 1'b0;
    localparam logic READ_SRC_DATA = 1'b1;
    localparam logic [1:0] AXI_BURST_INCR = 2'b01;
    localparam logic [2:0] AXI_SIZE = $clog2(AXI_STRB_WIDTH);
    localparam int unsigned RD_AGE_LIMIT = RD_AGE_THRESHOLD;

    localparam int unsigned RD_REQ_WIDTH = 1 + AXI_ADDR_WIDTH +
        CACHE_REQ_LEN_WIDTH + DATA_ID_WIDTH;
    localparam int unsigned WR_REQ_WIDTH = AXI_ADDR_WIDTH +
        CACHE_REQ_LEN_WIDTH + CACHE_LINE_WIDTH + CACHE_STRB_WIDTH +
        DATA_ID_WIDTH;

    localparam int unsigned RD_ID_LSB   = 0;
    localparam int unsigned RD_LEN_LSB  = DATA_ID_WIDTH;
    localparam int unsigned RD_ADDR_LSB = DATA_ID_WIDTH + CACHE_REQ_LEN_WIDTH;
    localparam int unsigned RD_SRC_LSB  = DATA_ID_WIDTH +
        AXI_ADDR_WIDTH + CACHE_REQ_LEN_WIDTH;
    localparam int unsigned WR_ID_LSB   = 0;
    localparam int unsigned WR_STRB_LSB = DATA_ID_WIDTH;
    localparam int unsigned WR_DATA_LSB = DATA_ID_WIDTH + CACHE_STRB_WIDTH;
    localparam int unsigned WR_LEN_LSB  = DATA_ID_WIDTH +
        CACHE_STRB_WIDTH + CACHE_LINE_WIDTH;
    localparam int unsigned WR_ADDR_LSB = DATA_ID_WIDTH +
        CACHE_STRB_WIDTH + CACHE_LINE_WIDTH + CACHE_REQ_LEN_WIDTH;

    typedef enum logic [1:0] {
        RD_IDLE,
        RD_ADDR,
        RD_DATA,
        RD_RESP
    } rd_state_e;

    typedef enum logic [1:0] {
        WR_IDLE,
        WR_ADDR,
        WR_DATA,
        WR_RESP
    } wr_state_e;

    rd_state_e rd_state;
    wr_state_e wr_state;

    logic [RD_REQ_WIDTH-1:0] rd_fifo_in;
    logic [RD_REQ_WIDTH-1:0] rd_fifo_out;
    logic rd_fifo_push;
    logic rd_fifo_ready;
    logic rd_fifo_pop;
    logic rd_fifo_valid;

    logic [WR_REQ_WIDTH-1:0] wr_fifo_in;
    logic [WR_REQ_WIDTH-1:0] wr_fifo_out;
    logic wr_fifo_push;
    logic wr_fifo_ready;
    logic wr_fifo_pop;
    logic wr_fifo_valid;

    logic rd_pick_inst;
    logic rd_pick_data;
    logic rd_grant_valid;
    logic rd_grant_src;
    logic [AXI_ADDR_WIDTH-1:0] rd_grant_addr;
    logic [CACHE_REQ_LEN_WIDTH-1:0] rd_grant_len;
    logic [DATA_ID_WIDTH-1:0] rd_grant_id;
    logic [RD_AGE_WIDTH-1:0] i_rd_age;
    logic [RD_AGE_WIDTH-1:0] d_rd_age;

    logic rd_src_reg;
    logic [AXI_ADDR_WIDTH-1:0] rd_addr_reg;
    logic [CACHE_REQ_LEN_WIDTH-1:0] rd_len_reg;
    logic [DATA_ID_WIDTH-1:0] rd_id_reg;
    logic [CACHE_REQ_LEN_WIDTH:0] rd_beat_cnt;
    logic [CACHE_LINE_WIDTH-1:0] rd_data_reg;
    logic [1:0] rd_resp_reg;

    logic [AXI_ADDR_WIDTH-1:0] wr_addr_reg;
    logic [CACHE_REQ_LEN_WIDTH-1:0] wr_len_reg;
    logic [DATA_ID_WIDTH-1:0] wr_id_reg;
    logic [CACHE_LINE_WIDTH-1:0] wr_data_reg;
    logic [CACHE_STRB_WIDTH-1:0] wr_strb_reg;
    logic [CACHE_REQ_LEN_WIDTH:0] wr_beat_cnt;
    logic [1:0] wr_resp_reg;
    logic wr_resp_valid_reg;
    logic [CACHE_LINE_WIDTH-1:0] wr_data_shifted;
    logic [CACHE_STRB_WIDTH-1:0] wr_strb_shifted;

    assign wr_fifo_push = d_req_valid && d_req_write && wr_fifo_ready;
    assign wr_fifo_in = {d_req_addr, d_req_len, d_req_wdata,
                         d_req_wstrb, d_req_id};

    assign rd_fifo_pop = (rd_state == RD_IDLE) && rd_fifo_valid;
    assign wr_fifo_pop = (wr_state == WR_IDLE) && wr_fifo_valid;

    // Read arbitration policy: starvation first, burst length second, round-robin last.
    logic rd_select_inst;
    logic rd_select_data;
    logic rd_offer_inst;
    logic rd_offer_data;
    logic rd_accept_inst;
    logic rd_accept_data;
    logic rd_can_accept;
    logic i_rd_starving;
    logic d_rd_starving;

    assign rd_can_accept = !rd_grant_valid || rd_fifo_ready;
    assign rd_accept_inst = rd_can_accept && rd_offer_inst && i_req_valid;
    assign rd_accept_data = rd_can_accept && rd_offer_data && d_req_valid && !d_req_write;
    assign i_rd_starving = (i_rd_age >= RD_AGE_LIMIT);
    assign d_rd_starving = (d_rd_age >= RD_AGE_LIMIT);

    always_comb begin
        rd_select_inst = 1'b0;
        rd_select_data = 1'b0;

        if (i_req_valid && !(d_req_valid && !d_req_write)) begin
            rd_select_inst = 1'b1;
        end
        else if (!i_req_valid && (d_req_valid && !d_req_write)) begin
            rd_select_data = 1'b1;
        end
        else if (i_req_valid && d_req_valid && !d_req_write) begin
            if (i_rd_starving && !d_rd_starving) begin
                rd_select_inst = 1'b1;
            end
            else if (!i_rd_starving && d_rd_starving) begin
                rd_select_data = 1'b1;
            end
            else if (i_rd_starving && d_rd_starving) begin
                if (i_rd_age >= d_rd_age) begin
                    rd_select_inst = 1'b1;
                end
                else begin
                    rd_select_data = 1'b1;
                end
            end
            else if (i_req_len != d_req_len) begin
                if ((RD_SHORT_BURST_FIRST && (i_req_len < d_req_len)) ||
                    (!RD_SHORT_BURST_FIRST && (i_req_len > d_req_len))) begin
                    rd_select_inst = 1'b1;
                end
                else begin
                    rd_select_data = 1'b1;
                end
            end
            else if (rd_grant_src == READ_SRC_INST) begin
                rd_select_data = 1'b1;
            end
            else begin
                rd_select_inst = 1'b1;
            end
        end
    end

    always @(posedge ACLK or negedge ARESETn) begin
        if (!ARESETn) begin
            rd_grant_valid <= 1'b0;
            rd_grant_src   <= READ_SRC_DATA;
            rd_grant_addr  <= '0;
            rd_grant_len   <= '0;
            rd_grant_id    <= '0;
            rd_offer_inst   <= 1'b0;
            rd_offer_data   <= 1'b0;
            i_rd_age       <= '0;
            d_rd_age       <= '0;
        end
        else begin
            if (rd_can_accept) begin
                rd_offer_inst <= rd_select_inst;
                rd_offer_data <= rd_select_data;
            end

            if (rd_fifo_push) begin
                rd_grant_valid <= 1'b0;
            end

            if (rd_accept_inst) begin
                rd_grant_valid <= 1'b1;
                rd_grant_src   <= READ_SRC_INST;
                rd_grant_addr  <= i_req_addr;
                rd_grant_len   <= i_req_len;
                rd_grant_id    <= '0;
            end
            else if (rd_accept_data) begin
                rd_grant_valid <= 1'b1;
                rd_grant_src   <= READ_SRC_DATA;
                rd_grant_addr  <= d_req_addr;
                rd_grant_len   <= d_req_len;
                rd_grant_id    <= d_req_id;
            end

            if (i_req_valid && !rd_accept_inst) begin
                if (!(&i_rd_age)) begin
                    i_rd_age <= i_rd_age + 1'b1;
                end
            end
            else if (rd_accept_inst) begin
                i_rd_age <= '0;
            end

            if ((d_req_valid && !d_req_write) && !rd_accept_data) begin
                if (!(&d_rd_age)) begin
                    d_rd_age <= d_rd_age + 1'b1;
                end
            end
            else if (rd_accept_data) begin
                d_rd_age <= '0;
            end
        end
    end

    assign rd_fifo_push = rd_grant_valid && rd_fifo_ready;
    assign rd_fifo_in = {rd_grant_src, rd_grant_addr,
                         rd_grant_len, rd_grant_id};

    assign rd_pick_inst = rd_fifo_push && (rd_grant_src == READ_SRC_INST);
    assign rd_pick_data = rd_fifo_push && (rd_grant_src == READ_SRC_DATA);

    assign i_req_ready = rd_can_accept && rd_offer_inst;
    assign d_req_ready = d_req_write ? wr_fifo_ready : (rd_can_accept && rd_offer_data);

    fifo_cache #(
        .WIDTH(RD_REQ_WIDTH),
        .NUM_CACHE(CACHE_REQ_FIFO_DEPTH)
    ) u_read_req_fifo (
        .ACLK(ACLK),
        .ARESETn(ARESETn),
        .input_data(rd_fifo_in),
        .i_valid(rd_fifo_push),
        .i_ready(rd_fifo_ready),
        .output_data(rd_fifo_out),
        .o_ready(rd_fifo_pop),
        .o_valid(rd_fifo_valid)
    );

    fifo_cache #(
        .WIDTH(WR_REQ_WIDTH),
        .NUM_CACHE(CACHE_REQ_FIFO_DEPTH)
    ) u_write_req_fifo (
        .ACLK(ACLK),
        .ARESETn(ARESETn),
        .input_data(wr_fifo_in),
        .i_valid(wr_fifo_push),
        .i_ready(wr_fifo_ready),
        .output_data(wr_fifo_out),
        .o_ready(wr_fifo_pop),
        .o_valid(wr_fifo_valid)
    );

    assign wr_data_shifted = wr_data_reg >> (wr_beat_cnt * AXI_DATA_WIDTH);
    assign wr_strb_shifted = wr_strb_reg >> (wr_beat_cnt * AXI_STRB_WIDTH);

    always_comb begin
        m_axi_arid     = '0;
        m_axi_arid[0]  = rd_src_reg;
        m_axi_araddr   = rd_addr_reg;
        m_axi_arlen    = rd_len_reg;
        m_axi_arsize   = AXI_SIZE;
        m_axi_arburst  = AXI_BURST_INCR;
        m_axi_arlock   = 1'b0;
        m_axi_arcache  = 4'b0011;
        m_axi_arprot   = 3'b000;
        m_axi_arqos    = 4'b0000;
        m_axi_arregion = 4'b0000;
        m_axi_aruser   = '0;
        m_axi_arvalid  = (rd_state == RD_ADDR);
        m_axi_rready   = (rd_state == RD_DATA);

        i_resp_valid   = (rd_state == RD_RESP) && (rd_src_reg == READ_SRC_INST);
        i_resp_data    = rd_data_reg;
        i_resp_status  = rd_resp_reg;
        i_resp_last    = (rd_state == RD_RESP) && (rd_src_reg == READ_SRC_INST);

        d_resp_valid   = wr_resp_valid_reg ||
                         ((rd_state == RD_RESP) && (rd_src_reg == READ_SRC_DATA) && !wr_resp_valid_reg);
        d_resp_rdata   = wr_resp_valid_reg ? '0 : rd_data_reg;
        d_resp_status  = wr_resp_valid_reg ? wr_resp_reg : rd_resp_reg;
        d_resp_last    = d_resp_valid;
        d_resp_id      = wr_resp_valid_reg ? wr_id_reg : rd_id_reg;
    end

    always_comb begin
        m_axi_awid     = '0;
        m_axi_awid[0]  = READ_SRC_DATA;
        m_axi_awaddr   = wr_addr_reg;
        m_axi_awlen    = wr_len_reg;
        m_axi_awsize   = AXI_SIZE;
        m_axi_awburst  = AXI_BURST_INCR;
        m_axi_awlock   = 1'b0;
        m_axi_awcache  = 4'b0011;
        m_axi_awprot   = 3'b000;
        m_axi_awqos    = 4'b0000;
        m_axi_awregion = 4'b0000;
        m_axi_awuser   = '0;
        m_axi_awvalid  = (wr_state == WR_ADDR);

        m_axi_wdata    = wr_data_shifted[AXI_DATA_WIDTH-1:0];
        m_axi_wstrb    = wr_strb_shifted[AXI_STRB_WIDTH-1:0];
        m_axi_wlast    = (wr_beat_cnt == wr_len_reg);
        m_axi_wuser    = '0;
        m_axi_wvalid   = (wr_state == WR_DATA);
        m_axi_bready   = (wr_state == WR_RESP) && !wr_resp_valid_reg;
    end


    always @(posedge ACLK or negedge ARESETn) begin
        if (!ARESETn) begin
            rd_state    <= RD_IDLE;
            rd_src_reg  <= READ_SRC_INST;
            rd_addr_reg <= '0;
            rd_len_reg  <= '0;
            rd_id_reg   <= '0;
            rd_beat_cnt <= '0;
            rd_data_reg <= '0;
            rd_resp_reg <= 2'b00;
        end
        else begin
            case (rd_state)
                RD_IDLE: begin
                    if (rd_fifo_valid) begin
                        rd_src_reg  <= rd_fifo_out[RD_SRC_LSB];
                        rd_addr_reg <= rd_fifo_out[RD_ADDR_LSB +: AXI_ADDR_WIDTH];
                        rd_len_reg  <= rd_fifo_out[RD_LEN_LSB +: CACHE_REQ_LEN_WIDTH];
                        rd_id_reg   <= rd_fifo_out[RD_ID_LSB +: DATA_ID_WIDTH];
                        rd_beat_cnt <= '0;
                        rd_data_reg <= '0;
                        rd_resp_reg <= 2'b00;
                        rd_state    <= RD_ADDR;
                    end
                end

                RD_ADDR: begin
                    if (m_axi_arready) begin
                        rd_state <= RD_DATA;
                    end
                end

                RD_DATA: begin
                    if (m_axi_rvalid) begin
                        if (rd_beat_cnt < CACHE_LINE_BEATS) begin
                            rd_data_reg[rd_beat_cnt * AXI_DATA_WIDTH +: AXI_DATA_WIDTH] <= m_axi_rdata;
                        end
                        if (m_axi_rresp != 2'b00) begin
                            rd_resp_reg <= m_axi_rresp;
                        end
                        rd_beat_cnt <= rd_beat_cnt + 1'b1;

                        if (m_axi_rlast || (rd_beat_cnt == rd_len_reg)) begin
                            rd_state <= RD_RESP;
                        end
                    end
                end

                RD_RESP: begin
                    if (((rd_src_reg == READ_SRC_INST) && i_resp_ready) ||
                        ((rd_src_reg == READ_SRC_DATA) && d_resp_ready && !wr_resp_valid_reg)) begin
                        rd_state <= RD_IDLE;
                    end
                end

                default: begin
                    rd_state <= RD_IDLE;
                end
            endcase
        end
    end

    always @(posedge ACLK or negedge ARESETn) begin
        if (!ARESETn) begin
            wr_state    <= WR_IDLE;
            wr_addr_reg <= '0;
            wr_len_reg  <= '0;
            wr_id_reg   <= '0;
            wr_data_reg <= '0;
            wr_strb_reg <= '0;
            wr_beat_cnt <= '0;
            wr_resp_reg <= 2'b00;
            wr_resp_valid_reg <= 1'b0;
        end
        else begin
            case (wr_state)
                WR_IDLE: begin
                    if (wr_fifo_valid) begin
                        wr_addr_reg <= wr_fifo_out[WR_ADDR_LSB +: AXI_ADDR_WIDTH];
                        wr_len_reg  <= wr_fifo_out[WR_LEN_LSB +: CACHE_REQ_LEN_WIDTH];
                        wr_data_reg <= wr_fifo_out[WR_DATA_LSB +: CACHE_LINE_WIDTH];
                        wr_strb_reg <= wr_fifo_out[WR_STRB_LSB +: CACHE_STRB_WIDTH];
                        wr_id_reg   <= wr_fifo_out[WR_ID_LSB +: DATA_ID_WIDTH];
                        wr_beat_cnt <= '0;
                        wr_resp_reg <= 2'b00;
                        wr_resp_valid_reg <= 1'b0;
                        wr_state    <= WR_ADDR;
                    end
                end

                WR_ADDR: begin
                    if (m_axi_awready) begin
                        wr_state <= WR_DATA;
                    end
                end

                WR_DATA: begin
                    if (m_axi_wready) begin
                        if (m_axi_wlast) begin
                            wr_state <= WR_RESP;
                        end
                        else begin
                            wr_beat_cnt <= wr_beat_cnt + 1'b1;
                        end
                    end
                end

                WR_RESP: begin
                    if (m_axi_bvalid && m_axi_bready) begin
                        wr_resp_reg <= m_axi_bresp;
                        wr_resp_valid_reg <= 1'b1;
                    end
                    else if (wr_resp_valid_reg && d_resp_ready) begin
                        wr_resp_valid_reg <= 1'b0;
                        wr_state <= WR_IDLE;
                    end
                end

                default: begin
                    wr_state <= WR_IDLE;
                end
            endcase
        end
    end

endmodule
