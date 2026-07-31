module free_list #(
    parameter int unsigned ARCH_REGS = 32,
    parameter int unsigned PHYS_REGS = 64,

    localparam int unsigned PHYS_TAG_WIDTH = (PHYS_REGS <= 1) ? 1 : $clog2(PHYS_REGS),
    localparam int unsigned COUNT_WIDTH = (PHYS_REGS <= 1) ? 1 : $clog2(PHYS_REGS + 1)
) (
    input  logic                        ACLK,
    input  logic                        ARESETn,

    input  logic                        alloc_req,
    output logic                        alloc_ready,
    output logic [PHYS_TAG_WIDTH-1:0]   alloc_tag,

    input  logic                        free_valid,
    input  logic [PHYS_TAG_WIDTH-1:0]   free_tag,

    output logic [COUNT_WIDTH-1:0]      free_count
);

    logic [PHYS_TAG_WIDTH-1:0] free_queue [0:PHYS_REGS-1];
    logic [PHYS_TAG_WIDTH-1:0] head_ptr;
    logic [PHYS_TAG_WIDTH-1:0] tail_ptr;
    logic alloc_fire;
    logic free_fire;

    assign alloc_ready = (free_count != '0);
    assign alloc_tag = free_queue[head_ptr];
    assign alloc_fire = alloc_req && alloc_ready;
    assign free_fire = free_valid && (free_tag != '0);

    always @(posedge ACLK or negedge ARESETn) begin
        if (!ARESETn) begin
            for (int i = 0; i < PHYS_REGS; i++) begin
                if (i < (PHYS_REGS - ARCH_REGS)) begin
                    free_queue[i] <= ARCH_REGS + i;
                end
                else begin
                    free_queue[i] <= '0;
                end
            end
            head_ptr <= '0;
            tail_ptr <= PHYS_REGS - ARCH_REGS;
            free_count <= PHYS_REGS - ARCH_REGS;
        end
        else begin
            if (alloc_fire) begin
                if (head_ptr == PHYS_REGS-1) begin
                    head_ptr <= '0;
                end
                else begin
                    head_ptr <= head_ptr + 1'b1;
                end
            end

            if (free_fire) begin
                free_queue[tail_ptr] <= free_tag;
                if (tail_ptr == PHYS_REGS-1) begin
                    tail_ptr <= '0;
                end
                else begin
                    tail_ptr <= tail_ptr + 1'b1;
                end
            end

            unique case ({alloc_fire, free_fire})
                2'b10: free_count <= free_count - 1'b1;
                2'b01: free_count <= free_count + 1'b1;
                default: free_count <= free_count;
            endcase
        end
    end

endmodule
