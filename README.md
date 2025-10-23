# Moodle 4.5.7+ Docker Stack

![Docker](https://img.shields.io/badge/Docker-✓-2496ED?logo=docker&logoColor=white)
![PHP](https://img.shields.io/badge/PHP-8.3-777BB4?logo=php&logoColor=white)
![Apache](https://img.shields.io/badge/Apache-2.4-D22128?logo=apache&logoColor=white)
![PostgreSQL](https://img.shields.io/badge/PostgreSQL-16.4-336791?logo=postgresql&logoColor=white)
![Redis](https://img.shields.io/badge/Redis-7.2-DC382D?logo=redis&logoColor=white)
![Elasticsearch](https://img.shields.io/badge/Elasticsearch-8.15-005571?logo=elasticsearch&logoColor=white)
![Moodle](https://img.shields.io/badge/Moodle-4.5.7+-F98012?logo=moodle&logoColor=white)
![License](https://img.shields.io/badge/License-MIT-blue)
![Build Status](https://github.com/pavel-pasechnik/moodle/actions/workflows/docker-build.yml/badge.svg?branch=main)

---

## Description

Fully automated Docker image for **Moodle 4.5.7+**,  
including optimizations for PHP, Redis, PostgreSQL, Elasticsearch,  
and external plugins installed during the image build.

---

## Image Components

| Component         |     Version     | Purpose                                                                                     |
| ----------------- | :-------------: | ------------------------------------------------------------------------------------------- |
| **PHP**           |       8.3       | Web interpreter with support for `gd`, `intl`, `soap`, `redis`, `pgsql`, `pdo_pgsql`, `zip` |
| **Apache**        |       2.4       | HTTP server for Moodle                                                                      |
| **PostgreSQL**    |      16.4       | Primary database                                                                            |
| **Redis**         |       7.2       | Cache and session manager                                                                   |
| **Elasticsearch** |      8.15       | Full-text search for Moodle                                                                 |
| **Moodle**        |     4.5.7+      | Core LMS                                                                                    |
| **OS**            | Debian Bookworm | Base PHP-Apache image                                                                       |

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
| **Persistent Volumes**        | Separate `moodledata` and `postgres` volumes         | Ensures safe upgrades and better I/O performance              |
| **Auto Plugin Update**        | Pulls latest plugin versions on container rebuild    | Keeps plugins up-to-date automatically                        |
| **Apache Deflate (optional)** | Enables gzip compression                             | Reduces traffic and speeds up delivery of static files        |
| **Cron Container (optional)** | Runs Moodle cron every 5 minutes                     | Keeps scheduled tasks isolated from web container             |

---

## Quick Start

```bash
git clone https://github.com/pavel-pasechnik/moodle-docker.git
cd moodle-docker
cp .env.example .env
docker compose up -d --build
```

After installation, Moodle is available at:  
👉 [http://localhost:8080](http://localhost:8080)

---

## Automatically Installed Plugins

| Plugin                 | Repository                                                                                                      | Purpose                              |
| ---------------------- | --------------------------------------------------------------------------------------------------------------- | ------------------------------------ |
| **Course Certificate** | [moodleworkplace/moodle-mod_coursecertificate](https://github.com/moodleworkplace/moodle-mod_coursecertificate) | Course certificates                  |
| **Autonumber**         | [pavel-pasechnik/autonumber](https://github.com/pavel-pasechnik/autonumber)                                     | Automatic numbering for certificates |

---

## Build Modes

You can build the Moodle Docker image in three modes depending on your environment.
The build mode is automatically detected from the `MODE` variable in your `.env` file (defaults to `dev`).

### 🧩 Development Mode (`dev`)

Default mode used when no `MODE` argument is specified.

```bash
docker compose up -d --build
```

- All components (PostgreSQL, Redis, Elasticsearch, Moodle) run in a single stack.
- Ideal for local testing and plugin development.
- Automatically installs plugins and regenerates config on every build.

### 🚀 Production Mode (`prod`)

Used for single-host production deployment.

```bash
docker compose -f docker-compose.prod.yml up -d --build
```

- Optimized for performance and persistence.
- Keeps `moodledata` and `postgres` volumes separate.
- Uses prebuilt image and auto-updates plugins on rebuild.

### ☁️ External Database Mode (`prod-ext`)

For deployments using an external PostgreSQL or MySQL database.

```bash
docker compose -f docker-compose.prod-ext.yml up -d --build
```

- Skips local PostgreSQL container.
- Reads database credentials from `.env` (`EXTERNAL_DB_*` variables).
- Ideal for cloud or multi-server setups.

---

## CI/CD Automation

This repository includes GitHub Actions:

| Workflow         | File                                 | Purpose                               |
| ---------------- | ------------------------------------ | ------------------------------------- |
| **Docker Build** | `.github/workflows/docker-build.yml` | Build and publish Moodle Docker image |
| **Lint & QA**    | `.github/workflows/lint.yml`         | Code and configuration quality checks |

---

## Support

Developed for Krishna Academy projects and academic Moodle installations.  
Author: [Pavel Pasechnik](https://github.com/pavel-pasechnik)  
License: MIT

---

## Migration Guide

This section provides a step-by-step guide to migrate your existing Moodle installation from a MySQL server to PostgreSQL using Docker and the provided migration script.

### 🧰 Requirements on Host

Before running the migration script, ensure your host system includes:

- **Docker** ≥ 24.0
- **Docker Compose** ≥ 2.20
- **MySQL client** (for dumping your existing DB)
- **PostgreSQL client** (for restoring the converted DB)
- **`pgloader`** — used for MySQL → PostgreSQL data conversion
- **bash**, **gzip**, and **curl** available in `$PATH`

### Steps:

1. **Prepare Environment**

   Ensure your current Moodle is running on MySQL and you have a backup of your Moodle database and `moodledata`.

2. **Configure `.env`**

   Add the following MySQL connection variables to your `.env` file (based on `.env.example`):

   ```env
   # MySQL connection details for migration
   MYSQL_HOST=your_mysql_host
   MYSQL_USER=your_mysql_user
   MYSQL_PASSWORD=your_mysql_password
   MYSQL_DATABASE=your_mysql_database
   ```

   These variables will be used by `scripts/migrate.sh` to connect to your existing MySQL database.

3. **Run Migration Script**

   Execute the migration script to automatically migrate your Moodle data from MySQL to PostgreSQL:

   ```bash
   ./scripts/migrate.sh
   ```

   The script will:

   - Verify connectivity to both MySQL and PostgreSQL servers.
   - Dump the MySQL database.
   - Convert the dump to PostgreSQL-compatible format.
   - Restore the data into PostgreSQL.
   - Update Moodle configuration accordingly.

4. **Start Moodle with PostgreSQL**

   After successful migration, start your Moodle Docker stack:

   ```bash
   docker compose up -d --build
   ```

5. **Verify**

   Access Moodle at [http://localhost:8080](http://localhost:8080) and verify all data and functionality are intact.

---

For detailed assistance, please refer to the `scripts/migrate.sh` comments and logs.

---

## Exporting Custom Patches

The `export-moodle-patch.sh` script helps you capture local Moodle changes (custom code, theme, or plugin modifications) as a reusable patch.

### Usage

1. Configure `.env`:
   ```env
   MOODLE_PATH=/var/www/html/moodle
   PATCHES_DIR=./patches
   ```
2. Run the script:
   ```bash
   ./scripts/export-moodle-patch.sh
   ```
3. A patch file will be saved under `patches/` and a backup under `backups/`.

These patches are automatically applied during Docker image build, ensuring consistent deployment across environments.

---

## Environment Variables

See `.env.example` for full list of configurable parameters.  
Key variables include:

| Variable                          | Description                              |
| --------------------------------- | ---------------------------------------- |
| `MODE`                            | Build mode: `dev`, `prod`, or `prod-ext` |
| `MOODLE_URL`                      | Moodle site URL                          |
| `MOODLE_DBTYPE`                   | Database type (`pgsql` or `mysqli`)      |
| `MOODLE_DBHOST`                   | Database host name                       |
| `MOODLE_DBUSER` / `MOODLE_DBPASS` | Database credentials                     |
| `MOODLE_DBNAME`                   | Database name                            |
| `REDIS_HOST`                      | Redis server host                        |
| `ELASTICSEARCH_HOST`              | Elasticsearch host                       |
