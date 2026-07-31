module rob_allocator #(
    parameter int unsigned WIDTH_INST = 32,
    parameter int unsigned ADDR_WIDTH = 32,
    parameter int unsigned ARCH_REGS = 32,
    parameter int unsigned PHYS_REGS = 64,
    parameter int unsigned ROB_ENTRIES = 32,
    parameter int unsigned LQ_DEPTH = 16,
    parameter int unsigned SQ_DEPTH = 16,

    localparam int unsigned ARCH_TAG_WIDTH = (ARCH_REGS <= 1) ? 1 : $clog2(ARCH_REGS),
    localparam int unsigned PHYS_TAG_WIDTH = (PHYS_REGS <= 1) ? 1 : $clog2(PHYS_REGS),
    localparam int unsigned PRF_W = PHYS_TAG_WIDTH,
    localparam int unsigned ROB_TAG_WIDTH = (ROB_ENTRIES <= 1) ? 1 : $clog2(ROB_ENTRIES),
    localparam int unsigned ROB_GEN_W = 2,
    localparam int unsigned LQ_IDX_W = (LQ_DEPTH <= 1) ? 1 : $clog2(LQ_DEPTH),
    localparam int unsigned SQ_IDX_W = (SQ_DEPTH <= 1) ? 1 : $clog2(SQ_DEPTH),
    localparam int unsigned EXC_CAUSE_WIDTH = 5
) (
    input  logic                        ACLK,
    input  logic                        ARESETn,

    // Dispatch allocation request
    input  logic                        alloc_valid,
    output logic                        alloc_ready,
    input  logic [ADDR_WIDTH-1:0]       alloc_pc,
    input  logic [WIDTH_INST-1:0]       alloc_inst,
    input  logic [ARCH_TAG_WIDTH-1:0]   alloc_arch_rd,
    input  logic [PHYS_TAG_WIDTH-1:0]   alloc_phys_rd,
    input  logic [PHYS_TAG_WIDTH-1:0]   alloc_old_phys_rd,
    input  logic                        alloc_write_rd,
    input  logic                        alloc_is_branch,
    input  logic                        alloc_is_jal,
    input  logic                        alloc_is_jalr,
    input  logic                        alloc_pred_taken,
    input  logic [ADDR_WIDTH-1:0]       alloc_pred_target,
    input  logic                        alloc_illegal_inst,
    input  logic [1:0]                  alloc_if_status,

    // Allocated ROB tag forwarded to queues
    output logic                        alloc_rob_valid,
    output logic [ROB_TAG_WIDTH-1:0]    alloc_rob_tag,

    // Completion/writeback update
    input  logic                        complete_valid,
    input  logic [ROB_TAG_WIDTH-1:0]    complete_rob_tag,
    input  logic [ADDR_WIDTH-1:0]       complete_actual_target,
    input  logic                        complete_branch_taken,
    input  logic                        complete_exception,
    input  logic [EXC_CAUSE_WIDTH-1:0] complete_exception_cause,
    input  logic [ADDR_WIDTH-1:0]       complete_exception_tval,

    // Commit interface
    output logic                        commit_valid,
    input  logic                        commit_ready,
    output logic [ROB_TAG_WIDTH-1:0]    commit_rob_tag,
    output logic [ADDR_WIDTH-1:0]       commit_pc,
    output logic [WIDTH_INST-1:0]      commit_inst,
    output logic [ARCH_TAG_WIDTH-1:0]   commit_arch_rd,
    output logic [PHYS_TAG_WIDTH-1:0]   commit_phys_rd,
    output logic [PHYS_TAG_WIDTH-1:0]   commit_old_phys_rd,
    output logic                        commit_is_store,
    output logic                        commit_write_rd,
    output logic                        commit_free_valid,
    output logic [PHYS_TAG_WIDTH-1:0]   commit_free_tag,

    // Precise synchronous exception at ROB head
    output logic                        head_exception_valid,
    output logic [EXC_CAUSE_WIDTH-1:0] head_exception_cause,
    output logic [ADDR_WIDTH-1:0]       head_exception_pc,
    output logic [ADDR_WIDTH-1:0]       head_exception_tval,

    // Recovery/redirect interface
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
    output logic [ROB_TAG_WIDTH-1:0]    rob_head_tag
);

    // ROB Entry 구성

    typedef struct packed {
        logic               valid;
        logic               complete;
        logic [ROB_GEN_W-1:0] gen;

        logic [31:0]        pc;
        logic [31:0]        inst;

        logic               writes_rd;
        logic [4:0]         logical_rd;
        logic [PRF_W-1:0]   pdst;
        logic [PRF_W-1:0]   stale_pdst;

        logic               is_branch;
        logic               is_load;
        logic               is_store;
        logic               is_fence;

        logic               exception;
        logic [EXC_CAUSE_WIDTH-1:0] exception_cause;
        logic [ADDR_WIDTH-1:0] exception_tval;

        logic               branch_mispredict;
        logic [31:0]        redirect_pc;
        logic pred_taken;
        logic [ADDR_WIDTH-1:0] pred_target;

        logic [LQ_IDX_W-1:0] lq_idx;
        logic [SQ_IDX_W-1:0] sq_idx;       
    } rob_entry_t;

    // ROB entry declare 
    rob_entry_t rob_entry[0:ROB_ENTRIES-1];

    // ARMv8 (LEGv8) 기준을 따르는 instruction을 구분하기 위하여 여기에 typedef enum 선언

    typedef enum logic [4:0] { 
        INT_ADD,
        SHIFT,
        BIT_FIX,
        MUL,
        DIV,
        BRANCH,
        COND,
        LOAD,
        STORE,
        ATOMIC,
        FP_ALU,
        SIMD,
        SYS,
        EXCEPTION
    } inst_class_enum; 
    
    inst_class_enum inst_class;



    typedef enum logic [EXC_CAUSE_WIDTH-1:0] {
        EXC_INST_ADDR_MISALIGNED  = 5'd0,
        EXC_INST_ACCESS_FAULT     = 5'd1,
        EXC_ILLEGAL_INSTRUCTION   = 5'd2,
        EXC_BREAKPOINT            = 5'd3,
        EXC_LOAD_ADDR_MISALIGNED  = 5'd4,
        EXC_LOAD_ACCESS_FAULT     = 5'd5,
        EXC_STORE_ADDR_MISALIGNED = 5'd6,
        EXC_STORE_ACCESS_FAULT    = 5'd7,
        EXC_ECALL_U_MODE          = 5'd8,
        EXC_ECALL_S_MODE          = 5'd9,
        EXC_ECALL_M_MODE          = 5'd11,
        EXC_INST_PAGE_FAULT       = 5'd12,
        EXC_LOAD_PAGE_FAULT       = 5'd13,
        EXC_STORE_PAGE_FAULT      = 5'd15
    } exception_cause_enum;

    logic alloc_fetch_exception;
    logic alloc_exception;
    // counter seq logic for head / count / tail
    logic [ROB_TAG_WIDTH-1:0] rob_head;
    logic [ROB_TAG_WIDTH-1:0] rob_tail;
    logic [ROB_TAG_WIDTH:0] rob_count;
    logic alloc_fire;
    logic commit_fire;
    logic head_mispredict;
    logic recover_start;
    logic rollback_step;
    logic [ROB_TAG_WIDTH-1:0] rollback_idx;

    assign rob_empty = (rob_count == 0);
    assign rob_full = (rob_count == ROB_ENTRIES);
    assign rob_head_tag = rob_head;
    assign alloc_fetch_exception = (alloc_if_status != 2'b00);
    assign alloc_exception = alloc_fetch_exception || alloc_illegal_inst;
    
    assign alloc_ready = !rob_full && !recovery_busy && !head_mispredict &&
                         !external_recover_valid;

    assign alloc_fire = alloc_ready&&alloc_valid;
    assign commit_fire = commit_ready&&commit_valid;

    assign alloc_rob_tag = rob_tail;
    assign alloc_rob_valid = alloc_fire;

    assign commit_rob_tag = rob_head;
    assign commit_pc = rob_entry[rob_head].pc;
    assign commit_inst = rob_entry[rob_head].inst;
    // commit_valid 부분 수정 : Mispredict Branch가 Head에 도착하는 경우, commit 중지
    assign commit_valid =
    !rob_empty &&
    rob_entry[rob_head].valid &&
    rob_entry[rob_head].complete &&
    !rob_entry[rob_head].branch_mispredict &&
    !rob_entry[rob_head].exception &&
    !recovery_busy;
    assign commit_arch_rd = rob_entry[rob_head].logical_rd;
    assign commit_phys_rd = rob_entry[rob_head].pdst;
    assign commit_old_phys_rd = rob_entry[rob_head].stale_pdst;
    assign commit_is_store = rob_entry[rob_head].is_store;
    assign commit_write_rd = rob_entry[rob_head].writes_rd;
    assign commit_free_valid = commit_fire && commit_write_rd;
    assign commit_free_tag = rob_entry[rob_head].stale_pdst;

    assign head_exception_valid = !rob_empty &&
                                  rob_entry[rob_head].valid &&
                                  rob_entry[rob_head].complete &&
                                  rob_entry[rob_head].exception &&
                                  !recovery_busy;
    assign head_exception_cause = rob_entry[rob_head].exception_cause;
    assign head_exception_pc = rob_entry[rob_head].pc;
    assign head_exception_tval = rob_entry[rob_head].exception_tval;


    // head
    always @(posedge ACLK or negedge ARESETn) begin
        if (!ARESETn) begin
            rob_head <= '0;
        end
        else begin
            if (commit_fire) begin
                if (rob_head==ROB_ENTRIES-1) begin
                    rob_head <= 0;
                end

                else rob_head <= rob_head + 1;
            end
        end
    end 

    // tail
    always @(posedge ACLK or negedge ARESETn) begin
        if (!ARESETn) begin
            rob_tail <= '0;
        end
        else begin
            if (rollback_step) begin
                rob_tail <= rollback_idx;
            end
            else if (alloc_fire) begin
                if (rob_tail==ROB_ENTRIES-1) begin
                    rob_tail <= '0;
                end 
                else rob_tail <= rob_tail + 1;
            end

        end
    end 
   



    // count
    always @(posedge ACLK or negedge ARESETn) begin
        if (!ARESETn) begin
            rob_count <= '0;
        end
        else if (rollback_step) begin
            rob_count <= rob_count - 1'b1;
        end
        else begin
            case({alloc_fire, commit_fire})
                2'b00 : begin
                    rob_count <= rob_count;
                end
                2'b01 : begin
                    if (!rob_empty) begin
                        rob_count <= rob_count - 1;
                    end
                end 
                2'b10 : begin
                    if (!rob_full) begin
                        rob_count <= rob_count + 1;
                    end
                end 
                2'b11 : begin
                    rob_count <= rob_count;
                end 
            endcase
        end
    end


    // instruction에 따른 ROB Entry에 alloc (dispatch) 입력 저장.
    integer i;

    always @(posedge ACLK or negedge ARESETn) begin
        if (!ARESETn) begin
            for (i=0; i<ROB_ENTRIES; i=i+1) begin: clear_valid
                rob_entry[i].valid <= 1'b0;
                rob_entry[i].gen    <= '0;
                rob_entry[i].complete <= 1'b0;
            end
        end
        else begin
            if (!rob_full) begin
                if (alloc_fire) begin
                    if (alloc_exception) begin
                        inst_class = EXCEPTION;
                    end
                    else begin
                        case (alloc_inst[6:0])
                            7'b0000011: inst_class = LOAD;
                            7'b0100011: inst_class = STORE;
                            7'b1100011,
                            7'b1100111,
                            7'b1101111: inst_class = BRANCH;
                            7'b1110011,
                            7'b0001111: inst_class = SYS;
                            default:    inst_class = INT_ADD;
                        endcase
                    end

                    rob_entry[rob_tail].valid           <= 1'b1;
                    rob_entry[rob_tail].complete        <= alloc_exception;
                    rob_entry[rob_tail].pc              <= alloc_pc;
                    rob_entry[rob_tail].inst            <= alloc_inst;
                    rob_entry[rob_tail].gen             <= rob_entry[rob_tail].gen + 1'b1;
                    rob_entry[rob_tail].writes_rd       <= alloc_write_rd;
                    rob_entry[rob_tail].logical_rd      <= alloc_arch_rd;
                    rob_entry[rob_tail].pdst            <= alloc_phys_rd;
                    rob_entry[rob_tail].stale_pdst      <= alloc_old_phys_rd;
                    rob_entry[rob_tail].exception       <= alloc_exception;
                    rob_entry[rob_tail].exception_cause <=
                        alloc_fetch_exception ? EXC_INST_ACCESS_FAULT :
                        EXC_ILLEGAL_INSTRUCTION;
                    rob_entry[rob_tail].exception_tval  <=
                        alloc_fetch_exception ? alloc_pc : alloc_inst;
                    rob_entry[rob_tail].is_store        <= (inst_class == STORE);
                    rob_entry[rob_tail].is_branch       <= alloc_is_branch || alloc_is_jal || alloc_is_jalr;
                    rob_entry[rob_tail].is_load         <= (inst_class == LOAD);
                    rob_entry[rob_tail].pred_taken      <= alloc_pred_taken;
                    rob_entry[rob_tail].pred_target     <= alloc_pred_target;
                    rob_entry[rob_tail].branch_mispredict <= 1'b0;
                    
                end
            end
        
            if (complete_valid && rob_entry[complete_rob_tag].valid && !recovery_busy && !head_mispredict) begin
                rob_entry[complete_rob_tag].complete <= 1'b1;
                // rob_entry[complete_rob_tag].exception <= rob_entry[complete_rob_tag].exception || complete_exception;

                if (complete_exception) begin
                    rob_entry[complete_rob_tag].exception <= 1'b1;
                    rob_entry[complete_rob_tag].exception_cause <= complete_exception_cause;
                    rob_entry[complete_rob_tag].exception_tval <= complete_exception_tval;
                end


                else if (rob_entry[complete_rob_tag].is_branch) begin  // 분기문일 경우 pred 사용 필요
                    rob_entry[complete_rob_tag].exception <= rob_entry[complete_rob_tag].exception || complete_exception;
                    // mispredict 출력의 경우, pred 사용이 필요한데 branch taking을 실패한 경우와, branch taking은 성공했으나 target이 서로 다른 경우 mispredict를 출력하는 logic임
                    rob_entry[complete_rob_tag].branch_mispredict <= (rob_entry[complete_rob_tag].pred_taken != complete_branch_taken)||(complete_branch_taken&&(rob_entry[complete_rob_tag].pred_target!=complete_actual_target));
                    // redirect pc 값은 branch taken이 성공했을 경우 실제 target 값을 넣어 PC를 설정하고, 아닌 경우 +4 (32bit 기준) 하는 것으로 진행함.
                    rob_entry[complete_rob_tag].redirect_pc <= complete_branch_taken ? complete_actual_target : rob_entry[complete_rob_tag].pc + 'd4;
                    

                end
            end

            if (commit_fire) begin
                rob_entry[rob_head].valid <= 1'b0;
                rob_entry[rob_head].complete <= 1'b0;
            end

            if (rollback_step) begin
                rob_entry[rollback_idx].valid <= 1'b0;
                rob_entry[rollback_idx].complete <= 1'b0;
            end

            if (recover_valid) begin
                rob_entry[recover_branch_tag].branch_mispredict <= 1'b0;
            end
        end
    end


    // Recovery FSM 관련
    // Head가 마지막에 commit 된 것을 나타내므로, 거기서부터 Recovery를 시작한다는 아이디어.
    assign head_mispredict = !rob_empty && rob_entry[rob_head].valid && rob_entry[rob_head].complete && rob_entry[rob_head].branch_mispredict;
    
    // FSM 만들기
    typedef enum logic [1:0] { 
        REC_SURVEILANCE,
        REC_ROLLBACK,
        REC_REDIRECT
    } recover_state_t;

    recover_state_t recover_status;

    // 대충 저장해야 하는 값은 이 정도.
    // 복구해야 할 명령어의 ROB TAG와 PC 값을 저장하는 것이 핵심.

    logic [ADDR_WIDTH-1:0] save_redirect_pc;
    logic [ROB_TAG_WIDTH-1:0] recover_branch_tag;
    logic recover_inclusive;

    // FSM Sequential Machine
    // Rollback에 필요한 function 2개
    
    function automatic logic [ROB_TAG_WIDTH-1:0] rob_prev(
        input logic [ROB_TAG_WIDTH-1:0] idx
    );
        begin
            if (idx == '0) rob_prev = ROB_ENTRIES - 1;    
            else rob_prev = idx - 1'b1;
        end 

    endfunction

    // rob_tail과 recover_branch_tag + 1 값이 동일하다면, Branch를 제외한 모든 Entry는 제거 (counter=1).

    function automatic logic [ROB_TAG_WIDTH-1:0] rob_next(
        input logic [ROB_TAG_WIDTH-1:0] idx
    );
        begin
            if (idx == ROB_ENTRIES - 1) rob_next = '0;
            else rob_next = idx + 1'b1;
        end

    endfunction

    // 주석 하나하나 달아놓겠음.
    // recover_start => REC_SURVEILANCE (즉 mispredict 감시 중) state 에서 head mispredict가 검출된 경우.
    assign recover_start = (recover_status == REC_SURVEILANCE) &&
                           (head_mispredict || external_recover_valid);

    // rollback_idx => allocated 된 항목 바로 직전까지 rollback 시켜야함
    assign rollback_idx = rob_prev(rob_tail);

    // 그럼 얼마나 rollback 시켜야 함? head부터 하나 씩 줄여서 tail이 recover 시킬 tag 바로 뒷까지는 rollback 시켜야 함.
    assign rollback_step = (recover_status == REC_ROLLBACK) &&
                           (rob_tail != (recover_inclusive ?
                                        recover_branch_tag :
                                        rob_next(recover_branch_tag)));

    // 이거 두 개는 pass
    assign recovery_busy = (recover_status != REC_SURVEILANCE);
    assign recover_flush = recover_start;

    // recover 시킬 때 지나간 step에 따라 rollback idx에 맞는 정보들을 들고와야 함.
    // valid 같은 경우에는 write가 핵심 (read는 register나 memory의 값을 바꾸지 않으므로) 이기에, 저렇게 설정함.

    assign recover_map_valid = rollback_step &&
                               rob_entry[rollback_idx].valid &&
                               rob_entry[rollback_idx].writes_rd;
    assign recover_arch_rd = rob_entry[rollback_idx].logical_rd;
    assign recover_phys_rd = rob_entry[rollback_idx].stale_pdst;

    // map이 valid하면 free 시키는 것이 목표가 됨.
    // tag는 pdst (Physical Destination) 부분을 반환해주면 됨. free 시키니까.
    assign recover_free_valid = recover_map_valid;
    assign recover_free_tag = rob_entry[rollback_idx].pdst;

    // recover 과정이 정상적으로 REC_ROLLBACK을 벗어나면, REDIRECT로 status가 이동함. 이 과정에서 recover_valid를 표기함.
    assign recover_valid = (recover_status == REC_REDIRECT);
    assign recover_redirect_pc = save_redirect_pc;


    // FSM
    always @(posedge ACLK or negedge ARESETn) begin
        if (!ARESETn) begin
            recover_status <= REC_SURVEILANCE;
            recover_branch_tag <= '0;
            save_redirect_pc <= '0;
            recover_inclusive <= 1'b0;
        end
        else begin
            case(recover_status)
                REC_SURVEILANCE : begin
                    if (external_recover_valid) begin
                        recover_branch_tag <= rob_head;
                        save_redirect_pc <= external_recover_pc;
                        recover_inclusive <= 1'b1;
                        recover_status <= REC_ROLLBACK;
                    end
                    else if (head_mispredict) begin
                        recover_branch_tag <= rob_head;
                        save_redirect_pc <= rob_entry[rob_head].redirect_pc;
                        recover_inclusive <= 1'b0;
                        recover_status <= REC_ROLLBACK;
                    end
                end 
                REC_ROLLBACK : begin    // tali의 count를 clear 하는 것은 얘가 하는 일이 아님.
                    if (rob_tail == (recover_inclusive ?
                                     recover_branch_tag :
                                     rob_next(recover_branch_tag))) begin
                        recover_status <= REC_REDIRECT;
                    end
                end
                REC_REDIRECT : begin
                    recover_status <= REC_SURVEILANCE;
                end
                default : recover_status <= REC_SURVEILANCE;
            endcase
        end
    end





endmodule
