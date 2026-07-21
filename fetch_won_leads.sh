#!/bin/bash
# Полная выгрузка успешных сделок (status_id=142, pipeline_id=8568342)
# за 14-20 июля 2026, с обработкой ВСЕХ страниц (не только первой).
# Результат — один валидный JSON-массив сделок в /root/won_leads_14_20_07_full.json

TOKEN="eyJ0eXAiOiJKV1QiLCJhbGciOiJSUzI1NiIsImp0aSI6IjBlMTQ2YzI3MDk0NTkyMmQxM2JmMGZkMTgzYjU2ZjI4NzI0N2Y3ZDk2NGI3OWRiY2YwNGQ1ZTJjZTQ5YWJkNThmNWY2ZmI1YjM1MTRkYzQ0In0.eyJhdWQiOiIwNDRlYzY0Mi0xMTAxLTRlYzgtOTBiYy03MThjODU1YTZjYmIiLCJqdGkiOiIwZTE0NmMyNzA5NDU5MjJkMTNiZjBmZDE4M2I1NmYyODcyNDdmN2Q5NjRiNzlkYmNmMDRkNWUyY2U0OWFiZDU4ZjVmNmZiNWIzNTE0ZGM0NCIsImlhdCI6MTc4Mjg5NDE1NCwibmJmIjoxNzgyODk0MTU0LCJleHAiOjE4NDM0MzA0MDAsInN1YiI6IjExNDY3MjU4IiwiZ3JhbnRfdHlwZSI6IiIsImFjY291bnRfaWQiOjMxOTI4Mjk4LCJiYXNlX2RvbWFpbiI6ImFtb2NybS5ydSIsInZlcnNpb24iOjIsInNjb3BlcyI6WyJwdXNoX25vdGlmaWNhdGlvbnMiLCJmaWxlcyIsImNybSIsImZpbGVzX2RlbGV0ZSIsIm5vdGlmaWNhdGlvbnMiXSwiaGFzaF91dWlkIjoiMjM2Mjc0M2UtMDA3NC00ZjJhLWIzMzgtOTc5YjgxZjY1NGFlIiwiYXBpX2RvbWFpbiI6ImFwaS1iLmFtb2NybS5ydSJ9.AC-lkIhD_CIkM9c12WVayoEjolvyTNEpvDkfBY95WyoMjsRaRgn57wkDBl-pOGuNuLkts94DubkkoyAkZjEVZ7AuZyoTuZvyTL5TFYz4cU2tmR0Igy-WdboJcD3AgAdSe1KSb5chmoOX06kqH93cO78H_F_5_u2k4pyWHvLTe2LMwbthXU900UMQFQshLVKTsilaLJviUBfYdscNKd2Un0XedJL8Fiu--lp4BkWWr0oq_71Jy9CETm2U8oUaFW8lkGKezjnLcqXhdma3siZNqICOHFVXLQRAE7k6qvJIfUyCendrepO_rLoMt7ShGQjYB4MDd3lBXSjhK8-Svn1Xsg"

OUT="/root/won_leads_14_20_07_full.json"
TMPDIR=$(mktemp -d)
page=1

echo "Скачиваю страницы..."
while true; do
  resp="$TMPDIR/page_$page.json"
  code=$(curl -s -g -o "$resp" -w "%{http_code}" \
    "https://daangrah000.amocrm.ru/api/v4/leads?filter[statuses][0][pipeline_id]=8568342&filter[statuses][0][status_id]=142&filter[closed_at][from]=1752447600&filter[closed_at][to]=1753052399&with=tags,custom_fields_values&limit=250&page=$page" \
    -H "Authorization: Bearer $TOKEN")

  if [ "$code" == "204" ]; then
    echo "Страница $page: пусто (204) — конец данных."
    break
  fi
  if [ "$code" != "200" ]; then
    echo "Страница $page: ошибка HTTP $code"
    cat "$resp"
    break
  fi

  count=$(python3 -c "import json; d=json.load(open('$resp')); print(len(d.get('_embedded',{}).get('leads',[])))" 2>/dev/null || echo 0)
  echo "Страница $page: $count сделок"

  if [ "$count" == "0" ]; then
    break
  fi

  page=$((page+1))
  if [ "$page" -gt 20 ]; then
    echo "Стоп — подозрительно много страниц (>20), прерываю на всякий случай."
    break
  fi
done

echo "Склеиваю все страницы в один JSON массив..."
python3 << PYEOF
import json, glob

all_leads = []
for f in sorted(glob.glob("$TMPDIR/page_*.json"), key=lambda x: int(x.split('_')[-1].split('.')[0])):
    try:
        d = json.load(open(f))
        leads = d.get('_embedded', {}).get('leads', [])
        all_leads.extend(leads)
    except Exception as e:
        print(f"Пропуск {f}: {e}")

with open("$OUT", "w", encoding="utf-8") as out:
    json.dump(all_leads, out, ensure_ascii=False, indent=2)

print(f"Итого сделок: {len(all_leads)}")
print(f"Сохранено в: $OUT")
PYEOF

rm -rf "$TMPDIR"
echo "Готово. Скачай файл $OUT (scp/WinSCP/FileZilla) и пришли мне как файл."
