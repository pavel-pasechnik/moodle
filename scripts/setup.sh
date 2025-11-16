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
MOODLE_EXTRA_CONFIG_DIR=${MOODLE_EXTRA_CONFIG_DIR:-/config/moodle}
PHP_OVERRIDE_DIR=${PHP_OVERRIDE_DIR:-/config/php}
WEB_PUBLIC_LINK=${WEB_PUBLIC_LINK:-/var/www/html/public_web}
MOODLE_HTML_DIR=${MOODLE_HTML_DIR:-/var/www/html}
MOODLE_DATA_DIR=${MOODLE_DATA_DIR:-/var/moodledata}

# Load environment variables from .env if present (prefer /config/.env inside image).
load_env_file() {
  local envfile="$1"
  [ -f "$envfile" ] || return
  set -a
  # shellcheck disable=SC1090
  . "$envfile"
  set +a
}

if [ -f "/config/.env" ]; then
  load_env_file "/config/.env"
elif [ -f ".env" ]; then
  load_env_file ".env"
fi

DEFAULT_DB_TYPE=${DB_TYPE:-${MOODLE_DB_TYPE:-pgsql}}
DEFAULT_DB_HOST=${DB_HOST:-${MOODLE_DB_HOST:-postgres}}
DEFAULT_DB_PORT=${DB_PORT:-${MOODLE_DB_PORT:-5432}}
DEFAULT_DB_NAME=${DB_NAME:-${MOODLE_DB_NAME:-moodle}}
DEFAULT_DB_USER=${DB_USER:-${MOODLE_DB_USER:-moodle}}
DEFAULT_DB_PASS=${DB_PASSWORD:-${MOODLE_DB_PASS:-supersecret}}

ensure_webroot_link() {
  local link="${WEB_PUBLIC_LINK}"
  local target=""
  local candidates=(
    "/var/www/html/publicroot"
    "/var/www/html/public"
    "/srv/moodle/public"
    "/var/www/html"
  )

  for candidate in "${candidates[@]}"; do
    if [ -d "$candidate" ]; then
      target="$candidate"
      break
    fi
  done

  if [ -z "$target" ]; then
    target="/var/www/html"
  fi

  ln -sfn "$target" "$link"
  chown -h www-data:www-data "$link" 2>/dev/null || true
  echo "🌐 Nginx docroot points to ${target}"
}

prepare_moodle_paths() {
  mkdir -p "$MOODLE_HTML_DIR" "$MOODLE_DATA_DIR"
  chown -R www-data:www-data "$MOODLE_DATA_DIR" 2>/dev/null || true
}

echo "=== Moodle Setup Script ==="
prepare_moodle_paths
ensure_webroot_link

apply_php_overrides() {
  local dir="$PHP_OVERRIDE_DIR"
  if [ ! -d "$dir" ]; then
    return
  fi

  shopt -s nullglob
  for file in "$dir"/*.ini; do
    [ -f "$file" ] || continue
    local base
    base=$(basename "$file")
    echo "🛠  Applying PHP override $base"
    cp "$file" "/usr/local/etc/php/conf.d/zz-${base}"
  done
  shopt -u nullglob
}

apply_moodle_overrides() {
  local dir="$MOODLE_EXTRA_CONFIG_DIR"
  [ -d "$dir" ] || return

  if [ -f "$dir/config.php" ]; then
    echo "⚙️  Replacing config.php with $dir/config.php"
    cp "$dir/config.php" /var/www/html/config.php
    chown www-data:www-data /var/www/html/config.php
    chmod 644 /var/www/html/config.php
    return
  fi

  if [ ! -f /var/www/html/config.php ]; then
    return
  fi

  if ! ls "$dir"/*.php >/dev/null 2>&1; then
    return
  fi

  local marker="// === Custom config injected from ${dir} ==="
  if grep -q "$marker" /var/www/html/config.php; then
    return
  fi

  echo "$marker" >> /var/www/html/config.php
  for snippet in "$dir"/*.php; do
    [ -f "$snippet" ] || continue
    [ "$(basename "$snippet")" = "config.php" ] && continue
    cat "$snippet" >> /var/www/html/config.php
    echo >> /var/www/html/config.php
  done
}

bootstrap_moodle_core() {
  local moodle_dir="/var/www/html"
  local image_moodle_dir="/var/www/moodle"
  local source="${MOODLE_REPO_URL:-}"
  local cleanup_image_copy="${CLEANUP_IMAGE_MOODLE_COPY:-1}"

  if [ -f "$moodle_dir/admin/cli/install.php" ]; then
    echo "✅ Moodle core detected under $moodle_dir"
    return
  fi

  echo "⬇️  Moodle core not found — bootstrapping..."

  if [ -n "$(ls -A "$moodle_dir" 2>/dev/null)" ]; then
    local backup="/tmp/moodle-html-backup-$(date +%s)"
    echo "📦  Backing up current /var/www/html contents to $backup"
    mkdir -p "$backup"
    cp -a "$moodle_dir/." "$backup/" || echo "⚠️  Backup copy failed; continuing with fresh checkout"
    find "$moodle_dir" -mindepth 1 -maxdepth 1 -exec rm -rf {} +
  fi

  if [ -d "$image_moodle_dir" ] && [ -f "$image_moodle_dir/admin/cli/install.php" ]; then
    echo "📦  Copying prebuilt Moodle from ${image_moodle_dir}"
    cp -a "$image_moodle_dir/." "$moodle_dir/"
    chown -R www-data:www-data "$moodle_dir"

    if [ "$cleanup_image_copy" = "1" ] && [ "$image_moodle_dir" != "$moodle_dir" ]; then
      echo "🧹  Removing image copy at ${image_moodle_dir} to avoid duplicate trees"
      rm -rf "$image_moodle_dir"
    fi
    return
  fi

  if [ -n "$source" ]; then
    echo "📥  Downloading Moodle sources from ${source}"
  else
    echo "📦  No MOODLE_REPO_URL supplied; skipping auto-download."
    return
  fi

  if [[ "$source" =~ \.git(@.+)?$ ]]; then
    command -v git >/dev/null 2>&1 || { echo "❌ git is required to clone Moodle sources"; exit 1; }
    local repo_url="$source"
    local git_ref=""
    if [[ "$source" == *@* ]]; then
      git_ref="${source##*@}"
      repo_url="${source%@*}"
    fi

    if [ -n "$git_ref" ]; then
      git clone --depth=1 --branch "$git_ref" "$repo_url" "$moodle_dir"
    else
      git clone --depth=1 "$repo_url" "$moodle_dir"
    fi
  else
    command -v curl >/dev/null 2>&1 || { echo "❌ curl is required to download Moodle archive"; exit 1; }
    command -v unzip >/dev/null 2>&1 || command -v tar >/dev/null 2>&1 || {
      echo "❌ Either unzip or tar is required to extract Moodle archive"; exit 1;
    }

    local archive_url="$source"
    if [[ "$archive_url" == *"/releases/tag/"* ]]; then
      local repo_root="${archive_url%/releases/tag/*}"
      local tag="${archive_url##*/}"
      archive_url="${repo_root}/archive/refs/tags/${tag}.zip"
    fi

    local tmpdir
    tmpdir=$(mktemp -d)
    local archive_path="$tmpdir/moodle-archive"
    echo "📥  Downloading ${archive_url}"
    curl -fsSL "$archive_url" -o "$archive_path"

    if [[ "$archive_url" =~ \.zip$ ]]; then
      unzip -q "$archive_path" -d "$tmpdir"
    else
      tar -xf "$archive_path" -C "$tmpdir"
    fi

    local extracted_dir
    extracted_dir=$(find "$tmpdir" -mindepth 1 -maxdepth 1 -type d | head -n1)
    if [ -z "$extracted_dir" ]; then
      echo "❌ Failed to extract Moodle sources from ${archive_url}"
      exit 1
    fi

    cp -a "$extracted_dir/." "$moodle_dir/"
    rm -rf "$tmpdir"
  fi

  chown -R www-data:www-data "$moodle_dir"
}

ensure_router_middleware_order() {
  local file="/var/www/html/lib/classes/router.php"
  [ -f "$file" ] || return

  if grep -q "Bootstrap middleware executes before route attribute" "$file"; then
    return
  fi

  perl -0pi -e 's#// Add the Moodle route attribute to the request.\n(\s*)// This must be processed after the Routing Middleware has been processed on the request.\n(\s*)\$this->app->add\(di::get\(moodle_route_attribute_middleware::class\)\);\n\n(\s*)// Add Middleware to Bootstrap Moodle from a request.\n(\s*)\$this->app->add\(di::get\(moodle_bootstrap_middleware::class\)\);#// Add Middleware to Bootstrap Moodle from a request.\n\3\$this->app->add(di::get(moodle_bootstrap_middleware::class));\n\n\1// Add the Moodle route attribute to the request.\n\1// This must be processed after the Routing Middleware has been processed on the request.\n\1// Bootstrap middleware executes before route attribute (required for authenticated REST).\n\1\$this->app->add(di::get(moodle_route_attribute_middleware::class));#' "$file" || true
}

bootstrap_moodle_core
ensure_router_middleware_order
apply_php_overrides
ensure_webroot_link

# Deployment mode detection and DB configuration
if [ -n "${EXTERNAL_DB_HOST}" ]; then
  DBHOST=${EXTERNAL_DB_HOST}
  DBPORT=${EXTERNAL_DB_PORT:-${DEFAULT_DB_PORT}}
  DBUSER=${EXTERNAL_DB_USER:-${DEFAULT_DB_USER}}
  DBPASS=${EXTERNAL_DB_PASS:-${DEFAULT_DB_PASS}}
  DBNAME=${EXTERNAL_DB_NAME:-${DEFAULT_DB_NAME}}
  DBTYPE=${EXTERNAL_DB_TYPE:-${DEFAULT_DB_TYPE}}
  echo "Detected external database (production environment)"
else
  DBHOST=${DEFAULT_DB_HOST}
  if [ -n "${POSTGRES_HOST}" ]; then
    DBHOST=${POSTGRES_HOST}
  elif getent hosts postgres >/dev/null 2>&1; then
    DBHOST="postgres"
  fi

  DBPORT=${DEFAULT_DB_PORT}
  DBUSER=${DEFAULT_DB_USER}
  DBPASS=${DEFAULT_DB_PASS}
  DBNAME=${DEFAULT_DB_NAME}
  DBTYPE=${DEFAULT_DB_TYPE}
  echo "Detected internal database (host: ${DBHOST:-postgres})"
fi

# Waiting for the database to start (PostgreSQL or MySQL)

wait_for_db() {
  local dbtype="$1"
  local host="$2"
  local port="$3"
  local user="$4"
  local pass="$5"
  local dbname="$6"

  if [ "$dbtype" = "pgsql" ]; then
    echo "Waiting for PostgreSQL to start on host $host port $port..."
    until PGPASSWORD="$pass" pg_isready -h "$host" -p "$port" -U "$user" >/dev/null 2>&1; do
      sleep 2
    done
  elif [ "$dbtype" = "mysqli" ]; then
    echo "Waiting for MySQL to start on host $host port $port..."
    until mysqladmin ping -h "$host" -P "$port" -u "$user" -p"$pass" --silent; do
      sleep 2
    done
  else
    echo "Unsupported DBTYPE: $dbtype"
    exit 1
  fi
}

wait_for_db "$DBTYPE" "$DBHOST" "$DBPORT" "$DBUSER" "$DBPASS" "$DBNAME"

db_table_exists() {
  local tablename="$1"

  if [ "$DBTYPE" = "pgsql" ]; then
    local result
    result=$(PGPASSWORD="$DBPASS" psql -h "$DBHOST" -p "$DBPORT" -U "$DBUSER" -d "$DBNAME" -tAc \
      "SELECT 1 FROM pg_tables WHERE schemaname = 'public' AND tablename = '${tablename}' LIMIT 1;" 2>/dev/null || true)
    if [[ "$result" =~ 1 ]]; then
      return 0
    fi
  elif [ "$DBTYPE" = "mysqli" ]; then
    local result
    result=$(mysql -h "$DBHOST" -P "$DBPORT" -u "$DBUSER" -p"$DBPASS" -D "$DBNAME" -se \
      "SHOW TABLES LIKE '${tablename}';" 2>/dev/null || true)
    if [[ "$result" == "$tablename" ]]; then
      return 0
    fi
  fi

  return 1
}

ensure_rw_access() {
  local target="$1"
  local owner="$2"

  if [ -e "$target" ]; then
    echo "🔐 Ensuring read/write access on $target"
    chown -R "$owner" "$target" 2>/dev/null || true
    chmod -R ug+rwX "$target" 2>/dev/null || true
  fi
}

MOODLE_DB_READY=false
if db_table_exists "mdl_config" && db_table_exists "mdl_user"; then
  MOODLE_DB_READY=true
fi

NEEDS_INSTALL=false
if [ ! -f /var/www/html/config.php ]; then
  NEEDS_INSTALL=true
fi

if [ "$MOODLE_DB_READY" = false ]; then
  NEEDS_INSTALL=true
  if [ -f /var/www/html/config.php ]; then
    STALE_CONFIG="/var/www/html/config.php.stale.$(date +%s)"
    echo "⚠️  Moodle tables not found but config.php exists — moving it aside to $STALE_CONFIG"
    mv /var/www/html/config.php "$STALE_CONFIG"
  fi
fi

if [ "$NEEDS_INSTALL" = true ]; then
  echo "⚙️  Running full Moodle installation..."
  /usr/local/bin/php /var/www/html/admin/cli/install.php \
    --chmod=2777 \
    --lang=${MOODLE_LANG:-ru} \
    --wwwroot=${MOODLE_URL:-http://localhost} \
    --dataroot=/var/moodledata \
    --dbtype=$DBTYPE \
    --dbhost=$DBHOST \
    --dbport=$DBPORT \
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

  MOODLE_DB_READY=true
fi

if [ -x /scripts/install_plugins.sh ]; then
  /scripts/install_plugins.sh
else
  echo "ℹ️ install_plugins.sh not found — skipping plugin bootstrap."
fi

if [ -f /var/www/html/config.php ]; then
  echo "🧩 Running Moodle upgrade (ensuring all plugins are installed)..."
  cd /var/www/html
  if [ -f admin/cli/upgrade_plugins.php ]; then
    /usr/local/bin/php admin/cli/upgrade_plugins.php --non-interactive || echo "⚠️ Plugin registration failed"
  fi
  /usr/local/bin/php admin/cli/upgrade.php --non-interactive || echo "⚠️ Moodle upgrade failed"
  /usr/local/bin/php admin/cli/purge_caches.php || echo "⚠️ Cache purge failed"

  if [ -f admin/cli/scheduled_task.php ]; then
    echo "🧼  Running context cleanup task..."
    if output=$(/usr/local/bin/php admin/cli/scheduled_task.php --execute='core\\task\\context_cleanup_task' 2>&1); then
      printf '%s\n' "$output"
    else
      if echo "$output" | grep -q "context_cleanup_task' not found"; then
        echo "ℹ️ Context cleanup task not registered yet — skipping."
      else
        printf '%s\n' "$output"
        echo "⚠️ Context cleanup task failed"
      fi
    fi
  else
    echo "ℹ️ scheduled_task.php not available — skipping context cleanup."
  fi

  cd /var/www/html
  /usr/local/bin/php admin/cli/purge_caches.php || true
fi

apply_moodle_overrides
if [ -f /scripts/configure_cache.php ] && [ -f /var/www/html/config.php ]; then
  echo "🧠 Applying Redis session/cache configuration..."
  if ! /usr/local/bin/php /scripts/configure_cache.php; then
    echo "⚠️  Redis cache bootstrap failed; continuing with defaults."
  fi
else
  echo "ℹ️  Redis cache bootstrap skipped (missing configure_cache.php or config.php)."
fi
if [ -f /scripts/configure_filesystem_repository.php ] && [ -f /var/www/html/config.php ]; then
  echo "📁 Configuring filesystem repository defaults..."
  if ! /usr/local/bin/php /scripts/configure_filesystem_repository.php; then
    echo "⚠️  Filesystem repository bootstrap failed; continuing."
  fi
else
  echo "ℹ️  Filesystem repository bootstrap skipped (missing script or config.php)."
fi
if [ -f /scripts/configure_cli_paths.php ] && [ -f /var/www/html/config.php ]; then
  echo "🛠  Configuring CLI tool paths..."
  if ! /usr/local/bin/php /scripts/configure_cli_paths.php; then
    echo "⚠️  CLI path bootstrap failed; continuing."
  fi
else
  echo "ℹ️  CLI path bootstrap skipped (missing script or config.php)."
fi
apply_php_overrides

# Create the installation flag file to mark successful install
touch "$MOODLE_INIT_FLAG"

ensure_rw_access /var/www/html www-data:www-data
ensure_rw_access /var/moodledata www-data:www-data
ensure_rw_access /scripts www-data:www-data
find /scripts -maxdepth 1 -name "*.sh" -exec chmod +x {} \; 2>/dev/null || true

# Fix permissions for config.php to ensure the web server can read it
fix_config_permissions() {
  if [ -f /var/www/html/config.php ]; then
    chown root:www-data /var/www/html/config.php
    chmod 640 /var/www/html/config.php
  fi
}

fix_config_permissions

if [ ! -f /var/www/html/config.php ]; then
  echo "⚠️  Moodle config.php not found — Moodle may not be initialized yet."
fi

echo "🧹 Clearing old sessions and caches..."
rm -rf /var/moodledata/sessions/* || true
php /var/www/html/admin/cli/purge_caches.php || true

# === Final cache clear for static resources ===
echo "🧹 Clearing caches again to refresh static resources..."
php /var/www/html/admin/cli/purge_caches.php || true

echo "=== Moodle setup complete ==="

echo "ℹ️ Starting php-fpm..."
exec php-fpm -F
