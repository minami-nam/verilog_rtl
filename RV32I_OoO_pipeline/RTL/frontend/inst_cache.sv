module inst_cache #(
    parameter int unsigned WIDTH_INST = 32,
    parameter int unsigned NUM_CACHE = 48,
    parameter int unsigned CACHE_LINE_BYTES = 16,

    parameter int unsigned AXI_ADDR_WIDTH = 32,
    parameter int unsigned AXI_DATA_WIDTH = 64,
    parameter int unsigned CACHE_REQ_LEN_WIDTH = 8,

    localparam int unsigned INST_BYTES = WIDTH_INST / 8,
    localparam int unsigned CACHE_LINE_WIDTH = CACHE_LINE_BYTES * 8,
    localparam int unsigned AXI_STRB_WIDTH = AXI_DATA_WIDTH / 8,
    localparam int unsigned CACHE_LINE_BEATS = CACHE_LINE_BYTES / AXI_STRB_WIDTH,
    localparam int unsigned LINE_INST_NUM = CACHE_LINE_BYTES / INST_BYTES,
    localparam int unsigned LINE_OFFSET_WIDTH = $clog2(CACHE_LINE_BYTES),
    localparam int unsigned WORD_OFFSET_WIDTH = (LINE_INST_NUM <= 1) ? 1 : $clog2(LINE_INST_NUM),
    localparam int unsigned INDEX_WIDTH = (NUM_CACHE <= 1) ? 1 : $clog2(NUM_CACHE),
    localparam int unsigned LINE_ADDR_WIDTH = AXI_ADDR_WIDTH - LINE_OFFSET_WIDTH,
    localparam logic [CACHE_REQ_LEN_WIDTH-1:0] REFILL_AXI_LEN = CACHE_LINE_BEATS - 1
) (
    input  logic                        ACLK,
    input  logic                        ARESETn,

    // Frontend fetch request channel
    input  logic                        fetch_req_valid,
    output logic                        fetch_req_ready,
    input  logic [AXI_ADDR_WIDTH-1:0]   fetch_req_addr,

    // Frontend fetch response channel
    output logic                        fetch_resp_valid,
    input  logic                        fetch_resp_ready,
    output logic [WIDTH_INST-1:0]       fetch_resp_inst,
    output logic [AXI_ADDR_WIDTH-1:0]   fetch_resp_addr,
    output logic [1:0]                  fetch_resp_status,
    output logic                        fetch_resp_hit,

    // Inst. Cache - Cache_reqmaker read request channel
    output logic                        i_req_valid,
    input  logic                        i_req_ready,
    output logic [AXI_ADDR_WIDTH-1:0]   i_req_addr,
    output logic [CACHE_REQ_LEN_WIDTH-1:0] i_req_len,

    // Inst. Cache - Cache_reqmaker read response channel
    input  logic                        i_resp_valid,
    output logic                        i_resp_ready,
    input  logic [CACHE_LINE_WIDTH-1:0] i_resp_data,
    input  logic [1:0]                  i_resp_status,
    input  logic                        i_resp_last
);

    typedef enum logic [1:0] {
        IC_IDLE,
        IC_MISS_REQ,
        IC_REFILL,
        IC_RESP
    } ic_state_e;

    ic_state_e state;

    logic [CACHE_LINE_WIDTH-1:0] cache_data [0:NUM_CACHE-1];
    logic [LINE_ADDR_WIDTH-1:0]  cache_tag  [0:NUM_CACHE-1];
    logic                       cache_valid[0:NUM_CACHE-1];

    logic resp_valid_reg;
    logic [WIDTH_INST-1:0] resp_inst_reg;
    logic [AXI_ADDR_WIDTH-1:0] resp_addr_reg;
    logic [1:0] resp_status_reg;
    logic resp_hit_reg;

    logic [AXI_ADDR_WIDTH-1:0] pending_addr;
    logic [LINE_ADDR_WIDTH-1:0] pending_line_addr;
    logic [INDEX_WIDTH-1:0] pending_index;
    logic [WORD_OFFSET_WIDTH-1:0] pending_word_offset;

    logic [LINE_ADDR_WIDTH-1:0] fetch_line_addr;
    logic [INDEX_WIDTH-1:0] fetch_index;
    logic [WORD_OFFSET_WIDTH-1:0] fetch_word_offset;
    logic fetch_hit;

    assign fetch_line_addr = fetch_req_addr[AXI_ADDR_WIDTH-1:LINE_OFFSET_WIDTH];
    assign fetch_index = fetch_line_addr % NUM_CACHE;
    assign fetch_word_offset = fetch_req_addr[LINE_OFFSET_WIDTH-1:2];
    assign fetch_hit = cache_valid[fetch_index] && (cache_tag[fetch_index] == fetch_line_addr);

    assign fetch_req_ready = (state == IC_IDLE) && (!resp_valid_reg || fetch_resp_ready);

    assign fetch_resp_valid = resp_valid_reg;
    assign fetch_resp_inst = resp_inst_reg;
    assign fetch_resp_addr = resp_addr_reg;
    assign fetch_resp_status = resp_status_reg;
    assign fetch_resp_hit = resp_hit_reg;

    assign i_req_valid = (state == IC_MISS_REQ);
    assign i_req_addr = {pending_line_addr, {LINE_OFFSET_WIDTH{1'b0}}};
    assign i_req_len = REFILL_AXI_LEN;
    assign i_resp_ready = (state == IC_REFILL);

    function automatic logic [WIDTH_INST-1:0] select_inst_from_line(
        input logic [CACHE_LINE_WIDTH-1:0] line_data,
        input logic [WORD_OFFSET_WIDTH-1:0] word_offset
    );
        select_inst_from_line = line_data[word_offset * WIDTH_INST +: WIDTH_INST];
    endfunction

    always @(posedge ACLK or negedge ARESETn) begin
        if (!ARESETn) begin
            for (int i = 0; i < NUM_CACHE; i++) begin
                cache_data[i] <= '0;
                cache_tag[i] <= '0;
                cache_valid[i] <= 1'b0;
            end
        end
        else begin
            if ((state == IC_REFILL) && i_resp_valid && i_resp_last && (i_resp_status == 2'b00)) begin
                cache_data[pending_index] <= i_resp_data;
                cache_tag[pending_index] <= pending_line_addr;
                cache_valid[pending_index] <= 1'b1;
            end
        end
    end

    always @(posedge ACLK or negedge ARESETn) begin
        if (!ARESETn) begin
            state <= IC_IDLE;
            resp_valid_reg <= 1'b0;
            resp_inst_reg <= '0;
            resp_addr_reg <= '0;
            resp_status_reg <= 2'b00;
            resp_hit_reg <= 1'b0;
            pending_addr <= '0;
            pending_line_addr <= '0;
            pending_index <= '0;
            pending_word_offset <= '0;
        end
        else begin
            if (resp_valid_reg && fetch_resp_ready) begin
                resp_valid_reg <= 1'b0;
            end

            case (state)
                IC_IDLE: begin
                    if (fetch_req_valid && fetch_req_ready) begin
                        if (fetch_hit) begin
                            resp_valid_reg <= 1'b1;
                            resp_inst_reg <= select_inst_from_line(cache_data[fetch_index], fetch_word_offset);
                            resp_addr_reg <= fetch_req_addr;
                            resp_status_reg <= 2'b00;
                            resp_hit_reg <= 1'b1;
                        end
                        else begin
                            pending_addr <= fetch_req_addr;
                            pending_line_addr <= fetch_line_addr;
                            pending_index <= fetch_index;
                            pending_word_offset <= fetch_word_offset;
                            state <= IC_MISS_REQ;
                        end
                    end
                end

                IC_MISS_REQ: begin
                    if (i_req_ready) begin
                        state <= IC_REFILL;
                    end
                end

                IC_REFILL: begin
                    if (i_resp_valid && i_resp_last) begin
                        resp_valid_reg <= 1'b1;
                        resp_inst_reg <= select_inst_from_line(i_resp_data, pending_word_offset);
                        resp_addr_reg <= pending_addr;
                        resp_status_reg <= i_resp_status;
                        resp_hit_reg <= 1'b0;
                        state <= IC_RESP;
                    end
                end

                IC_RESP: begin
                    if (resp_valid_reg && fetch_resp_ready) begin
                        state <= IC_IDLE;
                    end
                end

                default: begin
                    state <= IC_IDLE;
                end
            endcase
        end
    end

endmodule
