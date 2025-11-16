// Performance tuning for low-resource hosts (2 vCPU / 2 GB RAM).
// These settings are appended to config.php by scripts/setup.sh.
$CFG->task_scheduled_concurrency_limit = 1;
$CFG->task_scheduled_max_runtime = 900; // 15 minutes per scheduled runner.
$CFG->task_adhoc_concurrency_limit = 1;
$CFG->task_adhoc_max_runtime = 900; // Keep adhoc runners short-lived.
$CFG->task_logmode = 2; // Only keep failing task logs to save I/O.
