# HAND-Score-Hexagon (placeholder)

> **This folder is a placeholder for the Android / Qualcomm Hexagon NPU measurement application referenced in the paper *HAND-Score: The Standard for Evaluating LLMs on Mobile NPUs*.** The Hexagon app is maintained separately from the iOS app under `../HAND-Score-iOS/` and will be filled in here by its maintainer.

The iOS / Apple Neural Engine counterpart is fully released under [`../HAND-Score-iOS/`](../HAND-Score-iOS/) and the shared dataset, host-side analysis pipeline, and result schema are described in the top-level [`../README.md`](../README.md).

---

## What the Hexagon app must produce

To remain consistent with the iOS run and with the paper's host-side aggregation pipeline (`samples/results/analysis/build_summary.py`), the Hexagon app MUST:

1. **Consume the same prompt set** — `samples/chatalpaca_handscore.json` (30 single-turn + 15 multi-turn samples). No re-extraction or substitution.
2. **Execute the six-phase HAND-Score protocol** (Phase 0 environment prep through Phase 5 result aggregation) as described in the top-level README.
3. **Run the three experiments** with the exact same calling convention:
    - Exp A — 30 ChatAlpaca single-turn prompts with a 10-second cool-down
    - Exp C — repeat one single-turn prompt for `N_round` rounds with **no cool-down**
    - Exp E — 15 multi-turn dialogues; **re-prefill the entire chat history at every assistant turn (no KV-cache reuse)**
4. **Emit one JSON file per LLM call** to device storage with the same top-level schema as the iOS app (see `../HAND-Score-iOS/README.md` § "Result JSON schema"). The shared fields are:
    - `id`, `timestamp`
    - `device.{model, name, chip, osVersion}`
    - `model.{name, path, contextLength, batchSize}`
    - `config.{prompt, maxTokens, temperature, mode}`
    - `performance.{modelLoadTimeMs, prefillTimeMs, prefillTokens, prefillTokensPerSec, decodeTokens, decodeTimeMs, decodeTokensPerSec, ttftMs, totalTokens, totalTimeMs}`
    - `system.{before, after, timeline[]}` (battery / memory / thermal samples)
    - `generatedText`
    - `npuProfile` (analogous to the iOS `aneProfile` — Hexagon op-level mapping)
    - `turnResults` (populated only in `multi_turn` mode)
5. **Use deterministic decoding** (`temperature = 0.0`) so run-to-run variation comes only from device thermal state and OS scheduling.

The host-side aggregator deliberately separates the three experiments by inspecting `config.mode` and the repetition count of `config.prompt`; the Hexagon app does not need to tag experiments explicitly.

---

## What this folder must contain (checklist)

The maintainer should replace this placeholder README and add the following items so the Hexagon app reaches release parity with `../HAND-Score-iOS/`:

- [ ] `README.md` — build & run guide, supported SoC list, requirements (min Android version, NDK / Android Studio / Gradle), installation prerequisites
- [ ] Source tree for the Android measurement app (Kotlin / Java + Hexagon SDK glue)
- [ ] Gradle / build configuration
- [ ] Reference to the Hexagon-converted model catalog (HuggingFace repos with the same quantization scheme, context length, and prefill batch size as the ANE catalog in `../HAND-Score-iOS/README.md`)
- [ ] Host-side retrieval command (the `adb pull` analogue of `xcrun devicectl device copy from`)
- [ ] `LICENSE` — license for the Hexagon app sources (the host-side scripts and the iOS app are MIT)
- [ ] Per-platform notes on reproducibility, including any field-by-field deviations from the iOS JSON schema and the workaround applied in `samples/results/analysis/build_summary.py`

---

## How the Hexagon results enter the published tables

The paper's Hexagon numbers (`samples/results/analysis/qualcomm_summary.json`) were generated from `qualcomm_exp.pdf` and merged into `samples/results/analysis/all_summary.json` by `build_summary.py`. Once the Hexagon app is integrated, raw per-call JSONs from supported Snapdragon devices (paper reports SM8750 and SM8850) should be dropped into a directory analogous to `samples/results/raw/<model-name>/` and `build_summary.py` should be extended to ingest them through the same code path as the ANE JSONs.
