#!/usr/bin/env python3
"""ChatAlpaca-20K에서 HAND-Score 실험용 샘플을 추출하여 JSON으로 export.

추출 정책:
  - 단발성 세트 (실험 A): 30개
      Short    (0-30 tok)   : 15개
      Med-Short(31-80 tok)  : 10개
      Medium   (81-150 tok) : 5개
  - 멀티턴 세트 (실험 E): 15개 대화
      4턴 5개 / 5턴 5개 / 6턴 5개

사용법:
  python3 scripts/extract_samples.py --output samples/chatalpaca_handscore.json
"""

from __future__ import annotations

import argparse
import json
import random
from collections import defaultdict
from datetime import datetime
from pathlib import Path
from typing import Any

import tiktoken
from datasets import load_dataset


SEED = 42  # 재현성
DATASET_NAME = "robinsmits/ChatAlpaca-20K"
ENCODING_NAME = "cl100k_base"


def build_arg_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument(
        "--output",
        type=Path,
        default=Path("samples/chatalpaca_handscore.json"),
        help="출력 JSON 경로 (기본: samples/chatalpaca_handscore.json)",
    )
    parser.add_argument("--seed", type=int, default=SEED, help="랜덤 시드 (기본: 42)")
    return parser


def token_count(enc: tiktoken.Encoding, text: str) -> int:
    return len(enc.encode(text))


def extract_single_turn(ds, enc: tiktoken.Encoding, rng: random.Random) -> list[dict[str, Any]]:
    """첫 user 메시지 token bin별로 sample 추출."""
    bins: dict[str, list[dict[str, Any]]] = defaultdict(list)

    for idx, item in enumerate(ds):
        msgs = item["messages"]
        user_msgs = [m for m in msgs if m["role"] == "user"]
        asst_msgs = [m for m in msgs if m["role"] == "assistant"]
        if not user_msgs:
            continue

        first_user = user_msgs[0]["content"]
        first_user_tok = token_count(enc, first_user)

        first_asst_ref = asst_msgs[0]["content"] if asst_msgs else None

        if 0 <= first_user_tok <= 30:
            label = "short"
        elif 31 <= first_user_tok <= 80:
            label = "med_short"
        elif 81 <= first_user_tok <= 150:
            label = "medium"
        else:
            continue

        bins[label].append(
            {
                "source_idx": idx,
                "bin": label,
                "input_tokens": first_user_tok,
                "prompt": first_user,
                "reference": first_asst_ref,
            }
        )

    quotas = {"short": 15, "med_short": 10, "medium": 5}
    selected: list[dict[str, Any]] = []
    for label, n in quotas.items():
        pool = bins[label]
        rng.shuffle(pool)
        chosen = pool[:n]
        selected.extend(chosen)

    # ID 부여
    for i, sample in enumerate(selected, start=1):
        sample["id"] = f"st-{i:03d}"

    return selected


def extract_multi_turn(ds, enc: tiktoken.Encoding, rng: random.Random) -> list[dict[str, Any]]:
    """턴 수별 멀티턴 대화 샘플 추출."""
    bins: dict[int, list[dict[str, Any]]] = defaultdict(list)

    for idx, item in enumerate(ds):
        msgs = item["messages"]
        user_msgs = [m for m in msgs if m["role"] == "user"]
        turn_count = len(user_msgs)

        if turn_count not in {4, 5, 6}:
            continue

        # HAND-Score BenchmarkRunner 형식: assistant content는 빈 문자열로 (모델이 생성)
        # reference는 별도 필드로 보존
        rendered_messages: list[dict[str, str]] = []
        references: list[str] = []
        for m in msgs:
            if m["role"] == "user":
                rendered_messages.append({"role": "user", "content": m["content"]})
            elif m["role"] == "assistant":
                rendered_messages.append({"role": "assistant", "content": ""})
                references.append(m["content"])

        total_tokens = sum(token_count(enc, m["content"]) for m in msgs)

        bins[turn_count].append(
            {
                "source_idx": idx,
                "turn_count": turn_count,
                "total_tokens": total_tokens,
                "messages": rendered_messages,
                "references": references,
            }
        )

    quotas = {4: 5, 5: 5, 6: 5}
    selected: list[dict[str, Any]] = []
    for turn_count, n in quotas.items():
        pool = bins[turn_count]
        rng.shuffle(pool)
        chosen = pool[:n]
        selected.extend(chosen)

    for i, sample in enumerate(selected, start=1):
        sample["id"] = f"mt-{i:03d}"

    return selected


def main() -> None:
    args = build_arg_parser().parse_args()
    rng = random.Random(args.seed)

    print(f"[extract] 데이터셋 로드: {DATASET_NAME}")
    ds = load_dataset(DATASET_NAME, split="train")
    print(f"[extract] 총 대화 수: {len(ds)}")

    enc = tiktoken.get_encoding(ENCODING_NAME)

    print("[extract] 단발성 세트 추출 중...")
    single_turn = extract_single_turn(ds, enc, rng)
    print(f"[extract]   추출 완료: {len(single_turn)}개")
    for label in ("short", "med_short", "medium"):
        n = sum(1 for s in single_turn if s["bin"] == label)
        print(f"[extract]   {label}: {n}개")

    print("[extract] 멀티턴 세트 추출 중...")
    multi_turn = extract_multi_turn(ds, enc, rng)
    print(f"[extract]   추출 완료: {len(multi_turn)}개")
    for tc in (4, 5, 6):
        n = sum(1 for s in multi_turn if s["turn_count"] == tc)
        print(f"[extract]   {tc}턴: {n}개")

    payload: dict[str, Any] = {
        "version": "1.0",
        "dataset": DATASET_NAME,
        "encoding": ENCODING_NAME,
        "extracted_at": datetime.now().strftime("%Y-%m-%d"),
        "seed": args.seed,
        "policies": {
            "single_turn": {
                "bins": [
                    {"label": "short", "min_tok": 0, "max_tok": 30, "quota": 15},
                    {"label": "med_short", "min_tok": 31, "max_tok": 80, "quota": 10},
                    {"label": "medium", "min_tok": 81, "max_tok": 150, "quota": 5},
                ],
                "max_tokens_default": 256,
                "temperature_default": 0.0,
            },
            "multi_turn": {
                "turn_counts": [4, 5, 6],
                "quota_per_turn": 5,
                "max_tokens_per_assist_turn_default": 256,
                "temperature_default": 0.0,
            },
        },
        "single_turn": single_turn,
        "multi_turn": multi_turn,
    }

    args.output.parent.mkdir(parents=True, exist_ok=True)
    with args.output.open("w", encoding="utf-8") as f:
        json.dump(payload, f, ensure_ascii=False, indent=2)

    print(f"[extract] 저장 완료: {args.output} ({args.output.stat().st_size / 1024:.1f} KB)")


if __name__ == "__main__":
    main()
