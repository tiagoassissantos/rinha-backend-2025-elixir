FROM elixir:1.18-alpine

# Set production environment
ENV MIX_ENV=prod \
    LANG=C.UTF-8

WORKDIR /app

# Install build tools and git for deps
RUN apk add --no-cache build-base git

# Install Hex/Rebar and fetch deps
COPY mix.exs mix.lock ./
RUN mix local.hex --force \
 && mix local.rebar --force \
 && mix deps.get --only prod

# Copy app source and compile
COPY config ./config
COPY lib ./lib
RUN mix compile

# Expose the HTTP port (default 9999)
EXPOSE 9999
ENV PORT=9999

# Start the app
CMD ["mix", "run", "--no-halt"]

