#!/bin/sh
# Runs before the official WordPress entrypoint.
#
# Creates the per-stack debug log file named by WP_DEBUG_LOG_FILE (set per env
# file, e.g. wp-content/debug.log.php74) and makes it writable by the web user.
# Works for the default single stack and for the multi-PHP debug compare.
set -e

if [ -n "${WP_DEBUG_LOG_FILE:-}" ]; then
  log="/var/www/html/${WP_DEBUG_LOG_FILE}"
  mkdir -p "$(dirname "$log")"
  : >>"$log"
  chown www-data:www-data "$log" 2>/dev/null || true
fi

exec /usr/local/bin/docker-entrypoint.sh "$@"
