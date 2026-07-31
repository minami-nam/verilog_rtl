module data_cache #(
    parameter int unsigned DATA_WIDTH = 32,
    parameter int unsigned ADDR_WIDTH = 32,
    parameter int unsigned NUM_LINES = 64,
    parameter int unsigned CACHE_LINE_BYTES = 16,
    parameter int unsigned AXI_DATA_WIDTH = 64,
    parameter int unsigned CACHE_REQ_LEN_WIDTH = 8,
    parameter int unsigned MEM_ID_WIDTH = 5,
    parameter int unsigned MSHR_ENTRIES = 8,
    parameter int unsigned RESP_QUEUE_DEPTH = 16,

    localparam int unsigned DATA_STRB_WIDTH = DATA_WIDTH / 8,
    localparam int unsigned CACHE_LINE_WIDTH = CACHE_LINE_BYTES * 8,
    localparam int unsigned CACHE_STRB_WIDTH = CACHE_LINE_BYTES,
    localparam int unsigned AXI_STRB_WIDTH = AXI_DATA_WIDTH / 8,
    localparam int unsigned CACHE_LINE_BEATS =
        CACHE_LINE_BYTES / AXI_STRB_WIDTH,
    localparam int unsigned LINE_OFFSET_WIDTH =
        (CACHE_LINE_BYTES <= 1) ? 1 : $clog2(CACHE_LINE_BYTES),
    localparam int unsigned WORD_BYTES = DATA_WIDTH / 8,
    localparam int unsigned WORDS_PER_LINE =
        CACHE_LINE_BYTES / WORD_BYTES,
    localparam int unsigned WORD_OFFSET_WIDTH =
        (WORDS_PER_LINE <= 1) ? 1 : $clog2(WORDS_PER_LINE),
    localparam int unsigned INDEX_WIDTH =
        (NUM_LINES <= 1) ? 1 : $clog2(NUM_LINES),
    localparam int unsigned LINE_ADDR_WIDTH =
        ADDR_WIDTH - LINE_OFFSET_WIDTH,
    localparam int unsigned MSHR_IDX_WIDTH =
        (MSHR_ENTRIES <= 1) ? 1 : $clog2(MSHR_ENTRIES),
    localparam int unsigned MSHR_COUNT_WIDTH =
        (MSHR_ENTRIES <= 1) ? 1 : $clog2(MSHR_ENTRIES + 1),
    localparam int unsigned RESP_IDX_WIDTH =
        (RESP_QUEUE_DEPTH <= 1) ? 1 : $clog2(RESP_QUEUE_DEPTH),
    localparam int unsigned RESP_COUNT_WIDTH =
        (RESP_QUEUE_DEPTH <= 1) ? 1 : $clog2(RESP_QUEUE_DEPTH + 1),
    localparam logic [CACHE_REQ_LEN_WIDTH-1:0] LINE_AXI_LEN =
        CACHE_LINE_BEATS - 1
) (
    input  logic                        ACLK,
    input  logic                        ARESETn,

    input  logic                        mem_req_valid,
    output logic                        mem_req_ready,
    input  logic                        mem_req_write,
    input  logic [ADDR_WIDTH-1:0]       mem_req_addr,
    input  logic [DATA_WIDTH-1:0]       mem_req_wdata,
    input  logic [DATA_STRB_WIDTH-1:0]  mem_req_wstrb,
    input  logic [MEM_ID_WIDTH-1:0]     mem_req_id,

    output logic                        mem_resp_valid,
    input  logic                        mem_resp_ready,
    output logic [DATA_WIDTH-1:0]       mem_resp_rdata,
    output logic                        mem_resp_error,
    output logic [MEM_ID_WIDTH-1:0]     mem_resp_id,

    output logic                        d_req_valid,
    input  logic                        d_req_ready,
    output logic                        d_req_write,
    output logic [ADDR_WIDTH-1:0]       d_req_addr,
    output logic [CACHE_REQ_LEN_WIDTH-1:0] d_req_len,
    output logic [CACHE_LINE_WIDTH-1:0] d_req_wdata,
    output logic [CACHE_STRB_WIDTH-1:0] d_req_wstrb,
    output logic [MEM_ID_WIDTH-1:0]     d_req_id,

    input  logic                        d_resp_valid,
    output logic                        d_resp_ready,
    input  logic [CACHE_LINE_WIDTH-1:0] d_resp_rdata,
    input  logic [1:0]                  d_resp_status,
    input  logic                        d_resp_last,
    input  logic [MEM_ID_WIDTH-1:0]     d_resp_id
);

    typedef struct packed {
        logic                         valid;
        logic                         issued;
        logic                         needs_lower;
        logic                         write;
        logic [MEM_ID_WIDTH-1:0]      id;
        logic [ADDR_WIDTH-1:0]        addr;
        logic [LINE_ADDR_WIDTH-1:0]   line_addr;
        logic [INDEX_WIDTH-1:0]       index;
        logic [WORD_OFFSET_WIDTH-1:0] word_offset;
        logic [DATA_WIDTH-1:0]        wdata;
        logic [DATA_STRB_WIDTH-1:0]   wstrb;
    } mshr_entry_t;

    typedef struct packed {
        logic [MEM_ID_WIDTH-1:0]      id;
        logic [DATA_WIDTH-1:0]        data;
        logic                         error;
    } response_entry_t;

    logic [CACHE_LINE_WIDTH-1:0] cache_data [0:NUM_LINES-1];
    logic [LINE_ADDR_WIDTH-1:0] cache_tag [0:NUM_LINES-1];
    logic cache_valid [0:NUM_LINES-1];
    mshr_entry_t mshr [0:MSHR_ENTRIES-1];
    response_entry_t response_queue [0:RESP_QUEUE_DEPTH-1];

    logic [RESP_IDX_WIDTH-1:0] resp_head;
    logic [RESP_IDX_WIDTH-1:0] resp_tail;
    logic [RESP_COUNT_WIDTH-1:0] resp_count;
    logic [MSHR_COUNT_WIDTH-1:0] mshr_count;

    logic [LINE_ADDR_WIDTH-1:0] request_line_addr;
    logic [INDEX_WIDTH-1:0] request_index;
    logic [WORD_OFFSET_WIDTH-1:0] request_word_offset;
    logic request_hit;

    logic alloc_found;
    logic [MSHR_IDX_WIDTH-1:0] alloc_idx;
    logic hit_found;
    logic [MSHR_IDX_WIDTH-1:0] hit_idx;
    logic lower_req_found;
    logic [MSHR_IDX_WIDTH-1:0] lower_req_idx;
    logic lower_resp_found;
    logic [MSHR_IDX_WIDTH-1:0] lower_resp_idx;

    logic alloc_fire;
    logic hit_complete_fire;
    logic lower_req_fire;
    logic lower_resp_fire;
    logic cpu_resp_fire;
    logic resp_dual_space;
    response_entry_t hit_response;
    response_entry_t lower_response;

    logic [CACHE_LINE_WIDTH-1:0] lower_write_line_data;
    logic [CACHE_STRB_WIDTH-1:0] lower_write_line_strb;

    function automatic logic [RESP_IDX_WIDTH-1:0] resp_next(
        input logic [RESP_IDX_WIDTH-1:0] idx
    );
        if (idx == RESP_QUEUE_DEPTH-1)
            resp_next = '0;
        else
            resp_next = idx + 1'b1;
    endfunction

    function automatic logic [DATA_WIDTH-1:0] select_word(
        input logic [CACHE_LINE_WIDTH-1:0] line_data,
        input logic [WORD_OFFSET_WIDTH-1:0] word_offset
    );
        select_word =
            line_data[word_offset * DATA_WIDTH +: DATA_WIDTH];
    endfunction

    assign request_line_addr =
        mem_req_addr[ADDR_WIDTH-1:LINE_OFFSET_WIDTH];
    assign request_index = request_line_addr % NUM_LINES;
    assign request_word_offset =
        mem_req_addr[LINE_OFFSET_WIDTH-1:$clog2(WORD_BYTES)];
    assign request_hit = cache_valid[request_index] &&
                         (cache_tag[request_index] == request_line_addr);

    always_comb begin : mshr_search
        alloc_found = 1'b0;
        alloc_idx = '0;
        hit_found = 1'b0;
        hit_idx = '0;
        lower_req_found = 1'b0;
        lower_req_idx = '0;
        lower_resp_found = 1'b0;
        lower_resp_idx = '0;
        mshr_count = '0;

        for (int i = 0; i < MSHR_ENTRIES; i++) begin
            if (mshr[i].valid)
                mshr_count = mshr_count + 1'b1;
            if (!alloc_found && !mshr[i].valid) begin
                alloc_found = 1'b1;
                alloc_idx = i[MSHR_IDX_WIDTH-1:0];
            end
            if (!hit_found && mshr[i].valid &&
                !mshr[i].issued && !mshr[i].needs_lower) begin
                hit_found = 1'b1;
                hit_idx = i[MSHR_IDX_WIDTH-1:0];
            end
            if (!lower_req_found && mshr[i].valid &&
                !mshr[i].issued && mshr[i].needs_lower) begin
                lower_req_found = 1'b1;
                lower_req_idx = i[MSHR_IDX_WIDTH-1:0];
            end
            if (!lower_resp_found && mshr[i].valid &&
                mshr[i].issued &&
                (mshr[i].id == d_resp_id)) begin
                lower_resp_found = 1'b1;
                lower_resp_idx = i[MSHR_IDX_WIDTH-1:0];
            end
        end
    end

    assign mem_req_ready = alloc_found;
    assign alloc_fire = mem_req_valid && mem_req_ready;

    assign resp_dual_space = (resp_count <= RESP_QUEUE_DEPTH-2);
    assign hit_complete_fire = hit_found && resp_dual_space;

    assign d_req_valid = lower_req_found;
    assign d_req_write = mshr[lower_req_idx].write;
    assign d_req_addr = {
        mshr[lower_req_idx].line_addr,
        {LINE_OFFSET_WIDTH{1'b0}}
    };
    assign d_req_len = LINE_AXI_LEN;
    assign d_req_id = mshr[lower_req_idx].id;

    always_comb begin
        lower_write_line_data = '0;
        lower_write_line_strb = '0;
        lower_write_line_data[
            mshr[lower_req_idx].word_offset * DATA_WIDTH +:
            DATA_WIDTH
        ] = mshr[lower_req_idx].wdata;
        lower_write_line_strb[
            mshr[lower_req_idx].word_offset * DATA_STRB_WIDTH +:
            DATA_STRB_WIDTH
        ] = mshr[lower_req_idx].wstrb;
    end

    assign d_req_wdata = lower_write_line_data;
    assign d_req_wstrb = lower_write_line_strb;
    assign lower_req_fire = d_req_valid && d_req_ready;

    assign d_resp_ready = lower_resp_found &&
        ((resp_count < RESP_QUEUE_DEPTH) &&
         (!hit_found || resp_dual_space));
    assign lower_resp_fire = d_resp_valid && d_resp_ready && d_resp_last;

    always_comb begin
        hit_response = '0;
        hit_response.id = mshr[hit_idx].id;
        hit_response.data = select_word(
            cache_data[mshr[hit_idx].index],
            mshr[hit_idx].word_offset);

        lower_response = '0;
        lower_response.id = d_resp_id;
        lower_response.data = select_word(
            d_resp_rdata,
            mshr[lower_resp_idx].word_offset);
        lower_response.error = (d_resp_status != 2'b00);
    end

    assign mem_resp_valid = (resp_count != '0);
    assign mem_resp_id = response_queue[resp_head].id;
    assign mem_resp_rdata = response_queue[resp_head].data;
    assign mem_resp_error = response_queue[resp_head].error;
    assign cpu_resp_fire = mem_resp_valid && mem_resp_ready;

    always_ff @(posedge ACLK or negedge ARESETn) begin
        if (!ARESETn) begin
            for (int i = 0; i < NUM_LINES; i++) begin
                cache_data[i] <= '0;
                cache_tag[i] <= '0;
                cache_valid[i] <= 1'b0;
            end
        end
        else begin
            if (lower_resp_fire && !mshr[lower_resp_idx].write &&
                (d_resp_status == 2'b00)) begin
                cache_data[mshr[lower_resp_idx].index] <= d_resp_rdata;
                cache_tag[mshr[lower_resp_idx].index] <=
                    mshr[lower_resp_idx].line_addr;
                cache_valid[mshr[lower_resp_idx].index] <= 1'b1;
            end

            if (lower_resp_fire && mshr[lower_resp_idx].write &&
                (d_resp_status == 2'b00) &&
                cache_valid[mshr[lower_resp_idx].index] &&
                (cache_tag[mshr[lower_resp_idx].index] ==
                 mshr[lower_resp_idx].line_addr)) begin
                for (int byte_idx = 0;
                     byte_idx < DATA_STRB_WIDTH;
                     byte_idx++) begin
                    if (mshr[lower_resp_idx].wstrb[byte_idx])
                        cache_data[mshr[lower_resp_idx].index][
                            mshr[lower_resp_idx].word_offset * DATA_WIDTH +
                            byte_idx * 8 +: 8
                        ] <= mshr[lower_resp_idx].wdata[
                            byte_idx * 8 +: 8];
                end
            end
        end
    end

    always_ff @(posedge ACLK or negedge ARESETn) begin
        if (!ARESETn) begin
            for (int i = 0; i < MSHR_ENTRIES; i++)
                mshr[i] <= '0;
        end
        else begin
            if (alloc_fire) begin
                mshr[alloc_idx].valid <= 1'b1;
                mshr[alloc_idx].issued <= 1'b0;
                mshr[alloc_idx].needs_lower <=
                    mem_req_write || !request_hit;
                mshr[alloc_idx].write <= mem_req_write;
                mshr[alloc_idx].id <= mem_req_id;
                mshr[alloc_idx].addr <= mem_req_addr;
                mshr[alloc_idx].line_addr <= request_line_addr;
                mshr[alloc_idx].index <= request_index;
                mshr[alloc_idx].word_offset <= request_word_offset;
                mshr[alloc_idx].wdata <= mem_req_wdata;
                mshr[alloc_idx].wstrb <= mem_req_wstrb;
            end
            if (lower_req_fire)
                mshr[lower_req_idx].issued <= 1'b1;
            if (hit_complete_fire)
                mshr[hit_idx].valid <= 1'b0;
            if (lower_resp_fire)
                mshr[lower_resp_idx].valid <= 1'b0;
        end
    end

    always_ff @(posedge ACLK or negedge ARESETn) begin
        if (!ARESETn) begin
            resp_head <= '0;
            resp_tail <= '0;
            resp_count <= '0;
            for (int i = 0; i < RESP_QUEUE_DEPTH; i++)
                response_queue[i] <= '0;
        end
        else begin
            if (lower_resp_fire)
                response_queue[resp_tail] <= lower_response;
            if (hit_complete_fire) begin
                if (lower_resp_fire)
                    response_queue[resp_next(resp_tail)] <= hit_response;
                else
                    response_queue[resp_tail] <= hit_response;
            end

            if (cpu_resp_fire)
                resp_head <= resp_next(resp_head);

            unique case ({lower_resp_fire, hit_complete_fire})
                2'b01, 2'b10: resp_tail <= resp_next(resp_tail);
                2'b11: resp_tail <= resp_next(resp_next(resp_tail));
                default: resp_tail <= resp_tail;
            endcase

            unique case ({lower_resp_fire,
                          hit_complete_fire,
                          cpu_resp_fire})
                3'b001: resp_count <= resp_count - 1'b1;
                3'b010, 3'b100: resp_count <= resp_count + 1'b1;
                3'b110: resp_count <= resp_count + 2'd2;
                3'b111: resp_count <= resp_count + 1'b1;
                default: resp_count <= resp_count;
            endcase
        end
    end

endmodule
