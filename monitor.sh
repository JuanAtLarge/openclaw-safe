#!/usr/bin/env bash
# monitor.sh — OpenClaw Memory File Watcher
# Part of openclaw-safe: https://github.com/JuanAtLarge/openclaw-safe
#
# Watches ~/.openclaw/workspace memory files for suspicious prompt injection
# attempts in real-time. Read-only monitoring — never modifies files.
#
# Usage:
#   ./monitor.sh start    — start background daemon
#   ./monitor.sh stop     — stop daemon
#   ./monitor.sh status   — check if running
#   ./monitor.sh tail     — tail the log live
#   ./monitor.sh run      — run in foreground (for debugging)

set -euo pipefail

# ─── Config ───────────────────────────────────────────────────────────────────
WATCH_DIR="${HOME}/.openclaw/workspace"
MEMORY_DIR="${WATCH_DIR}/memory"
SAFE_DIR="${HOME}/.openclaw-safe"
LOG_FILE="${SAFE_DIR}/monitor.log"
PID_FILE="${SAFE_DIR}/monitor.pid"
POLL_INTERVAL="${POLL_INTERVAL:-30}"   # seconds between polls in fallback mode
RAPID_WRITE_THRESHOLD=5   # more than this many writes in 60s = alert
RAPID_WRITE_WINDOW=60     # seconds

# Suspicious patterns (case-insensitive, matched per line)
SUSPICIOUS_PATTERNS=(
  "remember to"
  "always "
  "never "
  "from now on"
  "ignore previous"
  "your new instructions"
  "system prompt"
  "you are now"
  "disregard"
  "forget everything"
  "new persona"
  "act as if"
  "pretend you are"
)

# ─── Colors ───────────────────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
BOLD='\033[1m'
RESET='\033[0m'

# ─── Helpers ──────────────────────────────────────────────────────────────────
log() { echo -e "$*"; }
ts()  { date "+%Y-%m-%d %H:%M:%S"; }

ensure_dirs() {
  mkdir -p "$SAFE_DIR"
  mkdir -p "$MEMORY_DIR" 2>/dev/null || true
  touch "$LOG_FILE"
}

write_log() {
  local level="$1"
  local msg="$2"
  echo "[$(ts)] [$level] $msg" >> "$LOG_FILE"
}

alert() {
  local msg="$1"
  local file="${2:-}"
  local line="${3:-}"

  # Log it
  write_log "ALERT" "$msg${file:+ | file: $file}${line:+ | match: $line}"

  # Print to terminal if in foreground
  if [[ "${FOREGROUND:-0}" == "1" ]]; then
    log ""
    log "${RED}${BOLD}🚨 ALERT:${RESET} $msg"
    [[ -n "$file" ]] && log "   ${YELLOW}File:${RESET} $file"
    [[ -n "$line" ]] && log "   ${YELLOW}Match:${RESET} $line"
    log ""
  fi

  # Try openclaw message if available (non-blocking)
  if command -v openclaw &>/dev/null 2>&1; then
    local full_msg="🚨 [openclaw-safe monitor] $msg"
    [[ -n "$file" ]] && full_msg+=" | File: $(basename "$file")"
    openclaw message send --target self --message "$full_msg" 2>/dev/null || true
  fi
}

# ─── Pattern checker ──────────────────────────────────────────────────────────
check_file_for_injection() {
  local file="$1"
  [[ ! -f "$file" ]] && return 0
  [[ ! -r "$file" ]] && return 0

  local found=0
  while IFS= read -r line; do
    local lower_line
    lower_line=$(echo "$line" | tr '[:upper:]' '[:lower:]')
    for pattern in "${SUSPICIOUS_PATTERNS[@]}"; do
      if [[ "$lower_line" == *"$pattern"* ]]; then
        alert "Suspicious instruction-like language detected" "$file" "$line"
        found=1
        break
      fi
    done

    # Also flag newly written bare URLs (http/https not in markdown link format)
    if echo "$line" | grep -qiE 'https?://[a-zA-Z0-9._/-]{10,}' 2>/dev/null; then
      # Only flag if it looks like an embedded/suspicious URL (not a normal markdown link)
      if ! echo "$line" | grep -qiE '^\s*[-*]?\s*\[.*\]\(https?://' 2>/dev/null; then
        if echo "$line" | grep -qiE 'https?://[a-zA-Z0-9._-]+\.[a-z]{2,}/[a-zA-Z0-9._/?=&%-]{5,}' 2>/dev/null; then
          alert "Embedded URL in memory file (possible exfil or injection)" "$file" "$(echo "$line" | cut -c1-120)"
          found=1
        fi
      fi
    fi
  done < "$file"

  return $found
}

# ─── Rapid write detection ────────────────────────────────────────────────────
# We track write timestamps in a simple file
RECENT_WRITES_FILE="${SAFE_DIR}/.monitor-recent-writes"

record_write() {
  local now
  now=$(date +%s)
  local cutoff=$((now - RAPID_WRITE_WINDOW))

  # Append current time
  echo "$now" >> "$RECENT_WRITES_FILE"

  # Prune old entries and count recent ones
  local count=0
  local tmp
  tmp=$(mktemp)
  while IFS= read -r ts_entry; do
    if [[ "$ts_entry" -ge "$cutoff" ]] 2>/dev/null; then
      echo "$ts_entry" >> "$tmp"
      count=$((count+1))
    fi
  done < <(cat "$RECENT_WRITES_FILE" 2>/dev/null || true)
  mv "$tmp" "$RECENT_WRITES_FILE"

  if [[ "$count" -gt "$RAPID_WRITE_THRESHOLD" ]]; then
    alert "Rapid writes detected: $count changes in ${RAPID_WRITE_WINDOW}s (possible injection loop)"
  fi
}

# ─── Snapshot for change detection (polling mode) ─────────────────────────────
SNAPSHOT_FILE="${SAFE_DIR}/.monitor-snapshot"

take_snapshot() {
  # Output: "<mtime_epoch> <filepath>" per .md file
  # Use find -newer trick: compare against a reference file
  find "$WATCH_DIR" -maxdepth 3 -name "*.md" 2>/dev/null | while IFS= read -r f; do
    # Get mtime in epoch seconds (macOS & Linux compatible)
    local mtime
    mtime=$(stat -f "%m" "$f" 2>/dev/null || stat -c "%Y" "$f" 2>/dev/null || echo "0")
    echo "${mtime} ${f}"
  done
}

check_changed_files() {
  local old_snap=""
  [[ -f "$SNAPSHOT_FILE" ]] && old_snap=$(cat "$SNAPSHOT_FILE")

  take_snapshot | while IFS=' ' read -r mtime filepath; do
    [[ -z "$filepath" ]] && continue

    # Look for this file in old snapshot
    local old_entry
    old_entry=$(echo "$old_snap" | grep -F " ${filepath}" 2>/dev/null | head -1 || true)

    if [[ -z "$old_entry" ]]; then
      # New file
      write_log "INFO" "New file detected: $filepath"
      record_write
      check_file_for_injection "$filepath"
    else
      # File existed — check if mtime changed
      local old_mtime
      old_mtime=$(echo "$old_entry" | awk '{print $1}')
      if [[ "$mtime" != "$old_mtime" ]]; then
        write_log "INFO" "Modified file detected: $filepath"
        record_write
        check_file_for_injection "$filepath"
      fi
    fi
  done

  # Save new snapshot
  take_snapshot > "$SNAPSHOT_FILE" 2>/dev/null || true
}

# ─── Main watch loop ──────────────────────────────────────────────────────────
run_monitor() {
  ensure_dirs
  write_log "INFO" "monitor.sh started (PID $$) — watching $WATCH_DIR"
  log "${GREEN}✓${RESET} Monitor started — watching ${BOLD}$WATCH_DIR${RESET}"
  log "  Log: $LOG_FILE"

  # Determine watch method
  local watch_method="poll"
  if [[ "$(uname)" == "Darwin" ]]; then
    if command -v fswatch &>/dev/null 2>&1; then
      watch_method="fswatch"
    else
      log "  ${YELLOW}⚠${RESET} fswatch not found — using polling mode (every ${POLL_INTERVAL}s)"
      log "  ${BLUE}ℹ${RESET} Install for real-time watching: brew install fswatch"
    fi
  else
    if command -v inotifywait &>/dev/null 2>&1; then
      watch_method="inotifywait"
    else
      log "  ${YELLOW}⚠${RESET} inotifywait not found — using polling mode (every ${POLL_INTERVAL}s)"
      log "  ${BLUE}ℹ${RESET} Install: sudo apt-get install inotify-tools"
    fi
  fi

  write_log "INFO" "Watch method: $watch_method"
  log "  ${BLUE}ℹ${RESET} Watch method: ${BOLD}$watch_method${RESET}"

  # Make sure memory dir exists
  mkdir -p "$MEMORY_DIR" 2>/dev/null || true

  if [[ "$watch_method" == "fswatch" ]]; then
    # Real-time via fswatch (macOS)
    # Initialize snapshot
    take_snapshot > "$SNAPSHOT_FILE" 2>/dev/null || true

    fswatch -r --event Created --event Updated --event Renamed \
      "$WATCH_DIR" 2>/dev/null | while IFS= read -r changed_file; do
      # Filter to only .md files
      if [[ "$changed_file" == *.md ]]; then
        write_log "INFO" "File event: $changed_file"
        record_write
        check_file_for_injection "$changed_file"
      fi
    done

  elif [[ "$watch_method" == "inotifywait" ]]; then
    # Real-time via inotifywait (Linux)
    take_snapshot > "$SNAPSHOT_FILE" 2>/dev/null || true

    inotifywait -m -r -e close_write,create,moved_to \
      --include '.*\.md$' \
      "$WATCH_DIR" 2>/dev/null | while IFS= read -r dir event file; do
      local changed_file="${dir}${file}"
      write_log "INFO" "File event: $event $changed_file"
      record_write
      check_file_for_injection "$changed_file"
    done

  else
    # Polling fallback
    take_snapshot > "$SNAPSHOT_FILE" 2>/dev/null || true

    while true; do
      sleep "$POLL_INTERVAL"
      check_changed_files
    done
  fi
}

# ─── Daemon management ────────────────────────────────────────────────────────
cmd_start() {
  ensure_dirs

  if [[ -f "$PID_FILE" ]]; then
    local existing_pid
    existing_pid=$(cat "$PID_FILE")
    if kill -0 "$existing_pid" 2>/dev/null; then
      log "${YELLOW}⚠${RESET} Monitor already running (PID $existing_pid)"
      log "  Run ${BOLD}./monitor.sh stop${RESET} first to restart"
      exit 1
    else
      rm -f "$PID_FILE"
    fi
  fi

  log ""
  log "${BOLD}╔══════════════════════════════════════════════════╗${RESET}"
  log "${BOLD}║      OpenClaw Memory Monitor 🦙👁️               ║${RESET}"
  log "${BOLD}╚══════════════════════════════════════════════════╝${RESET}"

  # Start daemon in background
  nohup bash "$0" run >> "$LOG_FILE" 2>&1 &
  local daemon_pid=$!
  echo "$daemon_pid" > "$PID_FILE"

  sleep 1  # Give it a moment to start

  if kill -0 "$daemon_pid" 2>/dev/null; then
    log "${GREEN}✓${RESET} Monitor started (PID $daemon_pid)"
    log "  Log:  $LOG_FILE"
    log "  Stop: ${BOLD}./monitor.sh stop${RESET}"
    log "  Tail: ${BOLD}./monitor.sh tail${RESET}"
  else
    log "${RED}✗${RESET} Monitor failed to start — check log: $LOG_FILE"
    rm -f "$PID_FILE"
    exit 1
  fi
  log ""
}

cmd_stop() {
  if [[ ! -f "$PID_FILE" ]]; then
    log "${YELLOW}⚠${RESET} Monitor is not running (no PID file)"
    exit 0
  fi

  local pid
  pid=$(cat "$PID_FILE")

  if kill -0 "$pid" 2>/dev/null; then
    kill "$pid" 2>/dev/null || true
    sleep 1
    if kill -0 "$pid" 2>/dev/null; then
      kill -9 "$pid" 2>/dev/null || true
    fi
    rm -f "$PID_FILE"
    write_log "INFO" "Monitor stopped"
    log "${GREEN}✓${RESET} Monitor stopped (PID $pid)"
  else
    rm -f "$PID_FILE"
    log "${YELLOW}⚠${RESET} Monitor was not running (stale PID $pid removed)"
  fi
}

cmd_status() {
  log ""
  log "${BOLD}OpenClaw Memory Monitor — Status${RESET}"
  log ""

  if [[ -f "$PID_FILE" ]]; then
    local pid
    pid=$(cat "$PID_FILE")
    if kill -0 "$pid" 2>/dev/null; then
      log "  ${GREEN}● Running${RESET} (PID $pid)"
      log "  Log:   $LOG_FILE"
      log "  Watch: $WATCH_DIR"
    else
      log "  ${RED}● Stopped${RESET} (stale PID file — run ${BOLD}./monitor.sh start${RESET})"
      rm -f "$PID_FILE"
    fi
  else
    log "  ${RED}● Not running${RESET}"
    log "  Start with: ${BOLD}./monitor.sh start${RESET}"
  fi

  if [[ -f "$LOG_FILE" ]]; then
    local alert_count
    alert_count=$(grep -c "\[ALERT\]" "$LOG_FILE" 2>/dev/null | tr -d '[:space:]' || echo "0")
    log ""
    log "  Total alerts logged: ${BOLD}${alert_count}${RESET}"
    if [[ "${alert_count}" -gt 0 ]] 2>/dev/null; then
      log "  ${YELLOW}Last alert:${RESET}"
      grep "\[ALERT\]" "$LOG_FILE" | tail -1 | sed 's/^/    /'
    fi
  fi
  log ""
}

cmd_tail() {
  ensure_dirs
  if [[ ! -f "$LOG_FILE" ]]; then
    log "${BLUE}ℹ${RESET} No log file yet — start monitor with: ${BOLD}./monitor.sh start${RESET}"
    exit 0
  fi
  log "${BOLD}Tailing: $LOG_FILE${RESET} (Ctrl+C to stop)"
  tail -f "$LOG_FILE"
}

cmd_run() {
  # Foreground mode — used by daemon via nohup
  export FOREGROUND=1
  run_monitor
}

# ─── Dispatch ─────────────────────────────────────────────────────────────────
COMMAND="${1:-help}"

case "$COMMAND" in
  start)  cmd_start ;;
  stop)   cmd_stop ;;
  status) cmd_status ;;
  tail)   cmd_tail ;;
  run)    cmd_run ;;
  help|--help|-h)
    log ""
    log "${BOLD}monitor.sh — OpenClaw Memory File Watcher${RESET}"
    log ""
    log "Usage:"
    log "  ./monitor.sh start    Start background daemon"
    log "  ./monitor.sh stop     Stop daemon"
    log "  ./monitor.sh status   Check if running + alert count"
    log "  ./monitor.sh tail     Live log tail"
    log ""
    log "Watches: $WATCH_DIR"
    log "Log:     $LOG_FILE"
    log ""
    log "Suspicious patterns flagged:"
    for p in "${SUSPICIOUS_PATTERNS[@]}"; do
      log "  - \"$p\""
    done
    log ""
    ;;
  *)
    log "${RED}Unknown command: $COMMAND${RESET}"
    log "Run ${BOLD}./monitor.sh help${RESET} for usage"
    exit 1
    ;;
esac
