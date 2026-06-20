import os
import shutil

BASE_DIR = r"C:\aura-guide-fyp\ai-model\datasets"

AURA = os.path.join(BASE_DIR, "AuraGuide")
ROD = os.path.join(BASE_DIR, "ROD-Dataset")
COMBINED = os.path.join(BASE_DIR, "CombinedDataset")

# AuraGuide -> CombinedDataset class mapping
mapping = {
    0: 23,  # chair -> Chair
    1: 25,  # door
    2: 26,  # elevator
    3: 27,  # escalator
    4: 28,  # lift_icon
    5: 3,   # person -> Person
    6: 4,   # stairs -> Stairs
    7: 29,  # surau_icon
    8: 30   # toilet_icon
}

for split in ["train", "valid", "test"]:

    # Create folders if not exist
    os.makedirs(os.path.join(COMBINED, split, "images"), exist_ok=True)
    os.makedirs(os.path.join(COMBINED, split, "labels"), exist_ok=True)

    print(f"\nProcessing {split}...")

    # ==========================
    # Copy ROD Dataset
    # ==========================
    for file in os.listdir(os.path.join(ROD, split, "images")):
        src = os.path.join(ROD, split, "images", file)
        dst = os.path.join(COMBINED, split, "images", "ROD_" + file)
        shutil.copy2(src, dst)

    for file in os.listdir(os.path.join(ROD, split, "labels")):
        src = os.path.join(ROD, split, "labels", file)
        dst = os.path.join(COMBINED, split, "labels", "ROD_" + file)
        shutil.copy2(src, dst)

    # ==========================
    # Copy AuraGuide Images
    # ==========================
    for file in os.listdir(os.path.join(AURA, split, "images")):
        src = os.path.join(AURA, split, "images", file)
        dst = os.path.join(COMBINED, split, "images", "AURA_" + file)
        shutil.copy2(src, dst)

    # ==========================
    # Remap AuraGuide Labels
    # ==========================
    for file in os.listdir(os.path.join(AURA, split, "labels")):

        src = os.path.join(AURA, split, "labels", file)
        dst = os.path.join(COMBINED, split, "labels", "AURA_" + file)

        with open(src, "r") as f:
            lines = f.readlines()

        new_lines = []

        for line in lines:
            parts = line.strip().split()

            if len(parts) == 0:
                continue

            old_class = int(parts[0])
            new_class = mapping[old_class]

            parts[0] = str(new_class)

            new_lines.append(" ".join(parts))

        with open(dst, "w") as f:
            f.write("\n".join(new_lines))

print("\n================================")
print("Merge Complete!")
print("================================")