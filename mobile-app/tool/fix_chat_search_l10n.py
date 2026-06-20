#!/usr/bin/env python3
"""Add chat search l10n keys and regenerate Dart maps."""
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
        "searchMessagesHint": "Search with keywords",
        "closeSearchA11y": "Close search",
        "noSearchResults": "No messages match your search.",
        "searchConversationA11y": "Search conversation",
    },
    "ms": {
        "searchMessagesHint": "Cari dengan kata kunci",
        "closeSearchA11y": "Tutup carian",
        "noSearchResults": "Tiada mesej sepadan dengan carian anda.",
        "searchConversationA11y": "Cari perbualan",
    },
    "zh": {
        "searchMessagesHint": "使用关键词搜索",
        "closeSearchA11y": "关闭搜索",
        "noSearchResults": "没有匹配的消息。",
        "searchConversationA11y": "搜索对话",
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
    print("Added chat search l10n keys.")


if __name__ == "__main__":
    main()
