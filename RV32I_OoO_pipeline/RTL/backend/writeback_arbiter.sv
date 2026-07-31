module writeback_arbiter #(
    parameter int unsigned DATA_WIDTH = 32,
    parameter int unsigned ADDR_WIDTH = 32,
    parameter int unsigned PHYS_REGS = 64,
    parameter int unsigned ROB_ENTRIES = 32,
    parameter int unsigned EXC_CAUSE_WIDTH = 5,

    localparam int unsigned PHYS_TAG_WIDTH =
        (PHYS_REGS <= 1) ? 1 : $clog2(PHYS_REGS),
    localparam int unsigned ROB_TAG_WIDTH =
        (ROB_ENTRIES <= 1) ? 1 : $clog2(ROB_ENTRIES)
) (
    input  logic                        alu_valid,
    output logic                        alu_ready,
    input  logic [ROB_TAG_WIDTH-1:0]    alu_rob_tag,
    input  logic [PHYS_TAG_WIDTH-1:0]   alu_phys_rd,
    input  logic                        alu_write_rd,
    input  logic [DATA_WIDTH-1:0]       alu_data,
    input  logic                        alu_branch_taken,
    input  logic [ADDR_WIDTH-1:0]       alu_actual_target,
    input  logic                        alu_exception,
    input  logic [EXC_CAUSE_WIDTH-1:0] alu_exception_cause,
    input  logic [ADDR_WIDTH-1:0]       alu_exception_tval,

    input  logic                        lsu_valid,
    output logic                        lsu_ready,
    input  logic [ROB_TAG_WIDTH-1:0]    lsu_rob_tag,
    input  logic [PHYS_TAG_WIDTH-1:0]   lsu_phys_rd,
    input  logic                        lsu_write_rd,
    input  logic [DATA_WIDTH-1:0]       lsu_data,
    input  logic                        lsu_exception,
    input  logic [EXC_CAUSE_WIDTH-1:0] lsu_exception_cause,
    input  logic [ADDR_WIDTH-1:0]       lsu_exception_tval,

    input  logic                        csr_valid,
    output logic                        csr_ready,
    input  logic [ROB_TAG_WIDTH-1:0]    csr_rob_tag,
    input  logic [PHYS_TAG_WIDTH-1:0]   csr_phys_rd,
    input  logic                        csr_write_rd,
    input  logic [DATA_WIDTH-1:0]       csr_data,
    input  logic                        csr_exception,
    input  logic [EXC_CAUSE_WIDTH-1:0] csr_exception_cause,
    input  logic [ADDR_WIDTH-1:0]       csr_exception_tval,

    output logic                        wb_valid,
    input  logic                        wb_ready,
    output logic [ROB_TAG_WIDTH-1:0]    wb_rob_tag,
    output logic [PHYS_TAG_WIDTH-1:0]   wb_phys_rd,
    output logic                        wb_write_rd,
    output logic [DATA_WIDTH-1:0]       wb_data,
    output logic                        wb_branch_taken,
    output logic [ADDR_WIDTH-1:0]       wb_actual_target,
    output logic                        wb_exception,
    output logic [EXC_CAUSE_WIDTH-1:0] wb_exception_cause,
    output logic [ADDR_WIDTH-1:0]       wb_exception_tval
);

    always_comb begin
        alu_ready = 1'b0;
        lsu_ready = 1'b0;
        csr_ready = 1'b0;

        wb_valid = 1'b0;
        wb_rob_tag = '0;
        wb_phys_rd = '0;
        wb_write_rd = 1'b0;
        wb_data = '0;
        wb_branch_taken = 1'b0;
        wb_actual_target = '0;
        wb_exception = 1'b0;
        wb_exception_cause = '0;
        wb_exception_tval = '0;

        if (lsu_valid) begin
            wb_valid = 1'b1;
            lsu_ready = wb_ready;
            wb_rob_tag = lsu_rob_tag;
            wb_phys_rd = lsu_phys_rd;
            wb_write_rd = lsu_write_rd;
            wb_data = lsu_data;
            wb_exception = lsu_exception;
            wb_exception_cause = lsu_exception_cause;
            wb_exception_tval = lsu_exception_tval;
        end
        else if (csr_valid) begin
            wb_valid = 1'b1;
            csr_ready = wb_ready;
            wb_rob_tag = csr_rob_tag;
            wb_phys_rd = csr_phys_rd;
            wb_write_rd = csr_write_rd;
            wb_data = csr_data;
            wb_exception = csr_exception;
            wb_exception_cause = csr_exception_cause;
            wb_exception_tval = csr_exception_tval;
        end
        else if (alu_valid) begin
            wb_valid = 1'b1;
            alu_ready = wb_ready;
            wb_rob_tag = alu_rob_tag;
            wb_phys_rd = alu_phys_rd;
            wb_write_rd = alu_write_rd;
            wb_data = alu_data;
            wb_branch_taken = alu_branch_taken;
            wb_actual_target = alu_actual_target;
            wb_exception = alu_exception;
            wb_exception_cause = alu_exception_cause;
            wb_exception_tval = alu_exception_tval;
        end
    end
endmodule
