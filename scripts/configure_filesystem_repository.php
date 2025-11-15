#!/usr/bin/env php
<?php
declare(strict_types=1);

define('CLI_SCRIPT', true);

$configPath = getenv('MOODLE_CONFIG_PATH') ?: '/var/www/html/config.php';
if (!is_file($configPath)) {
    fwrite(STDOUT, "ℹ️ config.php not found, skipping filesystem repository bootstrap.\n");
    exit(0);
}

require_once($configPath);
$dirroot = getenv('MOODLE_DIRROOT') ?: ($CFG->dirroot ?? '/var/www/html');
if (!is_dir($dirroot)) {
    fwrite(STDOUT, "ℹ️ Moodle dirroot '{$dirroot}' missing, skipping filesystem repository bootstrap.\n");
    exit(0);
}

$enable = getenv('MOODLE_ENABLE_FILESYSTEM_REPOSITORY');
if ($enable !== false && (string)$enable === '0') {
    fwrite(STDOUT, "ℹ️ Filesystem repository bootstrap disabled (MOODLE_ENABLE_FILESYSTEM_REPOSITORY=0).\n");
    exit(0);
}

set_config('filesystem', 1, 'repository_plugins_enabled');

set_config('enablecourseinstances', 1, 'repository_filesystem');
set_config('enableuserinstances', 1, 'repository_filesystem');

fwrite(STDOUT, "📁 Filesystem repository enabled for courses and personal use.\n");
