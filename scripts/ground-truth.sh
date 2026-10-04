#!/usr/bin/env bash
# Print the correct answer for every test question so Metabot's output can be checked against it.
set -euo pipefail
cd "$(dirname "$0")/.."
docker compose exec -T analytics-db psql -U analytics_admin -d analytics -e < questions/ground-truth.sql
