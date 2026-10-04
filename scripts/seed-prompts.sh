#!/usr/bin/env bash
# Replace Metabot's suggested prompts with the questions in questions/ground-truth.sql.
# Runs in the setup container: needs psql with PG* env vars pointing at Metabase's app database.
set -euo pipefail

cd "$(dirname "$0")/.."

MB_URL="${MB_URL:-http://localhost:3000}"
EMAIL="${POC_ADMIN_EMAIL:-admin@poc.local}"
PASSWORD="${POC_ADMIN_PASSWORD:-Metabot-poc-1}"
DB_NAME="Analytics (demo)"
MODEL_NAME="Sales Orders (POC)"

SESSION=$(curl -sf -X POST "$MB_URL/api/session" -H 'Content-Type: application/json' \
  -d "$(jq -n --arg u "$EMAIL" --arg p "$PASSWORD" '{username: $u, password: $p}')" | jq -r .id)
api() { curl -sf -H "X-Metabase-Session: $SESSION" -H 'Content-Type: application/json' "$@"; }

# Metabase only attaches suggested prompts to a saved model or metric, so create a pass-through model.
MODEL_ID=$(psql -At -v name="$MODEL_NAME" <<'SQL'
SELECT id FROM report_card WHERE type = 'model' AND name = :'name' AND NOT archived LIMIT 1;
SQL
)
if [ -z "$MODEL_ID" ]; then
  DB_ID=$(api "$MB_URL/api/database" | jq -r --arg n "$DB_NAME" '.data[] | select(.name == $n) | .id')
  TABLE_ID=$(api "$MB_URL/api/database/$DB_ID/metadata" | jq '[.tables[] | select(.name == "fact_saleorder")][0].id')
  MODEL_ID=$(api -X POST "$MB_URL/api/card" -d "$(jq -n --arg n "$MODEL_NAME" --argjson db "$DB_ID" --argjson t "$TABLE_ID" '{
      name: $n, type: "model", display: "table", visualization_settings: {},
      description: "One row per order, cart or canceled order (same rows as the fact_saleorder table). Filter order_state = '\''complete'\'' for real sales.",
      dataset_query: {database: $db, type: "query", query: {"source-table": $t}}
    }')" | jq -r .id)
fi

QUESTIONS=$(sed -n 's/^-- Q[0-9]* "\(.*\)"$/\1/p' questions/ground-truth.sql)
[ -n "$QUESTIONS" ] || { echo "No questions found in questions/ground-truth.sql" >&2; exit 1; }

for metabot_id in $(api "$MB_URL/api/metabot/metabot" | jq -r '.items // . | .[]? | .id'); do
  api -X DELETE "$MB_URL/api/metabot/metabot/$metabot_id/prompt-suggestions" >/dev/null
  while IFS= read -r question; do
    psql -q -v ON_ERROR_STOP=1 -v prompt="$question" -v model_id="$MODEL_ID" -v metabot_id="$metabot_id" <<'SQL'
INSERT INTO metabot_prompt (model, card_id, entity_id, prompt, metabot_id)
VALUES ('model', :model_id, substr(md5(random()::text || :'prompt' || :metabot_id), 1, 21), :'prompt', :metabot_id);
SQL
  done <<<"$QUESTIONS"
done

echo "Set $(wc -l <<<"$QUESTIONS" | tr -d ' ') suggested prompts from questions/ground-truth.sql."
