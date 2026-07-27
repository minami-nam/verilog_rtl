module axi4_full_memory #(
    parameter int AXI_ADDR_WIDTH = 32,
    parameter int AXI_DATA_WIDTH = 64,
    parameter int AXI_ID_WIDTH = 4,
    parameter int AXI_STRB_WIDTH = AXI_DATA_WIDTH / 8,
    parameter int MEM_BYTES = 64 * 1024,
    parameter logic [AXI_ADDR_WIDTH-1:0] BASE_ADDR = '0,
    parameter bit ZERO_INIT = 1'b1,
    parameter string INIT_FILE = ""
)(
    input  logic ACLK,
    input  logic ARESETn,

    // AXI4 Full slave write-address channel
    input  logic [AXI_ID_WIDTH-1:0]   s_axi_awid,
    input  logic [AXI_ADDR_WIDTH-1:0] s_axi_awaddr,
    input  logic [7:0]                s_axi_awlen,
    input  logic [2:0]                s_axi_awsize,
    input  logic [1:0]                s_axi_awburst,
    input  logic                      s_axi_awlock,
    input  logic [3:0]                s_axi_awcache,
    input  logic [2:0]                s_axi_awprot,
    input  logic [3:0]                s_axi_awqos,
    input  logic                      s_axi_awvalid,
    output logic                      s_axi_awready,

    // AXI4 Full slave write-data channel
    input  logic [AXI_DATA_WIDTH-1:0] s_axi_wdata,
    input  logic [AXI_STRB_WIDTH-1:0] s_axi_wstrb,
    input  logic                      s_axi_wlast,
    input  logic                      s_axi_wvalid,
    output logic                      s_axi_wready,

    // AXI4 Full slave write-response channel
    output logic [AXI_ID_WIDTH-1:0] s_axi_bid,
    output logic [1:0]              s_axi_bresp,
    output logic                    s_axi_bvalid,
    input  logic                    s_axi_bready,

    // AXI4 Full slave read-address channel
    input  logic [AXI_ID_WIDTH-1:0]   s_axi_arid,
    input  logic [AXI_ADDR_WIDTH-1:0] s_axi_araddr,
    input  logic [7:0]                s_axi_arlen,
    input  logic [2:0]                s_axi_arsize,
    input  logic [1:0]                s_axi_arburst,
    input  logic                      s_axi_arlock,
    input  logic [3:0]                s_axi_arcache,
    input  logic [2:0]                s_axi_arprot,
    input  logic [3:0]                s_axi_arqos,
    input  logic                      s_axi_arvalid,
    output logic                      s_axi_arready,

    // AXI4 Full slave read-data channel
    output logic [AXI_ID_WIDTH-1:0]   s_axi_rid,
    output logic [AXI_DATA_WIDTH-1:0] s_axi_rdata,
    output logic [1:0]                s_axi_rresp,
    output logic                      s_axi_rlast,
    output logic                      s_axi_rvalid,
    input  logic                      s_axi_rready
);
    localparam int DATA_BYTES = AXI_DATA_WIDTH / 8;
    localparam logic [2:0] FULL_SIZE = $clog2(DATA_BYTES);

    localparam logic [1:0] RESP_OKAY   = 2'b00;
    localparam logic [1:0] RESP_SLVERR = 2'b10;
    localparam logic [1:0] RESP_DECERR = 2'b11;
    localparam logic [1:0] BURST_FIXED = 2'b00;
    localparam logic [1:0] BURST_INCR  = 2'b01;

    // Byte-addressed storage makes WSTRB behavior explicit.
    logic [7:0] mem [0:MEM_BYTES-1];

    logic read_active;
    logic [AXI_ADDR_WIDTH-1:0] read_addr_reg;
    logic [7:0] read_len_reg;
    logic [7:0] read_beat_reg;
    logic [1:0] read_burst_reg;
    logic [1:0] read_response_reg;

    logic write_active;
    logic [AXI_ADDR_WIDTH-1:0] write_addr_reg;
    logic [7:0] write_len_reg;
    logic [7:0] write_beat_reg;
    logic [1:0] write_burst_reg;
    logic [AXI_ID_WIDTH-1:0] write_id_reg;
    logic [1:0] write_response_reg;

    function automatic logic address_is_valid(
        input logic [AXI_ADDR_WIDTH-1:0] address
    );
        logic [AXI_ADDR_WIDTH:0] offset;
        begin
            offset = {1'b0, address} - {1'b0, BASE_ADDR};
            address_is_valid =
                (address >= BASE_ADDR) &&
                ((offset + DATA_BYTES) <= MEM_BYTES);
        end
    endfunction

    function automatic logic [1:0] address_response(
        input logic [AXI_ADDR_WIDTH-1:0] address
    );
        begin
            if (address_is_valid(address))
                address_response = RESP_OKAY;
            else
                address_response = RESP_DECERR;
        end
    endfunction

    function automatic logic [1:0] merge_response(
        input logic [1:0] first_response,
        input logic [1:0] second_response
    );
        begin
            if ((first_response == RESP_DECERR) ||
                (second_response == RESP_DECERR))
                merge_response = RESP_DECERR;
            else if ((first_response != RESP_OKAY) ||
                     (second_response != RESP_OKAY))
                merge_response = RESP_SLVERR;
            else
                merge_response = RESP_OKAY;
        end
    endfunction

    function automatic logic [1:0] command_response(
        input logic [AXI_ADDR_WIDTH-1:0] address,
        input logic [7:0] length,
        input logic [2:0] size,
        input logic [1:0] burst,
        input logic lock
    );
        integer unsigned burst_byte_count;
        integer unsigned page_offset;
        begin
            burst_byte_count = (length + 1) * DATA_BYTES;
            page_offset = address % 4096;

            if (size != FULL_SIZE)
                command_response = RESP_SLVERR;
            else if ((burst != BURST_FIXED) && (burst != BURST_INCR))
                command_response = RESP_SLVERR;
            else if (lock)
                command_response = RESP_SLVERR;
            else if ((address % DATA_BYTES) != 0)
                command_response = RESP_SLVERR;
            else if (!address_is_valid(address))
                command_response = RESP_DECERR;
            else if ((burst == BURST_INCR) &&
                     ((page_offset + burst_byte_count) > 4096))
                command_response = RESP_SLVERR;
            else
                command_response = RESP_OKAY;
        end
    endfunction

    function automatic logic [AXI_DATA_WIDTH-1:0] read_memory_word(
        input logic [AXI_ADDR_WIDTH-1:0] address
    );
        integer byte_lane;
        integer unsigned memory_index;
        begin
            read_memory_word = '0;

            if (address_is_valid(address)) begin
                memory_index = address - BASE_ADDR;

                for (byte_lane = 0;
                     byte_lane < DATA_BYTES;
                     byte_lane = byte_lane + 1)
                    read_memory_word[byte_lane*8 +: 8] =
                        mem[memory_index + byte_lane];
            end
        end
    endfunction

    integer init_index;
    initial begin
        if ((AXI_DATA_WIDTH % 8) != 0)
            $error("AXI_DATA_WIDTH must be a multiple of 8");
        if ((DATA_BYTES & (DATA_BYTES - 1)) != 0)
            $error("AXI_DATA_WIDTH/8 must be a power of two");
        if (AXI_STRB_WIDTH != DATA_BYTES)
            $error("AXI_STRB_WIDTH must equal AXI_DATA_WIDTH/8");
        if (MEM_BYTES < DATA_BYTES)
            $error("MEM_BYTES must hold at least one AXI beat");

        if (ZERO_INIT) begin
            for (init_index = 0;
                 init_index < MEM_BYTES;
                 init_index = init_index + 1)
                mem[init_index] = '0;
        end

        if (INIT_FILE != "")
            $readmemh(INIT_FILE, mem);
    end

    assign s_axi_arready = !read_active && !s_axi_rvalid;

    always @(posedge ACLK or negedge ARESETn) begin
        if (!ARESETn) begin
            read_active <= 1'b0;
            read_addr_reg <= '0;
            read_len_reg <= '0;
            read_beat_reg <= '0;
            read_burst_reg <= BURST_INCR;
            read_response_reg <= RESP_OKAY;

            s_axi_rid <= '0;
            s_axi_rdata <= '0;
            s_axi_rresp <= RESP_OKAY;
            s_axi_rlast <= 1'b0;
            s_axi_rvalid <= 1'b0;
        end
        else begin
            if (s_axi_arvalid && s_axi_arready) begin
                read_active <= 1'b1;
                read_addr_reg <= s_axi_araddr;
                read_len_reg <= s_axi_arlen;
                read_beat_reg <= '0;
                read_burst_reg <= s_axi_arburst;
                read_response_reg <= command_response(
                    s_axi_araddr,
                    s_axi_arlen,
                    s_axi_arsize,
                    s_axi_arburst,
                    s_axi_arlock
                );

                s_axi_rid <= s_axi_arid;
                s_axi_rdata <= read_memory_word(s_axi_araddr);
                s_axi_rresp <= command_response(
                    s_axi_araddr,
                    s_axi_arlen,
                    s_axi_arsize,
                    s_axi_arburst,
                    s_axi_arlock
                );
                s_axi_rlast <= (s_axi_arlen == 0);
                s_axi_rvalid <= 1'b1;
            end
            else if (s_axi_rvalid && s_axi_rready) begin
                if (s_axi_rlast) begin
                    read_active <= 1'b0;
                    s_axi_rvalid <= 1'b0;
                    s_axi_rlast <= 1'b0;
                end
                else begin
                    read_beat_reg <= read_beat_reg + 1'b1;
                    s_axi_rlast <=
                        ((read_beat_reg + 1'b1) == read_len_reg);

                    if (read_burst_reg == BURST_INCR) begin
                        read_addr_reg <= read_addr_reg + DATA_BYTES;
                        s_axi_rdata <=
                            read_memory_word(read_addr_reg + DATA_BYTES);
                        s_axi_rresp <= merge_response(
                            read_response_reg,
                            address_response(read_addr_reg + DATA_BYTES)
                        );
                    end
                    else begin
                        s_axi_rdata <= read_memory_word(read_addr_reg);
                        s_axi_rresp <= merge_response(
                            read_response_reg,
                            address_response(read_addr_reg)
                        );
                    end
                end
            end
        end
    end

    assign s_axi_awready = !write_active && !s_axi_bvalid;
    assign s_axi_wready = write_active && !s_axi_bvalid;

    integer write_byte_lane;
    always @(posedge ACLK or negedge ARESETn) begin
        if (!ARESETn) begin
            write_active <= 1'b0;
            write_addr_reg <= '0;
            write_len_reg <= '0;
            write_beat_reg <= '0;
            write_burst_reg <= BURST_INCR;
            write_id_reg <= '0;
            write_response_reg <= RESP_OKAY;

            s_axi_bid <= '0;
            s_axi_bresp <= RESP_OKAY;
            s_axi_bvalid <= 1'b0;
        end
        else begin
            if (s_axi_bvalid && s_axi_bready)
                s_axi_bvalid <= 1'b0;

            if (s_axi_awvalid && s_axi_awready) begin
                write_active <= 1'b1;
                write_addr_reg <= s_axi_awaddr;
                write_len_reg <= s_axi_awlen;
                write_beat_reg <= '0;
                write_burst_reg <= s_axi_awburst;
                write_id_reg <= s_axi_awid;
                write_response_reg <= command_response(
                    s_axi_awaddr,
                    s_axi_awlen,
                    s_axi_awsize,
                    s_axi_awburst,
                    s_axi_awlock
                );
            end

            if (s_axi_wvalid && s_axi_wready) begin
                if ((write_response_reg == RESP_OKAY) &&
                    (address_response(write_addr_reg) == RESP_OKAY)) begin
                    for (write_byte_lane = 0;
                         write_byte_lane < DATA_BYTES;
                         write_byte_lane = write_byte_lane + 1) begin
                        if (s_axi_wstrb[write_byte_lane])
                            mem[(write_addr_reg - BASE_ADDR) + write_byte_lane]
                                <= s_axi_wdata[write_byte_lane*8 +: 8];
                    end
                end

                if (s_axi_wlast ||
                    (write_beat_reg == write_len_reg)) begin
                    write_active <= 1'b0;
                    s_axi_bid <= write_id_reg;
                    s_axi_bresp <= merge_response(
                        merge_response(
                            write_response_reg,
                            address_response(write_addr_reg)
                        ),
                        (s_axi_wlast ==
                         (write_beat_reg == write_len_reg))
                            ? RESP_OKAY : RESP_SLVERR
                    );
                    s_axi_bvalid <= 1'b1;
                end
                else begin
                    write_beat_reg <= write_beat_reg + 1'b1;
                    write_response_reg <= merge_response(
                        write_response_reg,
                        address_response(write_addr_reg)
                    );

                    if (write_burst_reg == BURST_INCR)
                        write_addr_reg <= write_addr_reg + DATA_BYTES;
                end
            end
        end
    end

endmodule
