`timescale 1ns/1ps

module tb_mac_multi_axi4_subsystem;
    localparam int NUM_MAC = 3;
    localparam int NUM_MEMORY = 3;
    localparam int ARRAY_H_SIZE = 2;
    localparam int ARRAY_K_SIZE = 3;
    localparam int ARRAY_W_SIZE = 2;
    localparam int DATA_WIDTH_IN = 8;
    localparam int ACC_WIDTH = 2 * DATA_WIDTH_IN;
    localparam int AXI_ADDR_WIDTH = 32;
    localparam int AXI_DATA_WIDTH = 64;
    localparam int AXI_ID_WIDTH = 4;
    localparam int MEMORY_BYTES = 64 * 1024;
    localparam int RESULT_BYTES = ACC_WIDTH / 8;

    localparam int A_OFFSET = 'h0000;
    localparam int B_OFFSET = 'h0100;
    localparam int C_OFFSET = 'h0200;
    localparam int TIMEOUT_CYCLES = 5000;
    localparam time CLK_PERIOD = 10ns;

    logic ACLK;
    logic ARESETn;
    logic [NUM_MAC-1:0] start;
    logic [NUM_MAC-1:0] clear_request;
    logic [NUM_MAC*AXI_ADDR_WIDTH-1:0] a_base_addr;
    logic [NUM_MAC*AXI_ADDR_WIDTH-1:0] b_base_addr;
    logic [NUM_MAC*AXI_ADDR_WIDTH-1:0] c_base_addr;
    logic [NUM_MAC-1:0] busy;
    logic [NUM_MAC-1:0] done;
    logic [NUM_MAC-1:0] error;

    integer matrix_a [0:NUM_MAC-1][0:ARRAY_H_SIZE-1][0:ARRAY_K_SIZE-1];
    integer matrix_b [0:NUM_MAC-1][0:ARRAY_K_SIZE-1][0:ARRAY_W_SIZE-1];
    integer golden_c [0:NUM_MAC-1][0:ARRAY_H_SIZE-1][0:ARRAY_W_SIZE-1];
    logic signed [ACC_WIDTH-1:0] observed_c
        [0:NUM_MAC-1][0:ARRAY_H_SIZE-1][0:ARRAY_W_SIZE-1];
    logic observed_c_valid
        [0:NUM_MAC-1][0:ARRAY_H_SIZE-1][0:ARRAY_W_SIZE-1];
    // Packed waveform mirrors. Element order is MAC, row, then column;
    // MAC0 C[0][0] occupies the least-significant ACC_WIDTH bits.
    logic [NUM_MAC*ARRAY_H_SIZE*ARRAY_W_SIZE*ACC_WIDTH-1:0]
        observed_c_flat;
    logic [NUM_MAC*ARRAY_H_SIZE*ARRAY_W_SIZE-1:0]
        observed_c_valid_flat;

    integer cycle_count;
    integer start_cycle;
    integer done_cycle [0:NUM_MAC-1];
    integer master_ar_count [0:NUM_MAC-1];
    integer master_aw_count [0:NUM_MAC-1];
    integer slave_ar_count [0:NUM_MEMORY-1];
    integer slave_aw_count [0:NUM_MEMORY-1];
    integer error_count;
    integer log_fd;
    logic [NUM_MAC-1:0] done_seen;
    logic [NUM_MAC-1:0] error_seen;

    function automatic logic [AXI_ADDR_WIDTH-1:0] memory_base(
        input integer memory_index
    );
        begin
            case (memory_index)
                0: memory_base = 32'h0000_0000;
                1: memory_base = 32'h4000_0000;
                2: memory_base = 32'h8000_0000;
                default: memory_base = '0;
            endcase
        end
    endfunction

    task automatic write_memory_byte(
        input integer memory_index,
        input integer byte_offset,
        input logic [7:0] byte_value
    );
        begin
            case (memory_index)
                0: dut.gen_memories[0].u_memory.mem[byte_offset] = byte_value;
                1: dut.gen_memories[1].u_memory.mem[byte_offset] = byte_value;
                2: dut.gen_memories[2].u_memory.mem[byte_offset] = byte_value;
                default: $fatal(1, "Invalid memory index %0d", memory_index);
            endcase
        end
    endtask

    function automatic logic [7:0] read_memory_byte(
        input integer memory_index,
        input integer byte_offset
    );
        begin
            case (memory_index)
                0: read_memory_byte =
                    dut.gen_memories[0].u_memory.mem[byte_offset];
                1: read_memory_byte =
                    dut.gen_memories[1].u_memory.mem[byte_offset];
                2: read_memory_byte =
                    dut.gen_memories[2].u_memory.mem[byte_offset];
                default: read_memory_byte = 'x;
            endcase
        end
    endfunction

    function automatic integer read_result_element(
        input integer memory_index,
        input integer element_index
    );
        logic signed [ACC_WIDTH-1:0] packed_result;
        integer byte_index;
        begin
            packed_result = '0;

            for (byte_index = 0;
                 byte_index < RESULT_BYTES;
                 byte_index = byte_index + 1)
                packed_result[byte_index*8 +: 8] =
                    read_memory_byte(
                        memory_index,
                        C_OFFSET + element_index*RESULT_BYTES + byte_index
                    );

            read_result_element = $signed(packed_result);
        end
    endfunction

    mac_multi_axi4_subsystem #(
        .NUM_MAC(NUM_MAC),
        .NUM_MEMORY(NUM_MEMORY),
        .ARRAY_H_SIZE(ARRAY_H_SIZE),
        .ARRAY_K_SIZE(ARRAY_K_SIZE),
        .ARRAY_W_SIZE(ARRAY_W_SIZE),
        .DATA_WIDTH_IN(DATA_WIDTH_IN),
        .ACC_WIDTH(ACC_WIDTH),
        .AXI_ADDR_WIDTH(AXI_ADDR_WIDTH),
        .AXI_DATA_WIDTH(AXI_DATA_WIDTH),
        .AXI_ID_WIDTH(AXI_ID_WIDTH),
        .MEMORY_BYTES(MEMORY_BYTES)
    ) dut (
        .ACLK(ACLK),
        .ARESETn(ARESETn),
        .start(start),
        .clear_request(clear_request),
        .a_base_addr(a_base_addr),
        .b_base_addr(b_base_addr),
        .c_base_addr(c_base_addr),
        .busy(busy),
        .done(done),
        .error(error)
    );

    initial ACLK = 1'b0;
    always #(CLK_PERIOD/2) ACLK = ~ACLK;

    integer monitor_index;
    always @(posedge ACLK) begin
        if (!ARESETn) begin
            cycle_count = 0;
            done_seen = '0;
            error_seen = '0;

            for (monitor_index = 0;
                 monitor_index < NUM_MAC;
                 monitor_index = monitor_index + 1) begin
                done_cycle[monitor_index] = 0;
                master_ar_count[monitor_index] = 0;
                master_aw_count[monitor_index] = 0;
            end

            for (monitor_index = 0;
                 monitor_index < NUM_MEMORY;
                 monitor_index = monitor_index + 1) begin
                slave_ar_count[monitor_index] = 0;
                slave_aw_count[monitor_index] = 0;
            end
        end
        else begin
            cycle_count = cycle_count + 1;
            error_seen = error_seen | error;

            for (monitor_index = 0;
                 monitor_index < NUM_MAC;
                 monitor_index = monitor_index + 1) begin
                if (done[monitor_index]) begin
                    done_seen[monitor_index] = 1'b1;
                    done_cycle[monitor_index] = cycle_count;
                    $fdisplay(
                        log_fd,
                        "[cycle %0d][DONE] MAC %0d error=%0b",
                        cycle_count,
                        monitor_index,
                        error[monitor_index]
                    );
                end

                if (dut.s_axi_arvalid[monitor_index] &&
                    dut.s_axi_arready[monitor_index]) begin
                    master_ar_count[monitor_index] =
                        master_ar_count[monitor_index] + 1;
                    $fdisplay(
                        log_fd,
                        "[cycle %0d][M%0d AR] id=%0h addr=%08h len=%0d size=%0d",
                        cycle_count,
                        monitor_index,
                        dut.s_axi_arid[
                            monitor_index*AXI_ID_WIDTH +: AXI_ID_WIDTH],
                        dut.s_axi_araddr[
                            monitor_index*AXI_ADDR_WIDTH +: AXI_ADDR_WIDTH],
                        dut.s_axi_arlen[monitor_index*8 +: 8],
                        dut.s_axi_arsize[monitor_index*3 +: 3]
                    );
                end

                if (dut.s_axi_awvalid[monitor_index] &&
                    dut.s_axi_awready[monitor_index]) begin
                    master_aw_count[monitor_index] =
                        master_aw_count[monitor_index] + 1;
                    $fdisplay(
                        log_fd,
                        "[cycle %0d][M%0d AW] id=%0h addr=%08h len=%0d size=%0d",
                        cycle_count,
                        monitor_index,
                        dut.s_axi_awid[
                            monitor_index*AXI_ID_WIDTH +: AXI_ID_WIDTH],
                        dut.s_axi_awaddr[
                            monitor_index*AXI_ADDR_WIDTH +: AXI_ADDR_WIDTH],
                        dut.s_axi_awlen[monitor_index*8 +: 8],
                        dut.s_axi_awsize[monitor_index*3 +: 3]
                    );
                end

                if (dut.s_axi_rvalid[monitor_index] &&
                    dut.s_axi_rready[monitor_index] &&
                    dut.s_axi_rlast[monitor_index])
                    $fdisplay(
                        log_fd,
                        "[cycle %0d][M%0d RLAST] id=%0h resp=%0b data=%016h",
                        cycle_count,
                        monitor_index,
                        dut.s_axi_rid[
                            monitor_index*AXI_ID_WIDTH +: AXI_ID_WIDTH],
                        dut.s_axi_rresp[monitor_index*2 +: 2],
                        dut.s_axi_rdata[
                            monitor_index*AXI_DATA_WIDTH +: AXI_DATA_WIDTH]
                    );

                if (dut.s_axi_bvalid[monitor_index] &&
                    dut.s_axi_bready[monitor_index])
                    $fdisplay(
                        log_fd,
                        "[cycle %0d][M%0d B] id=%0h resp=%0b",
                        cycle_count,
                        monitor_index,
                        dut.s_axi_bid[
                            monitor_index*AXI_ID_WIDTH +: AXI_ID_WIDTH],
                        dut.s_axi_bresp[monitor_index*2 +: 2]
                    );
            end

            for (monitor_index = 0;
                 monitor_index < NUM_MEMORY;
                 monitor_index = monitor_index + 1) begin
                if (dut.m_axi_arvalid[monitor_index] &&
                    dut.m_axi_arready[monitor_index]) begin
                    slave_ar_count[monitor_index] =
                        slave_ar_count[monitor_index] + 1;
                    $fdisplay(
                        log_fd,
                        "[cycle %0d][S%0d AR] id=%0h addr=%08h len=%0d",
                        cycle_count,
                        monitor_index,
                        dut.m_axi_arid[
                            monitor_index*AXI_ID_WIDTH +: AXI_ID_WIDTH],
                        dut.m_axi_araddr[
                            monitor_index*AXI_ADDR_WIDTH +: AXI_ADDR_WIDTH],
                        dut.m_axi_arlen[monitor_index*8 +: 8]
                    );
                end

                if (dut.m_axi_awvalid[monitor_index] &&
                    dut.m_axi_awready[monitor_index]) begin
                    slave_aw_count[monitor_index] =
                        slave_aw_count[monitor_index] + 1;
                    $fdisplay(
                        log_fd,
                        "[cycle %0d][S%0d AW] id=%0h addr=%08h len=%0d",
                        cycle_count,
                        monitor_index,
                        dut.m_axi_awid[
                            monitor_index*AXI_ID_WIDTH +: AXI_ID_WIDTH],
                        dut.m_axi_awaddr[
                            monitor_index*AXI_ADDR_WIDTH +: AXI_ADDR_WIDTH],
                        dut.m_axi_awlen[monitor_index*8 +: 8]
                    );
                end
            end
        end
    end

    integer timeout_counter;
    initial begin : timeout_watchdog
        wait (ARESETn === 1'b1);

        for (timeout_counter = 0;
             timeout_counter < TIMEOUT_CYCLES;
             timeout_counter = timeout_counter + 1) begin
            @(posedge ACLK);

            if (&done_seen)
                disable timeout_watchdog;
        end

        $display("[TB][FATAL] Timeout after %0d cycles", TIMEOUT_CYCLES);
        $fdisplay(log_fd, "[FATAL] Timeout after %0d cycles", TIMEOUT_CYCLES);
        $fatal(1);
    end

    integer mac_index;
    integer row_index;
    integer col_index;
    integer k_index;
    integer linear_index;

    initial begin : test_sequence
        ARESETn = 1'b0;
        start = '0;
        clear_request = '0;
        a_base_addr = '0;
        b_base_addr = '0;
        c_base_addr = '0;
        error_count = 0;
        start_cycle = 0;
        observed_c_flat = '0;
        observed_c_valid_flat = '0;

        log_fd = $fopen("tb_mac_multi_axi4_subsystem.log", "w");
        if (log_fd == 0)
            $fatal(1, "Failed to open subsystem log file");

        $fdisplay(log_fd, "==================================================");
        $fdisplay(log_fd, "MAC AXI4 Multi-Controller Subsystem Verification");
        $fdisplay(
            log_fd,
            "NUM_MAC=%0d NUM_MEMORY=%0d H=%0d K=%0d W=%0d DATA=%0d ACC=%0d AXI=%0d",
            NUM_MAC,
            NUM_MEMORY,
            ARRAY_H_SIZE,
            ARRAY_K_SIZE,
            ARRAY_W_SIZE,
            DATA_WIDTH_IN,
            ACC_WIDTH,
            AXI_DATA_WIDTH
        );
        $fdisplay(log_fd, "==================================================");

        $dumpfile("tb_mac_multi_axi4_subsystem.vcd");
        $dumpvars(0, tb_mac_multi_axi4_subsystem);

        // Wait until every memory instance has completed its time-zero init.
        repeat (2) @(posedge ACLK);

        for (mac_index = 0;
             mac_index < NUM_MAC;
             mac_index = mac_index + 1) begin
            a_base_addr[mac_index*AXI_ADDR_WIDTH +: AXI_ADDR_WIDTH] =
                memory_base(mac_index) + A_OFFSET;
            b_base_addr[mac_index*AXI_ADDR_WIDTH +: AXI_ADDR_WIDTH] =
                memory_base(mac_index) + B_OFFSET;
            c_base_addr[mac_index*AXI_ADDR_WIDTH +: AXI_ADDR_WIDTH] =
                memory_base(mac_index) + C_OFFSET;

            $fdisplay(
                log_fd,
                "[CONFIG] MAC %0d A=%08h B=%08h C=%08h",
                mac_index,
                memory_base(mac_index) + A_OFFSET,
                memory_base(mac_index) + B_OFFSET,
                memory_base(mac_index) + C_OFFSET
            );

            for (row_index = 0;
                 row_index < ARRAY_H_SIZE;
                 row_index = row_index + 1) begin
                for (k_index = 0;
                     k_index < ARRAY_K_SIZE;
                     k_index = k_index + 1) begin
                    matrix_a[mac_index][row_index][k_index] =
                        (mac_index + 1) * (row_index + k_index + 1);

                    linear_index = row_index * ARRAY_K_SIZE + k_index;
                    write_memory_byte(
                        mac_index,
                        A_OFFSET + linear_index,
                        matrix_a[mac_index][row_index][k_index]
                    );
                    $fdisplay(
                        log_fd,
                        "[PRELOAD] MAC %0d A[%0d][%0d]=%0d mem[%04h]=%02h",
                        mac_index,
                        row_index,
                        k_index,
                        matrix_a[mac_index][row_index][k_index],
                        A_OFFSET + linear_index,
                        matrix_a[mac_index][row_index][k_index][7:0]
                    );
                end
            end

            for (k_index = 0;
                 k_index < ARRAY_K_SIZE;
                 k_index = k_index + 1) begin
                for (col_index = 0;
                     col_index < ARRAY_W_SIZE;
                     col_index = col_index + 1) begin
                    if (col_index == 0)
                        matrix_b[mac_index][k_index][col_index] =
                            k_index + 1;
                    else
                        matrix_b[mac_index][k_index][col_index] =
                            -(k_index + 1);

                    linear_index = k_index * ARRAY_W_SIZE + col_index;
                    write_memory_byte(
                        mac_index,
                        B_OFFSET + linear_index,
                        matrix_b[mac_index][k_index][col_index]
                    );
                    $fdisplay(
                        log_fd,
                        "[PRELOAD] MAC %0d B[%0d][%0d]=%0d mem[%04h]=%02h",
                        mac_index,
                        k_index,
                        col_index,
                        matrix_b[mac_index][k_index][col_index],
                        B_OFFSET + linear_index,
                        matrix_b[mac_index][k_index][col_index][7:0]
                    );
                end
            end

            for (row_index = 0;
                 row_index < ARRAY_H_SIZE;
                 row_index = row_index + 1) begin
                for (col_index = 0;
                     col_index < ARRAY_W_SIZE;
                     col_index = col_index + 1) begin
                    golden_c[mac_index][row_index][col_index] = 0;

                    for (k_index = 0;
                         k_index < ARRAY_K_SIZE;
                         k_index = k_index + 1)
                        golden_c[mac_index][row_index][col_index] =
                            golden_c[mac_index][row_index][col_index] +
                            matrix_a[mac_index][row_index][k_index] *
                            matrix_b[mac_index][k_index][col_index];

                    observed_c[mac_index][row_index][col_index] = '0;
                    observed_c_valid[mac_index][row_index][col_index] = 1'b0;
                    $fdisplay(
                        log_fd,
                        "[GOLDEN] MAC %0d C[%0d][%0d]=%0d",
                        mac_index,
                        row_index,
                        col_index,
                        golden_c[mac_index][row_index][col_index]
                    );
                end
            end
        end

        repeat (3) @(posedge ACLK);
        @(negedge ACLK);
        ARESETn = 1'b1;

        repeat (2) @(posedge ACLK);
        @(negedge ACLK);
        start_cycle = cycle_count + 1;
        start = '1;
        $fdisplay(
            log_fd,
            "[cycle %0d][START] Launch all MAC masters",
            start_cycle
        );
        @(negedge ACLK);
        start = '0;

        wait (&done_seen);
        @(posedge ACLK);
        #1;

        for (mac_index = 0;
             mac_index < NUM_MAC;
             mac_index = mac_index + 1) begin
            if (error_seen[mac_index]) begin
                error_count = error_count + 1;
                $display("[TB][ERROR] MAC %0d reported an error", mac_index);
                $fdisplay(log_fd,
                          "[ERROR] MAC %0d reported an error", mac_index);
            end

            if (master_ar_count[mac_index] != 2) begin
                error_count = error_count + 1;
                $display("[TB][ERROR] MAC %0d AR count=%0d expected=2",
                         mac_index, master_ar_count[mac_index]);
            end

            if (master_aw_count[mac_index] != 1) begin
                error_count = error_count + 1;
                $display("[TB][ERROR] MAC %0d AW count=%0d expected=1",
                         mac_index, master_aw_count[mac_index]);
            end

            $display("[TB] MAC %0d completed in %0d cycles",
                     mac_index, done_cycle[mac_index] - start_cycle + 1);
            $fdisplay(log_fd,
                      "MAC %0d completed in %0d cycles, AR=%0d AW=%0d",
                      mac_index,
                      done_cycle[mac_index] - start_cycle + 1,
                      master_ar_count[mac_index],
                      master_aw_count[mac_index]);

            for (row_index = 0;
                 row_index < ARRAY_H_SIZE;
                 row_index = row_index + 1) begin
                for (col_index = 0;
                     col_index < ARRAY_W_SIZE;
                     col_index = col_index + 1) begin
                    linear_index = row_index * ARRAY_W_SIZE + col_index;
                    observed_c[mac_index][row_index][col_index] =
                        read_result_element(mac_index, linear_index);
                    observed_c_valid[mac_index][row_index][col_index] = 1'b1;
                    observed_c_flat[
                        ((mac_index*ARRAY_H_SIZE*ARRAY_W_SIZE) +
                         (row_index*ARRAY_W_SIZE) + col_index)*ACC_WIDTH
                        +: ACC_WIDTH] =
                            observed_c[mac_index][row_index][col_index];
                    observed_c_valid_flat[
                        (mac_index*ARRAY_H_SIZE*ARRAY_W_SIZE) +
                        (row_index*ARRAY_W_SIZE) + col_index] = 1'b1;

                    if ($signed(
                            observed_c[mac_index][row_index][col_index]) !==
                        golden_c[mac_index][row_index][col_index]) begin
                        error_count = error_count + 1;
                        $display(
                            "[TB][ERROR] MAC %0d C[%0d][%0d]=%0d expected=%0d",
                            mac_index,
                            row_index,
                            col_index,
                            $signed(observed_c[
                                mac_index][row_index][col_index]),
                            golden_c[mac_index][row_index][col_index]
                        );
                        $fdisplay(
                            log_fd,
                            "[ERROR] MAC %0d C[%0d][%0d]=%0d expected=%0d",
                            mac_index,
                            row_index,
                            col_index,
                            $signed(observed_c[
                                mac_index][row_index][col_index]),
                            golden_c[mac_index][row_index][col_index]
                        );
                    end
                    else begin
                        $display(
                            "[TB][MATCH] MAC %0d C[%0d][%0d]=%0d",
                            mac_index,
                            row_index,
                            col_index,
                            $signed(observed_c[
                                mac_index][row_index][col_index])
                        );
                        $fdisplay(
                            log_fd,
                            "[MATCH] MAC %0d C[%0d][%0d] observed=%0d expected=%0d raw=%04h",
                            mac_index,
                            row_index,
                            col_index,
                            $signed(observed_c[
                                mac_index][row_index][col_index]),
                            golden_c[mac_index][row_index][col_index],
                            observed_c[mac_index][row_index][col_index]
                        );
                    end
                end
            end
        end

        for (mac_index = 0;
             mac_index < NUM_MEMORY;
             mac_index = mac_index + 1) begin
            $fdisplay(
                log_fd,
                "[SUMMARY] Memory %0d AR=%0d AW=%0d",
                mac_index,
                slave_ar_count[mac_index],
                slave_aw_count[mac_index]
            );
            if ((slave_ar_count[mac_index] != 2) ||
                (slave_aw_count[mac_index] != 1)) begin
                error_count = error_count + 1;
                $display(
                    "[TB][ERROR] Memory %0d transaction count AR=%0d AW=%0d",
                    mac_index,
                    slave_ar_count[mac_index],
                    slave_aw_count[mac_index]
                );
            end
        end

        if (error_count == 0) begin
            $display("[TB][PASS] All MAC results and AXI transaction counts match");
            $fdisplay(log_fd,
                      "[PASS] All MAC results and AXI transaction counts match");
        end
        else begin
            $display("[TB][FAIL] error_count=%0d", error_count);
            $fdisplay(log_fd, "[FAIL] error_count=%0d", error_count);
        end

        $fclose(log_fd);

        if (error_count != 0)
            $fatal(1, "Subsystem verification failed");

        $finish;
    end

endmodule
