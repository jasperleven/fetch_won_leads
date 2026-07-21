#!/bin/bash
# Выгрузка расходов Yandex Direct за 14-20.07.2026 по кампаниям,
# по обоим аккаунтам (porg-wzixxjna, porg-echzpycx).
# Reports API асинхронный: сначала может вернуть 201/202 ("отчёт готовится"),
# нужно повторять запрос, пока не придёт 200 с данными.

declare -A TOKENS
TOKENS["porg-wzixxjna"]="y0__wgBEMvy7ekIGPb0QiDq2q7jFzjw1_PrCNstDXECQReIs2fEW1qU_H_bOCPw"
TOKENS["porg-echzpycx"]="y0__wgBEMvy7ekIGKrwQiDY0tPjFziTufnpCCIrXlTQBvs54scQYcOK898VQc5F"

DATE_FROM="2026-07-14"
DATE_TO="2026-07-20"

for LOGIN in "porg-wzixxjna" "porg-echzpycx"; do
  TOKEN="${TOKENS[$LOGIN]}"
  OUT="/root/yandex_spend_${LOGIN}.tsv"
  echo "=== Аккаунт: $LOGIN ==="

  BODY=$(cat << JSON
{
  "params": {
    "SelectionCriteria": {
      "DateFrom": "$DATE_FROM",
      "DateTo": "$DATE_TO"
    },
    "FieldNames": ["Date", "CampaignName", "Cost"],
    "ReportName": "SpendReport_${LOGIN}_${DATE_FROM}_${DATE_TO}",
    "ReportType": "CUSTOM_REPORT",
    "DateRangeType": "CUSTOM_DATE",
    "Format": "TSV",
    "IncludeVAT": "NO",
    "IncludeDiscount": "NO"
  }
}
JSON
)

  attempt=1
  max_attempts=15
  while [ $attempt -le $max_attempts ]; do
    echo "  Попытка $attempt..."
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
      echo "  Готово (200). Сохранено в $OUT"
      break
    elif [ "$http_code" == "201" ] || [ "$http_code" == "202" ]; then
      echo "  Отчёт ещё готовится (HTTP $http_code), жду 5 сек..."
      sleep 5
    else
      echo "  Ошибка HTTP $http_code:"
      cat "$OUT"
      break
    fi
    attempt=$((attempt+1))
  done
  echo ""
done

echo "=== Готово. Файлы: /root/yandex_spend_porg-wzixxjna.tsv и /root/yandex_spend_porg-echzpycx.tsv ==="
echo "=== Суммы расходов по каждому: ==="
for LOGIN in "porg-wzixxjna" "porg-echzpycx"; do
  F="/root/yandex_spend_${LOGIN}.tsv"
  if [ -f "$F" ]; then
    echo "--- $LOGIN ---"
    awk -F'\t' 'NF==3 {sum+=$3; n++} END {print "строк:", n, " сумма Cost (микро-у.е. или у.е., зависит от returnMoneyInMicros):", sum}' "$F"
    echo "первые строки:"
    head -5 "$F"
  fi
done
