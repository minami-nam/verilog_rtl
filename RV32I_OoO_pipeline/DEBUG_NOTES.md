# Backend debug notes

## 1. Same-cycle writeback ready 누락

- 증상: `tag 2`의 `ADD x3, x1, x2`가 issue되지 않아 ROB가 정지하고 timeout이 발생했다.
- 원인: rename과 source physical register의 writeback이 같은 cycle에 발생하면, `busy_table`의 sequential 갱신 전 값을 dispatch packet이 저장했다. IQ enqueue 시점에는 해당 wakeup pulse도 이미 지나간 상태였다.
- 수정: `RTL/id/busy_table.sv`의 `rs1_ready`, `rs2_ready` 판정에 `clear_busy_valid`와 `clear_busy_tag` 비교를 추가해 같은 cycle writeback을 ready로 bypass했다.
- 확인: 수정 후 `tag 2`가 cycle 24에 complete되고 cycle 25에 commit됐다.

## 2. SYSTEM 명령의 IQ hold deadlock

- 증상: load인 `tag 10`은 complete/commit됐지만, 그 결과를 기다리던 `tag 11`이 issue되지 않아 다시 timeout이 발생했다.
- 원인:
  - `tag 11`이 load 결과를 기다리는 동안 ready 상태인 `tag 23` SYSTEM 명령이 IQ에서 선택됐다.
  - CSR/SYSTEM 명령은 ROB head일 때만 backend에서 `issue_ready`를 받을 수 있다.
  - IQ가 ready가 낮은 `tag 23`을 `issue_hold`에 고정했다.
  - 이후 ROB head에 가까운 `tag 11`이 wakeup돼도 hold된 `tag 23` 때문에 선택되지 못했다.
- 수정: `RTL/backend/issue_queue.sv`에서 SYSTEM 명령은 자신의 ROB tag가 `rob_head_tag`와 같을 때만 issue 후보가 되도록 제한했다.
- 확인: 수정 후 첫 번째 `tag 11`은 cycle 120에 complete되고 cycle 121에 commit됐다. SYSTEM `tag 21`, `tag 22`도 각각 cycle 214, 217에 complete되어 ROB head에서 정상 처리됐다.

## 재검증 항목

Vivado에서 simulation source를 다시 compile/elaborate한 뒤 `run all`로 실행한다.

다음 순서를 우선 확인한다.

```text
[COMPLETE] ... tag=10
[COMMIT]   ... tag=10
[COMPLETE] ... tag=11
[COMMIT]   ... tag=11
```

이후 `tag 23` SYSTEM 명령이 ROB head에서 complete/commit되는지 확인한다.

최종 completion store가 retire되면 TB의 `program_done`이 설정되고 다음 결과가 출력돼야 한다.

```text
[PERF] ...
[BASELINE] ...
[COMPARE] ...
[TEST][PASS] ...
```

참고로 timeout 경로는 `report_results()`를 호출하지 않으므로, 프로그램이 끝까지 retire되지 않으면 성능 비교 결과도 출력되지 않는다.

## 3. IQ hold와 실행 불가능한 Memory 후보의 arbitration deadlock

### 관찰된 증상

ROB tag가 재사용된 뒤 다음 명령 순서에서 진행이 다시 멈췄다.

```text
tag 10, pc=0x000070b0: ORI   x25, x0, 0x55
tag 11, pc=0x000070b4: AND   x26, x25, x6
tag 12, pc=0x000070b8: STORE x23, signature_address
tag 18, pc=0x000070d0: JAL   x0, 0
```

`tag 10`은 cycle 381에 `0x55`를 writeback했지만, 이를 기다리던 `tag 11`의 completion은 발생하지 않았다. 반면 younger store인 `tag 12`는 cycle 395에 address-generation completion까지 진행한 뒤 ROB commit을 기다렸다. ROB head는 미완료 `tag 11`에서 멈췄고, LSU는 younger store의 commit을 기다려 순환 대기가 형성됐다.

마지막 self-loop JAL이 실행되지 않으면서 frontend가 프로그램 끝 이후의 zero-filled 영역까지 가져왔고, `UNKNOWN` 명령이 반복 dispatch된 것은 이 정체의 부차적인 증상이다.

### 직접 원인 1: Integer IQ의 비선택 후보 고정

기존 IQ는 `issue_valid=1`, `issue_ready=0`이면 선택한 entry를 `issue_hold_idx`에 저장했다. 이후 더 오래된 명령이 wakeup돼도 `issue_hold_valid`가 후보 선택보다 우선하므로 새로운 oldest-ready entry를 선택할 수 없었다.

이 구조에서 `issue_ready=0`은 단순한 실행기 backpressure뿐 아니라 Memory IQ가 공용 PRF read/issue 경로를 획득한 경우에도 발생한다. 따라서 arbiter에서 선택되지 않았을 뿐인 Integer 후보까지 장기간 고정되는 문제가 있었다.

### 직접 원인 2: 실행 불가능한 Memory 후보도 나이 비교에 참여

기존 backend arbiter는 `int_issue_valid`와 `ls_issue_valid`만 비교했다. LSU가 `STORE_DONE` 등으로 `lsu_issue_ready=0`이어도 Memory 명령이 더 오래됐으면 Memory 경로를 선택했다. 결과적으로 LSU는 새 명령을 받을 수 없고, ALU가 비어 있어도 Integer 명령에는 grant가 전달되지 않았다.

### 수정 내용

`RTL/backend/issue_queue.sv`:

- `issue_hold_valid`, `issue_hold_idx` 상태와 관련 sequential block을 제거했다.
- `issue_candidate_idx`로 선택한 현재 oldest-ready entry를 매 cycle 직접 출력한다.
- entry는 `issue_fire`가 발생해야만 invalid 처리되므로, grant를 받지 못한 명령은 IQ 안에 그대로 남는다.
- 새로 wakeup된 더 오래된 명령은 다음 arbitration에서 즉시 후보가 될 수 있다.

```systemverilog
assign issue_select_valid = issue_candidate_valid;
assign issue_select_idx   = issue_candidate_idx;
```

`RTL/backend/ooo_backend.sv`:

- 각 queue의 valid와 실제 functional-unit ready를 결합해 `int_can_issue`, `mem_can_issue`를 계산한다.
- 이번 cycle에 실제 실행 가능한 후보끼리만 ROB distance를 비교한다.
- queue의 `issue_ready`는 단순한 준비 상태가 아니라 실제 pop을 허용하는 최종 grant로 사용한다.

```systemverilog
int_can_issue = int_issue_valid && selected_integer_ready && !global_flush;
mem_can_issue = ls_issue_valid  && lsu_issue_ready         && !global_flush;
```

선택 규칙은 다음과 같다.

```text
Integer만 실행 가능           -> Integer grant
Memory만 실행 가능            -> Memory grant
둘 다 실행 가능               -> ROB head에서 가까운 후보 grant
둘 다 실행 불가능             -> grant 없음
Memory가 더 오래됐지만 LSU busy -> 실행 가능한 Integer grant
```

같은 ROB distance에서는 기존 정책을 유지해 Integer가 우선한다.

### 설계 의미

Issue Queue의 출력은 일반 FIFO의 단일 고정 transaction과 다르다. grant 전에는 여러 ready entry 중 선택 후보를 다시 계산할 수 있어야 한다. 명령의 보존 책임은 `issue_hold`가 아니라 IQ entry의 valid bit가 담당하며, 실제 삭제는 `issue_valid && issue_ready` handshake에서만 수행한다.

현재 backend는 Integer와 Memory가 공용 PRF read 선택 경로를 사용하므로 한 cycle에 하나만 grant한다. 이 제약 아래에서도 실행할 수 없는 한쪽 queue가 실행 가능한 다른 queue를 막지 않도록 arbitration eligibility와 age priority를 분리해야 한다.

### 재검증 포인트

최신 정체 구간에서 다음 순서를 확인한다.

```text
[COMPLETE] ... tag=10 pc 대응 결과=00000055
[COMPLETE] ... tag=11 data=00000044
[COMMIT]   ... tag=11 pc=000070b4
[COMMIT]   ... tag=12 pc=000070b8
```

그 뒤 마지막 `tag 18`, `pc=0x000070d0`의 self-loop JAL이 실행되어 더 이상 zero-filled 영역의 `UNKNOWN` 명령이 유효 경로에서 계속 retire되지 않아야 한다. 최종 completion store `pc=0x000070cc`가 retire되면 TB가 성능 결과를 출력한다.

## 4. LSU Store Buffer 추가

### 기존 병목

기존 LSU는 하나의 store를 다음 상태로 끝까지 직렬 처리했다.

```text
STORE_ADDR_WB -> STORE_WAIT_COMMIT -> STORE_REQ
              -> STORE_RESP -> STORE_DONE -> IDLE
```

`issue_ready`가 `LSU_IDLE`에서만 올라가므로 store가 ROB head와 cache/AXI response를 기다리는 동안 다음 load/store의 주소 생성도 진행할 수 없었다. 결과 검사용 store가 많은 TB에서 dispatch-to-commit latency가 최대 197 cycles까지 누적됐다.

### 구현 구조

`RTL/backend/lsu.sv` 내부에 기본 8-entry `STORE_BUFFER_DEPTH`를 추가했다. 각 entry는 다음 정보를 저장한다.

```text
valid, committed, ROB tag, aligned address, shifted data, byte strobe
```

세 개의 포인터를 사용한다.

- `sb_head`: memory로 drain할 가장 오래된 committed store
- `sb_commit_head`: ROB에서 다음으로 commit할 가장 오래된 uncommitted store
- `sb_tail`: 새 store enqueue 위치

Store 실행과 memory write를 분리했다.

```text
LSQ issue -> 주소/데이터 계산 -> Store Buffer enqueue -> ROB completion
                                      |
ROB head -> committed 표시 -----------+
                                      |
별도 drain FSM: IDLE -> REQ -> RESP -> entry 제거
```

Store가 ROB head에 도달하면 matching `sb_commit_head`를 committed로 표시하고 즉시 retire할 수 있다. Cache write는 committed prefix를 유지하는 별도 drain FSM이 program order로 처리한다.

### Recovery 정책

branch/trap flush에서는 uncommitted entry만 제거하고 committed entry는 보존한다. Committed store는 architectural state에 포함되므로 recovery가 발생해도 memory drain을 끝내야 한다. `sb_committed_count`와 `sb_commit_head`를 사용해 speculative suffix만 잘라낸다.

### Load ordering 정책

현재 첫 구현은 store-to-load forwarding을 넣지 않았다. 정확성을 위해 Store Buffer가 완전히 empty이고 drain FSM도 idle일 때만 load를 LSU로 받는다.

```text
Store burst       : 여러 store의 address/completion/retire를 buffer로 분리
Store 다음 load  : 모든 older store가 memory에 반영될 때까지 보수적으로 대기
```

이 정책은 alias 검사가 없어도 memory ordering을 보장하지만, 서로 다른 주소의 load가 pending store를 추월하지 못한다. 다음 최적화 단계는 byte-mask 기반 store-to-load forwarding과 non-alias load bypass이다.

### Memory error 제약

Store는 ROB에서 retire된 뒤 buffer가 cache write를 수행하므로 늦게 도착한 store access error를 precise ROB exception으로 되돌릴 수 없다. 현재 구현은 `store_error_sticky`에 오류를 기록하지만 CSR machine-check 경로는 아직 연결하지 않았다. 실제 시스템에서는 다음 중 하나가 추가로 필요하다.

- cache가 store 수락 시점에 fault 여부를 확정하는 규약
- 비동기 machine-check/버스 오류 CSR 경로
- precise store fault가 필요할 때 해당 store만 response까지 retire 보류

### TB 완료 조건 변경

마지막 completion store가 ROB에서 retire된 시점에는 buffer에 memory write가 남아 있을 수 있다. TB는 `program_done` 이후 `done_addr == 1`이 실제 memory에 기록될 때까지 기다린 후 결과를 검사한다. 성능 scoreboard는 마지막 프로그램 store까지만 retire를 집계하고 drain 대기 중 sentinel JAL은 제외한다.

### 조합 경로 주의

초기 구현에서 LSU `issue_ready`가 gated `issue_valid`, PRF operand, misalignment 판정에 의존하면서 다음 loop가 생겼다.

```text
select_memory -> LSU issue_valid/PRF tag -> LSU issue_ready
              -> mem_can_issue -> select_memory
```

최종 구현의 LSU ready는 LSU state, load/store 종류, Store Buffer full/empty에만 의존한다. 주소 형식과 misalignment는 실제 grant 후 LSU state machine에서 검사한다.

## 5. Store Buffer timing으로 노출된 frontend metadata race

Store commit이 빨라지면서 JAL recovery 후 stale `pc=0x7068` 명령이 한 번 retire되는 기존 frontend race가 노출됐다. 원인은 새 fetch request와 이전 instruction response가 같은 cycle에 handshake될 때 `meta_valid`가 다음 순서로 덮어써지는 것이었다.

```text
new fetch handshake : meta_valid <= 1
old response        : meta_valid <= 0  (마지막 assignment가 승리)
```

새 outstanding request의 metadata를 잃으면 redirect 시 stale response가 있다는 사실을 알 수 없어 wrong-path packet이 통과한다.

`RTL/frontend/if_id_frontend.sv`에서 request handshake를 우선하도록 `if ... else if` 구조로 바꿨다. response handshake는 `discard_response`만 독립적으로 clear한다. 동시 handshake에서는 새 request의 `meta_valid`, PC, prediction metadata가 유지된다.

수정 후 `pc=0x7068`은 recovery 이후 한 번만 retire되고, expected/actual retired instruction 수가 모두 50으로 일치했다.

## 6. Store Buffer 적용 결과

동일한 50-instruction cold-cache TB의 비교 결과다.

| Metric | 적용 전 | 적용 후 | 변화 |
|---|---:|---:|---:|
| Total cycles | 473 | 379 | -94 (-19.9%) |
| Core cycles | 458 | 291 | -167 (-36.5%) |
| OoO core IPC | 0.1092 | 0.1718 | +57.3% |
| Avg dispatch-to-WB | 40.78 | 14.44 | -64.6% |
| Avg dispatch-to-commit | 77.86 | 38.24 | -50.9% |
| Max dispatch-to-commit | 197 | 100 | -49.2% |
| Speedup vs shadow baseline | 0.138x | 0.216x | 개선 |

초기 연속 store들은 기존 17~49 cycle commit latency 대신 약 4~5 cycle에 retire됐다. Total cycles 개선폭이 core cycles보다 작은 이유는 TB가 architectural retire 이후에도 최종 Store Buffer memory drain을 기다리기 때문이다.

최종 Vivado 2025.1 clean compile, elaboration, full simulation 결과는 다음과 같다.

```text
[CHECK][PASS] retired instructions = 50
[PERF] total cycles = 379
[COMPARE] OoO core cycles = 291
[COMPARE] OoO core IPC = 0.1718
[TEST][PASS] RV32I OoO core test completed successfully
```

## 7. Load bypass/forwarding 및 decoupled parallel LSU

기존 LSU는 하나의 `state`가 load request, response, writeback까지 모두 직렬로 점유했다. Store Buffer가 있어도 pending store가 있으면 load를 받지 않았고, load 하나가 cache response를 기다리는 동안 다음 LD/ST를 받을 수 없었다.

### 변경된 내부 구조

LSU를 다음 세 queue와 독립 memory transaction FSM으로 분리했다.

```text
LSQ issue ----+--> Store Buffer (8) ------> committed store drain --+
              |                                                    |
              +--> Load Queue (8) --------> load cache request -----+--> data cache
              |                                                    |
              +--> forwarded/immediate result --+                  |
                                                 +--> Completion FIFO (16) --> WB arbiter
cache load response -----------------------------+
```

- Store Buffer: speculative/committed store의 주소, 데이터, byte strobe 보관
- Load Queue: cache 요청을 기다리는 여러 load와 forwarding overlay 보관
- Completion FIFO: store address completion, forwarded load, cache load response를 WB backpressure와 분리
- Memory FSM: data cache가 ID 없는 단일 요청/응답 interface이므로 외부 transaction은 한 번에 하나만 발행
- Fair arbitration: committed store drain과 pending load가 동시에 있으면 이전에 처리하지 않은 종류를 우선하여 starvation 방지

즉, 현재의 `data_cache` 자체는 single-outstanding이지만 LSU issue는 cache response와 분리됐다. LSU는 memory transaction 진행 중에도 다음 LD/ST를 queue에 받을 수 있다. 실제 여러 cache miss를 동시에 발행하려면 다음 단계에서 data cache에 request ID/MSHR와 response ID를 추가해야 한다.

`LOAD_QUEUE_DEPTH=8`, `COMPLETION_QUEUE_DEPTH=16`을 `ooo_backend`와 `rv32_ooo_core_top` parameter로 노출했다.

### Store Buffer bypass와 forwarding

현재 `ldst_queue`는 program-order head만 LSU에 issue한다. 따라서 어떤 load가 LSU에 도착했을 때 Store Buffer에 남아 있는 valid store는 모두 그 load보다 오래된 store다. 이 성질 때문에 별도 ROB-age comparator 없이 Store Buffer 전체를 oldest-to-youngest 순으로 검사할 수 있다.

1. load와 store의 word-aligned address 비교
2. 일치하는 store의 byte strobe마다 forwarding data/mask 갱신
3. oldest부터 youngest 순서로 덮어써 동일 byte에는 가장 최근 store 값 적용
4. load가 요구하는 byte가 모두 mask에 포함되면 cache를 거치지 않고 즉시 completion
5. 일부 byte만 포함되면 cache word를 읽은 뒤 해당 byte만 Store Buffer 값으로 overlay
6. 일치 byte가 없으면 load가 pending store를 non-alias bypass하여 Load Queue로 진입

이 방식은 `SB/SH/SW` 뒤의 `LB/LBU/LH/LHU/LW` 조합과 여러 partial store가 한 word를 갱신하는 경우를 byte 단위로 처리한다. Misaligned access는 기존처럼 exception으로 완료한다.

### Flush 처리

- Completion FIFO와 speculative Load Queue는 flush 시 제거한다.
- 이미 data cache에 수락된 load request는 취소할 수 없으므로 response를 받아 버리되 WB에는 올리지 않는다.
- 아직 수락되지 않은 load request는 취소한다.
- committed store transaction과 Store Buffer committed prefix는 계속 보존하고 drain한다.
- precise store access fault 제약은 기존과 동일하다. Retire 후 도착한 store bus error는 현재 `store_error_sticky`에만 기록된다.

## 8. Frontend 공급률 및 stall-reason counter

`TB/tb_rv32_ooo_core_top.sv` scoreboard에 다음 counter를 추가했다. Counter는 `fetch_enable` 이후 final program store retire까지 집계하며, 일부 원인은 같은 cycle에 겹칠 수 있으므로 합이 전체 cycle과 같을 필요는 없다.

### Frontend/supply

- fetch request valid / handshake
- instruction-cache response handshake
- IF packet valid / ID accept
- dispatch valid / backend accept
- frontend empty cycle
- frontend delivery rate 및 dispatch supply rate

### Backend stall/throughput

- dispatch backpressure
- ROB/IQ/LSQ full cycle
- recovery busy cycle
- ROB가 비어 있지 않지만 head가 incomplete인 cycle
- store commit이 Store Buffer match를 기다리는 cycle
- integer/memory issue grant
- ALU와 LSU의 WB 동시 요청 cycle

### LSU 상세

- load/store issue 수
- full forwarding / partial forwarding / non-alias bypass 수
- Load Queue / Store Buffer full stall
- data-cache request backpressure / response wait
- Load Queue / Store Buffer / Completion FIFO 평균 및 최대 점유율

## 9. Parallel LSU 적용 결과

동일한 50-instruction cold-cache TB의 최종 Vivado 2025.1 결과다.

| Metric | Store Buffer만 | Parallel LSU + forwarding | 변화 |
|---|---:|---:|---:|
| Total cycles | 379 | 321 | -58 (-15.3%) |
| Core cycles | 291 | 224 | -67 (-23.0%) |
| OoO core IPC | 0.1718 | 0.2232 | +29.9% |
| Avg dispatch-to-WB | 14.44 | 3.92 | -72.9% |
| Avg dispatch-to-commit | 38.24 | 6.10 | -84.0% |
| Max dispatch-to-commit | 100 | 31 | -69.0% |

기능 검사는 register, signature memory, retired instruction 50개가 모두 PASS했다. LSU counter 결과는 다음과 같다.

```text
load/store issues           = 6 / 21
full/partial forwarding     = 5 / 0
non-alias load bypasses     = 1
LQ/SB full stalls           = 0 / 0
memory req stall/resp wait  = 0 / 153
max LQ/SB/CQ occupancy      = 1 / 7 / 1
```

이 workload에서는 6개 load 중 5개가 Store Buffer에서 완전히 forwarding되어 load latency가 크게 감소했다. Partial-forward 경로는 구현됐지만 현재 프로그램에는 word 일부만 store한 직후 더 넓은 load를 하는 패턴이 없어 counter가 0이다.

새 계측이 보여주는 다음 병목은 LSU queue 용량이 아니다.

```text
frontend delivery rate = 21.76%
dispatch supply rate   = 21.76%
frontend empty cycles  = 185 / 239 active cycles
ROB head incomplete    = 78 cycles
memory response wait   = 153 cycles
```

Backend 구조가 issue할 수 있어도 frontend가 약 4.6 cycle당 한 명령만 공급한다. 다음 성능 작업의 우선순위는 instruction cache hit 응답 throughput과 fetch metadata/control 경로 개선이다. 그 다음 data cache의 MSHR/response ID를 추가해야 Load Queue가 여러 miss를 실제로 동시에 outstanding할 수 있다.

## 10. Frontend 1-cycle hit 공급 및 fetch queue 분리

기존 frontend는 instruction 요청 하나의 metadata만 보존했기 때문에 이전 응답이 끝날 때까지 다음 PC 요청을 만들 수 없었다. `if_id_frontend.sv`를 다음 두 queue로 분리했다.

- `FETCH_META_DEPTH=8`: 발행한 요청의 PC, branch prediction 결과, fetch epoch를 순서대로 보존
- `FETCH_PACKET_DEPTH=8`: 돌아온 instruction과 PC/prediction/cache status를 ID가 받을 때까지 보존

I-cache hit 응답을 받는 cycle에 metadata FIFO head를 pop하면서 다음 요청을 push할 수 있고, packet FIFO도 ID가 소비하는 cycle에 다음 응답을 push할 수 있다. 따라서 backpressure와 redirect가 없다면 hit 구간에서 요청/응답/ID 전달을 매 cycle 계속할 수 있다.

Redirect 시 fetch epoch를 증가시키고 packet FIFO는 즉시 비운다. Redirect 이전에 발행되어 뒤늦게 도착한 응답은 metadata에 저장된 epoch가 현재 epoch와 다르므로 packet FIFO에 넣지 않고 폐기한다. 이 방법으로 AXI/I-cache 내부 요청을 강제로 취소하지 않아도 wrong-path instruction이 dispatch되는 것을 막는다.

FIFO 깊이는 `rv32_ooo_core_top.sv`의 `FETCH_META_DEPTH`, `FETCH_PACKET_DEPTH` 파라미터로 조절할 수 있다.

## 11. Load transaction ID와 D-cache MSHR

LSU의 single memory FSM을 제거하고 Load Queue 각 entry에 `requested`와 `mem_id`를 추가했다. 요청 ID는 load/store 종류, flush epoch, LQ index를 포함한다. Load response는 ID로 해당 LQ entry에 직접 매칭하며, flush 뒤 늦게 돌아온 old-epoch response는 재사용된 LQ entry를 잘못 완료시키지 않는다.

`data_cache.sv`에는 기본 8-entry MSHR와 16-entry response FIFO를 추가했다.

- CPU request를 빈 MSHR에 수락
- hit는 내부에서 response FIFO로 완료
- miss와 write는 lower cache/AXI adapter로 발행
- lower response ID로 MSHR를 검색해 refill/write update 후 해제
- hit response와 lower response가 같은 cycle에 생겨도 response FIFO에 모두 보존

`integ_cache.sv`의 data read/write request FIFO에도 ID를 저장하고, read와 write response 각각에 원래 ID를 되돌려준다. 따라서 독립 read/write engine의 응답 순서가 바뀌어도 LSU가 올바른 load에 결과를 연결한다. MSHR와 response FIFO 깊이는 top의 `DCACHE_MSHR_ENTRIES`, `DCACHE_RESP_QUEUE_DEPTH`로 조절할 수 있다.

현재 adapter는 여러 요청과 ID를 queue에 보존하지만 AXI read engine 자체는 한 번에 한 burst만 진행한다. 즉 MSHR는 LSU와 cache request 경로의 직렬화를 제거하고 miss를 대기열에 겹쳐 놓지만, 여러 AXI AR을 동시에 outstanding으로 만드는 구조는 아니다. 그 단계까지 확장하려면 AXI ID별 refill beat 조립 table과 여러 outstanding AR credit 관리가 추가로 필요하다. 동일 cache line miss coalescing도 아직 구현하지 않았다.

## 12. 장시간 성능 TB와 최종 결과

TB에 다음 구간을 추가했다.

- 서로 다른 네 cache line에서 독립 `LW` 네 개를 연속 수행하고 합이 10인지 검사하는 MSHR stress 구간
- 5개 instruction loop를 128회 반복하는 warm frontend 구간
- 동적 retired instruction 기대값과 warm-loop 전용 cycle/IPC 측정
- fetch metadata/packet FIFO 점유율, I-cache hit/miss, D-cache MSHR 점유율 및 request/response counter

Vivado 2025.1 clean compile/elaboration 후 703-instruction test 결과는 모두 PASS했다.

```text
Total cycles                  = 1003
Retired instructions          = 703
Overall IPC                   = 0.7009
Core IPC                      = 0.7233
Warm-loop instructions/cycles = 640 / 680
Warm-loop IPC                 = 0.9412
I-cache hit/miss responses    = 707 / 18
Metadata FIFO avg/max/full    = 0.98 / 1 / 0
Packet FIFO avg/max/full      = 0.75 / 7 / 0
LQ maximum occupancy          = 4
D-cache MSHR avg/max/full     = 0.35 / 5 / 0
```

Warm hit 구간 IPC 0.9412는 frontend가 매-cycle에 가까운 속도로 공급하는 것을 보여준다. 1.0과의 차이는 loop branch recovery와 pipeline fill/drain 때문이다. 전체 IPC 0.7009에는 cold I-cache miss 18회, control recovery, memory latency가 포함된다.

D-cache counter의 CPU request/lower request/response가 `27/27/26`인 것은 counter 집계가 final DONE store retire 시점에 끝나고, 그 store의 bus response는 그 뒤에 도착하기 때문이다. TB는 signature memory 반영까지 별도로 기다린 뒤 PASS하므로 transaction loss를 뜻하지 않는다.
