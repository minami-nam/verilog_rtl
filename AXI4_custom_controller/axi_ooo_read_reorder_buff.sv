`include "axi_include_top.vh"
import axi_pkg::*;

module axi_ooo_read_reorder_buff #(
    parameter int DATA_WIDTH = 32,
    parameter int ID_WIDTH = 4,
    parameter int NUM_READ_IDTABLE = 4,
    parameter int NUM_READ_REORDER = 4,
    parameter int READ_REORDER_KEEP_OUT_TIMES = 8
) (
    input  wire ACLK,
    input  wire ARESETn,

    // From M_AXI R channel
    input  wire [ID_WIDTH-1:0]   in_rid,
    input  wire [DATA_WIDTH-1:0] in_rdata,
    input  wire [1:0]            in_rresp,
    input  wire                  in_rlast,
    input  wire                  in_rvalid,
    output wire                  in_rready,

    // To S_AXI R channel
    output wire [ID_WIDTH-1:0]   out_rid,
    output wire [DATA_WIDTH-1:0] out_rdata,
    output wire [1:0]            out_rresp,
    output wire                  out_rlast,
    output wire                  out_rvalid,
    input  wire                  out_rready
);

    `ifdef LOWEST_PRIORITY  

    `elsif MINAMI_CUSTOM
        localparam int KEEP_OUT_TIMES = READ_REORDER_KEEP_OUT_TIMES;

        localparam int CNT_WIDTH = $clog2(KEEP_OUT_TIMES);

        

        wire data_in = in_rvalid & in_rready;
        wire data_out = out_rvalid & out_rready;


        wire [ID_WIDTH-1:0]   integ_in_rid[0:NUM_READ_IDTABLE-1];
        wire [DATA_WIDTH-1:0] integ_in_rdata[0:NUM_READ_IDTABLE-1];
        wire [1:0]            integ_in_rresp[0:NUM_READ_IDTABLE-1];
        wire                  integ_in_rlast[0:NUM_READ_IDTABLE-1];
        wire                  integ_in_rvalid[0:NUM_READ_IDTABLE-1];
        wire                  integ_in_rready[0:NUM_READ_IDTABLE-1];


        wire [ID_WIDTH-1:0]   integ_out_rid[0:NUM_READ_IDTABLE-1];
        wire [DATA_WIDTH-1:0] integ_out_rdata[0:NUM_READ_IDTABLE-1];
        wire [1:0]            integ_out_rresp[0:NUM_READ_IDTABLE-1];
        wire                  integ_out_rlast[0:NUM_READ_IDTABLE-1];
        wire                  integ_out_rvalid[0:NUM_READ_IDTABLE-1];
        wire                  integ_out_rready[0:NUM_READ_IDTABLE-1];

        assign in_rready = integ_in_rready[in_rid];

        reg [CNT_WIDTH-1:0] cnt;
        
        reg [ID_WIDTH-1:0] prev_out_rid;
        reg [ID_WIDTH-1:0] at_least_rid_value;
        reg [ID_WIDTH-1:0] final_out_rid;
        reg valid;

        assign out_rid = integ_out_rid[final_out_rid];
        assign out_rdata = integ_out_rdata[final_out_rid];
        assign out_rresp = integ_out_rresp[final_out_rid];
        assign out_rlast = integ_out_rlast[final_out_rid];
        assign out_rvalid = integ_out_rvalid[final_out_rid];

        always @(*) begin
            final_out_rid = 0;
            valid = OFF;
            if (cnt==0) begin
                if (prev_out_rid%2==0) begin    // 오름차순으로 찾기
                    for (int i=0; i<NUM_READ_IDTABLE; i++) begin : search_cell
                        if (!valid&integ_out_rvalid[i]) begin
                            final_out_rid = i;
                            valid = ON;
                        end
                    end 
                end
                else begin  // Starvation 방지를 위한 내림차순으로 찾기
                    for (int i=0; i<NUM_READ_IDTABLE; i++) begin : search_cell
                        if (!valid&integ_out_rvalid[NUM_READ_IDTABLE-(1+i)]) begin
                            final_out_rid = NUM_READ_IDTABLE-(1+i);
                            valid = ON;
                        end
                    end 
                end
            end

            else if (cnt!=0) begin
                final_out_rid = prev_out_rid;
            end
        end 

        genvar a;
        genvar i;
        generate
            for (a=0; a<NUM_READ_IDTABLE; a++) begin : input_assign_wires
                assign integ_in_rid[a] = (in_rid == a) ? in_rid : '0;
                assign integ_in_rdata[a] = (in_rid == a) ? in_rdata : '0;
                assign integ_in_rresp[a] = (in_rid == a) ? in_rresp : '0;
                assign integ_in_rlast[a] = (in_rid == a) ? in_rlast : '0;
                assign integ_in_rvalid[a] = (in_rid == a) ? in_rvalid : OFF;
            end

            for (i=0; i<NUM_READ_IDTABLE; i++) begin : instantiate_fifo_cache
                fifo_small #(
                    .per_id(NUM_READ_REORDER),
                    .DATA_WIDTH(DATA_WIDTH),
                    .ID_WIDTH(ID_WIDTH)
                ) fifo_integ(
                    .ACLK(ACLK),
                    .ARESETn(ARESETn),

                    .in_rid(integ_in_rid[i]),
                    .in_rdata(integ_in_rdata[i]),
                    .in_rresp(integ_in_rresp[i]),
                    .in_rlast(integ_in_rlast[i]),
                    .in_rvalid(integ_in_rvalid[i]),
                    .in_rready(integ_in_rready[i]),

                    // To S_AXI R channel
                    .out_rid(integ_out_rid[i]),
                    .out_rdata(integ_out_rdata[i]),
                    .out_rresp(integ_out_rresp[i]),
                    .out_rlast(integ_out_rlast[i]),
                    .out_rvalid(integ_out_rvalid[i]),
                    .out_rready(integ_out_rready[i])

                );
            end
        endgenerate

        // cnt 설정 관련
        always @(posedge ACLK or negedge ARESETn) begin
            if (!ARESETn) begin
                cnt <= '0;
            end 
            else begin
                if ((prev_out_rid==out_rid)&(cnt<KEEP_OUT_TIMES-1)) begin
                    cnt <= cnt + 1;
                end
                else if (cnt==KEEP_OUT_TIMES-1) begin
                    cnt <= '0;
                end
                else if (prev_out_rid!=out_rid) begin
                    cnt <= '0;
                end
                else cnt <= cnt;
            end   
        end

        // prev_out_rid 값 캡쳐하는 방법
        always @(posedge ACLK or negedge ARESETn) begin
            if (!ARESETn) begin
                prev_out_rid <= '0;
            end
            else begin
                if (data_out) begin
                    prev_out_rid <= final_out_rid;
                end
                else begin
                    prev_out_rid <= prev_out_rid;
                end
            end
        end

        

        `ifdef INITIAL_REG_RESET
            initial begin
                cnt=0;
            
                prev_out_rid=0;
                at_least_rid_value=0;
                final_out_rid=0;
                valid=OFF;
            end
        `endif

 

        

    `endif




endmodule
