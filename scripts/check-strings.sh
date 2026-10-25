#!/bin/bash
# Lists UI strings that have no Russian translation (brand, demo and debug strings are ignored).
cd "$(dirname "$0")/.."
python3 scripts/extract-strings.py Sources/HaluMe | python3 -c '
import re, sys, plistlib
have = set(re.findall(r"^\"((?:[^\"\\\\]|\\\\.)*)\" =", open("Resources/ru.lproj/Localizable.strings").read(), re.M))
have = {h.replace("\\\\n", "\\n") for h in have}
have |= set(plistlib.load(open("Resources/ru.lproj/Localizable.stringsdict", "rb")))
ignore = {"HaluMe", "Plan each paycheck,\nnot each coffee", "HaluMe %@.csv", "HaluMe: could not save the budget: %@", "RUB", "USD", "%@, %@", "%@ — %@", " — %@",
          "%@%%", "Milana", "Yandex Split", "Yandex Plus", "Kinopoisk", "Spotify",
          "ChatGPT Plus", "Telegram Premium", "Apple Music", "VK Music", "YouTube Premium", "Netflix", }
missing = [k for k in (l.rstrip("\n").replace("\\n", "\n") for l in sys.stdin) if k not in have and k not in ignore and not re.search(r"-%@$|\.json$|^halume\.|^[A-Z]{2,3}$|^%$|^me\.|^https?:|%0|^[0-9%]+$|^%@ ?– ?%@$", k) and k not in {"AppleLanguages", "English", "Русский", "Public"}]
print("\n".join(missing) if missing else "All UI strings translated")
'
