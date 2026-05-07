#!/usr/bin/env python3
"""ChatAlpaca-20K 토큰 수 분포 분석 스크립트"""

from datasets import load_dataset
import tiktoken
from collections import Counter
import statistics

print("=== ChatAlpaca-20K 데이터셋 로딩 ===")
ds = load_dataset("robinsmits/ChatAlpaca-20K", split="train")
print(f"총 대화 수: {len(ds)}")

enc = tiktoken.get_encoding("cl100k_base")

turn_counts = []
first_user_tokens = []
all_user_tokens = []
all_assistant_tokens = []
conversation_total_tokens = []

for i, item in enumerate(ds):
    messages = item["messages"]
    user_msgs = [m for m in messages if m["role"] == "user"]
    asst_msgs = [m for m in messages if m["role"] == "assistant"]

    num_turns = len(user_msgs)
    turn_counts.append(num_turns)

    if user_msgs:
        first_user_tokens.append(len(enc.encode(user_msgs[0]["content"])))

    total_conv = 0
    for m in messages:
        tok = len(enc.encode(m["content"]))
        total_conv += tok
        if m["role"] == "user":
            all_user_tokens.append(tok)
        else:
            all_assistant_tokens.append(tok)

    conversation_total_tokens.append(total_conv)

    if i % 5000 == 0:
        print(f"  처리 중... {i}/{len(ds)}")

print(f"\n=== 분석 완료 ===\n")


def print_stats(name, data):
    if not data:
        return
    s = sorted(data)
    n = len(s)
    print(f"\n{'='*60}")
    print(f"  {name} (n={n})")
    print(f"{'='*60}")
    print(f"  Min:    {min(data)}")
    print(f"  P5:     {s[int(n*0.05)]}")
    print(f"  P10:    {s[int(n*0.10)]}")
    print(f"  P25:    {s[int(n*0.25)]}")
    print(f"  Median: {statistics.median(data)}")
    print(f"  Mean:   {statistics.mean(data):.1f}")
    print(f"  P75:    {s[int(n*0.75)]}")
    print(f"  P90:    {s[int(n*0.90)]}")
    print(f"  P95:    {s[int(n*0.95)]}")
    print(f"  P99:    {s[int(n*0.99)]}")
    print(f"  Max:    {max(data)}")
    print(f"  StdDev: {statistics.stdev(data):.1f}")


print_stats("대화당 턴 수 (user-assistant 쌍)", turn_counts)
print_stats("첫 번째 USER 메시지 토큰 수", first_user_tokens)
print_stats("모든 USER 메시지 토큰 수", all_user_tokens)
print_stats("모든 ASSISTANT 메시지 토큰 수", all_assistant_tokens)
print_stats("대화 전체 토큰 수", conversation_total_tokens)

# 턴 수 분포
turn_dist = Counter(turn_counts)
print(f"\n{'='*60}")
print(f"  턴 수 분포")
print(f"{'='*60}")
for k in sorted(turn_dist.keys()):
    pct = turn_dist[k] / len(turn_counts) * 100
    bar = "#" * int(pct)
    print(f"  {k}턴: {turn_dist[k]:>5} ({pct:>5.1f}%) {bar}")

# 첫 USER 메시지 토큰 수 구간별
bins = [(0, 30, "Short"), (31, 80, "Med-Short"), (81, 150, "Medium"),
        (151, 300, "Long"), (301, 500, "Very Long"), (501, 99999, "Extra Long")]

print(f"\n{'='*60}")
print(f"  첫 USER 메시지 토큰 수 구간별 분포")
print(f"{'='*60}")
for lo, hi, label in bins:
    count = sum(1 for t in first_user_tokens if lo <= t <= hi)
    pct = count / len(first_user_tokens) * 100
    bar = "#" * int(pct / 2)
    print(f"  {label:>12} ({lo:>3}-{hi:>5} tok): {count:>5} ({pct:>5.1f}%) {bar}")

# 대화 전체 토큰 수 구간별
mt_bins = [(0, 100, "~100"), (101, 300, "101-300"), (301, 500, "301-500"),
           (501, 1000, "501-1K"), (1001, 2000, "1K-2K"), (2001, 99999, "2K+")]

print(f"\n{'='*60}")
print(f"  대화 전체 토큰 수 구간별 분포")
print(f"{'='*60}")
for lo, hi, label in mt_bins:
    count = sum(1 for t in conversation_total_tokens if lo <= t <= hi)
    pct = count / len(conversation_total_tokens) * 100
    bar = "#" * int(pct / 2)
    print(f"  {label:>10} tok: {count:>5} ({pct:>5.1f}%) {bar}")

# ASSISTANT 메시지 토큰 수 분포
asst_bins = [(0, 30, "~30"), (31, 64, "31-64"), (65, 128, "65-128"),
             (129, 256, "129-256"), (257, 512, "257-512"), (513, 99999, "512+")]

print(f"\n{'='*60}")
print(f"  ASSISTANT 메시지 토큰 수 분포 (출력 길이 참고)")
print(f"{'='*60}")
for lo, hi, label in asst_bins:
    count = sum(1 for t in all_assistant_tokens if lo <= t <= hi)
    pct = count / len(all_assistant_tokens) * 100
    bar = "#" * int(pct / 2)
    print(f"  {label:>10} tok: {count:>5} ({pct:>5.1f}%) {bar}")

# Bin별 샘플 예시
print(f"\n{'='*60}")
print(f"  Bin별 샘플 예시 (첫 user 메시지)")
print(f"{'='*60}")

for lo, hi, label in bins[:5]:
    print(f"\n--- {label} ({lo}-{hi} tok) ---")
    count = 0
    for item in ds:
        msgs = item["messages"]
        user_msgs = [m for m in msgs if m["role"] == "user"]
        if user_msgs:
            tok = len(enc.encode(user_msgs[0]["content"]))
            if lo <= tok <= hi and count < 2:
                text = user_msgs[0]["content"][:120]
                print(f"  [{tok} tok] {text}")
                count += 1
        if count >= 2:
            break
