#!/usr/bin/env python3
"""HAND-Score 결과 종합 분석.

raw/Gemma3-270m, raw/Llama-3.2-1B 의 JSON을 모두 읽어
- Exp A (single, dedup), Exp C (thermal stress 동일 prompt 반복), Exp E (multi-turn)
- NPU Profile (Exp D)
- deploy_score 산출
을 모두 포함한 summary JSON을 생성한다.
"""
from __future__ import annotations

import datetime as dt
import glob
import json
import os
from collections import Counter, defaultdict
from statistics import mean, median, stdev
from typing import Any

ROOT = os.path.dirname(os.path.abspath(__file__))
RAW_BASE = os.path.normpath(os.path.join(ROOT, "..", "raw"))

# iPhone 17 Pro RAM (GB)
RAM_GB = 12

MODELS = {
    "Gemma3-270m": "Gemma3-270m-4096-ANE",
    "Llama-3.2-1B": "Llama-3.2-1B-4096-ANE",
    "Llama-3.2-3B": "Llama-3.2-3B-4096-ANE",
    "Qwen3-4B": "Qwen3-4B-4096-ANE",
}


def stat(values: list[float]) -> dict[str, float] | None:
    if not values:
        return None
    return {
        "n": len(values),
        "mean": mean(values),
        "median": median(values),
        "std": stdev(values) if len(values) > 1 else 0.0,
        "min": min(values),
        "max": max(values),
    }


def parse_ts(s: str) -> dt.datetime:
    return dt.datetime.fromisoformat(s.replace("Z", "+00:00"))


def analyze_model(model_dir: str) -> dict[str, Any]:
    files = sorted(glob.glob(os.path.join(model_dir, "*.json")))
    by_mode: dict[str, list[Any]] = defaultdict(list)
    for f in files:
        with open(f) as fp:
            d = json.load(fp)
        by_mode[d["config"]["mode"]].append((f, d))

    sing = by_mode.get("single_turn", [])
    mt = by_mode.get("multi_turn", [])

    # thermal stress: 동일 prompt 20회 이상 반복
    pcount = Counter(d["config"]["prompt"] for _, d in sing)
    ts_prompts = {p for p, c in pcount.items() if c >= 20}
    ts = [(f, d) for f, d in sing if d["config"]["prompt"] in ts_prompts]
    exp_a = [(f, d) for f, d in sing if d["config"]["prompt"] not in ts_prompts]

    # =========== Exp A ===========
    exp_a_pf = [d["performance"]["prefillTokensPerSec"] for _, d in exp_a]
    exp_a_dec = [d["performance"]["decodeTokensPerSec"] for _, d in exp_a]
    exp_a_ttft = [d["performance"]["ttftMs"] / 1000 for _, d in exp_a]
    exp_a_load = [d["performance"]["modelLoadTimeMs"] / 1000 for _, d in exp_a]
    exp_a_mem_after = [d["system"]["after"]["memoryUsageMB"] for _, d in exp_a]
    exp_a_mem_peak = []
    exp_a_cpu = []
    for _, d in exp_a:
        tl = d["system"].get("timeline", [])
        if tl:
            exp_a_mem_peak.append(max(t["memoryUsageMB"] for t in tl))
            cpu = [t["cpuUsagePercent"] for t in tl if t["cpuUsagePercent"] is not None]
            if cpu:
                exp_a_cpu.append(mean(cpu))

    # bin별 분리
    bins: dict[str, list[Any]] = defaultdict(list)
    for f, d in exp_a:
        n = d["performance"]["prefillTokens"]
        if n <= 30:
            bins["Short"].append(d)
        elif n <= 80:
            bins["Med-Short"].append(d)
        else:
            bins["Medium"].append(d)
    bin_stats = {}
    for k, lst in bins.items():
        if not lst:
            continue
        bin_stats[k] = {
            "n": len(lst),
            "prefill_tps": mean(x["performance"]["prefillTokensPerSec"] for x in lst),
            "decode_tps": mean(x["performance"]["decodeTokensPerSec"] for x in lst),
            "ttft_s": mean(x["performance"]["ttftMs"] / 1000 for x in lst),
        }

    # =========== Exp C ===========
    exp_c_summary: dict[str, Any] | None = None
    if ts:
        ts_sorted = sorted(ts, key=lambda x: x[1]["timestamp"])
        t0 = parse_ts(ts_sorted[0][1]["timestamp"])
        t1 = parse_ts(ts_sorted[-1][1]["timestamp"])
        elapsed_h = (t1 - t0).total_seconds() / 3600
        bat0 = ts_sorted[0][1]["system"]["before"]["batteryLevel"]
        bat1 = ts_sorted[-1][1]["system"]["after"]["batteryLevel"]
        bdr = (bat0 - bat1) / elapsed_h * 100 if elapsed_h > 0 else 0.0
        dec_first = ts_sorted[0][1]["performance"]["decodeTokensPerSec"]
        dec_last = ts_sorted[-1][1]["performance"]["decodeTokensPerSec"]
        sus_degr = 1 - dec_last / dec_first if dec_first > 0 else 0.0
        max_thermal = max(d["system"]["after"]["thermalState"] for _, d in ts)
        rounds = []
        for f, d in ts_sorted:
            rounds.append({
                "ts": d["timestamp"],
                "decode_tps": d["performance"]["decodeTokensPerSec"],
                "prefill_tps": d["performance"]["prefillTokensPerSec"],
                "ttft_ms": d["performance"]["ttftMs"],
                "mem_mb": d["system"]["after"]["memoryUsageMB"],
                "thermal": d["system"]["after"]["thermalState"],
                "battery": d["system"]["after"]["batteryLevel"],
            })
        exp_c_summary = {
            "n_rounds": len(ts),
            "duration_min": elapsed_h * 60,
            "battery_start": bat0,
            "battery_end": bat1,
            "bdr_pct_per_h": bdr,
            "decode_first": dec_first,
            "decode_last": dec_last,
            "sustained_degradation": sus_degr,
            "thermal_max_state": max_thermal,
            "decode_stat": stat([r["decode_tps"] for r in rounds]),
            "rounds": rounds,
        }

    # =========== Exp E ===========
    exp_e_records = []
    t1_ttft, tK_ttft, t1_dec, tK_dec, t1_pf, tK_pf, mem_peak_mt = [], [], [], [], [], [], []
    by_K: dict[int, list[Any]] = defaultdict(list)
    for f, d in mt:
        tr = d.get("turnResults", [])
        asst = [t for t in tr if t.get("role") == "assistant" and t.get("outputTokens", 0) > 0]
        if not asst:
            continue
        K = len(asst)
        by_K[K].append((f, d, asst))
        t1_ttft.append(asst[0]["ttftMs"] / 1000)
        tK_ttft.append(asst[-1]["ttftMs"] / 1000)
        t1_dec.append(asst[0]["decodeTokensPerSec"])
        tK_dec.append(asst[-1]["decodeTokensPerSec"])
        t1_pf.append(asst[0]["prefillTokensPerSec"])
        tK_pf.append(asst[-1]["prefillTokensPerSec"])
        tl = d["system"].get("timeline", [])
        if tl:
            mem_peak_mt.append(max(t["memoryUsageMB"] for t in tl))
        exp_e_records.append({
            "ts": d["timestamp"],
            "K": K,
            "cumulative_prompt_tokens": d["performance"]["prefillTokens"],
            "decode_tps": d["performance"]["decodeTokensPerSec"],
            "ttft_ms": d["performance"]["ttftMs"],
            "t1_decode_tps": asst[0]["decodeTokensPerSec"],
            "tK_decode_tps": asst[-1]["decodeTokensPerSec"],
            "t1_ttft_ms": asst[0]["ttftMs"],
            "tK_ttft_ms": asst[-1]["ttftMs"],
        })

    # =========== NPU Profile (Exp D) ===========
    npu_profile = None
    if exp_a:
        ap = exp_a[0][1]["aneProfile"]
        ane_total = ap["aneOps"]
        cpu_total = sum(c["cpuOps"] for c in ap["components"])
        gpu_total = sum(c["gpuOps"] for c in ap["components"])
        total = ane_total + cpu_total + gpu_total
        comps = []
        for c in ap["components"]:
            comps.append({
                "name": c["name"],
                "ane_pct": c["anePercentage"],
                "ane_ops": c["aneOps"],
                "cpu_ops": c["cpuOps"],
                "gpu_ops": c["gpuOps"],
            })
        npu_profile = {
            "ane_pct": ane_total / total * 100 if total else 0,
            "gpu_pct": gpu_total / total * 100 if total else 0,
            "cpu_pct": cpu_total / total * 100 if total else 0,
            "total_ops": total,
            "ane_ops": ane_total,
            "cpu_ops": cpu_total,
            "gpu_ops": gpu_total,
            "components": comps,
            "blockers": ap.get("aneBlockers", []),
        }

    # =========== deploy_score ===========
    deploy = None
    if exp_a and exp_c_summary and npu_profile:
        S_NPU = npu_profile["ane_pct"] / 100
        dec_mean = mean(exp_a_dec)
        S_perf = min(1.0, dec_mean / 30.0) * (1 - exp_c_summary["sustained_degradation"])
        peak_mem_GB = max(max(exp_a_mem_peak or [0]), max(mem_peak_mt or [0])) / 1024
        S_sys_mem = 1 - min(1.0, peak_mem_GB / (0.6 * RAM_GB))
        S_sys_bdr = 1 - min(1.0, exp_c_summary["bdr_pct_per_h"] / 50.0)
        S_sys_thermal = (3 - exp_c_summary["thermal_max_state"]) / 3
        S_sys = (S_sys_mem + S_sys_bdr + S_sys_thermal) / 3
        score = 0.30 * S_NPU + 0.40 * S_perf + 0.30 * S_sys
        viol = []
        if S_NPU < 0.5:
            viol.append(f"npu_op_ratio < 0.5 ({S_NPU:.3f})")
        if peak_mem_GB / RAM_GB >= 0.6:
            viol.append(f"peak_memory >= 0.6×RAM ({peak_mem_GB:.3f} GB)")
        if exp_c_summary["sustained_degradation"] > 0.4:
            viol.append(f"sustained_degradation > 0.4 ({exp_c_summary['sustained_degradation']:.3f})")
        deploy = {
            "S_NPU": S_NPU,
            "S_perf": S_perf,
            "S_sys": S_sys,
            "S_sys_mem": S_sys_mem,
            "S_sys_bdr": S_sys_bdr,
            "S_sys_thermal": S_sys_thermal,
            "peak_memory_GB": peak_mem_GB,
            "deploy_score": score,
            "deployable": len(viol) == 0,
            "violations": viol,
            "RAM_GB_assumed": RAM_GB,
        }

    return {
        "device": exp_a[0][1].get("device") if exp_a else None,
        "raw_files_total": len(files),
        "exp_a": {
            "n": len(exp_a),
            "unique_prompts": len(set(d["config"]["prompt"] for _, d in exp_a)),
            "load_s": stat(exp_a_load),
            "ttft_s": stat(exp_a_ttft),
            "prefill_tps": stat(exp_a_pf),
            "decode_tps": stat(exp_a_dec),
            "mem_after_mb": stat(exp_a_mem_after),
            "mem_peak_mb": stat(exp_a_mem_peak),
            "cpu_pct": stat(exp_a_cpu),
            "by_bin": bin_stats,
        },
        "exp_c": exp_c_summary,
        "exp_e": {
            "n": len(mt),
            "by_K": {k: len(v) for k, v in by_K.items()},
            "t1_ttft_s": stat(t1_ttft),
            "tK_ttft_s": stat(tK_ttft),
            "t1_decode_tps": stat(t1_dec),
            "tK_decode_tps": stat(tK_dec),
            "t1_prefill_tps": stat(t1_pf),
            "tK_prefill_tps": stat(tK_pf),
            "mem_peak_mb": stat(mem_peak_mt),
            "records": exp_e_records,
        },
        "npu_profile": npu_profile,
        "deploy": deploy,
    }


def main() -> None:
    out: dict[str, Any] = {
        "version": "1.0",
        "generated_at": dt.datetime.now().isoformat(),
        "ram_gb_assumed": RAM_GB,
        "models": {},
    }
    for name, _model_id in MODELS.items():
        d = analyze_model(os.path.join(RAW_BASE, name))
        out["models"][name] = d
        # 모델별 개별 파일도 저장
        with open(os.path.join(ROOT, f"{name}_summary.json"), "w") as fp:
            json.dump(d, fp, indent=2, ensure_ascii=False)
        print(f"  → {name}_summary.json (raw {d['raw_files_total']}개)")
    with open(os.path.join(ROOT, "all_summary.json"), "w") as fp:
        json.dump(out, fp, indent=2, ensure_ascii=False)
    print(f"  → all_summary.json")


if __name__ == "__main__":
    main()
