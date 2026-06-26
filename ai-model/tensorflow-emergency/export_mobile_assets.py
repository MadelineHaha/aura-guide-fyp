"""Export TFLite model, vocabulary, and IDF weights for the Flutter app."""
from __future__ import annotations

import json
import shutil
from pathlib import Path

import numpy as np
import pandas as pd
import tensorflow as tf

ROOT = Path(__file__).resolve().parent
DATASET = ROOT.parent / "datasets" / "emergency-text" / "train.csv"
MOBILE_ASSETS = ROOT.parent.parent / "mobile-app" / "assets" / "ai"


def export_idf(vectorizer: tf.keras.layers.TextVectorization, vocab: list[str]) -> list[float]:
    idf = [0.0] * len(vocab)
    for i, token in enumerate(vocab):
        if not token or token == "[UNK]":
            continue
        vec = vectorizer(tf.constant([token])).numpy()[0]
        if i < len(vec):
            idf[i] = float(vec[i])
    return idf


def main() -> None:
    df = pd.read_csv(DATASET)
    texts = df["text"].astype(str).tolist()

    vectorizer = tf.keras.layers.TextVectorization(
        max_tokens=5000,
        output_mode="tf-idf",
    )
    vectorizer.adapt(texts)
    vocab = vectorizer.get_vocabulary()
    idf = export_idf(vectorizer, vocab)

    MOBILE_ASSETS.mkdir(parents=True, exist_ok=True)
    (MOBILE_ASSETS / "vocabulary.txt").write_text(
        "\n".join(vocab) + "\n",
        encoding="utf-8",
    )
    (MOBILE_ASSETS / "idf_weights.json").write_text(
        json.dumps(idf),
        encoding="utf-8",
    )

    tflite_src = ROOT / "emergency_model.tflite"
    if not tflite_src.exists():
        converter = tf.lite.TFLiteConverter.from_saved_model(
            str(ROOT / "saved_model_numeric")
        )
        tflite_src.write_bytes(converter.convert())

    shutil.copy2(tflite_src, MOBILE_ASSETS / "emergency_model.tflite")

    emergency = vectorizer(tf.constant(["I need help"])).numpy()[0]
    safe = vectorizer(tf.constant(["I'm fine"])).numpy()[0]
    print(f"Exported {len(vocab)} tokens to {MOBILE_ASSETS}")
    print(f"Emergency sum={float(emergency.sum()):.4f} Safe sum={float(safe.sum()):.4f}")


if __name__ == "__main__":
    main()
