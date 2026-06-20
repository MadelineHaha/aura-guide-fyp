import pandas as pd
import tensorflow as tf
from sklearn.model_selection import train_test_split
import numpy as np

# Load dataset
df = pd.read_csv(
    "../datasets/emergency-text/train.csv"
)

texts = df["text"].astype(str).tolist()
labels = df["label"].astype("float32").tolist()

# Split
x_train, x_test, y_train, y_test = train_test_split(
    texts,
    labels,
    test_size=0.2,
    random_state=42
)

y_train = np.array(y_train, dtype=np.float32)
y_test = np.array(y_test, dtype=np.float32)

# Create vectorizer
vectorizer = tf.keras.layers.TextVectorization(
    max_tokens=5000,
    output_mode="tf-idf"
)

vectorizer.adapt(x_train)

# Save vocabulary
vocab = vectorizer.get_vocabulary()

with open(
    "vocabulary.txt",
    "w",
    encoding="utf-8"
) as f:
    for word in vocab:
        f.write(word + "\n")

print("Vocabulary saved")

# Convert text to TF-IDF vectors
x_train_vec = vectorizer(
    tf.constant(x_train)
).numpy()

x_test_vec = vectorizer(
    tf.constant(x_test)
).numpy()

# Model WITHOUT TextVectorization
model = tf.keras.Sequential([
    tf.keras.Input(
        shape=(x_train_vec.shape[1],)
    ),
    tf.keras.layers.Dense(
        64,
        activation="relu"
    ),
    tf.keras.layers.Dense(
        1,
        activation="sigmoid"
    )
])

model.compile(
    optimizer="adam",
    loss="binary_crossentropy",
    metrics=["accuracy"]
)

model.fit(
    x_train_vec,
    y_train,
    epochs=10,
    validation_split=0.1,
    batch_size=32
)

loss, acc = model.evaluate(
    x_test_vec,
    y_test
)

print("Accuracy:", acc)

model.export(
    "saved_model_numeric"
)

print("Training complete")