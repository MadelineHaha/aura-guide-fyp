import pandas as pd
import joblib

from sklearn.model_selection import train_test_split
from sklearn.feature_extraction.text import TfidfVectorizer
from sklearn.linear_model import LogisticRegression
from sklearn.pipeline import Pipeline
from sklearn.metrics import classification_report

# Load dataset
df = pd.read_csv(
    "../datasets/emergency-text/train.csv"
)

X = df["text"]
y = df["label"]

# Split dataset
X_train, X_test, y_train, y_test = train_test_split(
    X,
    y,
    test_size=0.2,
    random_state=42
)

# Create pipeline
model = Pipeline([
    ("tfidf", TfidfVectorizer()),
    ("classifier", LogisticRegression())
])

# Train
model.fit(X_train, y_train)

# Evaluate
predictions = model.predict(X_test)

print(classification_report(
    y_test,
    predictions
))

# Save model
joblib.dump(
    model,
    "../models/emergency_model.pkl"
)

print("\nModel saved!")