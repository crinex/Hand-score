# HAND-Score 측정 결과 저장소

논문 *HAND-Score: The Standard for Evaluating LLMs on Mobile NPUs* 의 iOS/ANE 측정 데이터.

기준일: 2026-05-07
디바이스: iPhone 17 Pro (iPhone18,1, iOS 26.2.1, RAM 12GB 가정)
앱 빌드: HAND-Score (`com.optai.handscore`), ModelCatalog v2 (5개 `optai-inc/*-4096-ANE`)

## 폴더 구조

```
samples/results/
├── README.md                       # 이 파일
├── raw/
│   ├── Gemma3-270m/                # 105 JSON (ANE)
│   ├── Llama-3.2-1B/               # 150 JSON (ANE)
│   ├── Llama-3.2-3B/               #  75 JSON (ANE)
│   └── Qwen3-4B/                   #  87 JSON (ANE)
└── analysis/
    ├── build_summary.py            # raw → summary 변환 스크립트 (ANE 4개 모델)
    ├── all_summary.json            # ANE 4개 모델 통합 요약
    ├── Gemma3-270m_summary.json
    ├── Llama-3.2-1B_summary.json
    ├── Llama-3.2-3B_summary.json
    ├── Qwen3-4B_summary.json
    ├── qualcomm_summary.json       # Qualcomm Hexagon (SM8750/SM8850, qualcomm_exp.pdf 파싱)
    └── table_values.md             # 논문 3개 표 채우기용 LaTeX 라인 (ANE+Hexagon 통합)
```

## 측정 분류

각 raw JSON은 `config.mode` 필드로 구분:

- `single_turn` — Exp A (단발성, ChatAlpaca 30 prompt) + Exp C (thermal stress, 동일 prompt 반복)
  - 분리 기준: 같은 prompt가 20회 이상 반복되면 thermal stress로 분류
- `multi_turn` — Exp E (cumulative-context 멀티턴, 4·5·6턴 대화)

## 결과 요약 (ANE A19 Pro)

| 모델 | Exp A 건수 | Exp C 라운드 | Exp E 대화 | deploy_score | deployable |
|---|---|---|---|---|---|
| Gemma3-270M | 29 (1회씩) | 61 (49분) | 15 (1회씩) | **0.914** | true |
| Llama-3.2-1B | 58 (29×2회) | 62 (125분) | 30 (15×2회) | **0.911** | true |
| Llama-3.2-3B | 29 (1회씩) | 31 | 15 (1회씩) | **0.620** | true |
| Qwen3-4B | 29 (1회씩) | 31 | 27 (15×~1.8회) | **0.588** | true |

## 결과 요약 (Hexagon — `qualcomm_summary.json` 참조)

| 모델 | SoC | sus_degr | Mem_tK (GiB) | deploy_score | deployable |
|---|---|---|---|---|---|
| Llama-3.2-1B | SM8750 | 0.003 | 0.282 | N/A | true |
| Llama-3.2-1B | SM8850 | -0.003 | 0.401 | N/A | true |
| Llama-3.2-3B | SM8750 | 0.076 | 0.217 | N/A | true* (Severe thermal) |
| Llama-3.2-3B | SM8850 | 0.010 | 0.230 | N/A | true* (Severe thermal) |
| Qwen3-4B | SM8750 | 0.068 | 0.248 | N/A | **false** (3 multi-turn 실패) |
| Qwen3-4B | SM8850 | N/A | N/A | N/A | **false** (Android process kill) |

## 분석 재생성

```bash
cd samples/results/analysis
python3 build_summary.py
```

raw 폴더의 JSON을 다시 읽어 summary JSON 3개를 새로 생성한다.

## 디바이스 회수 명령 (참고)

```bash
xcrun devicectl device copy from \
  --device 5CE158FC-B30D-559D-B706-BBB608101CA2 \
  --domain-type appDataContainer \
  --domain-identifier com.optai.handscore \
  --source Documents \
  --destination /tmp/handscore_results
```

USB 미연결 상태에서도 같은 Wi-Fi + 페어링된 디바이스이면 회수 가능.

## 다음 단계

- [ ] Llama-3.2-3B 측정
- [ ] Qwen3-4B 측정
- [ ] Gemma3-1B 측정 (huggingface 업로드 후)
- [ ] 모델별 결과 추가되면 `build_summary.py` 의 `MODELS` dict 확장 후 재실행
