from ultralytics import YOLO

model = YOLO(
    r"runs\detect\runs\auraguide_yolo11s-3\weights\best.pt"
)

model.export(
    format="tflite"
)

print("Export completed!")