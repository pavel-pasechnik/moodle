# Moodle 4.5.7+ Docker Stack

![Docker](https://img.shields.io/badge/Docker-✓-2496ED?logo=docker&logoColor=white)
![PHP](https://img.shields.io/badge/PHP-8.3-777BB4?logo=php&logoColor=white)
![Nginx](https://img.shields.io/badge/Nginx-stable-009639?logo=nginx&logoColor=white)
![PostgreSQL](https://img.shields.io/badge/PostgreSQL-16.4-336791?logo=postgresql&logoColor=white)
![Redis](https://img.shields.io/badge/Redis-7.2-DC382D?logo=redis&logoColor=white)
![Elasticsearch](https://img.shields.io/badge/Elasticsearch-8.15-005571?logo=elasticsearch&logoColor=white)
![Moodle](https://img.shields.io/badge/Moodle-4.5.7+-F98012?logo=moodle&logoColor=white)
![License](https://img.shields.io/badge/License-MIT-blue)

## Available Tags

- `dev` — development image with full debugging and auto-plugin installation
- `prod` — optimized production-ready image with caching, OPcache, and production settings
All images are built automatically via GitHub Actions.

---

## Description

Fully automated Docker image for **Moodle 4.5.7+**,  
including optimizations for PHP, Redis, PostgreSQL, Elasticsearch,  
and external plugins installed during the image build.

---

## Image Components

| Component         |     Version     | Purpose                                                                                     |
| ----------------- | :-------------: | ------------------------------------------------------------------------------------------- |
| **PHP-FPM**       |       8.3       | Web interpreter with support for `gd`, `intl`, `soap`, `redis`, `pgsql`, `pdo_pgsql`, `zip` |
| **Nginx**         |    stable      | Reverse proxy serving Moodle over FastCGI                                                  |
| **PostgreSQL**    |      16.4       | Primary database                                                                            |
| **Redis**         |       7.2       | Cache and session manager                                                                   |
| **Elasticsearch** |      8.15       | Full-text search for Moodle                                                                 |
| **Moodle**        |     4.5.7+      | Core LMS                                                                                    |
| **OS**            | Debian Bookworm | Base PHP-FPM image                                                                          |

---

## PHP Optimizations

| Parameter              | Value | Description                        |
| ---------------------- | :---: | ---------------------------------- |
| `max_input_vars`       | 5000  | Moodle requirement for large forms |
| `memory_limit`         | 512M  | Optimal value for courses          |
| `upload_max_filesize`  |  50M  | Maximum upload file size           |
| `opcache.enable`       |   1   | Speeds up PHP page loading         |
| `session.save_handler` | redis | Sessions via Redis                 |
| `redis.host`           | redis | Caching                            |

---

## System and Caching Optimizations

| Area                          | Optimization                                         | Description                                                   |
| ----------------------------- | ---------------------------------------------------- | ------------------------------------------------------------- |
| **Redis Cache**               | Session, Locking, MUC                                | Improves concurrency, speeds up page loads and cron execution |
| **PostgreSQL**                | Optimized transactional engine                       | Ensures data integrity and efficient parallel processing      |
| **Elasticsearch**             | Full-text search backend                             | Speeds up course, forum, and resource searches                |
| **Docker Healthcheck**        | Waits for PostgreSQL to be ready before Moodle setup | Prevents early initialization failures                        |
| **Layer Cleanup**             | `apt-get clean && rm -rf /var/lib/apt/lists/*`       | Reduces final image size                                      |
| **Persistent Volumes**        | `/var/www/html` (code) + `/var/moodledata` (files)   | Lets you move user files elsewhere (e.g. Google Workspace)    |
| **Auto Plugin Update**        | Pulls latest plugin versions on container rebuild    | Keeps plugins up-to-date automatically                        |
| **Nginx gzip (optional)**     | Enables gzip compression                             | Reduces traffic and speeds up delivery of static files        |
| **Cron Container (optional)** | Runs Moodle cron every 5 minutes                     | Keeps scheduled tasks isolated from web container             |

---

Cron tasks are orchestrated through `scripts/run_cron.php`, a PHP-CLI watchdog that you can run inside the provided `cron` service or copy to another host/container (mount `/var/www/html` + `/var/moodledata` and reuse the same `.env`).

---

## Quick Start

```bash
git clone https://github.com/pavel-pasechnik/moodle-docker.git
cd moodle-docker
cp .env.example .env
docker compose up -d
```

After installation, Moodle is available at:  
👉 [http://localhost](http://localhost)

---

## Quick Run (without compose)

```bash
docker run -d \
  --name moodle \
  -p 8080:8080 \
  -e BUILD_MODE=prod \
  pasechnik/moodle_lts_optimized_images:prod
```

---

## Choosing Moodle Versions

The Docker stack can launch multiple Moodle tracks without changing compose files.  
Set `MOODLE_IMAGE` in `.env` to one of the published tags:

- `pasechnik/moodle_lts_images:4.5.7-lts-fpm` — current FPM LTS (default)
- `pasechnik/moodle_lts_images:5.0.3-fpm` — feature branch with public directory
- `pasechnik/moodle_lts_images:5.1.0-fpm` — latest generation with `publicroot`

`setup.sh` detects whether `public/` or `publicroot/` exists and keeps the `/var/www/html/public_web` symlink updated so Nginx always serves the supported docroot for that release.

---

## Build Modes

The image supports two build modes:

- `dev` — enables verbose debugging, plugin auto-installation and fast rebuilds
- `prod` — optimized for high performance, stable caching and production setups

Select build mode using tags:
```bash
docker pull pasechnik/moodle_lts_optimized_images:dev
docker pull pasechnik/moodle_lts_optimized_images:prod
```

---

## Custom Overrides

- Place Nginx snippets in `config/nginx/conf.d/*.conf` — they are bind-mounted into `/etc/nginx/conf.d` on each container start. The default virtual host already points to `/var/www/html/public_web`, so any Moodle 4.5 → 5.1 codebase is served correctly.
- Drop Moodle overrides in `config/moodle/`. Provide a full `config.php` to replace the auto-generated one or multiple `*.php` snippets to append after installation.

These directories are bind-mounted via `docker-compose.yml`, so they can also be managed through scripts if needed.

---

## Minimal docker-compose.yml

```yaml
services:
  moodle:
    image: pasechnik/moodle_lts_optimized_images:prod
    ports:
      - "80:8080"
    environment:
      BUILD_MODE: prod
    volumes:
      - moodledata:/var/moodledata
      - moodlehtml:/var/www/html

volumes:
  moodledata:
  moodlehtml:
```

---

## Redis Caching

- `scripts/configure_cache.php` runs after every container bootstrap and enforces Redis for sessions plus all heavy Moodle caches (string/lang/config/theme/plugin info/html purifier/question data/grade caches). A single `redis_shared` store becomes the default for both application and session cache modes, so PostgreSQL never stores MUC data.
- Request-mode caches stay on the built-in static store because the Redis cachestore only supports application + session modes. Everything else (sessions, locks, admin caches) is re-pointed automatically.
- Tune prefixes and locking with `.env`: `REDIS_CACHE_PREFIX`, `REDIS_SESSION_LOCK_TIMEOUT`, `REDIS_SESSION_LOCK_WAIT`, `REDIS_SESSION_LOCK_WARN`, and `REDIS_SESSION_LOCK_EXPIRE`.

> ⚠️ Elasticsearch is optional.  
> If your server has less than 4 GB RAM, disable global search or use `simpledb`.

---

## Persistent Data

- `/var/www/html` is backed by the `moodlehtml` named volume (or `/srv/moodle/html` in prod). On the first run Docker populates it with the Moodle code shipped inside the image, so you can treat the image like PostgreSQL — no manual checkout required.
- `/var/moodledata` is backed by the `moodledata` volume (or `/srv/moodle/moodledata` in prod). All user uploads, homework, grade exports, temporary files, etc. live here. Because it is a dedicated mount, you can later swap it for an NFS share, rclone mount, or Google Workspace drive without touching the code volume.
- To reset everything, run `docker compose down -v`; otherwise `docker compose pull && docker compose up -d` keeps both volumes intact while refreshing the Moodle image.

---

## Environment Hints

- `DB_TYPE`, `DB_HOST`, `DB_PORT`, `DB_NAME`, `DB_USER`, and `DB_PASSWORD` are read by the setup script and entrypoint. Adjust them in `.env` (or via `EXTERNAL_DB_*` overrides for `docker-compose.prod-ext.yml`) to point Moodle at any PostgreSQL/MySQL instance.
- `MOODLE_IMAGE` selects which Moodle version to boot (4.5.7 LTS, 5.0.3, 5.1.0). Change it in `.env`, run `docker compose pull`, and restart the stack to test another track without editing compose files.
- `ENABLE_REDIS_SESSION` together with the `REDIS_*` variables matches the tuning expected by `docker/moodle-entrypoint.sh` (timeouts, locking, pooling). Tweak these values to align with external Redis deployments without rebuilding the image.
- `REDIS_MAXMEMORY`, `REDIS_MAXMEMORY_POLICY`, and `REDIS_APPENDONLY` are passed directly to `redis-server`, so cache size/policy changes just require tweaking `.env` and restarting the container.
- PostgreSQL memory/connection settings can be tuned via `.env`: `PG_SHARED_BUFFERS`, `PG_WORK_MEM`, `PG_MAINTENANCE_WORK_MEM`, `PG_EFFECTIVE_CACHE_SIZE`, `PG_MAX_CONNECTIONS`, and `PG_WAL_BUFFERS`. The compose file passes them directly to the `postgres` process (`docker-compose.yml`), so changes take effect on the next container restart.
- `REDIS_CACHE_PREFIX`, `REDIS_SESSION_LOCK_TIMEOUT`, `REDIS_SESSION_LOCK_WAIT`, `REDIS_SESSION_LOCK_WARN`, and `REDIS_SESSION_LOCK_EXPIRE` shape the Redis cache bootstrap script. Set `ENABLE_REDIS_SESSION=0` to skip Redis entirely (not recommended).
- `MOODLE_PATH_TO_*` variables feed into `admin/cli/install.php` (paths to php, du, aspell, graphviz, ghostscript, pdftoppm). `MOODLE_ENABLE_FILESYSTEM_REPOSITORY=1` automatically turns on the File system repository for course/personal use.
- `MOODLE_REVERSE_PROXY`, `MOODLE_SSL_PROXY`, and `MOODLE_COOKIE_SECURE` should be enabled (`true`) when running behind Cloudflare or any HTTPS offloader so that Moodle generates HTTPS links and trusts the proxy headers.

---

## Why this image?

- Fully automated setup (no manual config.php)
- Supports Moodle 4.5 → 5.1+
- Auto-handles public/ and publicroot/ docroots
- Redis-first caching stack
- Optimized Nginx + PHP-FPM configuration
- Cron isolated into a separate service
- Production-ready and suitable for local development

---

## Production Deployment

1. Create directories on the host (if you run Moodle 5.1+ and want nginx to serve `/public`, update the `root` in `config/nginx/conf.d/moodle.conf` to `/var/www/html/public`; for HTTPS use `config/nginx/conf.d-https/moodle.conf`):
   ```bash
   sudo mkdir -p /srv/moodle/{html,moodledata,postgres,redis,certs}
   sudo chown -R 1000:1000 /srv/moodle  # adjust UID/GID to match Docker user
   ```
2. Place your TLS certificate/key inside `/srv/moodle/certs` as `tls.crt` and `tls.key` (nginx mounts this directory read-only).
3. Copy `docker-compose.prod.yml` from this repo to the server. Adjust `.env` to match your domain, DB credentials, and SSL/proxy settings (`MOODLE_REVERSE_PROXY`, `MOODLE_SSL_PROXY`, `MOODLE_COOKIE_SECURE`, `MOODLE_URL=https://subdomain.example.com`).
4. Start the stack: `docker compose -f docker-compose.prod.yml up -d`.
5. Updates follow the same pattern as Postgres: `docker compose -f docker-compose.prod.yml pull && docker compose -f docker-compose.prod.yml up -d`. Volumes under `/srv/moodle/...` keep all code, plugins, and user data intact.
6. When using Cloudflare (or any reverse proxy), configure the proxy to forward the real client IP headers and enable HTTPS. Moodle picks it up via the `.env` flags above.

---

## Automatically Installed Plugins

| Plugin                 | Repository                                                                                                      | Purpose                              |
| ---------------------- | --------------------------------------------------------------------------------------------------------------- | ------------------------------------ |
| **Course Certificate** | [moodleworkplace/moodle-mod_coursecertificate](https://github.com/moodleworkplace/moodle-mod_coursecertificate) | Course certificates                  |
| **Autonumber**         | [pavel-pasechnik/autonumber](https://github.com/pavel-pasechnik/autonumber)                                     | Automatic numbering for certificates |

---

## Changelog

Full release notes:  
https://github.com/pavel-pasechnik/moodle/releases

---
