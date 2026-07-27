module write_transaction_tracker #(
    parameter int NUM_MASTER      = 3,
    parameter int NUM_SLAVE       = 3,
    parameter int ID_WIDTH        = 4,
    parameter int ADDR_WIDTH      = 32,
    parameter int LEN_WIDTH       = 8,
    parameter int SIZE_WIDTH      = 3,
    parameter int BURST_WIDTH     = 2,
    parameter int W_PAYLOAD_WIDTH = 37,
    parameter int RESP_WIDTH      = 2,
    parameter int MASTER_WIDTH    = (NUM_MASTER <= 1) ? 1 : $clog2(NUM_MASTER)
) (
    input wire ACLK,
    input wire ARESETn,

    input  wire [NUM_SLAVE*MASTER_WIDTH-1:0] s_aw_source_master,
    input  wire [NUM_SLAVE*ID_WIDTH-1:0]     s_aw_id,
    input  wire [NUM_SLAVE*ADDR_WIDTH-1:0]   s_aw_addr,
    input  wire [NUM_SLAVE*LEN_WIDTH-1:0]    s_aw_len,
    input  wire [NUM_SLAVE*SIZE_WIDTH-1:0]   s_aw_size,
    input  wire [NUM_SLAVE*BURST_WIDTH-1:0]  s_aw_burst,
    input  wire [NUM_SLAVE-1:0]              s_aw_drop,
    input  wire [NUM_SLAVE-1:0]              s_aw_valid,
    output wire [NUM_SLAVE-1:0]              s_aw_ready,

    input  wire [NUM_MASTER*W_PAYLOAD_WIDTH-1:0] s_w_payload,
    input  wire [NUM_MASTER-1:0]                 s_w_valid,
    output wire [NUM_MASTER-1:0]                 s_w_ready,

    output wire [NUM_SLAVE*W_PAYLOAD_WIDTH-1:0]  m_w_payload,
    output wire [NUM_SLAVE-1:0]                  m_w_valid,
    input  wire [NUM_SLAVE-1:0]                  m_w_ready,

    input  wire [NUM_SLAVE-1:0]                  write_response_valid,
    input  wire [NUM_SLAVE-1:0]                  write_response_success,

    output wire [NUM_SLAVE*MASTER_WIDTH-1:0] local_b_master,
    output wire [NUM_SLAVE*ID_WIDTH-1:0]     local_b_id,
    output wire [NUM_SLAVE*RESP_WIDTH-1:0]   local_b_resp,
    output wire [NUM_SLAVE-1:0]              local_b_valid,
    input  wire [NUM_SLAVE-1:0]              local_b_ready,

    output wire [NUM_SLAVE*MASTER_WIDTH-1:0] write_commit_master,
    output wire [NUM_SLAVE*ADDR_WIDTH-1:0]   write_commit_addr,
    output wire [NUM_SLAVE*LEN_WIDTH-1:0]    write_commit_len,
    output wire [NUM_SLAVE*SIZE_WIDTH-1:0]   write_commit_size,
    output wire [NUM_SLAVE*BURST_WIDTH-1:0]  write_commit_burst,
    output wire [NUM_SLAVE-1:0]              write_commit_valid,

    output wire [NUM_SLAVE-1:0] w_early_last_error,
    output wire [NUM_SLAVE-1:0] w_missing_last_error
);

    localparam integer BEAT_COUNT_WIDTH = LEN_WIDTH + 1;

    reg [NUM_SLAVE-1:0] active;
    reg [NUM_SLAVE-1:0] drop_write;
    reg [MASTER_WIDTH-1:0] owner_master [0:NUM_SLAVE-1];
    reg [ID_WIDTH-1:0] owner_id [0:NUM_SLAVE-1];
    reg [ADDR_WIDTH-1:0] owner_addr [0:NUM_SLAVE-1];
    reg [LEN_WIDTH-1:0] owner_len [0:NUM_SLAVE-1];
    reg [SIZE_WIDTH-1:0] owner_size [0:NUM_SLAVE-1];
    reg [BURST_WIDTH-1:0] owner_burst [0:NUM_SLAVE-1];
    reg [NUM_SLAVE-1:0] response_pending;
    reg [BEAT_COUNT_WIDTH-1:0] beats_remaining [0:NUM_SLAVE-1];

    reg [NUM_SLAVE-1:0] aw_ready_reg;
    reg [NUM_MASTER-1:0] w_ready_reg;
    reg [NUM_SLAVE-1:0] w_valid_reg;
    reg [W_PAYLOAD_WIDTH-1:0] w_payload_reg [0:NUM_SLAVE-1];
    reg [NUM_MASTER-1:0] master_busy;

    reg [MASTER_WIDTH-1:0] local_b_master_reg [0:NUM_SLAVE-1];
    reg [ID_WIDTH-1:0] local_b_id_reg [0:NUM_SLAVE-1];
    reg [RESP_WIDTH-1:0] local_b_resp_reg [0:NUM_SLAVE-1];
    reg [NUM_SLAVE-1:0] local_b_valid_reg;

    reg [MASTER_WIDTH-1:0] commit_master_reg [0:NUM_SLAVE-1];
    reg [ADDR_WIDTH-1:0] commit_addr_reg [0:NUM_SLAVE-1];
    reg [LEN_WIDTH-1:0] commit_len_reg [0:NUM_SLAVE-1];
    reg [SIZE_WIDTH-1:0] commit_size_reg [0:NUM_SLAVE-1];
    reg [BURST_WIDTH-1:0] commit_burst_reg [0:NUM_SLAVE-1];
    reg [NUM_SLAVE-1:0] commit_valid_reg;
    reg [NUM_SLAVE-1:0] early_last_reg;
    reg [NUM_SLAVE-1:0] missing_last_reg;

    assign s_aw_ready = aw_ready_reg;
    assign s_w_ready = w_ready_reg;
    assign m_w_valid = w_valid_reg;
    assign local_b_valid = local_b_valid_reg;
    assign write_commit_valid = commit_valid_reg;
    assign w_early_last_error = early_last_reg;
    assign w_missing_last_error = missing_last_reg;

    genvar output_index;
    generate
        for (output_index=0; output_index<NUM_SLAVE; output_index=output_index+1) begin : gen_outputs
            assign m_w_payload[output_index*W_PAYLOAD_WIDTH +: W_PAYLOAD_WIDTH] =
                w_payload_reg[output_index];
            assign local_b_master[output_index*MASTER_WIDTH +: MASTER_WIDTH] =
                local_b_master_reg[output_index];
            assign local_b_id[output_index*ID_WIDTH +: ID_WIDTH] = local_b_id_reg[output_index];
            assign local_b_resp[output_index*RESP_WIDTH +: RESP_WIDTH] = local_b_resp_reg[output_index];
            assign write_commit_master[output_index*MASTER_WIDTH +: MASTER_WIDTH] =
                commit_master_reg[output_index];
            assign write_commit_addr[output_index*ADDR_WIDTH +: ADDR_WIDTH] =
                commit_addr_reg[output_index];
            assign write_commit_len[output_index*LEN_WIDTH +: LEN_WIDTH] =
                commit_len_reg[output_index];
            assign write_commit_size[output_index*SIZE_WIDTH +: SIZE_WIDTH] =
                commit_size_reg[output_index];
            assign write_commit_burst[output_index*BURST_WIDTH +: BURST_WIDTH] =
                commit_burst_reg[output_index];
        end
    endgenerate

    integer busy_index;
    integer ready_index;
    integer route_index;
    reg [MASTER_WIDTH-1:0] route_owner;
    reg route_last;
    reg route_expected_last;
    reg route_finishes;

    always @* begin
        master_busy = '0;
        for (busy_index=0; busy_index<NUM_SLAVE; busy_index=busy_index+1) begin
            if (active[busy_index])
                master_busy[owner_master[busy_index]] = 1'b1;
        end

        aw_ready_reg = '0;
        for (ready_index=0; ready_index<NUM_SLAVE; ready_index=ready_index+1) begin
            if (!active[ready_index] && !response_pending[ready_index] &&
                !local_b_valid_reg[ready_index] &&
                !master_busy[s_aw_source_master[ready_index*MASTER_WIDTH +: MASTER_WIDTH]])
                aw_ready_reg[ready_index] = 1'b1;
        end

        w_ready_reg = '0;
        w_valid_reg = '0;
        for (route_index=0; route_index<NUM_SLAVE; route_index=route_index+1) begin
            w_payload_reg[route_index] = '0;
            route_owner = owner_master[route_index];
            route_last = s_w_payload[route_owner*W_PAYLOAD_WIDTH];
            route_expected_last = (beats_remaining[route_index] == 1);
            route_finishes = route_last || route_expected_last;

            if (active[route_index]) begin
                if (drop_write[route_index]) begin
                    w_ready_reg[route_owner] =
                        !route_finishes || !local_b_valid_reg[route_index] || local_b_ready[route_index];
                end
                else begin
                    w_payload_reg[route_index] =
                        s_w_payload[route_owner*W_PAYLOAD_WIDTH +: W_PAYLOAD_WIDTH];
                    w_valid_reg[route_index] = s_w_valid[route_owner];
                    w_ready_reg[route_owner] = m_w_ready[route_index];
                end
            end
        end
    end

    integer state_index;
    reg [MASTER_WIDTH-1:0] active_owner;
    reg observed_last;
    reg expected_last;
    reg beat_fire;
    always @(posedge ACLK or negedge ARESETn) begin
        if (!ARESETn) begin
            active <= '0;
            drop_write <= '0;
            response_pending <= '0;
            local_b_valid_reg <= '0;
            commit_valid_reg <= '0;
            early_last_reg <= '0;
            missing_last_reg <= '0;
            for (state_index=0; state_index<NUM_SLAVE; state_index=state_index+1) begin
                owner_master[state_index] <= '0;
                owner_id[state_index] <= '0;
                owner_addr[state_index] <= '0;
                owner_len[state_index] <= '0;
                owner_size[state_index] <= '0;
                owner_burst[state_index] <= '0;
                beats_remaining[state_index] <= '0;
                local_b_master_reg[state_index] <= '0;
                local_b_id_reg[state_index] <= '0;
                local_b_resp_reg[state_index] <= '0;
                commit_master_reg[state_index] <= '0;
                commit_addr_reg[state_index] <= '0;
                commit_len_reg[state_index] <= '0;
                commit_size_reg[state_index] <= '0;
                commit_burst_reg[state_index] <= '0;
            end
        end
        else begin
            commit_valid_reg <= '0;
            early_last_reg <= '0;
            missing_last_reg <= '0;

            for (state_index=0; state_index<NUM_SLAVE; state_index=state_index+1) begin
                if (local_b_valid_reg[state_index] && local_b_ready[state_index])
                    local_b_valid_reg[state_index] <= 1'b0;

                if (write_response_valid[state_index] && response_pending[state_index]) begin
                    response_pending[state_index] <= 1'b0;
                    if (write_response_success[state_index]) begin
                        commit_master_reg[state_index] <= owner_master[state_index];
                        commit_addr_reg[state_index] <= owner_addr[state_index];
                        commit_len_reg[state_index] <= owner_len[state_index];
                        commit_size_reg[state_index] <= owner_size[state_index];
                        commit_burst_reg[state_index] <= owner_burst[state_index];
                        commit_valid_reg[state_index] <= 1'b1;
                    end
                end

                if (s_aw_valid[state_index] && aw_ready_reg[state_index]) begin
                    active[state_index] <= 1'b1;
                    drop_write[state_index] <= s_aw_drop[state_index];
                    owner_master[state_index] <=
                        s_aw_source_master[state_index*MASTER_WIDTH +: MASTER_WIDTH];
                    owner_id[state_index] <= s_aw_id[state_index*ID_WIDTH +: ID_WIDTH];
                    owner_addr[state_index] <= s_aw_addr[state_index*ADDR_WIDTH +: ADDR_WIDTH];
                    owner_len[state_index] <= s_aw_len[state_index*LEN_WIDTH +: LEN_WIDTH];
                    owner_size[state_index] <= s_aw_size[state_index*SIZE_WIDTH +: SIZE_WIDTH];
                    owner_burst[state_index] <=
                        s_aw_burst[state_index*BURST_WIDTH +: BURST_WIDTH];
                    beats_remaining[state_index] <=
                        {1'b0, s_aw_len[state_index*LEN_WIDTH +: LEN_WIDTH]} + 1'b1;
                end

                active_owner = owner_master[state_index];
                observed_last = s_w_payload[active_owner*W_PAYLOAD_WIDTH];
                expected_last = (beats_remaining[state_index] == 1);
                beat_fire = active[state_index] && s_w_valid[active_owner] && w_ready_reg[active_owner];

                if (beat_fire) begin
                    if (observed_last && !expected_last)
                        early_last_reg[state_index] <= 1'b1;
                    if (!observed_last && expected_last)
                        missing_last_reg[state_index] <= 1'b1;

                    if (observed_last || expected_last) begin
                        active[state_index] <= 1'b0;
                        if (drop_write[state_index]) begin
                            local_b_master_reg[state_index] <= owner_master[state_index];
                            local_b_id_reg[state_index] <= owner_id[state_index];
                            local_b_resp_reg[state_index] <= {RESP_WIDTH{1'b0}};
                            local_b_valid_reg[state_index] <= 1'b1;
                        end
                        else begin
                            response_pending[state_index] <= 1'b1;
                        end
                    end
                    else begin
                        beats_remaining[state_index] <= beats_remaining[state_index] - 1'b1;
                    end
                end
            end
        end
    end

endmodule
