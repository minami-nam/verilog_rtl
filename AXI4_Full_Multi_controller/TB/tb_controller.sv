interface axi_master_bfm_if #(
    parameter int ADDR_WIDTH = 32,
    parameter int DATA_WIDTH = 32,
    parameter int ID_WIDTH   = 4,
    parameter int STRB_WIDTH = DATA_WIDTH / 8
) (
    input logic ACLK,
    input logic ARESETn
);
    logic [ID_WIDTH-1:0]   awid;
    logic [ADDR_WIDTH-1:0] awaddr;
    logic [7:0]            awlen;
    logic [2:0]            awsize;
    logic [1:0]            awburst;
    logic                  awlock;
    logic [3:0]            awcache;
    logic [2:0]            awprot;
    logic [3:0]            awqos;
    logic                  awvalid;
    logic                  awready;

    logic [DATA_WIDTH-1:0] wdata;
    logic [STRB_WIDTH-1:0] wstrb;
    logic                  wlast;
    logic                  wvalid;
    logic                  wready;

    logic [ID_WIDTH-1:0] bid;
    logic [1:0]          bresp;
    logic                bvalid;
    logic                bready;

    logic [ID_WIDTH-1:0]   arid;
    logic [ADDR_WIDTH-1:0] araddr;
    logic [7:0]            arlen;
    logic [2:0]            arsize;
    logic [1:0]            arburst;
    logic                  arlock;
    logic [3:0]            arcache;
    logic [2:0]            arprot;
    logic [3:0]            arqos;
    logic                  arvalid;
    logic                  arready;

    logic [ID_WIDTH-1:0]   rid;
    logic [DATA_WIDTH-1:0] rdata;
    logic [1:0]            rresp;
    logic                  rlast;
    logic                  rvalid;
    logic                  rready;
endinterface


interface axi_slave_bfm_if #(
    parameter int ADDR_WIDTH = 32,
    parameter int DATA_WIDTH = 32,
    parameter int ID_WIDTH   = 4,
    parameter int STRB_WIDTH = DATA_WIDTH / 8
) (
    input logic ACLK,
    input logic ARESETn
);
    logic [ID_WIDTH-1:0]   awid;
    logic [ADDR_WIDTH-1:0] awaddr;
    logic [7:0]            awlen;
    logic [2:0]            awsize;
    logic [1:0]            awburst;
    logic                  awlock;
    logic [3:0]            awcache;
    logic [2:0]            awprot;
    logic [3:0]            awqos;
    logic                  awvalid;
    logic                  awready;

    logic [DATA_WIDTH-1:0] wdata;
    logic [STRB_WIDTH-1:0] wstrb;
    logic                  wlast;
    logic                  wvalid;
    logic                  wready;

    logic [ID_WIDTH-1:0] bid;
    logic [1:0]          bresp;
    logic                bvalid;
    logic                bready;

    logic [ID_WIDTH-1:0]   arid;
    logic [ADDR_WIDTH-1:0] araddr;
    logic [7:0]            arlen;
    logic [2:0]            arsize;
    logic [1:0]            arburst;
    logic                  arlock;
    logic [3:0]            arcache;
    logic [2:0]            arprot;
    logic [3:0]            arqos;
    logic                  arvalid;
    logic                  arready;

    logic [ID_WIDTH-1:0]   rid;
    logic [DATA_WIDTH-1:0] rdata;
    logic [1:0]            rresp;
    logic                  rlast;
    logic                  rvalid;
    logic                  rready;
endinterface


`include "tb_transaction.svh"
`include "tb_agents.svh"
`include "tb_scenarios.svh"
`include "tb_scoreboard.svh"

module tb_controller;
    parameter int NUM_CACHE  = 16;
    parameter int ADDR_WIDTH = 32;
    parameter int DATA_WIDTH = 32;
    parameter int ID_WIDTH   = 4;
    parameter int NUM_MASTER = 3;
    parameter int NUM_SLAVE  = 3;
    parameter int STRB_WIDTH = DATA_WIDTH / 8;
    parameter int AGE_WIDTH = 10;
    parameter int TEST_TIMEOUT_CYCLES = 1000000;
    parameter time CLK_PERIOD = 10ns;

    logic ACLK;
    logic ARESETn;

    logic [NUM_MASTER*ID_WIDTH-1:0]   s_axi_awid;
    logic [NUM_MASTER*ADDR_WIDTH-1:0] s_axi_awaddr;
    logic [NUM_MASTER*8-1:0]          s_axi_awlen;
    logic [NUM_MASTER*3-1:0]          s_axi_awsize;
    logic [NUM_MASTER*2-1:0]          s_axi_awburst;
    logic [NUM_MASTER-1:0]            s_axi_awlock;
    logic [NUM_MASTER*4-1:0]          s_axi_awcache;
    logic [NUM_MASTER*3-1:0]          s_axi_awprot;
    logic [NUM_MASTER*4-1:0]          s_axi_awqos;
    logic [NUM_MASTER-1:0]            s_axi_awvalid;
    wire  [NUM_MASTER-1:0]            s_axi_awready;

    logic [NUM_MASTER*DATA_WIDTH-1:0] s_axi_wdata;
    logic [NUM_MASTER*STRB_WIDTH-1:0] s_axi_wstrb;
    logic [NUM_MASTER-1:0]            s_axi_wlast;
    logic [NUM_MASTER-1:0]            s_axi_wvalid;
    wire  [NUM_MASTER-1:0]            s_axi_wready;

    wire  [NUM_MASTER*ID_WIDTH-1:0] s_axi_bid;
    wire  [NUM_MASTER*2-1:0]        s_axi_bresp;
    wire  [NUM_MASTER-1:0]          s_axi_bvalid;
    logic [NUM_MASTER-1:0]          s_axi_bready;

    logic [NUM_MASTER*ID_WIDTH-1:0]   s_axi_arid;
    logic [NUM_MASTER*ADDR_WIDTH-1:0] s_axi_araddr;
    logic [NUM_MASTER*8-1:0]          s_axi_arlen;
    logic [NUM_MASTER*3-1:0]          s_axi_arsize;
    logic [NUM_MASTER*2-1:0]          s_axi_arburst;
    logic [NUM_MASTER-1:0]            s_axi_arlock;
    logic [NUM_MASTER*4-1:0]          s_axi_arcache;
    logic [NUM_MASTER*3-1:0]          s_axi_arprot;
    logic [NUM_MASTER*4-1:0]          s_axi_arqos;
    logic [NUM_MASTER-1:0]            s_axi_arvalid;
    wire  [NUM_MASTER-1:0]            s_axi_arready;

    wire  [NUM_MASTER*ID_WIDTH-1:0]   s_axi_rid;
    wire  [NUM_MASTER*DATA_WIDTH-1:0] s_axi_rdata;
    wire  [NUM_MASTER*2-1:0]          s_axi_rresp;
    wire  [NUM_MASTER-1:0]            s_axi_rlast;
    wire  [NUM_MASTER-1:0]            s_axi_rvalid;
    logic [NUM_MASTER-1:0]            s_axi_rready;

    wire  [NUM_SLAVE*ID_WIDTH-1:0]   m_axi_awid;
    wire  [NUM_SLAVE*ADDR_WIDTH-1:0] m_axi_awaddr;
    wire  [NUM_SLAVE*8-1:0]          m_axi_awlen;
    wire  [NUM_SLAVE*3-1:0]          m_axi_awsize;
    wire  [NUM_SLAVE*2-1:0]          m_axi_awburst;
    wire  [NUM_SLAVE-1:0]            m_axi_awlock;
    wire  [NUM_SLAVE*4-1:0]          m_axi_awcache;
    wire  [NUM_SLAVE*3-1:0]          m_axi_awprot;
    wire  [NUM_SLAVE*4-1:0]          m_axi_awqos;
    wire  [NUM_SLAVE-1:0]            m_axi_awvalid;
    logic [NUM_SLAVE-1:0]            m_axi_awready;

    wire  [NUM_SLAVE*DATA_WIDTH-1:0] m_axi_wdata;
    wire  [NUM_SLAVE*STRB_WIDTH-1:0] m_axi_wstrb;
    wire  [NUM_SLAVE-1:0]            m_axi_wlast;
    wire  [NUM_SLAVE-1:0]            m_axi_wvalid;
    logic [NUM_SLAVE-1:0]            m_axi_wready;

    logic [NUM_SLAVE*ID_WIDTH-1:0] m_axi_bid;
    logic [NUM_SLAVE*2-1:0]        m_axi_bresp;
    logic [NUM_SLAVE-1:0]          m_axi_bvalid;
    wire  [NUM_SLAVE-1:0]          m_axi_bready;

    wire  [NUM_SLAVE*ID_WIDTH-1:0]   m_axi_arid;
    wire  [NUM_SLAVE*ADDR_WIDTH-1:0] m_axi_araddr;
    wire  [NUM_SLAVE*8-1:0]          m_axi_arlen;
    wire  [NUM_SLAVE*3-1:0]          m_axi_arsize;
    wire  [NUM_SLAVE*2-1:0]          m_axi_arburst;
    wire  [NUM_SLAVE-1:0]            m_axi_arlock;
    wire  [NUM_SLAVE*4-1:0]          m_axi_arcache;
    wire  [NUM_SLAVE*3-1:0]          m_axi_arprot;
    wire  [NUM_SLAVE*4-1:0]          m_axi_arqos;
    wire  [NUM_SLAVE-1:0]            m_axi_arvalid;
    logic [NUM_SLAVE-1:0]            m_axi_arready;

    logic [NUM_SLAVE*ID_WIDTH-1:0]   m_axi_rid;
    logic [NUM_SLAVE*DATA_WIDTH-1:0] m_axi_rdata;
    logic [NUM_SLAVE*2-1:0]          m_axi_rresp;
    logic [NUM_SLAVE-1:0]            m_axi_rlast;
    logic [NUM_SLAVE-1:0]            m_axi_rvalid;
    wire  [NUM_SLAVE-1:0]            m_axi_rready;

    axi_master_bfm_if #(
        .ADDR_WIDTH(ADDR_WIDTH), .DATA_WIDTH(DATA_WIDTH),
        .ID_WIDTH(ID_WIDTH), .STRB_WIDTH(STRB_WIDTH)
    ) master_bus [NUM_MASTER] (ACLK, ARESETn);

    axi_slave_bfm_if #(
        .ADDR_WIDTH(ADDR_WIDTH), .DATA_WIDTH(DATA_WIDTH),
        .ID_WIDTH(ID_WIDTH), .STRB_WIDTH(STRB_WIDTH)
    ) slave_bus [NUM_SLAVE] (ACLK, ARESETn);

    typedef ScenarioMaster #(ADDR_WIDTH, DATA_WIDTH, ID_WIDTH, STRB_WIDTH) master_agent_t;
    typedef ScenarioSlave #(ADDR_WIDTH, DATA_WIDTH, ID_WIDTH, STRB_WIDTH) slave_agent_t;
    typedef ControllerScoreboard #(
        NUM_MASTER, NUM_SLAVE, ADDR_WIDTH, DATA_WIDTH, ID_WIDTH,
        STRB_WIDTH, AGE_WIDTH
    ) scoreboard_t;

    master_agent_t master_agents [NUM_MASTER];
    slave_agent_t slave_agents [NUM_SLAVE];
    scoreboard_t scoreboard;
    logic [NUM_MASTER-1:0] master_done = '0;
    localparam int MASTER_SELECT_WIDTH = (NUM_MASTER <= 1) ? 1 : $clog2(NUM_MASTER);
    localparam int SLAVE_SELECT_WIDTH = (NUM_SLAVE <= 1) ? 1 : $clog2(NUM_SLAVE);
    bit aw_grant_check_enable [NUM_SLAVE];
    bit ar_grant_check_enable [NUM_SLAVE];
    bit expected_aw_grant_valid [NUM_SLAVE];
    bit expected_ar_grant_valid [NUM_SLAVE];
    int unsigned expected_aw_grant_master [NUM_SLAVE];
    int unsigned expected_ar_grant_master [NUM_SLAVE];

    function automatic logic [15:0] policy_score(
        input logic [3:0] qos,
        input logic [AGE_WIDTH-1:0] age,
        input logic [7:0] burst_len
    );
        longint unsigned score;
        score = (longint'(qos) << 8) + (longint'(age) << 3) +
                (8'hff - burst_len);
        return score > 16'hffff ? 16'hffff : score[15:0];
    endfunction

    genvar lane;
    generate
        for (lane=0; lane<NUM_MASTER; lane=lane+1) begin : gen_master_bus_bridge
            always_comb begin
                s_axi_awid[lane*ID_WIDTH +: ID_WIDTH] = master_bus[lane].awid;
                s_axi_awaddr[lane*ADDR_WIDTH +: ADDR_WIDTH] = master_bus[lane].awaddr;
                s_axi_awlen[lane*8 +: 8] = master_bus[lane].awlen;
                s_axi_awsize[lane*3 +: 3] = master_bus[lane].awsize;
                s_axi_awburst[lane*2 +: 2] = master_bus[lane].awburst;
                s_axi_awlock[lane] = master_bus[lane].awlock;
                s_axi_awcache[lane*4 +: 4] = master_bus[lane].awcache;
                s_axi_awprot[lane*3 +: 3] = master_bus[lane].awprot;
                s_axi_awqos[lane*4 +: 4] = master_bus[lane].awqos;
                s_axi_awvalid[lane] = master_bus[lane].awvalid;
                master_bus[lane].awready = s_axi_awready[lane];

                s_axi_wdata[lane*DATA_WIDTH +: DATA_WIDTH] = master_bus[lane].wdata;
                s_axi_wstrb[lane*STRB_WIDTH +: STRB_WIDTH] = master_bus[lane].wstrb;
                s_axi_wlast[lane] = master_bus[lane].wlast;
                s_axi_wvalid[lane] = master_bus[lane].wvalid;
                master_bus[lane].wready = s_axi_wready[lane];

                master_bus[lane].bid = s_axi_bid[lane*ID_WIDTH +: ID_WIDTH];
                master_bus[lane].bresp = s_axi_bresp[lane*2 +: 2];
                master_bus[lane].bvalid = s_axi_bvalid[lane];
                s_axi_bready[lane] = master_bus[lane].bready;

                s_axi_arid[lane*ID_WIDTH +: ID_WIDTH] = master_bus[lane].arid;
                s_axi_araddr[lane*ADDR_WIDTH +: ADDR_WIDTH] = master_bus[lane].araddr;
                s_axi_arlen[lane*8 +: 8] = master_bus[lane].arlen;
                s_axi_arsize[lane*3 +: 3] = master_bus[lane].arsize;
                s_axi_arburst[lane*2 +: 2] = master_bus[lane].arburst;
                s_axi_arlock[lane] = master_bus[lane].arlock;
                s_axi_arcache[lane*4 +: 4] = master_bus[lane].arcache;
                s_axi_arprot[lane*3 +: 3] = master_bus[lane].arprot;
                s_axi_arqos[lane*4 +: 4] = master_bus[lane].arqos;
                s_axi_arvalid[lane] = master_bus[lane].arvalid;
                master_bus[lane].arready = s_axi_arready[lane];

                master_bus[lane].rid = s_axi_rid[lane*ID_WIDTH +: ID_WIDTH];
                master_bus[lane].rdata = s_axi_rdata[lane*DATA_WIDTH +: DATA_WIDTH];
                master_bus[lane].rresp = s_axi_rresp[lane*2 +: 2];
                master_bus[lane].rlast = s_axi_rlast[lane];
                master_bus[lane].rvalid = s_axi_rvalid[lane];
                s_axi_rready[lane] = master_bus[lane].rready;
            end
        end

        for (lane=0; lane<NUM_SLAVE; lane=lane+1) begin : gen_slave_bus_bridge
            always_comb begin
                slave_bus[lane].awid = m_axi_awid[lane*ID_WIDTH +: ID_WIDTH];
                slave_bus[lane].awaddr = m_axi_awaddr[lane*ADDR_WIDTH +: ADDR_WIDTH];
                slave_bus[lane].awlen = m_axi_awlen[lane*8 +: 8];
                slave_bus[lane].awsize = m_axi_awsize[lane*3 +: 3];
                slave_bus[lane].awburst = m_axi_awburst[lane*2 +: 2];
                slave_bus[lane].awlock = m_axi_awlock[lane];
                slave_bus[lane].awcache = m_axi_awcache[lane*4 +: 4];
                slave_bus[lane].awprot = m_axi_awprot[lane*3 +: 3];
                slave_bus[lane].awqos = m_axi_awqos[lane*4 +: 4];
                slave_bus[lane].awvalid = m_axi_awvalid[lane];
                m_axi_awready[lane] = slave_bus[lane].awready;

                slave_bus[lane].wdata = m_axi_wdata[lane*DATA_WIDTH +: DATA_WIDTH];
                slave_bus[lane].wstrb = m_axi_wstrb[lane*STRB_WIDTH +: STRB_WIDTH];
                slave_bus[lane].wlast = m_axi_wlast[lane];
                slave_bus[lane].wvalid = m_axi_wvalid[lane];
                m_axi_wready[lane] = slave_bus[lane].wready;

                m_axi_bid[lane*ID_WIDTH +: ID_WIDTH] = slave_bus[lane].bid;
                m_axi_bresp[lane*2 +: 2] = slave_bus[lane].bresp;
                m_axi_bvalid[lane] = slave_bus[lane].bvalid;
                slave_bus[lane].bready = m_axi_bready[lane];

                slave_bus[lane].arid = m_axi_arid[lane*ID_WIDTH +: ID_WIDTH];
                slave_bus[lane].araddr = m_axi_araddr[lane*ADDR_WIDTH +: ADDR_WIDTH];
                slave_bus[lane].arlen = m_axi_arlen[lane*8 +: 8];
                slave_bus[lane].arsize = m_axi_arsize[lane*3 +: 3];
                slave_bus[lane].arburst = m_axi_arburst[lane*2 +: 2];
                slave_bus[lane].arlock = m_axi_arlock[lane];
                slave_bus[lane].arcache = m_axi_arcache[lane*4 +: 4];
                slave_bus[lane].arprot = m_axi_arprot[lane*3 +: 3];
                slave_bus[lane].arqos = m_axi_arqos[lane*4 +: 4];
                slave_bus[lane].arvalid = m_axi_arvalid[lane];
                m_axi_arready[lane] = slave_bus[lane].arready;

                m_axi_rid[lane*ID_WIDTH +: ID_WIDTH] = slave_bus[lane].rid;
                m_axi_rdata[lane*DATA_WIDTH +: DATA_WIDTH] = slave_bus[lane].rdata;
                m_axi_rresp[lane*2 +: 2] = slave_bus[lane].rresp;
                m_axi_rlast[lane] = slave_bus[lane].rlast;
                m_axi_rvalid[lane] = slave_bus[lane].rvalid;
                slave_bus[lane].rready = m_axi_rready[lane];
            end
        end
    endgenerate

    generate
        for (lane=0; lane<NUM_MASTER; lane=lane+1) begin : gen_master_agents
            initial begin
                master_agents[lane] = new(lane, master_bus[lane],
                    $sformatf("master_%0d", lane));
                master_agents[lane].run();
                master_done[lane] = 1'b1;
            end
        end
        for (lane=0; lane<NUM_SLAVE; lane=lane+1) begin : gen_slave_agents
            initial begin
                slave_agents[lane] = new(lane, slave_bus[lane],
                    $sformatf("slave_%0d", lane));
                slave_agents[lane].run();
            end
        end
    endgenerate

    axi_controller_unit #(
        .NUM_CACHE(NUM_CACHE), .ADDR_WIDTH(ADDR_WIDTH), .DATA_WIDTH(DATA_WIDTH),
        .ID_WIDTH(ID_WIDTH), .NUM_MASTER(NUM_MASTER), .NUM_SLAVE(NUM_SLAVE),
        .STRB_WIDTH(STRB_WIDTH)
    ) dut (
        .*
    );

    initial ACLK = 1'b0;
    always #(CLK_PERIOD/2) ACLK = ~ACLK;

    initial begin
        ARESETn = 1'b0;
        repeat (5) @(posedge ACLK);
        ARESETn = 1'b1;
    end

    initial scoreboard = new();

    always @(posedge ACLK) begin : scoreboard_transaction_monitor
        int unsigned source_master;
        if (ARESETn && scoreboard != null) begin
            scoreboard.tick();

            for (int unsigned master=0; master<NUM_MASTER; master++) begin
                if (s_axi_awvalid[master] && s_axi_awready[master])
                    scoreboard.observe_master_aw(master,
                        s_axi_awid[master*ID_WIDTH +: ID_WIDTH],
                        s_axi_awaddr[master*ADDR_WIDTH +: ADDR_WIDTH],
                        s_axi_awlen[master*8 +: 8],
                        s_axi_awsize[master*3 +: 3],
                        s_axi_awburst[master*2 +: 2], s_axi_awlock[master],
                        s_axi_awqos[master*4 +: 4]);
                if (s_axi_wvalid[master] && s_axi_wready[master])
                    scoreboard.observe_master_w(master,
                        s_axi_wdata[master*DATA_WIDTH +: DATA_WIDTH],
                        s_axi_wstrb[master*STRB_WIDTH +: STRB_WIDTH],
                        s_axi_wlast[master]);
                if (s_axi_arvalid[master] && s_axi_arready[master])
                    scoreboard.observe_master_ar(master,
                        s_axi_arid[master*ID_WIDTH +: ID_WIDTH],
                        s_axi_araddr[master*ADDR_WIDTH +: ADDR_WIDTH],
                        s_axi_arlen[master*8 +: 8],
                        s_axi_arsize[master*3 +: 3],
                        s_axi_arburst[master*2 +: 2], s_axi_arlock[master],
                        s_axi_arqos[master*4 +: 4]);
            end

            for (int unsigned slave=0; slave<NUM_SLAVE; slave++) begin
                if (m_axi_awvalid[slave] && m_axi_awready[slave]) begin
                    source_master = dut.aw_scheduled_master[
                        slave*MASTER_SELECT_WIDTH +: MASTER_SELECT_WIDTH];
                    scoreboard.observe_slave_aw(slave, source_master,
                        m_axi_awid[slave*ID_WIDTH +: ID_WIDTH],
                        m_axi_awaddr[slave*ADDR_WIDTH +: ADDR_WIDTH],
                        m_axi_awlen[slave*8 +: 8],
                        m_axi_awsize[slave*3 +: 3],
                        m_axi_awburst[slave*2 +: 2], m_axi_awlock[slave]);
                end
                if (m_axi_wvalid[slave] && m_axi_wready[slave])
                    scoreboard.observe_slave_w(slave,
                        m_axi_wdata[slave*DATA_WIDTH +: DATA_WIDTH],
                        m_axi_wstrb[slave*STRB_WIDTH +: STRB_WIDTH],
                        m_axi_wlast[slave]);
                if (m_axi_bvalid[slave] && m_axi_bready[slave])
                    scoreboard.observe_slave_b(slave,
                        m_axi_bid[slave*ID_WIDTH +: ID_WIDTH],
                        m_axi_bresp[slave*2 +: 2]);
                if (m_axi_arvalid[slave] && m_axi_arready[slave]) begin
                    source_master = dut.ar_scheduled_master[
                        slave*MASTER_SELECT_WIDTH +: MASTER_SELECT_WIDTH];
                    scoreboard.observe_slave_ar(slave, source_master,
                        m_axi_arid[slave*ID_WIDTH +: ID_WIDTH],
                        m_axi_araddr[slave*ADDR_WIDTH +: ADDR_WIDTH],
                        m_axi_arlen[slave*8 +: 8],
                        m_axi_arsize[slave*3 +: 3],
                        m_axi_arburst[slave*2 +: 2], m_axi_arlock[slave]);
                end
                if (m_axi_rvalid[slave] && m_axi_rready[slave])
                    scoreboard.observe_slave_r(slave,
                        m_axi_rid[slave*ID_WIDTH +: ID_WIDTH],
                        m_axi_rdata[slave*DATA_WIDTH +: DATA_WIDTH],
                        m_axi_rresp[slave*2 +: 2], m_axi_rlast[slave]);
            end

            for (int unsigned master=0; master<NUM_MASTER; master++) begin
                if (s_axi_bvalid[master] && s_axi_bready[master])
                    scoreboard.observe_master_b(master,
                        s_axi_bid[master*ID_WIDTH +: ID_WIDTH],
                        s_axi_bresp[master*2 +: 2]);
                if (s_axi_rvalid[master] && s_axi_rready[master])
                    scoreboard.observe_master_r(master,
                        s_axi_rid[master*ID_WIDTH +: ID_WIDTH],
                        s_axi_rdata[master*DATA_WIDTH +: DATA_WIDTH],
                        s_axi_rresp[master*2 +: 2], s_axi_rlast[master]);
            end
        end
    end

    always @(posedge ACLK) begin : scoreboard_scheduler_policy_monitor
        logic [15:0] best_score;
        logic [15:0] candidate_score;
        int unsigned candidate_target;
        if (ARESETn && scoreboard != null) begin
            for (int unsigned slave=0; slave<NUM_SLAVE; slave++) begin
                aw_grant_check_enable[slave] =
                    !dut.u_aw_scheduler.grant_valid[slave] &&
                    (!dut.u_aw_scheduler.valid_reg[slave] ||
                     dut.aw_scheduler_ready[slave]);
                ar_grant_check_enable[slave] =
                    !dut.u_ar_scheduler.grant_valid[slave] &&
                    (!dut.u_ar_scheduler.valid_reg[slave] ||
                     dut.ar_scheduler_ready[slave]);
                expected_aw_grant_valid[slave] = 1'b0;
                expected_ar_grant_valid[slave] = 1'b0;
                expected_aw_grant_master[slave] = 0;
                expected_ar_grant_master[slave] = 0;

                best_score = '0;
                if (aw_grant_check_enable[slave]) begin
                    for (int unsigned master=0; master<NUM_MASTER; master++) begin
                        candidate_target = dut.s_aw_target[
                            master*SLAVE_SELECT_WIDTH +: SLAVE_SELECT_WIDTH];
                        candidate_score = policy_score(
                            dut.s_aw_cached_qos[master*4 +: 4],
                            dut.u_aw_scheduler.request_age[master],
                            dut.s_aw_cached_len[master*8 +: 8]);
                        if (dut.s_aw_cached_valid[master] &&
                            candidate_target == slave &&
                            (!expected_aw_grant_valid[slave] ||
                             candidate_score > best_score)) begin
                            expected_aw_grant_valid[slave] = 1'b1;
                            expected_aw_grant_master[slave] = master;
                            best_score = candidate_score;
                        end
                    end
                end

                best_score = '0;
                if (ar_grant_check_enable[slave]) begin
                    for (int unsigned master=0; master<NUM_MASTER; master++) begin
                        candidate_target = dut.s_ar_target[
                            master*SLAVE_SELECT_WIDTH +: SLAVE_SELECT_WIDTH];
                        candidate_score = policy_score(
                            dut.s_ar_cached_qos[master*4 +: 4],
                            dut.u_ar_scheduler.request_age[master],
                            dut.s_ar_cached_len[master*8 +: 8]);
                        if (dut.s_ar_cached_valid[master] &&
                            candidate_target == slave &&
                            (!expected_ar_grant_valid[slave] ||
                             candidate_score > best_score)) begin
                            expected_ar_grant_valid[slave] = 1'b1;
                            expected_ar_grant_master[slave] = master;
                            best_score = candidate_score;
                        end
                    end
                end
            end

            #1step;
            for (int unsigned slave=0; slave<NUM_SLAVE; slave++) begin
                if (aw_grant_check_enable[slave])
                    scoreboard.check_scheduler_grant(1'b1, slave,
                        expected_aw_grant_valid[slave],
                        expected_aw_grant_master[slave],
                        dut.u_aw_scheduler.grant_valid[slave],
                        dut.u_aw_scheduler.grant_master[slave]);
                if (ar_grant_check_enable[slave])
                    scoreboard.check_scheduler_grant(1'b0, slave,
                        expected_ar_grant_valid[slave],
                        expected_ar_grant_master[slave],
                        dut.u_ar_scheduler.grant_valid[slave],
                        dut.u_ar_scheduler.grant_master[slave]);
            end
        end
    end

    always @(posedge ACLK) begin : scoreboard_aging_monitor
        if (ARESETn && scoreboard != null) begin
            #1step;
            for (int unsigned master=0; master<NUM_MASTER; master++) begin
                scoreboard.sample_aging(1'b1, master,
                    dut.s_aw_cached_valid[master], dut.s_aw_cached_ready[master],
                    dut.u_aw_scheduler.request_age[master]);
                scoreboard.sample_aging(1'b0, master,
                    dut.s_ar_cached_valid[master], dut.s_ar_cached_ready[master],
                    dut.u_ar_scheduler.request_age[master]);
            end
        end
    end

    initial begin : finish_when_scenarios_complete
        wait (ARESETn);
        wait (&master_done);
        repeat (50) @(posedge ACLK);
        scoreboard.report();
        $finish;
    end

    initial begin : test_timeout
        wait (ARESETn);
        repeat (TEST_TIMEOUT_CYCLES) @(posedge ACLK);
        scoreboard.report();
        $finish;
    end

endmodule
