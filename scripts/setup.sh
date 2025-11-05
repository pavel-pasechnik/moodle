#!/bin/bash

# Moodle setup script with automatic deployment mode detection:
# - If EXTERNAL_DB_HOST is set and not empty, MODE=prod-ext and external DB vars are used.
# - Else, if POSTGRES_HOST or default postgres container is detected, MODE=dev or prod based on ENV_MODE (default dev).
# - Otherwise, defaults to dev mode with internal DB.
# This influences DB connection parameters and behavior accordingly.

set -Eeo pipefail
trap 'echo "❌ Setup failed at line $LINENO: [$BASH_COMMAND]"' ERR

export PATH=$PATH:/usr/local/bin

MOODLE_INIT_FLAG=/var/moodledata/.moodle_installed

# Load environment variables from .env if present (prefer /config/.env inside image)
if [ -f "/config/.env" ]; then
  export $(grep -v '^#' /config/.env | xargs)
elif [ -f ".env" ]; then
  export $(grep -v '^#' .env | xargs)
fi


echo "=== Moodle Setup Script ==="

# Deployment mode detection and DB configuration
if [ -n "${EXTERNAL_DB_HOST}" ]; then
  DBHOST=${EXTERNAL_DB_HOST}
  DBUSER=${EXTERNAL_DB_USER:-${MOODLE_DBUSER:-moodleuser}}
  DBPASS=${EXTERNAL_DB_PASS:-${MOODLE_DB_PASS:-StrongPassword123}}
  DBNAME=${EXTERNAL_DB_NAME:-${MOODLE_DB_NAME:-moodle}}
  DBTYPE=${MOODLE_DB_TYPE:-pgsql}
  echo "Detected external database (production environment)"
else
  # Check if POSTGRES_HOST or default postgres container exists (simple check by env var or hostname resolution)
  POSTGRES_HOST_DETECTED=false
  if [ -n "${POSTGRES_HOST}" ]; then
    POSTGRES_HOST_DETECTED=true
    DBHOST=${POSTGRES_HOST}
  else
    # Try to resolve 'postgres' hostname (default container)
    if getent hosts postgres >/dev/null 2>&1; then
      POSTGRES_HOST_DETECTED=true
      DBHOST="postgres"
    fi
  fi

  DBUSER=${MOODLE_DB_USER:-moodleuser}
  DBPASS=${MOODLE_DB_PASS:-StrongPassword123}
  DBNAME=${MOODLE_DB_NAME:-moodle}
  DBTYPE=${MOODLE_DB_TYPE:-pgsql}
  echo "Detected internal database (host: ${DBHOST:-postgres})"
fi

# Waiting for the database to start (PostgreSQL or MySQL)

wait_for_db() {
  local dbtype="$1"
  local host="$2"
  local user="$3"
  local pass="$4"
  local dbname="$5"

  if [ "$dbtype" = "pgsql" ]; then
    echo "Waiting for PostgreSQL to start on host $host..."
    until pg_isready -h "$host" -U "$user" >/dev/null 2>&1; do
      sleep 2
    done
  elif [ "$dbtype" = "mysqli" ]; then
    echo "Waiting for MySQL to start on host $host..."
    until mysqladmin ping -h "$host" -u "$user" -p"$pass" --silent; do
      sleep 2
    done
  else
    echo "Unsupported DBTYPE: $dbtype"
    exit 1
  fi
}

wait_for_db "$DBTYPE" "$DBHOST" "$DBUSER" "$DBPASS" "$DBNAME"

# New installation logic to avoid looping on existing config.php
if [ ! -f /var/www/html/config.php ]; then
    echo "⚙️  No config.php found — running full Moodle installation..."
    /usr/local/bin/php /var/www/html/admin/cli/install.php \
      --chmod=2777 \
      --lang=ru \
      --wwwroot=${MOODLE_URL:-http://localhost:8080} \
      --dataroot=/var/moodledata \
      --dbtype=$DBTYPE \
      --dbhost=$DBHOST \
      --dbname=$DBNAME \
      --dbuser=$DBUSER \
      --dbpass=$DBPASS \
      --fullname="Moodle 4.5.7 Test" \
      --shortname="Moodle" \
      --adminuser=${MOODLE_ADMIN_USER:-admin} \
      --adminpass=${MOODLE_ADMIN_PASS:-Admin@12345} \
      --adminemail=${MOODLE_ADMIN_EMAIL:-admin@example.com} \
      --non-interactive \
      --agree-license
fi

if [ -x /scripts/install_plugins.sh ]; then
  /scripts/install_plugins.sh
else
  echo "ℹ️ install_plugins.sh not found — skipping plugin bootstrap."
fi

echo "🧩 Running Moodle upgrade to register all new components..."
cd /var/www/html
if [ -f /var/www/html/admin/cli/upgrade_plugins.php ]; then
  /usr/local/bin/php admin/cli/upgrade_plugins.php --non-interactive || echo "⚠️ Plugin registration failed"
else
  echo "ℹ️ upgrade_plugins.php not found — running standard Moodle upgrade instead..."
  /usr/local/bin/php admin/cli/upgrade.php --non-interactive || echo "⚠️ Moodle upgrade failed"
fi
/usr/local/bin/php admin/cli/purge_caches.php || echo "⚠️ Cache purge failed"

# Check if Moodle database is already initialized (presence of mdl_config table)
if [ "$DBTYPE" = "pgsql" ]; then
  DB_CHECK=$(PGPASSWORD="$DBPASS" psql -h "$DBHOST" -U "$DBUSER" -d "$DBNAME" -tAc \
    "SELECT to_regclass('public.mdl_config');" 2>/dev/null || echo "")
elif [ "$DBTYPE" = "mysqli" ]; then
  DB_CHECK=$(mysql -h "$DBHOST" -u "$DBUSER" -p"$DBPASS" -D "$DBNAME" -se \
    "SHOW TABLES LIKE 'mdl_config';" 2>/dev/null || echo "")
else
  echo "Unsupported DBTYPE: $DBTYPE"
  exit 1
fi

if [ -n "$DB_CHECK" ] && [ "$DB_CHECK" != "null" ]; then
    echo "✅ Moodle database already initialized, skipping installation and admin setup."

    # Added post-install Moodle settings
    if [ -f /var/www/html/config.php ]; then
      cat >> /var/www/html/config.php <<'EOF'

// === Post-install defaults ===
$CFG->langstringcache = true;
$CFG->noemailever = true;
$CFG->debugdisplay = true;
$CFG->enableanalytics = false;
EOF
    fi
fi

if [ -f /var/www/html/config.php ]; then
  echo "🧩 Running Moodle upgrade (ensuring all plugins are installed)..."
  cd /var/www/html
  /usr/local/bin/php admin/cli/upgrade.php --non-interactive || echo "⚠️ Moodle upgrade failed"
  /usr/local/bin/php admin/cli/purge_caches.php || echo "⚠️ Cache purge failed"

  cd /var/www/html
  /usr/local/bin/php admin/cli/cfg.php --name=theme --set=boost || true
  /usr/local/bin/php admin/cli/purge_caches.php || true

  if ! grep -q "redis_lock_factory" /var/www/html/config.php; then
    echo "Configuring Redis and search engine..."

    # Append safe PHP config (no closing PHP tag, keep classes fully-qualified)
    cat <<EOCFG >> /var/www/html/config.php

// === Redis sessions and optional locking ===
// Sessions via Redis:
\$CFG->session_handler_class = '\\\\core\\\\session\\\\redis';
\$CFG->session_redis_host = getenv('REDIS_HOST') ?: 'redis';
\$CFG->session_redis_port = (int) (getenv('REDIS_PORT') ?: 6379);
\$CFG->session_redis_database = 0;
\$CFG->session_redis_prefix = 'moodle_';

// Locking via Redis (only if the class exists in this Moodle version):
if (class_exists('\\\\core\\\\lock\\\\redis_lock_factory')) {
    \$CFG->lock_factory = '\\\\core\\\\lock\\\\redis_lock_factory';
} else {
    // Fallback to default locking (file/db) when Redis lock factory is not present.
    // No explicit setting is required.
}

// === Optional: Global Search via Elasticsearch ===
// Comment out if not using Elasticsearch.
\$CFG->searchengine = 'elasticsearch';
\$CFG->search_elasticsearch_server = 'http://' . (getenv('ELASTICSEARCH_HOST') ?: 'elasticsearch') . ':' . (getenv('ELASTICSEARCH_PORT') ?: '9200');
\$CFG->search_elasticsearch_index = 'moodle_index';

EOCFG
  fi
fi

# Create the installation flag file to mark successful install
touch "$MOODLE_INIT_FLAG"

# Fix permissions for config.php to ensure Apache can read it
if [ -f /var/www/html/config.php ]; then
  chown www-data:www-data /var/www/html/config.php
  chmod 644 /var/www/html/config.php
fi

# Setup straight
chown -R www-data:www-data /var/moodledata || true
chmod -R 755 /var/moodledata

if [ ! -f /var/www/html/config.php ]; then
  echo "⚠️  Moodle config.php not found — Moodle may not be initialized yet."
fi

echo "=== Moodle setup complete ==="

exec apache2-foreground