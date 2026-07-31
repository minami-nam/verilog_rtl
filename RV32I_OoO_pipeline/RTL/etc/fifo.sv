

module fifo_cache #(
    parameter int WIDTH = 32,
    parameter int NUM_CACHE = 16
)(
    input wire ACLK,
    input wire ARESETn,

    input  wire [WIDTH-1:0] input_data,
    input  wire             i_valid,
    output wire             i_ready,

    output wire [WIDTH-1:0] output_data,
    input  wire             o_ready,
    output wire             o_valid

);
    localparam integer PTR_WIDTH = (NUM_CACHE <= 1) ? 1 : $clog2(NUM_CACHE);
    localparam integer CNT_WIDTH = (NUM_CACHE <= 1) ? 1 : $clog2(NUM_CACHE + 1);

    reg [WIDTH-1:0] register [0:NUM_CACHE-1];
    reg [PTR_WIDTH-1:0] pointer_in;
    reg [PTR_WIDTH-1:0] pointer_out;
    reg [CNT_WIDTH-1:0] counter;
    wire full;
    wire empty;
    wire inp, opt;

    assign full = (counter == NUM_CACHE);
    assign empty = (counter == 0);
    assign inp = i_valid && i_ready;
    assign opt = o_valid && o_ready;

    assign i_ready = !full;
    assign o_valid = !empty;

    assign output_data = register[pointer_out];




    // in and out
    always @(posedge ACLK or negedge ARESETn) begin
        if (!ARESETn) begin
            for (int i=0; i<NUM_CACHE; i++) begin
                register[i] <= '0;
            end
        end
        else begin
            if (inp) register[pointer_in] <= input_data;
        end
    end

    // counter (current status)
    always @(posedge ACLK or negedge ARESETn) begin
        if (!ARESETn) counter <= '0;
        else begin
            case({inp, opt})
                2'b00 : counter <= counter;
                2'b01 : counter <= counter - 1;
                2'b10 : counter <= counter + 1;
                2'b11 : counter <= counter;
                default : counter <= counter;
            endcase
        end
    end

    // pointers
    always @(posedge ACLK or negedge ARESETn) begin
        if (!ARESETn) begin
            pointer_in <= '0;
            pointer_out <= '0;
        end
        else begin
            if (inp) begin
                if (pointer_in < NUM_CACHE-1)
                    pointer_in <= pointer_in + 1;
                else
                    pointer_in <= '0;
            end

            if (opt) begin
                if (pointer_out < NUM_CACHE-1)
                    pointer_out <= pointer_out + 1;
                else
                    pointer_out <= '0;
            end
        end
    end


endmodule
