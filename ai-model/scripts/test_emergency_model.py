import joblib

model = joblib.load(
    "../models/emergency_model.pkl"
)

while True:

    text = input("Say something: ")

    result = model.predict([text])[0]

    if result == 1:
        print("EMERGENCY")
    else:
        print("SAFE")