#!/usr/bin/env python3
# Считает "Кол-во квал. лидов" (Все лиды - спам) и "% Спама" по баерам/источникам
# из /root/all_leads_14_20_07_full.json, той же логикой, что computeDayData()/buildMatrixEventsLast().

import json
import re
from collections import defaultdict

SOURCE_MAP = {
    "ТТ": "TikTok", "TT": "TikTok", "FB": "FB",
    "YANDEX": "Yandex", "GOOGLE": "Google", "MARQUIZ": "Другое",
}
SOURCE_TAGS = ["ТТ", "TT", "FB", "YANDEX", "GOOGLE", "MARQUIZ",
               "BOT_VIBER", "TILDA", "WEBCOM", "LP"]
SPAM_KEYWORDS = ["спам", "spam", "дубл"]
CYRILLIC_RE = re.compile(r"[а-яА-ЯёЁ]")

def is_likely_buyer(tag):
    if CYRILLIC_RE.search(tag): return False
    if "_" in tag or "/" in tag: return False
    if len(tag) > 15: return False
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

def get_cf(lead, key_substr):
    key_substr = key_substr.lower()
    for cf in lead.get("custom_fields_values") or []:
        if key_substr in (cf.get("field_name") or "").lower():
            vals = cf.get("values") or []
            return vals[0]["value"] if vals else None
    return None

with open("/root/all_leads_14_20_07_full.json", encoding="utf-8") as f:
    leads = json.load(f)

leads_total = defaultdict(int)
spam = defaultdict(int)
qual = defaultdict(int)
leads_total_src = defaultdict(int)
spam_src = defaultdict(int)
qual_src = defaultdict(int)
skipped_phone = 0

for lead in leads:
    name = lead.get("name", "")
    if is_phone_call_stub(name):
        skipped_phone += 1
        continue
    tags = lead.get("_embedded", {}).get("tags", [])
    tg, src = parse_tags(tags)
    reason = (get_cf(lead, "причина отказа") or "").lower()
    is_spam = any(k in reason for k in SPAM_KEYWORDS)

    leads_total[tg] += 1
    leads_total_src[(tg, src)] += 1
    if is_spam:
        spam[tg] += 1
        spam_src[(tg, src)] += 1
    else:
        qual[tg] += 1
        qual_src[(tg, src)] += 1

print(f"Всего лидов в файле: {len(leads)} (исключено звонков-заглушек: {skipped_phone})")
print()
print("=== Квал. лиды по баерам (все источники) ===")
total_q = total_l = 0
for baer in sorted(leads_total, key=lambda b: -leads_total[b]):
    l, s, q = leads_total[baer], spam[baer], qual[baer]
    pct = round(s / l * 100, 1) if l else 0
    print(f"  {baer:20} всего={l:<4} спам={s:<4} квал={q:<4} %спама={pct}")
    total_q += q; total_l += l
print(f"  {'ИТОГО':20} всего={total_l:<4} квал={total_q}")
print()
print("=== Квал. лиды по баерам x источникам ===")
for (baer, src) in sorted(leads_total_src):
    l = leads_total_src[(baer, src)]
    s = spam_src.get((baer, src), 0)
    q = qual_src.get((baer, src), 0)
    print(f"  {baer:20} {src:10} всего={l:<4} спам={s:<4} квал={q}")
