#!/usr/bin/env php
<?php
declare(strict_types=1);

// Portable Moodle cron runner that uses PHP CLI only.
// Can run inside Docker (default paths) or on a remote server with env overrides.

$configPath = getenv('MOODLE_CONFIG_PATH') ?: '/var/www/html/config.php';
$cronScript = getenv('MOODLE_CRON_SCRIPT') ?: '/var/www/html/admin/cli/cron.php';
$interval = (int)(getenv('MOODLE_CRON_INTERVAL') ?: 60);
$phpBinary = getenv('PHP_BIN') ?: PHP_BINARY;

if ($interval < 5) {
    $interval = 5;
}

echo "🕒 Starting Moodle cron watchdog (PHP CLI)...\n";

while (!is_file($configPath)) {
    echo "⏳ Waiting for {$configPath} ...\n";
    sleep(10);
}

echo "✅ Moodle config detected. Cron loop starting.\n";

while (true) {
    $started = microtime(true);
    $cmd = escapeshellcmd($phpBinary) . ' ' . escapeshellarg($cronScript);
    passthru($cmd, $status);
    if ($status !== 0) {
        echo "⚠️  cron.php exited with status {$status}\n";
    }
    $elapsed = (int)ceil(microtime(true) - $started);
    $sleep = $interval - $elapsed;
    if ($sleep > 0) {
        sleep($sleep);
    }
}
