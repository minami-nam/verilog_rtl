`ifndef TB_AGENTS_SVH
`define TB_AGENTS_SVH

class Master #(
    parameter int ADDR_WIDTH = 32,
    parameter int DATA_WIDTH = 32,
    parameter int ID_WIDTH   = 4,
    parameter int STRB_WIDTH = DATA_WIDTH / 8
);
    typedef virtual axi_master_bfm_if #(
        ADDR_WIDTH, DATA_WIDTH, ID_WIDTH, STRB_WIDTH
    ) master_vif_t;
    typedef logic [DATA_WIDTH-1:0] data_t;
    typedef logic [STRB_WIDTH-1:0] strb_t;
    typedef AxiTransaction #(
        ADDR_WIDTH, DATA_WIDTH, ID_WIDTH, STRB_WIDTH
    ) transaction_t;

    int unsigned master_index;
    string       instance_name;
    master_vif_t vif;
    int unsigned log_level;

    rand int unsigned request_gap_cycles;
    rand int unsigned write_beat_gap_cycles;
    rand int unsigned bready_delay_cycles;
    rand int unsigned rready_delay_cycles;
    rand bit [3:0]    default_qos;
    rand bit [7:0]    maximum_burst_len;
    rand bit          allow_fixed_burst;
    rand bit          allow_incr_burst;
    rand bit          allow_wrap_burst;
    rand bit          allow_exclusive;

    constraint legal_master_profile {
        request_gap_cycles inside {[0:32]};
        write_beat_gap_cycles inside {[0:16]};
        bready_delay_cycles inside {[0:32]};
        rready_delay_cycles inside {[0:32]};
        maximum_burst_len inside {[0:255]};
        allow_fixed_burst || allow_incr_burst || allow_wrap_burst;
    }

    function new(
        int unsigned master_index,
        master_vif_t vif,
        string instance_name = "master"
    );
        this.master_index = master_index;
        this.vif = vif;
        this.instance_name = instance_name;
        log_level = 1;
        request_gap_cycles = 0;
        write_beat_gap_cycles = 0;
        bready_delay_cycles = 0;
        rready_delay_cycles = 0;
        default_qos = 0;
        maximum_burst_len = 8'hff;
        allow_fixed_burst = 1;
        allow_incr_burst = 1;
        allow_wrap_burst = 1;
        allow_exclusive = 1;
    endfunction

    virtual task configure_behavior();
        case (master_index)
            0 : begin
                default_qos = $urandom_range(15,12); // real time 
                request_gap_cycles = 1;
            end
            
            1 : begin
                default_qos = $urandom_range(5,8); // System
                request_gap_cycles = 4;
            end

            2 : begin
                default_qos = $urandom_range(0,3);
                request_gap_cycles = 8;
            end 
        endcase
    endtask

    virtual task build_scenario();
        // USER: Write only scenario ordering and transaction constraints here.
    endtask

    virtual task generate_traffic();
        build_scenario();
    endtask

    task automatic execute_transaction(
        input transaction_t transaction,
        output logic [1:0] response,
        output data_t read_data[$]
    );
        read_data.delete();
        request_gap_cycles = transaction.request_gap;
        bready_delay_cycles = transaction.response_ready_delay;
        rready_delay_cycles = transaction.response_ready_delay;

        if (log_level >= 1)
            $display("[%0t][MASTER%0d][BEGIN] %s",
                     $time, master_index, transaction.sprint());

        case (transaction.operation)
            transaction_t::AXI_WRITE: begin
                write_transaction(
                    transaction.id, transaction.address, transaction.size,
                    transaction.burst, transaction.lock, transaction.qos,
                    transaction.data_queue, transaction.strobe_queue, response);
            end
            transaction_t::AXI_READ: begin
                read_transaction(
                    transaction.id, transaction.address, transaction.len,
                    transaction.size, transaction.burst, transaction.lock,
                    transaction.qos, read_data, response);
            end
            default: $fatal(1, "%s: unsupported transaction operation",
                            instance_name);
        endcase

        if (log_level >= 1)
            $display("[%0t][MASTER%0d][END] op=%s id=%0h resp=%0h read_beats=%0d",
                     $time, master_index,
                     transaction.operation == transaction_t::AXI_WRITE ?
                         "WRITE" : "READ",
                     transaction.id, response, read_data.size());
    endtask

    task automatic execute_write_then_read(
        input transaction_t write_request,
        output logic [1:0] write_response,
        output logic [1:0] read_response
    );
        transaction_t read_request = new();
        data_t ignored_write_readback[$];
        data_t read_data[$];

        if (write_request.operation != transaction_t::AXI_WRITE)
            $fatal(1, "%s: write/read sequence requires a WRITE",
                   instance_name);

        execute_transaction(write_request, write_response,
                            ignored_write_readback);
        if (!write_response[1]) begin
            read_request.copy_address_phase(write_request);
            read_request.operation = transaction_t::AXI_READ;
            read_request.lock = 1'b0;
            read_request.response_ready_delay = $urandom_range(10, 0);
            execute_transaction(read_request, read_response, read_data);
        end
    endtask

    task automatic execute_exclusive_success(
        input transaction_t write_request,
        output logic [1:0] read_response,
        output logic [1:0] write_response
    );
        transaction_t read_request = new();
        data_t read_data[$];
        data_t ignored_write_readback[$];

        if (write_request.operation != transaction_t::AXI_WRITE)
            $fatal(1, "%s: exclusive sequence requires a WRITE",
                   instance_name);

        write_request.lock = 1'b1;
        write_request.burst = 2'b01;
        read_request.copy_address_phase(write_request);
        read_request.operation = transaction_t::AXI_READ;
        read_request.lock = 1'b1;

        execute_transaction(read_request, read_response, read_data);
        execute_transaction(write_request, write_response,
                            ignored_write_readback);
    endtask


    task automatic wait_for_reset_release();
        wait (vif.ARESETn === 1'b1);
        @(posedge vif.ACLK);
    endtask

    task automatic wait_cycles(input int unsigned cycles);
        repeat (cycles) @(posedge vif.ACLK);
    endtask

    virtual task drive_idle();
        vif.awid    <= '0;
        vif.awaddr  <= '0;
        vif.awlen   <= '0;
        vif.awsize  <= '0;
        vif.awburst <= 2'b01;
        vif.awlock  <= 1'b0;
        vif.awcache <= '0;
        vif.awprot  <= '0;
        vif.awqos   <= '0;
        vif.awvalid <= 1'b0;
        vif.wdata   <= '0;
        vif.wstrb   <= '0;
        vif.wlast   <= 1'b0;
        vif.wvalid  <= 1'b0;
        vif.bready  <= 1'b0;
        vif.arid    <= '0;
        vif.araddr  <= '0;
        vif.arlen   <= '0;
        vif.arsize  <= '0;
        vif.arburst <= 2'b01;
        vif.arlock  <= 1'b0;
        vif.arcache <= '0;
        vif.arprot  <= '0;
        vif.arqos   <= '0;
        vif.arvalid <= 1'b0;
        vif.rready  <= 1'b0;
    endtask

    task automatic drive_aw(
        input logic [ID_WIDTH-1:0] id,
        input logic [ADDR_WIDTH-1:0] address,
        input logic [7:0] len,
        input logic [2:0] size,
        input logic [1:0] burst,
        input logic lock,
        input logic [3:0] qos
    );
        wait_cycles(request_gap_cycles);
        @(negedge vif.ACLK);
        vif.awid <= id;
        vif.awaddr <= address;
        vif.awlen <= len;
        vif.awsize <= size;
        vif.awburst <= burst;
        vif.awlock <= lock;
        vif.awcache <= '0;
        vif.awprot <= '0;
        vif.awqos <= qos;
        vif.awvalid <= 1'b1;
        do @(posedge vif.ACLK); while (!(vif.awvalid && vif.awready));
        @(negedge vif.ACLK);
        vif.awvalid <= 1'b0;
    endtask

    task automatic drive_w_beat(
        input data_t data,
        input strb_t strobe,
        input logic last
    );
        wait_cycles(write_beat_gap_cycles);
        @(negedge vif.ACLK);
        vif.wdata <= data;
        vif.wstrb <= strobe;
        vif.wlast <= last;
        vif.wvalid <= 1'b1;
        do @(posedge vif.ACLK); while (!(vif.wvalid && vif.wready));
        @(negedge vif.ACLK);
        vif.wvalid <= 1'b0;
        vif.wlast <= 1'b0;
    endtask

    task automatic drive_w_burst(
        input data_t data_queue[$],
        input strb_t strobe_queue[$]
    );
        if ((data_queue.size() == 0) ||
            (data_queue.size() != strobe_queue.size()))
            $fatal(1, "%s: invalid W burst arrays", instance_name);
        foreach (data_queue[beat])
            drive_w_beat(data_queue[beat], strobe_queue[beat],
                         beat == data_queue.size()-1);
    endtask

    task automatic wait_b(
        output logic [ID_WIDTH-1:0] id,
        output logic [1:0] response
    );
        wait_cycles(bready_delay_cycles);
        @(negedge vif.ACLK);
        vif.bready <= 1'b1;
        do @(posedge vif.ACLK); while (!(vif.bvalid && vif.bready));
        id = vif.bid;
        response = vif.bresp;
        @(negedge vif.ACLK);
        vif.bready <= 1'b0;
    endtask

    task automatic drive_ar(
        input logic [ID_WIDTH-1:0] id,
        input logic [ADDR_WIDTH-1:0] address,
        input logic [7:0] len,
        input logic [2:0] size,
        input logic [1:0] burst,
        input logic lock,
        input logic [3:0] qos
    );
        wait_cycles(request_gap_cycles);
        @(negedge vif.ACLK);
        vif.arid <= id;
        vif.araddr <= address;
        vif.arlen <= len;
        vif.arsize <= size;
        vif.arburst <= burst;
        vif.arlock <= lock;
        vif.arcache <= '0;
        vif.arprot <= '0;
        vif.arqos <= qos;
        vif.arvalid <= 1'b1;
        do @(posedge vif.ACLK); while (!(vif.arvalid && vif.arready));
        @(negedge vif.ACLK);
        vif.arvalid <= 1'b0;
    endtask

    task automatic collect_r(
        output data_t data_queue[$],
        output logic [ID_WIDTH-1:0] id,
        output logic [1:0] final_response
    );
        data_queue.delete();
        wait_cycles(rready_delay_cycles);
        @(negedge vif.ACLK);
        vif.rready <= 1'b1;
        forever begin
            @(posedge vif.ACLK);
            if (vif.rvalid && vif.rready) begin
                id = vif.rid;
                final_response = vif.rresp;
                data_queue.push_back(vif.rdata);
                if (vif.rlast) break;
            end
        end
        @(negedge vif.ACLK);
        vif.rready <= 1'b0;
    endtask

    task automatic write_transaction(
        input logic [ID_WIDTH-1:0] id,
        input logic [ADDR_WIDTH-1:0] address,
        input logic [2:0] size,
        input logic [1:0] burst,
        input logic lock,
        input logic [3:0] qos,
        input data_t data_queue[$],
        input strb_t strobe_queue[$],
        output logic [1:0] response
    );
        logic [ID_WIDTH-1:0] response_id;
        logic [7:0] len;
        if (data_queue.size() == 0 || data_queue.size() > 256)
            $fatal(1, "%s: illegal write burst length", instance_name);
        len = data_queue.size()-1;
        fork
            drive_aw(id, address, len, size, burst, lock, qos);
            drive_w_burst(data_queue, strobe_queue);
        join
        wait_b(response_id, response);
        if (response_id !== id)
            $error("%s: BID mismatch expected=%0h actual=%0h",
                   instance_name, id, response_id);
    endtask

    task automatic read_transaction(
        input logic [ID_WIDTH-1:0] id,
        input logic [ADDR_WIDTH-1:0] address,
        input logic [7:0] len,
        input logic [2:0] size,
        input logic [1:0] burst,
        input logic lock,
        input logic [3:0] qos,
        output data_t data_queue[$],
        output logic [1:0] response
    );
        logic [ID_WIDTH-1:0] response_id;
        drive_ar(id, address, len, size, burst, lock, qos);
        collect_r(data_queue, response_id, response);
        if (response_id !== id)
            $error("%s: RID mismatch expected=%0h actual=%0h",
                   instance_name, id, response_id);
    endtask

    task automatic exclusive_read_write(
        input logic [ID_WIDTH-1:0] id,
        input logic [ADDR_WIDTH-1:0] address,
        input logic [2:0] size,
        input logic [1:0] burst,
        input logic [3:0] qos,
        input data_t write_data[$],
        input strb_t write_strobe[$],
        output logic [1:0] read_response,
        output logic [1:0] write_response
    );
        data_t read_data[$];
        read_transaction(id, address, write_data.size()-1, size, burst,
                         1'b1, qos, read_data, read_response);
        write_transaction(id, address, size, burst, 1'b1, qos,
                          write_data, write_strobe, write_response);
    endtask

    virtual task run();
        drive_idle();
        wait_for_reset_release();
        configure_behavior();
        generate_traffic();
    endtask
endclass


class Slave #(
    parameter int ADDR_WIDTH = 32,
    parameter int DATA_WIDTH = 32,
    parameter int ID_WIDTH   = 4,
    parameter int STRB_WIDTH = DATA_WIDTH / 8
);
    typedef virtual axi_slave_bfm_if #(
        ADDR_WIDTH, DATA_WIDTH, ID_WIDTH, STRB_WIDTH
    ) slave_vif_t;
    typedef logic [DATA_WIDTH-1:0] data_t;
    typedef logic [STRB_WIDTH-1:0] strb_t;
    typedef struct packed {
        logic [ID_WIDTH-1:0] id;
        logic [ADDR_WIDTH-1:0] address;
        logic [7:0] len;
        logic [2:0] size;
        logic [1:0] burst;
        logic lock;
    } address_request_t;

    int unsigned slave_index;
    string       instance_name;
    slave_vif_t  vif;
    int unsigned log_level;
    bit          ideal_timing;
    byte unsigned memory [longint unsigned];

    rand int unsigned awready_delay_cycles;
    rand int unsigned wready_delay_cycles;
    rand int unsigned bresp_delay_cycles;
    rand int unsigned arready_delay_cycles;
    rand int unsigned rdata_delay_cycles;
    rand int unsigned read_beat_gap_cycles;
    rand int unsigned error_response_percent;
    rand bit          support_exclusive;

    constraint legal_slave_profile {
        awready_delay_cycles inside {[0:32]};
        wready_delay_cycles inside {[0:32]};
        bresp_delay_cycles inside {[0:64]};
        arready_delay_cycles inside {[0:32]};
        rdata_delay_cycles inside {[0:64]};
        read_beat_gap_cycles inside {[0:16]};
        error_response_percent inside {[0:100]};
    }

    function new(
        int unsigned slave_index,
        slave_vif_t vif,
        string instance_name = "slave"
    );
        this.slave_index = slave_index;
        this.vif = vif;
        this.instance_name = instance_name;
        log_level = 1;
        ideal_timing = 0;
        awready_delay_cycles = 0;
        wready_delay_cycles = 0;
        bresp_delay_cycles = 0;
        arready_delay_cycles = 0;
        rdata_delay_cycles = 0;
        read_beat_gap_cycles = 0;
        error_response_percent = 0;
        support_exclusive = 1;
    endfunction

    virtual task configure_behavior();
        case (slave_index)
            0: begin
                // Fast memory-like slave.
                awready_delay_cycles = 0;
                wready_delay_cycles = 0;
                bresp_delay_cycles = 1;
                arready_delay_cycles = 0;
                rdata_delay_cycles = 1;
                read_beat_gap_cycles = 0;
                error_response_percent = 0;
                support_exclusive = 1;
            end
            1: begin
                // Medium-latency peripheral/memory slave.
                awready_delay_cycles = 2;
                wready_delay_cycles = 1;
                bresp_delay_cycles = 3;
                arready_delay_cycles = 2;
                rdata_delay_cycles = 3;
                read_beat_gap_cycles = 1;
                error_response_percent = 0;
                support_exclusive = 1;
            end
            default: begin
                // Slow slave used to exercise sustained backpressure.
                awready_delay_cycles = 5;
                wready_delay_cycles = 3;
                bresp_delay_cycles = 8;
                arready_delay_cycles = 4;
                rdata_delay_cycles = 6;
                read_beat_gap_cycles = 2;
                error_response_percent = 0;
                support_exclusive = 1;
            end
        endcase
    endtask

    virtual task before_write(input address_request_t request);
        // USER: Optional peripheral side effect before a write burst.
    endtask

    virtual task after_write(input address_request_t request);
        // USER: Optional peripheral side effect after a write burst.
    endtask

    virtual task before_read(input address_request_t request);
        // USER: Optional peripheral side effect before a read burst.
    endtask

    virtual function logic [1:0] select_bresp(input address_request_t request);
        if ($urandom_range(99, 0) < error_response_percent)
            return 2'b10;
        return 2'b00;
    endfunction

    virtual function logic [1:0] select_rresp(
        input address_request_t request,
        input int unsigned beat
    );
        if ($urandom_range(99, 0) < error_response_percent)
            return 2'b10;
        return 2'b00;
    endfunction

    function automatic logic [ADDR_WIDTH-1:0] beat_address(
        input address_request_t request,
        input int unsigned beat
    );
        longint unsigned beat_bytes;
        longint unsigned total_bytes;
        longint unsigned wrap_base;
        longint unsigned offset;
        beat_bytes = 64'(1) << request.size;
        total_bytes = (longint'(request.len) + 1) * beat_bytes;
        case (request.burst)
            2'b00: beat_address = request.address;
            2'b10: begin
                wrap_base = (longint'(request.address) / total_bytes) * total_bytes;
                offset = (longint'(request.address) - wrap_base + beat*beat_bytes)
                         % total_bytes;
                beat_address = wrap_base + offset;
            end
            default: beat_address = request.address + beat*beat_bytes;
        endcase
    endfunction

    function automatic data_t read_memory_beat(
        input logic [ADDR_WIDTH-1:0] address
    );
        data_t result;
        result = '0;
        for (int unsigned byte_lane=0; byte_lane<STRB_WIDTH; byte_lane++) begin
            if (memory.exists(longint'(address) + byte_lane))
                result[byte_lane*8 +: 8] =
                    memory[longint'(address) + byte_lane];
        end
        return result;
    endfunction

    function automatic void write_memory_beat(
        input logic [ADDR_WIDTH-1:0] address,
        input data_t data,
        input strb_t strobe
    );
        for (int unsigned byte_lane=0; byte_lane<STRB_WIDTH; byte_lane++) begin
            if (strobe[byte_lane])
                memory[longint'(address) + byte_lane] =
                    data[byte_lane*8 +: 8];
        end
    endfunction

    task automatic wait_for_reset_release();
        wait (vif.ARESETn === 1'b1);
        @(posedge vif.ACLK);
    endtask

    task automatic wait_cycles(input int unsigned cycles);
        repeat (cycles) @(posedge vif.ACLK);
    endtask

    virtual task drive_idle();
        vif.awready <= 1'b0;
        vif.wready  <= 1'b0;
        vif.bid     <= '0;
        vif.bresp   <= '0;
        vif.bvalid  <= 1'b0;
        vif.arready <= 1'b0;
        vif.rid     <= '0;
        vif.rdata   <= '0;
        vif.rresp   <= '0;
        vif.rlast   <= 1'b0;
        vif.rvalid  <= 1'b0;
    endtask

    task automatic accept_aw(output address_request_t request);
        wait_cycles(awready_delay_cycles);
        @(negedge vif.ACLK);
        vif.awready <= 1'b1;
        do @(posedge vif.ACLK); while (!(vif.awvalid && vif.awready));
        request.id = vif.awid;
        request.address = vif.awaddr;
        request.len = vif.awlen;
        request.size = vif.awsize;
        request.burst = vif.awburst;
        request.lock = vif.awlock;
        if (log_level >= 1)
            $display("[%0t][SLAVE%0d][AW] id=%0h addr=%0h len=%0d burst=%0b lock=%0b",
                     $time, slave_index, request.id, request.address,
                     request.len, request.burst, request.lock);
        @(negedge vif.ACLK);
        vif.awready <= 1'b0;
    endtask

    task automatic accept_w_burst(
        input address_request_t request,
        output data_t data_queue[$],
        output strb_t strobe_queue[$]
    );
        data_queue.delete();
        strobe_queue.delete();

        // The ideal timing profile keeps WREADY asserted for the complete
        // burst. This permits one accepted beat per cycle and removes BFM
        // bubbles from controller performance measurements.
        if (ideal_timing) begin
            @(negedge vif.ACLK);
            vif.wready <= 1'b1;
            for (int unsigned beat=0; beat<=request.len; beat++) begin
                do @(posedge vif.ACLK); while (!(vif.wvalid && vif.wready));
                data_queue.push_back(vif.wdata);
                strobe_queue.push_back(vif.wstrb);
                if (log_level >= 2)
                    $display("[%0t][SLAVE%0d][W] beat=%0d data=%0h strb=%0h last=%0b",
                             $time, slave_index, beat, vif.wdata,
                             vif.wstrb, vif.wlast);
                if (vif.wlast != (beat == request.len))
                    $error("%s: WLAST mismatch at beat %0d", instance_name, beat);
            end
            @(negedge vif.ACLK);
            vif.wready <= 1'b0;
            return;
        end

        for (int unsigned beat=0; beat<=request.len; beat++) begin
            wait_cycles(wready_delay_cycles);
            @(negedge vif.ACLK);
            vif.wready <= 1'b1;
            do @(posedge vif.ACLK); while (!(vif.wvalid && vif.wready));
            data_queue.push_back(vif.wdata);
            strobe_queue.push_back(vif.wstrb);
            if (log_level >= 2)
                $display("[%0t][SLAVE%0d][W] beat=%0d data=%0h strb=%0h last=%0b",
                         $time, slave_index, beat, vif.wdata,
                         vif.wstrb, vif.wlast);
            if (vif.wlast != (beat == request.len))
                $error("%s: WLAST mismatch at beat %0d", instance_name, beat);
            @(negedge vif.ACLK);
            vif.wready <= 1'b0;
        end
    endtask

    task automatic send_b(
        input logic [ID_WIDTH-1:0] id,
        input logic [1:0] response
    );
        wait_cycles(bresp_delay_cycles);
        @(negedge vif.ACLK);
        vif.bid <= id;
        vif.bresp <= response;
        vif.bvalid <= 1'b1;
        do @(posedge vif.ACLK); while (!(vif.bvalid && vif.bready));
        @(negedge vif.ACLK);
        vif.bvalid <= 1'b0;
    endtask

    task automatic accept_ar(output address_request_t request);
        wait_cycles(arready_delay_cycles);
        @(negedge vif.ACLK);
        vif.arready <= 1'b1;
        do @(posedge vif.ACLK); while (!(vif.arvalid && vif.arready));
        request.id = vif.arid;
        request.address = vif.araddr;
        request.len = vif.arlen;
        request.size = vif.arsize;
        request.burst = vif.arburst;
        request.lock = vif.arlock;
        if (log_level >= 1)
            $display("[%0t][SLAVE%0d][AR] id=%0h addr=%0h len=%0d burst=%0b lock=%0b",
                     $time, slave_index, request.id, request.address,
                     request.len, request.burst, request.lock);
        @(negedge vif.ACLK);
        vif.arready <= 1'b0;
    endtask

    task automatic send_r_burst(input address_request_t request);
        logic [ADDR_WIDTH-1:0] address;
        wait_cycles(rdata_delay_cycles);

        // In ideal mode RVALID remains asserted between beats. Payload is
        // advanced on each falling edge after the preceding handshake, so a
        // ready master observes one R transfer per clock cycle.
        if (ideal_timing) begin
            for (int unsigned beat=0; beat<=request.len; beat++) begin
                address = beat_address(request, beat);
                @(negedge vif.ACLK);
                vif.rid <= request.id;
                vif.rdata <= read_memory_beat(address);
                vif.rresp <= select_rresp(request, beat);
                vif.rlast <= (beat == request.len);
                vif.rvalid <= 1'b1;
                do @(posedge vif.ACLK); while (!(vif.rvalid && vif.rready));
            end
            @(negedge vif.ACLK);
            vif.rvalid <= 1'b0;
            vif.rlast <= 1'b0;
            return;
        end

        for (int unsigned beat=0; beat<=request.len; beat++) begin
            wait_cycles(read_beat_gap_cycles);
            address = beat_address(request, beat);
            @(negedge vif.ACLK);
            vif.rid <= request.id;
            vif.rdata <= read_memory_beat(address);
            vif.rresp <= select_rresp(request, beat);
            vif.rlast <= (beat == request.len);
            vif.rvalid <= 1'b1;
            do @(posedge vif.ACLK); while (!(vif.rvalid && vif.rready));
            @(negedge vif.ACLK);
            vif.rvalid <= 1'b0;
            vif.rlast <= 1'b0;
        end
    endtask

    task automatic write_worker();
        address_request_t request;
        data_t data_queue[$];
        strb_t strobe_queue[$];
        logic [1:0] response;
        forever begin
            accept_aw(request);
            before_write(request);
            accept_w_burst(request, data_queue, strobe_queue);
            response = select_bresp(request);
            if (response inside {2'b00, 2'b01}) begin
                foreach (data_queue[beat])
                    write_memory_beat(beat_address(request, beat),
                                      data_queue[beat], strobe_queue[beat]);
            end
            after_write(request);
            send_b(request.id, response);
            if (log_level >= 1)
                $display("[%0t][SLAVE%0d][B] id=%0h resp=%0h",
                         $time, slave_index, request.id, response);
        end
    endtask

    task automatic read_worker();
        address_request_t request;
        forever begin
            accept_ar(request);
            before_read(request);
            send_r_burst(request);
            if (log_level >= 1)
                $display("[%0t][SLAVE%0d][R-DONE] id=%0h beats=%0d",
                         $time, slave_index, request.id, request.len + 1);
        end
    endtask

    virtual task run();
        drive_idle();
        wait_for_reset_release();
        configure_behavior();
        fork
            write_worker();
            read_worker();
        join
    endtask
endclass

`endif
