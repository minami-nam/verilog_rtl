module issue_queue #(
    parameter int unsigned WIDTH_INST = 32,
    parameter int unsigned ADDR_WIDTH = 32,
    parameter int unsigned ARCH_REGS = 32,
    parameter int unsigned PHYS_REGS = 64,
    parameter int unsigned ROB_ENTRIES = 32,
    parameter int unsigned IQ_ENTRIES = 16,

    localparam int unsigned ARCH_TAG_WIDTH = (ARCH_REGS <= 1) ? 1 : $clog2(ARCH_REGS),
    localparam int unsigned PHYS_TAG_WIDTH = (PHYS_REGS <= 1) ? 1 : $clog2(PHYS_REGS),
    localparam int unsigned ROB_TAG_WIDTH = (ROB_ENTRIES <= 1) ? 1 : $clog2(ROB_ENTRIES),
    localparam int unsigned IQ_IDX_WIDTH = (IQ_ENTRIES <= 1) ? 1 : $clog2(IQ_ENTRIES),
    localparam int unsigned IQ_COUNT_WIDTH = (IQ_ENTRIES <= 1) ? 1 : $clog2(IQ_ENTRIES + 1)
) (
    input  logic                        ACLK,
    input  logic                        ARESETn,

    // Dispatch enqueue
    input  logic                        enqueue_valid,
    output logic                        enqueue_ready,
    input  logic [ROB_TAG_WIDTH-1:0]    enqueue_rob_tag,
    input  logic [ADDR_WIDTH-1:0]       enqueue_pc,
    input  logic [WIDTH_INST-1:0]       enqueue_inst,
    input  logic [6:0]                  enqueue_opcode,
    input  logic [2:0]                  enqueue_funct3,
    input  logic [6:0]                  enqueue_funct7,
    input  logic [31:0]                 enqueue_imm,
    input  logic [ARCH_TAG_WIDTH-1:0]   enqueue_arch_rs1,
    input  logic [ARCH_TAG_WIDTH-1:0]   enqueue_arch_rs2,
    input  logic [ARCH_TAG_WIDTH-1:0]   enqueue_arch_rd,
    input  logic [PHYS_TAG_WIDTH-1:0]   enqueue_phys_rs1,
    input  logic [PHYS_TAG_WIDTH-1:0]   enqueue_phys_rs2,
    input  logic [PHYS_TAG_WIDTH-1:0]   enqueue_phys_rd,
    input  logic                        enqueue_rs1_ready,
    input  logic                        enqueue_rs2_ready,
    input  logic                        enqueue_use_rs1,
    input  logic                        enqueue_use_rs2,
    input  logic                        enqueue_write_rd,
    input  logic                        enqueue_is_alu,
    input  logic                        enqueue_is_branch,
    input  logic                        enqueue_is_jal,
    input  logic                        enqueue_is_jalr,
    input  logic                        enqueue_is_lui,
    input  logic                        enqueue_is_auipc,
    input  logic                        enqueue_is_system,
    input  logic                        enqueue_pred_taken,
    input  logic [ADDR_WIDTH-1:0]       enqueue_pred_target,

    // Wakeup from writeback/common-data bus
    input  logic                        wakeup_valid,
    input  logic [PHYS_TAG_WIDTH-1:0]   wakeup_phys_rd,

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

    input  logic                        flush_valid,
    input  logic [ROB_TAG_WIDTH-1:0]    rob_head_tag,
    output logic                        iq_empty,
    output logic                        iq_full
);

    // issue entry 선언
    typedef struct packed {
        logic valid;

        logic [ROB_TAG_WIDTH-1:0] rob_tag;
        logic [ADDR_WIDTH-1:0]    pc;
        logic [WIDTH_INST-1:0]    inst;

        logic [PHYS_TAG_WIDTH-1:0] phys_rs1;
        logic [PHYS_TAG_WIDTH-1:0] phys_rs2;
        logic [PHYS_TAG_WIDTH-1:0] phys_rd;

        logic rs1_ready;
        logic rs2_ready;
        logic use_rs1;
        logic use_rs2;

        logic write_rd;
        logic [6:0] opcode;
        logic [2:0] funct3;
        logic [6:0] funct7;
        logic [31:0] imm;
        logic is_branch;
        logic is_jal;
        logic is_jalr;
        logic is_system;
        logic pred_taken;
        logic [ADDR_WIDTH-1:0] pred_target;

    } issue_queue_entry_t;


    issue_queue_entry_t issue_list[0:IQ_ENTRIES-1];
    logic [IQ_ENTRIES-1:0] entry_ready;
    logic [IQ_COUNT_WIDTH-1:0] iq_count;
    logic enqueue_slot_valid;
    logic [IQ_IDX_WIDTH-1:0] enqueue_slot_idx;
    logic issue_select_valid;
    logic [IQ_IDX_WIDTH-1:0] issue_select_idx;
    logic issue_candidate_valid;
    logic [IQ_IDX_WIDTH-1:0] issue_candidate_idx;
    logic enqueue_fire;
    logic issue_fire;


    // 각 entry 별 ready 신호 생성.
    genvar i;
    generate
        for (i=0; i<IQ_ENTRIES; i++) begin : gen_entry_ready
            // list가 valid하고, rs1 , rs2 reg 가 사용되지 않고 준비된 경우에만 ready on
            assign entry_ready[i] = issue_list[i].valid && (!issue_list[i].use_rs1 || issue_list[i].rs1_ready) && (!issue_list[i].use_rs2 || issue_list[i].rs2_ready);
    
        end     
    endgenerate



    // writeback이 발생하는 경우, entry tag 별 Register 1, 2가 wakeup 신호의 Physical Destination 값과 동일한 경우, 
    // Entry Tag의 Register Ready 신호를 1로 바꾸어 WB가 가능하게 설정함.


    assign iq_empty = (iq_count == '0);
    assign issue_select_valid = issue_candidate_valid;
    assign issue_select_idx = issue_candidate_idx;
    assign iq_full = (iq_count == IQ_ENTRIES);
    assign enqueue_ready = enqueue_slot_valid && !flush_valid;
    assign enqueue_fire = enqueue_valid && enqueue_ready;
    assign issue_fire = issue_valid && issue_ready;

    assign issue_valid = issue_select_valid && !flush_valid;
    assign issue_rob_tag = issue_list[issue_select_idx].rob_tag;
    assign issue_pc = issue_list[issue_select_idx].pc;
    assign issue_inst = issue_list[issue_select_idx].inst;
    assign issue_opcode = issue_list[issue_select_idx].opcode;
    assign issue_funct3 = issue_list[issue_select_idx].funct3;
    assign issue_funct7 = issue_list[issue_select_idx].funct7;
    assign issue_imm = issue_list[issue_select_idx].imm;
    assign issue_phys_rs1 = issue_list[issue_select_idx].phys_rs1;
    assign issue_phys_rs2 = issue_list[issue_select_idx].phys_rs2;
    assign issue_phys_rd = issue_list[issue_select_idx].phys_rd;
    assign issue_use_rs1 = issue_list[issue_select_idx].use_rs1;
    assign issue_use_rs2 = issue_list[issue_select_idx].use_rs2;
    assign issue_write_rd = issue_list[issue_select_idx].write_rd;
    assign issue_is_branch = issue_list[issue_select_idx].is_branch;
    assign issue_is_jal = issue_list[issue_select_idx].is_jal;
    assign issue_is_jalr = issue_list[issue_select_idx].is_jalr;
    assign issue_is_system = issue_list[issue_select_idx].is_system;
    assign issue_pred_taken = issue_list[issue_select_idx].pred_taken;
    assign issue_pred_target = issue_list[issue_select_idx].pred_target;

    always_comb begin
        enqueue_slot_valid = 1'b0;
        enqueue_slot_idx = '0;

        for (int q = 0; q < IQ_ENTRIES; q++) begin
            if (!enqueue_slot_valid && !issue_list[q].valid) begin
                enqueue_slot_valid = 1'b1;
                enqueue_slot_idx = q;
            end
        end
    end 


    // priority logic

    // Oldest READY (ROB Tag를 기준으로 계산함) 를 위한 distance 계산 함수 (head로 부터 계산함.)
    function automatic logic [ROB_TAG_WIDTH:0] calc_tag(
        input logic [ROB_TAG_WIDTH-1:0] tag,
        input logic [ROB_TAG_WIDTH-1:0] head
    ); 

        if (tag >= head) begin
            calc_tag = tag - head;
        end
        else begin
            calc_tag = ROB_ENTRIES + tag - head;
        end

    endfunction


    // function automatic logic [IQ_IDX_WIDTH-1:0] select_iq_scoreboard(
    //     input issue_queue_entry_t iq_list_head;
    //     input issue_queue_entry_t iq_list_target;
    // );

    // endfunction

    logic [ROB_TAG_WIDTH:0] best_dist;
    logic [ROB_TAG_WIDTH:0] current_dist;

    integer l;

    always_comb begin
        issue_candidate_valid = 1'b0;
        issue_candidate_idx = '0;

        best_dist = '1;

        for (l=0; l<IQ_ENTRIES; l++) begin
            current_dist = calc_tag(issue_list[l].rob_tag, rob_head_tag);

            if (entry_ready[l] &&
                (!issue_list[l].is_system ||
                 (issue_list[l].rob_tag == rob_head_tag)) &&
                (!issue_candidate_valid ||
                 (current_dist < best_dist))) begin
                issue_candidate_valid = 1'b1;
                issue_candidate_idx = l;
                best_dist = current_dist;
            end
        end
    end


    always @(posedge ACLK or negedge ARESETn) begin
        if (!ARESETn) begin
            iq_count <= '0;
            for (int q = 0; q < IQ_ENTRIES; q++) begin
                issue_list[q] <= '0;
            end
        end
        else if (flush_valid) begin
            iq_count <= '0;
            for (int q = 0; q < IQ_ENTRIES; q++) begin
                issue_list[q].valid <= 1'b0;
            end
        end
        else begin
            if (wakeup_valid) begin
                for (int q = 0; q < IQ_ENTRIES; q++) begin
                    if (issue_list[q].valid) begin
                        if (issue_list[q].use_rs1 &&
                            (issue_list[q].phys_rs1 == wakeup_phys_rd)) begin
                            issue_list[q].rs1_ready <= 1'b1;
                        end

                        if (issue_list[q].use_rs2 &&
                            (issue_list[q].phys_rs2 == wakeup_phys_rd)) begin
                            issue_list[q].rs2_ready <= 1'b1;
                        end
                    end
                end
            end

            if (enqueue_fire) begin
                issue_list[enqueue_slot_idx].valid <= 1'b1;
                issue_list[enqueue_slot_idx].rob_tag <= enqueue_rob_tag;
                issue_list[enqueue_slot_idx].pc <= enqueue_pc;
                issue_list[enqueue_slot_idx].inst <= enqueue_inst;
                issue_list[enqueue_slot_idx].opcode <= enqueue_opcode;
                issue_list[enqueue_slot_idx].funct3 <= enqueue_funct3;
                issue_list[enqueue_slot_idx].funct7 <= enqueue_funct7;
                issue_list[enqueue_slot_idx].imm <= enqueue_imm;
                issue_list[enqueue_slot_idx].phys_rs1 <= enqueue_phys_rs1;
                issue_list[enqueue_slot_idx].phys_rs2 <= enqueue_phys_rs2;
                issue_list[enqueue_slot_idx].phys_rd <= enqueue_phys_rd;
                issue_list[enqueue_slot_idx].rs1_ready <=
                    !enqueue_use_rs1 ||
                    enqueue_rs1_ready ||
                    (wakeup_valid && (enqueue_phys_rs1 == wakeup_phys_rd));
                issue_list[enqueue_slot_idx].rs2_ready <=
                    !enqueue_use_rs2 ||
                    enqueue_rs2_ready ||
                    (wakeup_valid && (enqueue_phys_rs2 == wakeup_phys_rd));
                issue_list[enqueue_slot_idx].use_rs1 <= enqueue_use_rs1;
                issue_list[enqueue_slot_idx].use_rs2 <= enqueue_use_rs2;
                issue_list[enqueue_slot_idx].write_rd <= enqueue_write_rd;
                issue_list[enqueue_slot_idx].is_branch <= enqueue_is_branch;
                issue_list[enqueue_slot_idx].is_jal <= enqueue_is_jal;
                issue_list[enqueue_slot_idx].is_jalr <= enqueue_is_jalr;
                issue_list[enqueue_slot_idx].is_system <= enqueue_is_system;
                issue_list[enqueue_slot_idx].pred_taken <= enqueue_pred_taken;
                issue_list[enqueue_slot_idx].pred_target <= enqueue_pred_target;
            end

            if (issue_fire) begin
                issue_list[issue_select_idx].valid <= 1'b0;
            end

            case ({enqueue_fire, issue_fire})
                2'b10: iq_count <= iq_count + 1'b1;
                2'b01: iq_count <= iq_count - 1'b1;
                default: iq_count <= iq_count;
            endcase
        end
    end

endmodule
