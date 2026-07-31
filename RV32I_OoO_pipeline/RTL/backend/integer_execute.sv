module integer_execute #(
    parameter int unsigned WIDTH_INST = 32,
    parameter int unsigned ADDR_WIDTH = 32,
    parameter int unsigned DATA_WIDTH = 32,
    parameter int unsigned PHYS_REGS = 64,
    parameter int unsigned ROB_ENTRIES = 32,

    localparam int unsigned PHYS_TAG_WIDTH =
        (PHYS_REGS <= 1) ? 1 : $clog2(PHYS_REGS),
    localparam int unsigned ROB_TAG_WIDTH =
        (ROB_ENTRIES <= 1) ? 1 : $clog2(ROB_ENTRIES),
    localparam int unsigned EXC_CAUSE_WIDTH = 5
) (
    input  logic                         ACLK,
    input  logic                         ARESETn,

    input  logic                         issue_valid,
    output logic                         issue_ready,
    input  logic [ROB_TAG_WIDTH-1:0]     issue_rob_tag,
    input  logic [ADDR_WIDTH-1:0]        issue_pc,
    input  logic [WIDTH_INST-1:0]        issue_inst,
    input  logic [6:0]                   issue_opcode,
    input  logic [2:0]                   issue_funct3,
    input  logic [6:0]                   issue_funct7,
    input  logic [31:0]                  issue_imm,
    input  logic [PHYS_TAG_WIDTH-1:0]    issue_phys_rd,
    input  logic                         issue_write_rd,
    input  logic [DATA_WIDTH-1:0]        issue_rs1_data,
    input  logic [DATA_WIDTH-1:0]        issue_rs2_data,

    output logic                         wb_valid,
    input  logic                         wb_ready,
    output logic [ROB_TAG_WIDTH-1:0]     wb_rob_tag,
    output logic [PHYS_TAG_WIDTH-1:0]    wb_phys_rd,
    output logic                         wb_write_rd,
    output logic [DATA_WIDTH-1:0]        wb_data,
    output logic                         wb_branch_taken,
    output logic [ADDR_WIDTH-1:0]        wb_actual_target,
    output logic                         wb_exception,
    output logic [EXC_CAUSE_WIDTH-1:0]  wb_exception_cause,
    output logic [ADDR_WIDTH-1:0]        wb_exception_tval,

    input  logic                         flush_valid
);

    localparam logic [6:0] OPCODE_LUI    = 7'b0110111;
    localparam logic [6:0] OPCODE_AUIPC  = 7'b0010111;
    localparam logic [6:0] OPCODE_JAL    = 7'b1101111;
    localparam logic [6:0] OPCODE_JALR   = 7'b1100111;
    localparam logic [6:0] OPCODE_BRANCH = 7'b1100011;
    localparam logic [6:0] OPCODE_OP_IMM = 7'b0010011;
    localparam logic [6:0] OPCODE_OP     = 7'b0110011;
    localparam logic [6:0] OPCODE_SYSTEM = 7'b1110011;

    localparam logic [EXC_CAUSE_WIDTH-1:0] EXC_INST_ADDR_MISALIGNED =
        5'd0;
    localparam logic [EXC_CAUSE_WIDTH-1:0] EXC_ILLEGAL_INSTRUCTION =
        5'd2;
    localparam logic [EXC_CAUSE_WIDTH-1:0] EXC_BREAKPOINT =
        5'd3;
    localparam logic [EXC_CAUSE_WIDTH-1:0] EXC_ECALL_M_MODE =
        5'd11;

    logic [DATA_WIDTH-1:0] exec_data;
    logic exec_write_rd;
    logic exec_branch_taken;
    logic [ADDR_WIDTH-1:0] exec_actual_target;
    logic exec_exception;
    logic [EXC_CAUSE_WIDTH-1:0] exec_exception_cause;
    logic [ADDR_WIDTH-1:0] exec_exception_tval;

    assign issue_ready = !wb_valid || wb_ready;

    always_comb begin
        exec_data = '0;
        exec_write_rd = issue_write_rd;
        exec_branch_taken = 1'b0;
        exec_actual_target = '0;
        exec_exception = 1'b0;
        exec_exception_cause = '0;
        exec_exception_tval = '0;

        unique case (issue_opcode)
            OPCODE_LUI: begin
                exec_data = issue_imm;
            end

            OPCODE_AUIPC: begin
                exec_data = issue_pc + issue_imm;
            end

            OPCODE_JAL: begin
                exec_data = issue_pc + 32'd4;
                exec_branch_taken = 1'b1;
                exec_actual_target = issue_pc + issue_imm;
            end

            OPCODE_JALR: begin
                exec_data = issue_pc + 32'd4;
                exec_branch_taken = 1'b1;
                exec_actual_target =
                    (issue_rs1_data + issue_imm) &
                    {{(ADDR_WIDTH-1){1'b1}}, 1'b0};

                if (issue_funct3 != 3'b000) begin
                    exec_exception = 1'b1;
                    exec_exception_cause = EXC_ILLEGAL_INSTRUCTION;
                    exec_exception_tval = issue_inst;
                end
            end

            OPCODE_BRANCH: begin
                unique case (issue_funct3)
                    3'b000: exec_branch_taken =
                        (issue_rs1_data == issue_rs2_data);
                    3'b001: exec_branch_taken =
                        (issue_rs1_data != issue_rs2_data);
                    3'b100: exec_branch_taken =
                        ($signed(issue_rs1_data) <
                         $signed(issue_rs2_data));
                    3'b101: exec_branch_taken =
                        ($signed(issue_rs1_data) >=
                         $signed(issue_rs2_data));
                    3'b110: exec_branch_taken =
                        (issue_rs1_data < issue_rs2_data);
                    3'b111: exec_branch_taken =
                        (issue_rs1_data >= issue_rs2_data);
                    default: begin
                        exec_exception = 1'b1;
                        exec_exception_cause =
                            EXC_ILLEGAL_INSTRUCTION;
                        exec_exception_tval = issue_inst;
                    end
                endcase

                exec_actual_target = exec_branch_taken ?
                    (issue_pc + issue_imm) :
                    (issue_pc + 32'd4);
            end

            OPCODE_OP_IMM: begin
                unique case (issue_funct3)
                    3'b000: exec_data = issue_rs1_data + issue_imm;
                    3'b010: exec_data =
                        ($signed(issue_rs1_data) <
                         $signed(issue_imm)) ? 32'd1 : 32'd0;
                    3'b011: exec_data =
                        (issue_rs1_data < issue_imm) ? 32'd1 : 32'd0;
                    3'b100: exec_data = issue_rs1_data ^ issue_imm;
                    3'b110: exec_data = issue_rs1_data | issue_imm;
                    3'b111: exec_data = issue_rs1_data & issue_imm;

                    3'b001: begin
                        if (issue_funct7 == 7'b0000000)
                            exec_data =
                                issue_rs1_data << issue_imm[4:0];
                        else begin
                            exec_exception = 1'b1;
                            exec_exception_cause =
                                EXC_ILLEGAL_INSTRUCTION;
                            exec_exception_tval = issue_inst;
                        end
                    end

                    3'b101: begin
                        unique case (issue_funct7)
                            7'b0000000:
                                exec_data =
                                    issue_rs1_data >> issue_imm[4:0];
                            7'b0100000:
                                exec_data =
                                    $signed(issue_rs1_data) >>>
                                    issue_imm[4:0];
                            default: begin
                                exec_exception = 1'b1;
                                exec_exception_cause =
                                    EXC_ILLEGAL_INSTRUCTION;
                                exec_exception_tval = issue_inst;
                            end
                        endcase
                    end

                    default: begin
                        exec_exception = 1'b1;
                        exec_exception_cause =
                            EXC_ILLEGAL_INSTRUCTION;
                        exec_exception_tval = issue_inst;
                    end
                endcase
            end

            OPCODE_OP: begin
                unique case (issue_funct3)
                    3'b000: begin
                        unique case (issue_funct7)
                            7'b0000000:
                                exec_data =
                                    issue_rs1_data + issue_rs2_data;
                            7'b0100000:
                                exec_data =
                                    issue_rs1_data - issue_rs2_data;
                            default: begin
                                exec_exception = 1'b1;
                                exec_exception_cause =
                                    EXC_ILLEGAL_INSTRUCTION;
                                exec_exception_tval = issue_inst;
                            end
                        endcase
                    end

                    3'b001: begin
                        if (issue_funct7 == 7'b0000000)
                            exec_data =
                                issue_rs1_data <<
                                issue_rs2_data[4:0];
                        else begin
                            exec_exception = 1'b1;
                            exec_exception_cause =
                                EXC_ILLEGAL_INSTRUCTION;
                            exec_exception_tval = issue_inst;
                        end
                    end

                    3'b010: begin
                        if (issue_funct7 == 7'b0000000)
                            exec_data =
                                ($signed(issue_rs1_data) <
                                 $signed(issue_rs2_data)) ?
                                32'd1 : 32'd0;
                        else begin
                            exec_exception = 1'b1;
                            exec_exception_cause =
                                EXC_ILLEGAL_INSTRUCTION;
                            exec_exception_tval = issue_inst;
                        end
                    end

                    3'b011: begin
                        if (issue_funct7 == 7'b0000000)
                            exec_data =
                                (issue_rs1_data < issue_rs2_data) ?
                                32'd1 : 32'd0;
                        else begin
                            exec_exception = 1'b1;
                            exec_exception_cause =
                                EXC_ILLEGAL_INSTRUCTION;
                            exec_exception_tval = issue_inst;
                        end
                    end

                    3'b100: begin
                        if (issue_funct7 == 7'b0000000)
                            exec_data =
                                issue_rs1_data ^ issue_rs2_data;
                        else begin
                            exec_exception = 1'b1;
                            exec_exception_cause =
                                EXC_ILLEGAL_INSTRUCTION;
                            exec_exception_tval = issue_inst;
                        end
                    end

                    3'b101: begin
                        unique case (issue_funct7)
                            7'b0000000:
                                exec_data =
                                    issue_rs1_data >>
                                    issue_rs2_data[4:0];
                            7'b0100000:
                                exec_data =
                                    $signed(issue_rs1_data) >>>
                                    issue_rs2_data[4:0];
                            default: begin
                                exec_exception = 1'b1;
                                exec_exception_cause =
                                    EXC_ILLEGAL_INSTRUCTION;
                                exec_exception_tval = issue_inst;
                            end
                        endcase
                    end

                    3'b110: begin
                        if (issue_funct7 == 7'b0000000)
                            exec_data =
                                issue_rs1_data | issue_rs2_data;
                        else begin
                            exec_exception = 1'b1;
                            exec_exception_cause =
                                EXC_ILLEGAL_INSTRUCTION;
                            exec_exception_tval = issue_inst;
                        end
                    end

                    3'b111: begin
                        if (issue_funct7 == 7'b0000000)
                            exec_data =
                                issue_rs1_data & issue_rs2_data;
                        else begin
                            exec_exception = 1'b1;
                            exec_exception_cause =
                                EXC_ILLEGAL_INSTRUCTION;
                            exec_exception_tval = issue_inst;
                        end
                    end

                    default: begin
                        exec_exception = 1'b1;
                        exec_exception_cause =
                            EXC_ILLEGAL_INSTRUCTION;
                        exec_exception_tval = issue_inst;
                    end
                endcase
            end

            OPCODE_SYSTEM: begin
                exec_write_rd = 1'b0;

                if (issue_funct3 == 3'b000) begin
                    unique case (issue_inst[31:20])
                        12'h000: begin
                            exec_exception = 1'b1;
                            exec_exception_cause =
                                EXC_ECALL_M_MODE;
                            exec_exception_tval = '0;
                        end
                        12'h001: begin
                            exec_exception = 1'b1;
                            exec_exception_cause =
                                EXC_BREAKPOINT;
                            exec_exception_tval = issue_pc;
                        end
                        default: begin
                            exec_exception = 1'b1;
                            exec_exception_cause =
                                EXC_ILLEGAL_INSTRUCTION;
                            exec_exception_tval = issue_inst;
                        end
                    endcase
                end
                else begin
                    exec_exception = 1'b1;
                    exec_exception_cause =
                        EXC_ILLEGAL_INSTRUCTION;
                    exec_exception_tval = issue_inst;
                end
            end

            default: begin
                exec_exception = 1'b1;
                exec_exception_cause = EXC_ILLEGAL_INSTRUCTION;
                exec_exception_tval = issue_inst;
            end
        endcase

        if (!exec_exception &&
            exec_branch_taken &&
            (exec_actual_target[1:0] != 2'b00)) begin
            exec_exception = 1'b1;
            exec_exception_cause = EXC_INST_ADDR_MISALIGNED;
            exec_exception_tval = exec_actual_target;
        end
    end

    always_ff @(posedge ACLK or negedge ARESETn) begin
        if (!ARESETn) begin
            wb_valid <= 1'b0;
            wb_rob_tag <= '0;
            wb_phys_rd <= '0;
            wb_write_rd <= 1'b0;
            wb_data <= '0;
            wb_branch_taken <= 1'b0;
            wb_actual_target <= '0;
            wb_exception <= 1'b0;
            wb_exception_cause <= '0;
            wb_exception_tval <= '0;
        end
        else if (flush_valid) begin
            wb_valid <= 1'b0;
            wb_rob_tag <= '0;
            wb_phys_rd <= '0;
            wb_write_rd <= 1'b0;
            wb_data <= '0;
            wb_branch_taken <= 1'b0;
            wb_actual_target <= '0;
            wb_exception <= 1'b0;
            wb_exception_cause <= '0;
            wb_exception_tval <= '0;
        end
        else if (issue_ready) begin
            wb_valid <= issue_valid;

            if (issue_valid) begin
                wb_rob_tag <= issue_rob_tag;
                wb_phys_rd <= issue_phys_rd;
                wb_write_rd <= exec_write_rd && !exec_exception;
                wb_data <= exec_data;
                wb_branch_taken <= exec_branch_taken;
                wb_actual_target <= exec_actual_target;
                wb_exception <= exec_exception;
                wb_exception_cause <= exec_exception_cause;
                wb_exception_tval <= exec_exception_tval;
            end
        end
    end

endmodule
