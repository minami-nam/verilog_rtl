module addr_decoder #(
    parameter int ADDR_WIDTH  = 32,
    parameter int NUM_MASTER  = 3,
    parameter int NUM_SLAVE   = 3,
    parameter int SLAVE_WIDTH = (NUM_SLAVE <= 1) ? 1 : $clog2(NUM_SLAVE),
    parameter logic [NUM_SLAVE*ADDR_WIDTH-1:0] BASE_ADDR = '0,
    parameter logic [NUM_SLAVE*ADDR_WIDTH-1:0] END_ADDR  = '0
) (
    input  wire [NUM_MASTER*ADDR_WIDTH-1:0]  s_axi_awaddr,
    input  wire [NUM_MASTER*ADDR_WIDTH-1:0]  s_axi_araddr,
    output wire [NUM_MASTER*SLAVE_WIDTH-1:0] s_axi_awtarget,
    output wire [NUM_MASTER*SLAVE_WIDTH-1:0] s_axi_artarget
);

    // function [ADDR_WIDTH-1:0] boundary_value;
    //     input integer index;
    //     begin
    //         case (index)
    //             0: boundary_value = 32'hF000_0000;
    //             1: boundary_value = 32'hA000_0000;
    //             2: boundary_value = 32'h4000_0000;
    //             default: boundary_value = {ADDR_WIDTH{1'b0}};
    //         endcase
    //     end
    // endfunction

    function automatic [ADDR_WIDTH-1:0] get_addr_base;
        input integer index;
        begin
            get_addr_base = BASE_ADDR[index*ADDR_WIDTH +: ADDR_WIDTH];
        end
    endfunction

    function automatic [ADDR_WIDTH-1:0] get_addr_end;
        input integer index;
        begin
            get_addr_end = END_ADDR[index*ADDR_WIDTH +: ADDR_WIDTH];
        end
    endfunction

    function automatic [SLAVE_WIDTH-1:0] decode_address;
        input [ADDR_WIDTH-1:0] address;
        integer index;
        logic found;

        logic [ADDR_WIDTH-1:0] base_addr;
        logic [ADDR_WIDTH-1:0] end_addr;
        begin
            decode_address = '0;
            found = 1'b0;

            for (index=1; index<NUM_SLAVE; index=index+1) begin
                base_addr = get_addr_base(index);
                end_addr = get_addr_end(index);

                if (!found&&(address >= base_addr)&&(address <= end_addr)) begin
                    decode_address = SLAVE_WIDTH'(index);   // 폭 맞추는 것임.
                    found = 1'b1;
                end

            end
        end
    endfunction

    genvar master_index;
    generate
        for (master_index=0; master_index<NUM_MASTER; master_index=master_index+1) begin : gen_decode
            assign s_axi_awtarget[master_index*SLAVE_WIDTH +: SLAVE_WIDTH] =
                decode_address(s_axi_awaddr[master_index*ADDR_WIDTH +: ADDR_WIDTH]);
            assign s_axi_artarget[master_index*SLAVE_WIDTH +: SLAVE_WIDTH] =
                decode_address(s_axi_araddr[master_index*ADDR_WIDTH +: ADDR_WIDTH]);
        end
    endgenerate

endmodule
