module rv32_ooo_core_top #(
    parameter int unsigned WIDTH_INST = 32,
    parameter int unsigned ADDR_WIDTH = 32,
    parameter int unsigned DATA_WIDTH = 32,
    parameter int unsigned ARCH_REGS = 32,
    parameter int unsigned PHYS_REGS = 64,
    parameter int unsigned ROB_ENTRIES = 32,
    parameter int unsigned IQ_ENTRIES = 16,
    parameter int unsigned LSQ_ENTRIES = 16,
    parameter int unsigned STORE_BUFFER_DEPTH = 8,
    parameter int unsigned LOAD_QUEUE_DEPTH = 8,
    parameter int unsigned COMPLETION_QUEUE_DEPTH = 16,
    parameter int unsigned MEM_ID_WIDTH = 5,
    parameter int unsigned FETCH_META_DEPTH = 8,
    parameter int unsigned FETCH_PACKET_DEPTH = 8,
    parameter int unsigned DCACHE_MSHR_ENTRIES = 8,
    parameter int unsigned DCACHE_RESP_QUEUE_DEPTH = 16,
    parameter int unsigned ICACHE_LINES = 48,
    parameter int unsigned DCACHE_LINES = 64,
    parameter int unsigned CACHE_LINE_BYTES = 16,
    parameter int unsigned CACHE_REQ_LEN_WIDTH = 8,
    parameter int unsigned CACHE_REQ_FIFO_DEPTH = 8,
    parameter int unsigned BTB_ENTRIES = 64,
    parameter logic [DATA_WIDTH-1:0] RESET_MTVEC = '0,

    parameter int unsigned AXI_DATA_WIDTH = 64,
    parameter int unsigned AXI_ID_WIDTH = 3,
    parameter int unsigned AXI_AWUSER_WIDTH = 1,
    parameter int unsigned AXI_WUSER_WIDTH = 1,
    parameter int unsigned AXI_BUSER_WIDTH = 1,
    parameter int unsigned AXI_ARUSER_WIDTH = 1,
    parameter int unsigned AXI_RUSER_WIDTH = 1,

    localparam int unsigned ARCH_TAG_WIDTH =
        (ARCH_REGS <= 1) ? 1 : $clog2(ARCH_REGS),
    localparam int unsigned PHYS_TAG_WIDTH =
        (PHYS_REGS <= 1) ? 1 : $clog2(PHYS_REGS),
    localparam int unsigned ROB_TAG_WIDTH =
        (ROB_ENTRIES <= 1) ? 1 : $clog2(ROB_ENTRIES),
    localparam int unsigned FREE_COUNT_WIDTH =
        (PHYS_REGS <= 1) ? 1 : $clog2(PHYS_REGS + 1),
    localparam int unsigned AXI_STRB_WIDTH = AXI_DATA_WIDTH / 8,
    localparam int unsigned CACHE_LINE_WIDTH = CACHE_LINE_BYTES * 8,
    localparam int unsigned CACHE_STRB_WIDTH = CACHE_LINE_BYTES
) (
    input  logic                         ACLK,
    input  logic                         ARESETn,
    input  logic                         fetch_enable,

    input  logic                         irq_software,
    input  logic                         irq_timer,
    input  logic                         irq_external,

    output logic [AXI_ID_WIDTH-1:0]      m_axi_awid,
    output logic [ADDR_WIDTH-1:0]        m_axi_awaddr,
    output logic [7:0]                   m_axi_awlen,
    output logic [2:0]                   m_axi_awsize,
    output logic [1:0]                   m_axi_awburst,
    output logic                         m_axi_awlock,
    output logic [3:0]                   m_axi_awcache,
    output logic [2:0]                   m_axi_awprot,
    output logic [3:0]                   m_axi_awqos,
    output logic [3:0]                   m_axi_awregion,
    output logic [AXI_AWUSER_WIDTH-1:0]  m_axi_awuser,
    output logic                         m_axi_awvalid,
    input  logic                         m_axi_awready,

    output logic [AXI_DATA_WIDTH-1:0]    m_axi_wdata,
    output logic [AXI_STRB_WIDTH-1:0]    m_axi_wstrb,
    output logic                         m_axi_wlast,
    output logic [AXI_WUSER_WIDTH-1:0]   m_axi_wuser,
    output logic                         m_axi_wvalid,
    input  logic                         m_axi_wready,

    input  logic [AXI_ID_WIDTH-1:0]      m_axi_bid,
    input  logic [1:0]                   m_axi_bresp,
    input  logic [AXI_BUSER_WIDTH-1:0]   m_axi_buser,
    input  logic                         m_axi_bvalid,
    output logic                         m_axi_bready,

    output logic [AXI_ID_WIDTH-1:0]      m_axi_arid,
    output logic [ADDR_WIDTH-1:0]        m_axi_araddr,
    output logic [7:0]                   m_axi_arlen,
    output logic [2:0]                   m_axi_arsize,
    output logic [1:0]                   m_axi_arburst,
    output logic                         m_axi_arlock,
    output logic [3:0]                   m_axi_arcache,
    output logic [2:0]                   m_axi_arprot,
    output logic [3:0]                   m_axi_arqos,
    output logic [3:0]                   m_axi_arregion,
    output logic [AXI_ARUSER_WIDTH-1:0]  m_axi_aruser,
    output logic                         m_axi_arvalid,
    input  logic                         m_axi_arready,

    input  logic [AXI_ID_WIDTH-1:0]      m_axi_rid,
    input  logic [AXI_DATA_WIDTH-1:0]    m_axi_rdata,
    input  logic [1:0]                   m_axi_rresp,
    input  logic                         m_axi_rlast,
    input  logic [AXI_RUSER_WIDTH-1:0]   m_axi_ruser,
    input  logic                         m_axi_rvalid,
    output logic                         m_axi_rready,

    output logic                         commit_valid,
    output logic                         retire_valid,
    output logic [ROB_TAG_WIDTH-1:0]     commit_rob_tag,
    output logic [ADDR_WIDTH-1:0]        commit_pc,
    output logic [WIDTH_INST-1:0]       commit_inst,
    output logic [ARCH_TAG_WIDTH-1:0]    commit_arch_rd,
    output logic [PHYS_TAG_WIDTH-1:0]    commit_phys_rd,
    output logic                         commit_write_rd,

    output logic [DATA_WIDTH-1:0]        csr_mstatus,
    output logic [DATA_WIDTH-1:0]        csr_mie,
    output logic [DATA_WIDTH-1:0]        csr_mip,
    output logic [DATA_WIDTH-1:0]        csr_mtvec,
    output logic [DATA_WIDTH-1:0]        csr_mepc,
    output logic [DATA_WIDTH-1:0]        csr_mcause,
    output logic [DATA_WIDTH-1:0]        csr_mtval,

    output logic [FREE_COUNT_WIDTH-1:0]  free_count,
    output logic                         rob_full,
    output logic                         iq_full,
    output logic                         lsq_full,
    output logic                         recovery_busy,
    output logic                         pc_err
);

    logic if_id_valid;
    logic if_id_ready;
    logic [ADDR_WIDTH-1:0] if_id_pc;
    logic [WIDTH_INST-1:0] if_id_inst;
    logic if_id_pred_taken;
    logic [ADDR_WIDTH-1:0] if_id_pred_target;
    logic if_id_cache_hit;
    logic [1:0] if_id_status;
    logic [ADDR_WIDTH-1:0] frontend_resume_pc;

    logic dispatch_valid;
    logic dispatch_ready;
    logic [ADDR_WIDTH-1:0] dispatch_pc;
    logic [WIDTH_INST-1:0] dispatch_inst;
    logic [6:0] dispatch_opcode;
    logic [2:0] dispatch_funct3;
    logic [6:0] dispatch_funct7;
    logic [31:0] dispatch_imm;
    logic [ARCH_TAG_WIDTH-1:0] dispatch_arch_rs1;
    logic [ARCH_TAG_WIDTH-1:0] dispatch_arch_rs2;
    logic [ARCH_TAG_WIDTH-1:0] dispatch_arch_rd;
    logic [PHYS_TAG_WIDTH-1:0] dispatch_phys_rs1;
    logic [PHYS_TAG_WIDTH-1:0] dispatch_phys_rs2;
    logic [PHYS_TAG_WIDTH-1:0] dispatch_phys_rd;
    logic [PHYS_TAG_WIDTH-1:0] dispatch_old_phys_rd;
    logic dispatch_rs1_ready;
    logic dispatch_rs2_ready;
    logic dispatch_use_rs1;
    logic dispatch_use_rs2;
    logic dispatch_write_rd;
    logic dispatch_is_alu;
    logic dispatch_is_load;
    logic dispatch_is_store;
    logic dispatch_is_branch;
    logic dispatch_is_jal;
    logic dispatch_is_jalr;
    logic dispatch_is_lui;
    logic dispatch_is_auipc;
    logic dispatch_is_system;
    logic dispatch_pred_taken;
    logic [ADDR_WIDTH-1:0] dispatch_pred_target;
    logic dispatch_cache_hit;
    logic [1:0] dispatch_if_status;
    logic dispatch_illegal_inst;

    logic writeback_valid;
    logic [PHYS_TAG_WIDTH-1:0] writeback_phys_rd;
    logic [DATA_WIDTH-1:0] writeback_data;

    logic commit_free_valid;
    logic [PHYS_TAG_WIDTH-1:0] commit_free_tag;

    logic recover_valid;
    logic [ADDR_WIDTH-1:0] recover_redirect_pc;
    logic recover_map_valid;
    logic [ARCH_TAG_WIDTH-1:0] recover_arch_rd;
    logic [PHYS_TAG_WIDTH-1:0] recover_phys_rd;
    logic recover_free_valid;
    logic [PHYS_TAG_WIDTH-1:0] recover_free_tag;
    logic recover_flush;

    logic bp_update_valid;
    logic bp_update_is_branch;
    logic [ADDR_WIDTH-1:0] bp_update_pc;
    logic bp_update_taken;
    logic [ADDR_WIDTH-1:0] bp_update_target;

    logic [ADDR_WIDTH-1:0] backend_interrupt_pc;

    logic backend_mem_req_valid;
    logic backend_mem_req_ready;
    logic backend_mem_req_write;
    logic [ADDR_WIDTH-1:0] backend_mem_req_addr;
    logic [DATA_WIDTH-1:0] backend_mem_req_wdata;
    logic [DATA_WIDTH/8-1:0] backend_mem_req_wstrb;
    logic [MEM_ID_WIDTH-1:0] backend_mem_req_id;
    logic backend_mem_resp_valid;
    logic backend_mem_resp_ready;
    logic [DATA_WIDTH-1:0] backend_mem_resp_rdata;
    logic backend_mem_resp_error;
    logic [MEM_ID_WIDTH-1:0] backend_mem_resp_id;

    logic i_req_valid;
    logic i_req_ready;
    logic [ADDR_WIDTH-1:0] i_req_addr;
    logic [CACHE_REQ_LEN_WIDTH-1:0] i_req_len;
    logic i_resp_valid;
    logic i_resp_ready;
    logic [CACHE_LINE_WIDTH-1:0] i_resp_data;
    logic [1:0] i_resp_status;
    logic i_resp_last;

    logic d_req_valid;
    logic d_req_ready;
    logic d_req_write;
    logic [ADDR_WIDTH-1:0] d_req_addr;
    logic [CACHE_REQ_LEN_WIDTH-1:0] d_req_len;
    logic [CACHE_LINE_WIDTH-1:0] d_req_wdata;
    logic [CACHE_STRB_WIDTH-1:0] d_req_wstrb;
    logic [MEM_ID_WIDTH-1:0] d_req_id;
    logic d_resp_valid;
    logic d_resp_ready;
    logic [CACHE_LINE_WIDTH-1:0] d_resp_rdata;
    logic [1:0] d_resp_status;
    logic d_resp_last;
    logic [MEM_ID_WIDTH-1:0] d_resp_id;

    assign backend_interrupt_pc =
        dispatch_valid ? dispatch_pc : frontend_resume_pc;

    if_id_frontend #(
        .WIDTH_INST(WIDTH_INST),
        .ADDR_WIDTH(ADDR_WIDTH),
        .ICACHE_LINES(ICACHE_LINES),
        .CACHE_LINE_BYTES(CACHE_LINE_BYTES),
        .AXI_DATA_WIDTH(AXI_DATA_WIDTH),
        .CACHE_REQ_LEN_WIDTH(CACHE_REQ_LEN_WIDTH),
        .BTB_ENTRIES(BTB_ENTRIES),
        .FETCH_META_DEPTH(FETCH_META_DEPTH),
        .FETCH_PACKET_DEPTH(FETCH_PACKET_DEPTH)
    ) u_frontend (
        .ACLK(ACLK),
        .ARESETn(ARESETn),
        .fetch_enable(fetch_enable),
        .redirect_valid(recover_valid),
        .redirect_addr(recover_redirect_pc),
        .if_id_valid(if_id_valid),
        .if_id_ready(if_id_ready),
        .if_id_pc(if_id_pc),
        .if_id_inst(if_id_inst),
        .if_id_pred_taken(if_id_pred_taken),
        .if_id_pred_target(if_id_pred_target),
        .if_id_cache_hit(if_id_cache_hit),
        .if_id_status(if_id_status),
        .bp_update_valid(bp_update_valid),
        .bp_update_is_branch(bp_update_is_branch),
        .bp_update_pc(bp_update_pc),
        .bp_update_taken(bp_update_taken),
        .bp_update_target(bp_update_target),
        .i_req_valid(i_req_valid),
        .i_req_ready(i_req_ready),
        .i_req_addr(i_req_addr),
        .i_req_len(i_req_len),
        .i_resp_valid(i_resp_valid),
        .i_resp_ready(i_resp_ready),
        .i_resp_data(i_resp_data),
        .i_resp_status(i_resp_status),
        .i_resp_last(i_resp_last),
        .fetch_resume_pc(frontend_resume_pc),
        .pc_err(pc_err)
    );

    id_dispatch #(
        .WIDTH_INST(WIDTH_INST),
        .ADDR_WIDTH(ADDR_WIDTH),
        .ARCH_REGS(ARCH_REGS),
        .PHYS_REGS(PHYS_REGS)
    ) u_id_dispatch (
        .ACLK(ACLK),
        .ARESETn(ARESETn),
        .if_id_valid(if_id_valid),
        .if_id_ready(if_id_ready),
        .if_id_pc(if_id_pc),
        .if_id_inst(if_id_inst),
        .if_id_pred_taken(if_id_pred_taken),
        .if_id_pred_target(if_id_pred_target),
        .if_id_cache_hit(if_id_cache_hit),
        .if_id_status(if_id_status),
        .dispatch_valid(dispatch_valid),
        .dispatch_ready(dispatch_ready),
        .dispatch_pc(dispatch_pc),
        .dispatch_inst(dispatch_inst),
        .dispatch_opcode(dispatch_opcode),
        .dispatch_funct3(dispatch_funct3),
        .dispatch_funct7(dispatch_funct7),
        .dispatch_imm(dispatch_imm),
        .dispatch_arch_rs1(dispatch_arch_rs1),
        .dispatch_arch_rs2(dispatch_arch_rs2),
        .dispatch_arch_rd(dispatch_arch_rd),
        .dispatch_phys_rs1(dispatch_phys_rs1),
        .dispatch_phys_rs2(dispatch_phys_rs2),
        .dispatch_phys_rd(dispatch_phys_rd),
        .dispatch_old_phys_rd(dispatch_old_phys_rd),
        .dispatch_rs1_ready(dispatch_rs1_ready),
        .dispatch_rs2_ready(dispatch_rs2_ready),
        .dispatch_use_rs1(dispatch_use_rs1),
        .dispatch_use_rs2(dispatch_use_rs2),
        .dispatch_write_rd(dispatch_write_rd),
        .dispatch_is_alu(dispatch_is_alu),
        .dispatch_is_load(dispatch_is_load),
        .dispatch_is_store(dispatch_is_store),
        .dispatch_is_branch(dispatch_is_branch),
        .dispatch_is_jal(dispatch_is_jal),
        .dispatch_is_jalr(dispatch_is_jalr),
        .dispatch_is_lui(dispatch_is_lui),
        .dispatch_is_auipc(dispatch_is_auipc),
        .dispatch_is_system(dispatch_is_system),
        .dispatch_pred_taken(dispatch_pred_taken),
        .dispatch_pred_target(dispatch_pred_target),
        .dispatch_cache_hit(dispatch_cache_hit),
        .dispatch_if_status(dispatch_if_status),
        .dispatch_illegal_inst(dispatch_illegal_inst),
        .commit_free_valid(commit_free_valid),
        .commit_free_tag(commit_free_tag),
        .writeback_valid(writeback_valid),
        .writeback_phys_rd(writeback_phys_rd),
        .recover_map_valid(recover_map_valid),
        .recover_arch_rd(recover_arch_rd),
        .recover_phys_rd(recover_phys_rd),
        .recover_free_valid(recover_free_valid),
        .recover_free_tag(recover_free_tag),
        .recover_flush(recover_flush),
        .recovery_busy(recovery_busy),
        .free_count(free_count)
    );

    ooo_backend #(
        .WIDTH_INST(WIDTH_INST),
        .ADDR_WIDTH(ADDR_WIDTH),
        .DATA_WIDTH(DATA_WIDTH),
        .ARCH_REGS(ARCH_REGS),
        .PHYS_REGS(PHYS_REGS),
        .ROB_ENTRIES(ROB_ENTRIES),
        .IQ_ENTRIES(IQ_ENTRIES),
        .LSQ_ENTRIES(LSQ_ENTRIES),
        .STORE_BUFFER_DEPTH(STORE_BUFFER_DEPTH),
        .LOAD_QUEUE_DEPTH(LOAD_QUEUE_DEPTH),
        .COMPLETION_QUEUE_DEPTH(COMPLETION_QUEUE_DEPTH),
        .MEM_ID_WIDTH(MEM_ID_WIDTH),
        .RESET_MTVEC(RESET_MTVEC)
    ) u_backend (
        .ACLK(ACLK),
        .ARESETn(ARESETn),
        .dispatch_valid(dispatch_valid),
        .dispatch_ready(dispatch_ready),
        .dispatch_pc(dispatch_pc),
        .dispatch_inst(dispatch_inst),
        .dispatch_opcode(dispatch_opcode),
        .dispatch_funct3(dispatch_funct3),
        .dispatch_funct7(dispatch_funct7),
        .dispatch_imm(dispatch_imm),
        .dispatch_arch_rs1(dispatch_arch_rs1),
        .dispatch_arch_rs2(dispatch_arch_rs2),
        .dispatch_arch_rd(dispatch_arch_rd),
        .dispatch_phys_rs1(dispatch_phys_rs1),
        .dispatch_phys_rs2(dispatch_phys_rs2),
        .dispatch_phys_rd(dispatch_phys_rd),
        .dispatch_old_phys_rd(dispatch_old_phys_rd),
        .dispatch_rs1_ready(dispatch_rs1_ready),
        .dispatch_rs2_ready(dispatch_rs2_ready),
        .dispatch_use_rs1(dispatch_use_rs1),
        .dispatch_use_rs2(dispatch_use_rs2),
        .dispatch_write_rd(dispatch_write_rd),
        .dispatch_is_alu(dispatch_is_alu),
        .dispatch_is_load(dispatch_is_load),
        .dispatch_is_store(dispatch_is_store),
        .dispatch_is_branch(dispatch_is_branch),
        .dispatch_is_jal(dispatch_is_jal),
        .dispatch_is_jalr(dispatch_is_jalr),
        .dispatch_is_lui(dispatch_is_lui),
        .dispatch_is_auipc(dispatch_is_auipc),
        .dispatch_is_system(dispatch_is_system),
        .dispatch_pred_taken(dispatch_pred_taken),
        .dispatch_pred_target(dispatch_pred_target),
        .dispatch_cache_hit(dispatch_cache_hit),
        .dispatch_if_status(dispatch_if_status),
        .dispatch_illegal_inst(dispatch_illegal_inst),
        .writeback_valid(writeback_valid),
        .writeback_phys_rd(writeback_phys_rd),
        .writeback_data(writeback_data),
        .bp_update_valid(bp_update_valid),
        .bp_update_is_branch(bp_update_is_branch),
        .bp_update_pc(bp_update_pc),
        .bp_update_taken(bp_update_taken),
        .bp_update_target(bp_update_target),
        .commit_valid(commit_valid),
        .retire_valid(retire_valid),
        .commit_ready(1'b1),
        .commit_rob_tag(commit_rob_tag),
        .commit_pc(commit_pc),
        .commit_inst(commit_inst),
        .commit_arch_rd(commit_arch_rd),
        .commit_phys_rd(commit_phys_rd),
        .commit_write_rd(commit_write_rd),
        .commit_free_valid(commit_free_valid),
        .commit_free_tag(commit_free_tag),
        .recover_valid(recover_valid),
        .recover_redirect_pc(recover_redirect_pc),
        .recover_map_valid(recover_map_valid),
        .recover_arch_rd(recover_arch_rd),
        .recover_phys_rd(recover_phys_rd),
        .recover_free_valid(recover_free_valid),
        .recover_free_tag(recover_free_tag),
        .recover_flush(recover_flush),
        .recovery_busy(recovery_busy),
        .irq_software(irq_software),
        .irq_timer(irq_timer),
        .irq_external(irq_external),
        .interrupt_pc(backend_interrupt_pc),
        .mem_req_valid(backend_mem_req_valid),
        .mem_req_ready(backend_mem_req_ready),
        .mem_req_write(backend_mem_req_write),
        .mem_req_addr(backend_mem_req_addr),
        .mem_req_wdata(backend_mem_req_wdata),
        .mem_req_wstrb(backend_mem_req_wstrb),
        .mem_req_id(backend_mem_req_id),
        .mem_resp_valid(backend_mem_resp_valid),
        .mem_resp_ready(backend_mem_resp_ready),
        .mem_resp_rdata(backend_mem_resp_rdata),
        .mem_resp_error(backend_mem_resp_error),
        .mem_resp_id(backend_mem_resp_id),
        .csr_mstatus(csr_mstatus),
        .csr_mie(csr_mie),
        .csr_mip(csr_mip),
        .csr_mtvec(csr_mtvec),
        .csr_mepc(csr_mepc),
        .csr_mcause(csr_mcause),
        .csr_mtval(csr_mtval),
        .rob_full(rob_full),
        .iq_full(iq_full),
        .lsq_full(lsq_full)
    );

    data_cache #(
        .DATA_WIDTH(DATA_WIDTH),
        .ADDR_WIDTH(ADDR_WIDTH),
        .NUM_LINES(DCACHE_LINES),
        .CACHE_LINE_BYTES(CACHE_LINE_BYTES),
        .AXI_DATA_WIDTH(AXI_DATA_WIDTH),
        .CACHE_REQ_LEN_WIDTH(CACHE_REQ_LEN_WIDTH),
        .MEM_ID_WIDTH(MEM_ID_WIDTH),
        .MSHR_ENTRIES(DCACHE_MSHR_ENTRIES),
        .RESP_QUEUE_DEPTH(DCACHE_RESP_QUEUE_DEPTH)
    ) u_data_cache (
        .ACLK(ACLK),
        .ARESETn(ARESETn),
        .mem_req_valid(backend_mem_req_valid),
        .mem_req_ready(backend_mem_req_ready),
        .mem_req_write(backend_mem_req_write),
        .mem_req_addr(backend_mem_req_addr),
        .mem_req_wdata(backend_mem_req_wdata),
        .mem_req_wstrb(backend_mem_req_wstrb),
        .mem_req_id(backend_mem_req_id),
        .mem_resp_valid(backend_mem_resp_valid),
        .mem_resp_ready(backend_mem_resp_ready),
        .mem_resp_rdata(backend_mem_resp_rdata),
        .mem_resp_error(backend_mem_resp_error),
        .mem_resp_id(backend_mem_resp_id),
        .d_req_valid(d_req_valid),
        .d_req_ready(d_req_ready),
        .d_req_write(d_req_write),
        .d_req_addr(d_req_addr),
        .d_req_len(d_req_len),
        .d_req_wdata(d_req_wdata),
        .d_req_wstrb(d_req_wstrb),
        .d_req_id(d_req_id),
        .d_resp_valid(d_resp_valid),
        .d_resp_ready(d_resp_ready),
        .d_resp_rdata(d_resp_rdata),
        .d_resp_status(d_resp_status),
        .d_resp_last(d_resp_last),
        .d_resp_id(d_resp_id)
    );

    cache_reqmaker #(
        .WIDTH_INST(WIDTH_INST),
        .NUM_CACHE(ICACHE_LINES),
        .WIDTH_DATA(DATA_WIDTH),
        .CACHE_LINE_BYTES(CACHE_LINE_BYTES),
        .CACHE_REQ_LEN_WIDTH(CACHE_REQ_LEN_WIDTH),
        .CACHE_REQ_FIFO_DEPTH(CACHE_REQ_FIFO_DEPTH),
        .DATA_ID_WIDTH(MEM_ID_WIDTH),
        .AXI_ADDR_WIDTH(ADDR_WIDTH),
        .AXI_DATA_WIDTH(AXI_DATA_WIDTH),
        .AXI_ID_WIDTH(AXI_ID_WIDTH),
        .AXI_AWUSER_WIDTH(AXI_AWUSER_WIDTH),
        .AXI_WUSER_WIDTH(AXI_WUSER_WIDTH),
        .AXI_BUSER_WIDTH(AXI_BUSER_WIDTH),
        .AXI_ARUSER_WIDTH(AXI_ARUSER_WIDTH),
        .AXI_RUSER_WIDTH(AXI_RUSER_WIDTH)
    ) u_cache_axi_adapter (
        .ACLK(ACLK),
        .ARESETn(ARESETn),
        .m_axi_awid(m_axi_awid),
        .m_axi_awaddr(m_axi_awaddr),
        .m_axi_awlen(m_axi_awlen),
        .m_axi_awsize(m_axi_awsize),
        .m_axi_awburst(m_axi_awburst),
        .m_axi_awlock(m_axi_awlock),
        .m_axi_awcache(m_axi_awcache),
        .m_axi_awprot(m_axi_awprot),
        .m_axi_awqos(m_axi_awqos),
        .m_axi_awregion(m_axi_awregion),
        .m_axi_awuser(m_axi_awuser),
        .m_axi_awvalid(m_axi_awvalid),
        .m_axi_awready(m_axi_awready),
        .m_axi_wdata(m_axi_wdata),
        .m_axi_wstrb(m_axi_wstrb),
        .m_axi_wlast(m_axi_wlast),
        .m_axi_wuser(m_axi_wuser),
        .m_axi_wvalid(m_axi_wvalid),
        .m_axi_wready(m_axi_wready),
        .m_axi_bid(m_axi_bid),
        .m_axi_bresp(m_axi_bresp),
        .m_axi_buser(m_axi_buser),
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
        .m_axi_arregion(m_axi_arregion),
        .m_axi_aruser(m_axi_aruser),
        .m_axi_arvalid(m_axi_arvalid),
        .m_axi_arready(m_axi_arready),
        .m_axi_rid(m_axi_rid),
        .m_axi_rdata(m_axi_rdata),
        .m_axi_rresp(m_axi_rresp),
        .m_axi_rlast(m_axi_rlast),
        .m_axi_ruser(m_axi_ruser),
        .m_axi_rvalid(m_axi_rvalid),
        .m_axi_rready(m_axi_rready),
        .i_req_valid(i_req_valid),
        .i_req_ready(i_req_ready),
        .i_req_addr(i_req_addr),
        .i_req_len(i_req_len),
        .i_resp_valid(i_resp_valid),
        .i_resp_ready(i_resp_ready),
        .i_resp_data(i_resp_data),
        .i_resp_status(i_resp_status),
        .i_resp_last(i_resp_last),
        .d_req_valid(d_req_valid),
        .d_req_ready(d_req_ready),
        .d_req_write(d_req_write),
        .d_req_addr(d_req_addr),
        .d_req_len(d_req_len),
        .d_req_wdata(d_req_wdata),
        .d_req_wstrb(d_req_wstrb),
        .d_req_id(d_req_id),
        .d_resp_valid(d_resp_valid),
        .d_resp_ready(d_resp_ready),
        .d_resp_rdata(d_resp_rdata),
        .d_resp_status(d_resp_status),
        .d_resp_last(d_resp_last),
        .d_resp_id(d_resp_id)
    );
endmodule
