# HAND-Score iOS Benchmark App

This is the iOS measurement application that produces the Apple Neural Engine (ANE) results reported in the paper *HAND-Score: The Standard for Evaluating LLMs on Mobile NPUs*. It implements the six-phase HAND-Score protocol for ANE-converted LLMs and exports per-call JSON reports that are aggregated into the four-axis tables of the paper.

The app's display name on the Home Screen is **HAND-Score**.

---

## What the app measures

For each model selected from the catalog, the app runs the following experiments and writes one JSON file per call to the app's `Documents/HAND-Score/` container.

| Experiment | Mode in the JSON | Description |
|---|---|---|
| Exp A — Single-shot baseline | `single_turn` | 30 ChatAlpaca prompts (15 Short / 10 Med-Short / 5 Medium) with a 10-second cool-down between calls. |
| Exp C — Thermal stress | `single_turn` (same prompt repeated 30+ times) | The same sample is repeated for `N_round` rounds with **no cool-down**, used to compute `sustained_degradation`. |
| Exp E — Multi-turn cumulative-context | `multi_turn` | 15 ChatAlpaca dialogues (5 of 4 turns, 5 of 5 turns, 5 of 6 turns). At every assistant turn the entire chat history is re-prefilled from scratch (no KV-cache reuse). |
| Exp D — NPU profile | embedded in every JSON | Op-level NPU/GPU/CPU mapping extracted via the iOS 17.4+ `MLComputePlan` API, classified into Embed / Attn+FFN / LM head per ANEMLL component. |

Per-call metrics: `model_load_time`, `TTFT`, `prefill_throughput` (defined as `N_prompt / TTFT`, the standard convention used by Genie/llama.cpp/vLLM), `decode_throughput`, `total_time`, `peak_memory`, `cpu_usage`, `battery_drain_rate` (BDR), and the `MLComputePlan`-derived NPU profile.

---

## Requirements

| Item | Version |
|---|---|
| iOS device | iOS 17.4 or later (required for `MLComputePlan`) |
| iPhone | iPhone 15 Pro or later (Apple Neural Engine) — A19 Pro and A18 Pro have been validated against the paper results |
| macOS for building | macOS 14 or later |
| Xcode | 16 or later |
| Swift | 6.0 |
| Apple Developer account | A free personal team is enough for sideloading; signing must succeed |

---

## Project layout

```
HAND-Score-iOS/
├── README.md                           # this file
├── LICENSE                             # MIT license for the HAND-Score app code
├── HAND-Score.xcodeproj                  # Xcode project (target name kept as HAND-Score, display name "HAND-Score")
├── Package.swift                       # SwiftPM manifest for HandScoreCore + Yams dependencies
├── HandScoreCore/                      # vendored ANE inference runtime (originally AnemllCore, MIT)
│   ├── Package.swift                   # library target manifest
│   ├── LICENSE-AnemllCore              # upstream MIT notice
│   └── Sources/HandScoreCore/          # 7 .swift files (InferenceManager, Tokenizer, ModelLoader, ...)
└── HAND-Score/                         # app source
    ├── App/HandScoreApp.swift           # @main entry point
    ├── Models/
    │   ├── BenchmarkResult.swift       # JSON-serializable schema for results
    │   ├── ChatAlpacaDataset.swift     # bundled dataset reader
    │   ├── ModelCatalog.swift          # downloadable-model catalog (5 entries)
    │   └── SystemMetrics.swift         # 1-second timeline samples + before/after snapshots
    ├── Services/
    │   ├── ANEProfiler.swift           # MLComputePlan-based op-level analyzer
    │   ├── BenchmarkRunner.swift       # orchestrator (load → warm-up → run → profile → save)
    │   ├── HuggingFaceService.swift    # in-app downloader for the optai-inc/*-4096-ANE catalog
    │   ├── MetricsCollector.swift      # Timer-driven CPU/memory/thermal sampler
    │   └── ResultStore.swift           # writes one JSON per call to Documents/HAND-Score/
    ├── ViewModels/BenchmarkViewModel.swift
    ├── Views/
    │   ├── BenchmarkView.swift         # main screen
    │   ├── ModelCardView.swift         # model picker (bundled + downloadable)
    │   ├── ResultsListView.swift       # saved-result list
    │   └── ResultDetailView.swift      # per-result detail + share-as-JSON
    └── Datasets/
        └── chatalpaca_handscore.json    # 30 single-turn + 15 multi-turn samples (extracted by scripts/extract_samples.py)
```

---

## Building and running

1. **Clone or extract the project**. The repository is self-contained: the ANE inference runtime lives at `HandScoreCore/` as a local SwiftPM package, so no sibling repository is required.

2. **Open the project in Xcode**:
   ```
   open HAND-Score.xcodeproj
   ```

3. **Set the signing team**: select the `HAND-Score` target → *Signing & Capabilities* → choose your team. **`DEVELOPMENT_TEAM` is intentionally left empty in `project.pbxproj`**, so Xcode will prompt you to pick your own Apple Developer Team on first build. The bundle identifier may be changed; the display name `HAND-Score` is hard-coded via `INFOPLIST_KEY_CFBundleDisplayName`.

4. **Connect a supported iPhone** and select it as the run destination. The first launch will install the app under the display name **HAND-Score**.

5. **Press Run (⌘R)**. The first build resolves the SwiftPM dependencies (`HandScoreCore` and its transitive dependencies: `swift-transformers`, `Stencil`, `Yams`); subsequent builds are incremental.

The app contains no bundled model. Models are obtained at runtime through the in-app HuggingFace downloader.

---

## How to reproduce the paper results

The four ANE-converted models reported in the paper are published under the `optai-inc/*-4096-ANE` namespace and are available in the in-app downloader:

| Display name | HuggingFace repo |
|---|---|
| Gemma 3 270M | [`optai-inc/Gemma3-270m-4096-ANE`](https://huggingface.co/optai-inc/Gemma3-270m-4096-ANE) |
| Gemma 3 1B | [`optai-inc/Gemma3-1b-4096-ANE`](https://huggingface.co/optai-inc/Gemma3-1b-4096-ANE) |
| Llama 3.2 1B | [`optai-inc/Llama-3.2-1B-4096-ANE`](https://huggingface.co/optai-inc/Llama-3.2-1B-4096-ANE) |
| Llama 3.2 3B | [`optai-inc/Llama-3.2-3B-4096-ANE`](https://huggingface.co/optai-inc/Llama-3.2-3B-4096-ANE) |
| Qwen 3 4B | [`optai-inc/Qwen3-4B-4096-ANE`](https://huggingface.co/optai-inc/Qwen3-4B-4096-ANE) |

All entries share the same conversion options: 4-bit FFN weights, 6-bit LM-head weights, fp16 activations, context length 4096, prefill batch size 64, and a 2-chunk decomposition for the 3B/4B graphs.

### Step-by-step reproduction protocol

1. **Phase 0 — Environment preparation** (per the paper, manual on the device).
   - Charge the iPhone above 80%, then disconnect external power.
   - Wait at least 5 minutes after charge until the surface temperature returns to nominal.
   - Quit background apps; fix screen brightness; set Auto-Lock to "Never".

2. **Phase 1 — Download a model**. Tap the download icon on a catalog card. Progress is displayed inside the card.

3. **Phase 2 — Warm-up**. Run a single benchmark with default parameters (`Run Benchmark` button) and discard the result; this stabilizes the ANE compilation cache.

4. **Phase 3 — Single-shot baseline (Exp A)**.
   - Mode: `Single-Turn` (default).
   - Tap **Run ChatAlpaca 30 samples** under the *Exp A — Single-turn Batch* section.
   - The app cycles through all 30 ChatAlpaca single-turn samples with a 10-second cool-down between calls; one JSON is saved per call.

5. **Phase 4 — Sustained performance**.
   - **Exp C (Thermal stress)**: pick a single-turn sample from the picker, set `Rounds` (default 30), and tap *Run thermal stress for N rounds* under *Exp C — Thermal Stress*. Cool-down is intentionally skipped.
   - **Exp E (Multi-turn cumulative-context)**: switch the mode to `Multi-Turn (KV Cache)`, then tap **Run ChatAlpaca 15 samples** under *Exp E — Multi-turn Batch*. The app re-prefills the entire history at every assistant turn.

6. **Phase 5 — Result aggregation**. Tap **Results** in the top-right toolbar to inspect each saved JSON, share it via *Share*, or use the off-device retrieval below.

### Retrieving results to the host machine

Each call writes one JSON to the app's container at `Documents/HAND-Score/bench_<model>_<YYYYMMDD_HHMMSS>.json`. The host-side aggregation pipeline used in the paper expects all of these files to live under a single directory, which can be retrieved over USB or Wi-Fi (paired devices) with:

```bash
xcrun devicectl device copy from \
  --device <device-uuid> \
  --domain-type appDataContainer \
  --domain-identifier com.optai.handscore \
  --source Documents \
  --destination /tmp/handscore_results
```

Replace `<device-uuid>` with the value reported by `xcrun devicectl list devices`. The paper's analysis scripts (under `samples/results/analysis/build_summary.py` of the project root, outside this app folder) parse the JSON files in this directory and produce the deploy-score / deployable verdict tables.

---

## Result JSON schema (summary)

Each per-call JSON has the following top-level structure:

```jsonc
{
  "id": "<UUID>",
  "timestamp": "<ISO-8601>",
  "device": { "model": "iPhone18,1", "name": "iPhone 17 Pro", "chip": "A18 / A18 Pro", "osVersion": "..." },
  "model":   { "name": "...", "path": "...", "contextLength": 4096, "batchSize": 64, "isMonolithic": false },
  "config":  { "prompt": "...", "maxTokens": 256, "temperature": 0.0, "mode": "single_turn" },
  "performance": { "modelLoadTimeMs": ..., "prefillTimeMs": ..., "prefillTokens": 97, "prefillTokensPerSec": ..., "decodeTokens": ..., "decodeTimeMs": ..., "decodeTokensPerSec": ..., "ttftMs": ..., "totalTokens": ..., "totalTimeMs": ... },
  "system": {
    "before": { "batteryLevel": 0.85, "batteryState": "unplugged", "memoryUsageMB": ..., "availableMemoryMB": ..., "thermalState": 0 },
    "after":  { ... },
    "timeline": [ { "timestamp": 0, "memoryUsageMB": ..., "availableMemoryMB": ..., "cpuUsagePercent": ..., "thermalState": 0 }, ... ]
  },
  "generatedText": "...",
  "aneProfile": {
    "totalOps": 1650, "aneOps": 1632, "gpuOps": 0, "cpuOps": 18, "anePercentage": 98.91,
    "components": [ { "name": "gemma3_FFN_PF_lut4_chunk_01of01", "anePercentage": 99.18, ... }, ... ],
    "aneBlockers": [ "gemma3_embeddings: select (1x) - dynamic control flow", ... ],
    "topCostOps": [ ... ]
  },
  "turnResults": null   // populated only in multi-turn mode (one entry per user/assistant turn)
}
```

The `mode` field plus the `prompt` field are sufficient to separate the three experiments after the fact: a `single_turn` JSON whose `config.prompt` repeats more than 20 times in a session belongs to Exp C; the remaining `single_turn` JSONs belong to Exp A; `multi_turn` JSONs belong to Exp E.

---

## Notes on reproducibility

- All decoding is greedy (`temperature = 0.0`); the prompt set is fixed and committed (`Datasets/chatalpaca_handscore.json`); the only sources of run-to-run variation are device thermal state and OS-level scheduling.
- The Apple Neural Engine path is a closed-source runtime; we do not redistribute model weights and instead reference the public `optai-inc/*-4096-ANE` HuggingFace repositories.
- The `MLComputePlan` API requires iOS 17.4+; on earlier iOS versions the `aneProfile` field of every JSON is absent and the NPU-utilization axis cannot be filled in. The app still runs on iOS 17.4+ devices that lack the ANE entirely (e.g., iPhone SE) but the NPU% report becomes meaningless.
- The Hexagon NPU experiments reported in the paper are not produced by this app; the corresponding Android measurement application is referenced separately in the paper's appendix.

---

## License

The HAND-Score app code in this repository is released under the MIT license; the full text is in [`LICENSE`](LICENSE).

The bundled `chatalpaca_handscore.json` derives from [robinsmits/ChatAlpaca-20K](https://huggingface.co/datasets/robinsmits/ChatAlpaca-20K) and is redistributed under that dataset's license. Model weights downloaded at runtime are subject to the respective model licenses (Gemma Terms of Use, Llama Community License, Qwen license).

## Acknowledgements

The `HandScoreCore/` package vendors the Apple Neural Engine inference runtime originally published as `AnemllCore` by the [ANEMLL](https://github.com/Anemll/Anemll) project under the MIT license. The source files were renamed and repackaged so the HAND-Score app can be built without the surrounding ANEMLL repository; the upstream copyright notice is preserved in [`HandScoreCore/LICENSE-AnemllCore`](HandScoreCore/LICENSE-AnemllCore) and per-file attribution headers were prepended to each `.swift` file in `HandScoreCore/Sources/HandScoreCore/`. No functional changes were made to the runtime logic.
