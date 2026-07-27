`ifndef TB_SCENARIOS_SVH
`define TB_SCENARIOS_SVH

// This is the primary user-editable file. Protocol legality and AXI channel
// handshakes remain in AxiTransaction and Master/Slave parent classes.
class ScenarioMaster #(
    parameter int ADDR_WIDTH = 32,
    parameter int DATA_WIDTH = 32,
    parameter int ID_WIDTH   = 4,
    parameter int STRB_WIDTH = DATA_WIDTH / 8
) extends Master #(ADDR_WIDTH, DATA_WIDTH, ID_WIDTH, STRB_WIDTH);
    typedef virtual axi_master_bfm_if #(
        ADDR_WIDTH, DATA_WIDTH, ID_WIDTH, STRB_WIDTH
    ) scenario_master_vif_t;
    typedef AxiTransaction #(
        ADDR_WIDTH, DATA_WIDTH, ID_WIDTH, STRB_WIDTH
    ) transaction_t;

    function new(
        int unsigned master_index,
        scenario_master_vif_t vif,
        string instance_name = "scenario_master"
    );
        super.new(master_index, vif, instance_name);
    endfunction

    virtual task configure_behavior();
        // 0=off, 1=transaction/channel summary, 2=include every W beat.
        log_level = 1;
        case (master_index)
            0: begin
                default_qos = $urandom_range(15, 12);
                request_gap_cycles = 1;
            end
            1: begin
                default_qos = $urandom_range(8, 5);
                request_gap_cycles = 4;
            end
            default: begin
                default_qos = $urandom_range(3, 0);
                request_gap_cycles = 8;
            end
        endcase
    endtask

    virtual task build_scenario();
        transaction_t write_request;
        logic [1:0] write_response;
        logic [1:0] read_response;
        int unsigned transaction_count;
        bit randomize_ok;

        // USER SCENARIO CONTROL: number of write->read pairs per master.
        transaction_count = 30;

        // A small random phase offset keeps simultaneous masters realistic
        // while preserving heavy contention at common slave ports.
        wait_cycles($urandom_range(3, 0));

        for (int unsigned transaction=0;
             transaction<transaction_count; transaction++) begin
            write_request = new();
            write_request.force_operation = 1;
            write_request.configured_operation = transaction_t::AXI_WRITE;
            write_request.force_target = 1;
            write_request.force_lock = 1;
            write_request.configured_lock = 0;
            write_request.force_qos = 1;
            write_request.configured_qos = default_qos;
            write_request.limit_max_len = 1;
            write_request.configured_max_len = 15;

            case (transaction % 3)
                0: write_request.configured_target =
                       transaction_t::TARGET_SLAVE0;
                1: write_request.configured_target =
                       transaction_t::TARGET_SLAVE1;
                default: write_request.configured_target =
                       transaction_t::TARGET_SLAVE2;
            endcase

            randomize_ok = write_request.randomize();
            if (randomize_ok == 0)
                $fatal(1, "%s: normal transaction randomization failed",
                       instance_name);

            execute_write_then_read(
                write_request, write_response, read_response);
        end

        // Example correlated scenario: only Master 2 performs one exclusive
        // read followed by a matching exclusive write.
        if ((master_index == 2) && allow_exclusive) begin
            write_request = new();
            write_request.force_operation = 1;
            write_request.configured_operation = transaction_t::AXI_WRITE;
            write_request.force_target = 1;
            write_request.configured_target = transaction_t::TARGET_SLAVE2;
            write_request.force_lock = 1;
            write_request.configured_lock = 1;
            write_request.force_qos = 1;
            write_request.configured_qos = default_qos;
            write_request.force_burst = 1;
            write_request.configured_burst = 2'b01;
            write_request.force_len = 1;
            write_request.configured_len = 0;

            randomize_ok = write_request.randomize();
            if (randomize_ok == 0)
                $fatal(1, "%s: exclusive transaction randomization failed",
                       instance_name);

            execute_exclusive_success(
                write_request, read_response, write_response);
            $display("[%s] exclusive RRESP=%0h BRESP=%0h",
                     instance_name, read_response, write_response);
        end
    endtask

endclass


class ScenarioSlave #(
    parameter int ADDR_WIDTH = 32,
    parameter int DATA_WIDTH = 32,
    parameter int ID_WIDTH   = 4,
    parameter int STRB_WIDTH = DATA_WIDTH / 8
) extends Slave #(ADDR_WIDTH, DATA_WIDTH, ID_WIDTH, STRB_WIDTH);
    typedef virtual axi_slave_bfm_if #(
        ADDR_WIDTH, DATA_WIDTH, ID_WIDTH, STRB_WIDTH
    ) scenario_slave_vif_t;

    function new(
        int unsigned slave_index,
        scenario_slave_vif_t vif,
        string instance_name = "scenario_slave"
    );
        super.new(slave_index, vif, instance_name);
    endfunction

    virtual task configure_behavior();
        // 0=off, 1=transaction/channel summary, 2=include every W beat.
        log_level = 1;

        // Controller performance baseline: all slaves use identical ideal
        // timing, so measured differences come from the DUT rather than BFM
        // random backpressure. Set this to 0 and configure the delays below
        // when running deterministic or stress profiles.
        ideal_timing = 1;
        awready_delay_cycles = 0;
        wready_delay_cycles = 0;
        bresp_delay_cycles = 0;
        arready_delay_cycles = 0;
        rdata_delay_cycles = 0;
        read_beat_gap_cycles = 0;

        // USER SCENARIO CONTROL: enable after normal-path regressions pass.
        error_response_percent = 0;
        support_exclusive = 1;
    endtask
endclass

`endif
