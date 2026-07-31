module ooo_backend #(
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
    parameter logic [DATA_WIDTH-1:0] RESET_MTVEC = '0,

    localparam int unsigned ARCH_TAG_WIDTH =
        (ARCH_REGS <= 1) ? 1 : $clog2(ARCH_REGS),
    localparam int unsigned PHYS_TAG_WIDTH =
        (PHYS_REGS <= 1) ? 1 : $clog2(PHYS_REGS),
    localparam int unsigned ROB_TAG_WIDTH =
        (ROB_ENTRIES <= 1) ? 1 : $clog2(ROB_ENTRIES),
    localparam int unsigned DATA_STRB_WIDTH = DATA_WIDTH / 8,
    localparam int unsigned EXC_CAUSE_WIDTH = 5
) (
    input  logic                        ACLK,
    input  logic                        ARESETn,

    input  logic                        dispatch_valid,
    output logic                        dispatch_ready,
    input  logic [ADDR_WIDTH-1:0]       dispatch_pc,
    input  logic [WIDTH_INST-1:0]       dispatch_inst,
    input  logic [6:0]                  dispatch_opcode,
    input  logic [2:0]                  dispatch_funct3,
    input  logic [6:0]                  dispatch_funct7,
    input  logic [31:0]                 dispatch_imm,
    input  logic [ARCH_TAG_WIDTH-1:0]   dispatch_arch_rs1,
    input  logic [ARCH_TAG_WIDTH-1:0]   dispatch_arch_rs2,
    input  logic [ARCH_TAG_WIDTH-1:0]   dispatch_arch_rd,
    input  logic [PHYS_TAG_WIDTH-1:0]   dispatch_phys_rs1,
    input  logic [PHYS_TAG_WIDTH-1:0]   dispatch_phys_rs2,
    input  logic [PHYS_TAG_WIDTH-1:0]   dispatch_phys_rd,
    input  logic [PHYS_TAG_WIDTH-1:0]   dispatch_old_phys_rd,
    input  logic                        dispatch_rs1_ready,
    input  logic                        dispatch_rs2_ready,
    input  logic                        dispatch_use_rs1,
    input  logic                        dispatch_use_rs2,
    input  logic                        dispatch_write_rd,
    input  logic                        dispatch_is_alu,
    input  logic                        dispatch_is_load,
    input  logic                        dispatch_is_store,
    input  logic                        dispatch_is_branch,
    input  logic                        dispatch_is_jal,
    input  logic                        dispatch_is_jalr,
    input  logic                        dispatch_is_lui,
    input  logic                        dispatch_is_auipc,
    input  logic                        dispatch_is_system,
    input  logic                        dispatch_pred_taken,
    input  logic [ADDR_WIDTH-1:0]       dispatch_pred_target,
    input  logic                        dispatch_cache_hit,
    input  logic [1:0]                  dispatch_if_status,
    input  logic                        dispatch_illegal_inst,

    output logic                        writeback_valid,
    output logic [PHYS_TAG_WIDTH-1:0]   writeback_phys_rd,
    output logic [DATA_WIDTH-1:0]       writeback_data,

    output logic                        bp_update_valid,
    output logic                        bp_update_is_branch,
    output logic [ADDR_WIDTH-1:0]       bp_update_pc,
    output logic                        bp_update_taken,
    output logic [ADDR_WIDTH-1:0]       bp_update_target,

    output logic                        commit_valid,
    output logic                        retire_valid,
    input  logic                        commit_ready,
    output logic [ROB_TAG_WIDTH-1:0]    commit_rob_tag,
    output logic [ADDR_WIDTH-1:0]       commit_pc,
    output logic [WIDTH_INST-1:0]      commit_inst,
    output logic [ARCH_TAG_WIDTH-1:0]   commit_arch_rd,
    output logic [PHYS_TAG_WIDTH-1:0]   commit_phys_rd,
    output logic                        commit_write_rd,
    output logic                        commit_free_valid,
    output logic [PHYS_TAG_WIDTH-1:0]   commit_free_tag,

    output logic                        recover_valid,
    output logic [ADDR_WIDTH-1:0]       recover_redirect_pc,
    output logic                        recover_map_valid,
    output logic [ARCH_TAG_WIDTH-1:0]   recover_arch_rd,
    output logic [PHYS_TAG_WIDTH-1:0]   recover_phys_rd,
    output logic                        recover_free_valid,
    output logic [PHYS_TAG_WIDTH-1:0]   recover_free_tag,
    output logic                        recover_flush,
    output logic                        recovery_busy,

    input  logic                        irq_software,
    input  logic                        irq_timer,
    input  logic                        irq_external,
    input  logic [ADDR_WIDTH-1:0]       interrupt_pc,

    output logic                        mem_req_valid,
    input  logic                        mem_req_ready,
    output logic                        mem_req_write,
    output logic [ADDR_WIDTH-1:0]       mem_req_addr,
    output logic [DATA_WIDTH-1:0]       mem_req_wdata,
    output logic [DATA_STRB_WIDTH-1:0]  mem_req_wstrb,
    output logic [MEM_ID_WIDTH-1:0]      mem_req_id,
    input  logic                        mem_resp_valid,
    output logic                        mem_resp_ready,
    input  logic [DATA_WIDTH-1:0]       mem_resp_rdata,
    input  logic                        mem_resp_error,
    input  logic [MEM_ID_WIDTH-1:0]      mem_resp_id,

    output logic [DATA_WIDTH-1:0]       csr_mstatus,
    output logic [DATA_WIDTH-1:0]       csr_mie,
    output logic [DATA_WIDTH-1:0]       csr_mip,
    output logic [DATA_WIDTH-1:0]       csr_mtvec,
    output logic [DATA_WIDTH-1:0]       csr_mepc,
    output logic [DATA_WIDTH-1:0]       csr_mcause,
    output logic [DATA_WIDTH-1:0]       csr_mtval,

    output logic                        rob_full,
    output logic                        iq_full,
    output logic                        lsq_full
);

    logic dispatch_ready_internal;
    logic int_issue_valid;
    logic int_issue_ready;
    logic [ROB_TAG_WIDTH-1:0] int_issue_rob_tag;
    logic [ADDR_WIDTH-1:0] int_issue_pc;
    logic [WIDTH_INST-1:0] int_issue_inst;
    logic [6:0] int_issue_opcode;
    logic [2:0] int_issue_funct3;
    logic [6:0] int_issue_funct7;
    logic [31:0] int_issue_imm;
    logic [PHYS_TAG_WIDTH-1:0] int_issue_phys_rs1;
    logic [PHYS_TAG_WIDTH-1:0] int_issue_phys_rs2;
    logic [PHYS_TAG_WIDTH-1:0] int_issue_phys_rd;
    logic int_issue_use_rs1;
    logic int_issue_use_rs2;
    logic int_issue_write_rd;
    logic int_issue_is_branch;
    logic int_issue_is_jal;
    logic int_issue_is_jalr;
    logic int_issue_is_system;
    logic int_issue_pred_taken;
    logic [ADDR_WIDTH-1:0] int_issue_pred_target;

    logic ls_issue_valid;
    logic ls_issue_ready;
    logic [ROB_TAG_WIDTH-1:0] ls_issue_rob_tag;
    logic [ADDR_WIDTH-1:0] ls_issue_pc;
    logic [WIDTH_INST-1:0] ls_issue_inst;
    logic [2:0] ls_issue_funct3;
    logic [31:0] ls_issue_imm;
    logic [PHYS_TAG_WIDTH-1:0] ls_issue_phys_rs1;
    logic [PHYS_TAG_WIDTH-1:0] ls_issue_phys_rs2;
    logic [PHYS_TAG_WIDTH-1:0] ls_issue_phys_rd;
    logic ls_issue_is_load;
    logic ls_issue_is_store;

    logic [ROB_TAG_WIDTH-1:0] rob_head_tag;
    logic rob_empty;
    logic dispatch_recover_valid;
    logic [ADDR_WIDTH-1:0] dispatch_recover_pc;
    logic dispatch_recover_flush;
    logic dispatch_recovery_busy;

    logic head_exception_valid;
    logic [EXC_CAUSE_WIDTH-1:0] head_exception_cause;
    logic [ADDR_WIDTH-1:0] head_exception_pc;
    logic [ADDR_WIDTH-1:0] head_exception_tval;

    logic commit_store_valid;
    logic [ROB_TAG_WIDTH-1:0] commit_store_rob_tag;
    logic commit_store_ready;

    logic arb_wb_valid;
    logic arb_wb_ready;
    logic [ROB_TAG_WIDTH-1:0] arb_wb_rob_tag;
    logic [PHYS_TAG_WIDTH-1:0] arb_wb_phys_rd;
    logic arb_wb_write_rd;
    logic [DATA_WIDTH-1:0] arb_wb_data;
    logic arb_wb_branch_taken;
    logic [ADDR_WIDTH-1:0] arb_wb_actual_target;
    logic arb_wb_exception;
    logic [EXC_CAUSE_WIDTH-1:0] arb_wb_exception_cause;
    logic [ADDR_WIDTH-1:0] arb_wb_exception_tval;

    logic [PHYS_TAG_WIDTH-1:0] prf_rs1_tag;
    logic [PHYS_TAG_WIDTH-1:0] prf_rs2_tag;
    logic [DATA_WIDTH-1:0] prf_rs1_data;
    logic [DATA_WIDTH-1:0] prf_rs2_data;

    logic select_integer;
    logic select_memory;
    logic int_can_issue;
    logic mem_can_issue;
    logic [ROB_TAG_WIDTH:0] int_distance;
    logic [ROB_TAG_WIDTH:0] ls_distance;

    logic route_csr;
    logic route_mret;
    logic route_alu;
    logic selected_integer_ready;

    logic alu_issue_valid;
    logic alu_issue_ready;
    logic alu_wb_valid;
    logic alu_wb_ready;
    logic [ROB_TAG_WIDTH-1:0] alu_wb_rob_tag;
    logic [PHYS_TAG_WIDTH-1:0] alu_wb_phys_rd;
    logic alu_wb_write_rd;
    logic [DATA_WIDTH-1:0] alu_wb_data;
    logic alu_wb_branch_taken;
    logic [ADDR_WIDTH-1:0] alu_wb_actual_target;
    logic alu_wb_exception;
    logic alu_meta_is_control;
    logic [ADDR_WIDTH-1:0] alu_meta_pc;
    logic [EXC_CAUSE_WIDTH-1:0] alu_wb_exception_cause;
    logic [ADDR_WIDTH-1:0] alu_wb_exception_tval;

    logic lsu_issue_ready;
    logic lsu_wb_valid;
    logic lsu_wb_ready;
    logic [ROB_TAG_WIDTH-1:0] lsu_wb_rob_tag;
    logic [PHYS_TAG_WIDTH-1:0] lsu_wb_phys_rd;
    logic lsu_wb_write_rd;
    logic [DATA_WIDTH-1:0] lsu_wb_data;
    logic lsu_wb_exception;
    logic [EXC_CAUSE_WIDTH-1:0] lsu_wb_exception_cause;
    logic [ADDR_WIDTH-1:0] lsu_wb_exception_tval;

    logic csr_req_valid;
    logic csr_req_ready;
    logic csr_resp_valid;
    logic csr_resp_ready;
    logic [DATA_WIDTH-1:0] csr_resp_rdata;
    logic csr_resp_illegal;
    logic csr_wb_ready;
    logic [ROB_TAG_WIDTH-1:0] csr_meta_rob_tag;
    logic [PHYS_TAG_WIDTH-1:0] csr_meta_phys_rd;
    logic csr_meta_write_rd;
    logic [WIDTH_INST-1:0] csr_meta_inst;

    logic csr_trap_valid;
    logic csr_trap_ready;
    logic csr_trap_is_interrupt;
    logic [EXC_CAUSE_WIDTH-1:0] csr_trap_cause;
    logic [ADDR_WIDTH-1:0] csr_trap_pc;
    logic [ADDR_WIDTH-1:0] csr_trap_tval;
    logic csr_mret_valid;
    logic csr_mret_ready;
    logic [ADDR_WIDTH-1:0] csr_mret_pc;
    logic [ADDR_WIDTH-1:0] trap_vector_pc;
    logic interrupt_pending;
    logic [EXC_CAUSE_WIDTH-1:0] interrupt_cause;
    logic sync_trap_request;
    logic interrupt_request;
    logic trap_fire;
    logic sync_trap_fire;
    logic interrupt_take;
    logic mret_fire;
    logic external_recover_valid;
    logic [ADDR_WIDTH-1:0] external_recover_pc;
    logic global_flush;
    logic retire_fire;

    function automatic logic [ROB_TAG_WIDTH:0] rob_distance(
        input logic [ROB_TAG_WIDTH-1:0] tag,
        input logic [ROB_TAG_WIDTH-1:0] head
    );
        if (tag >= head)
            rob_distance = tag - head;
        else
            rob_distance = ROB_ENTRIES + tag - head;
    endfunction

    assign dispatch_ready = dispatch_ready_internal && !interrupt_take;

    assign int_distance = rob_distance(int_issue_rob_tag, rob_head_tag);
    assign ls_distance = rob_distance(ls_issue_rob_tag, rob_head_tag);
    assign int_can_issue = int_issue_valid &&
                           selected_integer_ready &&
                           !global_flush;
    assign mem_can_issue = ls_issue_valid &&
                           lsu_issue_ready &&
                           !global_flush;

    assign select_integer = int_can_issue &&
                            (!mem_can_issue ||
                             (int_distance <= ls_distance));
    assign select_memory = mem_can_issue &&
                           (!int_can_issue ||
                            (ls_distance < int_distance));

    assign prf_rs1_tag = select_memory ?
                         ls_issue_phys_rs1 : int_issue_phys_rs1;
    assign prf_rs2_tag = select_memory ?
                         ls_issue_phys_rs2 : int_issue_phys_rs2;

    assign route_csr = int_issue_is_system &&
                       (int_issue_funct3 != 3'b000);
    assign route_mret = int_issue_is_system &&
                        (int_issue_inst == 32'h3020_0073);
    assign route_alu = !route_csr && !route_mret;

    always_comb begin
        selected_integer_ready = 1'b0;
        if (route_csr)
            selected_integer_ready =
                (int_issue_rob_tag == rob_head_tag) && csr_req_ready;
        else if (route_mret)
            selected_integer_ready =
                (int_issue_rob_tag == rob_head_tag) && csr_mret_ready;
        else
            selected_integer_ready = alu_issue_ready;
    end

    assign int_issue_ready = select_integer;
    assign ls_issue_ready = select_memory;

    assign alu_issue_valid = int_issue_valid && select_integer &&
                             route_alu && !global_flush;
    assign csr_req_valid = int_issue_valid && select_integer &&
                           route_csr &&
                           (int_issue_rob_tag == rob_head_tag) &&
                           !global_flush;
    assign csr_mret_valid = int_issue_valid && select_integer &&
                            route_mret &&
                            (int_issue_rob_tag == rob_head_tag);
    assign mret_fire = csr_mret_valid && csr_mret_ready;

    assign sync_trap_request = head_exception_valid &&
                               !dispatch_recovery_busy;
    assign interrupt_request = interrupt_pending && rob_empty &&
                               !dispatch_recovery_busy &&
                               !sync_trap_request;

    assign csr_trap_valid = sync_trap_request || interrupt_request;
    assign csr_trap_is_interrupt = interrupt_request;
    assign csr_trap_cause = sync_trap_request ?
                            head_exception_cause : interrupt_cause;
    assign csr_trap_pc = sync_trap_request ?
                         head_exception_pc : interrupt_pc;
    assign csr_trap_tval = sync_trap_request ?
                           head_exception_tval : '0;

    assign trap_fire = csr_trap_valid && csr_trap_ready;
    assign sync_trap_fire = trap_fire && sync_trap_request;
    assign interrupt_take = trap_fire && interrupt_request;
    assign external_recover_valid = sync_trap_fire || mret_fire;
    assign external_recover_pc = sync_trap_fire ?
                                 trap_vector_pc : csr_mret_pc;

    assign recover_valid = dispatch_recover_valid || interrupt_take;
    assign recover_redirect_pc = interrupt_take ?
                                 trap_vector_pc : dispatch_recover_pc;
    assign recover_flush = dispatch_recover_flush || interrupt_take;
    assign recovery_busy = dispatch_recovery_busy;
    assign global_flush = recover_flush;

    assign arb_wb_ready = !dispatch_recovery_busy;
    assign writeback_valid = arb_wb_valid && arb_wb_ready &&
                             arb_wb_write_rd && !arb_wb_exception;
    assign writeback_phys_rd = arb_wb_phys_rd;
    assign writeback_data = arb_wb_data;

    assign bp_update_valid = alu_wb_valid && alu_wb_ready &&
                             alu_meta_is_control && !alu_wb_exception;
    assign bp_update_is_branch = alu_meta_is_control;
    assign bp_update_pc = alu_meta_pc;
    assign bp_update_taken = alu_wb_branch_taken;
    assign bp_update_target = alu_wb_actual_target;

    assign retire_fire = commit_valid && commit_ready &&
                         (!commit_store_valid || commit_store_ready);
    assign retire_valid = retire_fire;

    always_ff @(posedge ACLK or negedge ARESETn) begin
        if (!ARESETn) begin
            alu_meta_is_control <= 1'b0;
            alu_meta_pc <= '0;
        end
        else if (global_flush) begin
            alu_meta_is_control <= 1'b0;
        end
        else if (alu_issue_valid && alu_issue_ready) begin
            alu_meta_is_control <= int_issue_is_branch ||
                                   int_issue_is_jal ||
                                   int_issue_is_jalr;
            alu_meta_pc <= int_issue_pc;
        end
    end

    always_ff @(posedge ACLK or negedge ARESETn) begin
        if (!ARESETn) begin
            csr_meta_rob_tag <= '0;
            csr_meta_phys_rd <= '0;
            csr_meta_write_rd <= 1'b0;
            csr_meta_inst <= '0;
        end
        else if (csr_req_valid && csr_req_ready) begin
            csr_meta_rob_tag <= int_issue_rob_tag;
            csr_meta_phys_rd <= int_issue_phys_rd;
            csr_meta_write_rd <= int_issue_write_rd;
            csr_meta_inst <= int_issue_inst;
        end
    end

    ooo_backend_dispatch #(
        .WIDTH_INST(WIDTH_INST),
        .ADDR_WIDTH(ADDR_WIDTH),
        .DATA_WIDTH(DATA_WIDTH),
        .ARCH_REGS(ARCH_REGS),
        .PHYS_REGS(PHYS_REGS),
        .ROB_ENTRIES(ROB_ENTRIES),
        .IQ_ENTRIES(IQ_ENTRIES),
        .LSQ_ENTRIES(LSQ_ENTRIES)
    ) u_dispatch (
        .ACLK(ACLK),
        .ARESETn(ARESETn),
        .dispatch_valid(dispatch_valid && !interrupt_take),
        .dispatch_ready(dispatch_ready_internal),
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
        .issue_valid(int_issue_valid),
        .issue_ready(int_issue_ready),
        .issue_rob_tag(int_issue_rob_tag),
        .issue_pc(int_issue_pc),
        .issue_inst(int_issue_inst),
        .issue_opcode(int_issue_opcode),
        .issue_funct3(int_issue_funct3),
        .issue_funct7(int_issue_funct7),
        .issue_imm(int_issue_imm),
        .issue_phys_rs1(int_issue_phys_rs1),
        .issue_phys_rs2(int_issue_phys_rs2),
        .issue_phys_rd(int_issue_phys_rd),
        .issue_use_rs1(int_issue_use_rs1),
        .issue_use_rs2(int_issue_use_rs2),
        .issue_write_rd(int_issue_write_rd),
        .issue_is_branch(int_issue_is_branch),
        .issue_is_jal(int_issue_is_jal),
        .issue_is_jalr(int_issue_is_jalr),
        .issue_is_system(int_issue_is_system),
        .issue_pred_taken(int_issue_pred_taken),
        .issue_pred_target(int_issue_pred_target),
        .ls_issue_valid(ls_issue_valid),
        .ls_issue_ready(ls_issue_ready),
        .ls_issue_rob_tag(ls_issue_rob_tag),
        .ls_issue_pc(ls_issue_pc),
        .ls_issue_inst(ls_issue_inst),
        .ls_issue_funct3(ls_issue_funct3),
        .ls_issue_imm(ls_issue_imm),
        .ls_issue_phys_rs1(ls_issue_phys_rs1),
        .ls_issue_phys_rs2(ls_issue_phys_rs2),
        .ls_issue_phys_rd(ls_issue_phys_rd),
        .ls_issue_is_load(ls_issue_is_load),
        .ls_issue_is_store(ls_issue_is_store),
        .writeback_valid(arb_wb_valid && arb_wb_ready),
        .writeback_rob_tag(arb_wb_rob_tag),
        .writeback_phys_rd(arb_wb_phys_rd),
        .writeback_write_rd(arb_wb_write_rd),
        .writeback_actual_target(arb_wb_actual_target),
        .writeback_branch_taken(arb_wb_branch_taken),
        .writeback_exception(arb_wb_exception),
        .writeback_exception_cause(arb_wb_exception_cause),
        .writeback_exception_tval(arb_wb_exception_tval),
        .commit_valid(commit_valid),
        .commit_ready(commit_ready),
        .commit_store_ready(commit_store_ready),
        .commit_rob_tag(commit_rob_tag),
        .commit_pc(commit_pc),
        .commit_inst(commit_inst),
        .commit_arch_rd(commit_arch_rd),
        .commit_phys_rd(commit_phys_rd),
        .commit_write_rd(commit_write_rd),
        .commit_free_valid(commit_free_valid),
        .commit_free_tag(commit_free_tag),
        .commit_store_valid(commit_store_valid),
        .commit_store_rob_tag(commit_store_rob_tag),
        .head_exception_valid(head_exception_valid),
        .head_exception_cause(head_exception_cause),
        .head_exception_pc(head_exception_pc),
        .head_exception_tval(head_exception_tval),
        .recover_valid(dispatch_recover_valid),
        .recover_redirect_pc(dispatch_recover_pc),
        .recover_map_valid(recover_map_valid),
        .recover_arch_rd(recover_arch_rd),
        .recover_phys_rd(recover_phys_rd),
        .recover_free_valid(recover_free_valid),
        .recover_free_tag(recover_free_tag),
        .recover_flush(dispatch_recover_flush),
        .recovery_busy(dispatch_recovery_busy),
        .external_recover_valid(external_recover_valid),
        .external_recover_pc(external_recover_pc),
        .rob_empty(rob_empty),
        .rob_full(rob_full),
        .rob_head_tag(rob_head_tag),
        .iq_full(iq_full),
        .lsq_full(lsq_full)
    );

    physical_register_file #(
        .DATA_WIDTH(DATA_WIDTH),
        .PHYS_REGS(PHYS_REGS)
    ) u_prf (
        .ACLK(ACLK),
        .ARESETn(ARESETn),
        .read_rs1_tag(prf_rs1_tag),
        .read_rs2_tag(prf_rs2_tag),
        .read_rs1_data(prf_rs1_data),
        .read_rs2_data(prf_rs2_data),
        .writeback_valid(writeback_valid),
        .writeback_tag(writeback_phys_rd),
        .writeback_data(writeback_data)
    );

    integer_execute #(
        .DATA_WIDTH(DATA_WIDTH),
        .ADDR_WIDTH(ADDR_WIDTH),
        .WIDTH_INST(WIDTH_INST),
        .PHYS_REGS(PHYS_REGS),
        .ROB_ENTRIES(ROB_ENTRIES)
    ) u_integer_execute (
        .ACLK(ACLK),
        .ARESETn(ARESETn),
        .flush_valid(global_flush),
        .issue_valid(alu_issue_valid),
        .issue_ready(alu_issue_ready),
        .issue_rob_tag(int_issue_rob_tag),
        .issue_pc(int_issue_pc),
        .issue_inst(int_issue_inst),
        .issue_opcode(int_issue_opcode),
        .issue_funct3(int_issue_funct3),
        .issue_funct7(int_issue_funct7),
        .issue_imm(int_issue_imm),
        .issue_phys_rd(int_issue_phys_rd),
        .issue_write_rd(int_issue_write_rd),
        .issue_rs1_data(prf_rs1_data),
        .issue_rs2_data(prf_rs2_data),
        .wb_valid(alu_wb_valid),
        .wb_ready(alu_wb_ready),
        .wb_rob_tag(alu_wb_rob_tag),
        .wb_phys_rd(alu_wb_phys_rd),
        .wb_write_rd(alu_wb_write_rd),
        .wb_data(alu_wb_data),
        .wb_branch_taken(alu_wb_branch_taken),
        .wb_actual_target(alu_wb_actual_target),
        .wb_exception(alu_wb_exception),
        .wb_exception_cause(alu_wb_exception_cause),
        .wb_exception_tval(alu_wb_exception_tval)
    );

    lsu #(
        .DATA_WIDTH(DATA_WIDTH),
        .ADDR_WIDTH(ADDR_WIDTH),
        .PHYS_REGS(PHYS_REGS),
        .ROB_ENTRIES(ROB_ENTRIES),
        .STORE_BUFFER_DEPTH(STORE_BUFFER_DEPTH),
        .LOAD_QUEUE_DEPTH(LOAD_QUEUE_DEPTH),
        .COMPLETION_QUEUE_DEPTH(COMPLETION_QUEUE_DEPTH),
        .MEM_ID_WIDTH(MEM_ID_WIDTH)
    ) u_lsu (
        .ACLK(ACLK),
        .ARESETn(ARESETn),
        .flush_valid(global_flush),
        .issue_valid(ls_issue_valid && select_memory),
        .issue_ready(lsu_issue_ready),
        .issue_rob_tag(ls_issue_rob_tag),
        .issue_inst(ls_issue_inst),
        .issue_funct3(ls_issue_funct3),
        .issue_imm(ls_issue_imm),
        .issue_phys_rd(ls_issue_phys_rd),
        .issue_is_load(ls_issue_is_load),
        .issue_is_store(ls_issue_is_store),
        .issue_base_data(prf_rs1_data),
        .issue_store_data(prf_rs2_data),
        .commit_store_valid(commit_store_valid && commit_ready),
        .commit_store_rob_tag(commit_store_rob_tag),
        .commit_store_ready(commit_store_ready),
        .mem_req_valid(mem_req_valid),
        .mem_req_ready(mem_req_ready),
        .mem_req_write(mem_req_write),
        .mem_req_addr(mem_req_addr),
        .mem_req_wdata(mem_req_wdata),
        .mem_req_wstrb(mem_req_wstrb),
        .mem_req_id(mem_req_id),
        .mem_resp_valid(mem_resp_valid),
        .mem_resp_ready(mem_resp_ready),
        .mem_resp_rdata(mem_resp_rdata),
        .mem_resp_error(mem_resp_error),
        .mem_resp_id(mem_resp_id),
        .wb_valid(lsu_wb_valid),
        .wb_ready(lsu_wb_ready),
        .wb_rob_tag(lsu_wb_rob_tag),
        .wb_phys_rd(lsu_wb_phys_rd),
        .wb_write_rd(lsu_wb_write_rd),
        .wb_data(lsu_wb_data),
        .wb_exception(lsu_wb_exception),
        .wb_exception_cause(lsu_wb_exception_cause),
        .wb_exception_tval(lsu_wb_exception_tval)
    );

    machine_csr #(
        .XLEN(DATA_WIDTH),
        .CAUSE_CODE_WIDTH(EXC_CAUSE_WIDTH),
        .RESET_MTVEC(RESET_MTVEC)
    ) u_machine_csr (
        .ACLK(ACLK),
        .ARESETn(ARESETn),
        .csr_req_valid(csr_req_valid),
        .csr_req_ready(csr_req_ready),
        .csr_req_inst(int_issue_inst),
        .csr_req_rs1_data(prf_rs1_data),
        .csr_resp_valid(csr_resp_valid),
        .csr_resp_ready(csr_resp_ready),
        .csr_resp_rdata(csr_resp_rdata),
        .csr_resp_illegal(csr_resp_illegal),
        .trap_valid(csr_trap_valid),
        .trap_ready(csr_trap_ready),
        .trap_is_interrupt(csr_trap_is_interrupt),
        .trap_cause_code(csr_trap_cause),
        .trap_pc(csr_trap_pc),
        .trap_tval(csr_trap_tval),
        .mret_valid(csr_mret_valid),
        .mret_ready(csr_mret_ready),
        .mret_pc(csr_mret_pc),
        .irq_software(irq_software),
        .irq_timer(irq_timer),
        .irq_external(irq_external),
        .interrupt_pending(interrupt_pending),
        .interrupt_cause_code(interrupt_cause),
        .retire_valid(retire_fire || mret_fire),
        .trap_vector_pc(trap_vector_pc),
        .csr_mstatus(csr_mstatus),
        .csr_mie(csr_mie),
        .csr_mip(csr_mip),
        .csr_mtvec(csr_mtvec),
        .csr_mepc(csr_mepc),
        .csr_mcause(csr_mcause),
        .csr_mtval(csr_mtval)
    );

    assign csr_resp_ready = csr_wb_ready;

    writeback_arbiter #(
        .DATA_WIDTH(DATA_WIDTH),
        .ADDR_WIDTH(ADDR_WIDTH),
        .PHYS_REGS(PHYS_REGS),
        .ROB_ENTRIES(ROB_ENTRIES)
    ) u_writeback_arbiter (
        .alu_valid(alu_wb_valid),
        .alu_ready(alu_wb_ready),
        .alu_rob_tag(alu_wb_rob_tag),
        .alu_phys_rd(alu_wb_phys_rd),
        .alu_write_rd(alu_wb_write_rd),
        .alu_data(alu_wb_data),
        .alu_branch_taken(alu_wb_branch_taken),
        .alu_actual_target(alu_wb_actual_target),
        .alu_exception(alu_wb_exception),
        .alu_exception_cause(alu_wb_exception_cause),
        .alu_exception_tval(alu_wb_exception_tval),
        .lsu_valid(lsu_wb_valid),
        .lsu_ready(lsu_wb_ready),
        .lsu_rob_tag(lsu_wb_rob_tag),
        .lsu_phys_rd(lsu_wb_phys_rd),
        .lsu_write_rd(lsu_wb_write_rd),
        .lsu_data(lsu_wb_data),
        .lsu_exception(lsu_wb_exception),
        .lsu_exception_cause(lsu_wb_exception_cause),
        .lsu_exception_tval(lsu_wb_exception_tval),
        .csr_valid(csr_resp_valid),
        .csr_ready(csr_wb_ready),
        .csr_rob_tag(csr_meta_rob_tag),
        .csr_phys_rd(csr_meta_phys_rd),
        .csr_write_rd(csr_meta_write_rd && !csr_resp_illegal),
        .csr_data(csr_resp_rdata),
        .csr_exception(csr_resp_illegal),
        .csr_exception_cause(5'd2),
        .csr_exception_tval(csr_meta_inst),
        .wb_valid(arb_wb_valid),
        .wb_ready(arb_wb_ready),
        .wb_rob_tag(arb_wb_rob_tag),
        .wb_phys_rd(arb_wb_phys_rd),
        .wb_write_rd(arb_wb_write_rd),
        .wb_data(arb_wb_data),
        .wb_branch_taken(arb_wb_branch_taken),
        .wb_actual_target(arb_wb_actual_target),
        .wb_exception(arb_wb_exception),
        .wb_exception_cause(arb_wb_exception_cause),
        .wb_exception_tval(arb_wb_exception_tval)
    );
endmodule
