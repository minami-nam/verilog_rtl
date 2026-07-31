module busy_table #(
    parameter int unsigned ARCH_REGS = 32,
    parameter int unsigned PHYS_REGS = 64,

    localparam int unsigned PHYS_TAG_WIDTH = (PHYS_REGS <= 1) ? 1 : $clog2(PHYS_REGS)
) (
    input  logic                        ACLK,
    input  logic                        ARESETn,

    input  logic [PHYS_TAG_WIDTH-1:0]   phys_rs1,
    input  logic [PHYS_TAG_WIDTH-1:0]   phys_rs2,
    input  logic                        use_rs1,
    input  logic                        use_rs2,
    output logic                        rs1_ready,
    output logic                        rs2_ready,

    input  logic                        set_busy_valid,
    input  logic [PHYS_TAG_WIDTH-1:0]   set_busy_tag,

    input  logic                        clear_busy_valid,
    input  logic [PHYS_TAG_WIDTH-1:0]   clear_busy_tag
);

    logic ready_table [0:PHYS_REGS-1];

    assign rs1_ready = !use_rs1 ||
                       ready_table[phys_rs1] ||
                       (clear_busy_valid &&
                        (clear_busy_tag == phys_rs1));
    assign rs2_ready = !use_rs2 ||
                       ready_table[phys_rs2] ||
                       (clear_busy_valid &&
                        (clear_busy_tag == phys_rs2));

    always @(posedge ACLK or negedge ARESETn) begin
        if (!ARESETn) begin
            for (int i = 0; i < PHYS_REGS; i++) begin
                ready_table[i] <= 1'b1;
            end
        end
        else begin
            if (set_busy_valid && (set_busy_tag != '0)) begin
                ready_table[set_busy_tag] <= 1'b0;
            end

            if (clear_busy_valid) begin
                ready_table[clear_busy_tag] <= 1'b1;
            end
        end
    end

endmodule
