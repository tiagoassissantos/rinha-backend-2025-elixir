# AGENTS.md — How to Work With This Repo (Agents + Humans)

This project is an Elixir Plug + Bandit HTTP API for the Rinha backend challenge. This guide standardizes how agents (and humans) build, test, and ship changes here.

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
- JSON helpers: `lib/tas_rinhaback3ed/json.ex`
- Mix task (generator): `lib/mix/tasks/gen.module.ex`
- Config: `config/config.exs`, `config/runtime.exs`
- Docker: `Dockerfile`, `docker-compose.yaml`, `infra/nginx.conf`
- Tests: `test/**`

## Run Locally
- Install deps: `mix deps.get`
- Run server: `mix run --no-halt`
- Change port: `PORT=4001 mix run --no-halt`
- Interactive shell: `iex -S mix run --no-halt`
- Health check: `curl -i http://localhost:9999/health`

## Endpoints (current)
- GET `/health`: returns `{ "status": "ok" }`.
- POST `/payments`: validates input and forwards JSON to the external payment gateway. Returns 200 with echo payload on success; returns 400 with validation errors when invalid.
- GET `/payments-summary`: returns a stub summary payload (placeholder for future aggregation).

## External Gateways
- Primary base URL: `http://localhost:8001`
- Fallback base URL: `http://localhost:8002`
- Effective URL is `<base>/payments` (service appends `/payments`).
- Config override: `Application.get_env(:tas_rinhaback_3ed, :payments_base_url, ...)` or pass `base_url:` option to `PaymentGateway.send_payment/2` in tests.
- Fallback behavior: only on pool pressure timeouts (`:pool_timeout`). Other errors bubble up.

## Configuration
- Port (prod): `PORT` env var. Default: `9999`.
- Gateway base URL: `:tas_rinhaback_3ed, :payments_base_url`.
- Logger: console with request_id metadata.

## Development Workflow
- Add routes in `lib/tas_rinhaback3ed/router.ex`.
- Keep request parsing in Plug via `Plug.Parsers` (JSON/urlencoded/multipart configured with Jason).
- Put controller modules under `TasRinhaback3ed.Controllers.*`.
- Use `TasRinhaback3ed.JSON.send_json/3` for consistent responses.
- Avoid starting the HTTP server inside code generators or tests.

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

### Dev Workflow (making code changes)
- Restart apps to pick up changes:
  - `docker compose restart app1 app2`
- View logs while iterating:
  - `docker compose logs -f app1 app2 nginx`
- Tear down the stack:
  - `docker compose down` (add `--volumes` to clean deps/build caches if you mounted them)

Notes
- Nginx maps host `9999 -> nginx:80`, and proxies to `app1:4001` and `app2:4002`.
- From inside containers, use `http://host.docker.internal:8001` (and `8002`) to reach gateway mocks running on the host.

Troubleshooting
- If compose asks to install Hex or fails on deps:
  - Ensure Hex is installed on the host: `mix local.hex --force` (creates `~/.mix/archives/hex-*.ez`).
  - Ensure `./deps` and `./_build` exist by running `mix deps.get` on the host.
  - Recreate containers: `docker compose up --force-recreate` (or `docker compose restart app1 app2`).

### Faster loops (optional)
If your Docker Compose supports it (v2.22+), you can auto-rebuild on file changes:

- Add a `develop.watch` section to each service in `docker-compose.yaml`:

  ```yaml
  services:
    app1:
      develop:
        watch:
          - path: ./lib
            action: sync+restart
          - path: ./config
            action: sync+restart
          - path: ./mix.exs
            action: sync+restart
    app2:
      develop:
        watch:
          - path: ./lib
            action: sync+restart
          - path: ./config
            action: sync+restart
          - path: ./mix.exs
            action: sync+restart
    nginx:
      develop:
        watch:
          - path: ./infra/nginx.conf
            action: sync+restart
  ```

- Then run: `docker compose watch`
  - Compose will sync files and restart the affected services when files change.

### Dev mode in main compose
The main `docker-compose.yaml` runs two dev app instances (`app1`, `app2`) using the Elixir base image with mounted code, fronted by nginx on host port 9999. No separate override file is required.

## Releases (optional)
- Build: `MIX_ENV=prod mix deps.get --only prod && MIX_ENV=prod mix release`
- Start: `PORT=9999 _build/prod/rel/tas_rinhaback_3ed/bin/tas_rinhaback_3ed start`
- Logs/remote: `... bin/tas_rinhaback_3ed log` / `... remote`

---

# Agent Playbook
This section is for automation agents (e.g., Codex CLI) contributing to this repo.

## Goals
- Make safe, minimal, well‑scoped changes.
- Maintain routing, controller, and service boundaries.
- Preserve gateway fallback semantics and JSON response consistency.
- Maintain README.md always updated with changes made by agents.
- Always is necessary update this AGENTS.md

## High‑Value Starting Points
- New HTTP endpoint:
  1) Add route in `lib/tas_rinhaback3ed/router.ex`
  2) Add controller in `lib/tas_rinhaback3ed/controllers/`
  3) Reuse `TasRinhaback3ed.JSON.send_json/3`
  4) Add tests under `test/tas_rinhaback3ed/controllers/`
- Payment flow enhancements:
  - Keep `PaymentGateway.send_payment/2` fallback only on `:pool_timeout`.
  - Surface other errors as `{:error, reason}` and decide response mapping in controller.
- Input validation:
  - Validate UUID v1–v5 and decimal amounts as in `PaymentController`.

## Common Commands
- Install deps: `mix deps.get`
- Format: `mix format`
- Tests: `mix test`
- Run app: `mix run --no-halt`
- Generate module: `mix gen.module TasRinhaback3ed.Domain.Example`

## Definition of Done
- Compiles with no warnings relevant to the change.
- All tests pass locally (`mix test`).
- New code is formatted and documented.
- Public contracts (routes, payloads) updated in README or this file if changed.

## Guardrails
- Don’t change unrelated modules or global behaviors.
- Don’t widen fallback conditions in `PaymentGateway` beyond pool timeouts unless requested.
- Don’t introduce new dependencies without discussion.
- Keep responses stable and documented; use the JSON helper.

## Testing Guidance
- For HTTP client code, use `Bypass` to assert payloads and simulate statuses/timeouts.
- For controller testing, build conns with `Plug.Test.conn/3` and call the router.
- Validate JSON `content-type` header and response body shape.

## Troubleshooting
- 404 responses: check `match _` in `router.ex` and route precedence.
- JSON parsing errors: ensure `content-type: application/json` and valid JSON.
- Gateway timeouts: only `:pool_timeout` triggers fallback; others should bubble up for visibility.
- Port conflicts: set `PORT` or stop other listeners.

## PR/Change Notes (if applicable)
- Summarize the change, impacted endpoints, and any config/env changes.
- Include manual test steps (curl examples) and screenshots/log snippets if helpful.

---

For broader project context and examples, also see `README.md`.
