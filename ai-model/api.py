from fastapi import FastAPI
from pydantic import BaseModel
import joblib

app = FastAPI()

model = joblib.load("models/emergency_model.pkl")

danger_words = [
    "help",
    "ambulance",
    "pain",
    "hurt",
    "injured",
    "bleeding",
    "dizzy",
    "faint",
    "breathe",

    "tolong",
    "ambulans",
    "cedera",
    "sakit",
    "pening",
    "pengsan",

    "救命",
    "头晕",
    "晕",
    "受伤",
    "疼",
    "痛"
]

class Request(BaseModel):
    text: str

@app.post("/classify")
def classify(req: Request):

    text = req.text.lower()

    for word in danger_words:
        if word.lower() in text:
            return {
                "result": "EMERGENCY",
                "source": "keyword"
            }

    prediction = model.predict([req.text])[0]

    return {
        "result": "EMERGENCY" if prediction == 1 else "SAFE",
        "source": "ai"
    }