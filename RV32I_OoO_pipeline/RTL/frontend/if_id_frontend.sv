module if_id_frontend #(
    parameter int unsigned WIDTH_INST = 32,
    parameter int unsigned ADDR_WIDTH = 32,
    parameter int unsigned PC_REMEMBER_NUM = 16,
    parameter int unsigned PC_PER_INCR = 4,
    parameter int unsigned FETCH_META_DEPTH = 8,
    parameter int unsigned FETCH_PACKET_DEPTH = 8,
    parameter int unsigned FETCH_EPOCH_WIDTH = 2,

    parameter int unsigned ICACHE_LINES = 48,
    parameter int unsigned CACHE_LINE_BYTES = 16,
    parameter int unsigned AXI_DATA_WIDTH = 64,
    parameter int unsigned CACHE_REQ_LEN_WIDTH = 8,
    parameter int unsigned BTB_ENTRIES = 64,

    localparam int unsigned CACHE_LINE_WIDTH = CACHE_LINE_BYTES * 8,
    localparam int unsigned META_IDX_WIDTH =
        (FETCH_META_DEPTH <= 1) ? 1 : $clog2(FETCH_META_DEPTH),
    localparam int unsigned META_COUNT_WIDTH =
        (FETCH_META_DEPTH <= 1) ? 1 : $clog2(FETCH_META_DEPTH + 1),
    localparam int unsigned PACKET_IDX_WIDTH =
        (FETCH_PACKET_DEPTH <= 1) ? 1 : $clog2(FETCH_PACKET_DEPTH),
    localparam int unsigned PACKET_COUNT_WIDTH =
        (FETCH_PACKET_DEPTH <= 1) ? 1 : $clog2(FETCH_PACKET_DEPTH + 1)
) (
    input  logic                        ACLK,
    input  logic                        ARESETn,

    input  logic                        fetch_enable,
    input  logic                        redirect_valid,
    input  logic [ADDR_WIDTH-1:0]       redirect_addr,

    output logic                        if_id_valid,
    input  logic                        if_id_ready,
    output logic [ADDR_WIDTH-1:0]       if_id_pc,
    output logic [WIDTH_INST-1:0]       if_id_inst,
    output logic                        if_id_pred_taken,
    output logic [ADDR_WIDTH-1:0]       if_id_pred_target,
    output logic                        if_id_cache_hit,
    output logic [1:0]                  if_id_status,

    input  logic                        bp_update_valid,
    input  logic                        bp_update_is_branch,
    input  logic [ADDR_WIDTH-1:0]       bp_update_pc,
    input  logic                        bp_update_taken,
    input  logic [ADDR_WIDTH-1:0]       bp_update_target,

    output logic                        i_req_valid,
    input  logic                        i_req_ready,
    output logic [ADDR_WIDTH-1:0]       i_req_addr,
    output logic [CACHE_REQ_LEN_WIDTH-1:0] i_req_len,

    input  logic                        i_resp_valid,
    output logic                        i_resp_ready,
    input  logic [CACHE_LINE_WIDTH-1:0] i_resp_data,
    input  logic [1:0]                  i_resp_status,
    input  logic                        i_resp_last,

    output logic [ADDR_WIDTH-1:0]       fetch_resume_pc,
    output logic                        pc_err
);

    typedef struct packed {
        logic [ADDR_WIDTH-1:0]          pc;
        logic                           pred_taken;
        logic [ADDR_WIDTH-1:0]          pred_target;
        logic [FETCH_EPOCH_WIDTH-1:0]   epoch;
    } fetch_meta_t;

    typedef struct packed {
        logic [ADDR_WIDTH-1:0]          pc;
        logic [WIDTH_INST-1:0]          inst;
        logic                           pred_taken;
        logic [ADDR_WIDTH-1:0]          pred_target;
        logic                           cache_hit;
        logic [1:0]                     status;
    } fetch_packet_t;

    logic [ADDR_WIDTH-1:0] pc_addr;
    logic pc_step;
    logic pc_jump;
    logic [ADDR_WIDTH-1:0] pc_jump_delta;

    logic pred_valid;
    logic pred_taken;
    logic [ADDR_WIDTH-1:0] pred_target;
    logic [ADDR_WIDTH-1:0] next_pc;

    logic ic_fetch_valid;
    logic ic_fetch_ready;
    logic [ADDR_WIDTH-1:0] ic_fetch_addr;
    logic ic_resp_valid;
    logic ic_resp_ready;
    logic [WIDTH_INST-1:0] ic_resp_inst;
    logic [ADDR_WIDTH-1:0] ic_resp_addr;
    logic [1:0] ic_resp_status;
    logic ic_resp_hit;

    fetch_meta_t meta_fifo [0:FETCH_META_DEPTH-1];
    logic [META_IDX_WIDTH-1:0] meta_head;
    logic [META_IDX_WIDTH-1:0] meta_tail;
    logic [META_COUNT_WIDTH-1:0] meta_count;
    logic [FETCH_EPOCH_WIDTH-1:0] fetch_epoch;
    logic meta_empty;
    logic meta_full;
    logic meta_push;
    logic meta_pop;
    logic meta_head_current;

    fetch_packet_t packet_fifo [0:FETCH_PACKET_DEPTH-1];
    logic [PACKET_IDX_WIDTH-1:0] packet_head;
    logic [PACKET_IDX_WIDTH-1:0] packet_tail;
    logic [PACKET_COUNT_WIDTH-1:0] packet_count;
    logic packet_empty;
    logic packet_full;
    logic packet_push;
    logic packet_pop;

    function automatic logic [META_IDX_WIDTH-1:0] meta_next(
        input logic [META_IDX_WIDTH-1:0] idx
    );
        if (idx == FETCH_META_DEPTH-1)
            meta_next = '0;
        else
            meta_next = idx + 1'b1;
    endfunction

    function automatic logic [PACKET_IDX_WIDTH-1:0] packet_next(
        input logic [PACKET_IDX_WIDTH-1:0] idx
    );
        if (idx == FETCH_PACKET_DEPTH-1)
            packet_next = '0;
        else
            packet_next = idx + 1'b1;
    endfunction

    assign meta_empty = (meta_count == '0);
    assign meta_full = (meta_count == FETCH_META_DEPTH);
    assign meta_head_current = !meta_empty &&
        (meta_fifo[meta_head].epoch == fetch_epoch);
    assign packet_empty = (packet_count == '0);
    assign packet_full = (packet_count == FETCH_PACKET_DEPTH);
    assign packet_pop = !packet_empty && if_id_ready;
    assign packet_push = meta_pop && meta_head_current &&
                         !redirect_valid;

    assign if_id_valid = !packet_empty;
    assign if_id_pc = packet_fifo[packet_head].pc;
    assign if_id_inst = packet_fifo[packet_head].inst;
    assign if_id_pred_taken = packet_fifo[packet_head].pred_taken;
    assign if_id_pred_target = packet_fifo[packet_head].pred_target;
    assign if_id_cache_hit = packet_fifo[packet_head].cache_hit;
    assign if_id_status = packet_fifo[packet_head].status;

    assign next_pc = pred_taken ? pred_target : (pc_addr + PC_PER_INCR);
    assign fetch_resume_pc = if_id_valid ? if_id_pc :
                             (!meta_empty ? meta_fifo[meta_head].pc :
                              pc_addr);

    assign ic_fetch_valid = fetch_enable && !redirect_valid &&
                            (!meta_full || meta_pop);
    assign ic_fetch_addr = pc_addr;
    assign ic_resp_ready = !meta_empty &&
                           (!meta_head_current || redirect_valid ||
                            !packet_full || packet_pop);

    assign meta_push = ic_fetch_valid && ic_fetch_ready;
    assign meta_pop = ic_resp_valid && ic_resp_ready;

    assign pc_jump = redirect_valid ||
                     (meta_push && pred_taken);
    assign pc_step = meta_push && !pred_taken && !redirect_valid;
    assign pc_jump_delta =
        (redirect_valid ? redirect_addr : next_pc) - pc_addr;

    program_counter #(
        .COUNTER_BIT(ADDR_WIDTH),
        .PC_REMEMBER_NUM(PC_REMEMBER_NUM),
        .PC_PER_INCR(PC_PER_INCR),
        .ENABLE_RETURN_STACK(1'b0)
    ) u_program_counter (
        .ACLK(ACLK),
        .ARESETn(ARESETn),
        .req(pc_step),
        .req_jump(pc_jump),
        .jump_addr(pc_jump_delta),
        .req_return(1'b0),
        .err(pc_err),
        .o_addr(pc_addr)
    );

    branch_predictor #(
        .ADDR_WIDTH(ADDR_WIDTH),
        .BTB_ENTRIES(BTB_ENTRIES),
        .PC_INCR(PC_PER_INCR)
    ) u_branch_predictor (
        .ACLK(ACLK),
        .ARESETn(ARESETn),
        .lookup_pc(pc_addr),
        .predict_valid(pred_valid),
        .predict_taken(pred_taken),
        .predict_target(pred_target),
        .update_valid(bp_update_valid),
        .update_is_branch(bp_update_is_branch),
        .update_pc(bp_update_pc),
        .update_taken(bp_update_taken),
        .update_target(bp_update_target)
    );

    inst_cache #(
        .WIDTH_INST(WIDTH_INST),
        .NUM_CACHE(ICACHE_LINES),
        .CACHE_LINE_BYTES(CACHE_LINE_BYTES),
        .AXI_ADDR_WIDTH(ADDR_WIDTH),
        .AXI_DATA_WIDTH(AXI_DATA_WIDTH),
        .CACHE_REQ_LEN_WIDTH(CACHE_REQ_LEN_WIDTH)
    ) u_inst_cache (
        .ACLK(ACLK),
        .ARESETn(ARESETn),
        .fetch_req_valid(ic_fetch_valid),
        .fetch_req_ready(ic_fetch_ready),
        .fetch_req_addr(ic_fetch_addr),
        .fetch_resp_valid(ic_resp_valid),
        .fetch_resp_ready(ic_resp_ready),
        .fetch_resp_inst(ic_resp_inst),
        .fetch_resp_addr(ic_resp_addr),
        .fetch_resp_status(ic_resp_status),
        .fetch_resp_hit(ic_resp_hit),
        .i_req_valid(i_req_valid),
        .i_req_ready(i_req_ready),
        .i_req_addr(i_req_addr),
        .i_req_len(i_req_len),
        .i_resp_valid(i_resp_valid),
        .i_resp_ready(i_resp_ready),
        .i_resp_data(i_resp_data),
        .i_resp_status(i_resp_status),
        .i_resp_last(i_resp_last)
    );

    always_ff @(posedge ACLK or negedge ARESETn) begin
        if (!ARESETn) begin
            meta_head <= '0;
            meta_tail <= '0;
            meta_count <= '0;
            fetch_epoch <= '0;
            for (int i = 0; i < FETCH_META_DEPTH; i++)
                meta_fifo[i] <= '0;
        end
        else begin
            if (redirect_valid)
                fetch_epoch <= fetch_epoch + 1'b1;

            if (meta_push) begin
                meta_fifo[meta_tail].pc <= pc_addr;
                meta_fifo[meta_tail].pred_taken <= pred_taken;
                meta_fifo[meta_tail].pred_target <= pred_target;
                meta_fifo[meta_tail].epoch <= fetch_epoch;
                meta_tail <= meta_next(meta_tail);
            end

            if (meta_pop)
                meta_head <= meta_next(meta_head);

            unique case ({meta_push, meta_pop})
                2'b10: meta_count <= meta_count + 1'b1;
                2'b01: meta_count <= meta_count - 1'b1;
                default: meta_count <= meta_count;
            endcase
        end
    end

    always_ff @(posedge ACLK or negedge ARESETn) begin
        if (!ARESETn) begin
            packet_head <= '0;
            packet_tail <= '0;
            packet_count <= '0;
            for (int i = 0; i < FETCH_PACKET_DEPTH; i++)
                packet_fifo[i] <= '0;
        end
        else if (redirect_valid) begin
            packet_head <= '0;
            packet_tail <= '0;
            packet_count <= '0;
        end
        else begin
            if (packet_push) begin
                packet_fifo[packet_tail].pc <= meta_fifo[meta_head].pc;
                packet_fifo[packet_tail].inst <= ic_resp_inst;
                packet_fifo[packet_tail].pred_taken <=
                    meta_fifo[meta_head].pred_taken;
                packet_fifo[packet_tail].pred_target <=
                    meta_fifo[meta_head].pred_target;
                packet_fifo[packet_tail].cache_hit <= ic_resp_hit;
                packet_fifo[packet_tail].status <= ic_resp_status;
                packet_tail <= packet_next(packet_tail);
            end
            if (packet_pop)
                packet_head <= packet_next(packet_head);

            unique case ({packet_push, packet_pop})
                2'b10: packet_count <= packet_count + 1'b1;
                2'b01: packet_count <= packet_count - 1'b1;
                default: packet_count <= packet_count;
            endcase
        end
    end

endmodule
