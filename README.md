# wp-quick-env

Bare, configurable WordPress development environment: Docker Compose + Task.

WordPress, MariaDB, phpMyAdmin, wp-cli, Composer and Node in one stack, with every version and port controlled from a single `.env`. `wp-content/themes` and `wp-content/plugins` ship empty, so you clone a theme, drop in plugins and go.

## Requirements

- Docker + Docker Compose v2
- [Task](https://taskfile.dev) (optional — every task maps to a `bin/` script or a plain `docker compose` command)

## Quickstart

```bash
task init           # asks for versions, ports and credentials, writes .env
task start          # build + start (or: docker compose up -d --build)
task install        # creates tables + admin user from .env
```

`task init` prompts for the project name, WordPress/PHP/tooling versions, the random or fixed port block, database credentials and the WordPress admin. Press Enter to accept a default. In CI, or without a terminal, it skips the prompts; `task init --yes` does the same explicitly, `--force` regenerates an existing `.env` without asking.

Then open the WordPress URL printed by `task init` (`task ports` shows it again). Bundled themes are copied from the image on first boot, so the front end renders right away; run `task seed` only if you emptied `wp-content/themes`.

### Add your theme

```bash
task theme:clone -- https://github.com/your/theme my-theme
```

This clones your theme into `wp-content/themes/my-theme` and sets `THEME_DIR` in `.env` for Node/Composer tasks.

### New project from this template

```bash
gh repo clone <you>/wp-quick-env my-new-site -- --depth 1
cd my-new-site
task init
task start && task install
```

`task init` proposes the directory name as `COMPOSE_PROJECT_NAME`, so every checkout becomes an independent stack (containers, volumes and ports included). Two or three clones can run at the same time.

## Safe PHP Versions

Only PHP branches that receive security patches are accepted:

| PHP Version | Source | Image |
|-------------|--------|-------|
| 8.3, 8.4, 8.5 | Official | `wordpress:<WP_VERSION>-php<PHP_VERSION>-apache` (tracks upstream patch releases) |
| 5.6, 7.0–7.4, 8.0–8.2 | Ondřej Surý (packages.sury.org) | Debian bookworm + patched EOL branches |

`PHP_SOURCE` (`official` or `sury`) selects the Dockerfile. `task init` writes it from `PHP_VERSION`; `task check` refuses a mismatch or a branch that neither source publishes.

**Legacy branches need matching tooling:**
- Below PHP 7.2, `task init` defaults `COMPOSER_VERSION` to `2.2` (Composer 2.3+ needs PHP 7.2.5+)
- WordPress must support the chosen PHP — `task check` warns when `WP_VERSION` and `PHP_VERSION` are incompatible

## Commands

| Task | What it does |
|---|---|
| `task init` | Create `.env` (same as `./bin/init`) |
| `task check` | Validate image tags and port availability |
| `task versions` | Print the resolved version matrix |
| `task start` / `stop` / `restart` | Manage the stack |
| `task ps` / `logs` / `shell` | Inspect / enter containers |
| `task wp -- <args>` | wp-cli, e.g. `task wp -- plugin list` |
| `task install` | `wp core install` from `.env` (idempotent) |
| `task seed` | Restore bundled WP themes if `wp-content/themes` was emptied |
| `task ports` / `ports:new` | Show ports / allocate a new random block |
| `task db:export` / `db:import FILE=…` / `db:shell` | Database round-trip |
| `task theme:clone -- <git-url> [name]` | Clone theme, set `THEME_DIR` |
| `task node:install` / `node:dev` / `node:build` | npm in `THEME_DIR` |
| `task composer:install` / `composer:update` | Composer in `THEME_DIR` |
| `task clear-cache`, `task fix-perms`, `task reset` | Maintenance |

Everything also works without Task:

```bash
docker compose up -d --build
docker compose exec -T -u www-data wordpress wp plugin list
./bin/wp core version
```

## Configuration (`.env`)

Never commit `.env`; `.env.example` is the template and documents every key.

### Versions

| Variable | Effect |
|---|---|
| `WP_VERSION` + `PHP_VERSION` | WordPress and PHP branch. Validated by `task check`. |
| `PHP_SOURCE` | `official` or `sury`; derived from `PHP_VERSION` by `task init` |
| `PHP_VERSION` | Also the PHP that Composer runs on (see below) |
| `NODE_VERSION` | `node:<NODE_VERSION>` |
| `WP_CLI_VERSION` | Pinned wp-cli phar, SHA-512 verified at build time |
| `COMPOSER_VERSION` | Composer binary copied from `composer:<COMPOSER_VERSION>` |
| `MARIADB_VERSION` / `PHPMYADMIN_VERSION` | Database / admin UI images |

Changing any version requires a rebuild: `task restart` (it runs `--build`). `HOST_UID` / `HOST_GID` are build args too — after editing them run `docker compose build` (or `task build`).

### Composer runs on the WordPress PHP

`wordpress` and `composer` are the **same built image**; Composer just overrides the entrypoint. So `composer install` validates requirements against the exact PHP binary and extensions that serve the site — no more "installs fine, fatal error in WordPress". The image also carries wp-cli, so `wp db export`, `wp plugin install` etc. work without a separate container or extra config.

### Ports

`task init` offers a random free **block** in `20000–29999` (or a base you type):

| Variable | Default offset |
|---|---|
| `WP_PORT` | block base |
| `PMA_PORT` | base + 1 |
| `VITE_PORT` | base + 10 |

The block is verified free (host listeners *and* Docker-published ports) before being written to `.env`, then kept stable across restarts. The range sits below Linux's ephemeral port range (`32768–60999`) to avoid racing outgoing sockets, and away from common dev ports (`3000`, `5173`, `8000`, `8080`, `8085`, `8180`).

`WP_HOME` / `WP_SITEURL` are derived inside `compose.yml` from `WP_PORT`, so the site URL can never disagree with the actual mapping.

Need different values?

```bash
task init --base 20500                 # specific block
task init --wp-port 9000 --no-random   # fully manual
task init --php 8.2 --wp 6.9           # legacy PHP from sury backports
task init --yes                        # defaults, no prompts
task ports:new                          # re-roll later
```

### Theme and tooling

`THEME_DIR` is the theme path used by the node/composer tasks, e.g. `wp-content/themes/my-theme`. `task theme:clone -- <url>` sets it for you.

Theme side integration (one-time, in the theme's build config):

- read `APP_URL` (already exported by the node service) instead of hardcoding a URL
- read `VITE_PORT` for `server.port` and `server.hmr.clientPort` instead of hardcoding `5173`

## Gotchas

- **`wp-content/themes` and `wp-content/plugins` ship empty and are gitignored.** On boot the official WordPress entrypoint copies the bundled themes/plugins from the image into the mounted directory (Twenty Twenty-Five etc.), so a fresh stack renders immediately and `task seed` is only a recovery command. Those files stay untracked; your own theme goes in via `task theme:clone -- <url>`, your plugins are simply dropped in.
- **`composer` is behind the `tools` profile**, so `docker compose up` does not start it. Use `task composer:*` (which runs it on demand) or `docker compose run --rm composer ...`.
- **PHP below 8.3 is built from packages.sury.org**, so the image name ends in `-sury` and a rebuild downloads packages instead of the official tag. Moving `PHP_VERSION` across the 8.3 line also means updating `PHP_SOURCE`; `task check` refuses the mismatch.
- **Changing ports after install** keeps login/redirects working (config wins over the DB copy), but absolute URLs inside post content still point at the old port. Fix with `task wp -- search-replace 'http://localhost:<old>' 'http://localhost:<new>' --all-tables`.
- **Node runs as your host UID**, so `HOME` and the npm cache point to `/tmp`. If you add tools that need a home directory, do the same for them.
- **`localhost`, not `127.0.0.1`** — HMR, cookies and asset URLs all assume the same host the browser uses.
- **Root-owned files** should not happen (image remaps `www-data`; node/composer run as your UID). If they do appear after a manual `docker compose exec` as root, run `task fix-perms`.
- **`task reset` deletes the database volume.** Export first with `task db:export`.

## Layout

```
compose.yml                          stack definition, all values from .env
docker/wordpress/Dockerfile.official PHP 8.3+ image: WordPress + wp-cli + composer
docker/wordpress/Dockerfile.sury     PHP <8.3 image on Debian + packages.sury.org
Taskfile.yml                         task runner (thin wrappers)
bin/init                             interactive .env generator: versions, ports, credentials
bin/check                            image tag, PHP source + port validation
bin/ports                            show ports / re-roll a block
bin/versions                         print the resolved matrix
bin/wp                               wp-cli shim (runs as www-data)
bin/theme-clone                      clone a theme into wp-content/themes
bin/lib.sh                           shared shell helpers
wp-content/                          mounted into the container; themes/plugins start empty
db/                                  database dumps (gitignored)
```

## Security

Development only. Database credentials in `.env` are intentionally weak, MySQL root is reused by phpMyAdmin, and debug output is on. Never expose this stack to the internet.