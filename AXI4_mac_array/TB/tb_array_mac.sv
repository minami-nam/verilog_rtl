`timescale 1ns/1ps

module tb_array_mac;
    localparam int ARRAY_H_SIZE = 3;
    localparam int ARRAY_K_SIZE = 5;
    localparam int ARRAY_W_SIZE = 2;
    localparam int DATA_WIDTH_IN = 8;
    localparam int ACC_WIDTH = 2 * DATA_WIDTH_IN;
    localparam int AXI_DATA_WIDTH = 64;
    localparam int AXI_STRB_WIDTH = AXI_DATA_WIDTH / 8;
    localparam int INPUT_CELL_PER_BEAT = AXI_DATA_WIDTH / DATA_WIDTH_IN;
    localparam int OUTPUT_CELL_PER_BEAT = AXI_DATA_WIDTH / ACC_WIDTH;
    localparam int RESULT_BYTE_WIDTH = ACC_WIDTH / 8;
    localparam int C_ELEMENT_COUNT = ARRAY_H_SIZE * ARRAY_W_SIZE;
    localparam int CLK_PERIOD = 10;
    localparam int TIMEOUT_CYCLES = 2000;

    logic ACLK;
    logic ARESETn;

    logic clear;
    logic read_request;
    logic matrix_select;
    logic write_start;
    logic a_loaded;
    logic b_loaded;
    logic read_error;
    logic mac_clear_done;
    logic result_buffer_full;
    logic write_done;

    logic [AXI_DATA_WIDTH-1:0] axi_rdata;
    logic [1:0] axi_rresp;
    logic axi_rlast;
    logic axi_rvalid;
    logic axi_rready;

    logic [AXI_DATA_WIDTH-1:0] axi_wdata;
    logic [AXI_STRB_WIDTH-1:0] axi_wstrb;
    logic axi_wlast;
    logic axi_wvalid;
    logic axi_wready;

    integer matrix_a [0:ARRAY_H_SIZE-1][0:ARRAY_K_SIZE-1];
    integer matrix_b [0:ARRAY_K_SIZE-1][0:ARRAY_W_SIZE-1];
    integer golden_c [0:ARRAY_H_SIZE-1][0:ARRAY_W_SIZE-1];
    integer observed_c [0:C_ELEMENT_COUNT-1];

    integer cycle_count;
    integer start_cycle;
    integer end_cycle;
    integer observed_count;
    integer error_count;
    integer log_fd;
    integer monitor_lane;
    integer monitor_byte;
    integer timeout_idx;
    logic output_finished;

    mac_array_top #(
        .ARRAY_H_SIZE(ARRAY_H_SIZE),
        .ARRAY_K_SIZE(ARRAY_K_SIZE),
        .ARRAY_W_SIZE(ARRAY_W_SIZE),
        .DATA_WIDTH_IN(DATA_WIDTH_IN),
        .AXI_DATA_WIDTH(AXI_DATA_WIDTH),
        .AXI_STRB_WIDTH(AXI_STRB_WIDTH)
    ) dut (
        .ACLK(ACLK),
        .ARESETn(ARESETn),

        .clear(clear),
        .read_request(read_request),
        .matrix_select(matrix_select),
        .write_start(write_start),
        .a_loaded(a_loaded),
        .b_loaded(b_loaded),
        .read_error(read_error),
        .mac_clear_done(mac_clear_done),
        .result_buffer_full(result_buffer_full),
        .write_done(write_done),

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

    always #(CLK_PERIOD/2) ACLK = ~ACLK;

    task automatic pulse_read_request(input logic select_b);
        begin
            @(negedge ACLK);
            matrix_select = select_b;
            if (!select_b)
                start_cycle = cycle_count + 1;

            read_request = 1'b1;
            @(negedge ACLK);
            read_request = 1'b0;
        end
    endtask

    task automatic send_matrix_burst(input logic select_b);
        integer element_count;
        integer beat_count;
        integer beat_idx;
        integer lane_idx;
        integer linear_idx;
        integer row_idx;
        integer col_idx;
        reg [AXI_DATA_WIDTH-1:0] beat_data;
        begin
            element_count = select_b
                          ? ARRAY_K_SIZE * ARRAY_W_SIZE
                          : ARRAY_H_SIZE * ARRAY_K_SIZE;
            beat_count = (element_count + INPUT_CELL_PER_BEAT - 1)
                       / INPUT_CELL_PER_BEAT;

            pulse_read_request(select_b);

            $display("[TB][cycle %0d] Start %s burst: %0d elements, %0d beats",
                     cycle_count, select_b ? "B" : "A", element_count, beat_count);
            $fdisplay(log_fd,
                      "[cycle %0d] Start %s burst: %0d elements, %0d beats",
                      cycle_count, select_b ? "B" : "A", element_count, beat_count);

            for (beat_idx = 0; beat_idx < beat_count; beat_idx = beat_idx + 1) begin
                @(negedge ACLK);
                beat_data = '0;

                for (lane_idx = 0;
                     lane_idx < INPUT_CELL_PER_BEAT;
                     lane_idx = lane_idx + 1) begin
                    linear_idx = beat_idx * INPUT_CELL_PER_BEAT + lane_idx;

                    if (linear_idx < element_count) begin
                        if (!select_b) begin
                            row_idx = linear_idx / ARRAY_K_SIZE;
                            col_idx = linear_idx % ARRAY_K_SIZE;
                            beat_data[lane_idx*DATA_WIDTH_IN +: DATA_WIDTH_IN]
                                = matrix_a[row_idx][col_idx];
                        end
                        else begin
                            row_idx = linear_idx / ARRAY_W_SIZE;
                            col_idx = linear_idx % ARRAY_W_SIZE;
                            beat_data[lane_idx*DATA_WIDTH_IN +: DATA_WIDTH_IN]
                                = matrix_b[row_idx][col_idx];
                        end
                    end
                end

                axi_rdata = beat_data;
                axi_rresp = 2'b00;
                axi_rlast = (beat_idx == beat_count-1);
                axi_rvalid = 1'b1;

                do begin
                    @(posedge ACLK);
                end while (!axi_rready);
            end

            @(negedge ACLK);
            axi_rvalid = 1'b0;
            axi_rlast = 1'b0;
            axi_rdata = '0;
        end
    endtask

    task automatic pulse_write_start;
        begin
            @(negedge ACLK);
            write_start = 1'b1;
            @(negedge ACLK);
            write_start = 1'b0;
        end
    endtask

    // Cycle counter and AXI write-data monitor.
    always @(posedge ACLK) begin
        if (!ARESETn) begin
            cycle_count = 0;
            observed_count = 0;
            output_finished = 1'b0;
            end_cycle = 0;
        end
        else begin
            cycle_count = cycle_count + 1;

            if (axi_wvalid && axi_wready) begin
                $display("[TB][cycle %0d] W beat: data=%h strb=%h last=%0b",
                         cycle_count, axi_wdata, axi_wstrb, axi_wlast);
                $fdisplay(log_fd,
                          "[cycle %0d] W beat: data=%h strb=%h last=%0b",
                          cycle_count, axi_wdata, axi_wstrb, axi_wlast);

                for (monitor_lane = 0;
                     monitor_lane < OUTPUT_CELL_PER_BEAT;
                     monitor_lane = monitor_lane + 1) begin
                    if (|axi_wstrb[monitor_lane*RESULT_BYTE_WIDTH +: RESULT_BYTE_WIDTH]) begin
                        if (!(&axi_wstrb[monitor_lane*RESULT_BYTE_WIDTH
                                        +: RESULT_BYTE_WIDTH])) begin
                            error_count = error_count + 1;
                            $display("[TB][ERROR] Partial strobe inside result lane %0d",
                                     monitor_lane);
                        end
                        else if (observed_count >= C_ELEMENT_COUNT) begin
                            error_count = error_count + 1;
                            $display("[TB][ERROR] Received more C elements than expected");
                        end
                        else begin
                            observed_c[observed_count]
                                = $signed(axi_wdata[monitor_lane*ACC_WIDTH +: ACC_WIDTH]);
                            observed_count = observed_count + 1;
                        end
                    end
                end

                if (axi_wlast) begin
                    end_cycle = cycle_count;
                    output_finished = 1'b1;

                    if (observed_count != C_ELEMENT_COUNT) begin
                        error_count = error_count + 1;
                        $display("[TB][ERROR] WLAST with %0d/%0d result elements",
                                 observed_count, C_ELEMENT_COUNT);
                    end
                end
            end
        end
    end

    initial begin : timeout_watchdog
        wait (ARESETn === 1'b1);
        for (timeout_idx = 0;
             timeout_idx < TIMEOUT_CYCLES;
             timeout_idx = timeout_idx + 1) begin
            @(posedge ACLK);
            if (output_finished)
                disable timeout_watchdog;
        end

        $display("[TB][FATAL] Timeout after %0d cycles", TIMEOUT_CYCLES);
        $fdisplay(log_fd, "[FATAL] Timeout after %0d cycles", TIMEOUT_CYCLES);
        $fatal(1);
    end

    integer row_idx;
    integer col_idx;
    integer k_idx;
    integer linear_idx;
    integer expected_value;
    integer elapsed_cycles;

    initial begin : test_sequence
        ACLK = 1'b0;
        ARESETn = 1'b0;
        clear = 1'b0;
        read_request = 1'b0;
        matrix_select = 1'b0;
        write_start = 1'b0;
        axi_rdata = '0;
        axi_rresp = 2'b00;
        axi_rlast = 1'b0;
        axi_rvalid = 1'b0;
        axi_wready = 1'b1;
        cycle_count = 0;
        end_cycle = 0;
        observed_count = 0;
        error_count = 0;
        start_cycle = 0;
        output_finished = 1'b0;
        expected_value = '0;
        monitor_byte = '0;
        monitor_lane = '0;
        elapsed_cycles = '0;
        axi_wdata = '0;


        for (linear_idx = 0;
             linear_idx < C_ELEMENT_COUNT;
             linear_idx = linear_idx + 1) begin
            observed_c[linear_idx] = 0;
        end

        log_fd = $fopen("tb_array_mac.log", "w");
        if (log_fd == 0)
            $fatal(1, "Failed to open tb_array_mac.log");

        $dumpfile("tb_array_mac.vcd");
        $dumpvars(0, tb_array_mac);

        // Small signed values keep the expected sum inside ACC_WIDTH.
        for (row_idx = 0; row_idx < ARRAY_H_SIZE; row_idx = row_idx + 1) begin
            for (k_idx = 0; k_idx < ARRAY_K_SIZE; k_idx = k_idx + 1) begin
                matrix_a[row_idx][k_idx] = (row_idx + 1) * (k_idx + 1);
            end
        end

        for (k_idx = 0; k_idx < ARRAY_K_SIZE; k_idx = k_idx + 1) begin
            for (col_idx = 0; col_idx < ARRAY_W_SIZE; col_idx = col_idx + 1) begin
                if (col_idx == 0)
                    matrix_b[k_idx][col_idx] = k_idx + 1;
                else
                    matrix_b[k_idx][col_idx] = -(k_idx + 1);
            end
        end

        for (row_idx = 0; row_idx < ARRAY_H_SIZE; row_idx = row_idx + 1) begin
            for (col_idx = 0; col_idx < ARRAY_W_SIZE; col_idx = col_idx + 1) begin
                golden_c[row_idx][col_idx] = 0;
                for (k_idx = 0; k_idx < ARRAY_K_SIZE; k_idx = k_idx + 1) begin
                    golden_c[row_idx][col_idx]
                        = golden_c[row_idx][col_idx]
                        + matrix_a[row_idx][k_idx] * matrix_b[k_idx][col_idx];
                end
            end
        end

        $display("[TB] H=%0d K=%0d W=%0d DATA=%0d AXI=%0d",
                 ARRAY_H_SIZE, ARRAY_K_SIZE, ARRAY_W_SIZE,
                 DATA_WIDTH_IN, AXI_DATA_WIDTH);
        $fdisplay(log_fd, "H=%0d K=%0d W=%0d DATA=%0d AXI=%0d",
                  ARRAY_H_SIZE, ARRAY_K_SIZE, ARRAY_W_SIZE,
                  DATA_WIDTH_IN, AXI_DATA_WIDTH);

        repeat (4) @(posedge ACLK);
        @(negedge ACLK);
        ARESETn = 1'b1;

        @(negedge ACLK);
        clear = 1'b1;
        wait (mac_clear_done === 1'b1);
        @(negedge ACLK);
        clear = 1'b0;
        wait (mac_clear_done === 1'b0);

        send_matrix_burst(1'b0);
        wait (a_loaded === 1'b1);
        $display("[TB][cycle %0d] Matrix A loaded", cycle_count);
        $fdisplay(log_fd, "[cycle %0d] Matrix A loaded", cycle_count);

        send_matrix_burst(1'b1);
        wait (b_loaded === 1'b1);
        $display("[TB][cycle %0d] Matrix B loaded", cycle_count);
        $fdisplay(log_fd, "[cycle %0d] Matrix B loaded", cycle_count);

        if (read_error) begin
            error_count = error_count + 1;
            $display("[TB][ERROR] Input buffer reported AXI read error");
        end

        wait (result_buffer_full === 1'b1);
        $display("[TB][cycle %0d] Complete C tile stored in output buffer",
                 cycle_count);
        $fdisplay(log_fd,
                  "[cycle %0d] Complete C tile stored in output buffer",
                  cycle_count);

        pulse_write_start();
        wait (output_finished === 1'b1);
        #1;

        elapsed_cycles = end_cycle - start_cycle + 1;
        $display("[TB] First read request to WLAST handshake: %0d cycles",
                 elapsed_cycles);
        $fdisplay(log_fd,
                  "First read request to WLAST handshake: %0d cycles",
                  elapsed_cycles);

        for (linear_idx = 0;
             linear_idx < C_ELEMENT_COUNT;
             linear_idx = linear_idx + 1) begin
            row_idx = linear_idx / ARRAY_W_SIZE;
            col_idx = linear_idx % ARRAY_W_SIZE;
            expected_value = golden_c[row_idx][col_idx];

            if (observed_c[linear_idx] !== expected_value) begin
                error_count = error_count + 1;
                $display("[TB][ERROR] C[%0d][%0d]: expected=%0d actual=%0d",
                         row_idx, col_idx, expected_value, observed_c[linear_idx]);
                $fdisplay(log_fd,
                          "[ERROR] C[%0d][%0d]: expected=%0d actual=%0d",
                          row_idx, col_idx, expected_value, observed_c[linear_idx]);
            end
            else begin
                $display("[TB][PASS] C[%0d][%0d] = %0d",
                         row_idx, col_idx, observed_c[linear_idx]);
                $fdisplay(log_fd, "[PASS] C[%0d][%0d] = %0d",
                          row_idx, col_idx, observed_c[linear_idx]);
            end
        end

        if (error_count == 0) begin
            $display("[TB][PASS] All results matched. Total cycles=%0d",
                     elapsed_cycles);
            $fdisplay(log_fd, "[PASS] All results matched. Total cycles=%0d",
                      elapsed_cycles);
        end
        else begin
            $display("[TB][FAIL] %0d errors detected", error_count);
            $fdisplay(log_fd, "[FAIL] %0d errors detected", error_count);
        end

        $fclose(log_fd);
        repeat (2) @(posedge ACLK);

        if (error_count == 0)
            $finish;
        else
            $fatal(1, "Matrix result mismatch");
    end

endmodule
