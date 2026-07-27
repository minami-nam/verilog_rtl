# README Image Assets

이 디렉터리는 프로젝트 README와 상세 문서에 사용할 이미지 파일을 저장합니다.

| File | Purpose |
|---|---|
| `architecture-overview.png` | 전체 Controller 블록 다이어그램 |
| `write-path-timing.png` | AW/W transaction 흐름 |
| `response-routing.png` | B/R 응답 라우팅 구조 |
| `exclusive-access.png` | Exclusive 성공/실패 sequence |
| `simulation-waveform.png` | 대표 simulation waveform |
| `scoreboard-result.png` | Scoreboard 실행 결과 |
| `implementation-result.png` | Vivado timing/utilization 결과 |

README에서는 다음처럼 상대 경로로 참조할 수 있습니다.

```markdown
![System architecture](docs/images/architecture-overview.png)
```

이미지는 가능하면 PNG 또는 SVG 형식을 사용하고, 파일 이름에는 공백 대신 하이픈을 사용하세요.
