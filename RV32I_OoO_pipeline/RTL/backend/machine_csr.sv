module machine_csr #(
    parameter int unsigned XLEN = 32,
    parameter int unsigned CSR_ADDR_WIDTH = 12,
    parameter int unsigned CAUSE_CODE_WIDTH = 5,

    parameter logic [XLEN-1:0] RESET_MTVEC = '0,
    parameter logic [XLEN-1:0] RESET_MSTATUS = '0,
    parameter logic [XLEN-1:0] MISA_VALUE = 32'h4000_0100,
    parameter logic [XLEN-1:0] HART_ID = '0,

    localparam logic [31:0] MSTATUS_WRITE_MASK =
    (32'h1 << 3)  |       // MIE
    (32'h1 << 7)  |       // MPIE
    (32'h3 << 11)         // MPP
) (
    input  logic                         ACLK,
    input  logic                         ARESETn,

    // Raw CSR instruction request from a serialized system path
    input  logic                         csr_req_valid,
    output logic                         csr_req_ready,
    input  logic [31:0]                  csr_req_inst,
    input  logic [XLEN-1:0]              csr_req_rs1_data,

    // CSR instruction response
    output logic                         csr_resp_valid,
    input  logic                         csr_resp_ready,
    output logic [XLEN-1:0]              csr_resp_rdata,
    output logic                         csr_resp_illegal,

    // Precise trap request from Exception/Interrupt Recovery
    input  logic                         trap_valid,
    output logic                         trap_ready,
    input  logic                         trap_is_interrupt,
    input  logic [CAUSE_CODE_WIDTH-1:0] trap_cause_code,
    input  logic [XLEN-1:0]              trap_pc,
    input  logic [XLEN-1:0]              trap_tval,

    // MRET request and recovery target
    input  logic                         mret_valid,
    output logic                         mret_ready,
    output logic [XLEN-1:0]              mret_pc,

    // Raw machine interrupt sources
    input  logic                         irq_software,
    input  logic                         irq_timer,
    input  logic                         irq_external,

    // Qualified interrupt request to the recovery controller
    output logic                         interrupt_pending,
    output logic [CAUSE_CODE_WIDTH-1:0] interrupt_cause_code,

    // Retirement event for minstret
    input  logic                         retire_valid,

    // CSR state required by recovery/control logic
    output logic [XLEN-1:0]              trap_vector_pc,
    output logic [XLEN-1:0]              csr_mstatus,
    output logic [XLEN-1:0]              csr_mie,
    output logic [XLEN-1:0]              csr_mip,
    output logic [XLEN-1:0]              csr_mtvec,
    output logic [XLEN-1:0]              csr_mepc,
    output logic [XLEN-1:0]              csr_mcause,
    output logic [XLEN-1:0]              csr_mtval
);

    typedef enum logic [CSR_ADDR_WIDTH-1:0] {
        MSTATUS  = 12'h300,
        MISA     = 12'h301,
        MIE      = 12'h304,
        MTVEC    = 12'h305,
        MSCRATCH = 12'h340,
        MEPC     = 12'h341,
        MCAUSE   = 12'h342,
        MTVAL    = 12'h343,
        MIP      = 12'h344,
        MCYCLE   = 12'hB00,
        MINSTRET = 12'hB02,
        MCYCLEH  = 12'hB80,
        MINSTRETH= 12'hB82,
        MHARTID  = 12'hF14
    } csr_addr_t;

    typedef enum logic [3:0] {
        CSR_NONE    = 4'h0,
        CSRRW       = 4'h1,
        CSRRS       = 4'h2,
        CSRRC       = 4'h3,
        CSRRWI      = 4'h5,
        CSRRSI      = 4'h6,
        CSRRCI      = 4'h7,
        CSR_ILLEGAL = 4'hF
    } csr_command_t;

    localparam logic [6:0] OPCODE_SYSTEM = 7'b1110011;
    localparam int unsigned MSTATUS_MIE_BIT = 3;
    localparam int unsigned MSTATUS_MPIE_BIT = 7;
    localparam int unsigned MSTATUS_MPP_LSB = 11;

    localparam int unsigned MIP_MSIP_BIT = 3;
    localparam int unsigned MIP_MTIP_BIT = 7;
    localparam int unsigned MIP_MEIP_BIT = 11;

    localparam logic [XLEN-1:0] MACHINE_INTERRUPT_MASK =
        (32'h1 << MIP_MSIP_BIT) |
        (32'h1 << MIP_MTIP_BIT) |
        (32'h1 << MIP_MEIP_BIT);

    csr_command_t csr_cmd;

    logic [XLEN-1:0] mstatus_reg;
    logic [XLEN-1:0] mie_reg;
    logic [XLEN-1:0] mtvec_reg;
    logic [XLEN-1:0] mscratch_reg;
    logic [XLEN-1:0] mepc_reg;
    logic [XLEN-1:0] mcause_reg;
    logic [XLEN-1:0] mtval_reg;
    logic [XLEN-1:0] mip_value;

    logic [63:0] mcycle_reg;
    logic [63:0] minstret_reg;

    logic [CSR_ADDR_WIDTH-1:0] csr_req_addr;
    logic [1:0] csr_req_op;
    logic [XLEN-1:0] csr_req_wdata;
    logic csr_req_read_en;
    logic csr_req_write_en;
    logic csr_decode_valid;
    logic csr_decode_illegal;
    logic csr_use_imm;

    logic [XLEN-1:0] csr_read_data;
    logic [XLEN-1:0] csr_write_data;
    logic [XLEN-1:0] mstatus_write_data;
    logic csr_addr_valid;
    logic csr_addr_writable;
    logic csr_access_illegal;

    logic response_slot_ready;
    logic csr_fire;
    logic csr_write_fire;
    logic trap_fire;
    logic mret_fire;

    assign response_slot_ready = !csr_resp_valid || csr_resp_ready;

    assign trap_ready = response_slot_ready;
    assign mret_ready = response_slot_ready && !trap_valid;
    assign csr_req_ready =
        response_slot_ready && !trap_valid && !mret_valid;

    assign trap_fire = trap_valid && trap_ready;
    assign mret_fire = mret_valid && mret_ready;
    assign csr_fire = csr_req_valid && csr_req_ready;
    assign csr_write_fire =
        csr_fire && csr_req_write_en && !csr_access_illegal;

    assign trap_vector_pc = {mtvec_reg[XLEN-1:2], 2'b00};
    assign mret_pc = mepc_reg;

    assign csr_mstatus = mstatus_reg;
    assign csr_mie = mie_reg;
    assign csr_mip = mip_value;
    assign csr_mtvec = mtvec_reg;
    assign csr_mepc = mepc_reg;
    assign csr_mcause = mcause_reg;
    assign csr_mtval = mtval_reg;

    always_comb begin
        csr_cmd = CSR_NONE;
        csr_req_addr = csr_req_inst[31:20];
        csr_req_op = 2'b00;
        csr_req_wdata = csr_req_rs1_data;
        csr_req_read_en = 1'b0;
        csr_req_write_en = 1'b0;
        csr_decode_valid = 1'b0;
        csr_decode_illegal = 1'b0;
        csr_use_imm = 1'b0;

        if (csr_req_valid) begin
            if (csr_req_inst[6:0] != OPCODE_SYSTEM) begin
                csr_cmd = CSR_ILLEGAL;
                csr_decode_illegal = 1'b1;
            end
            else begin
                unique case (csr_req_inst[14:12])
                    3'b001: begin
                        csr_cmd = CSRRW;
                        csr_req_op = 2'b01;
                        csr_req_read_en =
                            (csr_req_inst[11:7] != 5'd0);
                        csr_req_write_en = 1'b1;
                        csr_decode_valid = 1'b1;
                    end

                    3'b010: begin
                        csr_cmd = CSRRS;
                        csr_req_op = 2'b10;
                        csr_req_read_en = 1'b1;
                        csr_req_write_en =
                            (csr_req_inst[19:15] != 5'd0);
                        csr_decode_valid = 1'b1;
                    end

                    3'b011: begin
                        csr_cmd = CSRRC;
                        csr_req_op = 2'b11;
                        csr_req_read_en = 1'b1;
                        csr_req_write_en =
                            (csr_req_inst[19:15] != 5'd0);
                        csr_decode_valid = 1'b1;
                    end

                    3'b101: begin
                        csr_cmd = CSRRWI;
                        csr_req_op = 2'b01;
                        csr_req_wdata =
                            {{(XLEN-5){1'b0}},
                             csr_req_inst[19:15]};
                        csr_req_read_en =
                            (csr_req_inst[11:7] != 5'd0);
                        csr_req_write_en = 1'b1;
                        csr_decode_valid = 1'b1;
                        csr_use_imm = 1'b1;
                    end

                    3'b110: begin
                        csr_cmd = CSRRSI;
                        csr_req_op = 2'b10;
                        csr_req_wdata =
                            {{(XLEN-5){1'b0}},
                             csr_req_inst[19:15]};
                        csr_req_read_en = 1'b1;
                        csr_req_write_en =
                            (csr_req_inst[19:15] != 5'd0);
                        csr_decode_valid = 1'b1;
                        csr_use_imm = 1'b1;
                    end

                    3'b111: begin
                        csr_cmd = CSRRCI;
                        csr_req_op = 2'b11;
                        csr_req_wdata =
                            {{(XLEN-5){1'b0}},
                             csr_req_inst[19:15]};
                        csr_req_read_en = 1'b1;
                        csr_req_write_en =
                            (csr_req_inst[19:15] != 5'd0);
                        csr_decode_valid = 1'b1;
                        csr_use_imm = 1'b1;
                    end

                    default: begin
                        csr_cmd = CSR_ILLEGAL;
                        csr_decode_illegal = 1'b1;
                    end
                endcase
            end
        end
    end

    always_comb begin
        csr_read_data = '0;
        csr_addr_valid = 1'b1;
        csr_addr_writable = 1'b0;

        unique case (csr_req_addr)
            MSTATUS: begin
                csr_read_data = mstatus_reg;
                csr_addr_writable = 1'b1;
            end

            MISA: begin
                csr_read_data = MISA_VALUE;
            end

            MIE: begin
                csr_read_data = mie_reg;
                csr_addr_writable = 1'b1;
            end

            MTVEC: begin
                csr_read_data = mtvec_reg;
                csr_addr_writable = 1'b1;
            end

            MSCRATCH: begin
                csr_read_data = mscratch_reg;
                csr_addr_writable = 1'b1;
            end

            MEPC: begin
                csr_read_data = mepc_reg;
                csr_addr_writable = 1'b1;
            end

            MCAUSE: begin
                csr_read_data = mcause_reg;
                csr_addr_writable = 1'b1;
            end

            MTVAL: begin
                csr_read_data = mtval_reg;
                csr_addr_writable = 1'b1;
            end

            MIP: begin
                csr_read_data = mip_value;
            end

            MCYCLE: begin
                csr_read_data = mcycle_reg[31:0];
                csr_addr_writable = 1'b1;
            end

            MCYCLEH: begin
                csr_read_data = mcycle_reg[63:32];
                csr_addr_writable = 1'b1;
            end

            MINSTRET: begin
                csr_read_data = minstret_reg[31:0];
                csr_addr_writable = 1'b1;
            end

            MINSTRETH: begin
                csr_read_data = minstret_reg[63:32];
                csr_addr_writable = 1'b1;
            end

            MHARTID: begin
                csr_read_data = HART_ID;
            end

            default: begin
                csr_read_data = '0;
                csr_addr_valid = 1'b0;
            end
        endcase
    end

    always_comb begin
        unique case (csr_req_op)
            2'b01: csr_write_data = csr_req_wdata;
            2'b10: csr_write_data =
                csr_read_data | csr_req_wdata;
            2'b11: csr_write_data =
                csr_read_data & ~csr_req_wdata;
            default: csr_write_data = csr_read_data;
        endcase

        mstatus_write_data =
            (mstatus_reg & ~MSTATUS_WRITE_MASK) |
            (csr_write_data & MSTATUS_WRITE_MASK);
        mstatus_write_data[MSTATUS_MPP_LSB +: 2] = 2'b11;
    end

    always_comb begin
        csr_access_illegal =
            csr_decode_illegal ||
            !csr_decode_valid ||
            !csr_addr_valid ||
            (csr_req_write_en &&
             (!csr_addr_writable ||
              (csr_req_addr[11:10] == 2'b11)));
    end

    always_comb begin
        mip_value = '0;
        mip_value[MIP_MSIP_BIT] = irq_software;
        mip_value[MIP_MTIP_BIT] = irq_timer;
        mip_value[MIP_MEIP_BIT] = irq_external;

        interrupt_pending = 1'b0;
        interrupt_cause_code = '0;

        if (mstatus_reg[MSTATUS_MIE_BIT]) begin
            if (mie_reg[MIP_MEIP_BIT] &&
                mip_value[MIP_MEIP_BIT]) begin
                interrupt_pending = 1'b1;
                interrupt_cause_code = 5'd11;
            end
            else if (mie_reg[MIP_MSIP_BIT] &&
                     mip_value[MIP_MSIP_BIT]) begin
                interrupt_pending = 1'b1;
                interrupt_cause_code = 5'd3;
            end
            else if (mie_reg[MIP_MTIP_BIT] &&
                     mip_value[MIP_MTIP_BIT]) begin
                interrupt_pending = 1'b1;
                interrupt_cause_code = 5'd7;
            end
        end
    end

    always_ff @(posedge ACLK or negedge ARESETn) begin
        if (!ARESETn) begin
            csr_resp_valid <= 1'b0;
            csr_resp_rdata <= '0;
            csr_resp_illegal <= 1'b0;
        end
        else begin
            if (csr_fire) begin
                csr_resp_valid <= 1'b1;
                csr_resp_rdata <=
                    (!csr_access_illegal && csr_req_read_en) ?
                    csr_read_data : '0;
                csr_resp_illegal <= csr_access_illegal;
            end
            else if (csr_resp_valid && csr_resp_ready) begin
                csr_resp_valid <= 1'b0;
                csr_resp_illegal <= 1'b0;
            end
        end
    end

    always_ff @(posedge ACLK or negedge ARESETn) begin
        if (!ARESETn) begin
            mstatus_reg <=
                (RESET_MSTATUS & MSTATUS_WRITE_MASK) |
                (32'h3 << MSTATUS_MPP_LSB);
            mie_reg <= '0;
            mtvec_reg <= {RESET_MTVEC[XLEN-1:2], 2'b00};
            mscratch_reg <= '0;
            mepc_reg <= '0;
            mcause_reg <= '0;
            mtval_reg <= '0;
        end
        else begin
            if (trap_fire) begin
                mepc_reg <= {trap_pc[XLEN-1:2], 2'b00};
                mcause_reg <= {
                    trap_is_interrupt,
                    {(XLEN-1-CAUSE_CODE_WIDTH){1'b0}},
                    trap_cause_code
                };
                mtval_reg <= trap_tval;
                mstatus_reg[MSTATUS_MPIE_BIT] <=
                    mstatus_reg[MSTATUS_MIE_BIT];
                mstatus_reg[MSTATUS_MIE_BIT] <= 1'b0;
                mstatus_reg[MSTATUS_MPP_LSB +: 2] <= 2'b11;
            end
            else if (mret_fire) begin
                mstatus_reg[MSTATUS_MIE_BIT] <=
                    mstatus_reg[MSTATUS_MPIE_BIT];
                mstatus_reg[MSTATUS_MPIE_BIT] <= 1'b1;
                mstatus_reg[MSTATUS_MPP_LSB +: 2] <= 2'b11;
            end
            else if (csr_write_fire) begin
                unique case (csr_req_addr)
                    MSTATUS:
                        mstatus_reg <= mstatus_write_data;
                    MIE:
                        mie_reg <=
                            csr_write_data & MACHINE_INTERRUPT_MASK;
                    MTVEC:
                        mtvec_reg <=
                            {csr_write_data[XLEN-1:2], 2'b00};
                    MSCRATCH:
                        mscratch_reg <= csr_write_data;
                    MEPC:
                        mepc_reg <=
                            {csr_write_data[XLEN-1:2], 2'b00};
                    MCAUSE:
                        mcause_reg <= csr_write_data;
                    MTVAL:
                        mtval_reg <= csr_write_data;
                    default: ;
                endcase
            end
        end
    end

    always_ff @(posedge ACLK or negedge ARESETn) begin
        if (!ARESETn) begin
            mcycle_reg <= '0;
        end
        else if (csr_write_fire && (csr_req_addr == MCYCLE)) begin
            mcycle_reg[31:0] <= csr_write_data[31:0];
        end
        else if (csr_write_fire && (csr_req_addr == MCYCLEH)) begin
            mcycle_reg[63:32] <= csr_write_data[31:0];
        end
        else begin
            mcycle_reg <= mcycle_reg + 64'd1;
        end
    end

    always_ff @(posedge ACLK or negedge ARESETn) begin
        if (!ARESETn) begin
            minstret_reg <= '0;
        end
        else if (csr_write_fire && (csr_req_addr == MINSTRET)) begin
            minstret_reg[31:0] <= csr_write_data[31:0];
        end
        else if (csr_write_fire && (csr_req_addr == MINSTRETH)) begin
            minstret_reg[63:32] <= csr_write_data[31:0];
        end
        else if (retire_valid) begin
            minstret_reg <= minstret_reg + 64'd1;
        end
    end

endmodule
