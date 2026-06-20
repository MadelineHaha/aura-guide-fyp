from ultralytics import YOLO

def main():
    model = YOLO("yolo11s.pt")

    model.train(
        data="datasets/CombinedDataset/data.yaml",
        epochs=100,
        imgsz=640,
        batch=8,
        device=0,
        workers=0,
        project="runs",
        name="auraguide_yolo11s"
    )

if __name__ == "__main__":
    main()