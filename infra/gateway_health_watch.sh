#!/usr/bin/env bash

set -euo pipefail

PRIMARY_URL="http://localhost:8001/payments/service-health"
FALLBACK_URL="http://localhost:8002/payments/service-health"
HEADERS=(-H "Content-Type: application/json")
echo -e "\n"
while true; do
  timestamp=$(date -u "+%Y-%m-%dT%H:%M:%SZ")

  primary_result=$(curl -sS -X GET "${HEADERS[@]}" "$PRIMARY_URL")
  echo "[$timestamp] GET $PRIMARY_URL: $primary_result"
  fallback_result=$(curl -sS -X GET "${HEADERS[@]}" "$FALLBACK_URL")
  echo "[$timestamp] GET $FALLBACK_URL: $fallback_result"
  echo -e "----------------------------------------------------------------"
  
  sleep 5
done
