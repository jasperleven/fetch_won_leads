#!/usr/bin/env python3
# Считает количество успешных сделок по баерам и источникам
# из /root/won_leads_14_20_07_full.json — той же логикой, что и в artaged_etl.gs
# (parseTags: первый тег не-источник, латиница, без "_"/"/", короче 15 символов).
# Печатает только компактную табличку, сырые данные никуда не выводятся.

import json
import re
from collections import defaultdict

SOURCE_MAP = {
    "ТТ": "TikTok", "TT": "TikTok", "FB": "FB",
    "YANDEX": "Yandex", "GOOGLE": "Google", "MARQUIZ": "Другое",
}
SOURCE_TAGS = ["ТТ", "TT", "FB", "YANDEX", "GOOGLE", "MARQUIZ",
               "BOT_VIBER", "TILDA", "WEBCOM", "LP"]

CYRILLIC_RE = re.compile(r"[а-яА-ЯёЁ]")

def is_likely_buyer(tag):
    if CYRILLIC_RE.search(tag):
        return False
    if "_" in tag or "/" in tag:
        return False
    if len(tag) > 15:
        return False
    return True

def parse_tags(tags):
    tg, src = "Остальные", "Другое"
    for t in tags:
        t_orig = t.get("name", "")
        t_up = t_orig.upper()
        if t_up in SOURCE_MAP and src == "Другое":
            src = SOURCE_MAP[t_up]
        if tg == "Остальные" and t_up not in SOURCE_TAGS and is_likely_buyer(t_orig):
            tg = t_up
    return tg, src

def is_phone_call_stub(name):
    return bool(re.match(r"^звонок\s+(от|на)\s+\d", (name or "").strip(), re.IGNORECASE))

with open("/root/won_leads_14_20_07_full.json", encoding="utf-8") as f:
    leads = json.load(f)

by_baer = defaultdict(int)
by_baer_src = defaultdict(int)
skipped_phone = 0

for lead in leads:
    name = lead.get("name", "")
    if is_phone_call_stub(name):
        skipped_phone += 1
        continue
    tags = lead.get("_embedded", {}).get("tags", [])
    tg, src = parse_tags(tags)
    by_baer[tg] += 1
    by_baer_src[(tg, src)] += 1

print(f"Всего сделок в файле: {len(leads)}")
print(f"Из них автосделок-звонков (исключены): {skipped_phone}")
print(f"Учтено в подсчёте: {len(leads) - skipped_phone}")
print()
print("=== По баерам (все источники) ===")
for baer, cnt in sorted(by_baer.items(), key=lambda x: -x[1]):
    print(f"  {baer:20} {cnt}")
print()
print("=== По баерам x источникам ===")
for (baer, src), cnt in sorted(by_baer_src.items()):
    print(f"  {baer:20} {src:10} {cnt}")
