#!/usr/bin/env python3
"""Translate booking/Firestore l10n keys and regenerate Dart maps."""
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
        "noTimesForDateDetail": "No times available for this date. Booked slots are hidden.",
        "firestorePermissionAppointments": "Could not load available times. Please try again later.",
        "firestoreIndexAppointments": "Appointment times are still setting up. Please try again later.",
        "couldNotLoadAvailableTimes": "Could not load available times: {error}",
    },
    "ms": {
        "noTimesForDateDetail": "Tiada masa tersedia untuk tarikh ini. Slot yang telah diambil tidak dipaparkan.",
        "firestorePermissionAppointments": "Tidak dapat memuatkan masa tersedia. Sila cuba lagi kemudian.",
        "firestoreIndexAppointments": "Masa temujanji masih disediakan. Sila cuba lagi kemudian.",
        "couldNotLoadAvailableTimes": "Tidak dapat memuatkan masa tersedia: {error}",
    },
    "zh": {
        "noTimesForDateDetail": "此日期暂无可用时段。已预约时段不会显示。",
        "firestorePermissionAppointments": "无法加载可用时段，请稍后重试。",
        "firestoreIndexAppointments": "预约时段正在配置中，请稍后重试。",
        "couldNotLoadAvailableTimes": "无法加载可用时段：{error}",
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
    print("Updated booking slot l10n strings.")


if __name__ == "__main__":
    main()
