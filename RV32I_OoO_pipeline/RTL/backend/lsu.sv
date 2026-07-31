module lsu #(
    parameter int unsigned DATA_WIDTH = 32,
    parameter int unsigned ADDR_WIDTH = 32,
    parameter int unsigned PHYS_REGS = 64,
    parameter int unsigned ROB_ENTRIES = 32,
    parameter int unsigned STORE_BUFFER_DEPTH = 8,
    parameter int unsigned LOAD_QUEUE_DEPTH = 8,
    parameter int unsigned COMPLETION_QUEUE_DEPTH = 16,
    parameter int unsigned MEM_ID_WIDTH = 5,
    parameter int unsigned EXC_CAUSE_WIDTH = 5,

    localparam int unsigned DATA_STRB_WIDTH = DATA_WIDTH / 8,
    localparam int unsigned PHYS_TAG_WIDTH =
        (PHYS_REGS <= 1) ? 1 : $clog2(PHYS_REGS),
    localparam int unsigned ROB_TAG_WIDTH =
        (ROB_ENTRIES <= 1) ? 1 : $clog2(ROB_ENTRIES),
    localparam int unsigned SB_IDX_WIDTH =
        (STORE_BUFFER_DEPTH <= 1) ? 1 : $clog2(STORE_BUFFER_DEPTH),
    localparam int unsigned SB_COUNT_WIDTH =
        (STORE_BUFFER_DEPTH <= 1) ? 1 : $clog2(STORE_BUFFER_DEPTH + 1),
    localparam int unsigned LQ_IDX_WIDTH =
        (LOAD_QUEUE_DEPTH <= 1) ? 1 : $clog2(LOAD_QUEUE_DEPTH),
    localparam int unsigned LQ_COUNT_WIDTH =
        (LOAD_QUEUE_DEPTH <= 1) ? 1 : $clog2(LOAD_QUEUE_DEPTH + 1),
    localparam int unsigned LOAD_EPOCH_WIDTH =
        MEM_ID_WIDTH - LQ_IDX_WIDTH - 1,
    localparam int unsigned CQ_IDX_WIDTH =
        (COMPLETION_QUEUE_DEPTH <= 1) ? 1 : $clog2(COMPLETION_QUEUE_DEPTH),
    localparam int unsigned CQ_COUNT_WIDTH =
        (COMPLETION_QUEUE_DEPTH <= 1) ? 1 : $clog2(COMPLETION_QUEUE_DEPTH + 1)
) (
    input  logic                        ACLK,
    input  logic                        ARESETn,
    input  logic                        flush_valid,

    input  logic                        issue_valid,
    output logic                        issue_ready,
    input  logic [ROB_TAG_WIDTH-1:0]    issue_rob_tag,
    input  logic [31:0]                 issue_inst,
    input  logic [2:0]                  issue_funct3,
    input  logic [31:0]                 issue_imm,
    input  logic [PHYS_TAG_WIDTH-1:0]   issue_phys_rd,
    input  logic                        issue_is_load,
    input  logic                        issue_is_store,
    input  logic [DATA_WIDTH-1:0]       issue_base_data,
    input  logic [DATA_WIDTH-1:0]       issue_store_data,

    input  logic                        commit_store_valid,
    input  logic [ROB_TAG_WIDTH-1:0]    commit_store_rob_tag,
    output logic                        commit_store_ready,

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

    output logic                        wb_valid,
    input  logic                        wb_ready,
    output logic [ROB_TAG_WIDTH-1:0]    wb_rob_tag,
    output logic [PHYS_TAG_WIDTH-1:0]   wb_phys_rd,
    output logic                        wb_write_rd,
    output logic [DATA_WIDTH-1:0]       wb_data,
    output logic                        wb_exception,
    output logic [EXC_CAUSE_WIDTH-1:0] wb_exception_cause,
    output logic [ADDR_WIDTH-1:0]       wb_exception_tval
);

    localparam logic [EXC_CAUSE_WIDTH-1:0] EXC_ILLEGAL_INSTRUCTION = 5'd2;
    localparam logic [EXC_CAUSE_WIDTH-1:0] EXC_LOAD_ADDR_MISALIGNED = 5'd4;
    localparam logic [EXC_CAUSE_WIDTH-1:0] EXC_LOAD_ACCESS_FAULT = 5'd5;
    localparam logic [EXC_CAUSE_WIDTH-1:0] EXC_STORE_ADDR_MISALIGNED = 5'd6;

    typedef struct packed {
        logic                         valid;
        logic                         committed;
        logic [ROB_TAG_WIDTH-1:0]     rob_tag;
        logic [ADDR_WIDTH-1:0]        addr;
        logic [DATA_WIDTH-1:0]        data;
        logic [DATA_STRB_WIDTH-1:0]   strb;
    } store_buffer_entry_t;

    typedef struct packed {
        logic                         valid;
        logic                         requested;
        logic [MEM_ID_WIDTH-1:0]      mem_id;
        logic [ROB_TAG_WIDTH-1:0]     rob_tag;
        logic [PHYS_TAG_WIDTH-1:0]    phys_rd;
        logic [2:0]                   funct3;
        logic [ADDR_WIDTH-1:0]        addr;
        logic [DATA_WIDTH-1:0]        forward_data;
        logic [DATA_STRB_WIDTH-1:0]   forward_mask;
    } load_queue_entry_t;

    typedef struct packed {
        logic [ROB_TAG_WIDTH-1:0]     rob_tag;
        logic [PHYS_TAG_WIDTH-1:0]    phys_rd;
        logic                         write_rd;
        logic [DATA_WIDTH-1:0]        data;
        logic                         exception;
        logic [EXC_CAUSE_WIDTH-1:0]   exception_cause;
        logic [ADDR_WIDTH-1:0]        exception_tval;
    } completion_entry_t;

    store_buffer_entry_t store_buffer [0:STORE_BUFFER_DEPTH-1];
    load_queue_entry_t load_queue [0:LOAD_QUEUE_DEPTH-1];
    completion_entry_t completion_queue [0:COMPLETION_QUEUE_DEPTH-1];

    logic [SB_IDX_WIDTH-1:0] sb_head;
    logic [SB_IDX_WIDTH-1:0] sb_commit_head;
    logic [SB_IDX_WIDTH-1:0] sb_tail;
    logic [SB_COUNT_WIDTH-1:0] sb_count;
    logic [SB_COUNT_WIDTH-1:0] sb_committed_count;

    logic [LQ_IDX_WIDTH-1:0] lq_head;
    logic [LQ_IDX_WIDTH-1:0] lq_tail;
    logic [LQ_COUNT_WIDTH-1:0] lq_count;

    logic [CQ_IDX_WIDTH-1:0] cq_head;
    logic [CQ_IDX_WIDTH-1:0] cq_tail;
    logic [CQ_COUNT_WIDTH-1:0] cq_count;

    logic prefer_store;
    logic store_req_outstanding;
    logic mem_req_is_store;
    logic lq_alloc_found;
    logic [LQ_IDX_WIDTH-1:0] lq_alloc_idx;
    logic lq_req_found;
    logic [LQ_IDX_WIDTH-1:0] lq_req_idx;
    logic [LQ_IDX_WIDTH-1:0] lq_resp_idx;
    logic [LOAD_EPOCH_WIDTH-1:0] load_epoch;
    logic [MEM_ID_WIDTH-1:0] new_load_mem_id;
    logic load_response_matches;
    logic store_error_sticky;

    logic [ADDR_WIDTH-1:0] issue_addr;
    logic issue_kind_valid;
    logic issue_size_valid;
    logic issue_misaligned;
    logic [DATA_WIDTH-1:0] shifted_store_data;
    logic [DATA_STRB_WIDTH-1:0] shifted_store_strb;
    logic [DATA_STRB_WIDTH-1:0] load_required_mask;
    logic [DATA_WIDTH-1:0] load_forward_data;
    logic [DATA_STRB_WIDTH-1:0] load_forward_mask;
    logic load_fully_forwarded;
    logic [DATA_WIDTH-1:0] issue_forward_word;

    logic sb_empty;
    logic sb_full;
    logic lq_empty;
    logic lq_full;
    logic cq_has_issue_reserve;
    logic store_head_committed;
    logic store_commit_match;
    logic issue_fire;
    logic issue_immediate;
    logic store_enqueue_fire;
    logic store_commit_fire;
    logic store_dequeue_fire;
    logic load_enqueue_fire;
    logic load_response_fire;
    logic load_response_enqueue;
    logic wb_dequeue_fire;
    logic issue_completion_enqueue;

    completion_entry_t issue_completion;
    completion_entry_t response_completion;
    logic [DATA_WIDTH-1:0] response_merged_word;

    function automatic logic [SB_IDX_WIDTH-1:0] sb_next(
        input logic [SB_IDX_WIDTH-1:0] idx
    );
        if (idx == STORE_BUFFER_DEPTH-1)
            sb_next = '0;
        else
            sb_next = idx + 1'b1;
    endfunction

    function automatic logic [LQ_IDX_WIDTH-1:0] lq_next(
        input logic [LQ_IDX_WIDTH-1:0] idx
    );
        if (idx == LOAD_QUEUE_DEPTH-1)
            lq_next = '0;
        else
            lq_next = idx + 1'b1;
    endfunction

    function automatic logic [CQ_IDX_WIDTH-1:0] cq_next(
        input logic [CQ_IDX_WIDTH-1:0] idx
    );
        if (idx == COMPLETION_QUEUE_DEPTH-1)
            cq_next = '0;
        else
            cq_next = idx + 1'b1;
    endfunction

    function automatic logic [DATA_WIDTH-1:0] format_load_data(
        input logic [DATA_WIDTH-1:0] word_data,
        input logic [1:0] addr_low,
        input logic [2:0] funct3
    );
        logic [DATA_WIDTH-1:0] shifted;
        begin
            shifted = word_data >> (8 * addr_low);
            unique case (funct3)
                3'b000: format_load_data =
                    {{24{shifted[7]}}, shifted[7:0]};
                3'b001: format_load_data =
                    {{16{shifted[15]}}, shifted[15:0]};
                3'b010: format_load_data = shifted;
                3'b100: format_load_data = {24'b0, shifted[7:0]};
                3'b101: format_load_data = {16'b0, shifted[15:0]};
                default: format_load_data = '0;
            endcase
        end
    endfunction

    assign issue_addr = issue_base_data + issue_imm;
    assign issue_kind_valid = issue_is_load ^ issue_is_store;
    assign sb_empty = (sb_count == '0);
    assign sb_full = (sb_count == STORE_BUFFER_DEPTH);
    assign lq_empty = (lq_count == '0);
    assign lq_full = (lq_count == LOAD_QUEUE_DEPTH);
    assign cq_has_issue_reserve =
        (cq_count <= COMPLETION_QUEUE_DEPTH-2);
    assign store_head_committed = !sb_empty &&
                                  store_buffer[sb_head].valid &&
                                  store_buffer[sb_head].committed;
    assign store_commit_match = !sb_empty &&
                                store_buffer[sb_commit_head].valid &&
                                !store_buffer[sb_commit_head].committed &&
                                (store_buffer[sb_commit_head].rob_tag ==
                                 commit_store_rob_tag);

    always_comb begin
        issue_size_valid = 1'b0;
        issue_misaligned = 1'b0;
        if (issue_is_load) begin
            unique case (issue_funct3)
                3'b000, 3'b100: issue_size_valid = 1'b1;
                3'b001, 3'b101: begin
                    issue_size_valid = 1'b1;
                    issue_misaligned = issue_addr[0];
                end
                3'b010: begin
                    issue_size_valid = 1'b1;
                    issue_misaligned = |issue_addr[1:0];
                end
                default: ;
            endcase
        end
        else if (issue_is_store) begin
            unique case (issue_funct3)
                3'b000: issue_size_valid = 1'b1;
                3'b001: begin
                    issue_size_valid = 1'b1;
                    issue_misaligned = issue_addr[0];
                end
                3'b010: begin
                    issue_size_valid = 1'b1;
                    issue_misaligned = |issue_addr[1:0];
                end
                default: ;
            endcase
        end
    end

    always_comb begin
        shifted_store_data = '0;
        shifted_store_strb = '0;
        unique case (issue_funct3)
            3'b000: begin
                shifted_store_data = issue_store_data <<
                                     (8 * issue_addr[1:0]);
                shifted_store_strb = 4'b0001 << issue_addr[1:0];
            end
            3'b001: begin
                shifted_store_data = issue_store_data <<
                                     (8 * issue_addr[1:0]);
                shifted_store_strb = 4'b0011 << issue_addr[1:0];
            end
            3'b010: begin
                shifted_store_data = issue_store_data;
                shifted_store_strb = '1;
            end
            default: ;
        endcase
    end

    always_comb begin : store_forward_scan
        integer scan_idx;
        load_required_mask = '0;
        load_forward_data = '0;
        load_forward_mask = '0;

        unique case (issue_funct3)
            3'b000, 3'b100:
                load_required_mask = 4'b0001 << issue_addr[1:0];
            3'b001, 3'b101:
                load_required_mask = 4'b0011 << issue_addr[1:0];
            3'b010:
                load_required_mask = '1;
            default:
                load_required_mask = '0;
        endcase

        for (int age = 0; age < STORE_BUFFER_DEPTH; age++) begin
            scan_idx = sb_head + age;
            if (scan_idx >= STORE_BUFFER_DEPTH)
                scan_idx = scan_idx - STORE_BUFFER_DEPTH;
            if ((age < sb_count) && store_buffer[scan_idx].valid &&
                (store_buffer[scan_idx].addr ==
                 {issue_addr[ADDR_WIDTH-1:2], 2'b00})) begin
                for (int byte_idx = 0;
                     byte_idx < DATA_STRB_WIDTH;
                     byte_idx++) begin
                    if (store_buffer[scan_idx].strb[byte_idx]) begin
                        load_forward_data[byte_idx*8 +: 8] =
                            store_buffer[scan_idx].data[byte_idx*8 +: 8];
                        load_forward_mask[byte_idx] = 1'b1;
                    end
                end
            end
        end
    end

    assign load_fully_forwarded =
        ((load_forward_mask & load_required_mask) == load_required_mask) &&
        (load_required_mask != '0);
    assign issue_forward_word = load_forward_data;

    always_comb begin : load_queue_search
        lq_alloc_found = 1'b0;
        lq_alloc_idx = '0;
        lq_req_found = 1'b0;
        lq_req_idx = '0;
        for (int i = 0; i < LOAD_QUEUE_DEPTH; i++) begin
            if (!lq_alloc_found && !load_queue[i].valid) begin
                lq_alloc_found = 1'b1;
                lq_alloc_idx = i[LQ_IDX_WIDTH-1:0];
            end
            if (!lq_req_found && load_queue[i].valid &&
                !load_queue[i].requested) begin
                lq_req_found = 1'b1;
                lq_req_idx = i[LQ_IDX_WIDTH-1:0];
            end
        end
    end

    always_comb begin
        issue_ready = 1'b0;
        if (!flush_valid && cq_has_issue_reserve) begin
            if (issue_is_store)
                issue_ready = !sb_full;
            else if (issue_is_load)
                issue_ready = lq_alloc_found;
            else
                issue_ready = 1'b1;
        end
    end

    assign issue_fire = issue_valid && issue_ready;
    assign issue_immediate = issue_fire &&
        (!issue_kind_valid || !issue_size_valid || issue_misaligned ||
         issue_is_store || (issue_is_load && load_fully_forwarded));
    assign store_enqueue_fire = issue_fire && issue_is_store &&
                                issue_kind_valid && issue_size_valid &&
                                !issue_misaligned;
    assign load_enqueue_fire = issue_fire && issue_is_load &&
                               issue_kind_valid && issue_size_valid &&
                               !issue_misaligned &&
                               !load_fully_forwarded;
    assign issue_completion_enqueue = issue_immediate;

    always_comb begin
        issue_completion = '0;
        issue_completion.rob_tag = issue_rob_tag;
        issue_completion.phys_rd = issue_phys_rd;
        issue_completion.exception_tval = '0;

        if (!issue_kind_valid || !issue_size_valid) begin
            issue_completion.exception = 1'b1;
            issue_completion.exception_cause = EXC_ILLEGAL_INSTRUCTION;
            issue_completion.exception_tval = issue_inst;
        end
        else if (issue_misaligned) begin
            issue_completion.exception = 1'b1;
            issue_completion.exception_cause = issue_is_load ?
                EXC_LOAD_ADDR_MISALIGNED : EXC_STORE_ADDR_MISALIGNED;
            issue_completion.exception_tval = issue_addr;
        end
        else if (issue_is_load) begin
            issue_completion.write_rd = 1'b1;
            issue_completion.data = format_load_data(
                issue_forward_word, issue_addr[1:0], issue_funct3);
        end
    end

    assign commit_store_ready = commit_store_valid && store_commit_match;
    assign store_commit_fire = commit_store_valid && commit_store_ready;

    assign mem_req_is_store = store_head_committed &&
        !store_req_outstanding && (!lq_req_found || prefer_store);
    assign mem_req_valid = !flush_valid &&
        ((store_head_committed && !store_req_outstanding) ||
         lq_req_found);
    assign mem_req_write = mem_req_is_store;
    assign mem_req_addr = mem_req_is_store ?
                          store_buffer[sb_head].addr :
                          {load_queue[lq_req_idx].addr[ADDR_WIDTH-1:2],
                           2'b00};
    assign mem_req_wdata = mem_req_is_store ?
                           store_buffer[sb_head].data : '0;
    assign mem_req_wstrb = mem_req_is_store ?
                           store_buffer[sb_head].strb : '0;
    always_comb begin
        mem_req_id = '0;
        mem_req_id[MEM_ID_WIDTH-1] = mem_req_is_store;
        if (!mem_req_is_store)
            mem_req_id = load_queue[lq_req_idx].mem_id;
    end

    always_comb begin
        new_load_mem_id = '0;
        new_load_mem_id[MEM_ID_WIDTH-2 -: LOAD_EPOCH_WIDTH] =
            load_epoch;
        new_load_mem_id[LQ_IDX_WIDTH-1:0] = lq_alloc_idx;
    end

    assign lq_resp_idx = mem_resp_id[LQ_IDX_WIDTH-1:0];
    assign load_response_matches =
        !mem_resp_id[MEM_ID_WIDTH-1] &&
        load_queue[lq_resp_idx].valid &&
        load_queue[lq_resp_idx].requested &&
        (load_queue[lq_resp_idx].mem_id == mem_resp_id);
    assign mem_resp_ready = mem_resp_id[MEM_ID_WIDTH-1] ||
                            !load_response_matches || flush_valid ||
                            (cq_count < COMPLETION_QUEUE_DEPTH);
    assign store_dequeue_fire = mem_resp_valid && mem_resp_ready &&
                                mem_resp_id[MEM_ID_WIDTH-1];
    assign load_response_fire = mem_resp_valid && mem_resp_ready &&
                                !mem_resp_id[MEM_ID_WIDTH-1];
    assign load_response_enqueue = load_response_fire &&
                                   load_response_matches &&
                                   !flush_valid;

    always_comb begin
        response_merged_word = mem_resp_rdata;
        for (int byte_idx = 0; byte_idx < DATA_STRB_WIDTH; byte_idx++) begin
            if (load_queue[lq_resp_idx].forward_mask[byte_idx])
                response_merged_word[byte_idx*8 +: 8] =
                    load_queue[lq_resp_idx].forward_data[byte_idx*8 +: 8];
        end

        response_completion = '0;
        response_completion.rob_tag =
            load_queue[lq_resp_idx].rob_tag;
        response_completion.phys_rd =
            load_queue[lq_resp_idx].phys_rd;
        response_completion.write_rd = !mem_resp_error;
        response_completion.data = format_load_data(
            response_merged_word,
            load_queue[lq_resp_idx].addr[1:0],
            load_queue[lq_resp_idx].funct3);
        response_completion.exception = mem_resp_error;
        response_completion.exception_cause = mem_resp_error ?
            EXC_LOAD_ACCESS_FAULT : '0;
        response_completion.exception_tval = mem_resp_error ?
            load_queue[lq_resp_idx].addr : '0;
    end

    assign wb_valid = (cq_count != '0);
    assign wb_rob_tag = completion_queue[cq_head].rob_tag;
    assign wb_phys_rd = completion_queue[cq_head].phys_rd;
    assign wb_write_rd = completion_queue[cq_head].write_rd &&
                         !completion_queue[cq_head].exception;
    assign wb_data = completion_queue[cq_head].data;
    assign wb_exception = completion_queue[cq_head].exception;
    assign wb_exception_cause =
        completion_queue[cq_head].exception_cause;
    assign wb_exception_tval = completion_queue[cq_head].exception_tval;
    assign wb_dequeue_fire = wb_valid && wb_ready;

    always_ff @(posedge ACLK or negedge ARESETn) begin
        if (!ARESETn) begin
            cq_head <= '0;
            cq_tail <= '0;
            cq_count <= '0;
            for (int i = 0; i < COMPLETION_QUEUE_DEPTH; i++)
                completion_queue[i] <= '0;
        end
        else if (flush_valid) begin
            cq_head <= '0;
            cq_tail <= '0;
            cq_count <= '0;
        end
        else begin
            if (load_response_enqueue)
                completion_queue[cq_tail] <= response_completion;
            if (issue_completion_enqueue) begin
                if (load_response_enqueue)
                    completion_queue[cq_next(cq_tail)] <= issue_completion;
                else
                    completion_queue[cq_tail] <= issue_completion;
            end

            if (wb_dequeue_fire)
                cq_head <= cq_next(cq_head);

            unique case ({load_response_enqueue,
                          issue_completion_enqueue})
                2'b01, 2'b10: cq_tail <= cq_next(cq_tail);
                2'b11: cq_tail <= cq_next(cq_next(cq_tail));
                default: cq_tail <= cq_tail;
            endcase

            unique case ({load_response_enqueue,
                          issue_completion_enqueue,
                          wb_dequeue_fire})
                3'b001: cq_count <= cq_count - 1'b1;
                3'b010, 3'b100: cq_count <= cq_count + 1'b1;
                3'b110: cq_count <= cq_count + 2'd2;
                3'b111: cq_count <= cq_count + 1'b1;
                default: cq_count <= cq_count;
            endcase
        end
    end

    always_ff @(posedge ACLK or negedge ARESETn) begin
        if (!ARESETn) begin
            lq_head <= '0;
            lq_tail <= '0;
            lq_count <= '0;
            load_epoch <= '0;
            for (int i = 0; i < LOAD_QUEUE_DEPTH; i++)
                load_queue[i] <= '0;
        end
        else if (flush_valid) begin
            lq_head <= '0;
            load_epoch <= load_epoch + 1'b1;
            lq_tail <= '0;
            lq_count <= '0;
            for (int i = 0; i < LOAD_QUEUE_DEPTH; i++) begin
                load_queue[i].valid <= 1'b0;
                load_queue[i].requested <= 1'b0;
            end
        end
        else begin
            if (load_enqueue_fire) begin
                load_queue[lq_alloc_idx].valid <= 1'b1;
                load_queue[lq_alloc_idx].requested <= 1'b0;
                load_queue[lq_alloc_idx].mem_id <= new_load_mem_id;
                load_queue[lq_alloc_idx].rob_tag <= issue_rob_tag;
                load_queue[lq_alloc_idx].phys_rd <= issue_phys_rd;
                load_queue[lq_alloc_idx].funct3 <= issue_funct3;
                load_queue[lq_alloc_idx].addr <= issue_addr;
                load_queue[lq_alloc_idx].forward_data <=
                    load_forward_data;
                load_queue[lq_alloc_idx].forward_mask <=
                    load_forward_mask;
            end
            if (mem_req_valid && mem_req_ready && !mem_req_is_store)
                load_queue[lq_req_idx].requested <= 1'b1;
            if (load_response_fire && load_response_matches) begin
                load_queue[lq_resp_idx].valid <= 1'b0;
                load_queue[lq_resp_idx].requested <= 1'b0;
            end

            unique case ({load_enqueue_fire,
                          load_response_fire && load_response_matches})
                2'b10: lq_count <= lq_count + 1'b1;
                2'b01: lq_count <= lq_count - 1'b1;
                default: lq_count <= lq_count;
            endcase
        end
    end

    always_ff @(posedge ACLK or negedge ARESETn) begin
        if (!ARESETn) begin
            prefer_store <= 1'b0;
            store_req_outstanding <= 1'b0;
        end
        else begin
            if (mem_req_valid && mem_req_ready) begin
                prefer_store <= !mem_req_is_store;
                if (mem_req_is_store)
                    store_req_outstanding <= 1'b1;
            end
            if (store_dequeue_fire)
                store_req_outstanding <= 1'b0;
        end
    end

    always_ff @(posedge ACLK or negedge ARESETn) begin
        if (!ARESETn) begin
            sb_head <= '0;
            sb_commit_head <= '0;
            sb_tail <= '0;
            sb_count <= '0;
            sb_committed_count <= '0;
            store_error_sticky <= 1'b0;
            for (int i = 0; i < STORE_BUFFER_DEPTH; i++)
                store_buffer[i] <= '0;
        end
        else if (flush_valid) begin
            for (int i = 0; i < STORE_BUFFER_DEPTH; i++) begin
                if (store_buffer[i].valid &&
                    !store_buffer[i].committed)
                    store_buffer[i].valid <= 1'b0;
            end
            sb_tail <= sb_commit_head;

            if (store_dequeue_fire) begin
                store_buffer[sb_head].valid <= 1'b0;
                sb_head <= sb_next(sb_head);
                sb_count <= sb_committed_count - 1'b1;
                sb_committed_count <= sb_committed_count - 1'b1;
                if (mem_resp_error)
                    store_error_sticky <= 1'b1;
            end
            else begin
                sb_count <= sb_committed_count;
            end
        end
        else begin
            if (store_enqueue_fire) begin
                store_buffer[sb_tail].valid <= 1'b1;
                store_buffer[sb_tail].committed <= 1'b0;
                store_buffer[sb_tail].rob_tag <= issue_rob_tag;
                store_buffer[sb_tail].addr <=
                    {issue_addr[ADDR_WIDTH-1:2], 2'b00};
                store_buffer[sb_tail].data <= shifted_store_data;
                store_buffer[sb_tail].strb <= shifted_store_strb;
                sb_tail <= sb_next(sb_tail);
            end

            if (store_commit_fire) begin
                store_buffer[sb_commit_head].committed <= 1'b1;
                sb_commit_head <= sb_next(sb_commit_head);
            end

            if (store_dequeue_fire) begin
                store_buffer[sb_head].valid <= 1'b0;
                store_buffer[sb_head].committed <= 1'b0;
                sb_head <= sb_next(sb_head);
                if (mem_resp_error)
                    store_error_sticky <= 1'b1;
            end

            unique case ({store_enqueue_fire, store_dequeue_fire})
                2'b10: sb_count <= sb_count + 1'b1;
                2'b01: sb_count <= sb_count - 1'b1;
                default: sb_count <= sb_count;
            endcase

            unique case ({store_commit_fire, store_dequeue_fire})
                2'b10: sb_committed_count <=
                    sb_committed_count + 1'b1;
                2'b01: sb_committed_count <=
                    sb_committed_count - 1'b1;
                default: sb_committed_count <= sb_committed_count;
            endcase
        end
    end

endmodule
