module rename_map_table #(
    parameter int unsigned ARCH_REGS = 32,
    parameter int unsigned PHYS_REGS = 64,

    localparam int unsigned ARCH_TAG_WIDTH = (ARCH_REGS <= 1) ? 1 : $clog2(ARCH_REGS),
    localparam int unsigned PHYS_TAG_WIDTH = (PHYS_REGS <= 1) ? 1 : $clog2(PHYS_REGS)
) (
    input  logic                        ACLK,
    input  logic                        ARESETn,

    input  logic [ARCH_TAG_WIDTH-1:0]   arch_rs1,
    input  logic [ARCH_TAG_WIDTH-1:0]   arch_rs2,
    input  logic [ARCH_TAG_WIDTH-1:0]   arch_rd,
    input  logic                        use_rs1,
    input  logic                        use_rs2,
    input  logic                        write_rd,

    output logic [PHYS_TAG_WIDTH-1:0]   phys_rs1,
    output logic [PHYS_TAG_WIDTH-1:0]   phys_rs2,
    output logic [PHYS_TAG_WIDTH-1:0]   old_phys_rd,

    input  logic                        rename_fire,
    input  logic [PHYS_TAG_WIDTH-1:0]   new_phys_rd,

    input  logic                        recover_valid,
    input  logic [ARCH_TAG_WIDTH-1:0]   recover_arch_rd,
    input  logic [PHYS_TAG_WIDTH-1:0]   recover_phys_rd
);

    logic [PHYS_TAG_WIDTH-1:0] map_table [0:ARCH_REGS-1];

    assign phys_rs1 = use_rs1 ? map_table[arch_rs1] : '0;
    assign phys_rs2 = use_rs2 ? map_table[arch_rs2] : '0;
    assign old_phys_rd = write_rd ? map_table[arch_rd] : '0;

    always @(posedge ACLK or negedge ARESETn) begin
        if (!ARESETn) begin
            for (int i = 0; i < ARCH_REGS; i++) begin
                map_table[i] <= i;
            end
        end
        else begin
            if (recover_valid && (recover_arch_rd != '0)) begin
                map_table[recover_arch_rd] <= recover_phys_rd;
            end
            else if (rename_fire && write_rd && (arch_rd != '0)) begin
                map_table[arch_rd] <= new_phys_rd;
            end
        end
    end

endmodule
