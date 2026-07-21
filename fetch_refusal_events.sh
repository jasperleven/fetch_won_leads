#!/bin/bash
# Когортный расчёт % Отказов за текущий месяц (с 1 июля 2026).
# Логика: находим лиды, прошедшие статус "Договор подписан", затем среди них —
# сколько ушло в отказные этапы. Результат — /root/refusal_events_full.json

TOKEN="eyJ0eXAiOiJKV1QiLCJhbGciOiJSUzI1NiIsImp0aSI6IjBlMTQ2YzI3MDk0NTkyMmQxM2JmMGZkMTgzYjU2ZjI4NzI0N2Y3ZDk2NGI3OWRiY2YwNGQ1ZTJjZTQ5YWJkNThmNWY2ZmI1YjM1MTRkYzQ0In0.eyJhdWQiOiIwNDRlYzY0Mi0xMTAxLTRlYzgtOTBiYy03MThjODU1YTZjYmIiLCJqdGkiOiIwZTE0NmMyNzA5NDU5MjJkMTNiZjBmZDE4M2I1NmYyODcyNDdmN2Q5NjRiNzlkYmNmMDRkNWUyY2U0OWFiZDU4ZjVmNmZiNWIzNTE0ZGM0NCIsImlhdCI6MTc4Mjg5NDE1NCwibmJmIjoxNzgyODk0MTU0LCJleHAiOjE4NDM0MzA0MDAsInN1YiI6IjExNDY3MjU4IiwiZ3JhbnRfdHlwZSI6IiIsImFjY291bnRfaWQiOjMxOTI4Mjk4LCJiYXNlX2RvbWFpbiI6ImFtb2NybS5ydSIsInZlcnNpb24iOjIsInNjb3BlcyI6WyJwdXNoX25vdGlmaWNhdGlvbnMiLCJmaWxlcyIsImNybSIsImZpbGVzX2RlbGV0ZSIsIm5vdGlmaWNhdGlvbnMiXSwiaGFzaF91dWlkIjoiMjM2Mjc0M2UtMDA3NC00ZjJhLWIzMzgtOTc5YjgxZjY1NGFlIiwiYXBpX2RvbWFpbiI6ImFwaS1iLmFtb2NybS5ydSJ9.AC-lkIhD_CIkM9c12WVayoEjolvyTNEpvDkfBY95WyoMjsRaRgn57wkDBl-pOGuNuLkts94DubkkoyAkZjEVZ7AuZyoTuZvyTL5TFYz4cU2tmR0Igy-WdboJcD3AgAdSe1KSb5chmoOX06kqH93cO78H_F_5_u2k4pyWHvLTe2LMwbthXU900UMQFQshLVKTsilaLJviUBfYdscNKd2Un0XedJL8Fiu--lp4BkWWr0oq_71Jy9CETm2U8oUaFW8lkGKezjnLcqXhdma3siZNqICOHFVXLQRAE7k6qvJIfUyCendrepO_rLoMt7ShGQjYB4MDd3lBXSjhK8-Svn1Xsg"

# Начало текущего месяца (01.07.2026 00:00 Минск, UTC+3) — ИСПРАВЛЕНО
MONTH_FROM=1782853200   # 01.07.2026 00:00:00 Минск -> UTC 30.06 21:00

echo "Начало месяца (проверка): $(date -d @$MONTH_FROM)"

OUT="/root/refusal_events_full.json"
TMPDIR=$(mktemp -d)
page=1

echo "Скачиваю события lead_status_changed..."
while true; do
  resp="$TMPDIR/page_$page.json"
  code=$(curl -s -g -o "$resp" -w "%{http_code}" \
    "https://daangrah000.amocrm.ru/api/v4/events?filter[type]=lead_status_changed&filter[created_at][from]=$MONTH_FROM&limit=250&page=$page" \
    -H "Authorization: Bearer $TOKEN")

  if [ "$code" == "204" ]; then
    echo "Страница $page: пусто (204) — конец данных."
    break
  fi
  if [ "$code" == "500" ] || [ "$code" == "429" ] || [ "$code" == "502" ] || [ "$code" == "503" ] || [ "$code" == "504" ]; then
    echo "Страница $page: ошибка HTTP $code — жду 5 сек и повторяю..."
    sleep 5
    continue
  fi
  if [ "$code" != "200" ]; then
    echo "Страница $page: ошибка HTTP $code"
    cat "$resp"
    break
  fi

  count=$(python3 -c "import json; d=json.load(open('$resp')); print(len(d.get('_embedded',{}).get('events',[])))" 2>/dev/null || echo 0)
  echo "Страница $page: $count событий"

  if [ "$count" == "0" ]; then
    break
  fi

  page=$((page+1))
  sleep 1
  if [ "$page" -gt 100 ]; then
    echo "Стоп — подозрительно много страниц (>100), прерываю."
    break
  fi
done

python3 << PYEOF
import json, glob
all_events = []
for f in sorted(glob.glob("$TMPDIR/page_*.json"), key=lambda x: int(x.split('_')[-1].split('.')[0])):
    try:
        d = json.load(open(f))
        all_events.extend(d.get('_embedded', {}).get('events', []))
    except Exception as e:
        print(f"Пропуск {f}: {e}")
with open("$OUT", "w", encoding="utf-8") as out:
    json.dump(all_events, out, ensure_ascii=False, indent=2)
print(f"Итого событий: {len(all_events)}")
PYEOF

rm -rf "$TMPDIR"

echo ""
echo "=== Ищу лиды, прошедшие 'Договор подписан' и ушедшие в отказ ==="
python3 << 'PYEOF'
import json

CONTRACT_SIGNED_IDS = {69561406, 85398554, 75840762}
REFUSAL_STATUS_IDS = {143, 85524994, 85411606, 85411610, 85411526, 85411534, 85398486, 85411638}

with open("/root/refusal_events_full.json", encoding="utf-8") as f:
    events = json.load(f)

contract_leads = set()
refusal_leads = set()

for e in events:
    va = e.get("value_after")
    if not va or not va[0].get("lead_status"):
        continue
    to_status = va[0]["lead_status"].get("id")
    if to_status is None:
        continue
    entity_id = e.get("entity_id")
    if to_status in CONTRACT_SIGNED_IDS:
        contract_leads.add(entity_id)
    if to_status in REFUSAL_STATUS_IDS:
        refusal_leads.add(entity_id)

print(f"Прошли 'Договор подписан': {len(contract_leads)}")
print(f"Ушли в отказ (из всех событий, не обязательно из числа прошедших договор): {len(refusal_leads)}")

with open("/root/contract_lead_ids.json", "w") as f:
    json.dump(sorted(contract_leads), f)
with open("/root/refusal_lead_ids.json", "w") as f:
    json.dump(sorted(refusal_leads), f)
print("ID сохранены в /root/contract_lead_ids.json и /root/refusal_lead_ids.json")
PYEOF
