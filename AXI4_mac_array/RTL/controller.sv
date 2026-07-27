module controller #(
    parameter int ARRAY_H_SIZE = 4,
    parameter int ARRAY_K_SIZE = 4,
    parameter int ARRAY_W_SIZE = 4,
    parameter int DATA_WIDTH_IN = 8,
    parameter int ACC_WIDTH = 2 * DATA_WIDTH_IN,
    parameter int AXI_DATA_WIDTH = 64,
    parameter int AXI_ADDR_WIDTH = 32,
    parameter int AXI_LEN_WIDTH = 8,
    parameter int AXI_STRB_WIDTH = AXI_DATA_WIDTH / 8
)(
    input  logic ACLK,
    input  logic ARESETn,

    // Host/register command and configuration
    input  logic start,
    input  logic clear_request,
    input  logic [AXI_ADDR_WIDTH-1:0] a_base_addr,
    input  logic [AXI_ADDR_WIDTH-1:0] b_base_addr,
    input  logic [AXI_ADDR_WIDTH-1:0] c_base_addr,

    output logic busy,
    output logic done,
    output logic error,

    // Datapath control/status
    output logic datapath_clear,
    output logic read_request,
    output logic matrix_select,  // 1'b0: matrix A, 1'b1: matrix B
    output logic write_start,
    output logic a_loaded,
    output logic b_loaded,
    output logic input_read_error,
    output logic mac_clear_done,
    output logic result_buffer_full,
    output logic write_data_done,

    // AXI4 read-data channel
    input  logic [AXI_DATA_WIDTH-1:0] axi_rdata,
    input  logic [1:0]                axi_rresp,
    input  logic                      axi_rlast,
    input  logic                      axi_rvalid,
    output logic                      axi_rready,

    // AXI4 write-data channel
    output logic [AXI_DATA_WIDTH-1:0] axi_wdata,
    output logic [AXI_STRB_WIDTH-1:0] axi_wstrb,
    output logic                      axi_wlast,
    output logic                      axi_wvalid,
    input  logic                      axi_wready,

    // Read command interface toward the AXI4 Master
    output logic                      read_cmd_valid,
    input  logic                      read_cmd_ready,
    output logic [AXI_ADDR_WIDTH-1:0] read_cmd_addr,
    output logic [AXI_LEN_WIDTH-1:0]  read_cmd_len,
    input  logic                      read_cmd_done,
    input  logic                      read_cmd_error,

    // Write command interface toward the AXI4 Master
    output logic                      write_cmd_valid,
    input  logic                      write_cmd_ready,
    output logic [AXI_ADDR_WIDTH-1:0] write_cmd_addr,
    output logic [AXI_LEN_WIDTH-1:0]  write_cmd_len,
    input  logic                      write_response_done,
    input  logic                      write_response_error
);
    localparam int AXI_MAX_BURST_BEATS = 1 << AXI_LEN_WIDTH;

    localparam int A_ELEMENT_COUNT = ARRAY_H_SIZE * ARRAY_K_SIZE;
    localparam int B_ELEMENT_COUNT = ARRAY_K_SIZE * ARRAY_W_SIZE;
    localparam int C_ELEMENT_COUNT = ARRAY_H_SIZE * ARRAY_W_SIZE;

    localparam int INPUT_CELL_PER_BEAT =
        (AXI_DATA_WIDTH >= DATA_WIDTH_IN) ? AXI_DATA_WIDTH / DATA_WIDTH_IN : 1;
    localparam int OUTPUT_CELL_PER_BEAT =
        (AXI_DATA_WIDTH >= ACC_WIDTH) ? AXI_DATA_WIDTH / ACC_WIDTH : 1;

    localparam int A_READ_BEATS =
        (A_ELEMENT_COUNT + INPUT_CELL_PER_BEAT - 1) / INPUT_CELL_PER_BEAT;
    localparam int B_READ_BEATS =
        (B_ELEMENT_COUNT + INPUT_CELL_PER_BEAT - 1) / INPUT_CELL_PER_BEAT;
    localparam int C_WRITE_BEATS =
        (C_ELEMENT_COUNT + OUTPUT_CELL_PER_BEAT - 1) / OUTPUT_CELL_PER_BEAT;

    // AXI4 AxLEN is one less than the actual number of transferred beats.
    localparam int A_READ_CMD_LEN  = A_READ_BEATS - 1;
    localparam int B_READ_CMD_LEN  = B_READ_BEATS - 1;
    localparam int C_WRITE_CMD_LEN = C_WRITE_BEATS - 1;

    localparam logic CONFIG_VALID =
        (ARRAY_H_SIZE > 0) &&
        (ARRAY_K_SIZE > 0) &&
        (ARRAY_W_SIZE > 0) &&
        (DATA_WIDTH_IN > 0) &&
        (ACC_WIDTH > 0) &&
        (ACC_WIDTH == (2 * DATA_WIDTH_IN)) &&
        (AXI_DATA_WIDTH >= DATA_WIDTH_IN) &&
        (AXI_DATA_WIDTH >= ACC_WIDTH) &&
        ((AXI_DATA_WIDTH % DATA_WIDTH_IN) == 0) &&
        ((AXI_DATA_WIDTH % ACC_WIDTH) == 0) &&
        ((ACC_WIDTH % 8) == 0) &&
        (A_READ_BEATS <= AXI_MAX_BURST_BEATS) &&
        (B_READ_BEATS <= AXI_MAX_BURST_BEATS) &&
        (C_WRITE_BEATS <= AXI_MAX_BURST_BEATS);

    typedef enum logic [3:0] {
        IDLE,
        CLEAR,
        READ_A_CMD,
        WAIT_A,
        READ_B_CMD,
        WAIT_B,
        RUN_MAC,
        WAIT_RESULT,
        WRITE_C_CMD,
        WAIT_WRITE_DATA,
        WAIT_RESP,
        DONE
    } fsm_status;

    fsm_status current_status;

    logic run_after_clear;
    logic read_done_seen;
    logic write_response_seen;
    logic write_response_failed;

    mac_array_top #(
        .ARRAY_H_SIZE(ARRAY_H_SIZE),
        .ARRAY_K_SIZE(ARRAY_K_SIZE),
        .ARRAY_W_SIZE(ARRAY_W_SIZE),
        .DATA_WIDTH_IN(DATA_WIDTH_IN),
        .AXI_DATA_WIDTH(AXI_DATA_WIDTH),
        .AXI_STRB_WIDTH(AXI_STRB_WIDTH)
    ) u_mac_array_top (
        .ACLK(ACLK),
        .ARESETn(ARESETn),

        .clear(datapath_clear),
        .read_request(read_request),
        .matrix_select(matrix_select),
        .write_start(write_start),
        .a_loaded(a_loaded),
        .b_loaded(b_loaded),
        .read_error(input_read_error),
        .mac_clear_done(mac_clear_done),
        .result_buffer_full(result_buffer_full),
        .write_done(write_data_done),

        .axi_rdata(axi_rdata),
        .axi_rresp(axi_rresp),
        .axi_rlast(axi_rlast),
        .axi_rvalid(axi_rvalid),
        .axi_rready(axi_rready),

        .axi_wdata(axi_wdata),
        .axi_wstrb(axi_wstrb),
        .axi_wlast(axi_wlast),
        .axi_wvalid(axi_wvalid),
        .axi_wready(axi_wready)
    );

    always @(posedge ACLK or negedge ARESETn) begin
        if (!ARESETn) begin
            current_status <= IDLE;
            run_after_clear <= 1'b0;
            read_done_seen <= 1'b0;
            write_response_seen <= 1'b0;
            write_response_failed <= 1'b0;

            busy <= 1'b0;
            done <= 1'b0;
            error <= 1'b0;

            datapath_clear <= 1'b0;
            read_request <= 1'b0;
            matrix_select <= 1'b0;
            write_start <= 1'b0;

            read_cmd_valid <= 1'b0;
            read_cmd_addr <= '0;
            read_cmd_len <= '0;

            write_cmd_valid <= 1'b0;
            write_cmd_addr <= '0;
            write_cmd_len <= '0;
        end
        else begin
            // Pulse-type outputs default low and are raised only at handshakes.
            done <= 1'b0;
            read_request <= 1'b0;
            write_start <= 1'b0;

            if (read_cmd_done)
                read_done_seen <= 1'b1;

            if (write_response_done) begin
                write_response_seen <= 1'b1;
                write_response_failed <= write_response_error;
            end

            case (current_status)
                IDLE: begin
                    busy <= 1'b0;
                    error <= 1'b0;
                    datapath_clear <= 1'b0;
                    read_cmd_valid <= 1'b0;
                    write_cmd_valid <= 1'b0;
                    read_done_seen <= 1'b0;
                    write_response_seen <= 1'b0;
                    write_response_failed <= 1'b0;

                    if (start || clear_request) begin
                        if (!CONFIG_VALID) begin
                            busy <= 1'b1;
                            error <= 1'b1;
                            current_status <= DONE;
                        end
                        else begin
                            busy <= 1'b1;
                            run_after_clear <= start;
                            datapath_clear <= 1'b1;
                            current_status <= CLEAR;
                        end
                    end
                end

                CLEAR: begin
                    busy <= 1'b1;
                    datapath_clear <= 1'b1;

                    if (mac_clear_done) begin
                        datapath_clear <= 1'b0;

                        if (run_after_clear)
                            current_status <= READ_A_CMD;
                        else
                            current_status <= DONE;
                    end
                end

                READ_A_CMD: begin
                    read_cmd_addr <= a_base_addr;
                    read_cmd_len <= A_READ_CMD_LEN;
                    matrix_select <= 1'b0;
                    read_cmd_valid <= 1'b1;

                    if (read_cmd_valid && read_cmd_ready) begin
                        read_cmd_valid <= 1'b0;
                        read_request <= 1'b1;
                        read_done_seen <= 1'b0;
                        current_status <= WAIT_A;
                    end
                end

                WAIT_A: begin
                    if (read_cmd_error || input_read_error) begin
                        error <= 1'b1;
                        current_status <= DONE;
                    end
                    else if ((read_done_seen || read_cmd_done) && a_loaded) begin
                        read_done_seen <= 1'b0;
                        current_status <= READ_B_CMD;
                    end
                end

                READ_B_CMD: begin
                    read_cmd_addr <= b_base_addr;
                    read_cmd_len <= B_READ_CMD_LEN;
                    matrix_select <= 1'b1;
                    read_cmd_valid <= 1'b1;

                    if (read_cmd_valid && read_cmd_ready) begin
                        read_cmd_valid <= 1'b0;
                        read_request <= 1'b1;
                        read_done_seen <= 1'b0;
                        current_status <= WAIT_B;
                    end
                end

                WAIT_B: begin
                    if (read_cmd_error || input_read_error) begin
                        error <= 1'b1;
                        current_status <= DONE;
                    end
                    else if ((read_done_seen || read_cmd_done) && b_loaded) begin
                        read_done_seen <= 1'b0;
                        current_status <= RUN_MAC;
                    end
                end

                RUN_MAC: begin
                    if (!a_loaded || !b_loaded) begin
                        error <= 1'b1;
                        current_status <= DONE;
                    end
                    else begin
                        current_status <= WAIT_RESULT;
                    end
                end

                WAIT_RESULT: begin
                    if (result_buffer_full)
                        current_status <= WRITE_C_CMD;
                end

                WRITE_C_CMD: begin
                    write_cmd_addr <= c_base_addr;
                    write_cmd_len <= C_WRITE_CMD_LEN;
                    write_cmd_valid <= 1'b1;

                    if (write_cmd_valid && write_cmd_ready) begin
                        write_cmd_valid <= 1'b0;
                        write_start <= 1'b1;
                        write_response_seen <= 1'b0;
                        write_response_failed <= 1'b0;
                        current_status <= WAIT_WRITE_DATA;
                    end
                end

                WAIT_WRITE_DATA: begin
                    if (write_data_done)
                        current_status <= WAIT_RESP;
                end

                WAIT_RESP: begin
                    if (write_response_seen || write_response_done) begin
                        if (write_response_failed ||
                            (write_response_done && write_response_error))
                            error <= 1'b1;

                        current_status <= DONE;
                    end
                end

                DONE: begin
                    busy <= 1'b0;
                    done <= 1'b1;
                    datapath_clear <= 1'b0;
                    read_cmd_valid <= 1'b0;
                    write_cmd_valid <= 1'b0;
                    current_status <= IDLE;
                end

                default: begin
                    busy <= 1'b0;
                    error <= 1'b1;
                    datapath_clear <= 1'b0;
                    read_cmd_valid <= 1'b0;
                    write_cmd_valid <= 1'b0;
                    current_status <= DONE;
                end
            endcase
        end
    end

endmodule
