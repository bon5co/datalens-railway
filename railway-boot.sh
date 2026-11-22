#!/bin/sh
# Fetch this service's share of the generated key set from the db service, export each as the env var upstream expects, then run
# the upstream entrypoint. KEYS_MAP is baked per image as "<key name>=<ENV VAR> ...".
set -eu

: "${KEYS_HOST:?KEYS_HOST is not set}"
: "${KEYS_TOKEN:?KEYS_TOKEN is not set}"

fetch() {
  if command -v curl >/dev/null 2>&1; then
    curl -fsS --max-time 5 "$1"
  elif command -v wget >/dev/null 2>&1; then
    wget -qO- -T 5 "$1"
  else
    python3 -c 'import sys,urllib.request;sys.stdout.write(urllib.request.urlopen(sys.argv[1],timeout=5).read().decode())' "$1"
  fi
}

get_key() {
  tries=0
  while :; do
    if out=$(fetch "http://${KEYS_HOST}:${KEYS_PORT:-8000}/${KEYS_TOKEN}/$1" 2>/dev/null) && [ -n "$out" ]; then
      printf '%s' "$out"
      return 0
    fi
    tries=$((tries + 1))
    if [ "$tries" -ge 180 ]; then
      echo "[railway-boot] key '$1' unreachable at ${KEYS_HOST} after 15 minutes" >&2
      return 1
    fi
    sleep 5
  done
}

for pair in ${KEYS_MAP:-}; do
  name="${pair%%=*}"
  var="${pair#*=}"
  value="$(get_key "$name")"
  export "$var=$value"
  echo "[railway-boot] $var loaded from key '$name'" >&2
done

exec "$@"
