# RV32I Out-of-Order Pipeline

SystemVerilog로 구현한 32-bit RV32I 기반 Out-of-Order CPU 코어입니다. 레지스터 리네이밍, 동적 issue, in-order commit을 결합해 명령 간 독립성을 활용하며, 분기 예측·캐시·AXI4 메모리 인터페이스까지 하나의 코어로 통합했습니다.

## 주요 구현 내용

- 32개 architectural register와 64개 physical register를 사용하는 register renaming
- 32-entry Reorder Buffer(ROB)를 통한 precise in-order commit 및 recovery
- Integer Issue Queue와 Load/Store Queue를 분리한 동적 명령 스케줄링
- BTB 기반 분기 예측과 misprediction 시 speculative state 복구
- Store Buffer, byte 단위 store-to-load forwarding, non-alias load bypass
- Load Queue와 Completion Queue를 이용한 LSU issue/memory response 분리
- fetch metadata/packet FIFO를 통한 연속 instruction 공급 및 epoch 기반 wrong-path 폐기
- I-cache와 MSHR 기반 D-cache, transaction ID 기반 load response 매칭
- AXI4 Full master interface를 통한 instruction/data memory 접근
- Machine-mode CSR, exception 및 software/timer/external interrupt 처리

## 구조

```text
                   +---------------- Frontend ----------------+
AXI4 <-> I-cache -> Fetch metadata FIFO -> Fetch packet FIFO -+
                   |        Branch Predictor / BTB             |
                   +---------------------+----------------------+
                                         |
                                  Decode / Rename
                                         |
                   +---------------------v----------------------+
                   |                  Backend                   |
                   |  ROB + Integer IQ + LSQ + Physical RF      |
                   |       |                    |                |
                   |  Integer Execute          LSU              |
                   |                     +------+-------+        |
                   |                     | Store Buffer |        |
                   |                     | Load Queue   |        |
                   |                     | Completion Q |        |
                   |                     +------+-------+        |
                   |                            |                |
                   |                         D-cache             |
                   +----------------------------+----------------+
                                                |
                                              AXI4
```

명령은 frontend에서 fetch된 뒤 decode와 physical register 할당을 거쳐 ROB 및 각 issue queue에 들어갑니다. 준비된 명령은 program order와 무관하게 실행되지만 architectural state는 ROB head부터 순서대로 갱신됩니다. 분기 오예측이나 exception이 발생하면 speculative 명령과 미완료 memory operation을 flush하고 rename state와 PC를 복구합니다.

## 디렉터리 구성

```text
RV32I_OoO_pipeline/
├── RTL/
│   ├── frontend/              # PC, branch predictor, I-cache, fetch queues
│   ├── id/                    # Decoder, rename map, free/busy table, dispatch
│   ├── backend/               # ROB, IQ, LSQ, execution, LSU, D-cache, CSR
│   ├── etc/                   # 공용 FIFO와 cache/AXI adapter
│   └── rv32_ooo_core_top.sv   # 최상위 코어 및 AXI4 연결
├── TB/
│   ├── tb_rv32_ooo_core_top.sv
│   └── core_files.f           # Vivado compile file list
├── vivadoproj/                # Vivado 프로젝트
├── DEBUG_NOTES.md             # 병목 분석, 수정 내역, 단계별 측정 결과
└── RV32I_OoO_pipeline_paper.docx
```

## 기본 구성

| 항목 | 기본값 |
| --- | ---: |
| Architectural / Physical registers | 32 / 64 |
| ROB / Integer IQ / LSQ entries | 32 / 16 / 16 |
| Store Buffer / Load Queue entries | 8 / 8 |
| Completion Queue entries | 16 |
| Fetch metadata / packet FIFO entries | 8 / 8 |
| I-cache / D-cache lines | 48 / 64 |
| Cache line size | 16 bytes |
| D-cache MSHR / response queue entries | 8 / 16 |
| AXI data / ID width | 64 / 3 bits |

주요 크기와 인터페이스 폭은 `RTL/rv32_ooo_core_top.sv`의 parameter로 조절할 수 있습니다.

## 검증

Self-checking testbench는 ALU, branch/jump, load/store, forwarding, CSR, recovery를 검사하고 다음 두 성능 구간도 포함합니다.

- 서로 다른 네 cache line에 대한 연속 `LW`로 D-cache MSHR 동작 검증
- 5개 명령으로 구성된 loop를 128회 반복해 warm-cache frontend throughput 측정

Vivado 2025.1 clean compile/elaboration 및 full simulation에서 703개 명령이 모두 정상 retire되었으며 결과는 다음과 같습니다.

| Metric | Result |
| --- | ---: |
| Total cycles | 1,003 |
| Retired instructions | 703 |
| Overall IPC | 0.7009 |
| Core IPC | 0.7233 |
| Warm-loop instructions / cycles | 640 / 680 |
| Warm-loop IPC | 0.9412 |
| I-cache hit / miss responses | 707 / 18 |
| Maximum Load Queue occupancy | 4 |
| Maximum D-cache MSHR occupancy | 5 |

시뮬레이션 로그의 최종 `[TEST][PASS]`와 signature memory 검사를 통해 기능적 성공 여부를 판정합니다. 설계 과정의 deadlock 분석, LSU 최적화 단계와 성능 변화는 [DEBUG_NOTES.md](DEBUG_NOTES.md)에 정리되어 있습니다.

## Vivado 시뮬레이션

GUI에서는 `vivadoproj/RV32I_CPU_PROTOTYPE/RV32I_CPU_PROTOTYPE.xpr`을 열고 simulation source를 compile/elaborate한 뒤 `Run All`을 실행합니다.

Vivado 명령행 도구를 사용하는 경우 프로젝트 디렉터리에서 다음과 같이 실행할 수 있습니다.

```bash
cd RV32I_OoO_pipeline
xvlog -sv -f TB/core_files.f
xelab tb_rv32_ooo_core_top -s tb_rv32_ooo_core_top_sim
xsim tb_rv32_ooo_core_top_sim -runall
```

## 현재 제약 사항

- 코어의 dispatch/commit 폭은 cycle당 1개 명령입니다.
- D-cache는 여러 요청을 MSHR에 보관하지만 lower AXI read engine은 한 번에 하나의 burst를 처리합니다.
- 동일 cache line miss coalescing은 구현하지 않았습니다.
- retire 이후 도착한 store access error는 sticky 상태로 기록되며 precise exception으로 되돌리지 않습니다.
- 검증 대상은 저장소의 self-checking RTL testbench이며, 전체 RISC-V compliance suite 결과를 의미하지는 않습니다.

