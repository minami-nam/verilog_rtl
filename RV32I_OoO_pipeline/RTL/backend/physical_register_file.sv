module physical_register_file #(
    parameter int unsigned DATA_WIDTH = 32,
    parameter int unsigned PHYS_REGS  = 64,

    localparam int unsigned PHYS_TAG_WIDTH =
        (PHYS_REGS <= 1) ? 1 : $clog2(PHYS_REGS)
) (
    input logic ACLK,
    input logic ARESETn,

    input  logic [PHYS_TAG_WIDTH-1:0] read_rs1_tag,
    input  logic [PHYS_TAG_WIDTH-1:0] read_rs2_tag,
    output logic [DATA_WIDTH-1:0]     read_rs1_data,
    output logic [DATA_WIDTH-1:0]     read_rs2_data,

    input logic                      writeback_valid,
    input logic [PHYS_TAG_WIDTH-1:0] writeback_tag,
    input logic [DATA_WIDTH-1:0]     writeback_data
);

    logic [DATA_WIDTH-1:0] phys_data [0:PHYS_REGS-1];

    // read 

    always @(*) begin
        read_rs1_data = '0;
        read_rs2_data = '0;

        if (read_rs1_tag != '0) begin
            read_rs1_data = phys_data[read_rs1_tag];
        end

        if (read_rs2_tag != '0) begin
            read_rs2_data = phys_data[read_rs2_tag];
        end

        if (writeback_valid && (writeback_tag != '0)) begin
            if (read_rs1_tag == writeback_tag) read_rs1_data = writeback_data;
            if (read_rs2_tag == writeback_tag) read_rs2_data = writeback_data;
        end
    end

    // WB

    always @(posedge ACLK or negedge ARESETn) begin
        if (!ARESETn) begin
            for (int i=0; i<PHYS_REGS; i=i+1) begin
                phys_data[i] <= '0;
            end
        end

        else begin
            if (writeback_valid && writeback_tag != '0) begin   // tag가 0일 때는 write X -> p0 값은 상시 0으로 유지됨.
                phys_data[writeback_tag] <= writeback_data;
            end
        end
    end


endmodule