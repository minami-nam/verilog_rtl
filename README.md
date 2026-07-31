# Verilog RTL Projects

Verilog/SystemVerilog로 작성한 AXI4 기반 RTL 설계 프로젝트 모음입니다.

## Projects

| Project | Description |
| --- | --- |
| [AXI4 Full Multi Controller](AXI4_Full_Multi_controller/) | 다수의 AXI4 Master와 Slave 간 트랜잭션을 중재하는 Controller 설계 |
| [AXI4 Custom Controller](AXI4_custom_controller/) | AXI4 Out-of-Order 처리를 위한 Queue, Scheduler 및 Reorder Buffer 설계 |
| [AXI4 MAC Array](AXI4_mac_array/) | AXI4 Full 인터페이스와 연동되는 MAC Array 기반 행렬곱 연산기 설계 |
| [RV32I Out-of-Order Pipeline](RV32I_OoO_pipeline/) | Register renaming, ROB, 동적 issue, cache 및 AXI4 interface를 통합한 RV32I OoO CPU 코어 |

각 프로젝트의 상세한 구조와 구현 내용은 해당 디렉터리의 문서와 RTL/TB 소스를 참고해 주세요.
