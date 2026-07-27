module mac_array #(
    parameter int ARRAY_H_SIZE = 4,
    parameter int ARRAY_K_SIZE = 4,
    parameter int ARRAY_W_SIZE = 4,
    parameter int DATA_WIDTH_IN = 8
)(
    input  logic ACLK,
    input  logic ARESETn,
    input  logic clear_request,
    output logic clear_done,

    input  logic i_valid,
    output logic i_ready,
    input  logic signed [DATA_WIDTH_IN-1:0] i_a_data [0:ARRAY_H_SIZE-1],
    input  logic signed [DATA_WIDTH_IN-1:0] i_b_data [0:ARRAY_W_SIZE-1],

    output logic o_valid,
    input  logic o_ready,
    output logic o_last,
    output logic signed [2*DATA_WIDTH_IN-1:0] o_data [0:ARRAY_W_SIZE-1]
);
    localparam int K_COUNTER_WIDTH =
        (ARRAY_K_SIZE <= 1) ? 1 : $clog2(ARRAY_K_SIZE);
    localparam int H_COUNTER_WIDTH =
        (ARRAY_H_SIZE <= 1) ? 1 : $clog2(ARRAY_H_SIZE);
    localparam int DRAIN_CYCLES = ARRAY_H_SIZE + ARRAY_W_SIZE - 2;
    localparam int DRAIN_COUNTER_WIDTH =
        (DRAIN_CYCLES <= 1) ? 1 : $clog2(DRAIN_CYCLES);

    typedef enum logic [2:0] {
        IDLE,
        CLEAR,
        LOAD_STREAM,
        DRAIN,
        OUTPUT,
        DONE
    } status_e;

    status_e current_state;

    logic [K_COUNTER_WIDTH-1:0] array_counter;
    logic [DRAIN_COUNTER_WIDTH-1:0] drain_counter;
    logic [H_COUNTER_WIDTH-1:0] output_counter;

    logic pe_en;
    logic clear_acc;

    logic signed [DATA_WIDTH_IN-1:0] a_buffer
        [0:ARRAY_H_SIZE-1][0:ARRAY_K_SIZE-1];
    logic signed [DATA_WIDTH_IN-1:0] b_buffer
        [0:ARRAY_K_SIZE-1][0:ARRAY_W_SIZE-1];

    wire signed [DATA_WIDTH_IN-1:0] a_wire
        [0:ARRAY_W_SIZE][0:ARRAY_H_SIZE-1];
    wire signed [DATA_WIDTH_IN-1:0] b_wire
        [0:ARRAY_W_SIZE-1][0:ARRAY_H_SIZE];
    wire a_valid_wire [0:ARRAY_W_SIZE][0:ARRAY_H_SIZE-1];
    wire b_valid_wire [0:ARRAY_W_SIZE-1][0:ARRAY_H_SIZE];
    wire signed [2*DATA_WIDTH_IN-1:0] acc_wire
        [0:ARRAY_W_SIZE-1][0:ARRAY_H_SIZE-1];
    wire acc_valid_wire [0:ARRAY_W_SIZE-1][0:ARRAY_H_SIZE-1];

    wire load_fire = i_valid && i_ready;
    wire output_fire = o_valid && o_ready;

    always @(*) begin
        pe_en = 1'b0;
        clear_acc = 1'b0;

        case (current_state)
            CLEAR: begin
                clear_acc = 1'b1;
            end
            LOAD_STREAM: begin
                pe_en = load_fire;
            end
            DRAIN: begin
                pe_en = 1'b1;
            end
            default: begin
                pe_en = 1'b0;
                clear_acc = 1'b0;
            end
        endcase
    end

    genvar input_row;
    genvar input_col;
    genvar instantiate_pe_w;
    genvar instantiate_pe_h;
    genvar output_col;

    generate
        // A[row][k] enters from the left, delayed by its row index.
        for (input_row = 0; input_row < ARRAY_H_SIZE; input_row++) begin : a_input_mux
            reg signed [DATA_WIDTH_IN-1:0] a_mux;
            reg a_mux_valid;

            always @(*) begin
                a_mux = '0;
                a_mux_valid = 1'b0;

                case (current_state)
                    LOAD_STREAM: begin
                        if (load_fire && (array_counter >= input_row)) begin
                            a_mux_valid = 1'b1;

                            if (input_row == 0)
                                a_mux = i_a_data[input_row];
                            else
                                a_mux = a_buffer[input_row][array_counter-input_row];
                        end
                    end
                    DRAIN: begin
                        if ((drain_counter < input_row) &&
                            ((ARRAY_K_SIZE + drain_counter) >= input_row)) begin
                            a_mux = a_buffer[input_row]
                                            [ARRAY_K_SIZE+drain_counter-input_row];
                            a_mux_valid = 1'b1;
                        end
                    end
                    default: begin
                        a_mux = '0;
                        a_mux_valid = 1'b0;
                    end
                endcase
            end

            assign a_wire[0][input_row] = a_mux;
            assign a_valid_wire[0][input_row] = a_mux_valid;
        end

        // B[k][col] enters from the top, delayed by its column index.
        for (input_col = 0; input_col < ARRAY_W_SIZE; input_col++) begin : b_input_mux
            reg signed [DATA_WIDTH_IN-1:0] b_mux;
            reg b_mux_valid;

            always @(*) begin
                b_mux = '0;
                b_mux_valid = 1'b0;

                case (current_state)
                    LOAD_STREAM: begin
                        if (load_fire && (array_counter >= input_col)) begin
                            b_mux_valid = 1'b1;

                            if (input_col == 0)
                                b_mux = i_b_data[input_col];
                            else
                                b_mux = b_buffer[array_counter-input_col][input_col];
                        end
                    end
                    DRAIN: begin
                        if ((drain_counter < input_col) &&
                            ((ARRAY_K_SIZE + drain_counter) >= input_col)) begin
                            b_mux = b_buffer
                                [ARRAY_K_SIZE+drain_counter-input_col][input_col];
                            b_mux_valid = 1'b1;
                        end
                    end
                    default: begin
                        b_mux = '0;
                        b_mux_valid = 1'b0;
                    end
                endcase
            end

            assign b_wire[input_col][0] = b_mux;
            assign b_valid_wire[input_col][0] = b_mux_valid;
        end

        for (instantiate_pe_w = 0;
             instantiate_pe_w < ARRAY_W_SIZE;
             instantiate_pe_w++) begin : pe_w
            for (instantiate_pe_h = 0;
                 instantiate_pe_h < ARRAY_H_SIZE;
                 instantiate_pe_h++) begin : pe_h
                processing_element #(
                    .DATA_WIDTH_IN(DATA_WIDTH_IN),
                    .ACCUMULATION_COUNT(ARRAY_K_SIZE)
                ) pe (
                    .ACLK(ACLK),
                    .ARESETn(ARESETn),

                    .A_IN(a_wire[instantiate_pe_w][instantiate_pe_h]),
                    .B_IN(b_wire[instantiate_pe_w][instantiate_pe_h]),
                    .A_VALID_IN(a_valid_wire[instantiate_pe_w][instantiate_pe_h]),
                    .B_VALID_IN(b_valid_wire[instantiate_pe_w][instantiate_pe_h]),
                    .en(pe_en),
                    .clear_acc(clear_acc),

                    .A_OUT(a_wire[instantiate_pe_w+1][instantiate_pe_h]),
                    .B_OUT(b_wire[instantiate_pe_w][instantiate_pe_h+1]),
                    .A_VALID_OUT(a_valid_wire[instantiate_pe_w+1][instantiate_pe_h]),
                    .B_VALID_OUT(b_valid_wire[instantiate_pe_w][instantiate_pe_h+1]),
                    .acc_out(acc_wire[instantiate_pe_w][instantiate_pe_h]),
                    .acc_valid(acc_valid_wire[instantiate_pe_w][instantiate_pe_h])
                );
            end
        end

        for (output_col = 0; output_col < ARRAY_W_SIZE; output_col++) begin : output_mux
            always @(*) begin
                o_data[output_col] = acc_wire[output_col][output_counter];
            end
        end
    endgenerate

    integer load_idx;
    always @(posedge ACLK or negedge ARESETn) begin
        if (!ARESETn) begin
            current_state <= IDLE;
            array_counter <= '0;
            drain_counter <= '0;
            output_counter <= '0;
            clear_done <= 1'b0;
        end
        else if (clear_request && (current_state != CLEAR)) begin
            current_state <= CLEAR;
            array_counter <= '0;
            drain_counter <= '0;
            output_counter <= '0;
            clear_done <= 1'b0;
        end
        else begin
            case (current_state)
                IDLE: begin
                    array_counter <= '0;
                    drain_counter <= '0;
                    output_counter <= '0;
                    clear_done <= 1'b0;
                end

                CLEAR: begin
                    array_counter <= '0;
                    drain_counter <= '0;
                    output_counter <= '0;

                    if (!clear_done) begin
                        clear_done <= 1'b1;
                    end
                    else if (!clear_request) begin
                        clear_done <= 1'b0;
                        current_state <= LOAD_STREAM;
                    end
                end

                LOAD_STREAM: begin
                    if (load_fire) begin
                        for (load_idx = 0;
                             load_idx < ARRAY_H_SIZE;
                             load_idx = load_idx + 1) begin
                            a_buffer[load_idx][array_counter] <= i_a_data[load_idx];
                        end

                        for (load_idx = 0;
                             load_idx < ARRAY_W_SIZE;
                             load_idx = load_idx + 1) begin
                            b_buffer[array_counter][load_idx] <= i_b_data[load_idx];
                        end

                        if (array_counter == ARRAY_K_SIZE-1) begin
                            array_counter <= '0;
                            drain_counter <= '0;

                            if (DRAIN_CYCLES == 0)
                                current_state <= OUTPUT;
                            else
                                current_state <= DRAIN;
                        end
                        else begin
                            array_counter <= array_counter + 1'b1;
                        end
                    end
                end

                DRAIN: begin
                    if (drain_counter == DRAIN_CYCLES-1) begin
                        drain_counter <= '0;
                        output_counter <= '0;
                        current_state <= OUTPUT;
                    end
                    else begin
                        drain_counter <= drain_counter + 1'b1;
                    end
                end

                OUTPUT: begin
                    if (output_fire) begin
                        if (output_counter == ARRAY_H_SIZE-1) begin
                            output_counter <= '0;
                            current_state <= DONE;
                        end
                        else begin
                            output_counter <= output_counter + 1'b1;
                        end
                    end
                end

                DONE: begin
                    current_state <= IDLE;
                end

                default: begin
                    current_state <= IDLE;
                end
            endcase
        end
    end

    integer valid_col;
    reg selected_row_valid;
    always @(*) begin
        selected_row_valid = 1'b1;
        for (valid_col = 0; valid_col < ARRAY_W_SIZE; valid_col = valid_col + 1)
            selected_row_valid = selected_row_valid &&
                                 acc_valid_wire[valid_col][output_counter];
    end

    assign i_ready = (current_state == LOAD_STREAM);
    assign o_valid = (current_state == OUTPUT) && selected_row_valid;
    assign o_last = o_valid && (output_counter == ARRAY_H_SIZE-1);

endmodule


module processing_element #(
    parameter int DATA_WIDTH_IN = 8,
    parameter int ACCUMULATION_COUNT = 4
)(
    input  logic ACLK,
    input  logic ARESETn,

    input  logic signed [DATA_WIDTH_IN-1:0] A_IN,
    input  logic signed [DATA_WIDTH_IN-1:0] B_IN,
    input  logic A_VALID_IN,
    input  logic B_VALID_IN,
    input  logic en,
    input  logic clear_acc,

    output logic signed [DATA_WIDTH_IN-1:0] A_OUT,
    output logic signed [DATA_WIDTH_IN-1:0] B_OUT,
    output logic A_VALID_OUT,
    output logic B_VALID_OUT,
    output logic signed [2*DATA_WIDTH_IN-1:0] acc_out,
    output logic acc_valid
);
    localparam int ACC_COUNT_WIDTH = (ACCUMULATION_COUNT <= 1) ? 1 : $clog2(ACCUMULATION_COUNT+1);

    logic signed [DATA_WIDTH_IN-1:0] A_reg;
    logic signed [DATA_WIDTH_IN-1:0] B_reg;
    logic A_valid_reg;
    logic B_valid_reg;
    logic signed [2*DATA_WIDTH_IN-1:0] acc_reg;
    logic [ACC_COUNT_WIDTH-1:0] accumulation_counter;

    always @(posedge ACLK or negedge ARESETn) begin
        if (!ARESETn) begin
            A_reg <= '0;
            B_reg <= '0;
            A_valid_reg <= 1'b0;
            B_valid_reg <= 1'b0;
            acc_reg <= '0;
            accumulation_counter <= '0;
            acc_valid <= 1'b0;
        end
        else if (clear_acc) begin
            A_reg <= '0;
            B_reg <= '0;
            A_valid_reg <= 1'b0;
            B_valid_reg <= 1'b0;
            acc_reg <= '0;
            accumulation_counter <= '0;
            acc_valid <= 1'b0;
        end
        else if (en) begin
            A_reg <= A_IN;
            B_reg <= B_IN;
            A_valid_reg <= A_VALID_IN;
            B_valid_reg <= B_VALID_IN;

            if (A_VALID_IN && B_VALID_IN) begin
                acc_reg <= acc_reg + (A_IN * B_IN);

                if (accumulation_counter == ACCUMULATION_COUNT-1) begin
                    acc_valid <= 1'b1;
                end
                else begin
                    accumulation_counter <= accumulation_counter + 1'b1;
                end
            end
        end
    end

    assign A_OUT = A_reg;
    assign B_OUT = B_reg;
    assign A_VALID_OUT = A_valid_reg;
    assign B_VALID_OUT = B_valid_reg;
    assign acc_out = acc_reg;

endmodule
