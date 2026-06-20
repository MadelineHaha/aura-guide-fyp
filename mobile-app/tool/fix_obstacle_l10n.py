#!/usr/bin/env python3
"""Add navigation obstacle l10n keys and regenerate Dart maps."""
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
        "obstacleDetected": "{label} detected",
        "obstacleLocated": "{label} on the {direction} at {distance} meter",
        "obstacleDirectionLeft": "left",
        "obstacleDirectionSlightlyLeft": "slightly left",
        "obstacleDirectionFront": "front",
        "obstacleDirectionSlightlyRight": "slightly right",
        "obstacleDirectionRight": "right",
    },
    "ms": {
        "obstacleDetected": "{label} dikesan",
        "obstacleLocated": "{label} di sebelah {direction}, {distance} meter",
        "obstacleDirectionLeft": "kiri",
        "obstacleDirectionSlightlyLeft": "sedikit ke kiri",
        "obstacleDirectionFront": "hadapan",
        "obstacleDirectionSlightlyRight": "sedikit ke kanan",
        "obstacleDirectionRight": "kanan",
    },
    "zh": {
        "obstacleDetected": "检测到{label}",
        "obstacleLocated": "{label}在{direction}{distance}米处",
        "obstacleDirectionLeft": "左侧",
        "obstacleDirectionSlightlyLeft": "左前方",
        "obstacleDirectionFront": "正前方",
        "obstacleDirectionSlightlyRight": "右前方",
        "obstacleDirectionRight": "右侧",
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
    print("Added obstacle navigation l10n keys.")


if __name__ == "__main__":
    main()
