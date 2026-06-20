#!/usr/bin/env python3
"""Add main-menu medication reminder l10n keys and regenerate Dart maps."""
from __future__ import annotations

import base64
import json
import importlib.util
import pathlib
import zlib

ROOT = pathlib.Path(__file__).resolve().parent.parent
GEN = ROOT / "tool" / "generate_l10n.py"

KEYS = {
    "en": {
        "medicationReminderNoneDue": "No medication reminder for today",
        "medicationDueAt": "{name} due at {time}",
        "medicationReminderA11yDue": "Medication reminder. {name} due at {time}.",
        "medicationReminderA11yAllTaken": "Medication reminder. All taken today.",
        "medicationReminderA11yNone": "Medication reminder. No medication reminder for today.",
    },
    "ms": {
        "medicationReminderNoneDue": "Tiada peringatan ubat untuk hari ini",
        "medicationDueAt": "{name} perlu diambil pada {time}",
        "medicationReminderA11yDue": "Peringatan ubat. {name} perlu diambil pada {time}.",
        "medicationReminderA11yAllTaken": "Peringatan ubat. Semua telah diambil hari ini.",
        "medicationReminderA11yNone": "Peringatan ubat. Tiada peringatan ubat untuk hari ini.",
    },
    "zh": {
        "medicationReminderNoneDue": "今日没有用药提醒",
        "medicationDueAt": "{name} 应于 {time} 服用",
        "medicationReminderA11yDue": "用药提醒。{name} 应于 {time} 服用。",
        "medicationReminderA11yAllTaken": "用药提醒。今日已全部服用。",
        "medicationReminderA11yNone": "用药提醒。今日没有用药提醒。",
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

    import subprocess
    import sys

    subprocess.run([sys.executable, str(GEN)], check=True)
    print("Added medication reminder keys and regenerated l10n maps.")


if __name__ == "__main__":
    main()
