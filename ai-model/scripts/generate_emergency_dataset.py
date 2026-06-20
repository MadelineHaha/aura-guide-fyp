import pandas as pd

# =====================
# SAFE PHRASES
# =====================

safe_templates = [

    # English
    "I'm okay",
    "I am okay",
    "I'm fine",
    "Everything is fine",
    "Everything is okay",
    "No problem",
    "False alarm",
    "I can walk",
    "I can stand",
    "I am safe",
    "I am not injured",
    "I don't need help",
    "No emergency",
    "I feel good",
    "I feel alright",
    "I can continue walking",
    "Nothing happened",
    "I recovered",
    "I'm still standing",

    # Malay
    "Saya okay",
    "Saya tidak apa apa",
    "Saya baik",
    "Saya selamat",
    "Tiada masalah",
    "Saya tidak cedera",
    "Saya boleh berjalan",
    "Saya boleh berdiri",
    "Saya tidak perlukan bantuan",
    "Semuanya baik",
    "Tiada kecemasan",
    "Saya sihat",
    "Saya rasa baik",

    # Chinese
    "我没事",
    "我很好",
    "没问题",
    "我很安全",
    "我没有受伤",
    "我可以走路",
    "我可以站起来",
    "我不需要帮助",
    "一切都很好",
    "没有紧急情况",
    "我感觉很好",
    "我恢复了",
    "我还能站着"
]

# =====================
# EMERGENCY PHRASES
# =====================

emergency_templates = [

    # English
    "Help me",
    "I need help",
    "Emergency",
    "Call ambulance",
    "Call for help",
    "I fell down",
    "I am injured",
    "I cannot move",
    "I can't walk",
    "I can't stand",
    "I am in pain",
    "My leg hurts",
    "My head hurts",
    "I feel dizzy",
    "I feel weak",
    "I might faint",
    "I cannot breathe",
    "I can't breathe",
    "I am bleeding",
    "I need urgent help",
    "I need immediate help",
    "I hit my head",
    "I think I am dying",
    "I feel like I am dying",
    "Please help me",
    "Send help",
    "Call somebody",
    "I lost consciousness",
    "I feel terrible",
    "My chest hurts",

    # Malay
    "Tolong saya",
    "Saya perlukan bantuan",
    "Kecemasan",
    "Panggil ambulans",
    "Saya jatuh",
    "Saya cedera",
    "Saya tidak boleh bergerak",
    "Saya tidak boleh berjalan",
    "Saya tidak boleh berdiri",
    "Saya sakit",
    "Kaki saya sakit",
    "Kepala saya sakit",
    "Saya pening",
    "Saya rasa lemah",
    "Saya mungkin pengsan",
    "Saya tidak boleh bernafas",
    "Saya berdarah",
    "Saya perlukan bantuan segera",
    "Tolong bantu saya",
    "Saya rasa seperti mahu mati",
    "Dada saya sakit",
    "Saya tidak sihat",

    # Chinese
    "救命",
    "帮帮我",
    "紧急情况",
    "叫救护车",
    "我跌倒了",
    "我受伤了",
    "我不能动",
    "我不能走路",
    "我不能站起来",
    "我很痛",
    "我的腿很痛",
    "我的头很痛",
    "我头晕",
    "我很虚弱",
    "我快晕倒了",
    "我无法呼吸",
    "我流血了",
    "我需要紧急帮助",
    "请帮助我",
    "我觉得我要死了",
    "我的胸口很痛",
    "我失去意识了",
    "我感觉很糟糕"
]

# =====================
# PREFIXES
# =====================

safe_prefixes = [
    "",
    "I think ",
    "Actually ",
    "Honestly ",
    "Luckily ",
    "Thankfully "
]

safe_suffixes = [
    "",
    " now",
    " at the moment",
    " right now",
    " after the fall"
]

emergency_prefixes = [
    "",
    "Please ",
    "Urgently ",
    "Quickly ",
    "Someone please "
]

emergency_suffixes = [
    "",
    " right now",
    " immediately",
    " please",
    " as soon as possible"
]

rows = []

# =====================
# SAFE DATA
# =====================

for prefix in safe_prefixes:
    for text in safe_templates:
        for suffix in safe_suffixes:
            rows.append([
                f"{prefix}{text}{suffix}".strip(),
                0
            ])

# =====================
# EMERGENCY DATA
# =====================

for prefix in emergency_prefixes:
    for text in emergency_templates:
        for suffix in emergency_suffixes:
            rows.append([
                f"{prefix}{text}{suffix}".strip(),
                1
            ])

df = pd.DataFrame(
    rows,
    columns=["text", "label"]
)

df = df.drop_duplicates()

df.to_csv(
    "../datasets/emergency-text/train.csv",
    index=False,
    encoding="utf-8-sig"
)

print("===================================")
print("Dataset Generated Successfully")
print("Total Samples:", len(df))
print("===================================")