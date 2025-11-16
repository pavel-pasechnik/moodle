# Moodle 4.5.7+ Docker Stack

![Docker](https://img.shields.io/badge/Docker-✓-2496ED?logo=docker&logoColor=white)
![PHP](https://img.shields.io/badge/PHP-8.1-777BB4?logo=php&logoColor=white)
![Nginx](https://img.shields.io/badge/Nginx-stable-009639?logo=nginx&logoColor=white)
![PostgreSQL](https://img.shields.io/badge/PostgreSQL-16.4-336791?logo=postgresql&logoColor=white)
![Redis](https://img.shields.io/badge/Redis-7.2-DC382D?logo=redis&logoColor=white)
![Moodle](https://img.shields.io/badge/Moodle-4.5.7+-F98012?logo=moodle&logoColor=white)
![License](https://img.shields.io/badge/License-MIT-blue)

## Available Tags

- `pasechnik/moodle_lts_optimized_images:latest` — universal build (contains all production optimizations)

This tag is built automatically via GitHub Actions and always reflects the latest commit on `main`.

---

## Description

Fully automated Docker image for **Moodle 4.5.7+**,  
including optimizations for PHP, Redis, PostgreSQL, optional Elasticsearch,  
and external plugins installed during the image build.

---

## Source Repository

All Dockerfiles, scripts, and compose configurations for this stack live in [pavel-pasechnik/moodle](https://github.com/pavel-pasechnik/moodle).

---

## Image Components

| Component         |     Version     | Purpose                                                                                     |
| ----------------- | :-------------: | ------------------------------------------------------------------------------------------- |
| **PHP-FPM**       |       8.1       | Web interpreter with support for `gd`, `intl`, `soap`, `redis`, `pgsql`, `pdo_pgsql`, `zip` |
| **Nginx**         |    stable      | Reverse proxy serving Moodle over FastCGI                                                  |
| **PostgreSQL**    |      16.4       | Primary database                                                                            |
| **Redis**         |       7.2       | Cache and session manager                                                                   |
| **Elasticsearch** |   optional      | Bring-your-own (disabled by default)                                                        |
| **Moodle**        |     4.5.7+      | Core LMS                                                                                    |
| **OS**            | Debian Bookworm | Base PHP-FPM image                                                                          |

---

## PHP Optimizations

| Parameter              | Value | Description                        |
| ---------------------- | :---: | ---------------------------------- |
| `max_input_vars`       | 5000  | Moodle requirement for large forms             |
| `memory_limit`         | 512M  | Optimal value for typical course workloads     |
| `upload_max_filesize`  |  50M  | Maximum upload file size                       |
| `max_execution_time`   | 300s  | Leaves room for heavy imports/cron hooks       |
| `opcache.enable`       |   1   | Speeds up PHP page loading                     |
| `session.save_handler` | redis | Sessions via Redis                             |
| `redis.host`           | redis | Caching                                        |
| `request_slowlog_timeout` | 0 | Slowlog disabled to avoid ptrace warnings in containers |

The bundled PHP-FPM pool is tuned for a 2 vCPU / 2 GB RAM host: `pm.max_children=12`, `pm.start_servers=6`, `pm.min_spare_servers=3`, `pm.max_spare_servers=9`, `pm.max_requests=200`, and `slowlog` is disabled so long-running UI posts do not block on ptrace.

---

## System and Caching Optimizations

| Area                          | Optimization                                         | Description                                                   |
| ----------------------------- | ---------------------------------------------------- | ------------------------------------------------------------- |
| **Redis Cache**               | Session, Locking, MUC                                | Improves concurrency, speeds up page loads and cron execution |
| **PostgreSQL**                | Optimized transactional engine                       | Ensures data integrity and efficient parallel processing      |
| **Elasticsearch**             | Optional bring-your-own backend                      | Integrate only if you deploy an external cluster              |
| **PHP-FPM pool**              | 12 workers, tuned spare servers, slowlog off         | Keeps UI responsive on 2 vCPU/2 GB hosts without ptrace noise |
| **Task queue guard**          | `task_*_concurrency_limit = 1` via `config/moodle/10-performance.php` | Heavy cron/adhoc jobs are serialized for low-RAM nodes        |
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
git clone https://github.com/pavel-pasechnik/moodle.git
cd moodle
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
  -p 9000:9000 \
  pasechnik/moodle_lts_optimized_images:latest
```

---

## Selecting the Moodle Image Tag

The stack defaults to the universal `latest` tag.  
Set `MOODLE_IMAGE` in `.env` if you need to test a different tag (e.g. a past release or custom build).

`setup.sh` detects whether `public/` or `publicroot/` exists and keeps the `/var/www/html/public_web` symlink updated so Nginx always serves the supported docroot for that release.

---

## Image Tags

```bash
docker pull pasechnik/moodle_lts_optimized_images:latest
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
    image: pasechnik/moodle_lts_optimized_images:latest
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
- The root `.env` is bind-mounted into every container as `/config/.env`, and `scripts/setup.sh` sources it automatically, so runtime bootstrap always uses the exact values you keep under version control.
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

| Plugin                             | Repository                                                                                                                                    | Purpose                                           |
| ---------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------- |
| **Certificate Tool**               | [moodleworkplace/moodle-tool_certificate](https://github.com/moodleworkplace/moodle-tool_certificate/releases/tag/v4.5.7)                     | Provides the certificate framework + APIs        |
| **Course Certificate**             | [moodleworkplace/moodle-mod_coursecertificate](https://github.com/moodleworkplace/moodle-mod_coursecertificate/releases/tag/v4.5.7)           | Adds the Course certificate activity type        |
| **Certificate Autonumber Element** | [pavel-pasechnik/certificateelement_autonumber](https://github.com/pavel-pasechnik/certificateelement_autonumber/releases/tag/v1.0.15)        | Auto-generates unique certificate numbers        |
| **Certificate "Certificat" Element** | [pavel-pasechnik/certificateelement_certificat](https://github.com/pavel-pasechnik/certificateelement_certificat/releases/tag/v1.0.4)         | Provides a branded visual element for templates  |
| **Certificate Import (local)**     | [pavel-pasechnik/local_certificateimport](https://github.com/pavel-pasechnik/local_certificateimport/releases/tag/v1.0.15)                    | Imports certificate templates/settings from file |

---
