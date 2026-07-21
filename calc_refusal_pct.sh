#!/bin/bash
# Забирает теги для сделок, прошедших "Договор подписан" (батчами по 50),
# и считает % Отказов по баерам — та же логика, что getRefusedLeads() в artaged_etl.gs

TOKEN="eyJ0eXAiOiJKV1QiLCJhbGciOiJSUzI1NiIsImp0aSI6IjBlMTQ2YzI3MDk0NTkyMmQxM2JmMGZkMTgzYjU2ZjI4NzI0N2Y3ZDk2NGI3OWRiY2YwNGQ1ZTJjZTQ5YWJkNThmNWY2ZmI1YjM1MTRkYzQ0In0.eyJhdWQiOiIwNDRlYzY0Mi0xMTAxLTRlYzgtOTBiYy03MThjODU1YTZjYmIiLCJqdGkiOiIwZTE0NmMyNzA5NDU5MjJkMTNiZjBmZDE4M2I1NmYyODcyNDdmN2Q5NjRiNzlkYmNmMDRkNWUyY2U0OWFiZDU4ZjVmNmZiNWIzNTE0ZGM0NCIsImlhdCI6MTc4Mjg5NDE1NCwibmJmIjoxNzgyODk0MTU0LCJleHAiOjE4NDM0MzA0MDAsInN1YiI6IjExNDY3MjU4IiwiZ3JhbnRfdHlwZSI6IiIsImFjY291bnRfaWQiOjMxOTI4Mjk4LCJiYXNlX2RvbWFpbiI6ImFtb2NybS5ydSIsInZlcnNpb24iOjIsInNjb3BlcyI6WyJwdXNoX25vdGlmaWNhdGlvbnMiLCJmaWxlcyIsImNybSIsImZpbGVzX2RlbGV0ZSIsIm5vdGlmaWNhdGlvbnMiXSwiaGFzaF91dWlkIjoiMjM2Mjc0M2UtMDA3NC00ZjJhLWIzMzgtOTc5YjgxZjY1NGFlIiwiYXBpX2RvbWFpbiI6ImFwaS1iLmFtb2NybS5ydSJ9.AC-lkIhD_CIkM9c12WVayoEjolvyTNEpvDkfBY95WyoMjsRaRgn57wkDBl-pOGuNuLkts94DubkkoyAkZjEVZ7AuZyoTuZvyTL5TFYz4cU2tmR0Igy-WdboJcD3AgAdSe1KSb5chmoOX06kqH93cO78H_F_5_u2k4pyWHvLTe2LMwbthXU900UMQFQshLVKTsilaLJviUBfYdscNKd2Un0XedJL8Fiu--lp4BkWWr0oq_71Jy9CETm2U8oUaFW8lkGKezjnLcqXhdma3siZNqICOHFVXLQRAE7k6qvJIfUyCendrepO_rLoMt7ShGQjYB4MDd3lBXSjhK8-Svn1Xsg"

echo "$TOKEN" > /root/.amo_token_tmp

python3 << 'PYEOF'
import json
import urllib.request
import re

TOKEN = open("/root/.amo_token_tmp").read().strip()

with open("/root/contract_lead_ids.json") as f:
    contract_ids = json.load(f)
with open("/root/refusal_lead_ids.json") as f:
    refusal_ids = set(json.load(f))

SOURCE_TAGS = ["ТТ", "TT", "FB", "YANDEX", "GOOGLE", "MARQUIZ", "BOT_VIBER", "TILDA", "WEBCOM", "LP"]
CYRILLIC_RE = re.compile(r"[а-яА-ЯёЁ]")

def is_likely_buyer(tag):
    if CYRILLIC_RE.search(tag): return False
    if "_" in tag or "/" in tag: return False
    if len(tag) > 15: return False
    return True

def parse_tag(tags):
    tg = "Остальные"
    for t in tags:
        t_orig = t.get("name", "")
        t_up = t_orig.upper()
        if tg == "Остальные" and t_up not in SOURCE_TAGS and is_likely_buyer(t_orig):
            tg = t_up
    return tg

contracted_by_baer = {}
refused_by_baer = {}

batch_size = 50
for i in range(0, len(contract_ids), batch_size):
    batch = contract_ids[i:i+batch_size]
    params = "&".join(f"filter[id][]={lid}" for lid in batch)
    url = f"https://daangrah000.amocrm.ru/api/v4/leads?{params}&with=tags&limit=50"
    req = urllib.request.Request(url, headers={"Authorization": f"Bearer {TOKEN}"})
    try:
        with urllib.request.urlopen(req) as resp:
            data = json.loads(resp.read())
    except Exception as e:
        print(f"Ошибка батча {i}: {e}")
        continue

    leads = data.get("_embedded", {}).get("leads", [])
    for lead in leads:
        tags = lead.get("_embedded", {}).get("tags", [])
        tg = parse_tag(tags)
        contracted_by_baer[tg] = contracted_by_baer.get(tg, 0) + 1
        if lead["id"] in refusal_ids:
            refused_by_baer[tg] = refused_by_baer.get(tg, 0) + 1

print("=== % Отказов по баерам (когорта с начала месяца) ===")
total_c = total_r = 0
for baer in sorted(contracted_by_baer, key=lambda b: -contracted_by_baer[b]):
    c = contracted_by_baer[baer]
    r = refused_by_baer.get(baer, 0)
    pct = round(r / c * 100, 1) if c else 0
    print(f"  {baer:20} договоров={c:<5} отказов={r:<5} %отказов={pct}")
    total_c += c
    total_r += r
print(f"  {'ВСЕГО':20} договоров={total_c:<5} отказов={total_r:<5} %отказов={round(total_r/total_c*100,1) if total_c else 0}")
PYEOF

rm -f /root/.amo_token_tmp
