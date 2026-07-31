module id_dispatch #(
    parameter int unsigned WIDTH_INST = 32,
    parameter int unsigned ADDR_WIDTH = 32,
    parameter int unsigned ARCH_REGS = 32,
    parameter int unsigned PHYS_REGS = 64,

    localparam int unsigned ARCH_TAG_WIDTH = (ARCH_REGS <= 1) ? 1 : $clog2(ARCH_REGS),
    localparam int unsigned PHYS_TAG_WIDTH = (PHYS_REGS <= 1) ? 1 : $clog2(PHYS_REGS),
    localparam int unsigned FREE_COUNT_WIDTH = (PHYS_REGS <= 1) ? 1 : $clog2(PHYS_REGS + 1)
) (
    input  logic                        ACLK,
    input  logic                        ARESETn,

    // Compatible with if_id_frontend outputs
    input  logic                        if_id_valid,
    output logic                        if_id_ready,
    input  logic [ADDR_WIDTH-1:0]       if_id_pc,
    input  logic [WIDTH_INST-1:0]       if_id_inst,
    input  logic                        if_id_pred_taken,
    input  logic [ADDR_WIDTH-1:0]       if_id_pred_target,
    input  logic                        if_id_cache_hit,
    input  logic [1:0]                  if_id_status,

    // Dispatch packet to ROB/issue queue stage
    output logic                        dispatch_valid,
    input  logic                        dispatch_ready,
    output logic [ADDR_WIDTH-1:0]       dispatch_pc,
    output logic [WIDTH_INST-1:0]       dispatch_inst,
    output logic [6:0]                  dispatch_opcode,
    output logic [2:0]                  dispatch_funct3,
    output logic [6:0]                  dispatch_funct7,
    output logic [31:0]                 dispatch_imm,
    output logic [ARCH_TAG_WIDTH-1:0]   dispatch_arch_rs1,
    output logic [ARCH_TAG_WIDTH-1:0]   dispatch_arch_rs2,
    output logic [ARCH_TAG_WIDTH-1:0]   dispatch_arch_rd,
    output logic [PHYS_TAG_WIDTH-1:0]   dispatch_phys_rs1,
    output logic [PHYS_TAG_WIDTH-1:0]   dispatch_phys_rs2,
    output logic [PHYS_TAG_WIDTH-1:0]   dispatch_phys_rd,
    output logic [PHYS_TAG_WIDTH-1:0]   dispatch_old_phys_rd,
    output logic                        dispatch_rs1_ready,
    output logic                        dispatch_rs2_ready,
    output logic                        dispatch_use_rs1,
    output logic                        dispatch_use_rs2,
    output logic                        dispatch_write_rd,
    output logic                        dispatch_is_alu,
    output logic                        dispatch_is_load,
    output logic                        dispatch_is_store,
    output logic                        dispatch_is_branch,
    output logic                        dispatch_is_jal,
    output logic                        dispatch_is_jalr,
    output logic                        dispatch_is_lui,
    output logic                        dispatch_is_auipc,
    output logic                        dispatch_is_system,
    output logic                        dispatch_pred_taken,
    output logic [ADDR_WIDTH-1:0]       dispatch_pred_target,
    output logic                        dispatch_cache_hit,
    output logic [1:0]                  dispatch_if_status,
    output logic                        dispatch_illegal_inst,

    // Physical register lifecycle interfaces
    input  logic                        commit_free_valid,
    input  logic [PHYS_TAG_WIDTH-1:0]   commit_free_tag,
    input  logic                        writeback_valid,
    input  logic [PHYS_TAG_WIDTH-1:0]   writeback_phys_rd,

    // Optional map recovery interface for flush/mispredict repair
    input  logic                        recover_map_valid,
    input  logic [ARCH_TAG_WIDTH-1:0]   recover_arch_rd,
    input  logic [PHYS_TAG_WIDTH-1:0]   recover_phys_rd,
    input  logic                        recover_free_valid,
    input  logic [PHYS_TAG_WIDTH-1:0]   recover_free_tag,
    input  logic                        recover_flush,
    input  logic                        recovery_busy,

    output logic [FREE_COUNT_WIDTH-1:0] free_count
);

    logic [6:0] dec_opcode;
    logic [2:0] dec_funct3;
    logic [6:0] dec_funct7;
    logic [ARCH_TAG_WIDTH-1:0] dec_arch_rs1;
    logic [ARCH_TAG_WIDTH-1:0] dec_arch_rs2;
    logic [ARCH_TAG_WIDTH-1:0] dec_arch_rd;
    logic [ADDR_WIDTH-1:0] dec_pc;
    logic [WIDTH_INST-1:0] dec_inst;
    logic [31:0] dec_imm;
    logic dec_use_rs1;
    logic dec_use_rs2;
    logic dec_write_rd;
    logic dec_is_alu;
    logic dec_is_load;
    logic dec_is_store;
    logic dec_is_branch;
    logic dec_is_jal;
    logic dec_is_jalr;
    logic dec_is_lui;
    logic dec_is_auipc;
    logic dec_is_system;
    logic dec_pred_taken;
    logic [ADDR_WIDTH-1:0] dec_pred_target;
    logic dec_illegal_inst;

    logic [PHYS_TAG_WIDTH-1:0] map_phys_rs1;
    logic [PHYS_TAG_WIDTH-1:0] map_phys_rs2;
    logic [PHYS_TAG_WIDTH-1:0] map_old_phys_rd;

    logic free_alloc_req;
    logic free_alloc_ready;
    logic [PHYS_TAG_WIDTH-1:0] free_alloc_tag;
    logic free_return_valid;
    logic [PHYS_TAG_WIDTH-1:0] free_return_tag;

    logic rename_fire;
    logic need_phys_rd;
    logic [PHYS_TAG_WIDTH-1:0] dispatch_phys_rd_next;

    logic busy_rs1_ready;
    logic busy_rs2_ready;

    assign need_phys_rd = dec_write_rd && (dec_arch_rd != '0);
    assign free_alloc_req = if_id_valid && if_id_ready && need_phys_rd;
    assign rename_fire = if_id_valid && if_id_ready && !recovery_busy && !recover_flush;
    assign if_id_ready = !recovery_busy && !recover_flush &&
                         dispatch_ready && (!need_phys_rd || free_alloc_ready);
    assign dispatch_phys_rd_next = need_phys_rd ? free_alloc_tag : '0;
    assign free_return_valid = recover_free_valid || commit_free_valid;
    assign free_return_tag = recover_free_valid ? recover_free_tag : commit_free_tag;

    decoder #(
        .WIDTH_INST(WIDTH_INST),
        .ADDR_WIDTH(ADDR_WIDTH),
        .ARCH_REGS(ARCH_REGS)
    ) u_decoder (
        .decode_valid(if_id_valid),
        .decode_pc(if_id_pc),
        .decode_inst(if_id_inst),
        .decode_pred_taken(if_id_pred_taken),
        .decode_pred_target(if_id_pred_target),
        .opcode(dec_opcode),
        .funct3(dec_funct3),
        .funct7(dec_funct7),
        .arch_rs1(dec_arch_rs1),
        .arch_rs2(dec_arch_rs2),
        .arch_rd(dec_arch_rd),
        .pc(dec_pc),
        .inst(dec_inst),
        .imm(dec_imm),
        .use_rs1(dec_use_rs1),
        .use_rs2(dec_use_rs2),
        .write_rd(dec_write_rd),
        .is_alu(dec_is_alu),
        .is_load(dec_is_load),
        .is_store(dec_is_store),
        .is_branch(dec_is_branch),
        .is_jal(dec_is_jal),
        .is_jalr(dec_is_jalr),
        .is_lui(dec_is_lui),
        .is_auipc(dec_is_auipc),
        .is_system(dec_is_system),
        .pred_taken(dec_pred_taken),
        .pred_target(dec_pred_target),
        .illegal_inst(dec_illegal_inst)
    );

    rename_map_table #(
        .ARCH_REGS(ARCH_REGS),
        .PHYS_REGS(PHYS_REGS)
    ) u_rename_map_table (
        .ACLK(ACLK),
        .ARESETn(ARESETn),
        .arch_rs1(dec_arch_rs1),
        .arch_rs2(dec_arch_rs2),
        .arch_rd(dec_arch_rd),
        .use_rs1(dec_use_rs1),
        .use_rs2(dec_use_rs2),
        .write_rd(dec_write_rd),
        .phys_rs1(map_phys_rs1),
        .phys_rs2(map_phys_rs2),
        .old_phys_rd(map_old_phys_rd),
        .rename_fire(rename_fire),
        .new_phys_rd(dispatch_phys_rd_next),
        .recover_valid(recover_map_valid),
        .recover_arch_rd(recover_arch_rd),
        .recover_phys_rd(recover_phys_rd)
    );

    free_list #(
        .ARCH_REGS(ARCH_REGS),
        .PHYS_REGS(PHYS_REGS)
    ) u_free_list (
        .ACLK(ACLK),
        .ARESETn(ARESETn),
        .alloc_req(free_alloc_req),
        .alloc_ready(free_alloc_ready),
        .alloc_tag(free_alloc_tag),
        .free_valid(free_return_valid),
        .free_tag(free_return_tag),
        .free_count(free_count)
    );

    busy_table #(
        .ARCH_REGS(ARCH_REGS),
        .PHYS_REGS(PHYS_REGS)
    ) u_busy_table (
        .ACLK(ACLK),
        .ARESETn(ARESETn),
        .phys_rs1(map_phys_rs1),
        .phys_rs2(map_phys_rs2),
        .use_rs1(dec_use_rs1),
        .use_rs2(dec_use_rs2),
        .rs1_ready(busy_rs1_ready),
        .rs2_ready(busy_rs2_ready),
        .set_busy_valid(rename_fire && need_phys_rd),
        .set_busy_tag(dispatch_phys_rd_next),
        .clear_busy_valid(writeback_valid),
        .clear_busy_tag(writeback_phys_rd)
    );

    always @(posedge ACLK or negedge ARESETn) begin
        if (!ARESETn) begin
            dispatch_valid <= 1'b0;
            dispatch_pc <= '0;
            dispatch_inst <= '0;
            dispatch_opcode <= '0;
            dispatch_funct3 <= '0;
            dispatch_funct7 <= '0;
            dispatch_imm <= '0;
            dispatch_arch_rs1 <= '0;
            dispatch_arch_rs2 <= '0;
            dispatch_arch_rd <= '0;
            dispatch_phys_rs1 <= '0;
            dispatch_phys_rs2 <= '0;
            dispatch_phys_rd <= '0;
            dispatch_old_phys_rd <= '0;
            dispatch_rs1_ready <= 1'b0;
            dispatch_rs2_ready <= 1'b0;
            dispatch_use_rs1 <= 1'b0;
            dispatch_use_rs2 <= 1'b0;
            dispatch_write_rd <= 1'b0;
            dispatch_is_alu <= 1'b0;
            dispatch_is_load <= 1'b0;
            dispatch_is_store <= 1'b0;
            dispatch_is_branch <= 1'b0;
            dispatch_is_jal <= 1'b0;
            dispatch_is_jalr <= 1'b0;
            dispatch_is_lui <= 1'b0;
            dispatch_is_auipc <= 1'b0;
            dispatch_is_system <= 1'b0;
            dispatch_pred_taken <= 1'b0;
            dispatch_pred_target <= '0;
            dispatch_cache_hit <= 1'b0;
            dispatch_if_status <= '0;
            dispatch_illegal_inst <= 1'b0;
        end
        else if (recover_flush) begin
            dispatch_valid <= 1'b0;
        end
        else begin
            if (dispatch_valid && dispatch_ready) begin
                dispatch_valid <= 1'b0;
            end

            if (rename_fire) begin
                dispatch_valid <= 1'b1;
                dispatch_pc <= dec_pc;
                dispatch_inst <= dec_inst;
                dispatch_opcode <= dec_opcode;
                dispatch_funct3 <= dec_funct3;
                dispatch_funct7 <= dec_funct7;
                dispatch_imm <= dec_imm;
                dispatch_arch_rs1 <= dec_arch_rs1;
                dispatch_arch_rs2 <= dec_arch_rs2;
                dispatch_arch_rd <= dec_arch_rd;
                dispatch_phys_rs1 <= map_phys_rs1;
                dispatch_phys_rs2 <= map_phys_rs2;
                dispatch_phys_rd <= dispatch_phys_rd_next;
                dispatch_old_phys_rd <= map_old_phys_rd;
                dispatch_rs1_ready <= busy_rs1_ready;
                dispatch_rs2_ready <= busy_rs2_ready;
                dispatch_use_rs1 <= dec_use_rs1;
                dispatch_use_rs2 <= dec_use_rs2;
                dispatch_write_rd <= dec_write_rd;
                dispatch_is_alu <= dec_is_alu;
                dispatch_is_load <= dec_is_load;
                dispatch_is_store <= dec_is_store;
                dispatch_is_branch <= dec_is_branch;
                dispatch_is_jal <= dec_is_jal;
                dispatch_is_jalr <= dec_is_jalr;
                dispatch_is_lui <= dec_is_lui;
                dispatch_is_auipc <= dec_is_auipc;
                dispatch_is_system <= dec_is_system;
                dispatch_pred_taken <= dec_pred_taken;
                dispatch_pred_target <= dec_pred_target;
                dispatch_cache_hit <= if_id_cache_hit;
                dispatch_if_status <= if_id_status;
                dispatch_illegal_inst <= dec_illegal_inst;
            end
        end
    end

endmodule
