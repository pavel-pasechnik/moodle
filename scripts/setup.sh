#!/bin/bash


set -e
set -o pipefail
export PATH=$PATH:/usr/local/bin

ssh -T git@github.com || echo "⚠️  SSH GitHub check failed, but continuing..."

# Remove unsupported options from SSH config (if macOS ~/.ssh/config is mounted)
if [ -f /root/.ssh/config ] && grep -q "UseKeychain" /root/.ssh/config; then
  sed -i '/UseKeychain/d' /root/.ssh/config
fi

echo "=== Moodle Setup Script ==="

# Waiting for the database to start
echo "Waiting for PostgreSQL to start..."
until pg_isready -h ${MOODLE_DBHOST:-postgres} -U ${MOODLE_DBUSER:-moodleuser}; do
  sleep 2
done

# Checking if Moodle is installed
if [ ! -f /var/www/html/config.php ]; then
  echo "Generating Moodle config.php..."
  /usr/local/bin/php admin/cli/install.php \
    --chmod=2777 \
    --lang=ru \
    --wwwroot=${MOODLE_URL:-http://localhost:8080} \
    --dataroot=/var/moodledata \
    --dbtype=pgsql \
    --dbhost=${MOODLE_DBHOST:-postgres} \
    --dbname=${MOODLE_DBNAME:-moodle} \
    --dbuser=${MOODLE_DBUSER:-moodleuser} \
    --dbpass=${MOODLE_DBPASS:-StrongPassword123} \
    --fullname="Moodle 4.5.7 Test" \
    --shortname="Moodle" \
    --adminuser=admin \
    --adminpass=Admin@12345 \
    --adminemail=admin@example.com \
    --non-interactive \
    --agree-license
else
  echo "Moodle already installed, skipping install.php"
fi

if ssh -T git@github.com 2>&1 | grep -q "successfully authenticated"; then
  echo "SSH connection to GitHub verified."
else
  echo "⚠️  Warning: GitHub SSH authentication failed. Plugins may not clone."
fi

# Installing the Course Certificate plugin
if [ ! -d /var/www/html/mod/coursecertificate ]; then
  echo "Installing Course Certificate plugin..."
  git clone --branch MOODLE_400_STABLE --depth 1 https://github.com/moodleworkplace/moodle-mod_coursecertificate.git /var/www/html/mod/coursecertificate
  chown -R www-data:www-data /var/www/html/mod/coursecertificate
else
  echo "Course Certificate plugin already installed."
fi


# Installing the Autonumber plugin
if [ ! -d /var/www/html/local/autonumber ]; then
  echo "Installing Autonumber plugin..."
  git clone https://github.com/pavel-pasechnik/autonumber.git /var/www/html/local/autonumber
  chown -R www-data:www-data /var/www/html/local/autonumber
else
  echo "Autonumber plugin already installed."
fi

# Add Redis and Elasticsearch settings if not specified
if [ -f /var/www/html/config.php ] && ! grep -q "redis" /var/www/html/config.php; then
  echo "Configuring Redis and search engine..."
  cat <<'EOCFG' >> /var/www/html/config.php

// Redis cache setup
\$CFG->session_handler_class = '\core\session\redis';
\$CFG->session_redis_host = '${REDIS_HOST:-redis}';
\$CFG->session_redis_port = ${REDIS_PORT:-6379};
\$CFG->cache_store_redis = 'redis';
\$CFG->cachestore_redis = true;
\$CFG->lock_factory = '\core\lock\redis_lock_factory';

// Global Search setup
\$CFG->searchengine = 'elasticsearch';
\$CFG->search_elasticsearch_server = 'http://${ELASTICSEARCH_HOST:-elasticsearch}:${ELASTICSEARCH_PORT:-9200}';
\$CFG->search_elasticsearch_index = 'moodle_index';
EOCFG
fi

if [ -f /var/www/html/config.php ]; then
  echo "Running Moodle upgrade..."
  /usr/local/bin/php admin/cli/upgrade.php --non-interactive
fi

# Setup straight
chown -R www-data:www-data /var/www/html /var/moodledata
chmod -R 755 /var/moodledata

echo "=== Moodle setup complete ==="
exec apache2-foreground