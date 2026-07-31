module decoder #(
    parameter int unsigned WIDTH_INST = 32,
    parameter int unsigned ADDR_WIDTH = 32,
    parameter int unsigned ARCH_REGS = 32,

    localparam int unsigned ARCH_TAG_WIDTH = (ARCH_REGS <= 1) ? 1 : $clog2(ARCH_REGS)
) (
    input  logic                        decode_valid,
    input  logic [ADDR_WIDTH-1:0]       decode_pc,
    input  logic [WIDTH_INST-1:0]       decode_inst,
    input  logic                        decode_pred_taken,
    input  logic [ADDR_WIDTH-1:0]       decode_pred_target,

    output logic [6:0]                  opcode,
    output logic [2:0]                  funct3,
    output logic [6:0]                  funct7,
    output logic [ARCH_TAG_WIDTH-1:0]   arch_rs1,
    output logic [ARCH_TAG_WIDTH-1:0]   arch_rs2,
    output logic [ARCH_TAG_WIDTH-1:0]   arch_rd,
    output logic [ADDR_WIDTH-1:0]       pc,
    output logic [WIDTH_INST-1:0]       inst,
    output logic [31:0]                 imm,

    output logic                        use_rs1,
    output logic                        use_rs2,
    output logic                        write_rd,
    output logic                        is_alu,
    output logic                        is_load,
    output logic                        is_store,
    output logic                        is_branch,
    output logic                        is_jal,
    output logic                        is_jalr,
    output logic                        is_lui,
    output logic                        is_auipc,
    output logic                        is_system,
    output logic                        pred_taken,
    output logic [ADDR_WIDTH-1:0]       pred_target,
    output logic                        illegal_inst
);

    localparam logic [6:0] OPCODE_LUI    = 7'b0110111;
    localparam logic [6:0] OPCODE_AUIPC  = 7'b0010111;
    localparam logic [6:0] OPCODE_JAL    = 7'b1101111;
    localparam logic [6:0] OPCODE_JALR   = 7'b1100111;
    localparam logic [6:0] OPCODE_BRANCH = 7'b1100011;
    localparam logic [6:0] OPCODE_LOAD   = 7'b0000011;
    localparam logic [6:0] OPCODE_STORE  = 7'b0100011;
    localparam logic [6:0] OPCODE_OP_IMM = 7'b0010011;
    localparam logic [6:0] OPCODE_OP     = 7'b0110011;
    localparam logic [6:0] OPCODE_SYSTEM = 7'b1110011;

    logic [31:0] imm_i;
    logic [31:0] imm_s;
    logic [31:0] imm_b;
    logic [31:0] imm_u;
    logic [31:0] imm_j;

    assign opcode = decode_inst[6:0];
    assign arch_rd = decode_inst[11:7];
    assign funct3 = decode_inst[14:12];
    assign arch_rs1 = decode_inst[19:15];
    assign arch_rs2 = decode_inst[24:20];
    assign funct7 = decode_inst[31:25];

    assign pc = decode_pc;
    assign inst = decode_inst;
    assign pred_taken = decode_pred_taken;
    assign pred_target = decode_pred_target;

    // RV32I 명령어 type 별 wire 선언 및 assign 
    assign imm_i = {{20{decode_inst[31]}}, decode_inst[31:20]};
    assign imm_s = {{20{decode_inst[31]}}, decode_inst[31:25], decode_inst[11:7]};
    assign imm_b = {{19{decode_inst[31]}}, decode_inst[31], decode_inst[7], decode_inst[30:25], decode_inst[11:8], 1'b0};
    assign imm_u = {decode_inst[31:12], 12'b0};
    assign imm_j = {{11{decode_inst[31]}}, decode_inst[31], decode_inst[19:12], decode_inst[20], decode_inst[30:21], 1'b0};

    always_comb begin
        imm = '0;
        use_rs1 = 1'b0;
        use_rs2 = 1'b0;
        write_rd = 1'b0;
        is_alu = 1'b0;
        is_load = 1'b0;
        is_store = 1'b0;
        is_branch = 1'b0;
        is_jal = 1'b0;
        is_jalr = 1'b0;
        is_lui = 1'b0;
        is_auipc = 1'b0;
        is_system = 1'b0;
        illegal_inst = 1'b0;

        if (decode_valid) begin
            unique case (opcode)
                OPCODE_LUI: begin
                    imm = imm_u;
                    write_rd = (arch_rd != '0);
                    is_lui = 1'b1;
                end

                OPCODE_AUIPC: begin
                    imm = imm_u;
                    write_rd = (arch_rd != '0);
                    is_auipc = 1'b1;
                end

                OPCODE_JAL: begin
                    imm = imm_j;
                    write_rd = (arch_rd != '0);
                    is_jal = 1'b1;
                end

                OPCODE_JALR: begin
                    imm = imm_i;
                    use_rs1 = 1'b1;
                    write_rd = (arch_rd != '0);
                    is_jalr = 1'b1;
                end

                OPCODE_BRANCH: begin
                    imm = imm_b;
                    use_rs1 = 1'b1;
                    use_rs2 = 1'b1;
                    is_branch = 1'b1;
                end

                OPCODE_LOAD: begin
                    imm = imm_i;
                    use_rs1 = 1'b1;
                    write_rd = (arch_rd != '0);
                    is_load = 1'b1;
                end

                OPCODE_STORE: begin
                    imm = imm_s;
                    use_rs1 = 1'b1;
                    use_rs2 = 1'b1;
                    is_store = 1'b1;
                end

                OPCODE_OP_IMM: begin
                    imm = imm_i;
                    use_rs1 = 1'b1;
                    write_rd = (arch_rd != '0);
                    is_alu = 1'b1;
                end

                OPCODE_OP: begin
                    use_rs1 = 1'b1;
                    use_rs2 = 1'b1;
                    write_rd = (arch_rd != '0);
                    is_alu = 1'b1;
                end

                OPCODE_SYSTEM: begin
                    imm = imm_i;
                    is_system = 1'b1;
                    unique case (funct3)
                        3'b001, 3'b010, 3'b011: begin
                            use_rs1 = 1'b1;
                            write_rd = (arch_rd != '0);
                        end
                        3'b101, 3'b110, 3'b111: begin
                            write_rd = (arch_rd != '0);
                        end
                        default: begin
                            use_rs1 = 1'b0;
                            write_rd = 1'b0;
                        end
                    endcase
                end

                default: begin
                    illegal_inst = 1'b1;
                end
            endcase
        end
    end

endmodule
