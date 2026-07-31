module branch_predictor #(
    parameter int unsigned ADDR_WIDTH = 32,
    parameter int unsigned BTB_ENTRIES = 64,
    parameter int unsigned PC_INCR = 4,

    localparam int unsigned INDEX_WIDTH = (BTB_ENTRIES <= 1) ? 1 : $clog2(BTB_ENTRIES),
    localparam int unsigned TAG_WIDTH = ADDR_WIDTH - 2
) (
    input  logic                    ACLK,
    input  logic                    ARESETn,

    // IF lookup
    input  logic [ADDR_WIDTH-1:0]   lookup_pc,
    output logic                    predict_valid,
    output logic                    predict_taken,
    output logic [ADDR_WIDTH-1:0]   predict_target,

    // Branch resolution/update
    input  logic                    update_valid,
    input  logic                    update_is_branch,
    input  logic [ADDR_WIDTH-1:0]   update_pc,
    input  logic                    update_taken,
    input  logic [ADDR_WIDTH-1:0]   update_target
);

    logic [TAG_WIDTH-1:0] btb_tag [0:BTB_ENTRIES-1];
    logic [ADDR_WIDTH-1:0] btb_target [0:BTB_ENTRIES-1];
    logic [1:0] bht_counter [0:BTB_ENTRIES-1];
    logic btb_valid [0:BTB_ENTRIES-1];

    logic [INDEX_WIDTH-1:0] lookup_index;
    logic [TAG_WIDTH-1:0] lookup_tag;
    logic lookup_hit;

    logic [INDEX_WIDTH-1:0] update_index;
    logic [TAG_WIDTH-1:0] update_tag;

    assign lookup_index = lookup_pc[INDEX_WIDTH+1:2];
    assign lookup_tag = lookup_pc[ADDR_WIDTH-1:2];
    assign lookup_hit = btb_valid[lookup_index] && (btb_tag[lookup_index] == lookup_tag);

    assign predict_valid = lookup_hit;
    assign predict_taken = lookup_hit && bht_counter[lookup_index][1];
    assign predict_target = predict_taken ? btb_target[lookup_index] : (lookup_pc + PC_INCR);

    assign update_index = update_pc[INDEX_WIDTH+1:2];
    assign update_tag = update_pc[ADDR_WIDTH-1:2];

    always @(posedge ACLK or negedge ARESETn) begin
        if (!ARESETn) begin
            for (int i = 0; i < BTB_ENTRIES; i++) begin
                btb_tag[i] <= '0;
                btb_target[i] <= '0;
                bht_counter[i] <= 2'b01;
                btb_valid[i] <= 1'b0;
            end
        end
        else if (update_valid) begin
            if (update_is_branch) begin
                btb_tag[update_index] <= update_tag;
                btb_target[update_index] <= update_target;
                btb_valid[update_index] <= 1'b1;

                if (update_taken) begin
                    if (bht_counter[update_index] != 2'b11) begin
                        bht_counter[update_index] <= bht_counter[update_index] + 1'b1;
                    end
                end
                else begin
                    if (bht_counter[update_index] != 2'b00) begin
                        bht_counter[update_index] <= bht_counter[update_index] - 1'b1;
                    end
                end
            end
            else begin
                btb_valid[update_index] <= 1'b0;
            end
        end
    end

endmodule
