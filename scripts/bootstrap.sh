#!/usr/bin/env bash
# Create the Metabase admin, connect the demo analytics DB (read-only role), and wait for the schema sync.
set -euo pipefail

cd "$(dirname "$0")/.."
[ -f .env ] && set -a && . ./.env && set +a

MB_URL="${MB_URL:-http://localhost:3000}"
EMAIL="${POC_ADMIN_EMAIL:-admin@poc.local}"
PASSWORD="${POC_ADMIN_PASSWORD:-Metabot-poc-1}"
DB_NAME="Analytics (demo)"

echo "Waiting for Metabase at $MB_URL ..."
until [ "$(curl -s -o /dev/null -w '%{http_code}' "$MB_URL/api/health")" = "200" ]; do sleep 3; done

SETUP_TOKEN=$(curl -s "$MB_URL/api/session/properties" | jq -r '."setup-token" // empty')
if [ -n "$SETUP_TOKEN" ]; then
  echo "Running first-time setup ..."
  # A new instance makes any old baseline stale (different table/field IDs), and would make setup skip enrichment.
  rm -f metadata/.baseline.json
  curl -sf -X POST "$MB_URL/api/setup" -H 'Content-Type: application/json' -d "$(jq -n \
    --arg token "$SETUP_TOKEN" --arg email "$EMAIL" --arg pw "$PASSWORD" '{
      token: $token,
      user: {first_name: "POC", last_name: "Admin", email: $email, password: $pw, site_name: "Metabot POC"},
      prefs: {site_name: "Metabot POC", site_locale: "en", allow_tracking: false}
    }')" >/dev/null
fi

SESSION=$(curl -sf -X POST "$MB_URL/api/session" -H 'Content-Type: application/json' \
  -d "$(jq -n --arg u "$EMAIL" --arg p "$PASSWORD" '{username: $u, password: $p}')" | jq -r .id)
AUTH=(-H "X-Metabase-Session: $SESSION" -H 'Content-Type: application/json')

DB_ID=$(curl -sf "${AUTH[@]}" "$MB_URL/api/database" | jq -r --arg n "$DB_NAME" '.data[] | select(.name == $n) | .id' | head -n1)
if [ -z "$DB_ID" ]; then
  echo "Connecting $DB_NAME ..."
  DB_ID=$(curl -sf -X POST "$MB_URL/api/database" "${AUTH[@]}" -d "$(jq -n --arg n "$DB_NAME" '{
      engine: "postgres", name: $n, is_full_sync: true, is_on_demand: false,
      details: {host: "analytics-db", port: 5432, dbname: "analytics", user: "metabase_ro",
                password: "metabase_ro", ssl: false}
    }')" | jq -r .id)
fi

echo "Waiting for schema sync of database $DB_ID ..."
until [ "$(curl -sf "${AUTH[@]}" "$MB_URL/api/database/$DB_ID/metadata" | jq '[.tables[]] | length')" -ge 5 ]; do sleep 3; done

echo "Done. Open $MB_URL and log in as $EMAIL"
