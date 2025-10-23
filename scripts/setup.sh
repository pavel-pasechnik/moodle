#!/bin/bash

# Moodle setup script with automatic deployment mode detection:
# - If EXTERNAL_DB_HOST is set and not empty, MODE=prod-ext and external DB vars are used.
# - Else, if POSTGRES_HOST or default postgres container is detected, MODE=dev or prod based on ENV_MODE (default dev).
# - Otherwise, defaults to dev mode with internal DB.
# This influences DB connection parameters and behavior accordingly.

set -e
set -o pipefail
export PATH=$PATH:/usr/local/bin


echo "=== Moodle Setup Script ==="

# Deployment mode detection and DB configuration
if [ -n "${EXTERNAL_DB_HOST}" ]; then
  MODE="prod-ext"
  DBHOST=${EXTERNAL_DB_HOST}
  DBUSER=${EXTERNAL_DB_USER:-${MOODLE_DBUSER:-moodleuser}}
  DBPASS=${EXTERNAL_DB_PASS:-${MOODLE_DBPASS:-StrongPassword123}}
  DBNAME=${EXTERNAL_DB_NAME:-${MOODLE_DBNAME:-moodle}}
  DBTYPE=${MOODLE_DBTYPE:-pgsql}
  echo "Detected deployment mode: prod-ext (external DB host detected)"
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

  ENV_MODE=${ENV_MODE:-dev}

  if [ "$POSTGRES_HOST_DETECTED" = true ]; then
    if [ "$ENV_MODE" = "prod" ]; then
      MODE="prod"
    else
      MODE="dev"
    fi
    DBUSER=${MOODLE_DBUSER:-moodleuser}
    DBPASS=${MOODLE_DBPASS:-StrongPassword123}
    DBNAME=${MOODLE_DBNAME:-moodle}
    DBTYPE=${MOODLE_DBTYPE:-pgsql}
    echo "Detected deployment mode: $MODE (internal DB host: $DBHOST)"
  else
    # Fallback to dev mode with defaults
    MODE="dev"
    DBHOST=${MOODLE_DBHOST:-postgres}
    DBUSER=${MOODLE_DBUSER:-moodleuser}
    DBPASS=${MOODLE_DBPASS:-StrongPassword123}
    DBNAME=${MOODLE_DBNAME:-moodle}
    DBTYPE=${MOODLE_DBTYPE:-pgsql}
    echo "Detected deployment mode: $MODE (default internal DB host: $DBHOST)"
  fi
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

# Check if Moodle database is already initialized
if [ "$DBTYPE" = "pgsql" ]; then
  DB_CHECK=$(PGPASSWORD="$DBPASS" psql -h "$DBHOST" -U "$DBUSER" -d "$DBNAME" -tAc \
    "SELECT COUNT(*) FROM information_schema.tables WHERE table_name='config';" 2>/dev/null || echo "0")
elif [ "$DBTYPE" = "mysqli" ]; then
  DB_CHECK=$(mysql -h "$DBHOST" -u "$DBUSER" -p"$DBPASS" -D "$DBNAME" -se \
    "SHOW TABLES LIKE 'config';" 2>/dev/null | grep -c config || echo "0")
else
  echo "Unsupported DBTYPE: $DBTYPE"
  exit 1
fi

if [ "$DB_CHECK" != "0" ]; then
  echo "✅ Moodle database already initialized, skipping installation and admin setup."
  SKIP_INSTALL=true
else
  echo "⚠️  Moodle database appears empty — proceeding with fresh installation."
  rm -f /var/www/html/config.php 2>/dev/null || true
  SKIP_INSTALL=false
fi

# Installing Moodle if not initialized
if [ "$SKIP_INSTALL" = false ] && [ ! -f /var/www/html/config.php ]; then
  if [ -f /var/www/html/install.php ] || [ -f /var/www/html/admin/cli/install.php ]; then
    echo "Installing fresh Moodle instance..."
    /usr/local/bin/php $( [ -f /var/www/html/admin/cli/install.php ] && echo "/var/www/html/admin/cli/install.php" || echo "/var/www/html/install.php" ) \
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
      --adminuser=admin \
      --adminpass=Admin@12345 \
      --adminemail=admin@example.com \
      --non-interactive \
      --agree-license
  else
    echo "⚠️  install.php not found in admin/cli or root directory. Skipping Moodle installation."
  fi
else
  echo "Moodle already initialized, skipping CLI installer."
fi



# Universal plugin cloning function
clone_plugin() {
  local repo_https="$2"
  local dest_dir="$3"

  echo "Cloning plugin to $dest_dir..."

  # Clone via HTTPS only
  if git clone --depth 1 "$repo_https" "$dest_dir"; then
    echo "✅ Cloned via HTTPS: $repo_https"
    return 0
  else
    echo "❌ Failed to clone plugin: $repo_https"
    return 1
  fi
}


# Installing or updating the Course Certificate plugin
if [ -d /var/www/html/mod/coursecertificate ]; then
  echo "Updating Course Certificate plugin..."
  cd /var/www/html/mod/coursecertificate && git pull || echo "⚠️  Failed to update Course Certificate plugin."
else
  echo "Installing Course Certificate plugin..."
  clone_plugin \
    "https://github.com/moodleworkplace/moodle-mod_coursecertificate.git" \
    "/var/www/html/mod/coursecertificate"
  chown -R www-data:www-data /var/www/html/mod/coursecertificate
fi



# Installing or updating the Autonumber plugin
if [ -d /var/www/html/local/autonumber ]; then
  echo "Updating Autonumber plugin..."
  cd /var/www/html/local/autonumber && git pull || echo "⚠️  Failed to update Autonumber plugin."
else
  echo "Installing Autonumber plugin..."
  clone_plugin \
    "https://github.com/pavel-pasechnik/autonumber.git" \
    "/var/www/html/local/autonumber"
  chown -R www-data:www-data /var/www/html/local/autonumber
fi

# Add Redis and Elasticsearch settings if not specified
if [ -f /var/www/html/config.php ] && ! grep -q "redis" /var/www/html/config.php; then
  echo "Configuring Redis and search engine..."
  REDIS_HOST=${REDIS_HOST:-redis}
  REDIS_PORT=${REDIS_PORT:-6379}
  ELASTICSEARCH_HOST=${ELASTICSEARCH_HOST:-elasticsearch}
  ELASTICSEARCH_PORT=${ELASTICSEARCH_PORT:-9200}

  cat <<EOCFG >> /var/www/html/config.php

if (!defined('MOODLE_INTERNAL')) die();

\$CFG->session_handler_class = 'core\\session\\redis';
\$CFG->session_redis_host = '${REDIS_HOST}';
\$CFG->session_redis_port = ${REDIS_PORT};
\$CFG->cache_store_redis = 'redis';
\$CFG->cachestore_redis = true;
\$CFG->lock_factory = 'core\\lock\\redis_lock';

// Global Search setup
\$CFG->searchengine = 'elasticsearch';
\$CFG->search_elasticsearch_server = 'http://${ELASTICSEARCH_HOST}:${ELASTICSEARCH_PORT}';
\$CFG->search_elasticsearch_index = 'moodle_index';

?>
EOCFG
fi

if [ -f /var/www/html/config.php ]; then
  echo "Running Moodle upgrade..."
  if [ -f /var/www/html/admin/cli/upgrade.php ]; then
    /usr/local/bin/php /var/www/html/admin/cli/upgrade.php --non-interactive || echo "⚠️ Moodle upgrade failed (likely first init)."
  else
    echo "ℹ️ upgrade.php not found — skipping."
  fi
else
  echo "⚠️ Moodle config.php not found — skipping Redis and upgrade setup."
  exit 0
fi

# Setup straight
chown -R www-data:www-data /var/www/html /var/moodledata
chmod -R 755 /var/moodledata

echo "=== Moodle setup complete ==="
exec apache2-foreground