# VM Health Check

A small shell script that assesses an Ubuntu virtual machine's health based on CPU, memory, and root-disk utilization.

Behavior
- Threshold: 60% (hard-coded in the script).
- If any of CPU, memory, or root-disk usage is strictly greater than 60% the VM is declared "NOT HEALTHY".
- Otherwise it is "HEALTHY".
- Exit codes:
  - 0 => HEALTHY
  - 1 => NOT HEALTHY
  - 2 => Usage/argument error

Requirements
- Tested on Ubuntu. Relies on /proc/stat, free, and df which are available on most Linux systems.

Usage
```bash
chmod +x "health check/vm_health_check.sh"
"health check/vm_health_check.sh"         # prints only "VM Health: HEALTHY" or "VM Health: NOT HEALTHY"
"health check/vm_health_check.sh" explain # prints the status plus CPU, memory, disk values and reasons
```

Examples
- Run once:
  "health check/vm_health_check.sh" explain

- Use in cron (run every 5 minutes):
  Add to crontab (`crontab -e`):
  */5 * * * * /path/to/"health check"/vm_health_check.sh >/var/log/vm_health_check.log 2>&1

Notes
- CPU sampling uses /proc/stat with a short 0.5s interval for a quick estimate.
- Memory uses the `available` field from `free` when present (more accurate than "used").
- Disk checks the root filesystem (`/`) usage only.
