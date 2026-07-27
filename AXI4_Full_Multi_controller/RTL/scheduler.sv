module axi_aw_scheduler #(
    parameter int NUM_MASTER     = 3,
    parameter int NUM_SLAVE      = 3,
    parameter int PAYLOAD_WIDTH  = 32,
    parameter int QOS_WIDTH      = 4,
    parameter int LEN_WIDTH      = 8,
    parameter int AGE_WIDTH      = 10,
    parameter int SCORE_WIDTH    = 16,
    parameter int QOS_SHIFT      = 8,
    parameter int AGE_SHIFT      = 3,
    parameter int BURST_SHIFT    = 0,
    parameter int MASTER_WIDTH   = (NUM_MASTER <= 1) ? 1 : $clog2(NUM_MASTER),
    parameter int SLAVE_WIDTH    = (NUM_SLAVE <= 1) ? 1 : $clog2(NUM_SLAVE)
) (
    input wire ACLK,
    input wire ARESETn,

    input  wire [NUM_MASTER*PAYLOAD_WIDTH-1:0] s_aw_payload,
    input  wire [NUM_MASTER*SLAVE_WIDTH-1:0]   s_aw_target,
    input  wire [NUM_MASTER*QOS_WIDTH-1:0]     s_aw_qos,
    input  wire [NUM_MASTER*LEN_WIDTH-1:0]     s_aw_len,
    input  wire [NUM_MASTER-1:0]               s_aw_valid,
    output wire [NUM_MASTER-1:0]               s_aw_ready,

    output wire [NUM_SLAVE*PAYLOAD_WIDTH-1:0]  m_aw_payload,
    output wire [NUM_SLAVE*MASTER_WIDTH-1:0]   m_aw_source_master,
    output wire [NUM_SLAVE-1:0]                m_aw_valid,
    input  wire [NUM_SLAVE-1:0]                m_aw_ready
);

    reg [PAYLOAD_WIDTH-1:0] payload_buffer [0:NUM_SLAVE-1];
    reg [MASTER_WIDTH-1:0] source_buffer [0:NUM_SLAVE-1];
    reg [AGE_WIDTH-1:0] request_age [0:NUM_MASTER-1];
    reg [MASTER_WIDTH-1:0] grant_master [0:NUM_SLAVE-1];
    reg [NUM_SLAVE-1:0] valid_reg;
    reg [NUM_SLAVE-1:0] grant_valid;
    reg [NUM_MASTER-1:0] ready_reg;

    assign s_aw_ready = ready_reg;
    assign m_aw_valid = valid_reg;

    function [SCORE_WIDTH-1:0] calculate_score;
        input [QOS_WIDTH-1:0] qos;
        input [AGE_WIDTH-1:0] age;
        input [LEN_WIDTH-1:0] burst_len;
        reg [SCORE_WIDTH-1:0] qos_term;
        reg [SCORE_WIDTH-1:0] age_term;
        reg [SCORE_WIDTH-1:0] burst_term;
        reg [SCORE_WIDTH+1:0] score_sum;
        begin
            qos_term = qos;
            qos_term = qos_term << QOS_SHIFT;
            age_term = age;
            age_term = age_term << AGE_SHIFT;
            burst_term = {LEN_WIDTH{1'b1}} - burst_len;
            burst_term = burst_term << BURST_SHIFT;
            score_sum = {2'b0, qos_term} + {2'b0, age_term} + {2'b0, burst_term};

            if (|score_sum[SCORE_WIDTH+1:SCORE_WIDTH])
                calculate_score = {SCORE_WIDTH{1'b1}};
            else
                calculate_score = score_sum[SCORE_WIDTH-1:0];
        end
    endfunction

    genvar aw_slave_index;
    generate
        for (aw_slave_index=0; aw_slave_index<NUM_SLAVE; aw_slave_index=aw_slave_index+1) begin : gen_aw_output
            assign m_aw_payload[aw_slave_index*PAYLOAD_WIDTH +: PAYLOAD_WIDTH] =
                payload_buffer[aw_slave_index];
            assign m_aw_source_master[aw_slave_index*MASTER_WIDTH +: MASTER_WIDTH] =
                source_buffer[aw_slave_index];
        end
    endgenerate

    // Only the registered grant is decoded combinationally. Score calculation
    // and winner registration are kept behind a clock boundary.
    integer aw_ready_slave;
    always @* begin
        ready_reg = '0;
        for (aw_ready_slave=0; aw_ready_slave<NUM_SLAVE; aw_ready_slave=aw_ready_slave+1) begin
            if (grant_valid[aw_ready_slave] &&
                (!valid_reg[aw_ready_slave] || m_aw_ready[aw_ready_slave])) begin
                ready_reg[grant_master[aw_ready_slave]] = 1'b1;
            end
        end
    end

    integer aw_master;
    integer aw_slave;
    integer aw_candidate;
    reg aw_best_valid;
    reg [MASTER_WIDTH-1:0] aw_best_master;
    reg [MASTER_WIDTH-1:0] aw_active_master;
    reg [SLAVE_WIDTH-1:0] aw_candidate_target;
    reg [SCORE_WIDTH-1:0] aw_best_score;
    reg [SCORE_WIDTH-1:0] aw_candidate_score;

    always @(posedge ACLK or negedge ARESETn) begin
        if (!ARESETn) begin
            valid_reg <= '0;
            grant_valid <= '0;
            for (aw_master=0; aw_master<NUM_MASTER; aw_master=aw_master+1)
                request_age[aw_master] <= '0;
            for (aw_slave=0; aw_slave<NUM_SLAVE; aw_slave=aw_slave+1) begin
                payload_buffer[aw_slave] <= '0;
                source_buffer[aw_slave] <= '0;
                grant_master[aw_slave] <= '0;
            end
        end
        else begin
            // Age only the current FIFO head. Saturation prevents wraparound.
            for (aw_master=0; aw_master<NUM_MASTER; aw_master=aw_master+1) begin
                if (!s_aw_valid[aw_master] ||
                    (s_aw_valid[aw_master] && ready_reg[aw_master])) begin
                    request_age[aw_master] <= '0;
                end
                else if (!(&request_age[aw_master])) begin
                    request_age[aw_master] <= request_age[aw_master] + 1'b1;
                end
            end

            for (aw_slave=0; aw_slave<NUM_SLAVE; aw_slave=aw_slave+1) begin
                if (valid_reg[aw_slave] && m_aw_ready[aw_slave])
                    valid_reg[aw_slave] <= 1'b0;

                if (grant_valid[aw_slave]) begin
                    aw_active_master = grant_master[aw_slave];
                    if (s_aw_valid[aw_active_master] && ready_reg[aw_active_master]) begin
                        payload_buffer[aw_slave] <=
                            s_aw_payload[aw_active_master*PAYLOAD_WIDTH +: PAYLOAD_WIDTH];
                        source_buffer[aw_slave] <= aw_active_master;
                        valid_reg[aw_slave] <= 1'b1;
                        grant_valid[aw_slave] <= 1'b0;
                    end
                end
                else if (!valid_reg[aw_slave] || m_aw_ready[aw_slave]) begin
                    aw_best_valid = 1'b0;
                    aw_best_master = '0;
                    aw_best_score = '0;

                    for (aw_candidate=0; aw_candidate<NUM_MASTER; aw_candidate=aw_candidate+1) begin
                        aw_candidate_target =
                            s_aw_target[aw_candidate*SLAVE_WIDTH +: SLAVE_WIDTH];
                        aw_candidate_score = calculate_score(
                            s_aw_qos[aw_candidate*QOS_WIDTH +: QOS_WIDTH],
                            request_age[aw_candidate],
                            s_aw_len[aw_candidate*LEN_WIDTH +: LEN_WIDTH]);

                        if (s_aw_valid[aw_candidate] &&
                            (aw_candidate_target == aw_slave) &&
                            (!aw_best_valid || aw_candidate_score > aw_best_score)) begin
                            aw_best_valid = 1'b1;
                            aw_best_master = aw_candidate;
                            aw_best_score = aw_candidate_score;
                        end
                    end

                    if (aw_best_valid) begin
                        grant_valid[aw_slave] <= 1'b1;
                        grant_master[aw_slave] <= aw_best_master;
                    end
                end
            end
        end
    end

endmodule

module axi_ar_scheduler #(
    parameter int NUM_MASTER     = 3,
    parameter int NUM_SLAVE      = 3,
    parameter int PAYLOAD_WIDTH  = 32,
    parameter int QOS_WIDTH      = 4,
    parameter int LEN_WIDTH      = 8,
    parameter int AGE_WIDTH      = 10,
    parameter int SCORE_WIDTH    = 16,
    parameter int QOS_SHIFT      = 8,
    parameter int AGE_SHIFT      = 3,
    parameter int BURST_SHIFT    = 0,
    parameter int MASTER_WIDTH   = (NUM_MASTER <= 1) ? 1 : $clog2(NUM_MASTER),
    parameter int SLAVE_WIDTH    = (NUM_SLAVE <= 1) ? 1 : $clog2(NUM_SLAVE)
) (
    input wire ACLK,
    input wire ARESETn,

    input  wire [NUM_MASTER*PAYLOAD_WIDTH-1:0] s_ar_payload,
    input  wire [NUM_MASTER*SLAVE_WIDTH-1:0]   s_ar_target,
    input  wire [NUM_MASTER*QOS_WIDTH-1:0]     s_ar_qos,
    input  wire [NUM_MASTER*LEN_WIDTH-1:0]     s_ar_len,
    input  wire [NUM_MASTER-1:0]               s_ar_valid,
    output wire [NUM_MASTER-1:0]               s_ar_ready,

    output wire [NUM_SLAVE*PAYLOAD_WIDTH-1:0]  m_ar_payload,
    output wire [NUM_SLAVE*MASTER_WIDTH-1:0]   m_ar_source_master,
    output wire [NUM_SLAVE-1:0]                m_ar_valid,
    input  wire [NUM_SLAVE-1:0]                m_ar_ready
);

    reg [PAYLOAD_WIDTH-1:0] payload_buffer [0:NUM_SLAVE-1];
    reg [MASTER_WIDTH-1:0] source_buffer [0:NUM_SLAVE-1];
    reg [AGE_WIDTH-1:0] request_age [0:NUM_MASTER-1];
    reg [MASTER_WIDTH-1:0] grant_master [0:NUM_SLAVE-1];
    reg [NUM_SLAVE-1:0] valid_reg;
    reg [NUM_SLAVE-1:0] grant_valid;
    reg [NUM_MASTER-1:0] ready_reg;

    assign s_ar_ready = ready_reg;
    assign m_ar_valid = valid_reg;

    function [SCORE_WIDTH-1:0] calculate_score;
        input [QOS_WIDTH-1:0] qos;
        input [AGE_WIDTH-1:0] age;
        input [LEN_WIDTH-1:0] burst_len;
        reg [SCORE_WIDTH-1:0] qos_term;
        reg [SCORE_WIDTH-1:0] age_term;
        reg [SCORE_WIDTH-1:0] burst_term;
        reg [SCORE_WIDTH+1:0] score_sum;
        begin
            qos_term = qos;
            qos_term = qos_term << QOS_SHIFT;
            age_term = age;
            age_term = age_term << AGE_SHIFT;
            burst_term = {LEN_WIDTH{1'b1}} - burst_len;
            burst_term = burst_term << BURST_SHIFT;
            score_sum = {2'b0, qos_term} + {2'b0, age_term} + {2'b0, burst_term};

            if (|score_sum[SCORE_WIDTH+1:SCORE_WIDTH])
                calculate_score = {SCORE_WIDTH{1'b1}};
            else
                calculate_score = score_sum[SCORE_WIDTH-1:0];
        end
    endfunction

    genvar ar_slave_index;
    generate
        for (ar_slave_index=0; ar_slave_index<NUM_SLAVE; ar_slave_index=ar_slave_index+1) begin : gen_ar_output
            assign m_ar_payload[ar_slave_index*PAYLOAD_WIDTH +: PAYLOAD_WIDTH] =
                payload_buffer[ar_slave_index];
            assign m_ar_source_master[ar_slave_index*MASTER_WIDTH +: MASTER_WIDTH] =
                source_buffer[ar_slave_index];
        end
    endgenerate

    integer ar_ready_slave;
    always @* begin
        ready_reg = '0;
        for (ar_ready_slave=0; ar_ready_slave<NUM_SLAVE; ar_ready_slave=ar_ready_slave+1) begin
            if (grant_valid[ar_ready_slave] &&
                (!valid_reg[ar_ready_slave] || m_ar_ready[ar_ready_slave])) begin
                ready_reg[grant_master[ar_ready_slave]] = 1'b1;
            end
        end
    end

    integer ar_master;
    integer ar_slave;
    integer ar_candidate;
    reg ar_best_valid;
    reg [MASTER_WIDTH-1:0] ar_best_master;
    reg [MASTER_WIDTH-1:0] ar_active_master;
    reg [SLAVE_WIDTH-1:0] ar_candidate_target;
    reg [SCORE_WIDTH-1:0] ar_best_score;
    reg [SCORE_WIDTH-1:0] ar_candidate_score;

    always @(posedge ACLK or negedge ARESETn) begin
        if (!ARESETn) begin
            valid_reg <= '0;
            grant_valid <= '0;
            for (ar_master=0; ar_master<NUM_MASTER; ar_master=ar_master+1)
                request_age[ar_master] <= '0;
            for (ar_slave=0; ar_slave<NUM_SLAVE; ar_slave=ar_slave+1) begin
                payload_buffer[ar_slave] <= '0;
                source_buffer[ar_slave] <= '0;
                grant_master[ar_slave] <= '0;
            end
        end
        else begin
            for (ar_master=0; ar_master<NUM_MASTER; ar_master=ar_master+1) begin
                if (!s_ar_valid[ar_master] ||
                    (s_ar_valid[ar_master] && ready_reg[ar_master])) begin
                    request_age[ar_master] <= '0;
                end
                else if (!(&request_age[ar_master])) begin
                    request_age[ar_master] <= request_age[ar_master] + 1'b1;
                end
            end

            for (ar_slave=0; ar_slave<NUM_SLAVE; ar_slave=ar_slave+1) begin
                if (valid_reg[ar_slave] && m_ar_ready[ar_slave])
                    valid_reg[ar_slave] <= 1'b0;

                if (grant_valid[ar_slave]) begin
                    ar_active_master = grant_master[ar_slave];
                    if (s_ar_valid[ar_active_master] && ready_reg[ar_active_master]) begin
                        payload_buffer[ar_slave] <=
                            s_ar_payload[ar_active_master*PAYLOAD_WIDTH +: PAYLOAD_WIDTH];
                        source_buffer[ar_slave] <= ar_active_master;
                        valid_reg[ar_slave] <= 1'b1;
                        grant_valid[ar_slave] <= 1'b0;
                    end
                end
                else if (!valid_reg[ar_slave] || m_ar_ready[ar_slave]) begin
                    ar_best_valid = 1'b0;
                    ar_best_master = '0;
                    ar_best_score = '0;

                    for (ar_candidate=0; ar_candidate<NUM_MASTER; ar_candidate=ar_candidate+1) begin
                        ar_candidate_target =
                            s_ar_target[ar_candidate*SLAVE_WIDTH +: SLAVE_WIDTH];
                        ar_candidate_score = calculate_score(
                            s_ar_qos[ar_candidate*QOS_WIDTH +: QOS_WIDTH],
                            request_age[ar_candidate],
                            s_ar_len[ar_candidate*LEN_WIDTH +: LEN_WIDTH]);

                        if (s_ar_valid[ar_candidate] &&
                            (ar_candidate_target == ar_slave) &&
                            (!ar_best_valid || ar_candidate_score > ar_best_score)) begin
                            ar_best_valid = 1'b1;
                            ar_best_master = ar_candidate;
                            ar_best_score = ar_candidate_score;
                        end
                    end

                    if (ar_best_valid) begin
                        grant_valid[ar_slave] <= 1'b1;
                        grant_master[ar_slave] <= ar_best_master;
                    end
                end
            end
        end
    end

endmodule
