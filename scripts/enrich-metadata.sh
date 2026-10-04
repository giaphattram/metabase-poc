#!/usr/bin/env bash
# Apply (or reset) table/field descriptions, semantic types, and glossary terms from metadata/descriptions.json.
# Usage: scripts/enrich-metadata.sh apply | reset
set -euo pipefail

cd "$(dirname "$0")/.."
[ -f .env ] && set -a && . ./.env && set +a

MODE="${1:-}"
[ "$MODE" = "apply" ] || [ "$MODE" = "reset" ] || { echo "usage: $0 apply|reset" >&2; exit 1; }

MB_URL="${MB_URL:-http://localhost:3000}"
EMAIL="${POC_ADMIN_EMAIL:-admin@poc.local}"
PASSWORD="${POC_ADMIN_PASSWORD:-Metabot-poc-1}"
DB_NAME="Analytics (demo)"
SPEC=metadata/descriptions.json
BASELINE=metadata/.baseline.json

SESSION=$(curl -sf -X POST "$MB_URL/api/session" -H 'Content-Type: application/json' \
  -d "$(jq -n --arg u "$EMAIL" --arg p "$PASSWORD" '{username: $u, password: $p}')" | jq -r .id)
api() { curl -sf -H "X-Metabase-Session: $SESSION" -H 'Content-Type: application/json' "$@"; }

DB_ID=$(api "$MB_URL/api/database" | jq -r --arg n "$DB_NAME" '.data[] | select(.name == $n) | .id')
META=$(api "$MB_URL/api/database/$DB_ID/metadata")

clear_glossary() {
  api "$MB_URL/api/glossary" | jq -r '.data[].id' | while read -r id; do
    api -X DELETE "$MB_URL/api/glossary/$id" >/dev/null
  done
}

# [{table, field, id, description, semantic_type}] for every field and table currently in Metabase.
snapshot() {
  jq '[.tables[] | {table: .name, table_id: .id, table_description: .description,
        fields: [.fields[] | {name, id, description, semantic_type}]}]' <<<"$META"
}

if [ "$MODE" = "apply" ]; then
  [ -f "$BASELINE" ] || { snapshot > "$BASELINE"; echo "Saved original metadata to $BASELINE"; }

  jq -c '.tables | to_entries[]' "$SPEC" | while read -r entry; do
    tname=$(jq -r .key <<<"$entry")
    tid=$(jq -r --arg t "$tname" '.tables[] | select(.name == $t) | .id' <<<"$META")
    api -X PUT "$MB_URL/api/table/$tid" -d "$(jq '{description: .value.description}' <<<"$entry")" >/dev/null
    jq -c '.value.fields | to_entries[]' <<<"$entry" | while read -r f; do
      fname=$(jq -r .key <<<"$f")
      fid=$(jq -r --arg t "$tname" --arg f "$fname" '.tables[] | select(.name == $t) | .fields[] | select(.name == $f) | .id' <<<"$META")
      api -X PUT "$MB_URL/api/field/$fid" -d "$(jq '{description: .value.description}
        + (if .value.semantic_type then {semantic_type: .value.semantic_type} else {} end)' <<<"$f")" >/dev/null
    done
    echo "  enriched $tname"
  done

  clear_glossary
  jq -c '.glossary[]' "$SPEC" | while read -r term; do
    api -X POST "$MB_URL/api/glossary" -d "$term" >/dev/null
  done
  echo "Applied descriptions, semantic types, and $(jq '.glossary | length' "$SPEC") glossary terms."
else
  [ -f "$BASELINE" ] || { echo "No $BASELINE: nothing to reset (apply was never run)." >&2; exit 1; }
  jq -c '.[]' "$BASELINE" | while read -r t; do
    api -X PUT "$MB_URL/api/table/$(jq -r .table_id <<<"$t")" -d "$(jq '{description: .table_description}' <<<"$t")" >/dev/null
    jq -c '.fields[]' <<<"$t" | while read -r f; do
      api -X PUT "$MB_URL/api/field/$(jq -r .id <<<"$f")" -d "$(jq '{description, semantic_type}' <<<"$f")" >/dev/null
    done
  done
  clear_glossary
  echo "Restored the original auto-detected metadata and cleared the glossary."
fi
