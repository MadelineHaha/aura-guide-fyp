import tensorflow as tf

converter = tf.lite.TFLiteConverter.from_saved_model(
    "saved_model_numeric"
)

tflite_model = converter.convert()

with open(
    "emergency_model.tflite",
    "wb"
) as f:
    f.write(tflite_model)

print(
    "TFLite model created successfully!"
)