#!/usr/bin/env python3
"""Add fall detection and voice assistant settings l10n keys."""
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

KEYS = {
    "en": {
        "fallDetectionSettingTitle": "FALL DETECTION",
        "fallDetectionSettingSubtitle": "Detect sudden falls and offer help",
        "fallDetectionTestTitle": "TEST FALL DETECTION",
        "fallDetectionTestSubtitle": "Run a practice check-in without sending an alert",
        "voiceAssistantSettingTitle": "VOICE ASSISTANT",
        "voiceAssistantSettingSubtitle": "Say \"Hey Aura\" to open pages hands-free",
    },
    "ms": {
        "fallDetectionSettingTitle": "PENGESANAN JATUH",
        "fallDetectionSettingSubtitle": "Kesan jatuh mendadak dan tawarkan bantuan",
        "fallDetectionTestTitle": "UJI PENGESANAN JATUH",
        "fallDetectionTestSubtitle": "Jalankan latihan daftar masuk tanpa menghantar amaran",
        "voiceAssistantSettingTitle": "PEMBANTU SUARA",
        "voiceAssistantSettingSubtitle": "Sebut \"Hey Aura\" untuk membuka halaman tanpa sentuh",
    },
    "zh": {
        "fallDetectionSettingTitle": "跌倒检测",
        "fallDetectionSettingSubtitle": "检测突发跌倒并提供帮助",
        "fallDetectionTestTitle": "测试跌倒检测",
        "fallDetectionTestSubtitle": "运行练习签到，不会发送警报",
        "voiceAssistantSettingTitle": "语音助手",
        "voiceAssistantSettingSubtitle": "说“Hey Aura”即可免提打开页面",
    },
}


def main() -> None:
    spec = importlib.util.spec_from_file_location("gen", GEN)
    gen = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(gen)

    catalog = gen._catalog()
    for lang, entries in KEYS.items():
        catalog[lang].update(entries)

    payload = base64.b64encode(
        zlib.compress(json.dumps(catalog, ensure_ascii=False).encode("utf-8"))
    ).decode("ascii")

    text = GEN.read_text(encoding="utf-8")
    start = text.index("_PAYLOAD = '") + len("_PAYLOAD = '")
    end = text.index("'", start)
    GEN.write_text(text[:start] + payload + text[end:], encoding="utf-8")

    subprocess.run([sys.executable, str(GEN)], check=True)
    print("Added fall detection and voice assistant settings l10n keys.")


if __name__ == "__main__":
    main()
