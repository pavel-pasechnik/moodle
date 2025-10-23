#!/bin/bash
source .env 2>/dev/null || true
set -e

echo "=== Moodle Migration Script ==="

# === Connection settings ===
MYSQL_HOST=${MYSQL_HOST:-localhost}
MYSQL_USER=${MYSQL_USER:-root}
MYSQL_PASS=${MYSQL_PASS:-root}
MYSQL_DB=${MYSQL_DB:-moodle}

PG_HOST=${PG_HOST:-localhost}
PG_USER=${PG_USER:-moodle}
PG_PASS=${PG_PASS:-moodle}
PG_DB=${PG_DB:-moodle}

DATE=$(date +%Y%m%d-%H%M%S)
BACKUP_DIR=${BACKUP_DIR:-$(pwd)/backups/$DATE}
mkdir -p "$BACKUP_DIR"

echo "Checking MySQL connection..."
if ! mysql -h "$MYSQL_HOST" -u "$MYSQL_USER" -p"$MYSQL_PASS" -e "USE $MYSQL_DB;" >/dev/null 2>&1; then
  echo "Error: Cannot connect to MySQL with provided credentials or database does not exist."
  exit 1
fi

echo "Checking PostgreSQL connection..."
if ! PGPASSWORD="$PG_PASS" psql -h "$PG_HOST" -U "$PG_USER" -d "$PG_DB" -c '\q' >/dev/null 2>&1; then
  echo "Error: Cannot connect to PostgreSQL with provided credentials or database does not exist."
  exit 1
fi

echo "1️⃣ Creating a MySQL backup..."
mysqldump -h "$MYSQL_HOST" -u "$MYSQL_USER" -p"$MYSQL_PASS" "$MYSQL_DB" > "$BACKUP_DIR/moodle_mysql.sql"

echo "2️⃣  Exporting MoodleData..."
tar czf "$BACKUP_DIR/moodledata.tar.gz" /var/www/moodledata

echo "3️⃣  Converting MySQL → PostgreSQL..."
docker run --rm -v "$BACKUP_DIR:/data" dimitri/pgloader:latest \
  pgloader mysql://$MYSQL_USER:$MYSQL_PASS@$MYSQL_HOST/$MYSQL_DB \
           postgresql://$PG_USER:$PG_PASS@$PG_HOST/$PG_DB

echo "4️⃣  Restoring moodledata..."
tar xzf "$BACKUP_DIR/moodledata.tar.gz" -C ./moodledata

echo "✅ Migration finished. Backups saved in $BACKUP_DIR"
echo "✅ Migration complete!"
echo "Now run: docker compose up -d"