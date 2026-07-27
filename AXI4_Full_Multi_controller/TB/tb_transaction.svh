`ifndef TB_TRANSACTION_SVH
`define TB_TRANSACTION_SVH

class AxiTransaction #(
    parameter int ADDR_WIDTH = 32,
    parameter int DATA_WIDTH = 32,
    parameter int ID_WIDTH   = 4,
    parameter int STRB_WIDTH = DATA_WIDTH / 8
);
    typedef enum logic {
        AXI_READ,
        AXI_WRITE
    } operation_t;

    typedef enum logic [1:0] {
        TARGET_SLAVE0 = 2'd0,
        TARGET_SLAVE1 = 2'd1,
        TARGET_SLAVE2 = 2'd2
    } target_t;

    typedef logic [DATA_WIDTH-1:0] data_t;
    typedef logic [STRB_WIDTH-1:0] strb_t;

    rand operation_t operation;
    rand target_t target;
    rand logic [ID_WIDTH-1:0] id;
    rand logic [ADDR_WIDTH-1:0] address;
    rand logic [7:0] len;
    rand logic [2:0] size;
    rand logic [1:0] burst;
    rand logic lock;
    rand logic [3:0] qos;
    rand int unsigned request_gap;
    rand int unsigned response_ready_delay;

    data_t data_queue[$];
    strb_t strobe_queue[$];

    // Scenario knobs: set these before randomize() instead of using inline
    // constraints. This also avoids XSim inline-constraint elaboration bugs.
    bit force_operation;
    bit force_target;
    bit force_lock;
    bit force_qos;
    bit force_burst;
    bit force_len;
    bit limit_max_len;
    operation_t configured_operation;
    target_t configured_target;
    logic configured_lock;
    logic [3:0] configured_qos;
    logic [1:0] configured_burst;
    logic [7:0] configured_len;
    logic [7:0] configured_max_len;

    constraint legal_operation {
        operation inside {AXI_READ, AXI_WRITE};
    }

    constraint scenario_overrides {
        if (force_operation) operation == configured_operation;
        if (force_target) target == configured_target;
        if (force_lock) lock == configured_lock;
        if (force_qos) qos == configured_qos;
        if (force_burst) burst == configured_burst;
        if (force_len) len == configured_len;
        if (limit_max_len) len <= configured_max_len;
    }

    constraint legal_target {
        target inside {TARGET_SLAVE0, TARGET_SLAVE1, TARGET_SLAVE2};
    }

    constraint legal_transfer_size {
        size == $clog2(STRB_WIDTH);
    }

    constraint legal_burst {
        burst inside {2'b00, 2'b01, 2'b10};

        if (burst == 2'b00)
            len inside {[0:3]};

        if (burst == 2'b01)
            len inside {[0:15]};

        if (burst == 2'b10)
            len inside {1, 3, 7, 15};
    }

    constraint aligned_address {
        address % (1 << size) == 0;
    }

    constraint mapped_address {
        if (target == TARGET_SLAVE0)
            address inside {[32'hA000_0000:32'hA00F_FFFC]};

        if (target == TARGET_SLAVE1)
            address inside {[32'h4000_0000:32'h400F_FFFC]};

        if (target == TARGET_SLAVE2)
            address inside {[32'h0001_0000:32'h000F_FFFC]};
    }

    constraint legal_exclusive {
        if (lock) {
            burst == 2'b01;
            len inside {0, 1, 3, 7, 15};
        }
    }

    constraint default_distribution {
        operation dist {
            AXI_WRITE := 55,
            AXI_READ  := 45
        };

        target dist {
            TARGET_SLAVE0 := 60,
            TARGET_SLAVE1 := 25,
            TARGET_SLAVE2 := 15
        };

        burst dist {
            2'b00 := 10,
            2'b01 := 75,
            2'b10 := 15
        };

        qos dist {
            [0:3]   := 30,
            [4:11]  := 50,
            [12:15] := 20
        };

        request_gap dist {
            0      := 40,
            [1:3]  := 40,
            [4:10] := 20
        };

        response_ready_delay inside {[0:10]};
    }

    function new();
        clear_scenario_overrides();
    endfunction

    function void clear_scenario_overrides();
        force_operation = 0;
        force_target = 0;
        force_lock = 0;
        force_qos = 0;
        force_burst = 0;
        force_len = 0;
        limit_max_len = 0;
        configured_operation = AXI_READ;
        configured_target = TARGET_SLAVE0;
        configured_lock = 0;
        configured_qos = 0;
        configured_burst = 2'b01;
        configured_len = 0;
        configured_max_len = 8'hff;
    endfunction

    function void post_randomize();
        data_t random_data;
        strb_t random_strobe;

        data_queue.delete();
        strobe_queue.delete();

        if (operation == AXI_WRITE) begin
            repeat (len + 1) begin
                random_data = data_t'($urandom());
                random_strobe = strb_t'($urandom());
                if (random_strobe == '0)
                    random_strobe = {STRB_WIDTH{1'b1}};
                data_queue.push_back(random_data);
                strobe_queue.push_back(random_strobe);
            end
        end
    endfunction

    function void copy_address_phase(input AxiTransaction source);
        id = source.id;
        target = source.target;
        address = source.address;
        len = source.len;
        size = source.size;
        burst = source.burst;
        lock = source.lock;
        qos = source.qos;
        request_gap = source.request_gap;
        response_ready_delay = source.response_ready_delay;
    endfunction

    function string sprint();
        return $sformatf(
            "op=%s target=%0d id=%0h addr=%0h len=%0d size=%0d burst=%0b lock=%0b qos=%0d",
            operation == AXI_WRITE ? "WRITE" : "READ",
            target, id, address, len, size, burst, lock, qos);
    endfunction
endclass

`endif
