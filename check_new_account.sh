#!/bin/bash
TOKEN="y0__wgBEMvy7ekIGKrwQiDv1bHhF2Pf_oEpVAQnsRobFmWZ5efverbA"

echo "=== Проверка: чей это токен (какой Login) ==="
curl -s -X POST "https://api.direct.yandex.com/json/v5/campaigns" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Accept-Language: ru" \
  -H "Content-Type: application/json" \
  -d '{
    "method": "get",
    "params": {
      "SelectionCriteria": {},
      "FieldNames": ["Id", "Name"]
    }
  }' | python3 -m json.tool

echo ""
echo "=== Расход по кампаниям за 14-20.07.2026 ==="
BODY='{
  "params": {
    "SelectionCriteria": {
      "DateFrom": "2026-07-14",
      "DateTo": "2026-07-20"
    },
    "FieldNames": ["Date", "CampaignName", "Cost"],
    "ReportName": "CheckReport_porg-3bbl2hmg",
    "ReportType": "CUSTOM_REPORT",
    "DateRangeType": "CUSTOM_DATE",
    "Format": "TSV",
    "IncludeVAT": "NO",
    "IncludeDiscount": "NO"
  }
}'

OUT="/root/yandex_spend_porg-3bbl2hmg.tsv"
attempt=1
while [ $attempt -le 15 ]; do
  http_code=$(curl -s -o "$OUT" -w "%{http_code}" \
    -X POST "https://api.direct.yandex.com/json/v5/reports" \
    -H "Authorization: Bearer $TOKEN" \
    -H "Accept-Language: ru" \
    -H "processingMode: auto" \
    -H "returnMoneyInMicros: false" \
    -H "skipReportHeader: true" \
    -H "skipReportSummary: true" \
    -H "Content-Type: application/json" \
    -d "$BODY")
  if [ "$http_code" == "200" ]; then
    echo "Готово."
    break
  elif [ "$http_code" == "201" ] || [ "$http_code" == "202" ]; then
    echo "Отчёт готовится (HTTP $http_code), жду 5 сек... (попытка $attempt)"
    sleep 5
  else
    echo "Ошибка HTTP $http_code:"
    cat "$OUT"
    break
  fi
  attempt=$((attempt+1))
done

echo ""
echo "Содержимое отчёта:"
cat "$OUT"
echo ""
echo "Сумма Cost:"
awk -F'\t' 'NF==3 {sum+=$3} END {print sum}' "$OUT"
