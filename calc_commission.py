#!/usr/bin/env python3
# Считает "Комиссия успешных сделок" по баерам из уже скачанного JSON,
# формулой из calcCommission() в artaged_etl.gs:
# Комиссия = Σ(Сумма банк N) − Доставка цена фактическая − Стоимость закупки − Σ(Сумма банк N × %банка/100)

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

BANK_COMMISSION_PERCENT = {
  "СБЕР-Банк": 4.0, "СБЕР-Банк Рассрочка 6 мес": 7.2, "СБЕР-Банк Рассрочка 9-12 мес": 11.5,
  "СБЕР-Банк Рассрочка 15-18 мес": 16.0, "СБЕР-Банк Грейс 5/24 - 6/36": 8.0,
  "СБЕР-Банк Грейс 12/24 - 12/60": 12.5, "НеоБанк Азия": 4.0,
  "НеоБанк Азия Рассрочка 4-6 мес": 7.0, "НеоБанк Азия Рассрочка 10-15 мес": 13.0,
  "НеоБанк Азия Рассрочка": 13.0, "Дабрабыт Рассрочка 6 мес": 8.0,
  "Дабрабыт Рассрочка 9-12 мес": 13.0, "Дабрабыт Рассрочка 15-18 мес": 19.0,
  "Дабрабыт Грейс 6/12-6/60": 8.5, "Дабрабыт Грейс 12/18-12/60": 14.0,
  "Дабрабыт Рассрочка": 19.0, "Дабрабыт Базовый": 0.5, "Дабрабыт базовый": 0.0,
  "Дабрабыт Комбо РБ": 4.0, "Банк Дабрабыт Комбо": 4.0, "Банк Решение Акционный": 0.0,
  "Банк Решение Решено": 3.0, "Банк Решение Стабильный РБ": 2.5,
  "(Архив)Банк Решение Акционный": 4.0, "(Архив)Банк Решение Стабильный РБ": 4.0,
  "(Архив)Банк Решение Решено": 4.0, "Банк Решение R-mix": 4.0, "Банк Решение": 4.0,
  "Банк Решение 0%": 0.0, "ПаритетБанк": 6.5, "Паритет ПО": 6.0, "РРБ-банк": 4.0,
  "РРБ базовый": 1.0, "РитейлЛизинг": 0.0, "ЛайтЛизинг": 0.0, "БЕЗНАЛ": 0.0,
  "Акцепт Лизинг": 0.0, "Автопромлизинг": 0.0, "Альфа-Банк": 2.4, "МТБанк": 2.4,
  "Статусбанк": 2.4, "БелВЭБ": 3.5, "БелВЭБ рассрочка 6 мес": 9.0,
  "БелВЭБ рассрочка 12 мес": 14.0, "БНБ Комбо": 4.0, "БНБ Рассрочка": 7.0,
  "Кэпитал Лизинг": 0.0, "Наличные": 2.5, "Ювилс Лизинг": 0.0,
}

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

def get_cf_exact(lead, exact_name):
    target = exact_name.lower().strip()
    for cf in lead.get("custom_fields_values") or []:
        if (cf.get("field_name") or "").lower().strip() == target:
            vals = cf.get("values") or []
            return vals[0]["value"] if vals else None
    return None

def get_bank_percent(bank_name):
    if not bank_name:
        return 0.0
    return BANK_COMMISSION_PERCENT.get(str(bank_name).strip(), 0.0)

def calc_commission(lead):
    suffixes = ["", " 2", " 3", " 4", " 5", " 6", " 7", " 8", " 9", " 10"]
    bank_sum, bank_comm_sum = 0.0, 0.0
    for suf in suffixes:
        amt_raw = get_cf_exact(lead, "Сумма банк" + suf)
        try:
            amt = float(amt_raw)
        except (TypeError, ValueError):
            continue
        if not amt:
            continue
        bank_name = get_cf_exact(lead, "Банк" + suf)
        bank_sum += amt
        bank_comm_sum += amt * (get_bank_percent(bank_name) / 100)

    try:
        delivery = float(get_cf_exact(lead, "Доставка цена фактическая") or 0)
    except (TypeError, ValueError):
        delivery = 0.0
    try:
        purchase = float(get_cf_exact(lead, "стоимость закупки") or 0)
    except (TypeError, ValueError):
        purchase = 0.0

    return bank_sum - delivery - purchase - bank_comm_sum

with open("/root/won_leads_14_20_07_full.json", encoding="utf-8") as f:
    leads = json.load(f)

by_baer = defaultdict(float)
by_baer_src = defaultdict(float)
unmatched_banks = set()

for lead in leads:
    name = lead.get("name", "")
    if is_phone_call_stub(name):
        continue
    tags = lead.get("_embedded", {}).get("tags", [])
    tg, src = parse_tags(tags)
    comm = calc_commission(lead)
    by_baer[tg] += comm
    by_baer_src[(tg, src)] += comm

    # проверим банки без % в таблице
    for suf in ["", " 2", " 3"]:
        bank_name = get_cf_exact(lead, "Банк" + suf)
        if bank_name and str(bank_name).strip() not in BANK_COMMISSION_PERCENT:
            unmatched_banks.add(str(bank_name).strip())

print("=== Комиссия по баерам (все источники), руб ===")
total = 0
for baer, comm in sorted(by_baer.items(), key=lambda x: -x[1]):
    print(f"  {baer:20} {round(comm):>10}")
    total += comm
print(f"  {'ИТОГО':20} {round(total):>10}")
print()
print("=== Комиссия по баерам x источникам, руб ===")
for (baer, src), comm in sorted(by_baer_src.items()):
    print(f"  {baer:20} {src:10} {round(comm):>10}")

if unmatched_banks:
    print()
    print("⚠ Банки, не найденные в BANK_COMMISSION_PERCENT (считались как 0%):")
    for b in sorted(unmatched_banks):
        print(f"  - {b}")
