`include "axi_include_top.vh"


`ifndef FEATURES
`define FEATURES
// Option
// SIM으로 설정 시 simulation 관련 설정 불러오기

`ifdef SIM
    `define DISPLAY_LOG_TRUE  // Log 기록 활성화. 
    `define USE_SYSTEMVERILOG_FEATURES // typedef enum과 같은 systemverilog 기능 사용 여부. 주석 처리 시 사용 X
    `define INITIAL_REG_RESET   // REGISTER RESET
    `define DISPLAY_ALL_SIGNALS // $dumpvars 기능 사용 여부. 주석 처리 시 사용 X
`endif
// IN_ORDER, OUT_ORDER 설정


// 정책 설정 
`ifdef OUT_ORDER
    `define OOO_POLICY_HERE // 생각한 Policy 작성하기
    `define BANK_AWARE
    `define MINAMI_CUSTOM
    `define WRITE_MINAMI_CUSTOM
    `ifdef IN_ORDER
        $error("ERROR : IN_ORDER and OUT_ORDER cannot be both defined!");
    `endif
`endif

`endif 