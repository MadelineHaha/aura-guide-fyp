#!/usr/bin/env python3
"""Add TalkBack / voice passphrase l10n keys and regenerate Dart maps."""
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
        "voicePassphraseCaptureSuccess": "Voice captured successfully.",
        "voicePassphraseRetake": "That was not correct. Please tap to record again and say, Sign me in.",
        "voicePassphraseCaptureFailed": "Voice profile could not be captured. Please tap to record again and say Sign me in.",
        "voiceRecordRecording": "Recording...",
        "voiceRecordCaptured": "Voice captured",
        "voiceRecordTapToRecord": "Tap to record",
        "voiceRecordCapturedA11y": "Voice captured. Use the Continue button below.",
        "voiceRecordTapA11y": "Tap to record. Please say Sign me in.",
        "voiceRecordPrompt": "Please say \"Sign me in\"",
        "voiceRecordHeard": "Heard: \"{text}\"",
        "voiceRecordAgain": "Record again",
    },
    "ms": {
        "voicePassphraseCaptureSuccess": "Suara berjaya dirakam.",
        "voicePassphraseRetake": "Itu tidak betul. Sila ketik untuk merakam semula dan sebut, Sign me in.",
        "voicePassphraseCaptureFailed": "Profil suara tidak dapat dirakam. Sila ketik untuk merakam semula dan sebut Sign me in.",
        "voiceRecordRecording": "Merakam...",
        "voiceRecordCaptured": "Suara dirakam",
        "voiceRecordTapToRecord": "Ketik untuk merakam",
        "voiceRecordCapturedA11y": "Suara dirakam. Gunakan butang Teruskan di bawah.",
        "voiceRecordTapA11y": "Ketik untuk merakam. Sila sebut Sign me in.",
        "voiceRecordPrompt": "Sila sebut \"Sign me in\"",
        "voiceRecordHeard": "Didengar: \"{text}\"",
        "voiceRecordAgain": "Rakam semula",
    },
    "zh": {
        "voicePassphraseCaptureSuccess": "语音已成功录制。",
        "voicePassphraseRetake": "不正确。请再次点击录制并说 Sign me in。",
        "voicePassphraseCaptureFailed": "无法录制语音档案。请再次点击录制并说 Sign me in。",
        "voiceRecordRecording": "正在录制...",
        "voiceRecordCaptured": "语音已录制",
        "voiceRecordTapToRecord": "点击录制",
        "voiceRecordCapturedA11y": "语音已录制。请使用下方的继续按钮。",
        "voiceRecordTapA11y": "点击录制。请说 Sign me in。",
        "voiceRecordPrompt": "请说“Sign me in”",
        "voiceRecordHeard": "听到：“{text}”",
        "voiceRecordAgain": "重新录制",
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
    print("Added TalkBack voice l10n keys.")


if __name__ == "__main__":
    main()
