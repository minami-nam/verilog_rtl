module ooo_backend_dispatch #(
    parameter int unsigned WIDTH_INST = 32,
    parameter int unsigned ADDR_WIDTH = 32,
    parameter int unsigned DATA_WIDTH = 32,
    parameter int unsigned ARCH_REGS = 32,
    parameter int unsigned PHYS_REGS = 64,
    parameter int unsigned ROB_ENTRIES = 32,
    parameter int unsigned IQ_ENTRIES = 16,
    parameter int unsigned LSQ_ENTRIES = 16,

    localparam int unsigned ARCH_TAG_WIDTH = (ARCH_REGS <= 1) ? 1 : $clog2(ARCH_REGS),
    localparam int unsigned PHYS_TAG_WIDTH = (PHYS_REGS <= 1) ? 1 : $clog2(PHYS_REGS),
    localparam int unsigned ROB_TAG_WIDTH = (ROB_ENTRIES <= 1) ? 1 : $clog2(ROB_ENTRIES),
    localparam int unsigned DATA_STRB_WIDTH = DATA_WIDTH / 8,
    localparam int unsigned EXC_CAUSE_WIDTH = 5
) (
    input  logic                        ACLK,
    input  logic                        ARESETn,

    // Packet from ID/Rename stage
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

    // Issue to execute stage
    output logic                        issue_valid,
    input  logic                        issue_ready,
    output logic [ROB_TAG_WIDTH-1:0]    issue_rob_tag,
    output logic [ADDR_WIDTH-1:0]       issue_pc,
    output logic [WIDTH_INST-1:0]       issue_inst,
    output logic [6:0]                  issue_opcode,
    output logic [2:0]                  issue_funct3,
    output logic [6:0]                  issue_funct7,
    output logic [31:0]                 issue_imm,
    output logic [PHYS_TAG_WIDTH-1:0]   issue_phys_rs1,
    output logic [PHYS_TAG_WIDTH-1:0]   issue_phys_rs2,
    output logic [PHYS_TAG_WIDTH-1:0]   issue_phys_rd,
    output logic                        issue_use_rs1,
    output logic                        issue_use_rs2,
    output logic                        issue_write_rd,
    output logic                        issue_is_branch,
    output logic                        issue_is_jal,
    output logic                        issue_is_jalr,
    output logic                        issue_is_system,
    output logic                        issue_pred_taken,
    output logic [ADDR_WIDTH-1:0]       issue_pred_target,

    // Ordered load/store issue to a later LSU stage
    output logic                        ls_issue_valid,
    input  logic                        ls_issue_ready,
    output logic [ROB_TAG_WIDTH-1:0]    ls_issue_rob_tag,
    output logic [ADDR_WIDTH-1:0]       ls_issue_pc,
    output logic [WIDTH_INST-1:0]       ls_issue_inst,
    output logic [2:0]                  ls_issue_funct3,
    output logic [31:0]                 ls_issue_imm,
    output logic [PHYS_TAG_WIDTH-1:0]   ls_issue_phys_rs1,
    output logic [PHYS_TAG_WIDTH-1:0]   ls_issue_phys_rs2,
    output logic [PHYS_TAG_WIDTH-1:0]   ls_issue_phys_rd,
    output logic                        ls_issue_is_load,
    output logic                        ls_issue_is_store,

    // Writeback/common-data bus
    input  logic                        writeback_valid,
    input  logic [ROB_TAG_WIDTH-1:0]    writeback_rob_tag,
    input  logic [PHYS_TAG_WIDTH-1:0]   writeback_phys_rd,
    input  logic                        writeback_write_rd,
    input  logic [ADDR_WIDTH-1:0]       writeback_actual_target,
    input  logic                        writeback_branch_taken,
    input  logic                        writeback_exception,
    input  logic [EXC_CAUSE_WIDTH-1:0] writeback_exception_cause,
    input  logic [ADDR_WIDTH-1:0]       writeback_exception_tval,

    // Commit and physical register lifecycle
    output logic                        commit_valid,
    input  logic                        commit_ready,
    input  logic                        commit_store_ready,
    output logic [ROB_TAG_WIDTH-1:0]    commit_rob_tag,
    output logic [ADDR_WIDTH-1:0]       commit_pc,
    output logic [WIDTH_INST-1:0]      commit_inst,
    output logic [ARCH_TAG_WIDTH-1:0]   commit_arch_rd,
    output logic [PHYS_TAG_WIDTH-1:0]   commit_phys_rd,
    output logic                        commit_write_rd,
    output logic                        commit_free_valid,
    output logic [PHYS_TAG_WIDTH-1:0]   commit_free_tag,
    output logic                        commit_store_valid,
    output logic [ROB_TAG_WIDTH-1:0]    commit_store_rob_tag,

    // Precise exception for CSR/Exception Recovery
    output logic                        head_exception_valid,
    output logic [EXC_CAUSE_WIDTH-1:0] head_exception_cause,
    output logic [ADDR_WIDTH-1:0]       head_exception_pc,
    output logic [ADDR_WIDTH-1:0]       head_exception_tval,

    // Recovery back to frontend / rename map
    output logic                        recover_valid,
    output logic [ADDR_WIDTH-1:0]       recover_redirect_pc,
    output logic                        recover_map_valid,
    output logic [ARCH_TAG_WIDTH-1:0]   recover_arch_rd,
    output logic [PHYS_TAG_WIDTH-1:0]   recover_phys_rd,
    output logic                        recover_free_valid,
    output logic [PHYS_TAG_WIDTH-1:0]   recover_free_tag,
    output logic                        recover_flush,
    output logic                        recovery_busy,

    input  logic                        external_recover_valid,
    input  logic [ADDR_WIDTH-1:0]       external_recover_pc,

    output logic                        rob_empty,
    output logic                        rob_full,
    output logic [ROB_TAG_WIDTH-1:0]    rob_head_tag,
    output logic                        iq_full,
    output logic                        lsq_full
);

    logic dispatch_is_memory;
    logic dispatch_needs_queue;
    logic dispatch_exception;
    logic dispatch_fire;
    logic rob_alloc_ready;
    logic rob_alloc_valid;
    logic [ROB_TAG_WIDTH-1:0] rob_alloc_tag;
    logic iq_empty;
    logic lsq_empty;
    logic iq_enqueue_ready;
    logic lsq_enqueue_ready;
    logic commit_is_store;
    logic [PHYS_TAG_WIDTH-1:0] commit_old_phys_rd;
    logic queue_wakeup_valid;

    assign dispatch_is_memory = dispatch_is_load || dispatch_is_store;
    assign dispatch_exception = dispatch_illegal_inst || (dispatch_if_status != 2'b00);
    assign dispatch_needs_queue = !dispatch_exception;
    assign dispatch_ready =
        !recovery_busy &&
        rob_alloc_ready &&
        (!dispatch_needs_queue ||
         (dispatch_is_memory ? lsq_enqueue_ready : iq_enqueue_ready));
    assign dispatch_fire = dispatch_valid && dispatch_ready;
    assign queue_wakeup_valid = writeback_valid && writeback_write_rd &&
                                !writeback_exception;

    logic rob_commit_ready;

    assign rob_commit_ready = commit_ready &&
                              (!commit_is_store || commit_store_ready);
    assign commit_store_valid = commit_valid && commit_is_store;
    assign commit_store_rob_tag = commit_rob_tag;

    rob_allocator #(
        .WIDTH_INST  (WIDTH_INST),
        .ADDR_WIDTH  (ADDR_WIDTH),
        .ARCH_REGS   (ARCH_REGS),
        .PHYS_REGS   (PHYS_REGS),
        .ROB_ENTRIES (ROB_ENTRIES),
        .LQ_DEPTH    (LSQ_ENTRIES),
        .SQ_DEPTH    (LSQ_ENTRIES)
    ) u_rob_allocator (
        .ACLK                    (ACLK),
        .ARESETn                 (ARESETn),
        .alloc_valid             (dispatch_fire),
        .alloc_ready             (rob_alloc_ready),
        .alloc_pc                (dispatch_pc),
        .alloc_inst              (dispatch_inst),
        .alloc_arch_rd           (dispatch_arch_rd),
        .alloc_phys_rd           (dispatch_phys_rd),
        .alloc_old_phys_rd       (dispatch_old_phys_rd),
        .alloc_write_rd          (dispatch_write_rd),
        .alloc_is_branch         (dispatch_is_branch),
        .alloc_is_jal            (dispatch_is_jal),
        .alloc_is_jalr           (dispatch_is_jalr),
        .alloc_pred_taken        (dispatch_pred_taken),
        .alloc_pred_target       (dispatch_pred_target),
        .alloc_illegal_inst      (dispatch_illegal_inst),
        .alloc_if_status         (dispatch_if_status),
        .alloc_rob_valid         (rob_alloc_valid),
        .alloc_rob_tag           (rob_alloc_tag),
        .complete_valid          (writeback_valid),
        .complete_rob_tag        (writeback_rob_tag),
        .complete_actual_target  (writeback_actual_target),
        .complete_branch_taken   (writeback_branch_taken),
        .complete_exception      (writeback_exception),
        .complete_exception_cause(writeback_exception_cause),
        .complete_exception_tval (writeback_exception_tval),
        .commit_valid            (commit_valid),
        .commit_ready            (rob_commit_ready),
        .commit_rob_tag          (commit_rob_tag),
        .commit_pc               (commit_pc),
        .commit_inst             (commit_inst),
        .commit_arch_rd          (commit_arch_rd),
        .commit_phys_rd          (commit_phys_rd),
        .commit_old_phys_rd      (commit_old_phys_rd),
        .commit_is_store         (commit_is_store),
        .commit_write_rd         (commit_write_rd),
        .commit_free_valid       (commit_free_valid),
        .commit_free_tag         (commit_free_tag),
        .head_exception_valid    (head_exception_valid),
        .head_exception_cause    (head_exception_cause),
        .head_exception_pc       (head_exception_pc),
        .head_exception_tval     (head_exception_tval),
        .recover_valid           (recover_valid),
        .recover_redirect_pc     (recover_redirect_pc),
        .recover_map_valid       (recover_map_valid),
        .recover_arch_rd         (recover_arch_rd),
        .recover_phys_rd         (recover_phys_rd),
        .recover_free_valid      (recover_free_valid),
        .recover_free_tag        (recover_free_tag),
        .recover_flush           (recover_flush),
        .recovery_busy           (recovery_busy),
        .external_recover_valid  (external_recover_valid),
        .external_recover_pc     (external_recover_pc),
        .rob_empty               (rob_empty),
        .rob_full                (rob_full),
        .rob_head_tag            (rob_head_tag)
    );

    issue_queue #(
        .WIDTH_INST  (WIDTH_INST),
        .ADDR_WIDTH  (ADDR_WIDTH),
        .ARCH_REGS   (ARCH_REGS),
        .PHYS_REGS   (PHYS_REGS),
        .ROB_ENTRIES (ROB_ENTRIES),
        .IQ_ENTRIES  (IQ_ENTRIES)
    ) u_issue_queue (
        .ACLK                    (ACLK),
        .ARESETn                 (ARESETn),
        .enqueue_valid           (dispatch_fire &&
                                  dispatch_needs_queue &&
                                  !dispatch_is_memory),
        .enqueue_ready           (iq_enqueue_ready),
        .enqueue_rob_tag         (rob_alloc_tag),
        .enqueue_pc              (dispatch_pc),
        .enqueue_inst            (dispatch_inst),
        .enqueue_opcode          (dispatch_opcode),
        .enqueue_funct3          (dispatch_funct3),
        .enqueue_funct7          (dispatch_funct7),
        .enqueue_imm             (dispatch_imm),
        .enqueue_arch_rs1        (dispatch_arch_rs1),
        .enqueue_arch_rs2        (dispatch_arch_rs2),
        .enqueue_arch_rd         (dispatch_arch_rd),
        .enqueue_phys_rs1        (dispatch_phys_rs1),
        .enqueue_phys_rs2        (dispatch_phys_rs2),
        .enqueue_phys_rd         (dispatch_phys_rd),
        .enqueue_rs1_ready       (dispatch_rs1_ready),
        .enqueue_rs2_ready       (dispatch_rs2_ready),
        .enqueue_use_rs1         (dispatch_use_rs1),
        .enqueue_use_rs2         (dispatch_use_rs2),
        .enqueue_write_rd        (dispatch_write_rd),
        .enqueue_is_alu          (dispatch_is_alu),
        .enqueue_is_branch       (dispatch_is_branch),
        .enqueue_is_jal          (dispatch_is_jal),
        .enqueue_is_jalr         (dispatch_is_jalr),
        .enqueue_is_lui          (dispatch_is_lui),
        .enqueue_is_auipc        (dispatch_is_auipc),
        .enqueue_is_system       (dispatch_is_system),
        .enqueue_pred_taken      (dispatch_pred_taken),
        .enqueue_pred_target     (dispatch_pred_target),
        .wakeup_valid            (queue_wakeup_valid),
        .wakeup_phys_rd          (writeback_phys_rd),
        .issue_valid             (issue_valid),
        .issue_ready             (issue_ready),
        .issue_rob_tag           (issue_rob_tag),
        .issue_pc                (issue_pc),
        .issue_inst              (issue_inst),
        .issue_opcode            (issue_opcode),
        .issue_funct3            (issue_funct3),
        .issue_funct7            (issue_funct7),
        .issue_imm               (issue_imm),
        .issue_phys_rs1          (issue_phys_rs1),
        .issue_phys_rs2          (issue_phys_rs2),
        .issue_phys_rd           (issue_phys_rd),
        .issue_use_rs1           (issue_use_rs1),
        .issue_use_rs2           (issue_use_rs2),
        .issue_write_rd          (issue_write_rd),
        .issue_is_branch         (issue_is_branch),
        .issue_is_jal            (issue_is_jal),
        .issue_is_jalr           (issue_is_jalr),
        .issue_is_system         (issue_is_system),
        .issue_pred_taken        (issue_pred_taken),
        .issue_pred_target       (issue_pred_target),
        .flush_valid             (recover_flush),
        .rob_head_tag            (rob_head_tag),
        .iq_empty                (iq_empty),
        .iq_full                 (iq_full)
    );

    ldst_queue #(
        .WIDTH_INST  (WIDTH_INST),
        .ADDR_WIDTH  (ADDR_WIDTH),
        .DATA_WIDTH  (DATA_WIDTH),
        .ARCH_REGS   (ARCH_REGS),
        .PHYS_REGS   (PHYS_REGS),
        .ROB_ENTRIES (ROB_ENTRIES),
        .LSQ_ENTRIES (LSQ_ENTRIES)
    ) u_ldst_queue (
        .ACLK                    (ACLK),
        .ARESETn                 (ARESETn),
        .enqueue_valid           (dispatch_fire &&
                                  dispatch_needs_queue &&
                                  dispatch_is_memory),
        .enqueue_ready           (lsq_enqueue_ready),
        .enqueue_rob_tag         (rob_alloc_tag),
        .enqueue_pc              (dispatch_pc),
        .enqueue_inst            (dispatch_inst),
        .enqueue_funct3          (dispatch_funct3),
        .enqueue_imm             (dispatch_imm),
        .enqueue_arch_rs1        (dispatch_arch_rs1),
        .enqueue_arch_rs2        (dispatch_arch_rs2),
        .enqueue_arch_rd         (dispatch_arch_rd),
        .enqueue_phys_rs1        (dispatch_phys_rs1),
        .enqueue_phys_rs2        (dispatch_phys_rs2),
        .enqueue_phys_rd         (dispatch_phys_rd),
        .enqueue_rs1_ready       (dispatch_rs1_ready),
        .enqueue_rs2_ready       (dispatch_rs2_ready),
        .enqueue_is_load         (dispatch_is_load),
        .enqueue_is_store        (dispatch_is_store),
        .wakeup_valid            (queue_wakeup_valid),
        .wakeup_phys_rd          (writeback_phys_rd),
        .ls_issue_valid          (ls_issue_valid),
        .ls_issue_ready          (ls_issue_ready),
        .ls_issue_rob_tag        (ls_issue_rob_tag),
        .ls_issue_pc             (ls_issue_pc),
        .ls_issue_inst           (ls_issue_inst),
        .ls_issue_funct3         (ls_issue_funct3),
        .ls_issue_imm            (ls_issue_imm),
        .ls_issue_phys_rs1       (ls_issue_phys_rs1),
        .ls_issue_phys_rs2       (ls_issue_phys_rs2),
        .ls_issue_phys_rd        (ls_issue_phys_rd),
        .ls_issue_is_load        (ls_issue_is_load),
        .ls_issue_is_store       (ls_issue_is_store),
        .flush_valid             (recover_flush),
        .lsq_empty               (lsq_empty),
        .lsq_full                (lsq_full)
    );
endmodule
