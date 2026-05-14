# HAND-Score Hexagon Android Benchmark App

This folder contains the Qualcomm Hexagon Android benchmark scaffold for HAND-Score. It is organized to mirror the iOS app: source code and reproducibility instructions are committed, while device-specific binaries, model weights, APK exports, and Qualcomm runtime artifacts stay outside Git.

No Git LFS is required for this repository.

---

## What the app measures

For each model under test, the Hexagon benchmark app should produce per-call JSON reports for the same HAND-Score experiments used by the iOS app.

| Experiment | Mode in the JSON | Description |
|---|---|---|
| Exp A - Single-shot baseline | `single_turn` | 30 ChatAlpaca prompts (15 Short / 10 Med-Short / 5 Medium) with a 10-second cool-down between calls. |
| Exp C - Thermal stress | `single_turn` (same prompt repeated 30+ times) | Repeats one sample for `N_round` rounds with no cool-down to compute `sustained_degradation`. |
| Exp E - Multi-turn cumulative-context | `multi_turn` | 15 ChatAlpaca dialogues (5 x 4 turns, 5 x 5 turns, 5 x 6 turns). The entire chat history is re-prefilled from scratch at every assistant turn. |
| Exp D - NPU profile | embedded in every JSON | Qualcomm Hexagon runtime profile data should be included in the JSON so the host pipeline can compare per-stage NPU utilization. |

Per-call metrics should include: `model_load_time`, `TTFT`, `prefill_throughput`, `decode_throughput`, `total_time`, `peak_memory`, `cpu_usage`, `battery_drain_rate`, and the Hexagon NPU profile.

---

## Requirements

| Item | Requirement |
|---|---|
| Android device | Qualcomm Snapdragon device with Hexagon NPU (paper reports SM8750 / SM8850 family) |
| Android OS | Android 12 / API 31 or later |
| Android Studio | Stable Android Studio with Android SDK support |
| Gradle | Use the committed Gradle wrapper (`./gradlew`) |
| ADB | USB or ADB-over-Wi-Fi for install and result retrieval |
| Qualcomm artifacts | Keep QNN / Hexagon SDK files, model binaries, and exported APKs local to the developer machine |

---

## Project layout

```text
HAND-Score-Hexagon/
├── README.md
├── app/
│   ├── build.gradle.kts
│   └── src/main/
│       ├── AndroidManifest.xml
│       ├── java/com/handscore/hexagon/MainActivity.java
│       └── res/values/
├── build.gradle.kts
├── gradle/
├── gradle.properties
├── gradlew
├── gradlew.bat
└── settings.gradle.kts
```

The repository intentionally does not include:

- APKs (`*.apk`, `*.aab`)
- model weights or converted graphs
- Qualcomm QNN / Hexagon SDK binaries
- raw benchmark result dumps

If local binary artifacts are needed while developing, place them under `HAND-Score-Hexagon/artifacts/` or `HAND-Score-Hexagon/prebuilt/`. Those directories are ignored by Git.

---

## App metadata

- App name: `HAND-Score`
- Package: `com.handscore.hexagon`
- Version: `0.1.0`
- Version code: `1`
- Minimum SDK: API 31
- Target SDK: API 36

---

## Build and run

Open the project in Android Studio:

```bash
open HAND-Score-Hexagon
```

Or build from the command line:

```bash
cd HAND-Score-Hexagon
./gradlew assembleDebug
```

Install the debug build on a connected Qualcomm device:

```bash
adb install -r app/build/outputs/apk/debug/app-debug.apk
```

The committed Android module is a source scaffold. It keeps the same package metadata and result schema expected by the host-side HAND-Score pipeline, but it does not commit large or proprietary runtime assets.

---

## Local artifacts

Use local-only artifact paths for device-specific pieces:

```text
HAND-Score-Hexagon/artifacts/
├── qnn/            # local Qualcomm runtime files, if needed
├── models/         # local converted model assets
└── results/        # local result exports before aggregation
```

These paths are ignored by Git so the repository can be pushed to GitHub without Git LFS.

---

## Retrieving results to the host machine

The Hexagon benchmark should write JSON reports to device storage. A typical retrieval command is:

```bash
adb pull /sdcard/Android/data/com.handscore.hexagon/files/HAND-Score /tmp/handscore_results
```

The host-side analysis pipeline expects those JSON files to be available locally for aggregation.

---

## Expected result JSON schema

The Hexagon app should produce JSON output aligned with the iOS benchmark pipeline, with fields such as:

- `mode`
- `config.prompt`
- `performance.*`
- `system.before`
- `system.after`
- `timeline`
- `npuProfile`
- `turnResults`

Example structure:

```jsonc
{
  "id": "<UUID>",
  "timestamp": "<ISO-8601>",
  "device": { "model": "...", "chip": "...", "osVersion": "..." },
  "model": { "name": "...", "contextLength": 4096, "batchSize": 64 },
  "config": { "prompt": "...", "mode": "single_turn" },
  "performance": {
    "model_load_time": 0,
    "prefill_throughput": 0,
    "decode_throughput": 0,
    "total_time": 0
  },
  "system": {
    "before": {},
    "after": {},
    "timeline": []
  },
  "npuProfile": {},
  "turnResults": []
}
```

This schema is aligned with the iOS benchmark JSON so the same host-side aggregation workflow can be reused.

---

## Notes

- The package namespace is de-identified as `com.handscore.hexagon`.
- Large Android artifacts are intentionally excluded from Git.
- The shared prompt set is committed at `../samples/chatalpaca_handscore.json` in the repository root.
