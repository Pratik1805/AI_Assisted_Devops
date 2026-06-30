#!/usr/bin/env bash
# vm_health_check.sh
# Usage: ./vm_health_check.sh [explain]
# If any of CPU, Memory, or Disk usage is > 60%, the VM is declared "NOT HEALTHY".
# Otherwise the VM is "HEALTHY".
# Pass "explain" (or --explain / -e) to print reason details.

set -euo pipefail

THRESHOLD=60

print_usage() {
  echo "Usage: $0 [explain]"
  echo "  explain    Show the metric values and the reason for the health status"
}

# CPU usage computed from /proc/stat over a short interval
get_cpu_usage() {
  # Read first line of /proc/stat
  read -r _ user nice system idle iowait irq softirq steal guest guest_nice < /proc/stat
  prev_idle=$((idle + iowait))
  prev_total=$((user + nice + system + idle + iowait + irq + softirq + steal + guest + guest_nice))

  sleep 0.5

  read -r _ user nice system idle iowait irq softirq steal guest guest_nice < /proc/stat
  idle=$((idle + iowait))
  total=$((user + nice + system + idle + iowait + irq + softirq + steal + guest + guest_nice))

  diff_idle=$((idle - prev_idle))
  diff_total=$((total - prev_total))

  if [ "$diff_total" -le 0 ]; then
    echo "0.0"
    return
  fi

  # compute usage percent as float with one decimal
  awk -v di="$diff_idle" -v dt="$diff_total" 'BEGIN { printf "%.1f", (1 - di/dt) * 100 }'
}

# Memory usage using "available" field (modern free output)
get_mem_usage() {
  # total and available in kB
  read -r _ total used free shared buff_cache available < <(free -k | awk '/^Mem:/ {print $1, $2, $3, $4, $6, $7}')
  # if "available" not present fallback to used/total
  if [ -z "${available:-}" ]; then
    # fallback: used / total * 100 (less accurate)
    awk -v t="$total" -v u="$used" 'BEGIN { if (t==0) print "0.0"; else printf "%.1f", (u/t)*100 }'
  else
    used_calc=$((total - available))
    awk -v t="$total" -v u="$used_calc" 'BEGIN { if (t==0) print "0.0"; else printf "%.1f", (u/t)*100 }'
  fi
}

# Disk usage for root filesystem "/"
get_disk_usage() {
  # Use POSIX df output and extract usage percent for "/"
  percent=$(df -P / | awk 'NR==2 {gsub(/%/,"",$5); print $5}')
  # ensure we always return a float like 23.0
  awk -v p="$percent" 'BEGIN { if (p=="") print "0.0"; else printf "%.1f", p }'
}

# Parse explain arg
EXPLAIN=false
if [ $# -gt 1 ]; then
  print_usage
  exit 2
fi
if [ $# -eq 1 ]; then
  case "$1" in
    explain|--explain|-e) EXPLAIN=true ;;
    -h|--help) print_usage; exit 0 ;;
    *) echo "Unknown argument: $1"; print_usage; exit 2 ;;
  esac
fi

cpu=$(get_cpu_usage)
mem=$(get_mem_usage)
disk=$(get_disk_usage)

# Decide health: if any metric is strictly greater than THRESHOLD => NOT HEALTHY
is_unhealthy=false
# Use awk for float comparison
if awk -v v="$cpu" -v t="$THRESHOLD" 'BEGIN { exit (v > t ? 0 : 1) }'; then
  cpu_flag=true
else
  cpu_flag=false
fi
if awk -v v="$mem" -v t="$THRESHOLD" 'BEGIN { exit (v > t ? 0 : 1) }'; then
  mem_flag=true
else
  mem_flag=false
fi
if awk -v v="$disk" -v t="$THRESHOLD" 'BEGIN { exit (v > t ? 0 : 1) }'; then
  disk_flag=true
else
  disk_flag=false
fi

if [ "$cpu_flag" = true ] || [ "$mem_flag" = true ] || [ "$disk_flag" = true ]; then
  HEALTH="NOT HEALTHY"
  is_unhealthy=true
else
  HEALTH="HEALTHY"
fi

# Print summary
echo "VM Health: $HEALTH"

# If explain requested, show details and reasons
if [ "$EXPLAIN" = true ]; then
  echo "Details (threshold: > ${THRESHOLD}% => NOT HEALTHY):"
  printf "  CPU usage:    %5s%% %s\n" "$cpu" "$( [ \"$cpu_flag\" = true ] && echo '(exceeds threshold)' || echo '(ok)' )"
  printf "  Memory usage: %5s%% %s\n" "$mem" "$( [ \"$mem_flag\" = true ] && echo '(exceeds threshold)' || echo '(ok)' )"
  printf "  Disk usage (/):%5s%% %s\n" "$disk" "$( [ \"$disk_flag\" = true ] && echo '(exceeds threshold)' || echo '(ok)' )"

  if [ "$is_unhealthy" = true ]; then
    echo "Reason: One or more resources exceed ${THRESHOLD}% usage."
    echo "  - Tip: investigate processes (top/htop), memory usage (free -h), and large files (du -sh /var/*)."
  else
    echo "Reason: All monitored resources are at or below ${THRESHOLD}% usage."
  fi
fi

# Exit code: 0 == healthy, 1 == not healthy
if [ "$is_unhealthy" = true ]; then
  exit 1
else
  exit 0
fi
