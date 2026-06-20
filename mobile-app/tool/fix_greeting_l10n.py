#!/usr/bin/env python3
"""Fix hardcoded demo names in l10n catalog and regenerate Dart maps."""
from __future__ import annotations

import base64
import importlib.util
import json
import pathlib
import subprocess
import sys
import zlib

ROOT = pathlib.Path(__file__).resolve().parent.parent
GEN = ROOT / "tool" / "generate_l10n.py"

FIXES = {
    "en": {
        "goodMorningA11yLabel": "Good morning, {name}. {date}.",
        "goodMorningA11yLabelNoName": "Good morning. {date}.",
        "helloUser": "Hello, {name}!",
        "helloUserNoName": "Hello!",
        "helloUserPatientIdA11y": "Hello, {name}. Patient ID {userId}.",
        "helloUserPatientIdA11yNoName": "Hello. Patient ID {userId}.",
        "patientIdLabel": "Patient ID: {userId}",
        "patientIdUnavailable": "Patient ID unavailable",
    },
    "ms": {
        "goodMorningA11yLabel": "Selamat pagi, {name}. {date}.",
        "goodMorningA11yLabelNoName": "Selamat pagi. {date}.",
        "helloUser": "Hello, {name}!",
        "helloUserNoName": "Hello!",
        "helloUserPatientIdA11y": "Hello, {name}. ID Pesakit {userId}.",
        "helloUserPatientIdA11yNoName": "Hello. ID Pesakit {userId}.",
        "patientIdLabel": "ID Pesakit: {userId}",
        "patientIdUnavailable": "ID Pesakit tidak tersedia",
    },
    "zh": {
        "goodMorningA11yLabel": "早上好，{name}。{date}。",
        "goodMorningA11yLabelNoName": "早上好。{date}。",
        "helloUser": "你好，{name}！",
        "helloUserNoName": "你好！",
        "helloUserPatientIdA11y": "你好，{name}。患者编号 {userId}。",
        "helloUserPatientIdA11yNoName": "你好。患者编号 {userId}。",
        "patientIdLabel": "患者编号：{userId}",
        "patientIdUnavailable": "患者编号不可用",
    },
}


def main() -> None:
    spec = importlib.util.spec_from_file_location("gen", GEN)
    gen = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(gen)

    catalog = gen._catalog()
    for lang, entries in FIXES.items():
        catalog[lang].update(entries)

    payload = base64.b64encode(
        zlib.compress(json.dumps(catalog, ensure_ascii=False).encode("utf-8"))
    ).decode("ascii")

    text = GEN.read_text(encoding="utf-8")
    start = text.index("_PAYLOAD = '") + len("_PAYLOAD = '")
    end = text.index("'", start)
    GEN.write_text(text[:start] + payload + text[end:], encoding="utf-8")

    subprocess.run([sys.executable, str(GEN)], check=True)
    print("Fixed greeting/patient ID l10n placeholders.")


if __name__ == "__main__":
    main()
