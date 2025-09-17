#
# Production Dockerfile for the Elixir application
#

# Stage 1: Builder
# This stage compiles the code and builds the release.
FROM elixir:1.18-alpine AS builder

ENV MIX_ENV=prod

# Install build tools
RUN apk add --no-cache build-base git

WORKDIR /app

# Install Hex and Rebar
RUN mix local.hex --force && mix local.rebar --force

# Copy dependency definitions
COPY mix.exs mix.lock ./

# Copy config files. This is important for releases.
COPY config config

# Install dependencies
RUN mix deps.get --only prod
RUN mix deps.compile

# Copy source code
COPY lib lib
COPY priv priv

# Build the release
RUN mix release

# Stage 2: Runner
# This stage creates the final, small image to run the application.
FROM alpine:latest AS runner

RUN apk add --no-cache openssl ncurses-libs libstdc++ libgcc htop \
  && addgroup -S app \
  && adduser -S -G app app

WORKDIR /app

COPY --chown=app:app --from=builder /app/_build/prod/rel/tas_rinhaback_3ed .

ENV HOME=/app

USER app

CMD ["bin/tas_rinhaback_3ed", "start"]
