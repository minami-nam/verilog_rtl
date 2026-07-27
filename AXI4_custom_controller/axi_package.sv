`include "axi_include_top.vh"

package axi_pkg;
    // Common
    parameter logic OFF = 1'b0;
    parameter logic ON = 1'b1;
    parameter int FIFO_NUM = 8;
    parameter int ADDR_WIDTH = 32;
    parameter int DATA_WIDTH = 32;
    parameter int ID_WIDTH   = 4;
    parameter int LEN_WIDTH  = 8;

    // For OoO Only

    
    `ifdef OUT_ORDER
        // Read
        parameter int NUM_READ_IDTABLE = 4;
        parameter int NUM_READ_SCHEDULER = 4;
        parameter int NUM_READ_REORDER = 4;
        // Common
        parameter int NUM_BANK = 4;

        // Write
        parameter int NUM_WRITE_AWQUEUE = 4;
        parameter int NUM_WRITE_SCHEDULER = 4;
        parameter int NUM_WRITE_ORDER_QUEUE_AW = 4;
        
        
    `endif
    
    // Testbench
    `ifdef USE_SYSTEMVERILOG_FEATURES
        // Burst Type 관련
        typedef enum logic [1:0] { 
            FIXED = 2'b00,
            INCR = 2'b01,
            WRAP = 2'b10,
            RESERVED = 2'b11
        } burst_type;

        // 이후 여기에 TB에서 사용할 것들 추가할 것.
        class axi_ar_rand;
            logic [ID_WIDTH-1:0]   id;
            logic [ADDR_WIDTH-1:0] addr;
            logic [LEN_WIDTH-1:0]  len;
            logic [2:0]            size;
            logic [1:0]            burst;
            bit                    valid;
            bit                    ready;

            function void set_fixed(
                input logic [ID_WIDTH-1:0]   fixed_id,
                input logic [ADDR_WIDTH-1:0] fixed_addr,
                input logic [LEN_WIDTH-1:0]  fixed_len
            );
                id = fixed_id;
                addr = {fixed_addr[ADDR_WIDTH-1:2], 2'b00};
                len = fixed_len;
                size = 3'b010;
                burst = INCR;
                valid = 1'b1;
                ready = ($urandom_range(0, 9) < 8);
            endfunction

            function void set_random();
                id = $urandom();
                addr = $urandom();
                addr[1:0] = 2'b00;
                len = $urandom_range(0, 7);
                size = 3'b010;
                burst = INCR;
                valid = ($urandom_range(0, 9) < 8);
                ready = ($urandom_range(0, 9) < 8);
            endfunction

            function void copy_to_master(
                output logic [ID_WIDTH-1:0]   arid,
                output logic [ADDR_WIDTH-1:0] araddr,
                output logic [LEN_WIDTH-1:0]  arlen,
                output logic [2:0]            arsize,
                output logic [1:0]            arburst,
                output logic                  arvalid
            );
                arid = id;
                araddr = addr;
                arlen = len;
                arsize = size;
                arburst = burst;
                arvalid = valid;
            endfunction
        endclass

        class axi_aw_rand;
            logic [ID_WIDTH-1:0]   id;
            logic [ADDR_WIDTH-1:0] addr;
            logic [LEN_WIDTH-1:0]  len;
            logic [2:0]            size;
            logic [1:0]            burst;
            bit                    valid;
            bit                    ready;

            function void set_fixed(
                input logic [ID_WIDTH-1:0]   fixed_id,
                input logic [ADDR_WIDTH-1:0] fixed_addr,
                input logic [LEN_WIDTH-1:0]  fixed_len
            );
                id = fixed_id;
                addr = {fixed_addr[ADDR_WIDTH-1:2], 2'b00};
                len = fixed_len;
                size = 3'b010;
                burst = INCR;
                valid = 1'b1;
                ready = ($urandom_range(0, 9) < 8);
            endfunction

            function void set_random();
                id = $urandom();
                addr = $urandom();
                addr[1:0] = 2'b00;
                len = $urandom_range(0, 7);
                size = 3'b010;
                burst = INCR;
                valid = ($urandom_range(0, 9) < 8);
                ready = ($urandom_range(0, 9) < 8);
            endfunction

            function void copy_to_master(
                output logic [ID_WIDTH-1:0]   awid,
                output logic [ADDR_WIDTH-1:0] awaddr,
                output logic [LEN_WIDTH-1:0]  awlen,
                output logic [2:0]            awsize,
                output logic [1:0]            awburst,
                output logic                  awvalid
            );
                awid = id;
                awaddr = addr;
                awlen = len;
                awsize = size;
                awburst = burst;
                awvalid = valid;
            endfunction
        endclass

        class axi_w_rand;
            logic [DATA_WIDTH-1:0]   data;
            logic [DATA_WIDTH/8-1:0] strb;
            bit                      last;
            bit                      valid;
            bit                      ready;

            function void set_fixed(
                input logic [DATA_WIDTH-1:0] fixed_data,
                input bit                    fixed_last
            );
                data = fixed_data;
                strb = $urandom();
                if (strb == '0) strb = '1;
                last = fixed_last;
                valid = 1'b1;
                ready = ($urandom_range(0, 9) < 8);
            endfunction

            function void set_random();
                data = $urandom();
                strb = $urandom();
                if (strb == '0) strb = '1;
                last = $urandom_range(0, 1);
                valid = ($urandom_range(0, 9) < 8);
                ready = ($urandom_range(0, 9) < 8);
            endfunction

            function void copy_to_master(
                output logic [DATA_WIDTH-1:0]   wdata,
                output logic [DATA_WIDTH/8-1:0] wstrb,
                output logic                    wlast,
                output logic                    wvalid
            );
                wdata = data;
                wstrb = strb;
                wlast = last;
                wvalid = valid;
            endfunction
        endclass

        class axi_r_rand;
            logic [ID_WIDTH-1:0]   id;
            logic [DATA_WIDTH-1:0] data;
            logic [1:0]            resp;
            bit                    last;
            bit                    valid;
            bit                    ready;

            function void set_fixed(
                input logic [ID_WIDTH-1:0]   fixed_id,
                input logic [DATA_WIDTH-1:0] fixed_data,
                input bit                    fixed_last
            );
                id = fixed_id;
                data = fixed_data;
                resp = 2'b00;
                last = fixed_last;
                valid = 1'b1;
                ready = ($urandom_range(0, 9) < 8);
            endfunction

            function void set_random();
                id = $urandom();
                data = $urandom();
                resp = 2'b00;
                last = $urandom_range(0, 1);
                valid = ($urandom_range(0, 9) < 8);
                ready = ($urandom_range(0, 9) < 8);
            endfunction

            function void copy_to_slave(
                output logic [ID_WIDTH-1:0]   rid,
                output logic [DATA_WIDTH-1:0] rdata,
                output logic [1:0]            rresp,
                output logic                  rlast,
                output logic                  rvalid
            );
                rid = id;
                rdata = data;
                rresp = resp;
                rlast = last;
                rvalid = valid;
            endfunction
        endclass

        class axi_b_rand;
            logic [ID_WIDTH-1:0] id;
            logic [1:0]          resp;
            bit                  valid;
            bit                  ready;

            function void set_fixed(input logic [ID_WIDTH-1:0] fixed_id);
                id = fixed_id;
                resp = 2'b00;
                valid = 1'b1;
                ready = ($urandom_range(0, 9) < 8);
            endfunction

            function void set_random();
                id = $urandom();
                resp = 2'b00;
                valid = ($urandom_range(0, 9) < 8);
                ready = ($urandom_range(0, 9) < 8);
            endfunction

            function void copy_to_slave(
                output logic [ID_WIDTH-1:0] bid,
                output logic [1:0]          bresp,
                output logic                bvalid
            );
                bid = id;
                bresp = resp;
                bvalid = valid;
            endfunction
        endclass

    `endif

endpackage
