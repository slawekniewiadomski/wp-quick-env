#!/usr/bin/env bash
# Shared helpers for bin/* scripts. Source this file, don't execute it.

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENV_FILE="$ROOT/.env"
ENV_EXAMPLE="$ROOT/.env.example"

die() { printf '\033[31m✗\033[0m %s\n' "$*" >&2; exit 1; }
ok() { printf '\033[32m✓\033[0m %s\n' "$*"; }
info() { printf '\033[36m·\033[0m %s\n' "$*"; }
warn() { printf '\033[33m!\033[0m %s\n' "$*" >&2; }

# env_get KEY [FILE] -> prints the value (last occurrence wins, quotes stripped)
env_get() {
  local key="$1" file="${2:-$ENV_FILE}" line value
  [ -f "$file" ] || return 1
  line="$(grep -E "^${key}=" "$file" | tail -n1)" || return 1
  value="${line#*=}"
  case "$value" in
    \"*\") value="${value#\"}"; value="${value%\"}" ;;
    \'*\') value="${value#\'}"; value="${value%\'}" ;;
  esac
  printf '%s' "$value"
}

# env_set KEY VALUE -> updates or appends KEY in .env (in place)
env_set() {
  local key="$1" value="$2" file="$ENV_FILE" escaped
  escaped="$(printf '%s' "$value" | sed -e 's/\\/\\\\/g' -e 's/[|&]/\\&/g')"
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

# --- interactive helpers ----------------------------------------------------

# is_interactive -> prompts are allowed (TTY and --yes not given). Prompts go
# to stderr and the answer comes back on stdout, so check stderr, not stdout:
# `value="$(ask ...)"` runs in a command substitution.
is_interactive() {
  [ "${ASSUME_YES:-0}" -eq 0 ] && [ -t 0 ] && [ -t 2 ]
}

# ask CURRENT LABEL DEFAULT [VALIDATOR] -> prints CURRENT when set, otherwise
# prompts (TTY) or the default. VALIDATOR is a function taking the answer.
ask() {
  local current="$1" label="$2" default="$3" validator="${4:-}" answer
  if [ -n "$current" ]; then
    printf '%s' "$current"
    return 0
  fi
  if ! is_interactive; then
    printf '%s' "$default"
    return 0
  fi
  while :; do
    printf '  %s [%s]: ' "$label" "$default" >&2
    IFS= read -r answer || answer=""
    answer="${answer:-$default}"
    if [ -z "$validator" ] || "$validator" "$answer"; then
      printf '%s' "$answer"
      return 0
    fi
    warn "invalid value: $answer"
  done
}

# ask_secret CURRENT LABEL DEFAULT -> like ask, but input is not echoed
ask_secret() {
  local current="$1" label="$2" default="$3" answer
  if [ -n "$current" ]; then
    printf '%s' "$current"
    return 0
  fi
  if ! is_interactive; then
    printf '%s' "$default"
    return 0
  fi
  printf '  %s [%s]: ' "$label" "$default" >&2
  IFS= read -rs answer || answer=""
  printf '\n' >&2
  printf '%s' "${answer:-$default}"
}

# confirm LABEL [DEFAULT y|n] -> 0 for yes, 1 for no
confirm() {
  local label="$1" default="${2:-y}" answer lower
  if ! is_interactive; then
    [ "$default" = "y" ]
    return
  fi
  while :; do
    printf '  %s [%s]: ' "$label" "$default" >&2
    IFS= read -r answer || answer=""
    answer="${answer:-$default}"
    lower="$(printf '%s' "$answer" | tr '[:upper:]' '[:lower:]')"
    case "$lower" in
      y | yes) return 0 ;;
      n | no) return 1 ;;
      *) warn "please answer y or n" ;;
    esac
  done
}

# --- PHP version matrix -----------------------------------------------------
#
# 8.3+ comes from the official WordPress image, which tracks the latest PHP
# patch release. Older branches have no official tag any more, so they are
# built from packages.sury.org (Ondrej Sury), which keeps rebuilding EOL
# branches with security fixes.
OFFICIAL_PHP_BRANCHES="8.3 8.4 8.5"
SURY_PHP_BRANCHES="5.6 7.0 7.1 7.2 7.3 7.4 8.0 8.1 8.2"
PHP_BRANCHES="$SURY_PHP_BRANCHES $OFFICIAL_PHP_BRANCHES"

# valid_php_branch VERSION -> 0 if valid patched PHP branch
valid_php_branch() {
  case " $PHP_BRANCHES " in
    *" $1 "*) return 0 ;;
    *) return 1 ;;
  esac
}

# valid_text VALUE -> 0 if non-empty
valid_text() { [ -n "$1" ]; }

# valid_wp_version VERSION -> 0 for X.Y or X.Y.Z
valid_wp_version() { [[ "$1" =~ ^[0-9]+\.[0-9]+(\.[0-9]+)?$ ]]; }

# valid_identifier VALUE -> 0 for [A-Za-z0-9_]+
valid_identifier() { [[ "$1" =~ ^[A-Za-z0-9_]+$ ]]; }

# valid_email VALUE -> 0 for a basic email shape
valid_email() { [[ "$1" =~ ^[^@[:space:]]+@[^@[:space:]]+\.[^@[:space:]]+$ ]]; }

# valid_port PORT -> 0 if valid port number (1024-65535)
valid_port() {
  [[ "$1" =~ ^[0-9]+$ ]] || return 1
  [ "$1" -ge 1024 ] && [ "$1" -le 65535 ]
}

# valid_image_version VERSION -> 0 if valid image version format
valid_image_version() { [[ "$1" =~ ^[0-9]+(\.[0-9]+)*$ ]]; }

# valid_db_version VERSION -> 0 if valid DB version format
valid_db_version() { [[ "$1" =~ ^[0-9]+\.[0-9]+(\.[0-9]+)?$ ]]; }

# php_source_for VERSION -> official|sury, fails for an unknown branch
php_source_for() {
  case "$1" in
    8.3 | 8.4 | 8.5) printf 'official' ;;
    5.6 | 7.0 | 7.1 | 7.2 | 7.3 | 7.4 | 8.0 | 8.1 | 8.2) printf 'sury' ;;
    *) return 1 ;;
  esac
}

# php_source_label SOURCE -> human-readable description
php_source_label() {
  case "$1" in
    official) printf 'official WordPress image' ;;
    sury) printf 'ondrej/sury backports' ;;
    *) printf 'unknown' ;;
  esac
}

# version_lt A B -> 0 when A < B (major.minor[.patch])
version_lt() {
  awk -v a="$1" -v b="$2" 'BEGIN {
    na = split(a, pa, "."); nb = split(b, pb, ".")
    for (i = 1; i <= 3; i++) {
      va = (i <= na && pa[i] != "") ? pa[i] + 0 : 0
      vb = (i <= nb && pb[i] != "") ? pb[i] + 0 : 0
      if (va < vb) exit 0
      if (va > vb) exit 1
    }
    exit 1
  }'
}

# composer_for_php VERSION -> newest Composer line that runs on that PHP
composer_for_php() {
  if version_lt "$1" "7.2"; then
    printf '2.2'
  else
    printf '2'
  fi
}

# composer_runs_on_php COMPOSER_VERSION PHP_VERSION -> 0 when compatible.
# Composer 2.3+ needs PHP 7.2.5; "2" means the latest 2.x, so it counts as 2.3+.
composer_runs_on_php() {
  local composer="$1" php="$2"
  if ! version_lt "$php" "7.2"; then
    return 0
  fi
  case "$composer" in
    1 | 1.* | 2.0 | 2.0.* | 2.1 | 2.1.* | 2.2 | 2.2.*) return 0 ;;
    *) return 1 ;;
  esac
}

# wp_min_php WP_VERSION -> minimum PHP branch for that WordPress release
wp_min_php() {
  if version_lt "$1" "6.4"; then
    printf '5.6'
  elif version_lt "$1" "6.7"; then
    printf '7.0'
  else
    printf '7.2'
  fi
}
