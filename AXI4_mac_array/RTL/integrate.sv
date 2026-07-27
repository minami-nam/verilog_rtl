module mac_array_top #(
    parameter int ARRAY_H_SIZE = 4,
    parameter int ARRAY_K_SIZE = 4,
    parameter int ARRAY_W_SIZE = 4,
    parameter int DATA_WIDTH_IN = 8,
    parameter int AXI_DATA_WIDTH = 64,
    parameter int AXI_STRB_WIDTH = AXI_DATA_WIDTH / 8
)(
    input  logic ACLK,
    input  logic ARESETn,

    // Top-level control/status
    input  logic clear,
    input  logic read_request,
    input  logic matrix_select,
    input  logic write_start,
    output logic a_loaded,
    output logic b_loaded,
    output logic read_error,
    output logic mac_clear_done,
    output logic result_buffer_full,
    output logic write_done,

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
    input  logic                      axi_wready
);
    localparam int ACC_WIDTH = 2 * DATA_WIDTH_IN;

    logic input_to_mac_valid;
    logic input_to_mac_ready;
    logic signed [DATA_WIDTH_IN-1:0] input_to_mac_a
        [0:ARRAY_H_SIZE-1];
    logic signed [DATA_WIDTH_IN-1:0] input_to_mac_b
        [0:ARRAY_W_SIZE-1];

    logic mac_to_output_valid;
    logic mac_to_output_ready;
    logic mac_to_output_last;
    logic signed [ACC_WIDTH-1:0] mac_to_output_data
        [0:ARRAY_W_SIZE-1];

    input_buffer_array #(
        .ARRAY_H_SIZE(ARRAY_H_SIZE),
        .ARRAY_K_SIZE(ARRAY_K_SIZE),
        .ARRAY_W_SIZE(ARRAY_W_SIZE),
        .DATA_WIDTH_IN(DATA_WIDTH_IN),
        .AXI_DATA_WIDTH(AXI_DATA_WIDTH)
    ) u_input_buffer_array (
        .ACLK(ACLK),
        .ARESETn(ARESETn),

        .request(read_request),
        .clear(clear),
        .matrix_select(matrix_select),
        .a_loaded(a_loaded),
        .b_loaded(b_loaded),
        .read_error(read_error),

        .axi_rdata(axi_rdata),
        .axi_rresp(axi_rresp),
        .axi_rlast(axi_rlast),
        .axi_rvalid(axi_rvalid),
        .axi_rready(axi_rready),

        .mac_valid(input_to_mac_valid),
        .mac_ready(input_to_mac_ready),
        .mac_a_data(input_to_mac_a),
        .mac_b_data(input_to_mac_b)
    );

    mac_array #(
        .ARRAY_H_SIZE(ARRAY_H_SIZE),
        .ARRAY_K_SIZE(ARRAY_K_SIZE),
        .ARRAY_W_SIZE(ARRAY_W_SIZE),
        .DATA_WIDTH_IN(DATA_WIDTH_IN)
    ) u_mac_array (
        .ACLK(ACLK),
        .ARESETn(ARESETn),
        .clear_request(clear),
        .clear_done(mac_clear_done),

        .i_valid(input_to_mac_valid),
        .i_ready(input_to_mac_ready),
        .i_a_data(input_to_mac_a),
        .i_b_data(input_to_mac_b),

        .o_valid(mac_to_output_valid),
        .o_ready(mac_to_output_ready),
        .o_last(mac_to_output_last),
        .o_data(mac_to_output_data)
    );

    output_buffer_array #(
        .ARRAY_H_SIZE(ARRAY_H_SIZE),
        .ARRAY_W_SIZE(ARRAY_W_SIZE),
        .DATA_WIDTH_IN(DATA_WIDTH_IN),
        .ACC_WIDTH(ACC_WIDTH),
        .AXI_DATA_WIDTH(AXI_DATA_WIDTH),
        .AXI_STRB_WIDTH(AXI_STRB_WIDTH)
    ) u_output_buffer_array (
        .ACLK(ACLK),
        .ARESETn(ARESETn),

        .clear(clear),
        .write_start(write_start),
        .buffer_full(result_buffer_full),
        .write_done(write_done),

        .mac_valid(mac_to_output_valid),
        .mac_ready(mac_to_output_ready),
        .mac_last(mac_to_output_last),
        .mac_data(mac_to_output_data),

        .axi_wdata(axi_wdata),
        .axi_wstrb(axi_wstrb),
        .axi_wlast(axi_wlast),
        .axi_wvalid(axi_wvalid),
        .axi_wready(axi_wready)
    );

endmodule
