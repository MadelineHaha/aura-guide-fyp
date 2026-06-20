#!/usr/bin/env python3
"""Add emergency SOS l10n keys and regenerate Dart maps."""
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
        "sosCountdownIntro": "Emergency alert sending in 5 seconds. Double tap Cancel to stop.",
        "sosCountdownTick": "Sending in {seconds} seconds. Double tap Cancel to stop.",
        "sosCountdownStopped": "Emergency alert cancelled.",
        "sosOpeningMessage": "Emergency alert will send automatically. Double tap Cancel to stop.",
        "sosEmergencyVoiceCancelled": "Emergency alert cancelled.",
        "sosEmergencyCancelledSnackbar": "Emergency alert cancelled.",
        "sosAlertSentVoice": "Emergency alert sent. Healthcare staff have been notified.",
        "sosSentSnackbar": "Emergency alert sent. Alert ID {id}.",
        "sosStaffResponding": "Healthcare staff are responding to your alert.",
        "sosStaffNotified": "Healthcare staff have been notified.",
        "sosCheckingStatus": "Checking emergency alert status.",
        "sosSending": "Sending",
        "sosSent": "Sent",
        "sosSentA11y": "Emergency alert sent.{idPart}{statusPart}{locationPart}",
        "gpsSharedWithLocation": "Location shared: {location}.",
        "gpsBeingShared": "Sharing your location.",
        "sharingLocationWithStaff": "Sharing location with healthcare staff.",
        "sosCancelTapAgain": "Double tap Cancel to stop the emergency alert.",
        "sosCancelA11yLabel": "Cancel emergency alert. Double tap to stop.",
    },
    "ms": {
        "sosCountdownIntro": "Amaran kecemasan dihantar dalam 5 saat. Ketik dua kali Batal untuk berhenti.",
        "sosCountdownTick": "Menghantar dalam {seconds} saat. Ketik dua kali Batal untuk berhenti.",
        "sosCountdownStopped": "Amaran kecemasan dibatalkan.",
        "sosOpeningMessage": "Amaran kecemasan akan dihantar secara automatik. Ketik dua kali Batal untuk berhenti.",
        "sosEmergencyVoiceCancelled": "Amaran kecemasan dibatalkan.",
        "sosEmergencyCancelledSnackbar": "Amaran kecemasan dibatalkan.",
        "sosAlertSentVoice": "Amaran kecemasan dihantar. Kakitangan kesihatan telah dimaklumkan.",
        "sosSentSnackbar": "Amaran kecemasan dihantar. ID amaran {id}.",
        "sosStaffResponding": "Kakitangan kesihatan sedang bertindak balas.",
        "sosStaffNotified": "Kakitangan kesihatan telah dimaklumkan.",
        "sosCheckingStatus": "Menyemak status amaran kecemasan.",
        "sosSending": "Menghantar",
        "sosSent": "Dihantar",
        "sosSentA11y": "Amaran kecemasan dihantar.{idPart}{statusPart}{locationPart}",
        "gpsSharedWithLocation": "Lokasi dikongsi: {location}.",
        "gpsBeingShared": "Berkongsi lokasi anda.",
        "sharingLocationWithStaff": "Berkongsi lokasi dengan kakitangan kesihatan.",
        "sosCancelTapAgain": "Ketik dua kali Batal untuk menghentikan amaran kecemasan.",
        "sosCancelA11yLabel": "Batal amaran kecemasan. Ketik dua kali untuk berhenti.",
    },
    "zh": {
        "sosCountdownIntro": "紧急警报将在 5 秒后发送。双击取消可停止。",
        "sosCountdownTick": "将在 {seconds} 秒后发送。双击取消可停止。",
        "sosCountdownStopped": "紧急警报已取消。",
        "sosOpeningMessage": "紧急警报将自动发送。双击取消可停止。",
        "sosEmergencyVoiceCancelled": "紧急警报已取消。",
        "sosEmergencyCancelledSnackbar": "紧急警报已取消。",
        "sosAlertSentVoice": "紧急警报已发送，医护人员已收到通知。",
        "sosSentSnackbar": "紧急警报已发送。警报编号 {id}。",
        "sosStaffResponding": "医护人员正在响应您的警报。",
        "sosStaffNotified": "医护人员已收到通知。",
        "sosCheckingStatus": "正在检查紧急警报状态。",
        "sosSending": "发送中",
        "sosSent": "已发送",
        "sosSentA11y": "紧急警报已发送。{idPart}{statusPart}{locationPart}",
        "gpsSharedWithLocation": "已共享位置：{location}。",
        "gpsBeingShared": "正在共享您的位置。",
        "sharingLocationWithStaff": "正在与医护人员共享位置。",
        "sosCancelTapAgain": "再次双击取消以停止紧急警报。",
        "sosCancelA11yLabel": "取消紧急警报。双击停止。",
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
    print("Added emergency SOS l10n keys.")


if __name__ == "__main__":
    main()
