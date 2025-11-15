#!/bin/bash
set -euo pipefail

echo "🕒 Starting Moodle cron watchdog..."

while [ ! -f /var/www/html/config.php ]; do
  echo "⏳ Waiting for /var/www/html/config.php ..."
  sleep 10
done

echo "✅ Moodle config detected. Cron loop starting."

while true; do
  php /var/www/html/admin/cli/cron.php || echo "⚠️ cron.php exited with non-zero status"
  sleep 60
done
