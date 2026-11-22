#!/bin/bash
# Generate the DataLens key set on first boot (kept on the volume so it survives redeploys), serve it to the other services, then
# hand over to upstream's Postgres entrypoint.
set -euo pipefail

: "${KEYS_TOKEN:?KEYS_TOKEN is not set}"
KEYS_DIR=/var/lib/postgresql/datalens-keys
mkdir -p "$KEYS_DIR"

# One line, literal backslash-n between lines, no trailing newline: the form upstream's compose defaults use.
oneline() { awk '{printf "%s%s", sep, $0; sep="\\n"}'; }

if [ ! -f "$KEYS_DIR/.complete" ]; then
  echo "[datalens-keys] generating key set"
  tmp="$(mktemp -d)"
  for name in auth bi ui; do
    openssl genrsa 2048 2>/dev/null | openssl pkcs8 -topk8 -nocrypt -out "$tmp/$name.pem"
    oneline <"$tmp/$name.pem" >"$KEYS_DIR/${name}_private"
    openssl rsa -in "$tmp/$name.pem" -pubout 2>/dev/null | oneline >"$KEYS_DIR/${name}_public"
  done
  # Temporal's JWKS script reads the public key only; the signer (meta-manager) takes the PKCS#1 private key.
  openssl genrsa -traditional 2048 2>/dev/null >"$tmp/temporal.pem"
  oneline <"$tmp/temporal.pem" >"$KEYS_DIR/temporal_private"
  openssl rsa -in "$tmp/temporal.pem" -pubout 2>/dev/null | oneline >"$KEYS_DIR/temporal_public"
  head -c 32 /dev/urandom | basenc --base64url >"$KEYS_DIR/crypto"
  rm -rf "$tmp"
  touch "$KEYS_DIR/.complete"
fi
chown -R postgres:postgres "$KEYS_DIR"
chmod 0700 "$KEYS_DIR"
chmod 0600 "$KEYS_DIR"/*

gosu postgres python3 /usr/local/bin/railway-keys-server.py "$KEYS_DIR" &

exec /usr/local/bin/docker-entrypoint-wrapper.sh "$@"
