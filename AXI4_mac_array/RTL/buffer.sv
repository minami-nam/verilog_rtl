module input_buffer_array #(
    parameter int ARRAY_H_SIZE = 4,
    parameter int ARRAY_K_SIZE = 4,
    parameter int ARRAY_W_SIZE = 4,
    parameter int DATA_WIDTH_IN = 8,
    parameter int AXI_DATA_WIDTH = 64
)(
    input  logic ACLK,
    input  logic ARESETn,

    // Buffer control/status
    input  logic request,
    
    input  logic clear,
    input  logic matrix_select,  // 1'b0: matrix A, 1'b1: matrix B
    output logic a_loaded,
    output logic b_loaded,
    output logic read_error,

    // AXI4 read-data channel
    input  logic [AXI_DATA_WIDTH-1:0] axi_rdata,
    input  logic [1:0]                axi_rresp,
    input  logic                      axi_rlast,
    input  logic                      axi_rvalid,
    output logic                      axi_rready,

    // MAC Array input stream
    output logic                           mac_valid,
    input  logic                           mac_ready,
    output logic signed [DATA_WIDTH_IN-1:0] mac_a_data [0:ARRAY_H_SIZE-1],
    output logic signed [DATA_WIDTH_IN-1:0] mac_b_data [0:ARRAY_W_SIZE-1]
);

    // Storage, AXI unpacking, and row/column vector generation logic.

    localparam int W_WIDTH = (ARRAY_W_SIZE <= 1) ? 1 : $clog2(ARRAY_W_SIZE);
    localparam int H_WIDTH = (ARRAY_H_SIZE <= 1) ? 1 : $clog2(ARRAY_H_SIZE);
    localparam int K_WIDTH = (ARRAY_K_SIZE <= 1) ? 1 : $clog2(ARRAY_K_SIZE);
    localparam int A_ELEMENT_COUNT = ARRAY_H_SIZE * ARRAY_K_SIZE;
    localparam int B_ELEMENT_COUNT = ARRAY_K_SIZE * ARRAY_W_SIZE;
    localparam int MAX_ELEMENT_COUNT =
        (A_ELEMENT_COUNT >= B_ELEMENT_COUNT) ? A_ELEMENT_COUNT : B_ELEMENT_COUNT;
    localparam int ELEMENT_COUNTER_WIDTH =
        (MAX_ELEMENT_COUNT <= 1) ? 1 : $clog2(MAX_ELEMENT_COUNT + 1);

    localparam int INSERT_CELL = AXI_DATA_WIDTH / DATA_WIDTH_IN;

    wire [H_WIDTH-1:0] a_row;
    wire [K_WIDTH-1:0] a_col;
    wire [K_WIDTH-1:0] b_row;
    wire [W_WIDTH-1:0] b_col;

    reg [ELEMENT_COUNTER_WIDTH-1:0] element_counter_reg;
    wire [ELEMENT_COUNTER_WIDTH-1:0] active_element_count;
    reg signed [DATA_WIDTH_IN-1:0] matrix_a_reg
        [0:ARRAY_H_SIZE-1][0:ARRAY_K_SIZE-1];
    reg signed [DATA_WIDTH_IN-1:0] matrix_b_reg
        [0:ARRAY_K_SIZE-1][0:ARRAY_W_SIZE-1];

    integer insert_cell_idx;

    reg [K_WIDTH-1:0] mac_k_counter_reg;
    reg mac_stream_done;
    reg matrix_select_reg;
    reg matrix_done;
    

    assign a_row = element_counter_reg / ARRAY_K_SIZE;
    assign a_col = element_counter_reg % ARRAY_K_SIZE;
    assign b_row = element_counter_reg / ARRAY_W_SIZE;
    assign b_col = element_counter_reg % ARRAY_W_SIZE;
    assign active_element_count = matrix_select_reg ? B_ELEMENT_COUNT : A_ELEMENT_COUNT;
    assign axi_rready = !matrix_done;

    // 시작하기 전 handshake
    always @(posedge ACLK or negedge ARESETn) begin
        if (!ARESETn) begin
            matrix_select_reg <= '0;
        end
        else begin
            if (request) begin
                matrix_select_reg <= matrix_select;
            end
        end
    end 

    wire r_last_fire;
    assign r_last_fire = axi_rvalid && axi_rready && axi_rlast;

    // counter 관련
    always @(posedge ACLK or negedge ARESETn) begin
        if (!ARESETn) begin
            element_counter_reg <= '0;
            matrix_done <= 1'b0;
            a_loaded <= 1'b0;
            b_loaded <= 1'b0;
            read_error <= 1'b0;
        end
        else if (clear) begin
            element_counter_reg <= '0;
            matrix_done <= 1'b0;
            a_loaded <= 1'b0;
            b_loaded <= 1'b0;
            read_error <= 1'b0;
        end
        else if (request) begin
            element_counter_reg <= '0;
            matrix_done <= 1'b0;
            read_error <= 1'b0;

            if (matrix_select)
                b_loaded <= 1'b0;
            else
                a_loaded <= 1'b0;
        end
        else begin
            if (axi_rvalid && axi_rready) begin
                if (axi_rresp[1])
                    read_error <= 1'b1;

                if (element_counter_reg < active_element_count) begin
                    for (insert_cell_idx = 0;
                         insert_cell_idx < INSERT_CELL;
                         insert_cell_idx = insert_cell_idx + 1) begin
                        if ((element_counter_reg + insert_cell_idx) < active_element_count) begin
                            if (!matrix_select_reg) begin
                                matrix_a_reg[(element_counter_reg + insert_cell_idx) / ARRAY_K_SIZE]
                                            [(element_counter_reg + insert_cell_idx) % ARRAY_K_SIZE]
                                    <= axi_rdata[insert_cell_idx*DATA_WIDTH_IN +: DATA_WIDTH_IN];
                            end
                            else begin
                                matrix_b_reg[(element_counter_reg + insert_cell_idx) / ARRAY_W_SIZE]
                                            [(element_counter_reg + insert_cell_idx) % ARRAY_W_SIZE]
                                    <= axi_rdata[insert_cell_idx*DATA_WIDTH_IN +: DATA_WIDTH_IN];
                            end
                        end
                    end

                    if ((element_counter_reg + INSERT_CELL) >= active_element_count) begin
                        element_counter_reg <= active_element_count;
                        matrix_done <= 1'b1;

                        if (matrix_select_reg)
                            b_loaded <= 1'b1;
                        else
                            a_loaded <= 1'b1;
                    end
                    else begin
                        element_counter_reg <= element_counter_reg + INSERT_CELL;
                    end
                end
                else if (element_counter_reg >= active_element_count) begin
                    element_counter_reg <= active_element_count;
                    matrix_done <= 1'b1;

                    if (matrix_select_reg)
                        b_loaded <= 1'b1;
                    else
                        a_loaded <= 1'b1;
                end
            end
        end
    end

    // MAC Array output vector generation.
    assign mac_valid = a_loaded && b_loaded && !mac_stream_done;

    genvar mac_row_idx;
    genvar mac_col_idx;
    generate
        for (mac_row_idx = 0; mac_row_idx < ARRAY_H_SIZE; mac_row_idx++) begin : mac_a_output
            assign mac_a_data[mac_row_idx] = a_loaded
                                               ? matrix_a_reg[mac_row_idx][mac_k_counter_reg]
                                               : '0;
        end

        for (mac_col_idx = 0; mac_col_idx < ARRAY_W_SIZE; mac_col_idx++) begin : mac_b_output
            assign mac_b_data[mac_col_idx] = b_loaded
                                               ? matrix_b_reg[mac_k_counter_reg][mac_col_idx]
                                               : '0;
        end
    endgenerate

    always @(posedge ACLK or negedge ARESETn) begin
        if (!ARESETn) begin
            mac_k_counter_reg <= '0;
            mac_stream_done <= 1'b0;
        end
        else if (clear || request) begin
            mac_k_counter_reg <= '0;
            mac_stream_done <= 1'b0;
        end
        else if (mac_valid && mac_ready) begin
            if (mac_k_counter_reg == ARRAY_K_SIZE-1) begin
                mac_stream_done <= 1'b1;
            end
            else begin
                mac_k_counter_reg <= mac_k_counter_reg + 1'b1;
            end
        end
    end



    //



endmodule


module output_buffer_array #(
    parameter int ARRAY_H_SIZE = 4,
    parameter int ARRAY_W_SIZE = 4,
    parameter int DATA_WIDTH_IN = 8,
    parameter int ACC_WIDTH = 2 * DATA_WIDTH_IN,
    parameter int AXI_DATA_WIDTH = 64,
    parameter int AXI_STRB_WIDTH = AXI_DATA_WIDTH / 8
)(
    input  logic ACLK,
    input  logic ARESETn,

    // Buffer control/status
    input  logic clear,
    input  logic write_start,
    output logic buffer_full,
    output logic write_done,

    // MAC Array output stream
    input  logic                        mac_valid,
    output logic                        mac_ready,
    input  logic                        mac_last,
    input  logic signed [ACC_WIDTH-1:0] mac_data [0:ARRAY_W_SIZE-1],

    // AXI4 write-data channel
    output logic [AXI_DATA_WIDTH-1:0] axi_wdata,
    output logic [AXI_STRB_WIDTH-1:0] axi_wstrb,
    output logic                      axi_wlast,
    output logic                      axi_wvalid,
    input  logic                      axi_wready
);

    // Storage, result packing, and AXI burst generation logic.

    localparam int H_WIDTH = (ARRAY_H_SIZE <= 1) ? 1 : $clog2(ARRAY_H_SIZE);
    localparam int ELEMENT_COUNT = ARRAY_H_SIZE * ARRAY_W_SIZE;
    localparam int ELEMENT_COUNTER_WIDTH =
        (ELEMENT_COUNT <= 1) ? 1 : $clog2(ELEMENT_COUNT + 1);
    localparam int RESULT_BYTE_WIDTH = ACC_WIDTH / 8;
    localparam int OUTPUT_CELL_PER_BEAT = AXI_DATA_WIDTH / ACC_WIDTH;

    reg signed [ACC_WIDTH-1:0] matrix_c_reg
        [0:ARRAY_H_SIZE-1][0:ARRAY_W_SIZE-1];

    reg [H_WIDTH-1:0] mac_row_counter_reg;
    reg [ELEMENT_COUNTER_WIDTH-1:0] axi_element_counter_reg;
    reg write_active;

    integer store_col_idx;
    integer pack_cell_idx;
    integer pack_byte_idx;

    assign mac_ready = !buffer_full && !write_active;
    assign axi_wvalid = write_active;
    assign axi_wlast = axi_wvalid &&
                       ((axi_element_counter_reg + OUTPUT_CELL_PER_BEAT) >= ELEMENT_COUNT);

    always @(*) begin
        axi_wdata = '0;
        axi_wstrb = '0;

        if (write_active) begin
            for (pack_cell_idx = 0;
                 pack_cell_idx < OUTPUT_CELL_PER_BEAT;
                 pack_cell_idx = pack_cell_idx + 1) begin
                if ((axi_element_counter_reg + pack_cell_idx) < ELEMENT_COUNT) begin
                    axi_wdata[pack_cell_idx*ACC_WIDTH +: ACC_WIDTH] =
                        matrix_c_reg[(axi_element_counter_reg + pack_cell_idx) / ARRAY_W_SIZE]
                                    [(axi_element_counter_reg + pack_cell_idx) % ARRAY_W_SIZE];

                    for (pack_byte_idx = 0;
                         pack_byte_idx < RESULT_BYTE_WIDTH;
                         pack_byte_idx = pack_byte_idx + 1) begin
                        axi_wstrb[pack_cell_idx*RESULT_BYTE_WIDTH + pack_byte_idx] = 1'b1;
                    end
                end
            end
        end
    end

    always @(posedge ACLK or negedge ARESETn) begin
        if (!ARESETn) begin
            mac_row_counter_reg <= '0;
            axi_element_counter_reg <= '0;
            buffer_full <= 1'b0;
            write_active <= 1'b0;
            write_done <= 1'b0;
        end
        else if (clear) begin
            mac_row_counter_reg <= '0;
            axi_element_counter_reg <= '0;
            buffer_full <= 1'b0;
            write_active <= 1'b0;
            write_done <= 1'b0;
        end
        else begin
            write_done <= 1'b0;

            if (mac_valid && mac_ready) begin
                for (store_col_idx = 0;
                     store_col_idx < ARRAY_W_SIZE;
                     store_col_idx = store_col_idx + 1) begin
                    matrix_c_reg[mac_row_counter_reg][store_col_idx]
                        <= mac_data[store_col_idx];
                end

                if ((mac_row_counter_reg == ARRAY_H_SIZE-1) && mac_last) begin
                    mac_row_counter_reg <= '0;
                    buffer_full <= 1'b1;
                end
                else begin
                    mac_row_counter_reg <= mac_row_counter_reg + 1'b1;
                end
            end

            if (write_start && buffer_full && !write_active) begin
                axi_element_counter_reg <= '0;
                write_active <= 1'b1;
            end
            else if (axi_wvalid && axi_wready) begin
                if (axi_wlast) begin
                    axi_element_counter_reg <= '0;
                    buffer_full <= 1'b0;
                    write_active <= 1'b0;
                    write_done <= 1'b1;
                end
                else begin
                    axi_element_counter_reg <= axi_element_counter_reg + OUTPUT_CELL_PER_BEAT;
                end
            end
        end
    end


endmodule
