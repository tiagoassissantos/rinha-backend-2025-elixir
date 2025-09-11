TasRinhaback 3rd Edition — Plug + Bandit API
================================================

This repository is an Elixir application scaffolded to serve a REST API using Plug and Bandit.

What was done in this change
- Initialized a Mix OTP app with supervisor (`mix new . --sup`).
- Added dependencies: `plug`, `bandit`, and `jason` in `mix.exs`.
- Wired a supervision tree to start Bandit HTTP server in `lib/tas_rinhaback3ed/application.ex`.
- Added a Plug router with a basic health endpoint in `lib/tas_rinhaback3ed_web/router.ex`.
- Added configs in `config/config.exs` and `config/runtime.exs` (PORT support).

Fixes
- Bandit child spec now uses top-level `:port` instead of `options: [port: ...]` to avoid `Unsupported key(s) in top level config: [:options]` error.
- Custom generator `mix gen.module` no longer starts the application (prevents server boot during codegen).

Project layout
- `lib/tas_rinhaback3ed/application.ex`: Starts Bandit with `TasRinhaback3ed.Router`.
- `lib/tas_rinhaback3ed_web/router.ex`: Plug.Router with `/health` and 404 handling.
- `lib/tas_rinhaback3ed_web/controllers/health_controller.ex`: Example controller wiring for `/health`.
- `lib/tas_rinhaback3ed_web/json.ex`: Helper for JSON responses.
- `mix.exs`: Declares dependencies and application entry.
- `config/config.exs`: Logger and JSON library config.
- `config/runtime.exs`: Reads `PORT` env var for HTTP port in `:prod`.

Dependencies
- Plug: request routing, parsers, etc.
- Bandit: HTTP server.
- Jason: JSON encoding/decoding.
- Ecto SQL + Postgrex: Database access (PostgreSQL).
 - Ecto SQL + Postgrex: Database access (PostgreSQL).

Run locally
1) Install dependencies (requires network):
   mix deps.get

2) Run the server:
   mix run --no-halt

   Or with a custom port:
   PORT=4001 mix run --no-halt

3) Test the health endpoint:
   curl -i http://localhost:9999/health

   Expected response:
   HTTP/1.1 200 OK
   {"status":"ok"}

Developer shell (IEx)
- Start with IEx so you can inspect the app while it runs:
  iex -S mix run --no-halt

Stop the application
- If started with `mix run --no-halt` or `iex -S mix run --no-halt`:
  - Press Ctrl+C, then Ctrl+C again to shut down the VM.
  - Or run `System.halt()` / `:init.stop()` in IEx.
- If running as a release:
  - Stop with `_build/prod/rel/tas_rinhaback_3ed/bin/tas_rinhaback_3ed stop`.

Run tests
- Execute the test suite:
  mix test

Docker & Compose
- Run (two instances + nginx LB on 9999) + Prometheus (9090) + Grafana (3000):
  docker compose up
  - App (via nginx LB): http://localhost:9999/health
  - Prometheus UI: http://localhost:9090
  - Grafana UI: http://localhost:3000 (login admin/admin)
  Nginx proxies to app1:4001 and app2:4002. Prometheus scrapes app1/app2 /metrics directly.
  PostgreSQL service available on localhost:5432 (container name `postgres`).

- After code changes:
  docker compose restart app1 app2

- Logs:
  docker compose logs -f app1 app2 nginx

- Details and variations are in `AGENTS.md` → Docker & Compose.

Observability in Compose
- Prometheus uses `infra/prometheus.yml` and scrapes `app1:4001` and `app2:4002` at `/metrics`.
- Grafana is pre-provisioned with:
  - Prometheus datasource at `http://prometheus:9090`
  - Dashboard from `infra/grafana/dashboards/tas.json` (Panels: HTTP RPS/latency/errors, queue length/in-flight, rates, durations, wait time)

Offline-friendly setup
- Ensure Hex is installed on the host: `mix local.hex --force`
- Ensure deps are present on the host: `mix deps.get`
- Compose mounts your host `~/.mix` into the containers so Mix can load the Hex SCM without downloading it.

Troubleshooting
- If containers prompt to install Hex or fail to fetch deps:
  - Run `mix deps.get` on the host to populate `./deps` and `./_build`.
  - Then `docker compose restart app1 app2` (or `docker compose up --force-recreate`).

Production (optional)
- Build a release:
  MIX_ENV=prod mix deps.get --only prod
  MIX_ENV=prod mix release

- Start the release (default port 9999 unless PORT is set):
  PORT=9999 _build/prod/rel/tas_rinhaback_3ed/bin/tas_rinhaback_3ed start

- View logs / attach console:
  _build/prod/rel/tas_rinhaback_3ed/bin/tas_rinhaback_3ed log
  _build/prod/rel/tas_rinhaback_3ed/bin/tas_rinhaback_3ed remote

Endpoints
- GET `/health`: `{ "status": "ok" }`.
- POST `/payments`: validates input and enqueues asynchronously; responds `202` with `{ status: "queued", correlationId, received_params }`. May return `400` on validation errors or `503` when the in-memory queue is full.
- GET `/payments-summary?from=<ISO8601>&to=<ISO8601>`: requires `from` and `to` query params (ISO8601 datetime). Returns an aggregated summary from the DB when available; otherwise falls back to a stub payload. Returns `400` with `{ error: "invalid_request", errors: [...] }` if missing/invalid.
 - GET `/metrics`: Prometheus metrics (via PromEx). Suitable for scraping by Prometheus.

Notes
- The project is intentionally minimal (Plug + Bandit only). Modules live under `lib/tas_rinhaback3ed/`.
- For structured JSON parsing, `Plug.Parsers` is configured to use Jason.
- Consider adding environments (dev/test/prod) specific configuration as needs grow.

Observability
- Metrics exporter: PromEx at `/metrics` (text exposition format)
- HTTP timings: via PromEx PlugRouter plugin on `[:tas,:http]` events; exported as `tas_rinhaback_3ed_prom_ex_plug_router_http_*` (duration histogram in ms, requests_total)
- Queue metrics: exported as `tas_rinhaback_3ed_prom_ex_queue_*` (e.g., `*_enqueued_total`, `*_dropped_total`, `*_length`, `*_in_flight`, `*_job_duration_milliseconds_*`, `*_wait_time_milliseconds_*`)
- DB metrics: via PromEx Ecto plugin (query timings)
- VM metrics: via PromEx BEAM plugin (schedulers, memory, run queue)

Prometheus scrape example:
  - job_name: tas_rinhaback_3ed
    static_configs:
      - targets: ['localhost:9999']
    metrics_path: /metrics

Quick start: Prometheus + Grafana (Docker)
- Prometheus (port 9090):
  docker run --rm -p 9090:9090 \
    -v $(pwd)/infra/prometheus.yml:/etc/prometheus/prometheus.yml \
    prom/prometheus

- Grafana (port 3000):
  docker run --rm -p 3000:3000 grafana/grafana
  # In Grafana UI: add a Prometheus datasource at http://host.docker.internal:9090
  # Import dashboard from file: infra/grafana-dashboard.json
 
Database (Ecto)
- Repo: `TasRinhaback3ed.Repo` (PostgreSQL)
- Configure via `DATABASE_URL` or `DB_HOST`, `DB_PORT`, `DB_USER`, `DB_PASSWORD`, `DB_NAME` (plus optional `DB_POOL_SIZE`, `DB_SSL`).
- Create DB and run migrations:
  mix ecto.create
  mix ecto.migrate

Generators (Rails-like)
- Added a custom Mix task `mix gen.module` to generate a module and its test file.

Usage
- Generate a module with test (default):
  mix gen.module TasRinhaback3ed.Users

- Generate a module without test:
  mix gen.module TasRinhaback3ed.Domain.Accounts --no-test

What it creates
- `lib/.../users.ex` or `lib/.../accounts.ex` with a minimal module skeleton.
- `test/.../users_test.exs` with a placeholder ExUnit test (unless `--no-test`).

Notes on generators
- Phoenix offers rich generators (`mix phx.gen.*`) if you use Phoenix.
- For non-Phoenix apps, custom Mix tasks like `mix gen.module` are the idiomatic way to scaffold files.
