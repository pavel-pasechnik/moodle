#!/bin/bash

# Moodle setup script with automatic deployment mode detection:
# - If EXTERNAL_DB_HOST is set and not empty, MODE=prod-ext and external DB vars are used.
# - Else, if POSTGRES_HOST or default postgres container is detected, MODE=dev or prod based on ENV_MODE (default dev).
# - Otherwise, defaults to dev mode with internal DB.
# This influences DB connection parameters and behavior accordingly.

set -e
set -o pipefail

export PATH=$PATH:/usr/local/bin

# Load environment variables from .env if present
if [ -f ".env" ]; then
  export $(grep -v '^#' .env | xargs)
fi


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

  if [ "$POSTGRES_HOST_DETECTED" = true ]; then
    MODE="dev"
  else
    MODE="dev"
  fi
  DBUSER=${MOODLE_DBUSER:-moodleuser}
  DBPASS=${MOODLE_DBPASS:-StrongPassword123}
  DBNAME=${MOODLE_DBNAME:-moodle}
  DBTYPE=${MOODLE_DBTYPE:-pgsql}
  echo "Detected deployment mode: $MODE (internal DB host: $DBHOST)"
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
    "SELECT COUNT(*) FROM pg_tables WHERE schemaname='public';" 2>/dev/null || echo "0")
elif [ "$DBTYPE" = "mysqli" ]; then
  DB_CHECK=$(mysql -h "$DBHOST" -u "$DBUSER" -p"$DBPASS" -D "$DBNAME" -se \
    "SHOW TABLES;" 2>/dev/null | wc -l || echo "0")
else
  echo "Unsupported DBTYPE: $DBTYPE"
  exit 1
fi

if [ "$DB_CHECK" -lt 10 ]; then
  echo "⚠️  Moodle database appears empty — proceeding with fresh installation."
  SKIP_INSTALL=false
else
  echo "✅ Moodle database already initialized, skipping installation and admin setup."
  SKIP_INSTALL=true
fi

# Installing Moodle if not initialized
if [ "$SKIP_INSTALL" = false ]; then
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
      --adminuser=${MOODLE_ADMIN_USER:-admin} \
      --adminpass=${MOODLE_ADMIN_PASS:-Admin@12345} \
      --adminemail=${MOODLE_ADMIN_EMAIL:-admin@example.com} \
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
  local repo_url="$1"
  local dest_dir="$2"

  echo "Cloning plugin to $dest_dir..."
  if git clone --depth 1 "$repo_url" "$dest_dir"; then
    echo "✅ Cloned via HTTPS: $repo_url"
    return 0
  else
    echo "❌ Failed to clone plugin: $repo_url"
    return 1
  fi
}


clone_with_fallback() {
  local repo="$1"
  local dest="$2"
  echo "Cloning $repo..."

  # Извлекаем major версию из MOODLE_VERSION (например, 4)
  major_version=$(echo "${MOODLE_VERSION:-4.5.7}" | cut -d'.' -f1)

  # Попытка определить доступную ветку Moodle X.xx_STABLE
  branch=$(git ls-remote --heads "$repo" | grep -Eo "refs/heads/MOODLE_${major_version}[0-9]{2}_STABLE" | sort -r | head -n1 | sed 's|refs/heads/||')

  # Если ничего не найдено — fallback на main или master
  if [ -z "$branch" ]; then
    git ls-remote --heads "$repo" main &>/dev/null && branch="main" ||
    git ls-remote --heads "$repo" master &>/dev/null && branch="master"
  fi

  echo "→ Using branch: ${branch:-unknown}"
  git clone --branch="${branch:-main}" --depth=1 "$repo" "$dest" || echo "⚠️  Failed to clone $repo"
}

# === TOOL_CERTIFICATE and its dependencies ===
echo "Installing tool_certificate and its dependencies..."

# Основной плагин tool_certificate
clone_with_fallback "https://github.com/moodleworkplace/moodle-tool_certificate.git" "/var/www/html/admin/tool/certificate" || true

# Установка подплагинов certificateelement_*
declare -a certificate_elements=(
  "border"
  "code"
  "date"
  "digitalsignature"
  "image"
  "program"
  "text"
  "userfield"
  "userpicture"
)

for element in "${certificate_elements[@]}"; do
  dir="/var/www/html/admin/tool/certificate/element/${element}"
  repo="https://github.com/moodleworkplace/moodle-certificateelement_${element}.git"
  if [ ! -d "$dir" ]; then
    echo "Installing ${element}..."
    clone_with_fallback "$repo" "$dir" || echo "⚠️  Failed to clone ${element}"
  else
    echo "${element} already exists."
  fi
done

chown -R www-data:www-data /var/www/html/admin/tool/certificate

# Installing or updating the Course Certificate plugin
if [ -d /var/www/html/mod/coursecertificate ]; then
  echo "Updating Course Certificate plugin..."
  cd /var/www/html/mod/coursecertificate && git pull || echo "⚠️  Failed to update Course Certificate plugin."
else
  echo "Installing Course Certificate plugin..."
  clone_with_fallback \
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
if [ -f /var/www/html/config.php ] && ! grep -q "redis_lock_factory" /var/www/html/config.php; then
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