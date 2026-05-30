import pathlib
import re

root = pathlib.Path(r"c:\Users\YevheniiPichkur\OneDrive - EWL\Pulpit\ssh\SysPulse\Resources")
extra = {
    "Unlock %@": ("Unlock %@", "Открыть %@", "Відкрити %@", "Odblokuj %@"),
    "systemd monitoring": ("systemd monitoring", "мониторинг systemd", "моніторинг systemd", "monitoring systemd"),
    "Free plan includes one server. Upgrade to add more.": (
        "Free plan includes one server. Upgrade to add more.",
        "Бесплатный план включает один сервер. Обновитесь, чтобы добавить больше.",
        "Безкоштовний план включає один сервер. Оновіться, щоб додати більше.",
        "Plan darmowy obejmuje jeden serwer. Ulepsz, aby dodać więcej.",
    ),
    "Show live CPU, RAM and health on the Lock Screen.": (
        "Show live CPU, RAM and health on the Lock Screen.",
        "Показывайте CPU, RAM и health на экране блокировки.",
        "Показуйте CPU, RAM і health на екрані блокування.",
        "Pokazuj CPU, RAM i health na ekranie blokady.",
    ),
}
locales = ["en", "ru", "uk", "pl"]
idx = {"en": 0, "ru": 1, "uk": 2, "pl": 3}
for loc in locales:
    p = root / f"{loc}.lproj" / "Localizable.strings"
    have = set(re.findall(r'^"([^"]+)"', p.read_text(encoding="utf-8"), re.M))
    lines = []
    for key, vals in extra.items():
        if key not in have:
            val = vals[idx[loc]].replace("\\", "\\\\").replace('"', '\\"')
            lines.append(f'"{key}" = "{val}";')
    if lines:
        with p.open("a", encoding="utf-8") as f:
            f.write("\n/* Paywall extras */\n" + "\n".join(lines) + "\n")
    print(loc, len(lines))
