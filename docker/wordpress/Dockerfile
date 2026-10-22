# syntax=docker/dockerfile:1

# Args used inside FROM must be declared before the first FROM (global scope).
ARG COMPOSER_VERSION=2
ARG WP_VERSION=7.1
ARG PHP_VERSION=8.4

# Composer binary, copied out of the official image below.
FROM composer:${COMPOSER_VERSION} AS composer-bin

FROM wordpress:${WP_VERSION}-php${PHP_VERSION}-apache

# --- wp-cli -----------------------------------------------------------------
# Pinned phar with checksum verification, so `wp` lives in the same container
# as WordPress and reuses the generated wp-config.php.
ARG WP_CLI_VERSION=2.12.0
RUN set -eux; \
    apt-get update; \
    apt-get install -y --no-install-recommends ca-certificates curl default-mysql-client git less unzip zip; \
    curl -fsSL -o /tmp/wp-cli.phar \
      "https://github.com/wp-cli/wp-cli/releases/download/v${WP_CLI_VERSION}/wp-cli-${WP_CLI_VERSION}.phar"; \
    curl -fsSL -o /tmp/wp-cli.phar.sha512 \
      "https://github.com/wp-cli/wp-cli/releases/download/v${WP_CLI_VERSION}/wp-cli-${WP_CLI_VERSION}.phar.sha512"; \
    expected="$(awk '{print $1}' /tmp/wp-cli.phar.sha512)"; \
    printf '%s  %s\n' "$expected" /tmp/wp-cli.phar | sha512sum -c -; \
    install -m 0755 /tmp/wp-cli.phar /usr/local/bin/wp; \
    rm -rf /tmp/wp-cli.phar /tmp/wp-cli.phar.sha512 /var/lib/apt/lists/*

COPY --from=composer-bin /usr/bin/composer /usr/local/bin/composer

# --- host user mapping ------------------------------------------------------
# Remap www-data to the host user so bind-mounted wp-content stays yours.
ARG HOST_UID=1000
ARG HOST_GID=1000
RUN set -eux; \
    if getent group "${HOST_GID}" >/dev/null 2>&1; then \
      groupmod -o -g "${HOST_GID}" www-data; \
    else \
      groupmod -g "${HOST_GID}" www-data; \
    fi; \
    if getent passwd "${HOST_UID}" >/dev/null 2>&1; then \
      usermod -o -u "${HOST_UID}" www-data; \
    else \
      usermod -u "${HOST_UID}" www-data; \
    fi

ENV WP_CLI_CACHE_DIR=/tmp/wp-cli-cache
