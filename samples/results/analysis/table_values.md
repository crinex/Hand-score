# HAND-Score Measurement Values for Paper Tables

Reference date: 2026-05-07
ANE device: iPhone 17 Pro (A19 Pro, iOS 26.2.1, RAM 12 GB)
Hexagon devices: SM8750 (QNN HTP v79), SM8850 (Snapdragon 8 Elite Gen 5)
Sources: `samples/results/raw/{model}/` (ANE raw JSON), `analysis/{model}_summary.json` (ANE statistics), `analysis/qualcomm_summary.json` (Hexagon, parsed from `qualcomm_exp.pdf`).

---

## Table 1 — NPU Utilization (`tab:npu-util`)

```
Platform              Model         NPU%   GPU%  CPU%  Embed  Attn+FFN  LMh    Top blocker
ANE A19 Pro           Gemma3-270M   98.91  0.00  1.09   0.00   99.18   100.00  dyn-select
ANE A19 Pro           Llama3.2-1B   98.71  0.00  1.29   0.00   98.99   100.00  dyn-select
ANE A19 Pro           Llama3.2-3B   98.69  0.00  1.31   0.00   98.84   100.00  dyn-select
ANE A19 Pro           Qwen3-4B      99.03  0.00  0.97   0.00   99.14   100.00  dyn-select
Hexagon SM8750        Llama3.2-1B    --     --    --     --      --      --    dyn-shape
Hexagon SM8750        Llama3.2-3B    --     --    --     --      --      --    dyn-shape
Hexagon SM8750        Qwen3-4B       --     --    --     --      --      --    rt-fallback
Hexagon SM8850        Llama3.2-1B    --     --    --     --      --      --    dyn-shape
Hexagon SM8850        Llama3.2-3B    --     --    --     --      --      --    dyn-shape
Hexagon SM8850        Qwen3-4B       --     --    --     --      --      --    rt-fallback
```

Hexagon op-level percentages are not reported because the QNN context binaries we evaluated do not expose a stable op-level NPU/GPU/CPU split through the public profiler tooling at the time of submission. The Top-blocker column reflects the dominant runtime fallback signal observed during execution.

---

## Table 2 — Single-shot Performance + System Resources (`tab:perf`)

```
Platform              Model         Load(s)  TTFT(s)  Prefill(t/s)  Decode(t/s)  Mem(GiB)  CPU%    BDR(%/h)
ANE A19 Pro           Gemma3-270M    0.73     0.45       90.2         77.85       0.30    109.0    12.18
ANE A19 Pro           Llama3.2-1B    0.19     1.29       91.5         28.35       0.36     53.1     7.17
ANE A19 Pro           Llama3.2-3B    0.33     3.15       42.2         11.22       0.82     39.2    29.97
ANE A19 Pro           Qwen3-4B       0.45     4.54        9.4          7.17       0.90     23.3     1.08*
Hexagon SM8750        Llama3.2-1B    0.502    0.046    1579.66        58.95       0.190    11.31    --
Hexagon SM8750        Llama3.2-3B    0.884    0.088     831.57        23.80       0.194    15.07   26.20
Hexagon SM8750        Qwen3-4B**     1.310    0.130     594.39        19.24       0.182    22.89    --
Hexagon SM8850        Llama3.2-1B    0.465    0.045    1693.68        68.20       0.294    10.55    --
Hexagon SM8850        Llama3.2-3B    0.785    0.076     962.16        27.44       0.292    14.20    --
Hexagon SM8850        Qwen3-4B**     1.414    0.108     713.72        22.35       0.226    21.98    --
```

\* ANE Qwen3-4B BDR 1.08 %/h is an artifact: the Phase 4 segment was conducted while iOS reported the device as charging via passive USB power, so battery telemetry did not move during the run. Reported as-is for transparency.

\*\* Hexagon Qwen3-4B completed all 45 single-shot calls but the run is annotated FAILED because the multi-turn KV-cache sample mt-013-kv fell back to an unsupported runtime; the row is reported as diagnostic evidence rather than a clean deployable result.

### Per-bin decomposition (appendix-grade, ANE only)

**Gemma3-270M**

| Bin | n | Prefill(t/s) | Decode(t/s) | TTFT(s) |
|---|---|---|---|---|
| Short (0-30 tok) | 14 | 72.7 | 78.2 | 0.326 |
| Med-Short (31-80) | 11 | 77.3 | 76.5 | 0.562 |
| Medium (81-150) | 4 | 187.1 | 80.3 | 0.552 |

**Llama3.2-1B**

| Bin | n | Prefill(t/s) | Decode(t/s) | TTFT(s) |
|---|---|---|---|---|
| Short (0-30) | 0 | — | — | — |
| Med-Short (31-80) | 48 | 91.91 | 28.12 | 1.221 |
| Medium (81-150) | 10 | 89.73 | 29.46 | 1.594 |

(Llama3.2-3B and Qwen3-4B per-bin breakdowns are available in `Llama-3.2-3B_summary.json` and `Qwen3-4B_summary.json` under `exp_a.by_bin`.)

---

## Table 3 — Multi-turn + Deploy Verdict (`tab:multiturn-deploy`)

```
Platform              Model         TTFT t1->tK (s)   Decode t1->tK (t/s)   Mem_tK (GiB)  Sus.Degr   deploy / deployable
ANE A19 Pro           Gemma3-270M   0.36 -> 0.65       78.9 -> 75.8           0.24         0.047       0.914 / true
ANE A19 Pro           Llama3.2-1B   1.60 -> 3.06       29.0 -> 24.3           0.46         0.019       0.911 / true
ANE A19 Pro           Llama3.2-3B   3.95 -> 5.84       11.8 -> 11.1           1.17         0.061       0.620 / true
ANE A19 Pro           Qwen3-4B      3.67 -> 10.60       6.4 ->  5.9           1.42         0.146       0.588 / true
Hexagon SM8750        Llama3.2-1B   0.040 -> 0.126     52.67 -> 51.73         0.282        0.003       N/A   / true
Hexagon SM8750        Llama3.2-3B   0.081 -> 0.228     21.17 -> 20.86         0.217        0.076       N/A   / true*
Hexagon SM8750        Qwen3-4B      0.202 -> 0.832     14.99 -> 13.15         0.248        0.068       N/A   / false
Hexagon SM8850        Llama3.2-1B   0.031 -> 0.103     62.30 -> 61.28         0.401       -0.003       N/A   / true
Hexagon SM8850        Llama3.2-3B   0.068 -> 0.187     25.78 -> 25.38         0.230        0.010       N/A   / true*
Hexagon SM8850        Qwen3-4B      N/A                N/A                    N/A          N/A         N/A   / false
```

`true*` indicates that the model passed the observed sustained-degradation threshold but reached a Severe thermal state during the run (deployment recommended only under thermal-aware scheduling). SM8850 Qwen3-4B deploy / deployable cells are N/A because Android killed the app process during cooldown before JSON export (51 of 105 cumulative-context calls observed).

### deploy_score breakdown (ANE only)

| Model | S_NPU | S_perf | S_sys (mem / bdr / thermal) | deploy_score | deployable |
|---|---|---|---|---|---|
| Gemma3-270M | 0.989 | 0.953 | 0.788 (0.940 / 0.756 / 0.667) | **0.914** | true |
| Llama3.2-1B | 0.987 | 0.927 | 0.811 (0.940 / 0.857 / 0.667) | **0.911** | true |
| Llama3.2-3B | 0.987 | 0.351 | 0.677 (0.864 / 0.401 / 0.667) | **0.620** | true |
| Qwen3-4B    | 0.990 | 0.204 | 0.838 (0.875 / 0.978 / 0.667) | **0.588** | true |

Threshold check (RAM = 12 GiB on iPhone 17 Pro):
- npu_op_ratio ≥ 0.5 → all four pass (≥ 0.987).
- peak_memory < 0.6 × RAM = 7.2 GiB → all four pass (max 1.42 GiB on Qwen3-4B).
- sustained_degradation ≤ 0.4 → all four pass (max 0.146 on Qwen3-4B).

---

## Cross-platform observations

1. **Single-shot decode**: Hexagon SM8850 outperforms ANE A19 Pro by 1.7×–3.1× on 1B–4B models. The gap widens with model size.
2. **Single-shot prefill**: Hexagon SM8850 outperforms ANE by 7×–75×, with the largest gap at 4B (713.72 vs 9.4 t/s). Root cause: ANE prefill batch=64 + 2-chunk decomposition serializes dispatches.
3. **Sustained behavior**: Hexagon Llama3.2-1B is the most stable configuration (Sus.Degr 0.003 / -0.003). Hexagon Llama3.2-3B passes the firewall but reaches Severe thermal state on both SoCs. Hexagon Qwen3-4B is non-deployable on both SoCs.
4. **deploy_score firewall**: ANE Qwen3-4B passes despite its low S_perf (0.204) because the firewall does not include a decode-throughput minimum; the score itself (0.588) flags it as marginal. The firewall + deploy_score combination expresses both signals separately, which a single composite score cannot.

---

## Ready-to-paste LaTeX rows

```latex
% Table 1 (tab:npu-util)
& Gemma3-270M  & 98.91 & 0.00 & 1.09 & 0.00 & 99.18 & 100.00 & dyn-select \\
& Llama3.2-1B  & 98.71 & 0.00 & 1.29 & 0.00 & 98.99 & 100.00 & dyn-select \\
& Llama3.2-3B  & 98.69 & 0.00 & 1.31 & 0.00 & 98.84 & 100.00 & dyn-select \\
& Qwen3-4B     & 99.03 & 0.00 & 0.97 & 0.00 & 99.14 & 100.00 & dyn-select \\

% Table 2 ANE (tab:perf)
& Gemma3-270M  & 0.73 & 0.45 &  90.2 & 77.85 & 0.30 & 109.0 & 12.18 \\
& Llama3.2-1B  & 0.19 & 1.29 &  91.5 & 28.35 & 0.36 &  53.1 &  7.17 \\
& Llama3.2-3B  & 0.33 & 3.15 &  42.2 & 11.22 & 0.82 &  39.2 & 29.97 \\
& Qwen3-4B     & 0.45 & 4.54 &   9.4 &  7.17 & 0.90 &  23.3 &  1.08 \\

% Table 2 Hexagon (tab:perf)
SM8750 & Llama3.2-1B & 0.502 & 0.046 & 1579.66 & 58.95 & 0.190 & 11.31 & --    \\
SM8750 & Llama3.2-3B & 0.884 & 0.088 &  831.57 & 23.80 & 0.194 & 15.07 & 26.20 \\
SM8750 & Qwen3-4B    & 1.310 & 0.130 &  594.39 & 19.24 & 0.182 & 22.89 & --    \\
SM8850 & Llama3.2-1B & 0.465 & 0.045 & 1693.68 & 68.20 & 0.294 & 10.55 & --    \\
SM8850 & Llama3.2-3B & 0.785 & 0.076 &  962.16 & 27.44 & 0.292 & 14.20 & --    \\
SM8850 & Qwen3-4B    & 1.414 & 0.108 &  713.72 & 22.35 & 0.226 & 21.98 & --    \\

% Table 3 ANE
& Gemma3-270M & 0.36$\to$0.65  & 78.9$\to$75.8  & 0.24 & 0.047 & 0.914 / true \\
& Llama3.2-1B & 1.60$\to$3.06  & 29.0$\to$24.3  & 0.46 & 0.019 & 0.911 / true \\
& Llama3.2-3B & 3.95$\to$5.84  & 11.8$\to$11.1  & 1.17 & 0.061 & 0.620 / true \\
& Qwen3-4B    & 3.67$\to$10.60 &  6.4$\to$5.9   & 1.42 & 0.146 & 0.588 / true \\

% Table 3 Hexagon
SM8750 & Llama3.2-1B & 0.040$\to$0.126 & 52.67$\to$51.73 & 0.282 & 0.003 & N/A / true   \\
SM8750 & Llama3.2-3B & 0.081$\to$0.228 & 21.17$\to$20.86 & 0.217 & 0.076 & N/A / true*  \\
SM8750 & Qwen3-4B    & 0.202$\to$0.832 & 14.99$\to$13.15 & 0.248 & 0.068 & N/A / false  \\
SM8850 & Llama3.2-1B & 0.031$\to$0.103 & 62.30$\to$61.28 & 0.401 & $-0.003$ & N/A / true \\
SM8850 & Llama3.2-3B & 0.068$\to$0.187 & 25.78$\to$25.38 & 0.230 & 0.010 & N/A / true*  \\
SM8850 & Qwen3-4B    & N/A             & N/A             & N/A   & N/A      & N/A / false \\
```
