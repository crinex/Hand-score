#!/usr/bin/env python3
"""Prepare local Android / Hexagon artifacts without committing binaries."""
from __future__ import annotations

import argparse
import json
import os
import shutil
import subprocess
import sys
from pathlib import Path

PROJECT_ROOT = Path(__file__).resolve().parents[1]
ARTIFACTS = PROJECT_ROOT / "artifacts"
MODELS = ARTIFACTS / "models"
QNN = ARTIFACTS / "qnn"
RESULTS = ARTIFACTS / "results"
MANIFEST = ARTIFACTS / "manifest.local.json"
LOCAL_PROPERTIES = PROJECT_ROOT / "local.properties"
DEVICE_MODEL_ROOT = "/sdcard/Android/data/com.handscore.hexagon/files/models"


def load_manifest() -> dict:
    if MANIFEST.exists():
        return json.loads(MANIFEST.read_text())
    return {}


def save_manifest(data: dict) -> None:
    ARTIFACTS.mkdir(parents=True, exist_ok=True)
    MANIFEST.write_text(json.dumps(data, indent=2) + "\n")


def ensure_dirs() -> None:
    for path in (ARTIFACTS, MODELS, QNN, RESULTS):
        path.mkdir(parents=True, exist_ok=True)


def init(args: argparse.Namespace) -> None:
    ensure_dirs()
    manifest = load_manifest()

    if args.android_sdk:
        sdk = Path(args.android_sdk).expanduser().resolve()
        LOCAL_PROPERTIES.write_text(f"sdk.dir={sdk}\n")
        manifest["android_sdk"] = str(sdk)

    if args.qnn_sdk:
        qnn = Path(args.qnn_sdk).expanduser().resolve()
        manifest["qnn_sdk"] = str(qnn)

    save_manifest(manifest)
    print(f"Created local artifact folders under {ARTIFACTS}")
    print(f"Wrote local manifest: {MANIFEST}")
    if args.android_sdk:
        print(f"Wrote Android SDK path: {LOCAL_PROPERTIES}")


def check(_args: argparse.Namespace) -> None:
    manifest = load_manifest()
    android_sdk = manifest.get("android_sdk") or os.environ.get("ANDROID_HOME") or os.environ.get("ANDROID_SDK_ROOT")
    qnn_sdk = manifest.get("qnn_sdk")

    rows = [
        ("project", PROJECT_ROOT, PROJECT_ROOT.exists()),
        ("local.properties", LOCAL_PROPERTIES, LOCAL_PROPERTIES.exists()),
        ("android_sdk", android_sdk or "(unset)", bool(android_sdk and Path(android_sdk).exists())),
        ("qnn_sdk", qnn_sdk or "(unset)", bool(qnn_sdk and Path(qnn_sdk).exists())),
        ("models_dir", MODELS, MODELS.exists()),
        ("adb", shutil.which("adb") or "(not on PATH)", shutil.which("adb") is not None),
    ]

    for name, value, ok in rows:
        print(f"{'OK' if ok else '!!'} {name}: {value}")

    if MODELS.exists():
        models = sorted(path.name for path in MODELS.iterdir() if path.is_dir())
        print("models:", ", ".join(models) if models else "(none)")


def adb_path() -> str:
    adb = shutil.which("adb")
    if adb:
        return adb

    manifest = load_manifest()
    sdk = manifest.get("android_sdk") or os.environ.get("ANDROID_HOME") or os.environ.get("ANDROID_SDK_ROOT")
    if sdk:
        candidate = Path(sdk) / "platform-tools" / "adb"
        if candidate.exists():
            return str(candidate)

    raise SystemExit("adb not found. Install Android SDK platform-tools or add adb to PATH.")


def push_model(args: argparse.Namespace) -> None:
    model_dir = MODELS / args.name
    if not model_dir.is_dir():
        raise SystemExit(f"Model directory not found: {model_dir}")

    adb = adb_path()
    device_path = f"{args.device_root.rstrip('/')}/{args.name}"
    subprocess.run([adb, "shell", "mkdir", "-p", args.device_root], check=True)
    subprocess.run([adb, "push", str(model_dir), device_path], check=True)
    print(f"Pushed {model_dir} -> {device_path}")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest="cmd", required=True)

    init_parser = sub.add_parser("init", help="Create ignored local artifact folders and optional SDK config.")
    init_parser.add_argument("--android-sdk", help="Absolute Android SDK path to write into local.properties.")
    init_parser.add_argument("--qnn-sdk", help="Local Qualcomm AI Engine Direct / QNN SDK path.")
    init_parser.set_defaults(func=init)

    check_parser = sub.add_parser("check", help="Print local artifact readiness.")
    check_parser.set_defaults(func=check)

    push_parser = sub.add_parser("push-model", help="Push one local model artifact directory to the Android device.")
    push_parser.add_argument("--name", required=True, help="Model folder name under artifacts/models.")
    push_parser.add_argument("--device-root", default=DEVICE_MODEL_ROOT, help="Device model root.")
    push_parser.set_defaults(func=push_model)

    args = parser.parse_args()
    args.func(args)


if __name__ == "__main__":
    try:
        main()
    except subprocess.CalledProcessError as exc:
        sys.exit(exc.returncode)
