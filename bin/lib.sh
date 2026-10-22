#!/usr/bin/env bash
# Shared helpers for bin/* scripts. Source this file, don't execute it.

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENV_FILE="$ROOT/.env"
ENV_EXAMPLE="$ROOT/.env.example"

die() { printf '\033[31m✗\033[0m %s\n' "$*" >&2; exit 1; }
ok() { printf '\033[32m✓\033[0m %s\n' "$*"; }
info() { printf '\033[36m·\033[0m %s\n' "$*"; }
warn() { printf '\033[33m!\033[0m %s\n' "$*" >&2; }

# env_get KEY [FILE] -> prints the value (last occurrence wins)
env_get() {
  local key="$1" file="${2:-$ENV_FILE}" line
  [ -f "$file" ] || return 1
  line="$(grep -E "^${key}=" "$file" | tail -n1)" || return 1
  printf '%s' "${line#*=}"
}

# env_set KEY VALUE -> updates or appends KEY in .env (in place)
env_set() {
  local key="$1" value="$2" file="$ENV_FILE" escaped
  escaped="$(printf '%s' "$value" | sed -e 's/[|&]/\\&/g')"
  if grep -qE "^${key}=" "$file"; then
    sed -i -E "s|^${key}=.*|${key}=${escaped}|" "$file"
  else
    printf '%s=%s\n' "$key" "$value" >>"$file"
  fi
}

# port_busy PORT -> returns 0 when a host listener or a Docker mapping holds it
port_busy() {
  local port="$1"
  if command -v ss >/dev/null 2>&1; then
    if ss -H -ltn "sport = :${port}" 2>/dev/null | grep -q .; then return 0; fi
  elif command -v lsof >/dev/null 2>&1; then
    if lsof -nP -iTCP:"${port}" -sTCP:LISTEN >/dev/null 2>&1; then return 0; fi
  else
    if (exec 3<>"/dev/tcp/127.0.0.1/${port}") 2>/dev/null; then return 0; fi
  fi
  if docker ps --format '{{.Ports}}' 2>/dev/null | grep -q "[:.]${port}->"; then return 0; fi
  return 1
}

# port_owner PORT -> best-effort name of whatever holds the port
port_owner() {
  local port="$1" name
  name="$(docker ps --format '{{.Names}}|{{.Ports}}' 2>/dev/null |
    awk -F'|' -v p=":${port}->" 'index($2, p) { print $1; exit }')"
  if [ -n "$name" ]; then
    printf '%s' "$name"
    return 0
  fi
  if command -v ss >/dev/null 2>&1; then
    ss -H -ltnp "sport = :${port}" 2>/dev/null |
      sed -n 's/.*users:(("\([^"]*\)".*/\1/p' | head -n1 | tr -d '\n'
  fi
  return 0
}

# pick_base -> random free port block base in 20000-29999 (step 100)
pick_base() {
  local attempt base
  for attempt in $(seq 1 50); do
    base=$(((RANDOM % 100 + 200) * 100))
    if ! port_busy "$base" && ! port_busy "$((base + 1))" && ! port_busy "$((base + 10))"; then
      printf '%s' "$base"
      return 0
    fi
  done
  return 1
}

# project_running -> 0 when this compose project has running containers
project_running() {
  (cd "$ROOT" && docker compose ps -q 2>/dev/null | grep -q .)
}

# sanitize_name NAME -> compose-safe project name
sanitize_name() {
  printf '%s' "$1" | tr '[:upper:]' '[:lower:]' |
    sed -E 's/[^a-z0-9_-]+/-/g; s/^-+//; s/-+$//'
}

# require_env -> fails when .env is missing
require_env() {
  [ -f "$ENV_FILE" ] || die "no .env in $ROOT - run ./bin/init first"
}
