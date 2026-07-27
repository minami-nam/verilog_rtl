`ifndef TB_SCOREBOARD_SVH
`define TB_SCOREBOARD_SVH

class AxiObservedTransaction #(
    parameter int ADDR_WIDTH = 32,
    parameter int DATA_WIDTH = 32,
    parameter int ID_WIDTH   = 4,
    parameter int STRB_WIDTH = DATA_WIDTH / 8
);
    int unsigned master;
    int unsigned slave;
    logic [ID_WIDTH-1:0] id;
    logic [ADDR_WIDTH-1:0] address;
    logic [7:0] len;
    logic [2:0] size;
    logic [1:0] burst;
    logic lock;
    logic [3:0] qos;
    longint unsigned accepted_cycle;
    longint unsigned issued_cycle;
    longint unsigned completed_cycle;
    int unsigned beat_index;
    logic [DATA_WIDTH-1:0] data_queue[$];
    logic [STRB_WIDTH-1:0] strobe_queue[$];
endclass


class AxiObservedBeat #(
    parameter int DATA_WIDTH = 32,
    parameter int ID_WIDTH   = 4,
    parameter int STRB_WIDTH = DATA_WIDTH / 8
);
    logic [ID_WIDTH-1:0] id;
    logic [DATA_WIDTH-1:0] data;
    logic [STRB_WIDTH-1:0] strobe;
    logic [1:0] response;
    logic last;
    longint unsigned transaction_start_cycle;
endclass


class ControllerScoreboard #(
    parameter int NUM_MASTER = 3,
    parameter int NUM_SLAVE  = 3,
    parameter int ADDR_WIDTH = 32,
    parameter int DATA_WIDTH = 32,
    parameter int ID_WIDTH   = 4,
    parameter int STRB_WIDTH = DATA_WIDTH / 8,
    parameter int AGE_WIDTH  = 10
);
    typedef AxiObservedTransaction #(
        ADDR_WIDTH, DATA_WIDTH, ID_WIDTH, STRB_WIDTH
    ) transaction_t;
    typedef AxiObservedBeat #(
        DATA_WIDTH, ID_WIDTH, STRB_WIDTH
    ) beat_t;

    transaction_t pending_aw [NUM_MASTER][$];
    transaction_t pending_ar [NUM_MASTER][$];
    transaction_t active_write [NUM_SLAVE][$];
    transaction_t active_read [NUM_SLAVE][$];
    transaction_t pending_b [NUM_MASTER][$];
    beat_t expected_w [NUM_MASTER][$];
    beat_t expected_r [NUM_MASTER][$];

    byte unsigned reference_memory [longint unsigned];

    longint unsigned current_cycle;
    longint unsigned aw_schedule_latency_sum;
    longint unsigned ar_schedule_latency_sum;
    longint unsigned write_latency_sum;
    longint unsigned read_latency_sum;
    longint unsigned aw_schedule_latency_max;
    longint unsigned ar_schedule_latency_max;
    longint unsigned write_latency_max;
    longint unsigned read_latency_max;
    longint unsigned max_aw_age;
    longint unsigned max_ar_age;
    int unsigned aw_issue_count;
    int unsigned ar_issue_count;
    int unsigned write_count;
    int unsigned read_count;
    int unsigned data_check_count;
    int unsigned protocol_error_count;
    int unsigned data_error_count;
    int unsigned aging_error_count;
    int unsigned arbitration_check_count;
    int unsigned arbitration_error_count;

    bit aw_age_initialized [NUM_MASTER];
    bit ar_age_initialized [NUM_MASTER];
    bit aw_previous_valid [NUM_MASTER];
    bit ar_previous_valid [NUM_MASTER];
    bit aw_previous_ready [NUM_MASTER];
    bit ar_previous_ready [NUM_MASTER];
    logic [AGE_WIDTH-1:0] aw_previous_age [NUM_MASTER];
    logic [AGE_WIDTH-1:0] ar_previous_age [NUM_MASTER];

    function new();
        reset_statistics();
    endfunction

    function void reset_statistics();
        current_cycle = 0;
        aw_schedule_latency_sum = 0;
        ar_schedule_latency_sum = 0;
        write_latency_sum = 0;
        read_latency_sum = 0;
        aw_schedule_latency_max = 0;
        ar_schedule_latency_max = 0;
        write_latency_max = 0;
        read_latency_max = 0;
        max_aw_age = 0;
        max_ar_age = 0;
        aw_issue_count = 0;
        ar_issue_count = 0;
        write_count = 0;
        read_count = 0;
        data_check_count = 0;
        protocol_error_count = 0;
        data_error_count = 0;
        aging_error_count = 0;
        arbitration_check_count = 0;
        arbitration_error_count = 0;
        foreach (aw_age_initialized[index]) begin
            aw_age_initialized[index] = 0;
            ar_age_initialized[index] = 0;
        end
    endfunction

    function automatic logic [ADDR_WIDTH-1:0] beat_address(
        input transaction_t transaction,
        input int unsigned beat
    );
        longint unsigned beat_bytes;
        longint unsigned total_bytes;
        longint unsigned wrap_base;
        longint unsigned offset;
        beat_bytes = 64'(1) << transaction.size;
        total_bytes = (longint'(transaction.len) + 1) * beat_bytes;
        case (transaction.burst)
            2'b00: beat_address = transaction.address;
            2'b10: begin
                wrap_base = (longint'(transaction.address) / total_bytes) * total_bytes;
                offset = (longint'(transaction.address) - wrap_base + beat*beat_bytes)
                         % total_bytes;
                beat_address = wrap_base + offset;
            end
            default: beat_address = transaction.address + beat*beat_bytes;
        endcase
    endfunction

    function automatic logic [DATA_WIDTH-1:0] reference_read(
        input logic [ADDR_WIDTH-1:0] address
    );
        logic [DATA_WIDTH-1:0] result;
        result = '0;
        for (int unsigned byte_lane=0; byte_lane<STRB_WIDTH; byte_lane++) begin
            if (reference_memory.exists(longint'(address) + byte_lane))
                result[byte_lane*8 +: 8] =
                    reference_memory[longint'(address) + byte_lane];
        end
        return result;
    endfunction

    function automatic void reference_write(
        input logic [ADDR_WIDTH-1:0] address,
        input logic [DATA_WIDTH-1:0] data,
        input logic [STRB_WIDTH-1:0] strobe
    );
        for (int unsigned byte_lane=0; byte_lane<STRB_WIDTH; byte_lane++) begin
            if (strobe[byte_lane])
                reference_memory[longint'(address) + byte_lane] =
                    data[byte_lane*8 +: 8];
        end
    endfunction

    function void tick();
        current_cycle++;
    endfunction

    function void observe_master_aw(
        input int unsigned master,
        input logic [ID_WIDTH-1:0] id,
        input logic [ADDR_WIDTH-1:0] address,
        input logic [7:0] len,
        input logic [2:0] size,
        input logic [1:0] burst,
        input logic lock,
        input logic [3:0] qos
    );
        transaction_t transaction = new();
        transaction.master = master;
        transaction.id = id;
        transaction.address = address;
        transaction.len = len;
        transaction.size = size;
        transaction.burst = burst;
        transaction.lock = lock;
        transaction.qos = qos;
        transaction.accepted_cycle = current_cycle;
        transaction.beat_index = 0;
        pending_aw[master].push_back(transaction);
    endfunction

    function void observe_master_w(
        input int unsigned master,
        input logic [DATA_WIDTH-1:0] data,
        input logic [STRB_WIDTH-1:0] strobe,
        input logic last
    );
        beat_t beat = new();
        beat.data = data;
        beat.strobe = strobe;
        beat.last = last;
        expected_w[master].push_back(beat);
    endfunction

    function void observe_master_ar(
        input int unsigned master,
        input logic [ID_WIDTH-1:0] id,
        input logic [ADDR_WIDTH-1:0] address,
        input logic [7:0] len,
        input logic [2:0] size,
        input logic [1:0] burst,
        input logic lock,
        input logic [3:0] qos
    );
        transaction_t transaction = new();
        transaction.master = master;
        transaction.id = id;
        transaction.address = address;
        transaction.len = len;
        transaction.size = size;
        transaction.burst = burst;
        transaction.lock = lock;
        transaction.qos = qos;
        transaction.accepted_cycle = current_cycle;
        transaction.beat_index = 0;
        pending_ar[master].push_back(transaction);
    endfunction

    function void observe_slave_aw(
        input int unsigned slave,
        input int unsigned source_master,
        input logic [ID_WIDTH-1:0] id,
        input logic [ADDR_WIDTH-1:0] address,
        input logic [7:0] len,
        input logic [2:0] size,
        input logic [1:0] burst,
        input logic lock
    );
        transaction_t transaction;
        longint unsigned latency;
        if (source_master >= NUM_MASTER || pending_aw[source_master].size() == 0) begin
            protocol_error_count++;
            $error("SB: slave%0d AW has no master request", slave);
            return;
        end
        transaction = pending_aw[source_master].pop_front();
        if (transaction.id !== id || transaction.address !== address ||
            transaction.len !== len || transaction.size !== size ||
            transaction.burst !== burst || transaction.lock !== lock) begin
            protocol_error_count++;
            $error("SB: AW payload mismatch master%0d -> slave%0d",
                   source_master, slave);
        end
        transaction.slave = slave;
        transaction.issued_cycle = current_cycle;
        transaction.beat_index = 0;
        active_write[slave].push_back(transaction);
        latency = current_cycle - transaction.accepted_cycle;
        aw_schedule_latency_sum += latency;
        if (latency > aw_schedule_latency_max) aw_schedule_latency_max = latency;
        aw_issue_count++;
    endfunction

    function void observe_slave_w(
        input int unsigned slave,
        input logic [DATA_WIDTH-1:0] data,
        input logic [STRB_WIDTH-1:0] strobe,
        input logic last
    );
        transaction_t transaction;
        beat_t expected;
        if (active_write[slave].size() == 0) begin
            protocol_error_count++;
            $error("SB: slave%0d W has no AW context", slave);
            return;
        end
        transaction = active_write[slave][0];
        if (expected_w[transaction.master].size() == 0) begin
            protocol_error_count++;
            $error("SB: slave%0d W has no master data", slave);
            return;
        end
        expected = expected_w[transaction.master].pop_front();
        data_check_count++;
        if (expected.data !== data || expected.strobe !== strobe ||
            expected.last !== last) begin
            data_error_count++;
            $error("SB: W mismatch master%0d -> slave%0d beat%0d",
                   transaction.master, slave, transaction.beat_index);
        end
        transaction.data_queue.push_back(data);
        transaction.strobe_queue.push_back(strobe);
        transaction.beat_index++;
    endfunction

    function void observe_slave_b(
        input int unsigned slave,
        input logic [ID_WIDTH-1:0] id,
        input logic [1:0] response
    );
        transaction_t transaction;
        if (active_write[slave].size() == 0) begin
            protocol_error_count++;
            $error("SB: slave%0d B has no write context", slave);
            return;
        end
        transaction = active_write[slave].pop_front();
        if (transaction.id !== id) begin
            protocol_error_count++;
            $error("SB: BID mismatch at slave%0d", slave);
        end
        if (!response[1]) begin
            foreach (transaction.data_queue[beat])
                reference_write(beat_address(transaction, beat),
                                transaction.data_queue[beat],
                                transaction.strobe_queue[beat]);
        end
        transaction.completed_cycle = current_cycle;
        pending_b[transaction.master].push_back(transaction);
    endfunction

    function void observe_master_b(
        input int unsigned master,
        input logic [ID_WIDTH-1:0] id,
        input logic [1:0] response
    );
        transaction_t transaction;
        longint unsigned latency;
        logic [1:0] expected_response;
        if (pending_b[master].size() != 0) begin
            transaction = pending_b[master].pop_front();
            expected_response = transaction.lock ? 2'b01 : 2'b00;
            if (transaction.id !== id ||
                (!response[1] && response !== expected_response)) begin
                protocol_error_count++;
                $error("SB: master%0d B mismatch ID=%0h RESP=%0h",
                       master, id, response);
            end
        end
        else if (pending_aw[master].size() != 0 && pending_aw[master][0].lock) begin
            // A failed exclusive write is consumed locally and never appears
            // on a slave AW/B channel.
            transaction = pending_aw[master].pop_front();
            if (response !== 2'b00) begin
                protocol_error_count++;
                $error("SB: failed exclusive write must return OKAY");
            end
            repeat (transaction.len + 1) begin
                if (expected_w[master].size() != 0)
                    void'(expected_w[master].pop_front());
            end
        end
        else begin
            protocol_error_count++;
            $error("SB: master%0d unexpected B response", master);
            return;
        end
        latency = current_cycle - transaction.accepted_cycle;
        write_latency_sum += latency;
        if (latency > write_latency_max) write_latency_max = latency;
        write_count++;
    endfunction

    function void observe_slave_ar(
        input int unsigned slave,
        input int unsigned source_master,
        input logic [ID_WIDTH-1:0] id,
        input logic [ADDR_WIDTH-1:0] address,
        input logic [7:0] len,
        input logic [2:0] size,
        input logic [1:0] burst,
        input logic lock
    );
        transaction_t transaction;
        longint unsigned latency;
        if (source_master >= NUM_MASTER || pending_ar[source_master].size() == 0) begin
            protocol_error_count++;
            $error("SB: slave%0d AR has no master request", slave);
            return;
        end
        transaction = pending_ar[source_master].pop_front();
        if (transaction.id !== id || transaction.address !== address ||
            transaction.len !== len || transaction.size !== size ||
            transaction.burst !== burst || transaction.lock !== lock) begin
            protocol_error_count++;
            $error("SB: AR payload mismatch master%0d -> slave%0d",
                   source_master, slave);
        end
        transaction.slave = slave;
        transaction.issued_cycle = current_cycle;
        transaction.beat_index = 0;
        active_read[slave].push_back(transaction);
        latency = current_cycle - transaction.accepted_cycle;
        ar_schedule_latency_sum += latency;
        if (latency > ar_schedule_latency_max) ar_schedule_latency_max = latency;
        ar_issue_count++;
    endfunction

    function void observe_slave_r(
        input int unsigned slave,
        input logic [ID_WIDTH-1:0] id,
        input logic [DATA_WIDTH-1:0] data,
        input logic [1:0] response,
        input logic last
    );
        transaction_t transaction;
        beat_t expected = new();
        logic [DATA_WIDTH-1:0] memory_data;
        if (active_read[slave].size() == 0) begin
            protocol_error_count++;
            $error("SB: slave%0d R has no AR context", slave);
            return;
        end
        transaction = active_read[slave][0];
        memory_data = reference_read(beat_address(transaction,
                                                   transaction.beat_index));
        if (!response[1] && data !== memory_data) begin
            data_error_count++;
            $error("SB: slave%0d memory data mismatch beat%0d expected=%0h actual=%0h",
                   slave, transaction.beat_index, memory_data, data);
        end
        expected.id = id;
        expected.data = data;
        expected.response = transaction.lock && response == 2'b00 ? 2'b01 : response;
        expected.last = last;
        expected.transaction_start_cycle = transaction.accepted_cycle;
        expected_r[transaction.master].push_back(expected);
        transaction.beat_index++;
        if (last) void'(active_read[slave].pop_front());
    endfunction

    function void observe_master_r(
        input int unsigned master,
        input logic [ID_WIDTH-1:0] id,
        input logic [DATA_WIDTH-1:0] data,
        input logic [1:0] response,
        input logic last
    );
        beat_t expected;
        longint unsigned latency;
        if (expected_r[master].size() == 0) begin
            protocol_error_count++;
            $error("SB: master%0d unexpected R beat", master);
            return;
        end
        expected = expected_r[master].pop_front();
        data_check_count++;
        if (expected.id !== id || expected.data !== data ||
            expected.response !== response || expected.last !== last) begin
            data_error_count++;
            $error("SB: R mismatch at master%0d", master);
        end
        if (last) begin
            latency = current_cycle - expected.transaction_start_cycle;
            read_latency_sum += latency;
            if (latency > read_latency_max) read_latency_max = latency;
            read_count++;
        end
    endfunction

    function void sample_aging(
        input bit write_channel,
        input int unsigned master,
        input bit valid,
        input bit ready,
        input logic [AGE_WIDTH-1:0] age
    );
        logic [AGE_WIDTH-1:0] expected_age;
        if (write_channel) begin
            if (aw_age_initialized[master]) begin
                if (!aw_previous_valid[master] || aw_previous_ready[master])
                    expected_age = '0;
                else if (&aw_previous_age[master])
                    expected_age = aw_previous_age[master];
                else
                    expected_age = aw_previous_age[master] + 1'b1;
                if (age !== expected_age) begin
                    aging_error_count++;
                    $error("SB: AW age mismatch master%0d expected=%0d actual=%0d",
                           master, expected_age, age);
                end
            end
            aw_age_initialized[master] = 1;
            aw_previous_valid[master] = valid;
            aw_previous_ready[master] = ready;
            aw_previous_age[master] = age;
            if (age > max_aw_age) max_aw_age = age;
        end
        else begin
            if (ar_age_initialized[master]) begin
                if (!ar_previous_valid[master] || ar_previous_ready[master])
                    expected_age = '0;
                else if (&ar_previous_age[master])
                    expected_age = ar_previous_age[master];
                else
                    expected_age = ar_previous_age[master] + 1'b1;
                if (age !== expected_age) begin
                    aging_error_count++;
                    $error("SB: AR age mismatch master%0d expected=%0d actual=%0d",
                           master, expected_age, age);
                end
            end
            ar_age_initialized[master] = 1;
            ar_previous_valid[master] = valid;
            ar_previous_ready[master] = ready;
            ar_previous_age[master] = age;
            if (age > max_ar_age) max_ar_age = age;
        end
    endfunction

    function void check_scheduler_grant(
        input bit write_channel,
        input int unsigned slave,
        input bit expected_valid,
        input int unsigned expected_master,
        input bit actual_valid,
        input int unsigned actual_master
    );
        arbitration_check_count++;
        if ((actual_valid !== expected_valid) ||
            (expected_valid && actual_master != expected_master)) begin
            arbitration_error_count++;
            $error("SB: %s grant mismatch slave%0d expected_valid=%0b expected_master=%0d actual_valid=%0b actual_master=%0d",
                   write_channel ? "AW" : "AR", slave, expected_valid,
                   expected_master, actual_valid, actual_master);
        end
    endfunction

    function void report();
        real aw_average;
        real ar_average;
        real write_average;
        real read_average;
        aw_average = aw_issue_count ? real'(aw_schedule_latency_sum)/aw_issue_count : 0.0;
        ar_average = ar_issue_count ? real'(ar_schedule_latency_sum)/ar_issue_count : 0.0;
        write_average = write_count ? real'(write_latency_sum)/write_count : 0.0;
        read_average = read_count ? real'(read_latency_sum)/read_count : 0.0;
        $display("\n========== Controller Scoreboard ==========");
        $display("Checks=%0d protocol_errors=%0d data_errors=%0d aging_errors=%0d",
                 data_check_count, protocol_error_count,
                 data_error_count, aging_error_count);
        $display("Arbitration checks=%0d errors=%0d",
                 arbitration_check_count, arbitration_error_count);
        $display("AW schedule latency: count=%0d avg=%0.2f max=%0d cycles",
                 aw_issue_count, aw_average, aw_schedule_latency_max);
        $display("AR schedule latency: count=%0d avg=%0.2f max=%0d cycles",
                 ar_issue_count, ar_average, ar_schedule_latency_max);
        $display("Write end-to-end: count=%0d avg=%0.2f max=%0d cycles",
                 write_count, write_average, write_latency_max);
        $display("Read end-to-end: count=%0d avg=%0.2f max=%0d cycles",
                 read_count, read_average, read_latency_max);
        $display("Maximum observed scheduler age: AW=%0d AR=%0d",
                 max_aw_age, max_ar_age);
        $display("===========================================\n");
    endfunction
endclass

`endif
