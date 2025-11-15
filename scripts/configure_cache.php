#!/usr/bin/env php
<?php
declare(strict_types=1);

use core_cache\config_writer;

define('CLI_SCRIPT', true);

$configPath = getenv('MOODLE_CONFIG_PATH') ?: '/var/www/html/config.php';
if (!file_exists($configPath)) {
    fwrite(STDOUT, "ℹ️ Moodle config.php not found, skipping Redis cache bootstrap for now.\n");
    exit(0);
}

require_once($configPath);
$dirroot = getenv('MOODLE_DIRROOT') ?: ($CFG->dirroot ?? '/var/www/html');
if (empty($dirroot) || strpos($dirroot, '[dirroot]') !== false) {
    $dirroot = '/var/www/html';
}
if (!is_dir($dirroot)) {
    fwrite(STDOUT, "ℹ️ Moodle dirroot '{$dirroot}' not available yet, skipping Redis cache bootstrap.\n");
    exit(0);
}

$cacheLib = $dirroot . '/cache/lib.php';
$redisLib = $dirroot . '/cache/stores/redis/lib.php';
if (!is_file($cacheLib) || !is_file($redisLib)) {
    fwrite(STDOUT, "ℹ️ Cache libraries not found under {$dirroot}, skipping Redis cache bootstrap.\n");
    exit(0);
}

require_once($cacheLib);
require_once($redisLib);

$redisEnabled = getenv('ENABLE_REDIS_SESSION');
if ($redisEnabled !== false && (string)$redisEnabled === '0') {
    fwrite(STDOUT, "ℹ️ Redis cache bootstrap skipped (ENABLE_REDIS_SESSION=0)\n");
    exit(0);
}

$redisHost = getenv('REDIS_HOST') ?: 'redis';
$redisPort = (int)(getenv('REDIS_PORT') ?: 6379);
$redisPassword = getenv('REDIS_PASSWORD') ?: '';
$redisDb = (int)(getenv('REDIS_DB') ?: 0);
$redisPrefix = getenv('REDIS_CACHE_PREFIX');
if ($redisPrefix === false || $redisPrefix === '') {
    $redisPrefix = getenv('REDIS_PREFIX') ?: 'moodle';
}
$redisConnectionTimeout = (float)(getenv('REDIS_TIMEOUT') ?: 3.0);
$redisReadTimeout = (float)(getenv('REDIS_READ_TIMEOUT') ?: 3.0);
$redisLockTimeout = (int)(getenv('REDIS_SESSION_LOCK_TIMEOUT') ?: 120);
$redisLockRetry = (int)(getenv('REDIS_SESSION_LOCK_WAIT') ?: 100);
$redisLockExpire = (int)(getenv('REDIS_SESSION_LOCK_EXPIRE') ?: 7200);
$redisLockWarn = (int)(getenv('REDIS_SESSION_LOCK_WARN') ?: 0);

$serverList = $redisHost;
if (strpos($redisHost, ':') === false) {
    $serverList = $redisHost . ':' . $redisPort;
}

// --- Configure Redis sessions ---
set_config('session_handler_class', '\\core\\session\\redis');
set_config('session_redis_host', $redisHost);
set_config('session_redis_port', $redisPort);
set_config('session_redis_database', $redisDb);
set_config('session_redis_prefix', sprintf('%s_sess_', $redisPrefix));
set_config('session_redis_connection_timeout', max(1, (int)$redisConnectionTimeout));
set_config('session_redis_acquire_lock_timeout', $redisLockTimeout);
set_config('session_redis_lock_retry', max(1, $redisLockRetry));
set_config('session_redis_lock_expire', max(300, $redisLockExpire));
if ($redisLockWarn > 0) {
    set_config('session_redis_acquire_lock_warn', $redisLockWarn);
}
if ($redisPassword !== '') {
    set_config('session_redis_auth', $redisPassword);
}
if ($redisReadTimeout > 0) {
    set_config('session_redis_max_retries', 3);
}

// --- Configure Moodle Universal Cache (MUC) ---
config_writer::update_definitions();
$writer = config_writer::instance();

$storeName = getenv('REDIS_MUC_STORE') ?: 'redis_shared';
$storeConfig = [
    'server' => $serverList,
    'prefix' => sprintf('%s_muc_%d_', $redisPrefix, $redisDb),
    'password' => $redisPassword,
    'serializer' => defined('Redis::SERIALIZER_IGBINARY') ? Redis::SERIALIZER_IGBINARY : Redis::SERIALIZER_PHP,
    'compressor' => cachestore_redis::COMPRESSOR_NONE,
    'connectiontimeout' => max(1, (int)$redisConnectionTimeout),
    'clustermode' => false,
];

try {
    $writer->edit_store_instance($storeName, 'redis', $storeConfig);
    fwrite(STDOUT, "✅ Updated existing Redis cache store '{$storeName}'.\n");
} catch (Throwable $exception) {
    $writer->add_store_instance($storeName, 'redis', $storeConfig);
    fwrite(STDOUT, "✅ Added Redis cache store '{$storeName}'.\n");
}

$writer->set_mode_mappings([
    \cache_store::MODE_APPLICATION => [$storeName, 'default_application'],
    \cache_store::MODE_SESSION => [$storeName, 'default_session'],
    \cache_store::MODE_REQUEST => ['default_request'],
]);

$definitionsToMap = [
    'core/config',
    'core/string',
    'core/langmenu',
    'core/htmlpurifier',
    'core/plugin_manager',
    'core/plugin_functions',
    'core/yuimodules',
    'core/questiondata',
    'core/grade_categories',
    'core/grade_letters',
    'core/gradesetting',
    'core/theme_usedincontext',
];

foreach ($definitionsToMap as $definition) {
    try {
        $writer->set_definition_mappings($definition, [$storeName]);
    } catch (Throwable $definitionError) {
        fwrite(STDOUT, "⚠️  Unable to map cache '{$definition}': {$definitionError->getMessage()}\n");
    }
}

fwrite(STDOUT, "🎯 Redis cache configuration applied.\n");
