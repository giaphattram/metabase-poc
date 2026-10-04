# Metabot POC

Metabase (open source) with its AI assistant, Metabot, on a demo Postgres of furniture-store orders. Use it to see how Metabot reads the metadata and answer your analytic questions.

## Start

Requires Docker, plus `curl` and `jq` for the helper scripts.

```
cp .env.example .env     # add ONE provider key + model, or enter it later in Admin > AI
docker compose up -d --wait
```

Open http://localhost:3000 and log in as `admin@poc.local` / `Metabot-poc-1`. The first start takes about a minute: it creates the admin, connects the demo database and applies the metadata.

## Try it

Open Metabot with Cmd+E (Ctrl+E on Windows), or use **+ New > AI exploration**. Ask the questions in [questions/ground-truth.sql](questions/ground-truth.sql), for example "What were total sales in AU last month?".

`./scripts/ground-truth.sh` prints the correct answer for each question. Compare Metabot's numbers and filters against it. Wording and SQL may differ; the result should match. Metabot is not deterministic, so ask each question 2-3 times.

## Compare with and without context

The metadata is stored in [metadata/descriptions.json](metadata/descriptions.json). Metabase is not aware of this file at all. When creating the stack from docker-compose, there is a step that runs `./scripts/enrich-metadata.sh apply` to use Metabase API to write metadata from this json files to Metabase.

To remove this metadata from Metabase, we can run `./scripts/enrich-metadata.sh reset`. When we to write the metadata to Metabase again, we can run `./scripts/enrich-metadata.sh apply`. This will allow us to see the quality of the AI Assistance with and without the metadata.


## See what Metabot built

Conversations are stored in Metabase's own database:

```
docker compose exec -T metabase-db psql -U metabase -d metabase -At \
  -c "SELECT id, usage FROM metabot_message WHERE role='assistant' ORDER BY id DESC LIMIT 1;"
```

`usage` shows the model used. The `data` column holds the queries it constructed.

## Notes

- Change model: edit `MB_LLM_METABOT_PROVIDER` in `.env` (format `provider/model`), then `docker compose up -d`. Use a key for that provider.
- The prompts suggested in a new Metabot chat are the questions in `questions/ground-truth.sql` (lines like `-- Q1 "question"`). They are set again on every `docker compose up`, and Regenerate in Admin > AI replaces them.
- The `.env` file holds your API key. Do not share or commit it.
- Ports: Metabase `3000`, demo database `127.0.0.1:5437`.

## Reset

```
docker compose down      # stop, keep data
docker compose down -v   # stop and delete everything
```

## Layout

| Path | Purpose |
|---|---|
| `docker-compose.yml` | Metabase, its app database, the demo database, and a one-shot `setup` service |
| `analytics-db/init/` | Schema and seed data for the demo database |
| `metadata/descriptions.json` | Descriptions, semantic types and glossary sent to Metabase |
| `questions/ground-truth.sql` | Test questions with reference SQL |
| `scripts/` | `bootstrap.sh`, `enrich-metadata.sh`, `seed-prompts.sh`, `ground-truth.sh` |
