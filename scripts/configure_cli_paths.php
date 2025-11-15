#!/usr/bin/env php
<?php
declare(strict_types=1);

define('CLI_SCRIPT', true);

$configPath = getenv('MOODLE_CONFIG_PATH') ?: '/var/www/html/config.php';
if (!is_file($configPath)) {
    fwrite(STDOUT, "ℹ️ config.php not found, skipping CLI path bootstrap.\n");
    exit(0);
}

require_once($configPath);
$dirroot = getenv('MOODLE_DIRROOT') ?: ($CFG->dirroot ?? '/var/www/html');
if (!is_dir($dirroot)) {
    fwrite(STDOUT, "ℹ️ Moodle dirroot '{$dirroot}' missing, skipping CLI path bootstrap.\n");
    exit(0);
}

require_once($dirroot . '/lib/dml/moodle_database.php');

$settings = [
    'pathtophp' => getenv('MOODLE_PATH_TO_PHP') ?: '/usr/local/bin/php',
    'pathtodu' => getenv('MOODLE_PATH_TO_DU') ?: '/usr/bin/du',
    'aspellpath' => getenv('MOODLE_ASPELL_PATH') ?: '/usr/bin/aspell',
    'pathtodot' => getenv('MOODLE_PATH_TO_DOT') ?: '/usr/bin/dot',
    'pathtogs' => getenv('MOODLE_PATH_TO_GS') ?: '/usr/bin/gs',
    'pathtopdftoppm' => getenv('MOODLE_PATH_TO_PDFTOPPM') ?: '/usr/bin/pdftoppm',
];

foreach ($settings as $key => $value) {
    if (!empty($value)) {
        set_config($key, $value);
    }
}

fwrite(STDOUT, "🛠  CLI path configuration applied.\n");
