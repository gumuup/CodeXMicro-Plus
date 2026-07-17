#!/usr/bin/env bash
set -euo pipefail

SIGNING_NAME="CodexMicro Local Development"
SIGNING_DIR="${CODEX_MICRO_SIGNING_DIR:-$HOME/Library/Application Support/CodexMicro/Signing}"
KEYCHAIN_PATH="$SIGNING_DIR/CodexMicroSigning-v1.keychain-db"
PASSWORD_FILE="$SIGNING_DIR/keychain-password"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OPENSSL_CONFIG="$ROOT_DIR/script/signing/openssl.cnf"

mkdir -p "$SIGNING_DIR"
chmod 700 "$SIGNING_DIR"

if [[ ! -f "$PASSWORD_FILE" ]]; then
  umask 077
  openssl rand -hex 32 >"$PASSWORD_FILE"
fi
KEYCHAIN_PASSWORD="$(<"$PASSWORD_FILE")"

if [[ ! -f "$KEYCHAIN_PATH" ]]; then
  security create-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN_PATH"
fi

security unlock-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN_PATH"
security set-keychain-settings -lut 21600 "$KEYCHAIN_PATH"

ensure_keychain_is_searchable() {
  local line normalized found=false
  local -a keychains=()
  while IFS= read -r line; do
    normalized="${line#*\"}"
    normalized="${normalized%\"*}"
    [[ -z "$normalized" ]] && continue
    keychains+=("$normalized")
    [[ "$normalized" == "$KEYCHAIN_PATH" ]] && found=true
  done < <(security list-keychains -d user)

  if [[ "$found" == false ]]; then
    security list-keychains -d user -s "${keychains[@]}" "$KEYCHAIN_PATH"
  fi
}

ensure_keychain_is_searchable

has_signing_identity() {
  local identities
  identities="$(security find-identity -p codesigning -v "$KEYCHAIN_PATH")"
  [[ "$identities" == *"\"$SIGNING_NAME\""* ]]
}

if ! has_signing_identity; then
  umask 077
  BOOTSTRAP_DIR="$(mktemp -d "$SIGNING_DIR/bootstrap.XXXXXX")"
  chmod 700 "$BOOTSTRAP_DIR"
  KEY_FILE="$BOOTSTRAP_DIR/key.pem"
  CERT_FILE="$BOOTSTRAP_DIR/cert.pem"
  IDENTITY_FILE="$BOOTSTRAP_DIR/identity.p12"

  cleanup_bootstrap() {
    local path
    for path in "$KEY_FILE" "$CERT_FILE" "$IDENTITY_FILE"; do
      [[ ! -e "$path" ]] || /bin/unlink "$path"
    done
    /bin/rmdir "$BOOTSTRAP_DIR" 2>/dev/null || true
  }
  trap cleanup_bootstrap EXIT

  openssl req \
    -new -newkey rsa:2048 -nodes -x509 -days 3650 \
    -config "$OPENSSL_CONFIG" \
    -keyout "$KEY_FILE" \
    -out "$CERT_FILE"
  openssl pkcs12 \
    -export \
    -inkey "$KEY_FILE" \
    -in "$CERT_FILE" \
    -name "$SIGNING_NAME" \
    -passout "pass:$KEYCHAIN_PASSWORD" \
    -out "$IDENTITY_FILE"

  security import "$IDENTITY_FILE" \
    -k "$KEYCHAIN_PATH" \
    -P "$KEYCHAIN_PASSWORD" \
    -T /usr/bin/codesign >/dev/null
  security set-key-partition-list \
    -S apple-tool:,apple:,codesign: \
    -s \
    -k "$KEYCHAIN_PASSWORD" \
    "$KEYCHAIN_PATH" >/dev/null
  security add-trusted-cert \
    -r trustRoot \
    -p codeSign \
    -k "$KEYCHAIN_PATH" \
    "$CERT_FILE"
fi

if ! has_signing_identity; then
  echo "Unable to create a valid local signing identity: $SIGNING_NAME" >&2
  exit 1
fi
