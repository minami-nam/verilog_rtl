module ldst_queue #(
    parameter int unsigned WIDTH_INST = 32,
    parameter int unsigned ADDR_WIDTH = 32,
    parameter int unsigned DATA_WIDTH = 32,
    parameter int unsigned ARCH_REGS = 32,
    parameter int unsigned PHYS_REGS = 64,
    parameter int unsigned ROB_ENTRIES = 32,
    parameter int unsigned LSQ_ENTRIES = 16,

    localparam int unsigned ARCH_TAG_WIDTH = (ARCH_REGS <= 1) ? 1 : $clog2(ARCH_REGS),
    localparam int unsigned PHYS_TAG_WIDTH = (PHYS_REGS <= 1) ? 1 : $clog2(PHYS_REGS),
    localparam int unsigned ROB_TAG_WIDTH = (ROB_ENTRIES <= 1) ? 1 : $clog2(ROB_ENTRIES),
    localparam int unsigned DATA_STRB_WIDTH = DATA_WIDTH / 8
) (
    input  logic                        ACLK,
    input  logic                        ARESETn,

    // Dispatch enqueue for load/store uops
    input  logic                        enqueue_valid,
    output logic                        enqueue_ready,
    input  logic [ROB_TAG_WIDTH-1:0]    enqueue_rob_tag,
    input  logic [ADDR_WIDTH-1:0]       enqueue_pc,
    input  logic [WIDTH_INST-1:0]       enqueue_inst,
    input  logic [2:0]                  enqueue_funct3,
    input  logic [31:0]                 enqueue_imm,
    input  logic [ARCH_TAG_WIDTH-1:0]   enqueue_arch_rs1,
    input  logic [ARCH_TAG_WIDTH-1:0]   enqueue_arch_rs2,
    input  logic [ARCH_TAG_WIDTH-1:0]   enqueue_arch_rd,
    input  logic [PHYS_TAG_WIDTH-1:0]   enqueue_phys_rs1,
    input  logic [PHYS_TAG_WIDTH-1:0]   enqueue_phys_rs2,
    input  logic [PHYS_TAG_WIDTH-1:0]   enqueue_phys_rd,
    input  logic                        enqueue_rs1_ready,
    input  logic                        enqueue_rs2_ready,
    input  logic                        enqueue_is_load,
    input  logic                        enqueue_is_store,

    // Wakeup from writeback/common-data bus
    input  logic                        wakeup_valid,
    input  logic [PHYS_TAG_WIDTH-1:0]   wakeup_phys_rd,

    // Ordered issue to a later LSU/address-generation stage
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

    input  logic                        flush_valid,
    output logic                        lsq_empty,
    output logic                        lsq_full
);

    localparam int unsigned LSQ_IDX_WIDTH =
        (LSQ_ENTRIES <= 1) ? 1 : $clog2(LSQ_ENTRIES);
    localparam int unsigned LSQ_COUNT_WIDTH =
        (LSQ_ENTRIES <= 1) ? 1 : $clog2(LSQ_ENTRIES + 1);

    typedef struct packed {
        logic                         valid;
        logic [ROB_TAG_WIDTH-1:0]     rob_tag;
        logic [ADDR_WIDTH-1:0]        pc;
        logic [WIDTH_INST-1:0]        inst;
        logic [2:0]                   funct3;
        logic [31:0]                  imm;
        logic [PHYS_TAG_WIDTH-1:0]    phys_rs1;
        logic [PHYS_TAG_WIDTH-1:0]    phys_rs2;
        logic [PHYS_TAG_WIDTH-1:0]    phys_rd;
        logic                         rs1_ready;
        logic                         rs2_ready;
        logic                         is_load;
        logic                         is_store;
    } ldst_queue_entry_t;

    ldst_queue_entry_t lsq_entry [0:LSQ_ENTRIES-1];
    logic [LSQ_IDX_WIDTH-1:0] lsq_head;
    logic [LSQ_IDX_WIDTH-1:0] lsq_tail;
    logic [LSQ_COUNT_WIDTH-1:0] lsq_count;
    logic enqueue_fire;
    logic issue_fire;
    logic head_ready;

    assign lsq_empty = (lsq_count == '0);
    assign lsq_full = (lsq_count == LSQ_ENTRIES);
    assign enqueue_ready = !lsq_full && !flush_valid;
    assign enqueue_fire = enqueue_valid && enqueue_ready;

    assign head_ready = !lsq_empty &&
                        lsq_entry[lsq_head].valid &&
                        lsq_entry[lsq_head].rs1_ready &&
                        (!lsq_entry[lsq_head].is_store ||
                         lsq_entry[lsq_head].rs2_ready);
    assign ls_issue_valid = head_ready && !flush_valid;
    assign issue_fire = ls_issue_valid && ls_issue_ready;

    assign ls_issue_rob_tag = lsq_entry[lsq_head].rob_tag;
    assign ls_issue_pc = lsq_entry[lsq_head].pc;
    assign ls_issue_inst = lsq_entry[lsq_head].inst;
    assign ls_issue_funct3 = lsq_entry[lsq_head].funct3;
    assign ls_issue_imm = lsq_entry[lsq_head].imm;
    assign ls_issue_phys_rs1 = lsq_entry[lsq_head].phys_rs1;
    assign ls_issue_phys_rs2 = lsq_entry[lsq_head].phys_rs2;
    assign ls_issue_phys_rd = lsq_entry[lsq_head].phys_rd;
    assign ls_issue_is_load = lsq_entry[lsq_head].is_load;
    assign ls_issue_is_store = lsq_entry[lsq_head].is_store;

    always_ff @(posedge ACLK or negedge ARESETn) begin
        if (!ARESETn) begin
            lsq_head <= '0;
            lsq_tail <= '0;
            lsq_count <= '0;
            for (int i = 0; i < LSQ_ENTRIES; i++) begin
                lsq_entry[i] <= '0;
            end
        end
        else if (flush_valid) begin
            lsq_head <= '0;
            lsq_tail <= '0;
            lsq_count <= '0;
            for (int i = 0; i < LSQ_ENTRIES; i++) begin
                lsq_entry[i].valid <= 1'b0;
            end
        end
        else begin
            if (wakeup_valid) begin
                for (int i = 0; i < LSQ_ENTRIES; i++) begin
                    if (lsq_entry[i].valid) begin
                        if (lsq_entry[i].phys_rs1 == wakeup_phys_rd)
                            lsq_entry[i].rs1_ready <= 1'b1;
                        if (lsq_entry[i].is_store &&
                            (lsq_entry[i].phys_rs2 == wakeup_phys_rd))
                            lsq_entry[i].rs2_ready <= 1'b1;
                    end
                end
            end

            if (enqueue_fire) begin
                lsq_entry[lsq_tail].valid <= 1'b1;
                lsq_entry[lsq_tail].rob_tag <= enqueue_rob_tag;
                lsq_entry[lsq_tail].pc <= enqueue_pc;
                lsq_entry[lsq_tail].inst <= enqueue_inst;
                lsq_entry[lsq_tail].funct3 <= enqueue_funct3;
                lsq_entry[lsq_tail].imm <= enqueue_imm;
                lsq_entry[lsq_tail].phys_rs1 <= enqueue_phys_rs1;
                lsq_entry[lsq_tail].phys_rs2 <= enqueue_phys_rs2;
                lsq_entry[lsq_tail].phys_rd <= enqueue_phys_rd;
                lsq_entry[lsq_tail].rs1_ready <= enqueue_rs1_ready ||
                    (wakeup_valid && (enqueue_phys_rs1 == wakeup_phys_rd));
                lsq_entry[lsq_tail].rs2_ready <= enqueue_rs2_ready ||
                    (wakeup_valid && (enqueue_phys_rs2 == wakeup_phys_rd));
                lsq_entry[lsq_tail].is_load <= enqueue_is_load;
                lsq_entry[lsq_tail].is_store <= enqueue_is_store;

                if (lsq_tail == LSQ_ENTRIES-1)
                    lsq_tail <= '0;
                else
                    lsq_tail <= lsq_tail + 1'b1;
            end

            if (issue_fire) begin
                lsq_entry[lsq_head].valid <= 1'b0;
                if (lsq_head == LSQ_ENTRIES-1)
                    lsq_head <= '0;
                else
                    lsq_head <= lsq_head + 1'b1;
            end

            case ({enqueue_fire, issue_fire})
                2'b01: lsq_count <= lsq_count - 1'b1;
                2'b10: lsq_count <= lsq_count + 1'b1;
                default: lsq_count <= lsq_count;
            endcase
        end
    end
endmodule
