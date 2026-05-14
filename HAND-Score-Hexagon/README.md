# HAND-Score Hexagon Android Benchmark App

This is the Android / Qualcomm Hexagon source project for HAND-Score. It is committed as a normal Android Studio project, not as a prebuilt APK:

- Gradle project files are committed (`settings.gradle.kts`, `build.gradle.kts`, `app/build.gradle.kts`, Gradle wrapper).
- Android source and resources live under `app/src/main/`.
- Build outputs, APKs, Android Studio local state, Qualcomm SDK files, model binaries, and raw result dumps are ignored.
- No Git LFS setup is required.

The app runs the same HAND-Score protocol used by the iOS project and writes one JSON result file per measured call. The committed backend is a reference Java backend so the UI, dataset loading, result schema, and host aggregation flow can be checked without proprietary Qualcomm artifacts. To reproduce paper numbers, replace `BackendFactory` with a Hexagon/QNN backend that implements `InferenceBackend`.

---

## What the app measures

For each model under test, the app produces per-call JSON reports for the same HAND-Score experiments used by the iOS app.

| Experiment | Mode in JSON | Description |
|---|---|---|
| Exp A - Single-shot baseline | `single_turn` | 30 ChatAlpaca prompts (15 Short / 10 Med-Short / 5 Medium) with a 10-second cool-down between calls. |
| Exp C - Thermal stress | `single_turn`, repeated prompt | Repeats the same prompt for 30 rounds with no cool-down so the host script can compute `sustained_degradation`. |
| Exp E - Multi-turn cumulative context | `multi_turn` | 15 ChatAlpaca dialogues (5 x 4 turns, 5 x 5 turns, 5 x 6 turns). At every assistant turn, the full accumulated chat history is re-prefilled from scratch. |
| Exp D - NPU profile | `npuProfile` | Backend-provided Hexagon / GPU / CPU op placement profile, aligned with the iOS `aneProfile` structure. |

Per-call metrics include `modelLoadTimeMs`, `ttftMs`, `prefillTokensPerSec`, `decodeTokensPerSec`, `totalTimeMs`, memory snapshots, CPU usage samples, battery state, thermal state, and the backend accelerator profile.

---

## Requirements

| Item | Requirement |
|---|---|
| Android device | Qualcomm Snapdragon device with Hexagon NPU (paper reports SM8750 / SM8850 family) |
| Android OS | Android 12 / API 31 or later |
| Android Studio | Stable Android Studio with Android SDK support |
| Gradle | Use the committed Gradle wrapper (`./gradlew`) |
| ADB | USB or ADB-over-Wi-Fi for install and result retrieval |
| Qualcomm artifacts | Keep QNN / Hexagon SDK files, model binaries, converted graphs, and signed release APKs local to the developer machine |

---

## Project layout

```text
HAND-Score-Hexagon/
├── README.md
├── app/
│   ├── build.gradle.kts
│   └── src/main/
│       ├── AndroidManifest.xml
│       ├── java/com/handscore/hexagon/
│       │   ├── MainActivity.java
│       │   ├── backend/          # InferenceBackend contract + reference backend
│       │   ├── data/             # ChatAlpaca dataset loader
│       │   ├── metrics/          # Android battery / memory / CPU / thermal sampling
│       │   ├── model/            # Benchmark result model pieces
│       │   ├── protocol/         # Exp A/C/E runner
│       │   └── results/          # JSON serialization and result storage
│       └── res/values/
├── build.gradle.kts
├── gradle/
├── gradle.properties
├── gradlew
├── gradlew.bat
└── settings.gradle.kts
```

The shared prompt file is copied into Android assets at build time from `../samples/chatalpaca_handscore.json`. This keeps the Android and iOS apps on the same deterministic prompt set.

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

The app writes results under the app-specific external files directory:

```text
/sdcard/Android/data/com.handscore.hexagon/files/HAND-Score/<model-name>/*.json
```

Retrieve them with:

```bash
adb pull /sdcard/Android/data/com.handscore.hexagon/files/HAND-Score samples/results/raw
```

Then regenerate host summaries:

```bash
cd samples/results/analysis
python3 build_summary.py
```

Artifact download and device-staging details are documented in [`ARTIFACTS.md`](ARTIFACTS.md). In short: build outputs are generated locally, Qualcomm SDK files are downloaded from Qualcomm Developer after license acceptance, and converted model artifacts are kept in ignored local folders or an external release/artifact store.

---

## Connecting the Hexagon backend

The committed `ReferenceBackend` is intentionally not a performance backend. It is only there to verify that the Android project opens, the prompt set loads, the protocol buttons run, JSON files are emitted, and the host pipeline accepts the schema.

For paper reproduction, implement a Qualcomm backend behind this interface:

```java
public interface InferenceBackend extends AutoCloseable {
    String name();
    ModelDescriptor loadModel(BenchmarkOptions options) throws Exception;
    GenerationResult generate(List<ChatMessage> history, int promptTokensHint, int maxTokens, float temperature) throws Exception;
    int countTokens(String text);
    NpuProfile profile() throws Exception;
    void close();
}
```

Then update `BackendFactory.create(...)` to return that backend instead of `ReferenceBackend`.

Backend responsibilities:

- Load local model / tokenizer / Hexagon runtime artifacts.
- Run generation for single-turn prompts and cumulative multi-turn histories.
- Return exact tokenizer prompt counts and measured TTFT / prefill / decode timings.
- Return `NpuProfile` with Hexagon NPU, GPU, and CPU op placement counts.
- Keep all proprietary or large files outside Git, for example under local `artifacts/` or device-local model directories.

---

## Local-only artifacts

The repository intentionally does not include:

- APKs (`*.apk`, `*.aab`)
- model weights or converted graphs
- Qualcomm QNN / Hexagon SDK binaries
- raw benchmark result dumps

If local binary artifacts are needed while developing, place them under `HAND-Score-Hexagon/artifacts/` or `HAND-Score-Hexagon/prebuilt/`. Those directories are ignored by Git.

---

## Expected result JSON schema

The Android app writes JSON aligned with the iOS benchmark pipeline:

- `config.mode`: `single_turn` or `multi_turn`
- `performance.modelLoadTimeMs`
- `performance.ttftMs`
- `performance.prefillTokens`
- `performance.prefillTokensPerSec`
- `performance.decodeTokens`
- `performance.decodeTokensPerSec`
- `system.before`
- `system.after`
- `system.timeline`
- `npuProfile`
- `turnResults`

The host analysis script accepts both iOS `aneProfile` and Android `npuProfile` fields.

---

## Notes

- The package namespace is de-identified as `com.handscore.hexagon`.
- The shared prompt set is committed at `../samples/chatalpaca_handscore.json` in the repository root.
- The app keeps the screen awake while a run is active so the manual phase-0 protocol remains comparable with the iOS run.
