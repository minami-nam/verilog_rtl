module exclusive_monitor #(
    parameter int NUM_MASTER    = 3,
    parameter int NUM_SLAVE     = 3,
    parameter int ADDR_WIDTH    = 32,
    parameter int ID_WIDTH      = 4,
    parameter int LEN_WIDTH     = 8,
    parameter int SIZE_WIDTH    = 3,
    parameter int BURST_WIDTH   = 2,
    parameter int MASTER_WIDTH  = (NUM_MASTER <= 1) ? 1 : $clog2(NUM_MASTER)
) (
    input wire ACLK,
    input wire ARESETn,

    // Register a reservation when an exclusive AR transaction is accepted.
    input wire [NUM_SLAVE*MASTER_WIDTH-1:0] reserve_master,
    input wire [NUM_SLAVE*ID_WIDTH-1:0]     reserve_id,
    input wire [NUM_SLAVE*ADDR_WIDTH-1:0]   reserve_addr,
    input wire [NUM_SLAVE*LEN_WIDTH-1:0]    reserve_len,
    input wire [NUM_SLAVE*SIZE_WIDTH-1:0]   reserve_size,
    input wire [NUM_SLAVE*BURST_WIDTH-1:0]  reserve_burst,
    input wire [NUM_SLAVE-1:0]              reserve_valid,

    // Registered check result. It remains stable until result_ready.
    input  wire [NUM_SLAVE*MASTER_WIDTH-1:0] check_master,
    input  wire [NUM_SLAVE*ID_WIDTH-1:0]     check_id,
    input  wire [NUM_SLAVE*ADDR_WIDTH-1:0]   check_addr,
    input  wire [NUM_SLAVE*LEN_WIDTH-1:0]    check_len,
    input  wire [NUM_SLAVE*SIZE_WIDTH-1:0]   check_size,
    input  wire [NUM_SLAVE*BURST_WIDTH-1:0]  check_burst,
    input  wire [NUM_SLAVE-1:0]              check_valid,
    output wire [NUM_SLAVE-1:0]              check_ready,
    output wire [NUM_SLAVE-1:0]              result_valid,
    output wire [NUM_SLAVE-1:0]              exclusive_success,
    input  wire [NUM_SLAVE-1:0]              result_ready,

    // A completed write is treated as an address-range value change.
    input wire [NUM_SLAVE*ADDR_WIDTH-1:0] write_commit_addr,
    input wire [NUM_SLAVE*LEN_WIDTH-1:0]  write_commit_len,
    input wire [NUM_SLAVE*SIZE_WIDTH-1:0] write_commit_size,
    input wire [NUM_SLAVE*BURST_WIDTH-1:0] write_commit_burst,
    input wire [NUM_SLAVE-1:0]            write_commit_valid
);

    reg [NUM_MASTER-1:0] reservation_valid;
    reg [ID_WIDTH-1:0] reservation_id [0:NUM_MASTER-1];
    reg [ADDR_WIDTH-1:0] reservation_first [0:NUM_MASTER-1];
    reg [ADDR_WIDTH-1:0] reservation_last [0:NUM_MASTER-1];
    reg [ADDR_WIDTH-1:0] reservation_start [0:NUM_MASTER-1];
    reg [BURST_WIDTH-1:0] reservation_burst [0:NUM_MASTER-1];

    reg [NUM_SLAVE-1:0] result_valid_reg;
    reg [NUM_SLAVE-1:0] success_reg;

    assign check_ready = ~result_valid_reg;
    assign result_valid = result_valid_reg;
    assign exclusive_success = success_reg;

    function [ADDR_WIDTH-1:0] first_address;
        input [ADDR_WIDTH-1:0] address;
        input [LEN_WIDTH-1:0] len;
        input [SIZE_WIDTH-1:0] size;
        input [BURST_WIDTH-1:0] burst;
        reg [ADDR_WIDTH:0] transfer_bytes;
        reg [ADDR_WIDTH-1:0] wrap_mask;
        begin
            transfer_bytes = ({1'b0, len} + 1'b1) << size;
            wrap_mask = transfer_bytes[ADDR_WIDTH-1:0] - 1'b1;
            case (burst)    // wrap인 경우 
                2'b10: first_address = address & ~wrap_mask;
                default: first_address = address;
            endcase
        end
    endfunction

    function [ADDR_WIDTH-1:0] last_address;
        input [ADDR_WIDTH-1:0] address;
        input [LEN_WIDTH-1:0] len;
        input [SIZE_WIDTH-1:0] size;
        input [BURST_WIDTH-1:0] burst;
        reg [ADDR_WIDTH:0] transfer_bytes;
        reg [ADDR_WIDTH:0] beat_bytes;
        reg [ADDR_WIDTH-1:0] range_first;
        begin
            transfer_bytes = ({1'b0, len} + 1'b1) << size;
            beat_bytes = {{ADDR_WIDTH{1'b0}}, 1'b1} << size;
            range_first = first_address(address, len, size, burst);
            case (burst)
                2'b00: last_address = address + beat_bytes - 1'b1;
                default: last_address = range_first + transfer_bytes - 1'b1;
            endcase
        end
    endfunction

    function ranges_overlap;
        input [ADDR_WIDTH-1:0] first_a;
        input [ADDR_WIDTH-1:0] last_a;
        input [ADDR_WIDTH-1:0] first_b;
        input [ADDR_WIDTH-1:0] last_b;
        begin
            ranges_overlap = (first_a <= last_b) && (first_b <= last_a);
        end
    endfunction

    integer master_index;
    integer lane_index;
    integer conflict_index;
    reg [MASTER_WIDTH-1:0] event_master;
    reg [ADDR_WIDTH-1:0] event_first;
    reg [ADDR_WIDTH-1:0] event_last;
    reg write_conflict;

    always @(posedge ACLK or negedge ARESETn) begin
        if (!ARESETn) begin
            reservation_valid <= '0;
            result_valid_reg <= '0;
            success_reg <= '0;
            for (master_index=0; master_index<NUM_MASTER; master_index=master_index+1) begin
                reservation_id[master_index] <= '0;
                reservation_first[master_index] <= '0;
                reservation_last[master_index] <= '0;
                reservation_start[master_index] <= '0;
                reservation_burst[master_index] <= '0;
            end
        end
        else begin
            // Exclusive read establishes or replaces that master's reservation.
            for (lane_index=0; lane_index<NUM_SLAVE; lane_index=lane_index+1) begin
                if (reserve_valid[lane_index]) begin
                    event_master = reserve_master[lane_index*MASTER_WIDTH +: MASTER_WIDTH];
                    reservation_valid[event_master] <= 1'b1;
                    reservation_id[event_master] <= reserve_id[lane_index*ID_WIDTH +: ID_WIDTH];
                    reservation_start[event_master] <=
                        reserve_addr[lane_index*ADDR_WIDTH +: ADDR_WIDTH];
                    reservation_burst[event_master] <=
                        reserve_burst[lane_index*BURST_WIDTH +: BURST_WIDTH];
                    reservation_first[event_master] <= first_address(
                        reserve_addr[lane_index*ADDR_WIDTH +: ADDR_WIDTH],
                        reserve_len[lane_index*LEN_WIDTH +: LEN_WIDTH],
                        reserve_size[lane_index*SIZE_WIDTH +: SIZE_WIDTH],
                        reserve_burst[lane_index*BURST_WIDTH +: BURST_WIDTH]);
                    reservation_last[event_master] <= last_address(
                        reserve_addr[lane_index*ADDR_WIDTH +: ADDR_WIDTH],
                        reserve_len[lane_index*LEN_WIDTH +: LEN_WIDTH],
                        reserve_size[lane_index*SIZE_WIDTH +: SIZE_WIDTH],
                        reserve_burst[lane_index*BURST_WIDTH +: BURST_WIDTH]);
                end
            end

            
            for (lane_index=0; lane_index<NUM_SLAVE; lane_index=lane_index+1) begin
                if (result_valid_reg[lane_index] && result_ready[lane_index])
                    result_valid_reg[lane_index] <= 1'b0;

                if (check_valid[lane_index] && check_ready[lane_index]) begin
                    event_master = check_master[lane_index*MASTER_WIDTH +: MASTER_WIDTH];
                    event_first = first_address(
                        check_addr[lane_index*ADDR_WIDTH +: ADDR_WIDTH],
                        check_len[lane_index*LEN_WIDTH +: LEN_WIDTH],
                        check_size[lane_index*SIZE_WIDTH +: SIZE_WIDTH],
                        check_burst[lane_index*BURST_WIDTH +: BURST_WIDTH]);
                    event_last = last_address(
                        check_addr[lane_index*ADDR_WIDTH +: ADDR_WIDTH],
                        check_len[lane_index*LEN_WIDTH +: LEN_WIDTH],
                        check_size[lane_index*SIZE_WIDTH +: SIZE_WIDTH],
                        check_burst[lane_index*BURST_WIDTH +: BURST_WIDTH]);


                    write_conflict = 1'b0;
                    for (conflict_index=0; conflict_index<NUM_SLAVE;
                         conflict_index=conflict_index+1) begin
                        if (write_commit_valid[conflict_index] && ranges_overlap(
                            event_first, event_last,
                            first_address(
                                write_commit_addr[conflict_index*ADDR_WIDTH +: ADDR_WIDTH],
                                write_commit_len[conflict_index*LEN_WIDTH +: LEN_WIDTH],
                                write_commit_size[conflict_index*SIZE_WIDTH +: SIZE_WIDTH],
                                write_commit_burst[conflict_index*BURST_WIDTH +: BURST_WIDTH]),
                            last_address(
                                write_commit_addr[conflict_index*ADDR_WIDTH +: ADDR_WIDTH],
                                write_commit_len[conflict_index*LEN_WIDTH +: LEN_WIDTH],
                                write_commit_size[conflict_index*SIZE_WIDTH +: SIZE_WIDTH],
                                write_commit_burst[conflict_index*BURST_WIDTH +: BURST_WIDTH])))
                            write_conflict = 1'b1;
                    end

                    success_reg[lane_index] <=
                        reservation_valid[event_master] &&
                        (reservation_id[event_master] ==
                            check_id[lane_index*ID_WIDTH +: ID_WIDTH]) &&
                        (reservation_start[event_master] ==
                            check_addr[lane_index*ADDR_WIDTH +: ADDR_WIDTH]) &&
                        (reservation_burst[event_master] ==
                            check_burst[lane_index*BURST_WIDTH +: BURST_WIDTH]) &&
                        (reservation_first[event_master] == event_first) &&
                        (reservation_last[event_master] == event_last) &&
                        !write_conflict;
                    result_valid_reg[lane_index] <= 1'b1;
                    reservation_valid[event_master] <= 1'b0;
                end
            end

            // Any completed overlapping write invalidates a reservation.
            for (lane_index=0; lane_index<NUM_SLAVE; lane_index=lane_index+1) begin
                if (write_commit_valid[lane_index]) begin
                    event_first = first_address(
                        write_commit_addr[lane_index*ADDR_WIDTH +: ADDR_WIDTH],
                        write_commit_len[lane_index*LEN_WIDTH +: LEN_WIDTH],
                        write_commit_size[lane_index*SIZE_WIDTH +: SIZE_WIDTH],
                        write_commit_burst[lane_index*BURST_WIDTH +: BURST_WIDTH]);
                    event_last = last_address(
                        write_commit_addr[lane_index*ADDR_WIDTH +: ADDR_WIDTH],
                        write_commit_len[lane_index*LEN_WIDTH +: LEN_WIDTH],
                        write_commit_size[lane_index*SIZE_WIDTH +: SIZE_WIDTH],
                        write_commit_burst[lane_index*BURST_WIDTH +: BURST_WIDTH]);
                    for (master_index=0; master_index<NUM_MASTER; master_index=master_index+1) begin
                        if (reservation_valid[master_index] && ranges_overlap(
                            reservation_first[master_index], reservation_last[master_index],
                            event_first, event_last)) begin
                            reservation_valid[master_index] <= 1'b0;
                        end
                    end
                end
            end
        end
    end

endmodule
