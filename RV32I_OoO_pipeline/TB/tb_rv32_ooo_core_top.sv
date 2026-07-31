`timescale 1ns/1ps

module tb_rv32_ooo_core_top;
    localparam int WIDTH_INST = 32;
    localparam int ADDR_WIDTH = 32;
    localparam int DATA_WIDTH = 32;
    localparam int ARCH_REGS = 32;
    localparam int PHYS_REGS = 64;
    localparam int ROB_ENTRIES = 32;
    localparam int AXI_DATA_WIDTH = 64;
    localparam int AXI_ID_WIDTH = 3;
    localparam int AXI_STRB_WIDTH = AXI_DATA_WIDTH / 8;
    localparam int MEM_BYTES = 65536;
    localparam int MAX_CYCLES = 10000;
    localparam int LONG_LOOP_ITERS = 128;
    localparam int READ_LATENCY = 2;
    localparam int WRITE_RESP_LATENCY = 2;
    localparam logic [31:0] PROGRAM_BASE = 32'h0000_7000;
    localparam logic [31:0] SIGNATURE_BASE = 32'h0000_0100;
    localparam logic [31:0] SCRATCH_BASE = 32'h0000_0300;

    logic ACLK;
    logic ARESETn;
    logic fetch_enable;
    logic irq_software;
    logic irq_timer;
    logic irq_external;

    logic [AXI_ID_WIDTH-1:0] m_axi_awid;
    logic [ADDR_WIDTH-1:0] m_axi_awaddr;
    logic [7:0] m_axi_awlen;
    logic [2:0] m_axi_awsize;
    logic [1:0] m_axi_awburst;
    logic m_axi_awlock;
    logic [3:0] m_axi_awcache;
    logic [2:0] m_axi_awprot;
    logic [3:0] m_axi_awqos;
    logic [3:0] m_axi_awregion;
    logic [0:0] m_axi_awuser;
    logic m_axi_awvalid;
    logic m_axi_awready;

    logic [AXI_DATA_WIDTH-1:0] m_axi_wdata;
    logic [AXI_STRB_WIDTH-1:0] m_axi_wstrb;
    logic m_axi_wlast;
    logic [0:0] m_axi_wuser;
    logic m_axi_wvalid;
    logic m_axi_wready;

    logic [AXI_ID_WIDTH-1:0] m_axi_bid;
    logic [1:0] m_axi_bresp;
    logic [0:0] m_axi_buser;
    logic m_axi_bvalid;
    logic m_axi_bready;

    logic [AXI_ID_WIDTH-1:0] m_axi_arid;
    logic [ADDR_WIDTH-1:0] m_axi_araddr;
    logic [7:0] m_axi_arlen;
    logic [2:0] m_axi_arsize;
    logic [1:0] m_axi_arburst;
    logic m_axi_arlock;
    logic [3:0] m_axi_arcache;
    logic [2:0] m_axi_arprot;
    logic [3:0] m_axi_arqos;
    logic [3:0] m_axi_arregion;
    logic [0:0] m_axi_aruser;
    logic m_axi_arvalid;
    logic m_axi_arready;

    logic [AXI_ID_WIDTH-1:0] m_axi_rid;
    logic [AXI_DATA_WIDTH-1:0] m_axi_rdata;
    logic [1:0] m_axi_rresp;
    logic m_axi_rlast;
    logic [0:0] m_axi_ruser;
    logic m_axi_rvalid;
    logic m_axi_rready;

    logic commit_valid;
    logic retire_valid;
    logic [$clog2(ROB_ENTRIES)-1:0] commit_rob_tag;
    logic [31:0] commit_pc;
    logic [31:0] commit_inst;
    logic [4:0] commit_arch_rd;
    logic [$clog2(PHYS_REGS)-1:0] commit_phys_rd;
    logic commit_write_rd;

    logic [31:0] csr_mstatus;
    logic [31:0] csr_mie;
    logic [31:0] csr_mip;
    logic [31:0] csr_mtvec;
    logic [31:0] csr_mepc;
    logic [31:0] csr_mcause;
    logic [31:0] csr_mtval;
    logic [$clog2(PHYS_REGS+1)-1:0] free_count;
    logic rob_full;
    logic iq_full;
    logic lsq_full;
    logic recovery_busy;
    logic pc_err;

    logic [7:0] memory [0:MEM_BYTES-1];

    logic read_active;
    logic [ADDR_WIDTH-1:0] read_addr;
    logic [7:0] read_len;
    logic [7:0] read_beat;
    integer read_wait;

    logic write_active;
    logic write_response_pending;
    logic [ADDR_WIDTH-1:0] write_addr;
    logic [7:0] write_len;
    logic [7:0] write_beat;
    logic [AXI_ID_WIDTH-1:0] write_id;
    integer write_wait;

    integer cycle_count;
    integer start_cycle;
    integer retired_count;
    integer error_count;
    integer log_fd;
    integer dispatch_cycle [0:ROB_ENTRIES-1];
    integer complete_cycle [0:ROB_ENTRIES-1];
    integer total_retire_latency;
    integer total_complete_latency;
    integer complete_samples;
    integer min_retire_latency;
    integer max_retire_latency;

    integer perf_active_cycles;
    integer fetch_request_valid_cycles;
    integer fetch_request_fire_cycles;
    integer fetch_response_fire_cycles;
    integer frontend_packet_valid_cycles;
    integer frontend_packet_fire_cycles;
    integer frontend_empty_cycles;
    integer dispatch_valid_cycles;
    integer dispatch_fire_cycles;
    integer dispatch_backpressure_cycles;
    integer rob_full_stall_cycles;
    integer iq_full_stall_cycles;
    integer lsq_full_stall_cycles;
    integer recovery_stall_cycles;
    integer rob_head_incomplete_cycles;
    integer store_commit_wait_cycles;
    integer integer_issue_cycles;
    integer memory_issue_cycles;
    integer wb_contention_cycles;
    integer lsu_load_issue_cycles;
    integer lsu_store_issue_cycles;
    integer lsu_full_forward_cycles;
    integer lsu_partial_forward_cycles;
    integer lsu_nonalias_bypass_cycles;
    integer lsu_lq_full_stall_cycles;
    integer lsu_sb_full_stall_cycles;
    integer lsu_mem_req_stall_cycles;
    integer lsu_mem_resp_wait_cycles;
    integer lsu_lq_occupancy_sum;
    integer lsu_sb_occupancy_sum;
    integer lsu_cq_occupancy_sum;
    integer lsu_lq_occupancy_max;
    integer lsu_sb_occupancy_max;
    integer lsu_cq_occupancy_max;
    integer frontend_meta_occupancy_sum;
    integer frontend_meta_occupancy_max;
    integer frontend_meta_full_cycles;
    integer fetch_packet_occupancy_sum;
    integer fetch_packet_occupancy_max;
    integer fetch_packet_full_cycles;
    integer icache_hit_response_cycles;
    integer icache_miss_response_cycles;
    integer dcache_mshr_occupancy_sum;
    integer dcache_mshr_occupancy_max;
    integer dcache_mshr_full_cycles;
    integer dcache_request_accept_cycles;
    integer dcache_lower_request_cycles;
    integer dcache_response_cycles;

    localparam int INORDER_PIPELINE_FILL = 4;
    localparam int INORDER_LOAD_USE_PENALTY = 1;
    localparam int INORDER_BRANCH_PENALTY = 2;
    localparam int INORDER_JUMP_PENALTY = 2;
    localparam int INORDER_CSR_PENALTY = 2;

    integer first_dispatch_cycle;
    integer last_retire_cycle;
    integer inorder_cycles;
    integer inorder_load_use_stalls;
    integer inorder_control_stalls;
    integer inorder_csr_stalls;
    logic [31:0] previous_retired_inst;
    logic previous_retired_valid;
    logic branch_taken_by_tag [0:ROB_ENTRIES-1];
    logic [31:0] phys_scoreboard [0:PHYS_REGS-1];
    logic [31:0] arch_scoreboard [0:ARCH_REGS-1];
    logic program_done;
    integer expected_retired_count;
    integer long_first_dispatch_cycle;
    integer long_last_retire_cycle;
    integer long_retired_count;
    logic [31:0] long_loop_start_pc;
    logic [31:0] long_loop_end_pc;

    logic [31:0] taken_wrong_path_pc;
    logic [31:0] jal_wrong_path_pc;
    logic [31:0] done_store_pc;
    logic [31:0] done_addr;

    logic [31:0] sig_alu_add;
    logic [31:0] sig_alu_sub;
    logic [31:0] sig_alu_shift;
    logic [31:0] sig_alu_xor;
    logic [31:0] sig_load_use;
    logic [31:0] sig_taken_branch;
    logic [31:0] sig_not_taken_branch;
    logic [31:0] sig_csr;
    logic [31:0] sig_lbu;
    logic [31:0] sig_lh;
    logic [31:0] sig_lhu;
    logic [31:0] sig_lb_negative;
    logic [31:0] sig_lbu_negative;
    logic [31:0] sig_slt;
    logic [31:0] sig_sltu;
    logic [31:0] sig_ori;
    logic [31:0] sig_and;
    logic [31:0] sig_long_loop;
    logic [31:0] sig_mshr_sum;

    function automatic logic [31:0] enc_r(
        input logic [6:0] funct7,
        input integer rs2,
        input integer rs1,
        input logic [2:0] funct3,
        input integer rd,
        input logic [6:0] opcode
    );
        enc_r = {funct7, rs2[4:0], rs1[4:0], funct3,
                 rd[4:0], opcode};
    endfunction

    function automatic logic [31:0] enc_i(
        input integer imm,
        input integer rs1,
        input logic [2:0] funct3,
        input integer rd,
        input logic [6:0] opcode
    );
        logic [11:0] imm12;
        begin
            imm12 = imm[11:0];
            enc_i = {imm12, rs1[4:0], funct3, rd[4:0], opcode};
        end
    endfunction

    function automatic logic [31:0] enc_s(
        input integer imm,
        input integer rs2,
        input integer rs1,
        input logic [2:0] funct3
    );
        logic [11:0] imm12;
        begin
            imm12 = imm[11:0];
            enc_s = {imm12[11:5], rs2[4:0], rs1[4:0], funct3,
                     imm12[4:0], 7'b0100011};
        end
    endfunction

    function automatic logic [31:0] enc_b(
        input integer imm,
        input integer rs2,
        input integer rs1,
        input logic [2:0] funct3
    );
        logic [12:0] imm13;
        begin
            imm13 = imm[12:0];
            enc_b = {imm13[12], imm13[10:5], rs2[4:0],
                     rs1[4:0], funct3, imm13[4:1],
                     imm13[11], 7'b1100011};
        end
    endfunction

    function automatic logic [31:0] enc_u(
        input integer imm20,
        input integer rd,
        input logic [6:0] opcode
    );
        enc_u = {imm20[19:0], rd[4:0], opcode};
    endfunction

    function automatic logic [31:0] enc_j(
        input integer imm,
        input integer rd
    );
        logic [20:0] imm21;
        begin
            imm21 = imm[20:0];
            enc_j = {imm21[20], imm21[10:1], imm21[11],
                     imm21[19:12], rd[4:0], 7'b1101111};
        end
    endfunction

    function automatic logic [31:0] insn_add(
        input integer rd, input integer rs1, input integer rs2);
        insn_add = enc_r(7'b0000000, rs2, rs1, 3'b000, rd,
                         7'b0110011);
    endfunction
    function automatic logic [31:0] insn_sub(
        input integer rd, input integer rs1, input integer rs2);
        insn_sub = enc_r(7'b0100000, rs2, rs1, 3'b000, rd,
                         7'b0110011);
    endfunction
    function automatic logic [31:0] insn_sll(
        input integer rd, input integer rs1, input integer rs2);
        insn_sll = enc_r(7'b0000000, rs2, rs1, 3'b001, rd,
                         7'b0110011);
    endfunction
    function automatic logic [31:0] insn_slt(
        input integer rd, input integer rs1, input integer rs2);
        insn_slt = enc_r(7'b0000000, rs2, rs1, 3'b010, rd,
                         7'b0110011);
    endfunction
    function automatic logic [31:0] insn_sltu(
        input integer rd, input integer rs1, input integer rs2);
        insn_sltu = enc_r(7'b0000000, rs2, rs1, 3'b011, rd,
                          7'b0110011);
    endfunction
    function automatic logic [31:0] insn_xor(
        input integer rd, input integer rs1, input integer rs2);
        insn_xor = enc_r(7'b0000000, rs2, rs1, 3'b100, rd,
                         7'b0110011);
    endfunction
    function automatic logic [31:0] insn_srl(
        input integer rd, input integer rs1, input integer rs2);
        insn_srl = enc_r(7'b0000000, rs2, rs1, 3'b101, rd,
                         7'b0110011);
    endfunction
    function automatic logic [31:0] insn_sra(
        input integer rd, input integer rs1, input integer rs2);
        insn_sra = enc_r(7'b0100000, rs2, rs1, 3'b101, rd,
                         7'b0110011);
    endfunction
    function automatic logic [31:0] insn_or(
        input integer rd, input integer rs1, input integer rs2);
        insn_or = enc_r(7'b0000000, rs2, rs1, 3'b110, rd,
                        7'b0110011);
    endfunction
    function automatic logic [31:0] insn_and(
        input integer rd, input integer rs1, input integer rs2);
        insn_and = enc_r(7'b0000000, rs2, rs1, 3'b111, rd,
                         7'b0110011);
    endfunction

    function automatic logic [31:0] insn_addi(
        input integer rd, input integer rs1, input integer imm);
        insn_addi = enc_i(imm, rs1, 3'b000, rd, 7'b0010011);
    endfunction
    function automatic logic [31:0] insn_slti(
        input integer rd, input integer rs1, input integer imm);
        insn_slti = enc_i(imm, rs1, 3'b010, rd, 7'b0010011);
    endfunction
    function automatic logic [31:0] insn_sltiu(
        input integer rd, input integer rs1, input integer imm);
        insn_sltiu = enc_i(imm, rs1, 3'b011, rd, 7'b0010011);
    endfunction
    function automatic logic [31:0] insn_xori(
        input integer rd, input integer rs1, input integer imm);
        insn_xori = enc_i(imm, rs1, 3'b100, rd, 7'b0010011);
    endfunction
    function automatic logic [31:0] insn_ori(
        input integer rd, input integer rs1, input integer imm);
        insn_ori = enc_i(imm, rs1, 3'b110, rd, 7'b0010011);
    endfunction
    function automatic logic [31:0] insn_andi(
        input integer rd, input integer rs1, input integer imm);
        insn_andi = enc_i(imm, rs1, 3'b111, rd, 7'b0010011);
    endfunction
    function automatic logic [31:0] insn_slli(
        input integer rd, input integer rs1, input integer shamt);
        insn_slli = enc_i(shamt & 31, rs1, 3'b001, rd,
                          7'b0010011);
    endfunction
    function automatic logic [31:0] insn_srli(
        input integer rd, input integer rs1, input integer shamt);
        insn_srli = enc_i(shamt & 31, rs1, 3'b101, rd,
                          7'b0010011);
    endfunction
    function automatic logic [31:0] insn_srai(
        input integer rd, input integer rs1, input integer shamt);
        insn_srai = enc_i(12'h400 | (shamt & 31), rs1,
                          3'b101, rd, 7'b0010011);
    endfunction

    function automatic logic [31:0] insn_lb(
        input integer rd, input integer rs1, input integer imm);
        insn_lb = enc_i(imm, rs1, 3'b000, rd, 7'b0000011);
    endfunction
    function automatic logic [31:0] insn_lh(
        input integer rd, input integer rs1, input integer imm);
        insn_lh = enc_i(imm, rs1, 3'b001, rd, 7'b0000011);
    endfunction
    function automatic logic [31:0] insn_lw(
        input integer rd, input integer rs1, input integer imm);
        insn_lw = enc_i(imm, rs1, 3'b010, rd, 7'b0000011);
    endfunction
    function automatic logic [31:0] insn_lbu(
        input integer rd, input integer rs1, input integer imm);
        insn_lbu = enc_i(imm, rs1, 3'b100, rd, 7'b0000011);
    endfunction
    function automatic logic [31:0] insn_lhu(
        input integer rd, input integer rs1, input integer imm);
        insn_lhu = enc_i(imm, rs1, 3'b101, rd, 7'b0000011);
    endfunction

    function automatic logic [31:0] insn_sb(
        input integer rs2, input integer rs1, input integer imm);
        insn_sb = enc_s(imm, rs2, rs1, 3'b000);
    endfunction
    function automatic logic [31:0] insn_sh(
        input integer rs2, input integer rs1, input integer imm);
        insn_sh = enc_s(imm, rs2, rs1, 3'b001);
    endfunction
    function automatic logic [31:0] insn_sw(
        input integer rs2, input integer rs1, input integer imm);
        insn_sw = enc_s(imm, rs2, rs1, 3'b010);
    endfunction

    function automatic logic [31:0] insn_beq(
        input integer rs1, input integer rs2, input integer imm);
        insn_beq = enc_b(imm, rs2, rs1, 3'b000);
    endfunction
    function automatic logic [31:0] insn_bne(
        input integer rs1, input integer rs2, input integer imm);
        insn_bne = enc_b(imm, rs2, rs1, 3'b001);
    endfunction
    function automatic logic [31:0] insn_blt(
        input integer rs1, input integer rs2, input integer imm);
        insn_blt = enc_b(imm, rs2, rs1, 3'b100);
    endfunction
    function automatic logic [31:0] insn_bge(
        input integer rs1, input integer rs2, input integer imm);
        insn_bge = enc_b(imm, rs2, rs1, 3'b101);
    endfunction
    function automatic logic [31:0] insn_bltu(
        input integer rs1, input integer rs2, input integer imm);
        insn_bltu = enc_b(imm, rs2, rs1, 3'b110);
    endfunction
    function automatic logic [31:0] insn_bgeu(
        input integer rs1, input integer rs2, input integer imm);
        insn_bgeu = enc_b(imm, rs2, rs1, 3'b111);
    endfunction

    function automatic logic [31:0] insn_lui(
        input integer rd, input integer imm20);
        insn_lui = enc_u(imm20, rd, 7'b0110111);
    endfunction
    function automatic logic [31:0] insn_auipc(
        input integer rd, input integer imm20);
        insn_auipc = enc_u(imm20, rd, 7'b0010111);
    endfunction
    function automatic logic [31:0] insn_jal(
        input integer rd, input integer imm);
        insn_jal = enc_j(imm, rd);
    endfunction
    function automatic logic [31:0] insn_jalr(
        input integer rd, input integer rs1, input integer imm);
        insn_jalr = enc_i(imm, rs1, 3'b000, rd, 7'b1100111);
    endfunction

    function automatic logic [31:0] enc_csr(
        input logic [11:0] csr,
        input integer rs1_or_zimm,
        input logic [2:0] funct3,
        input integer rd
    );
        enc_csr = {csr, rs1_or_zimm[4:0], funct3, rd[4:0],
                   7'b1110011};
    endfunction
    function automatic logic [31:0] insn_csrrw(
        input integer rd, input logic [11:0] csr, input integer rs1);
        insn_csrrw = enc_csr(csr, rs1, 3'b001, rd);
    endfunction
    function automatic logic [31:0] insn_csrrs(
        input integer rd, input logic [11:0] csr, input integer rs1);
        insn_csrrs = enc_csr(csr, rs1, 3'b010, rd);
    endfunction
    function automatic logic [31:0] insn_csrrc(
        input integer rd, input logic [11:0] csr, input integer rs1);
        insn_csrrc = enc_csr(csr, rs1, 3'b011, rd);
    endfunction
    function automatic logic [31:0] insn_csrrwi(
        input integer rd, input logic [11:0] csr, input integer zimm);
        insn_csrrwi = enc_csr(csr, zimm, 3'b101, rd);
    endfunction
    function automatic logic [31:0] insn_csrrsi(
        input integer rd, input logic [11:0] csr, input integer zimm);
        insn_csrrsi = enc_csr(csr, zimm, 3'b110, rd);
    endfunction
    function automatic logic [31:0] insn_csrrci(
        input integer rd, input logic [11:0] csr, input integer zimm);
        insn_csrrci = enc_csr(csr, zimm, 3'b111, rd);
    endfunction

    function automatic logic [31:0] insn_fence();
        insn_fence = 32'h0ff0_000f;
    endfunction
    function automatic logic [31:0] insn_fence_i();
        insn_fence_i = 32'h0000_100f;
    endfunction

    function automatic logic [31:0] insn_ecall();
        insn_ecall = 32'h0000_0073;
    endfunction
    function automatic logic [31:0] insn_ebreak();
        insn_ebreak = 32'h0010_0073;
    endfunction
    function automatic logic [31:0] insn_mret();
        insn_mret = 32'h3020_0073;
    endfunction
    function automatic logic [31:0] insn_nop();
        insn_nop = insn_addi(0, 0, 0);
    endfunction

    function automatic string mnemonic(input logic [31:0] inst);
        begin
            unique case (inst[6:0])
                7'b0110011: begin
                    unique case (inst[14:12])
                        3'b000: mnemonic =
                            inst[30] ? "SUB" : "ADD";
                        3'b001: mnemonic = "SLL";
                        3'b010: mnemonic = "SLT";
                        3'b011: mnemonic = "SLTU";
                        3'b100: mnemonic = "XOR";
                        3'b101: mnemonic =
                            inst[30] ? "SRA" : "SRL";
                        3'b110: mnemonic = "OR";
                        default: mnemonic = "AND";
                    endcase
                end
                7'b0010011: begin
                    unique case (inst[14:12])
                        3'b000: mnemonic = "ADDI";
                        3'b001: mnemonic = "SLLI";
                        3'b010: mnemonic = "SLTI";
                        3'b011: mnemonic = "SLTIU";
                        3'b100: mnemonic = "XORI";
                        3'b101: mnemonic =
                            inst[30] ? "SRAI" : "SRLI";
                        3'b110: mnemonic = "ORI";
                        default: mnemonic = "ANDI";
                    endcase
                end
                7'b0000011: mnemonic = "LOAD";
                7'b0100011: mnemonic = "STORE";
                7'b1100011: mnemonic = "BRANCH";
                7'b1101111: mnemonic = "JAL";
                7'b1100111: mnemonic = "JALR";
                7'b0110111: mnemonic = "LUI";
                7'b0010111: mnemonic = "AUIPC";
                7'b0001111: mnemonic =
                    inst[14:12] == 3'b001 ? "FENCE.I" : "FENCE";
                7'b1110011: mnemonic =
                    (inst == 32'h3020_0073) ? "MRET" : "SYSTEM";
                default: mnemonic = "UNKNOWN";
            endcase
        end
    endfunction

    function automatic logic baseline_is_load(
        input logic [31:0] inst
    );
        baseline_is_load = (inst[6:0] == 7'b0000011);
    endfunction

    function automatic logic baseline_is_branch(
        input logic [31:0] inst
    );
        baseline_is_branch = (inst[6:0] == 7'b1100011);
    endfunction

    function automatic logic baseline_is_jump(
        input logic [31:0] inst
    );
        baseline_is_jump =
            (inst[6:0] == 7'b1101111) ||
            (inst[6:0] == 7'b1100111);
    endfunction

    function automatic logic baseline_is_csr(
        input logic [31:0] inst
    );
        baseline_is_csr =
            (inst[6:0] == 7'b1110011) &&
            (inst[14:12] != 3'b000);
    endfunction

    function automatic logic baseline_uses_rs1(
        input logic [31:0] inst
    );
        begin
            unique case (inst[6:0])
                7'b0110011,
                7'b0010011,
                7'b0000011,
                7'b0100011,
                7'b1100011,
                7'b1100111:
                    baseline_uses_rs1 = 1'b1;

                7'b1110011:
                    baseline_uses_rs1 =
                        (inst[14:12] == 3'b001) ||
                        (inst[14:12] == 3'b010) ||
                        (inst[14:12] == 3'b011);

                default:
                    baseline_uses_rs1 = 1'b0;
            endcase
        end
    endfunction

    function automatic logic baseline_uses_rs2(
        input logic [31:0] inst
    );
        begin
            unique case (inst[6:0])
                7'b0110011,
                7'b0100011,
                7'b1100011:
                    baseline_uses_rs2 = 1'b1;

                default:
                    baseline_uses_rs2 = 1'b0;
            endcase
        end
    endfunction

    function automatic logic baseline_load_use_hazard(
        input logic [31:0] previous_inst,
        input logic [31:0] current_inst
    );
        logic [4:0] previous_rd;
        logic [4:0] current_rs1;
        logic [4:0] current_rs2;
        begin
            previous_rd = previous_inst[11:7];
            current_rs1 = current_inst[19:15];
            current_rs2 = current_inst[24:20];

            baseline_load_use_hazard =
                baseline_is_load(previous_inst) &&
                (previous_rd != 5'd0) &&
                ((baseline_uses_rs1(current_inst) &&
                  (current_rs1 == previous_rd)) ||
                 (baseline_uses_rs2(current_inst) &&
                  (current_rs2 == previous_rd)));
        end
    endfunction

    task automatic log_line(input string message);
        begin
            $display("%s", message);
            if (log_fd != 0)
                $fdisplay(log_fd, "%s", message);
        end
    endtask

    task automatic write_word(
        input logic [31:0] addr,
        input logic [31:0] data
    );
        begin
            if ((addr + 3) >= MEM_BYTES)
                $fatal(1, "write_word address out of range: %08x",
                       addr);
            memory[addr + 0] = data[7:0];
            memory[addr + 1] = data[15:8];
            memory[addr + 2] = data[23:16];
            memory[addr + 3] = data[31:24];
        end
    endtask

    function automatic logic [31:0] read_word(
        input logic [31:0] addr
    );
        read_word = {
            memory[addr + 3], memory[addr + 2],
            memory[addr + 1], memory[addr + 0]
        };
    endfunction

    function automatic logic [AXI_DATA_WIDTH-1:0] read_axi_beat(
        input logic [31:0] addr
    );
        logic [AXI_DATA_WIDTH-1:0] result;
        begin
            result = '0;
            for (int byte_idx = 0;
                 byte_idx < AXI_STRB_WIDTH;
                 byte_idx++) begin
                if ((addr + byte_idx) < MEM_BYTES)
                    result[byte_idx * 8 +: 8] =
                        memory[addr + byte_idx];
            end
            read_axi_beat = result;
        end
    endfunction

    task automatic emit_inst(
        inout logic [31:0] pc,
        input logic [31:0] inst,
        input logic expected_to_retire
    );
        begin
            write_word(pc, inst);
            if (expected_to_retire)
                expected_retired_count =
                    expected_retired_count + 1;
            pc = pc + 4;
        end
    endtask

    task automatic alloc_signature(
        inout logic [31:0] next_addr,
        output logic [31:0] allocated_addr
    );
        begin
            allocated_addr = next_addr;
            next_addr = next_addr + 4;
        end
    endtask

    task automatic load_program;
        logic [31:0] pc;
        logic [31:0] next_signature;
        begin
            pc = PROGRAM_BASE;
            next_signature = SIGNATURE_BASE;
            expected_retired_count = 0;
            taken_wrong_path_pc = '0;
            jal_wrong_path_pc = '0;
            done_store_pc = '0;
            done_addr = '0;
            long_loop_start_pc = '0;
            long_loop_end_pc = '0;

            alloc_signature(next_signature, sig_alu_add);
            alloc_signature(next_signature, sig_alu_sub);
            alloc_signature(next_signature, sig_alu_shift);
            alloc_signature(next_signature, sig_alu_xor);
            alloc_signature(next_signature, sig_load_use);
            alloc_signature(next_signature, sig_taken_branch);
            alloc_signature(next_signature, sig_not_taken_branch);
            alloc_signature(next_signature, sig_csr);
            alloc_signature(next_signature, sig_lbu);
            alloc_signature(next_signature, sig_lh);
            alloc_signature(next_signature, sig_lhu);
            alloc_signature(next_signature, sig_lb_negative);
            alloc_signature(next_signature, sig_lbu_negative);
            alloc_signature(next_signature, sig_slt);
            alloc_signature(next_signature, sig_sltu);
            alloc_signature(next_signature, sig_ori);
            alloc_signature(next_signature, sig_and);
            alloc_signature(next_signature, sig_long_loop);
            alloc_signature(next_signature, sig_mshr_sum);

            write_word(SCRATCH_BASE + 32'h100, 32'd1);
            write_word(SCRATCH_BASE + 32'h140, 32'd2);
            write_word(SCRATCH_BASE + 32'h180, 32'd3);
            write_word(SCRATCH_BASE + 32'h1c0, 32'd4);

            log_line("[PROGRAM] section 1: ALU dependency chain");
            emit_inst(pc, insn_addi(1, 0, 10), 1'b1);
            emit_inst(pc, insn_addi(2, 0, 20), 1'b1);
            emit_inst(pc, insn_add(3, 1, 2), 1'b1);
            emit_inst(pc, insn_sub(4, 3, 1), 1'b1);
            emit_inst(pc, insn_slli(5, 4, 2), 1'b1);
            emit_inst(pc, insn_xor(6, 5, 3), 1'b1);
            emit_inst(pc, insn_sw(3, 0, sig_alu_add), 1'b1);
            emit_inst(pc, insn_sw(4, 0, sig_alu_sub), 1'b1);
            emit_inst(pc, insn_sw(5, 0, sig_alu_shift), 1'b1);
            emit_inst(pc, insn_sw(6, 0, sig_alu_xor), 1'b1);

            log_line("[PROGRAM] section 2: load-use dependency");
            emit_inst(pc, insn_lw(7, 0, sig_alu_add), 1'b1);
            emit_inst(pc, insn_add(8, 7, 1), 1'b1);
            emit_inst(pc, insn_sw(8, 0, sig_load_use), 1'b1);

            log_line("[PROGRAM] section 3: taken branch recovery");
            emit_inst(pc, insn_beq(8, 8, 8), 1'b1);
            taken_wrong_path_pc = pc;
            emit_inst(pc, insn_addi(9, 0, 99), 1'b0);
            emit_inst(pc, insn_addi(9, 0, 1), 1'b1);
            emit_inst(pc, insn_sw(9, 0, sig_taken_branch), 1'b1);

            log_line("[PROGRAM] section 4: not-taken branch and JAL");
            emit_inst(pc, insn_bne(9, 9, 8), 1'b1);
            emit_inst(pc, insn_addi(10, 0, 2), 1'b1);
            emit_inst(pc, insn_jal(0, 8), 1'b1);
            jal_wrong_path_pc = pc;
            emit_inst(pc, insn_addi(10, 0, 88), 1'b0);
            emit_inst(pc, insn_sw(10, 0, sig_not_taken_branch), 1'b1);

            log_line("[PROGRAM] section 5: CSR read/write");
            emit_inst(pc, insn_addi(12, 0, 5), 1'b1);
            emit_inst(pc, insn_csrrw(13, 12'h340, 12), 1'b1);
            emit_inst(pc, insn_csrrs(14, 12'h340, 0), 1'b1);
            emit_inst(pc, insn_sw(14, 0, sig_csr), 1'b1);

            log_line("[PROGRAM] section 6: byte/halfword load-store");
            emit_inst(pc, insn_addi(15, 0, 127), 1'b1);
            emit_inst(pc, insn_sb(15, 0, SCRATCH_BASE), 1'b1);
            emit_inst(pc, insn_lbu(16, 0, SCRATCH_BASE), 1'b1);
            emit_inst(pc, insn_addi(17, 0, -1), 1'b1);
            emit_inst(pc, insn_sh(17, 0, SCRATCH_BASE + 2), 1'b1);
            emit_inst(pc, insn_lh(18, 0, SCRATCH_BASE + 2), 1'b1);
            emit_inst(pc, insn_lhu(19, 0, SCRATCH_BASE + 2), 1'b1);
            emit_inst(pc, insn_sw(16, 0, sig_lbu), 1'b1);
            emit_inst(pc, insn_sw(18, 0, sig_lh), 1'b1);
            emit_inst(pc, insn_sw(19, 0, sig_lhu), 1'b1);

            log_line("[PROGRAM] section 7: signed/unsigned byte load");
            emit_inst(pc, insn_addi(20, 0, -2), 1'b1);
            emit_inst(pc, insn_sb(20, 0, SCRATCH_BASE + 4), 1'b1);
            emit_inst(pc, insn_lb(21, 0, SCRATCH_BASE + 4), 1'b1);
            emit_inst(pc, insn_lbu(22, 0, SCRATCH_BASE + 4), 1'b1);
            emit_inst(pc, insn_sw(21, 0, sig_lb_negative), 1'b1);
            emit_inst(pc, insn_sw(22, 0, sig_lbu_negative), 1'b1);

            log_line("[PROGRAM] section 8: comparison and bitwise");
            emit_inst(pc, insn_slt(23, 17, 1), 1'b1);
            emit_inst(pc, insn_sltu(24, 17, 1), 1'b1);
            emit_inst(pc, insn_ori(25, 0, 12'h055), 1'b1);
            emit_inst(pc, insn_and(26, 25, 6), 1'b1);
            emit_inst(pc, insn_sw(23, 0, sig_slt), 1'b1);
            emit_inst(pc, insn_sw(24, 0, sig_sltu), 1'b1);
            emit_inst(pc, insn_sw(25, 0, sig_ori), 1'b1);
            emit_inst(pc, insn_sw(26, 0, sig_and), 1'b1);

            log_line("[PROGRAM] section 9: four independent cache misses");
            emit_inst(pc, insn_lw(28, 0, SCRATCH_BASE + 32'h100), 1'b1);
            emit_inst(pc, insn_lw(29, 0, SCRATCH_BASE + 32'h140), 1'b1);
            emit_inst(pc, insn_lw(30, 0, SCRATCH_BASE + 32'h180), 1'b1);
            emit_inst(pc, insn_lw(31, 0, SCRATCH_BASE + 32'h1c0), 1'b1);
            emit_inst(pc, insn_add(28, 28, 29), 1'b1);
            emit_inst(pc, insn_add(30, 30, 31), 1'b1);
            emit_inst(pc, insn_add(28, 28, 30), 1'b1);
            emit_inst(pc, insn_sw(28, 0, sig_mshr_sum), 1'b1);

            log_line("[PROGRAM] section 10: 128-iteration warm frontend loop");
            emit_inst(pc, insn_addi(28, 0, 0), 1'b1);
            emit_inst(pc, insn_addi(29, 0, LONG_LOOP_ITERS), 1'b1);
            emit_inst(pc, insn_addi(30, 0, 0), 1'b1);
            emit_inst(pc, insn_addi(31, 0, 0), 1'b1);
            long_loop_start_pc = pc;
            emit_inst(pc, insn_addi(28, 28, 1), 1'b1);
            emit_inst(pc, insn_addi(30, 30, 3), 1'b1);
            emit_inst(pc, insn_addi(31, 31, 5), 1'b1);
            emit_inst(pc, insn_addi(29, 29, -1), 1'b1);
            emit_inst(pc, insn_bne(29, 0,
                long_loop_start_pc - pc), 1'b1);
            long_loop_end_pc = pc;
            expected_retired_count = expected_retired_count +
                (LONG_LOOP_ITERS - 1) * 5;
            emit_inst(pc, insn_sw(28, 0, sig_long_loop), 1'b1);

            log_line("[PROGRAM] final dynamic completion signature");
            alloc_signature(next_signature, done_addr);
            emit_inst(pc, insn_addi(27, 0, 1), 1'b1);
            done_store_pc = pc;
            emit_inst(pc, insn_sw(27, 0, done_addr), 1'b1);
            emit_inst(pc, insn_jal(0, 0), 1'b0);

            log_line($sformatf(
                "[PROGRAM] done_addr=%08x done_store_pc=%08x expected_retired=%0d",
                done_addr, done_store_pc, expected_retired_count));
        end
    endtask

    task automatic check_reg(
        input integer reg_idx,
        input logic [31:0] expected
    );
        begin
            if (arch_scoreboard[reg_idx] !== expected) begin
                error_count = error_count + 1;
                log_line($sformatf(
                    "[CHECK][FAIL] x%0d expected=%08x actual=%08x",
                    reg_idx, expected, arch_scoreboard[reg_idx]));
            end
            else begin
                log_line($sformatf(
                    "[CHECK][PASS] x%0d = %08x",
                    reg_idx, arch_scoreboard[reg_idx]));
            end
        end
    endtask

    task automatic check_mem(
        input logic [31:0] addr,
        input logic [31:0] expected
    );
        logic [31:0] actual;
        begin
            actual = read_word(addr);
            if (actual !== expected) begin
                error_count = error_count + 1;
                log_line($sformatf(
                    "[CHECK][FAIL] MEM[%08x] expected=%08x actual=%08x",
                    addr, expected, actual));
            end
            else begin
                log_line($sformatf(
                    "[CHECK][PASS] MEM[%08x] = %08x",
                    addr, actual));
            end
        end
    endtask

    task automatic report_results;
        integer elapsed_cycles;
        real ipc;
        real average_retire_latency;
        real average_complete_latency;
        integer ooo_core_cycles;
        integer ideal_cycles;
        integer extra_inorder_cycles;
        real core_ipc;
        real ideal_efficiency;
        real inorder_ipc;
        real speedup_vs_inorder;
        integer long_loop_cycles;
        real long_loop_ipc;
        begin
            elapsed_cycles = cycle_count - start_cycle + 1;
            ipc = $itor(retired_count) / $itor(elapsed_cycles);
            average_retire_latency =
                $itor(total_retire_latency) / $itor(retired_count);
            average_complete_latency =
                (complete_samples == 0) ? 0.0 :
                $itor(total_complete_latency) /
                $itor(complete_samples);

            ooo_core_cycles =
                (first_dispatch_cycle >= 0 &&
                 last_retire_cycle >= first_dispatch_cycle) ?
                (last_retire_cycle - first_dispatch_cycle + 1) :
                elapsed_cycles;
            ideal_cycles = retired_count;
            extra_inorder_cycles =
                inorder_cycles - ideal_cycles -
                INORDER_PIPELINE_FILL;

            core_ipc = $itor(retired_count) /
                       $itor(ooo_core_cycles);
            ideal_efficiency = core_ipc * 100.0;
            inorder_ipc = $itor(retired_count) /
                          $itor(inorder_cycles);
            speedup_vs_inorder =
                $itor(inorder_cycles) /
                $itor(ooo_core_cycles);
            long_loop_cycles =
                (long_first_dispatch_cycle >= 0 &&
                 long_last_retire_cycle >= long_first_dispatch_cycle) ?
                long_last_retire_cycle - long_first_dispatch_cycle + 1 : 0;
            long_loop_ipc = (long_loop_cycles == 0) ? 0.0 :
                $itor(long_retired_count) / $itor(long_loop_cycles);

            log_line("--------------------------------------------------");
            log_line("[TEST] Checking architectural results");
            check_reg(1, 32'd10);
            check_reg(2, 32'd20);
            check_reg(3, 32'd30);
            check_reg(4, 32'd20);
            check_reg(5, 32'd80);
            check_reg(6, 32'd78);
            check_reg(7, 32'd30);
            check_reg(8, 32'd40);
            check_reg(9, 32'd1);
            check_reg(10, 32'd2);
            check_reg(12, 32'd5);
            check_reg(13, 32'd0);
            check_reg(14, 32'd5);
            check_reg(16, 32'd127);
            check_reg(17, 32'hffff_ffff);
            check_reg(18, 32'hffff_ffff);
            check_reg(19, 32'h0000_ffff);
            check_reg(20, 32'hffff_fffe);
            check_reg(21, 32'hffff_fffe);
            check_reg(22, 32'h0000_00fe);
            check_reg(23, 32'd1);
            check_reg(24, 32'd0);
            check_reg(25, 32'h0000_0055);
            check_reg(26, 32'h0000_0044);
            check_reg(27, 32'd1);
            check_reg(28, LONG_LOOP_ITERS);

            check_mem(sig_alu_add, 32'd30);
            check_mem(sig_alu_sub, 32'd20);
            check_mem(sig_alu_shift, 32'd80);
            check_mem(sig_alu_xor, 32'd78);
            check_mem(sig_load_use, 32'd40);
            check_mem(sig_taken_branch, 32'd1);
            check_mem(sig_not_taken_branch, 32'd2);
            check_mem(sig_csr, 32'd5);
            check_mem(sig_lbu, 32'd127);
            check_mem(sig_lh, 32'hffff_ffff);
            check_mem(sig_lhu, 32'h0000_ffff);
            check_mem(sig_lb_negative, 32'hffff_fffe);
            check_mem(sig_lbu_negative, 32'h0000_00fe);
            check_mem(sig_slt, 32'd1);
            check_mem(sig_sltu, 32'd0);
            check_mem(sig_ori, 32'h0000_0055);
            check_mem(sig_and, 32'h0000_0044);
            check_mem(sig_long_loop, LONG_LOOP_ITERS);
            check_mem(sig_mshr_sum, 32'd10);
            check_mem(done_addr, 32'd1);

            if (retired_count != expected_retired_count) begin
                error_count = error_count + 1;
                log_line($sformatf(
                    "[CHECK][FAIL] retired instructions expected=%0d actual=%0d",
                    expected_retired_count, retired_count));
            end
            else begin
                log_line($sformatf(
                    "[CHECK][PASS] retired instructions = %0d",
                    retired_count));
            end

            if (pc_err) begin
                error_count = error_count + 1;
                log_line("[CHECK][FAIL] frontend pc_err asserted");
            end

            log_line("--------------------------------------------------");
            log_line("[PERF] Performance summary");
            log_line($sformatf("[PERF] total cycles          : %0d",
                               elapsed_cycles));
            log_line($sformatf("[PERF] retired instructions  : %0d",
                               retired_count));
            log_line($sformatf("[PERF] IPC                   : %0.4f",
                               ipc));
            log_line($sformatf("[PERF] avg dispatch->WB      : %0.2f cycles",
                               average_complete_latency));
            log_line($sformatf("[PERF] avg dispatch->commit  : %0.2f cycles",
                               average_retire_latency));
            log_line($sformatf("[PERF] min dispatch->commit  : %0d cycles",
                               min_retire_latency));
            log_line($sformatf("[PERF] max dispatch->commit  : %0d cycles",
                               max_retire_latency));
            log_line("--------------------------------------------------");
            log_line("[LONG] Warm-loop IPC summary");
            log_line($sformatf("[LONG] loop iterations       : %0d",
                               LONG_LOOP_ITERS));
            log_line($sformatf("[LONG] retired instructions  : %0d",
                               long_retired_count));
            log_line($sformatf("[LONG] dispatch->last retire : %0d cycles",
                               long_loop_cycles));
            log_line($sformatf("[LONG] warm-loop IPC         : %0.4f",
                               long_loop_ipc));
            log_line("--------------------------------------------------");
            log_line("[SUPPLY] Frontend/backend cycle breakdown");
            log_line($sformatf("[SUPPLY] measured active cycles       : %0d",
                               perf_active_cycles));
            log_line($sformatf("[SUPPLY] fetch request valid/fire    : %0d / %0d",
                               fetch_request_valid_cycles,
                               fetch_request_fire_cycles));
            log_line($sformatf("[SUPPLY] fetch responses              : %0d",
                               fetch_response_fire_cycles));
            log_line($sformatf("[SUPPLY] IF packet valid/accepted    : %0d / %0d",
                               frontend_packet_valid_cycles,
                               frontend_packet_fire_cycles));
            log_line($sformatf("[SUPPLY] dispatch valid/accepted     : %0d / %0d",
                               dispatch_valid_cycles,
                               dispatch_fire_cycles));
            log_line($sformatf("[SUPPLY] frontend delivery rate       : %0.2f%%",
                               (perf_active_cycles == 0) ? 0.0 :
                               100.0 * $itor(frontend_packet_fire_cycles) /
                               $itor(perf_active_cycles)));
            log_line($sformatf("[SUPPLY] dispatch supply rate         : %0.2f%%",
                               (perf_active_cycles == 0) ? 0.0 :
                               100.0 * $itor(dispatch_fire_cycles) /
                               $itor(perf_active_cycles)));
            log_line($sformatf("[SUPPLY] frontend empty cycles        : %0d",
                               frontend_empty_cycles));
            log_line($sformatf("[SUPPLY] I-cache hit/miss responses  : %0d / %0d",
                               icache_hit_response_cycles,
                               icache_miss_response_cycles));
            log_line($sformatf("[SUPPLY] metadata FIFO avg/max/full : %0.2f / %0d / %0d",
                               (perf_active_cycles == 0) ? 0.0 :
                               $itor(frontend_meta_occupancy_sum) /
                               $itor(perf_active_cycles),
                               frontend_meta_occupancy_max,
                               frontend_meta_full_cycles));
            log_line($sformatf("[SUPPLY] packet FIFO avg/max/full   : %0.2f / %0d / %0d",
                               (perf_active_cycles == 0) ? 0.0 :
                               $itor(fetch_packet_occupancy_sum) /
                               $itor(perf_active_cycles),
                               fetch_packet_occupancy_max,
                               fetch_packet_full_cycles));
            log_line($sformatf("[STALL] dispatch backpressure         : %0d",
                               dispatch_backpressure_cycles));
            log_line($sformatf("[STALL] ROB/IQ/LSQ full             : %0d / %0d / %0d",
                               rob_full_stall_cycles, iq_full_stall_cycles,
                               lsq_full_stall_cycles));
            log_line($sformatf("[STALL] recovery busy                 : %0d",
                               recovery_stall_cycles));
            log_line($sformatf("[STALL] ROB head incomplete           : %0d",
                               rob_head_incomplete_cycles));
            log_line($sformatf("[STALL] store commit wait             : %0d",
                               store_commit_wait_cycles));
            log_line($sformatf("[ISSUE] integer/memory grants        : %0d / %0d",
                               integer_issue_cycles, memory_issue_cycles));
            log_line($sformatf("[ISSUE] WB contention cycles          : %0d",
                               wb_contention_cycles));
            log_line("--------------------------------------------------");
            log_line("[LSU] Parallel LSU and forwarding breakdown");
            log_line($sformatf("[LSU] load/store issues              : %0d / %0d",
                               lsu_load_issue_cycles,
                               lsu_store_issue_cycles));
            log_line($sformatf("[LSU] full/partial forwarding        : %0d / %0d",
                               lsu_full_forward_cycles,
                               lsu_partial_forward_cycles));
            log_line($sformatf("[LSU] non-alias load bypasses         : %0d",
                               lsu_nonalias_bypass_cycles));
            log_line($sformatf("[LSU] LQ/SB full stalls              : %0d / %0d",
                               lsu_lq_full_stall_cycles,
                               lsu_sb_full_stall_cycles));
            log_line($sformatf("[LSU] memory req stall/resp wait     : %0d / %0d",
                               lsu_mem_req_stall_cycles,
                               lsu_mem_resp_wait_cycles));
            log_line($sformatf("[LSU] avg LQ/SB/CQ occupancy        : %0.2f / %0.2f / %0.2f",
                               (perf_active_cycles == 0) ? 0.0 :
                                   $itor(lsu_lq_occupancy_sum) /
                                   $itor(perf_active_cycles),
                               (perf_active_cycles == 0) ? 0.0 :
                                   $itor(lsu_sb_occupancy_sum) /
                                   $itor(perf_active_cycles),
                               (perf_active_cycles == 0) ? 0.0 :
                                   $itor(lsu_cq_occupancy_sum) /
                                   $itor(perf_active_cycles)));
            log_line($sformatf("[LSU] max LQ/SB/CQ occupancy        : %0d / %0d / %0d",
                               lsu_lq_occupancy_max,
                               lsu_sb_occupancy_max,
                               lsu_cq_occupancy_max));
            log_line($sformatf("[DCACHE] MSHR avg/max/full cycles   : %0.2f / %0d / %0d",
                               (perf_active_cycles == 0) ? 0.0 :
                               $itor(dcache_mshr_occupancy_sum) /
                               $itor(perf_active_cycles),
                               dcache_mshr_occupancy_max,
                               dcache_mshr_full_cycles));
            log_line($sformatf("[DCACHE] CPU req/lower req/response : %0d / %0d / %0d",
                               dcache_request_accept_cycles,
                               dcache_lower_request_cycles,
                               dcache_response_cycles));
            log_line("--------------------------------------------------");
            log_line("[BASELINE] 5-stage in-order shadow timing model");
            log_line("[BASELINE] cache/AXI miss penalties are excluded");
            log_line($sformatf(
                "[BASELINE] ideal IPC=1 cycles    : %0d",
                ideal_cycles));
            log_line($sformatf(
                "[BASELINE] in-order total cycles : %0d",
                inorder_cycles));
            log_line($sformatf(
                "[BASELINE] pipeline fill cycles  : %0d",
                INORDER_PIPELINE_FILL));
            log_line($sformatf(
                "[BASELINE] load-use stall cycles : %0d",
                inorder_load_use_stalls));
            log_line($sformatf(
                "[BASELINE] control stall cycles  : %0d",
                inorder_control_stalls));
            log_line($sformatf(
                "[BASELINE] CSR stall cycles      : %0d",
                inorder_csr_stalls));
            log_line($sformatf(
                "[BASELINE] total penalty cycles  : %0d",
                extra_inorder_cycles));
            log_line($sformatf(
                "[BASELINE] in-order IPC           : %0.4f",
                inorder_ipc));
            log_line("--------------------------------------------------");
            log_line("[COMPARE] OoO vs baseline");
            log_line($sformatf(
                "[COMPARE] OoO core cycles        : %0d",
                ooo_core_cycles));
            log_line($sformatf(
                "[COMPARE] OoO core IPC           : %0.4f",
                core_ipc));
            log_line($sformatf(
                "[COMPARE] IPC=1 efficiency       : %0.2f%%",
                ideal_efficiency));
            log_line($sformatf(
                "[COMPARE] speedup vs in-order    : %0.3fx",
                speedup_vs_inorder));
            log_line("--------------------------------------------------");

            if (error_count == 0)
                log_line("[TEST][PASS] RV32I OoO core test completed successfully");
            else
                log_line($sformatf(
                    "[TEST][FAIL] %0d error(s) detected", error_count));
        end
    endtask


    // The in-order baseline is updated from the committed instruction
    // stream in the main scoreboard always block below.

    rv32_ooo_core_top #(
        .ICACHE_LINES(16),
        .DCACHE_LINES(16),
        .CACHE_REQ_FIFO_DEPTH(4),
        .AXI_DATA_WIDTH(AXI_DATA_WIDTH),
        .AXI_ID_WIDTH(AXI_ID_WIDTH),
        .RESET_MTVEC(PROGRAM_BASE)
    ) dut (
        .ACLK(ACLK),
        .ARESETn(ARESETn),
        .fetch_enable(fetch_enable),
        .irq_software(irq_software),
        .irq_timer(irq_timer),
        .irq_external(irq_external),
        .m_axi_awid(m_axi_awid),
        .m_axi_awaddr(m_axi_awaddr),
        .m_axi_awlen(m_axi_awlen),
        .m_axi_awsize(m_axi_awsize),
        .m_axi_awburst(m_axi_awburst),
        .m_axi_awlock(m_axi_awlock),
        .m_axi_awcache(m_axi_awcache),
        .m_axi_awprot(m_axi_awprot),
        .m_axi_awqos(m_axi_awqos),
        .m_axi_awregion(m_axi_awregion),
        .m_axi_awuser(m_axi_awuser),
        .m_axi_awvalid(m_axi_awvalid),
        .m_axi_awready(m_axi_awready),
        .m_axi_wdata(m_axi_wdata),
        .m_axi_wstrb(m_axi_wstrb),
        .m_axi_wlast(m_axi_wlast),
        .m_axi_wuser(m_axi_wuser),
        .m_axi_wvalid(m_axi_wvalid),
        .m_axi_wready(m_axi_wready),
        .m_axi_bid(m_axi_bid),
        .m_axi_bresp(m_axi_bresp),
        .m_axi_buser(m_axi_buser),
        .m_axi_bvalid(m_axi_bvalid),
        .m_axi_bready(m_axi_bready),
        .m_axi_arid(m_axi_arid),
        .m_axi_araddr(m_axi_araddr),
        .m_axi_arlen(m_axi_arlen),
        .m_axi_arsize(m_axi_arsize),
        .m_axi_arburst(m_axi_arburst),
        .m_axi_arlock(m_axi_arlock),
        .m_axi_arcache(m_axi_arcache),
        .m_axi_arprot(m_axi_arprot),
        .m_axi_arqos(m_axi_arqos),
        .m_axi_arregion(m_axi_arregion),
        .m_axi_aruser(m_axi_aruser),
        .m_axi_arvalid(m_axi_arvalid),
        .m_axi_arready(m_axi_arready),
        .m_axi_rid(m_axi_rid),
        .m_axi_rdata(m_axi_rdata),
        .m_axi_rresp(m_axi_rresp),
        .m_axi_rlast(m_axi_rlast),
        .m_axi_ruser(m_axi_ruser),
        .m_axi_rvalid(m_axi_rvalid),
        .m_axi_rready(m_axi_rready),
        .commit_valid(commit_valid),
        .retire_valid(retire_valid),
        .commit_rob_tag(commit_rob_tag),
        .commit_pc(commit_pc),
        .commit_inst(commit_inst),
        .commit_arch_rd(commit_arch_rd),
        .commit_phys_rd(commit_phys_rd),
        .commit_write_rd(commit_write_rd),
        .csr_mstatus(csr_mstatus),
        .csr_mie(csr_mie),
        .csr_mip(csr_mip),
        .csr_mtvec(csr_mtvec),
        .csr_mepc(csr_mepc),
        .csr_mcause(csr_mcause),
        .csr_mtval(csr_mtval),
        .free_count(free_count),
        .rob_full(rob_full),
        .iq_full(iq_full),
        .lsq_full(lsq_full),
        .recovery_busy(recovery_busy),
        .pc_err(pc_err)
    );

    assign m_axi_arready = !read_active && !m_axi_rvalid;
    assign m_axi_awready =
        !write_active && !write_response_pending && !m_axi_bvalid;
    assign m_axi_wready = write_active;

    always #5 ACLK = ~ACLK;

    always @(posedge ACLK or negedge ARESETn) begin
        if (!ARESETn) begin
            read_active <= 1'b0;
            read_addr <= '0;
            read_len <= '0;
            read_beat <= '0;
            read_wait <= 0;
            m_axi_rid <= '0;
            m_axi_rdata <= '0;
            m_axi_rresp <= 2'b00;
            m_axi_rlast <= 1'b0;
            m_axi_ruser <= '0;
            m_axi_rvalid <= 1'b0;
        end
        else begin
            if (m_axi_arvalid && m_axi_arready) begin
                read_active <= 1'b1;
                read_addr <= m_axi_araddr;
                read_len <= m_axi_arlen;
                read_beat <= '0;
                read_wait <= READ_LATENCY;
                m_axi_rid <= m_axi_arid;
            end

            if (read_active && !m_axi_rvalid) begin
                if (read_wait > 0) begin
                    read_wait <= read_wait - 1;
                end
                else begin
                    m_axi_rdata <= read_axi_beat(
                        read_addr + read_beat * AXI_STRB_WIDTH);
                    m_axi_rresp <= 2'b00;
                    m_axi_rlast <= (read_beat == read_len);
                    m_axi_rvalid <= 1'b1;
                end
            end

            if (m_axi_rvalid && m_axi_rready) begin
                m_axi_rvalid <= 1'b0;
                if (m_axi_rlast) begin
                    read_active <= 1'b0;
                    m_axi_rlast <= 1'b0;
                end
                else begin
                    read_beat <= read_beat + 1'b1;
                end
            end
        end
    end

    always @(posedge ACLK or negedge ARESETn) begin
        if (!ARESETn) begin
            write_active <= 1'b0;
            write_response_pending <= 1'b0;
            write_addr <= '0;
            write_len <= '0;
            write_beat <= '0;
            write_id <= '0;
            write_wait <= 0;
            m_axi_bid <= '0;
            m_axi_bresp <= 2'b00;
            m_axi_buser <= '0;
            m_axi_bvalid <= 1'b0;
        end
        else begin
            if (m_axi_awvalid && m_axi_awready) begin
                write_active <= 1'b1;
                write_addr <= m_axi_awaddr;
                write_len <= m_axi_awlen;
                write_beat <= '0;
                write_id <= m_axi_awid;
            end

            if (m_axi_wvalid && m_axi_wready) begin
                for (int byte_idx = 0;
                     byte_idx < AXI_STRB_WIDTH;
                     byte_idx++) begin
                    if (m_axi_wstrb[byte_idx] &&
                        ((write_addr +
                          write_beat * AXI_STRB_WIDTH +
                          byte_idx) < MEM_BYTES)) begin
                        memory[
                            write_addr +
                            write_beat * AXI_STRB_WIDTH +
                            byte_idx
                        ] <= m_axi_wdata[byte_idx * 8 +: 8];
                    end
                end

                if (m_axi_wlast) begin
                    write_active <= 1'b0;
                    write_response_pending <= 1'b1;
                    write_wait <= WRITE_RESP_LATENCY;
                    m_axi_bid <= write_id;
                    m_axi_bresp <= 2'b00;
                end
                else begin
                    write_beat <= write_beat + 1'b1;
                end
            end

            if (write_response_pending) begin
                if (write_wait > 0) begin
                    write_wait <= write_wait - 1;
                end
                else begin
                    write_response_pending <= 1'b0;
                    m_axi_bvalid <= 1'b1;
                end
            end

            if (m_axi_bvalid && m_axi_bready)
                m_axi_bvalid <= 1'b0;
        end
    end

    always @(posedge ACLK or negedge ARESETn) begin
        integer tag;
        integer retire_latency;
        integer wb_latency;
        if (!ARESETn) begin
            cycle_count = 0;
            retired_count = 0;
            error_count = 0;
            total_retire_latency = 0;
            total_complete_latency = 0;
            complete_samples = 0;
            min_retire_latency = MAX_CYCLES;
            max_retire_latency = 0;

            perf_active_cycles = 0;
            fetch_request_valid_cycles = 0;
            fetch_request_fire_cycles = 0;
            fetch_response_fire_cycles = 0;
            frontend_packet_valid_cycles = 0;
            frontend_packet_fire_cycles = 0;
            frontend_empty_cycles = 0;
            dispatch_valid_cycles = 0;
            dispatch_fire_cycles = 0;
            dispatch_backpressure_cycles = 0;
            rob_full_stall_cycles = 0;
            iq_full_stall_cycles = 0;
            lsq_full_stall_cycles = 0;
            recovery_stall_cycles = 0;
            rob_head_incomplete_cycles = 0;
            store_commit_wait_cycles = 0;
            integer_issue_cycles = 0;
            memory_issue_cycles = 0;
            wb_contention_cycles = 0;
            lsu_load_issue_cycles = 0;
            lsu_store_issue_cycles = 0;
            lsu_full_forward_cycles = 0;
            lsu_partial_forward_cycles = 0;
            lsu_nonalias_bypass_cycles = 0;
            lsu_lq_full_stall_cycles = 0;
            lsu_sb_full_stall_cycles = 0;
            lsu_mem_req_stall_cycles = 0;
            lsu_mem_resp_wait_cycles = 0;
            lsu_lq_occupancy_sum = 0;
            lsu_sb_occupancy_sum = 0;
            lsu_cq_occupancy_sum = 0;
            lsu_lq_occupancy_max = 0;
            lsu_sb_occupancy_max = 0;
            lsu_cq_occupancy_max = 0;
            frontend_meta_occupancy_sum = 0;
            frontend_meta_occupancy_max = 0;
            frontend_meta_full_cycles = 0;
            fetch_packet_occupancy_sum = 0;
            fetch_packet_occupancy_max = 0;
            fetch_packet_full_cycles = 0;
            icache_hit_response_cycles = 0;
            icache_miss_response_cycles = 0;
            dcache_mshr_occupancy_sum = 0;
            dcache_mshr_occupancy_max = 0;
            dcache_mshr_full_cycles = 0;
            dcache_request_accept_cycles = 0;
            dcache_lower_request_cycles = 0;
            dcache_response_cycles = 0;
            program_done = 1'b0;

            first_dispatch_cycle = -1;
            long_first_dispatch_cycle = -1;
            long_last_retire_cycle = -1;
            long_retired_count = 0;
            last_retire_cycle = -1;
            inorder_cycles = INORDER_PIPELINE_FILL;
            inorder_load_use_stalls = 0;
            inorder_control_stalls = 0;
            inorder_csr_stalls = 0;
            previous_retired_inst = '0;
            previous_retired_valid = 1'b0;

            for (int i = 0; i < ROB_ENTRIES; i++) begin
                dispatch_cycle[i] = -1;
                complete_cycle[i] = -1;
                branch_taken_by_tag[i] = 1'b0;
            end
            for (int i = 0; i < PHYS_REGS; i++)
                phys_scoreboard[i] = '0;
            for (int i = 0; i < ARCH_REGS; i++)
                arch_scoreboard[i] = '0;
        end
        else begin
            cycle_count = cycle_count + 1;

            if (fetch_enable && !program_done) begin
                perf_active_cycles = perf_active_cycles + 1;

                if (dut.u_frontend.ic_fetch_valid)
                    fetch_request_valid_cycles =
                        fetch_request_valid_cycles + 1;
                if (dut.u_frontend.ic_fetch_valid &&
                    dut.u_frontend.ic_fetch_ready)
                    fetch_request_fire_cycles =
                        fetch_request_fire_cycles + 1;
                if (dut.u_frontend.ic_resp_valid &&
                    dut.u_frontend.ic_resp_ready)
                    fetch_response_fire_cycles =
                        fetch_response_fire_cycles + 1;
                if (dut.if_id_valid)
                    frontend_packet_valid_cycles =
                        frontend_packet_valid_cycles + 1;
                if (dut.if_id_valid && dut.if_id_ready)
                    frontend_packet_fire_cycles =
                        frontend_packet_fire_cycles + 1;
                if (!dut.if_id_valid)
                    frontend_empty_cycles = frontend_empty_cycles + 1;

                if (dut.dispatch_valid)
                    dispatch_valid_cycles = dispatch_valid_cycles + 1;
                if (dut.u_backend.u_dispatch.dispatch_fire)
                    dispatch_fire_cycles = dispatch_fire_cycles + 1;
                if (dut.dispatch_valid && !dut.dispatch_ready)
                    dispatch_backpressure_cycles =
                        dispatch_backpressure_cycles + 1;
                if (rob_full)
                    rob_full_stall_cycles = rob_full_stall_cycles + 1;
                if (iq_full)
                    iq_full_stall_cycles = iq_full_stall_cycles + 1;
                if (lsq_full)
                    lsq_full_stall_cycles = lsq_full_stall_cycles + 1;
                if (recovery_busy)
                    recovery_stall_cycles = recovery_stall_cycles + 1;
                if (!dut.u_backend.rob_empty && !commit_valid)
                    rob_head_incomplete_cycles =
                        rob_head_incomplete_cycles + 1;
                if (dut.u_backend.commit_store_valid &&
                    !dut.u_backend.commit_store_ready)
                    store_commit_wait_cycles =
                        store_commit_wait_cycles + 1;

                if (dut.u_backend.int_issue_valid &&
                    dut.u_backend.int_issue_ready)
                    integer_issue_cycles = integer_issue_cycles + 1;
                if (dut.u_backend.ls_issue_valid &&
                    dut.u_backend.ls_issue_ready)
                    memory_issue_cycles = memory_issue_cycles + 1;
                if (dut.u_backend.alu_wb_valid &&
                    dut.u_backend.lsu_wb_valid)
                    wb_contention_cycles = wb_contention_cycles + 1;

                if (dut.u_backend.u_lsu.issue_fire &&
                    dut.u_backend.u_lsu.issue_is_load)
                    lsu_load_issue_cycles = lsu_load_issue_cycles + 1;
                if (dut.u_backend.u_lsu.issue_fire &&
                    dut.u_backend.u_lsu.issue_is_store)
                    lsu_store_issue_cycles = lsu_store_issue_cycles + 1;
                if (dut.u_backend.u_lsu.issue_fire &&
                    dut.u_backend.u_lsu.issue_is_load &&
                    dut.u_backend.u_lsu.load_fully_forwarded)
                    lsu_full_forward_cycles =
                        lsu_full_forward_cycles + 1;
                if (dut.u_backend.u_lsu.load_enqueue_fire &&
                    (dut.u_backend.u_lsu.load_forward_mask != 0))
                    lsu_partial_forward_cycles =
                        lsu_partial_forward_cycles + 1;
                if (dut.u_backend.u_lsu.load_enqueue_fire &&
                    (dut.u_backend.u_lsu.load_forward_mask == 0))
                    lsu_nonalias_bypass_cycles =
                        lsu_nonalias_bypass_cycles + 1;
                if (dut.u_backend.ls_issue_valid &&
                    dut.u_backend.ls_issue_is_load &&
                    dut.u_backend.u_lsu.lq_full)
                    lsu_lq_full_stall_cycles =
                        lsu_lq_full_stall_cycles + 1;
                if (dut.u_backend.ls_issue_valid &&
                    dut.u_backend.ls_issue_is_store &&
                    dut.u_backend.u_lsu.sb_full)
                    lsu_sb_full_stall_cycles =
                        lsu_sb_full_stall_cycles + 1;
                if (dut.backend_mem_req_valid &&
                    !dut.backend_mem_req_ready)
                    lsu_mem_req_stall_cycles =
                        lsu_mem_req_stall_cycles + 1;
                if ((dut.u_data_cache.mshr_count != 0) &&
                    !dut.backend_mem_resp_valid)
                    lsu_mem_resp_wait_cycles =
                        lsu_mem_resp_wait_cycles + 1;

                lsu_lq_occupancy_sum = lsu_lq_occupancy_sum +
                    dut.u_backend.u_lsu.lq_count;
                lsu_sb_occupancy_sum = lsu_sb_occupancy_sum +
                    dut.u_backend.u_lsu.sb_count;
                lsu_cq_occupancy_sum = lsu_cq_occupancy_sum +
                    dut.u_backend.u_lsu.cq_count;
                if (dut.u_backend.u_lsu.lq_count >
                    lsu_lq_occupancy_max)
                    lsu_lq_occupancy_max =
                        dut.u_backend.u_lsu.lq_count;
                if (dut.u_backend.u_lsu.sb_count >
                    lsu_sb_occupancy_max)
                    lsu_sb_occupancy_max =
                        dut.u_backend.u_lsu.sb_count;
                if (dut.u_backend.u_lsu.cq_count >
                    lsu_cq_occupancy_max)
                    lsu_cq_occupancy_max =
                        dut.u_backend.u_lsu.cq_count;

                frontend_meta_occupancy_sum =
                    frontend_meta_occupancy_sum +
                    dut.u_frontend.meta_count;
                if (dut.u_frontend.meta_count >
                    frontend_meta_occupancy_max)
                    frontend_meta_occupancy_max =
                        dut.u_frontend.meta_count;
                if (dut.u_frontend.meta_full)
                    frontend_meta_full_cycles =
                        frontend_meta_full_cycles + 1;
                fetch_packet_occupancy_sum =
                    fetch_packet_occupancy_sum +
                    dut.u_frontend.packet_count;
                if (dut.u_frontend.packet_count >
                    fetch_packet_occupancy_max)
                    fetch_packet_occupancy_max =
                        dut.u_frontend.packet_count;
                if (dut.u_frontend.packet_full)
                    fetch_packet_full_cycles =
                        fetch_packet_full_cycles + 1;
                if (dut.u_frontend.ic_resp_valid &&
                    dut.u_frontend.ic_resp_ready &&
                    dut.u_frontend.ic_resp_hit)
                    icache_hit_response_cycles =
                        icache_hit_response_cycles + 1;
                if (dut.u_frontend.ic_resp_valid &&
                    dut.u_frontend.ic_resp_ready &&
                    !dut.u_frontend.ic_resp_hit)
                    icache_miss_response_cycles =
                        icache_miss_response_cycles + 1;

                dcache_mshr_occupancy_sum =
                    dcache_mshr_occupancy_sum +
                    dut.u_data_cache.mshr_count;
                if (dut.u_data_cache.mshr_count >
                    dcache_mshr_occupancy_max)
                    dcache_mshr_occupancy_max =
                        dut.u_data_cache.mshr_count;
                if (!dut.backend_mem_req_ready)
                    dcache_mshr_full_cycles =
                        dcache_mshr_full_cycles + 1;
                if (dut.backend_mem_req_valid &&
                    dut.backend_mem_req_ready)
                    dcache_request_accept_cycles =
                        dcache_request_accept_cycles + 1;
                if (dut.d_req_valid && dut.d_req_ready)
                    dcache_lower_request_cycles =
                        dcache_lower_request_cycles + 1;
                if (dut.backend_mem_resp_valid &&
                    dut.backend_mem_resp_ready)
                    dcache_response_cycles =
                        dcache_response_cycles + 1;
            end

            if (dut.u_backend.u_dispatch.dispatch_fire) begin
                tag = dut.u_backend.u_dispatch.rob_alloc_tag;
                dispatch_cycle[tag] = cycle_count;
                complete_cycle[tag] = -1;
                branch_taken_by_tag[tag] = 1'b0;
                if (first_dispatch_cycle < 0)
                    first_dispatch_cycle = cycle_count;
                if ((dut.dispatch_pc == long_loop_start_pc) &&
                    (long_first_dispatch_cycle < 0))
                    long_first_dispatch_cycle = cycle_count;
                log_line($sformatf(
                    "[DISPATCH] cycle=%0d tag=%0d pc=%08x inst=%08x %-7s",
                    cycle_count, tag, dut.dispatch_pc,
                    dut.dispatch_inst, mnemonic(dut.dispatch_inst)));
            end

            if (dut.u_backend.arb_wb_valid &&
                dut.u_backend.arb_wb_ready) begin
                tag = dut.u_backend.arb_wb_rob_tag;
                complete_cycle[tag] = cycle_count;
                branch_taken_by_tag[tag] =
                    dut.u_backend.arb_wb_branch_taken;
                if (dispatch_cycle[tag] >= 0) begin
                    wb_latency = cycle_count - dispatch_cycle[tag] + 1;
                    total_complete_latency =
                        total_complete_latency + wb_latency;
                    complete_samples = complete_samples + 1;
                end
                log_line($sformatf(
                    "[COMPLETE] cycle=%0d tag=%0d data=%08x exception=%0b",
                    cycle_count, tag, dut.u_backend.arb_wb_data,
                    dut.u_backend.arb_wb_exception));
            end

            if (dut.writeback_valid)
                phys_scoreboard[dut.writeback_phys_rd] =
                    dut.writeback_data;

            if (retire_valid && !program_done) begin
                retired_count = retired_count + 1;
                tag = commit_rob_tag;

                if (commit_write_rd)
                    arch_scoreboard[commit_arch_rd] =
                        phys_scoreboard[commit_phys_rd];

                if (dispatch_cycle[tag] >= 0)
                    retire_latency =
                        cycle_count - dispatch_cycle[tag] + 1;
                else
                    retire_latency = 0;

                total_retire_latency =
                    total_retire_latency + retire_latency;
                if (retire_latency < min_retire_latency)
                    min_retire_latency = retire_latency;
                if (retire_latency > max_retire_latency)
                    max_retire_latency = retire_latency;

                last_retire_cycle = cycle_count;
                if ((commit_pc >= long_loop_start_pc) &&
                    (commit_pc < long_loop_end_pc)) begin
                    long_retired_count = long_retired_count + 1;
                    long_last_retire_cycle = cycle_count;
                end
                inorder_cycles = inorder_cycles + 1;

                if (previous_retired_valid &&
                    baseline_load_use_hazard(
                        previous_retired_inst,
                        commit_inst)) begin
                    inorder_cycles =
                        inorder_cycles +
                        INORDER_LOAD_USE_PENALTY;
                    inorder_load_use_stalls =
                        inorder_load_use_stalls +
                        INORDER_LOAD_USE_PENALTY;
                    log_line($sformatf(
                        "[BASELINE][STALL] load-use pc=%08x penalty=%0d",
                        commit_pc,
                        INORDER_LOAD_USE_PENALTY));
                end

                if (baseline_is_branch(commit_inst) &&
                    branch_taken_by_tag[tag]) begin
                    inorder_cycles =
                        inorder_cycles +
                        INORDER_BRANCH_PENALTY;
                    inorder_control_stalls =
                        inorder_control_stalls +
                        INORDER_BRANCH_PENALTY;
                    log_line($sformatf(
                        "[BASELINE][STALL] taken branch pc=%08x penalty=%0d",
                        commit_pc,
                        INORDER_BRANCH_PENALTY));
                end

                if (baseline_is_jump(commit_inst)) begin
                    inorder_cycles =
                        inorder_cycles +
                        INORDER_JUMP_PENALTY;
                    inorder_control_stalls =
                        inorder_control_stalls +
                        INORDER_JUMP_PENALTY;
                    log_line($sformatf(
                        "[BASELINE][STALL] jump pc=%08x penalty=%0d",
                        commit_pc,
                        INORDER_JUMP_PENALTY));
                end

                if (baseline_is_csr(commit_inst)) begin
                    inorder_cycles =
                        inorder_cycles +
                        INORDER_CSR_PENALTY;
                    inorder_csr_stalls =
                        inorder_csr_stalls +
                        INORDER_CSR_PENALTY;
                    log_line($sformatf(
                        "[BASELINE][STALL] CSR pc=%08x penalty=%0d",
                        commit_pc,
                        INORDER_CSR_PENALTY));
                end

                previous_retired_inst = commit_inst;
                previous_retired_valid = 1'b1;

                log_line($sformatf(
                    "[COMMIT] cycle=%0d tag=%0d pc=%08x inst=%08x %-7s rd=x%0d pdst=p%0d value=%08x dispatch_to_wb=%0d dispatch_to_commit=%0d",
                    cycle_count, tag, commit_pc, commit_inst,
                    mnemonic(commit_inst), commit_arch_rd,
                    commit_phys_rd,
                    commit_write_rd ?
                        phys_scoreboard[commit_phys_rd] : 32'b0,
                    (complete_cycle[tag] >= 0 &&
                     dispatch_cycle[tag] >= 0) ?
                        complete_cycle[tag] -
                        dispatch_cycle[tag] + 1 : 0,
                    retire_latency));

                if ((commit_pc == taken_wrong_path_pc) ||
                    (commit_pc == jal_wrong_path_pc)) begin
                    error_count = error_count + 1;
                    log_line($sformatf(
                        "[CHECK][FAIL] wrong-path instruction retired at pc=%08x",
                        commit_pc));
                end

                if (commit_pc == done_store_pc)
                    program_done = 1'b1;
            end
        end
    end

    initial begin
        ACLK = 1'b0;
        ARESETn = 1'b0;
        fetch_enable = 1'b0;
        irq_software = 1'b0;
        irq_timer = 1'b0;
        irq_external = 1'b0;
        start_cycle = 0;
        log_fd = $fopen("tb_ooo_core.log", "w");

        for (int i = 0; i < MEM_BYTES; i++)
            memory[i] = '0;
        load_program();

        log_line("[TEST] RV32I program loaded at 0x00007000");
        repeat (8) @(posedge ACLK);
        @(negedge ACLK);
        ARESETn = 1'b1;
        repeat (2) @(posedge ACLK);
        @(negedge ACLK);
        fetch_enable = 1'b1;
        start_cycle = cycle_count + 1;
        log_line("[TEST] CPU execution started");

        fork
            begin : wait_for_completion
                wait (program_done);
                while (read_word(done_addr) !== 32'd1)
                    @(posedge ACLK);
                #1;
                report_results();
                if (log_fd != 0)
                    $fclose(log_fd);
                if (error_count == 0)
                    $finish;
                else
                    $fatal(1, "Test failed with %0d errors",
                           error_count);
            end

            begin : timeout_guard
                repeat (MAX_CYCLES) @(posedge ACLK);
                log_line($sformatf(
                    "[TEST][TIMEOUT] no completion after %0d cycles",
                    MAX_CYCLES));
                if (log_fd != 0)
                    $fclose(log_fd);
                $fatal(1, "Simulation timeout");
            end
        join_any
        disable fork;
    end
endmodule
