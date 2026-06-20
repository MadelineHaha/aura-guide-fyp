import joblib

# Load trained model
model = joblib.load("../models/emergency_model.pkl")

danger_words = [
    # English
    "help",
    "ambulance",
    "pain",
    "hurt",
    "injured",
    "bleeding",
    "dizzy",
    "faint",
    "unconscious",
    "breathe",
    "emergency",

    # Malay
    "tolong",
    "ambulans",
    "cedera",
    "sakit",
    "pening",
    "pengsan",
    "kecemasan",

    # Chinese
    "救命",
    "受伤",
    "疼",
    "痛",
    "头晕",
    "晕",
    "呼吸",
    "救护车",
    "紧急"
]

def classify(text):
    text_lower = text.lower()

    # Safety rule layer
    for word in danger_words:
        if word.lower() in text_lower:
            return "EMERGENCY"

    # AI prediction
    prediction = model.predict([text])[0]

    if prediction == 1:
        return "EMERGENCY"

    return "SAFE"


if __name__ == "__main__":

    while True:
        text = input("Say something: ")

        result = classify(text)

        print(result)