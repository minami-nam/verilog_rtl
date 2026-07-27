module axi_response_router #(
    parameter int NUM_MASTER   = 3,
    parameter int NUM_SLAVE    = 3,
    parameter int ID_WIDTH     = 4,
    parameter int DATA_WIDTH   = 32,
    parameter int RESP_WIDTH   = 2,
    parameter int MASTER_WIDTH = (NUM_MASTER <= 1) ? 1 : $clog2(NUM_MASTER),
    parameter int SLAVE_WIDTH  = (NUM_SLAVE <= 1) ? 1 : $clog2(NUM_SLAVE)
) (
    input wire ACLK,
    input wire ARESETn,

    input  wire [NUM_SLAVE*MASTER_WIDTH-1:0] b_route_master,
    input  wire [NUM_SLAVE*ID_WIDTH-1:0]     b_route_id,
    input  wire [NUM_SLAVE-1:0]              b_route_exclusive,
    input  wire [NUM_SLAVE-1:0]              b_route_valid,
    output wire [NUM_SLAVE-1:0]              b_route_ready,

    input  wire [NUM_SLAVE*MASTER_WIDTH-1:0] r_route_master,
    input  wire [NUM_SLAVE*ID_WIDTH-1:0]     r_route_id,
    input  wire [NUM_SLAVE-1:0]              r_route_exclusive,
    input  wire [NUM_SLAVE-1:0]              r_route_valid,
    output wire [NUM_SLAVE-1:0]              r_route_ready,

    input  wire [NUM_SLAVE*ID_WIDTH-1:0]    s_axi_bid,
    input  wire [NUM_SLAVE*RESP_WIDTH-1:0]  s_axi_bresp,
    input  wire [NUM_SLAVE-1:0]             s_axi_bvalid,
    output wire [NUM_SLAVE-1:0]             s_axi_bready,

    output wire [NUM_SLAVE-1:0]             write_response_valid,
    output wire [NUM_SLAVE-1:0]             write_response_success,

    input  wire [NUM_SLAVE*ID_WIDTH-1:0]     local_bid,
    input  wire [NUM_SLAVE*RESP_WIDTH-1:0]   local_bresp,
    input  wire [NUM_SLAVE*MASTER_WIDTH-1:0] local_bmaster,
    input  wire [NUM_SLAVE-1:0]              local_bvalid,
    output wire [NUM_SLAVE-1:0]              local_bready,

    output wire [NUM_MASTER*ID_WIDTH-1:0]    m_axi_bid,
    output wire [NUM_MASTER*RESP_WIDTH-1:0]  m_axi_bresp,
    output wire [NUM_MASTER-1:0]             m_axi_bvalid,
    input  wire [NUM_MASTER-1:0]             m_axi_bready,

    input  wire [NUM_SLAVE*ID_WIDTH-1:0]    s_axi_rid,
    input  wire [NUM_SLAVE*DATA_WIDTH-1:0]  s_axi_rdata,
    input  wire [NUM_SLAVE*RESP_WIDTH-1:0]  s_axi_rresp,
    input  wire [NUM_SLAVE-1:0]             s_axi_rlast,
    input  wire [NUM_SLAVE-1:0]             s_axi_rvalid,
    output wire [NUM_SLAVE-1:0]             s_axi_rready,

    output wire [NUM_MASTER*ID_WIDTH-1:0]    m_axi_rid,
    output wire [NUM_MASTER*DATA_WIDTH-1:0]  m_axi_rdata,
    output wire [NUM_MASTER*RESP_WIDTH-1:0]  m_axi_rresp,
    output wire [NUM_MASTER-1:0]             m_axi_rlast,
    output wire [NUM_MASTER-1:0]             m_axi_rvalid,
    input  wire [NUM_MASTER-1:0]             m_axi_rready
);

    reg [NUM_SLAVE-1:0] b_route_active;
    reg [MASTER_WIDTH-1:0] b_owner [0:NUM_SLAVE-1];
    reg [ID_WIDTH-1:0] b_original_id [0:NUM_SLAVE-1];
    reg [NUM_SLAVE-1:0] b_exclusive;
    reg [NUM_SLAVE-1:0] r_route_active;
    reg [MASTER_WIDTH-1:0] r_owner [0:NUM_SLAVE-1];
    reg [ID_WIDTH-1:0] r_original_id [0:NUM_SLAVE-1];
    reg [NUM_SLAVE-1:0] r_exclusive;

    reg [NUM_MASTER-1:0] b_out_valid;
    reg [ID_WIDTH-1:0] b_out_id [0:NUM_MASTER-1];
    reg [RESP_WIDTH-1:0] b_out_resp [0:NUM_MASTER-1];
    reg [NUM_MASTER-1:0] r_out_valid;
    reg [ID_WIDTH-1:0] r_out_id [0:NUM_MASTER-1];
    reg [DATA_WIDTH-1:0] r_out_data [0:NUM_MASTER-1];
    reg [RESP_WIDTH-1:0] r_out_resp [0:NUM_MASTER-1];
    reg [NUM_MASTER-1:0] r_out_last;

    reg [NUM_MASTER-1:0] r_lock_valid;
    reg [SLAVE_WIDTH-1:0] r_lock_slave [0:NUM_MASTER-1];

    reg [NUM_SLAVE-1:0] s_bready_reg;
    reg [NUM_SLAVE-1:0] local_bready_reg;
    reg [NUM_SLAVE-1:0] s_rready_reg;

    assign b_route_ready = ~b_route_active;
    assign r_route_ready = ~r_route_active;
    assign s_axi_bready = s_bready_reg;
    assign local_bready = local_bready_reg;
    assign s_axi_rready = s_rready_reg;
    assign m_axi_bvalid = b_out_valid;
    assign m_axi_rvalid = r_out_valid;
    assign m_axi_rlast = r_out_last;

    genvar response_output;
    generate
        for (response_output=0; response_output<NUM_SLAVE;
             response_output=response_output+1) begin : gen_write_response
            assign write_response_valid[response_output] =
                s_axi_bvalid[response_output] && s_bready_reg[response_output];
            assign write_response_success[response_output] =
                !s_axi_bresp[response_output*RESP_WIDTH + RESP_WIDTH-1];
        end
    endgenerate

    genvar master_output;
    generate
        for (master_output=0; master_output<NUM_MASTER; master_output=master_output+1) begin : gen_master_outputs
            assign m_axi_bid[master_output*ID_WIDTH +: ID_WIDTH] = b_out_id[master_output];
            assign m_axi_bresp[master_output*RESP_WIDTH +: RESP_WIDTH] = b_out_resp[master_output];
            assign m_axi_rid[master_output*ID_WIDTH +: ID_WIDTH] = r_out_id[master_output];
            assign m_axi_rdata[master_output*DATA_WIDTH +: DATA_WIDTH] = r_out_data[master_output];
            assign m_axi_rresp[master_output*RESP_WIDTH +: RESP_WIDTH] = r_out_resp[master_output];
        end
    endgenerate

    integer select_master;
    integer select_slave;
    reg [NUM_MASTER-1:0] b_selected;
    reg [NUM_MASTER-1:0] r_selected;
    reg [SLAVE_WIDTH-1:0] locked_slave;

    // 이 부분은 한 번 seq하게 끊을 필요성도 있음.
    always @* begin
        s_bready_reg = '0;
        local_bready_reg = '0;
        s_rready_reg = '0;
        b_selected = '0;
        r_selected = '0;

        for (select_master=0; select_master<NUM_MASTER; select_master=select_master+1) begin
            if (!b_out_valid[select_master] || m_axi_bready[select_master]) begin
                for (select_slave=0; select_slave<NUM_SLAVE; select_slave=select_slave+1) begin
                    if (!b_selected[select_master] && b_route_active[select_slave] &&
                        (b_owner[select_slave] == select_master) && s_axi_bvalid[select_slave]) begin
                        s_bready_reg[select_slave] = 1'b1;
                        b_selected[select_master] = 1'b1;
                    end
                end
                for (select_slave=0; select_slave<NUM_SLAVE; select_slave=select_slave+1) begin
                    if (!b_selected[select_master] && local_bvalid[select_slave] &&
                        (local_bmaster[select_slave*MASTER_WIDTH +: MASTER_WIDTH] == select_master)) begin
                        local_bready_reg[select_slave] = 1'b1;
                        b_selected[select_master] = 1'b1;
                    end
                end
            end

            if (!r_out_valid[select_master] || m_axi_rready[select_master]) begin
                if (r_lock_valid[select_master]) begin
                    locked_slave = r_lock_slave[select_master];
                    if (r_route_active[locked_slave] && s_axi_rvalid[locked_slave])
                        s_rready_reg[locked_slave] = 1'b1;
                end
                else begin
                    for (select_slave=0; select_slave<NUM_SLAVE; select_slave=select_slave+1) begin
                        if (!r_selected[select_master] && r_route_active[select_slave] &&
                            (r_owner[select_slave] == select_master) && s_axi_rvalid[select_slave]) begin
                            s_rready_reg[select_slave] = 1'b1;
                            r_selected[select_master] = 1'b1;
                        end
                    end
                end
            end
        end
    end

    integer state_master;
    integer state_slave;
    reg [MASTER_WIDTH-1:0] response_master;
    always @(posedge ACLK or negedge ARESETn) begin
        if (!ARESETn) begin
            b_route_active <= '0;
            b_exclusive <= '0;
            r_route_active <= '0;
            r_exclusive <= '0;
            b_out_valid <= '0;
            r_out_valid <= '0;
            r_out_last <= '0;
            r_lock_valid <= '0;
            for (state_slave=0; state_slave<NUM_SLAVE; state_slave=state_slave+1) begin
                b_owner[state_slave] <= '0;
                b_original_id[state_slave] <= '0;
                r_owner[state_slave] <= '0;
                r_original_id[state_slave] <= '0;
            end
            for (state_master=0; state_master<NUM_MASTER; state_master=state_master+1) begin
                b_out_id[state_master] <= '0;
                b_out_resp[state_master] <= '0;
                r_out_id[state_master] <= '0;
                r_out_data[state_master] <= '0;
                r_out_resp[state_master] <= '0;
                r_lock_slave[state_master] <= '0;
            end
        end
        else begin
            for (state_master=0; state_master<NUM_MASTER; state_master=state_master+1) begin
                if (b_out_valid[state_master] && m_axi_bready[state_master])
                    b_out_valid[state_master] <= 1'b0;
                if (r_out_valid[state_master] && m_axi_rready[state_master])
                    r_out_valid[state_master] <= 1'b0;
            end

            for (state_slave=0; state_slave<NUM_SLAVE; state_slave=state_slave+1) begin
                if (b_route_valid[state_slave] && b_route_ready[state_slave]) begin
                    b_route_active[state_slave] <= 1'b1;
                    b_owner[state_slave] <=
                        b_route_master[state_slave*MASTER_WIDTH +: MASTER_WIDTH];
                    b_original_id[state_slave] <= b_route_id[state_slave*ID_WIDTH +: ID_WIDTH];
                    b_exclusive[state_slave] <= b_route_exclusive[state_slave];
                end
                if (r_route_valid[state_slave] && r_route_ready[state_slave]) begin
                    r_route_active[state_slave] <= 1'b1;
                    r_owner[state_slave] <=
                        r_route_master[state_slave*MASTER_WIDTH +: MASTER_WIDTH];
                    r_original_id[state_slave] <= r_route_id[state_slave*ID_WIDTH +: ID_WIDTH];
                    r_exclusive[state_slave] <= r_route_exclusive[state_slave];
                end

                if (s_axi_bvalid[state_slave] && s_bready_reg[state_slave]) begin
                    response_master = b_owner[state_slave];
                    b_out_id[response_master] <= b_original_id[state_slave];
                    if (b_exclusive[state_slave] &&
                        (s_axi_bresp[state_slave*RESP_WIDTH +: RESP_WIDTH] == {RESP_WIDTH{1'b0}}))
                        b_out_resp[response_master] <= {{(RESP_WIDTH-1){1'b0}}, 1'b1};
                    else
                        b_out_resp[response_master] <=
                            s_axi_bresp[state_slave*RESP_WIDTH +: RESP_WIDTH];
                    b_out_valid[response_master] <= 1'b1;
                    b_route_active[state_slave] <= 1'b0;
                end

                if (local_bvalid[state_slave] && local_bready_reg[state_slave]) begin
                    response_master =
                        local_bmaster[state_slave*MASTER_WIDTH +: MASTER_WIDTH];
                    b_out_id[response_master] <= local_bid[state_slave*ID_WIDTH +: ID_WIDTH];
                    b_out_resp[response_master] <=
                        local_bresp[state_slave*RESP_WIDTH +: RESP_WIDTH];
                    b_out_valid[response_master] <= 1'b1;
                end

                if (s_axi_rvalid[state_slave] && s_rready_reg[state_slave]) begin
                    response_master = r_owner[state_slave];
                    r_out_id[response_master] <= r_original_id[state_slave];
                    r_out_data[response_master] <=
                        s_axi_rdata[state_slave*DATA_WIDTH +: DATA_WIDTH];
                    if (r_exclusive[state_slave] &&
                        (s_axi_rresp[state_slave*RESP_WIDTH +: RESP_WIDTH] ==
                            {RESP_WIDTH{1'b0}}))
                        r_out_resp[response_master] <= {{(RESP_WIDTH-1){1'b0}}, 1'b1};
                    else
                        r_out_resp[response_master] <=
                            s_axi_rresp[state_slave*RESP_WIDTH +: RESP_WIDTH];
                    r_out_last[response_master] <= s_axi_rlast[state_slave];
                    r_out_valid[response_master] <= 1'b1;

                    if (s_axi_rlast[state_slave]) begin
                        r_route_active[state_slave] <= 1'b0;
                        r_lock_valid[response_master] <= 1'b0;
                    end
                    else begin
                        r_lock_valid[response_master] <= 1'b1;
                        r_lock_slave[response_master] <= state_slave;
                    end
                end
            end
        end
    end

endmodule
