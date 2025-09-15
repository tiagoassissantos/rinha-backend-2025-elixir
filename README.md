Rinha Backend 2025 - 3rd Edition — Plug + Bandit API
================================================

This project is an Elixir Plug + Bandit HTTP API for the Rinha Backend 2025 challenge. This guide standardizes how build, test, and ship changes here.

## Overview
- Language: Elixir (~> 1.18)
- HTTP: Plug + Bandit
- JSON: Jason
- HTTP client: Req (Finch/Mint under the hood)
- Tests: ExUnit, Plug.Test, Bypass (HTTP mocking)
- Default port: 9999 (overridable via `PORT`)

## Repo Map
- App entry/supervision: `lib/tas_rinhaback3ed/application.ex`
- Router: `lib/tas_rinhaback3ed/router.ex`
- Controllers:
  - Health: `lib/tas_rinhaback3ed/controllers/health_controller.ex`
  - Payments: `lib/tas_rinhaback3ed/controllers/payment_controller.ex`
- Services:
  - Payment gateway: `lib/tas_rinhaback3ed/services/payment_gateway.ex`
  - Transactions (DB): `lib/tas_rinhaback3ed/services/transactions.ex`
- JSON helpers: `lib/tas_rinhaback3ed/json.ex`
- Mix task (generator): `lib/mix/tasks/gen.module.ex`
- Config: `config/config.exs`, `config/runtime.exs`
- Docker: `Dockerfile`, `docker-compose.yaml`, `infra/nginx.conf`
- Tests: `test/**`
 - Repo (Ecto): `lib/tas_rinhaback3ed/repo.ex`, migrations in `priv/repo/migrations/`

## Endpoints (current)
- GET `/health`: returns `{ "status": "ok" }`.
- POST `/payments`: validates input and enqueues the payload for asynchronous forwarding to the external payment gateway. Returns 202 with `{ status: "queued", correlationId, received_params }` when accepted; returns 400 with validation errors when invalid. May return 503 `{ error: "queue_full" }` if the in-memory queue is saturated (see PaymentQueue config).
 - GET `/payments-summary`: requires `from` and `to` ISO8601 query params and returns an aggregated summary from the DB when available; otherwise falls back to a stub payload. Responds 400 with `{ error: "invalid_request", errors: [...] }` if params are missing/invalid.

## External Gateways
- Primary base URL: `http://localhost:8001`
- Fallback base URL: `http://localhost:8002`
- Effective URL is `<base>/payments` (service appends `/payments`).
- Config override: `Application.get_env(:tas_rinhaback_3ed, :payments_base_url, ...)` or pass `base_url:` option to `PaymentGateway.send_payment/2` in tests.
- Fallback behavior: only on pool pressure timeouts (`:pool_timeout`). Other errors bubble up.

## Async Queue (PaymentQueue)
- Module: `lib/tas_rinhaback3ed/services/payment_queue.ex`
- Purpose: decouple client request latency from payment forwarding. Bounded concurrency workers drain an in-memory `:queue` and send via `PaymentGateway`.
- Concurrency: configurable via `:tas_rinhaback_3ed, :payment_queue, :max_concurrency` (default: `System.schedulers_online()*2`).
- Back-pressure: optional `:max_queue_size` (default: `:infinity`). When full, controller returns `503 {"error":"queue_full"}`.
- Supervision: started via `TasRinhaback3ed.Application` with a named `Task.Supervisor` (`TasRinhaback3ed.PaymentTaskSup`).
 - Telemetry: emits events for queue monitoring
   - `[:tas, :queue, :enqueue]` (counter)
   - `[:tas, :queue, :drop]` (counter)
   - `[:tas, :queue, :state]` (gauges `queue.length`, `queue.in_flight`)
   - `[:tas, :queue, :wait_time]` (histogram in ms)
   - `[:tas, :queue, :job, :start|:stop|:exception]` (span for job duration)

## Run Locally
- Install deps: `mix deps.get`
- Run server: `mix run --no-halt`
- Change port: `PORT=4001 mix run --no-halt`
- Interactive shell: `iex -S mix run --no-halt`
- Health check: `curl -i http://localhost:9999/health`
- Prometheus: `http://localhost:9090` (scrapes OpenTelemetry Collector)
- Grafana: `http://localhost:3000` (no login; anonymous access enabled)
 - Tempo: `http://localhost:3200` (Tempo HTTP API; view traces in Grafana → Explore → Tempo)

## Configuration
- Port (prod): `PORT` env var. Default: `9999`.
- Gateway base URL: `:tas_rinhaback_3ed, :payments_base_url`.
- Logger: console with request_id metadata.
- Database (Ecto/PostgreSQL): configure via `DATABASE_URL` or `DB_HOST`, `DB_PORT`, `DB_USER`, `DB_PASSWORD`, `DB_NAME`. Optional: `DB_POOL_SIZE`, `DB_SSL`.
  - Repo: `TasRinhaback3ed.Repo` (PostgreSQL)
  - Create DB and run migrations:
    - mix ecto.create
    - mix ecto.migrate

## Tests
- Run all: `mix test`
- Pattern: use `Plug.Test` to build conns and call `TasRinhaback3ed.Router`.
- External HTTP: mock with `Bypass`. See `test/tas_rinhaback3ed/controllers/payment_controller_test.exs` for an end‑to‑end example.
- Async: prefer `use ExUnit.Case, async: true` unless stateful dependencies require sync.

## Code Style
- Format: `mix format` (configured by `.formatter.exs`).
- Module layout: keep `@moduledoc`/`@doc` up to date.
- Naming: group by domain (`Controllers`, `Services`, etc.).
- JSON: only encode maps; set content type via helper.

## Docker & Compose
- Dev (two instances + nginx LB on 9999):
  - `docker compose up`
  - Visit `http://localhost:9999/health`
  - Backends listen on `app1:4001` and `app2:4002` (nginx upstream)
  - Compose mounts host `${HOME}/.mix -> /root/.mix` so Hex is available offline
  - PostgreSQL available as `postgres:5432` (host mapped to `5432`), user `postgres`, password `postgres`, database `tasrinha_dev`.
  - OpenTelemetry Collector (OTLP): `otel-collector:4317` (gRPC), `4318` (HTTP)
  - Prometheus available at `http://localhost:9090` (scrapes `otel-collector:8889`)
  - Grafana available at `http://localhost:3000` (anonymous access; Prometheus + Tempo datasources provisioned)
  - Tempo HTTP API available at `http://localhost:3200` (use Grafana Explore → Tempo to browse traces)

### Dev Workflow (making code changes)
- Restart apps to pick up changes:
  - `docker compose restart app1 app2`
- View logs while iterating:
  - `docker compose logs -f app1 app2 nginx`
  - Tear down the stack:
  - `docker compose down` (add `--volumes` to clean deps/build caches if you mounted them)

## Observability (OpenTelemetry)
- Traces: Application → OpenTelemetry (OTLP) → OpenTelemetry Collector → Grafana Tempo → Grafana (Tempo datasource)
- Metrics: Application → OpenTelemetry (OTLP) → OpenTelemetry Collector (spanmetrics) → Prometheus → Grafana

What’s wired
- HTTP server: traces around requests (Plug.Telemetry → OTel spans)
- Ecto: DB query spans
- Outbound HTTP: Req/Finch client spans
- Trace propagation: outbound HTTP includes W3C `traceparent`/`baggage` headers by default
- Metrics: latency/throughput emitted by collector spanmetrics connector, scraped by Prometheus

How to use
- Bring up stack: `docker compose up -d`
- Hit the app: `curl -i http://localhost:9999/health`
- View traces in Grafana: `http://localhost:3000` (Explore → Tempo; search service `tas_rinhaback_3ed`)
- View metrics in Grafana: `http://localhost:3000` (Explore → Prometheus; try `sum(rate(service_calls_total[1m])) by (http_method, http_route, http_status_code)`)

Notes
- The app exports OTLP to `otel-collector:4317` (gRPC). Override with `OTEL_EXPORTER_OTLP_ENDPOINT` if needed.
- Prometheus scrapes the collector at `otel-collector:8889` (not the app directly).

Outbound tracing details
- Default: `OpentelemetryReq` is attached with `propagate_trace_headers: true` in `lib/tas_rinhaback3ed/http.ex`.
- Per‑call override: pass `propagate_trace_headers: false` in a specific `TasRinhaback3ed.HTTP.request/1` call if you need to suppress header injection.

Notes
- Nginx maps host `9999 -> nginx:80`, and proxies to `app1:4001` and `app2:4002`.
- From inside containers, use `http://host.docker.internal:8001` (and `8002`) to reach gateway mocks running on the host.

Troubleshooting
- If compose asks to install Hex or fails on deps:
  - Ensure Hex is installed on the host: `mix local.hex --force` (creates `~/.mix/archives/hex-*.ez`).
  - Ensure `./deps` and `./_build` exist by running `mix deps.get` on the host.
  - Recreate containers: `docker compose up --force-recreate` (or `docker compose restart app1 app2`).


---

## Generators (Rails-like)
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
