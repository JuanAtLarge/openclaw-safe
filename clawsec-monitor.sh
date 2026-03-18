#!/usr/bin/env bash
# clawsec-monitor.sh — ClawSec Alert Wrapper
# Part of openclaw-safe: https://github.com/JuanAtLarge/openclaw-safe
#
# Watches ClawSec logs and fires interactive Telegram alerts with action buttons.
#
# Usage:
#   ./clawsec-monitor.sh start   — start background daemon
#   ./clawsec-monitor.sh stop    — stop daemon
#   ./clawsec-monitor.sh status  — show running state
#   ./clawsec-monitor.sh tail    — tail the monitor log

set -euo pipefail

# ─── Config ───────────────────────────────────────────────────────────────────
DAEMON_DIR="${HOME}/.openclaw-safe"
PID_FILE="${DAEMON_DIR}/clawsec-monitor.pid"
LOG_FILE="${DAEMON_DIR}/clawsec-monitor.log"
STATE_FILE="${DAEMON_DIR}/clawsec-monitor.state"
POLL_INTERVAL=30
CHAT_ID="YOUR_TELEGRAM_CHAT_ID"

# ClawSec log search paths (in priority order)
CLAWSEC_LOG_CANDIDATES=(
  "${HOME}/.clawsec/clawsec.log"
  "${HOME}/.clawsec/logs/clawsec.log"
  "${HOME}/.clawsec/logs/events.log"
  "/var/log/clawsec/clawsec.log"
  "/var/log/clawsec.log"
)

# ─── Colors ───────────────────────────────────────────────────────────────────
if [[ -t 1 ]]; then
  RED='\033[0;31m' GREEN='\033[0;32m' YELLOW='\033[1;33m'
  BLUE='\033[0;34m' BOLD='\033[1m' RESET='\033[0m'
else
  RED="" GREEN="" YELLOW="" BLUE="" BOLD="" RESET=""
fi

log()   { echo -e "$*"; }
info()  { echo -e "${BLUE}ℹ${RESET} $*"; }
ok()    { echo -e "${GREEN}✓${RESET} $*"; }
warn()  { echo -e "${YELLOW}⚠${RESET} $*"; }
error() { echo -e "${RED}✗${RESET} $*"; }

# ─── Helpers ──────────────────────────────────────────────────────────────────
daemon_log() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" >> "$LOG_FILE"
}

get_bot_token() {
  local config="${HOME}/.openclaw/openclaw.json"
  if [[ ! -f "$config" ]]; then
    echo ""
    return
  fi
  python3 -c "
import json, sys
try:
    with open('${config}') as f:
        d = json.load(f)
    print(d.get('channels', {}).get('telegram', {}).get('botToken', ''))
except:
    print('')
" 2>/dev/null || echo ""
}

find_clawsec_log() {
  # Check if clawsec is installed
  if ! command -v clawsec &>/dev/null && [[ ! -d "${HOME}/.clawsec" ]]; then
    echo ""
    return
  fi

  # Try to get log path from clawsec status output
  if command -v clawsec &>/dev/null; then
    local status_log
    status_log=$(clawsec status 2>/dev/null | grep -i "log" | grep -oE '[^ ]+\.log' | head -1 || true)
    if [[ -n "$status_log" && -f "$status_log" ]]; then
      echo "$status_log"
      return
    fi
  fi

  # Try known candidate paths
  for candidate in "${CLAWSEC_LOG_CANDIDATES[@]}"; do
    if [[ -f "$candidate" ]]; then
      echo "$candidate"
      return
    fi
  done

  # ClawSec installed but no log found yet — return sentinel
  echo "INSTALLED_NO_LOG"
}

send_telegram() {
  local payload="$1"
  local bot_token
  bot_token=$(get_bot_token)
  if [[ -z "$bot_token" ]]; then
    daemon_log "ERROR: No bot token found in openclaw.json"
    return 1
  fi
  curl -s -X POST "https://api.telegram.org/bot${bot_token}/sendMessage" \
    -H "Content-Type: application/json" \
    -d "$payload" >> "$LOG_FILE" 2>&1
}

send_config_tamper_alert() {
  local alert_time="$1"
  daemon_log "Sending config tamper alert for time: $alert_time"
  local payload
  payload=$(python3 -c "
import json
text = '''🚨 ClawSec Alert: Config Change Detected

Your OpenClaw config file was modified unexpectedly at ${alert_time}.
This could mean a skill or agent made unauthorized changes to your settings.'''
buttons = {'inline_keyboard': [[
  {'text': '🔄 Restore Backup', 'callback_data': 'clawsec:restore-config'},
  {'text': '👁 Show Diff', 'callback_data': 'clawsec:show-diff'},
  {'text': '✅ I Made This Change', 'callback_data': 'clawsec:acknowledge-config'}
]]}
print(json.dumps({
  'chat_id': '${CHAT_ID}',
  'text': text,
  'reply_markup': json.dumps(buttons)
}))
")
  send_telegram "$payload"
}

send_network_block_alert() {
  local blocked_url="$1"
  local alert_time="$2"
  daemon_log "Sending network block alert for URL: $blocked_url"
  local safe_url
  safe_url=$(python3 -c "import urllib.parse; print(urllib.parse.quote('${blocked_url}', safe=''))")
  local payload
  payload=$(python3 -c "
import json
url = '${blocked_url}'
text = '''🚨 ClawSec Alert: Blocked Network Call

ClawSec blocked your agent from making an unexpected network request to:
${blocked_url}

This could be a skill trying to send data to an external server.'''
buttons = {'inline_keyboard': [[
  {'text': '🔍 Investigate Skill', 'callback_data': 'clawsec:investigate:${safe_url}'},
  {'text': '🚫 Keep Blocked', 'callback_data': 'clawsec:acknowledge-block'},
  {'text': '📋 View Full Log', 'callback_data': 'clawsec:view-log'}
]]}
print(json.dumps({
  'chat_id': '${CHAT_ID}',
  'text': text,
  'reply_markup': json.dumps(buttons)
}))
")
  send_telegram "$payload"
}

# ─── Log Parsing ──────────────────────────────────────────────────────────────
parse_clawsec_log() {
  local log_file="$1"
  local last_line="$2"
  local current_lines
  current_lines=$(wc -l < "$log_file" 2>/dev/null || echo "0")

  if [[ "$current_lines" -le "$last_line" ]]; then
    echo "$last_line"
    return
  fi

  # Read new lines since last check
  local new_content
  new_content=$(tail -n "+$((last_line + 1))" "$log_file" 2>/dev/null || true)

  if [[ -z "$new_content" ]]; then
    echo "$current_lines"
    return
  fi

  daemon_log "Processing $((current_lines - last_line)) new log lines"

  # Detect config tampering (adjust patterns as ClawSec's actual log format becomes known)
  local tamper_patterns=(
    "config.*tamper"
    "openclaw\.json.*modified"
    "config.*changed.*unexpect"
    "ALERT.*config"
    "CONFIG_TAMPER"
    "file.*modified.*openclaw"
    "tamper.*detected"
  )
  for pattern in "${tamper_patterns[@]}"; do
    if echo "$new_content" | grep -qi "$pattern"; then
      local alert_time
      alert_time=$(date '+%I:%M%p')
      daemon_log "Config tamper pattern matched: $pattern"
      send_config_tamper_alert "$alert_time"
      break
    fi
  done

  # Detect blocked network calls
  local network_patterns=(
    "BLOCKED.*http"
    "network.*blocked"
    "unauthorized.*request"
    "blocked.*url"
    "NETWORK_BLOCK"
    "blocked.*call.*http"
  )
  for pattern in "${network_patterns[@]}"; do
    local matched_line
    matched_line=$(echo "$new_content" | grep -i "$pattern" | head -1 || true)
    if [[ -n "$matched_line" ]]; then
      # Try to extract URL from log line
      local blocked_url
      blocked_url=$(echo "$matched_line" | grep -oE 'https?://[^ ]+' | head -1 || echo "unknown URL")
      local alert_time
      alert_time=$(date '+%I:%M%p')
      daemon_log "Network block pattern matched: $pattern → $blocked_url"
      send_network_block_alert "$blocked_url" "$alert_time"
      break
    fi
  done

  echo "$current_lines"
}

# ─── Daemon Loop ──────────────────────────────────────────────────────────────
run_daemon() {
  mkdir -p "$DAEMON_DIR"
  daemon_log "=== ClawSec monitor started (PID $$) ==="

  # Check if ClawSec is installed
  local clawsec_log
  clawsec_log=$(find_clawsec_log)

  if [[ -z "$clawsec_log" ]]; then
    daemon_log "ClawSec not installed — monitor will wait and retry every ${POLL_INTERVAL}s"
  elif [[ "$clawsec_log" == "INSTALLED_NO_LOG" ]]; then
    daemon_log "ClawSec installed but no log file found yet — will keep checking"
  else
    daemon_log "Watching ClawSec log: $clawsec_log"
  fi

  # Load last-seen line count
  local last_line=0
  if [[ -f "$STATE_FILE" ]]; then
    last_line=$(cat "$STATE_FILE" 2>/dev/null || echo "0")
  fi

  while true; do
    # Re-discover log path each cycle (in case ClawSec gets installed after start)
    clawsec_log=$(find_clawsec_log)

    if [[ -z "$clawsec_log" ]]; then
      daemon_log "ClawSec not installed — skipping check"
    elif [[ "$clawsec_log" == "INSTALLED_NO_LOG" ]]; then
      daemon_log "ClawSec installed, waiting for log file to appear..."
    else
      local new_last_line
      new_last_line=$(parse_clawsec_log "$clawsec_log" "$last_line")
      if [[ "$new_last_line" != "$last_line" ]]; then
        echo "$new_last_line" > "$STATE_FILE"
        last_line="$new_last_line"
      fi
    fi

    sleep "$POLL_INTERVAL"
  done
}

# ─── Commands ─────────────────────────────────────────────────────────────────
cmd_start() {
  mkdir -p "$DAEMON_DIR"

  if [[ -f "$PID_FILE" ]]; then
    local existing_pid
    existing_pid=$(cat "$PID_FILE")
    if kill -0 "$existing_pid" 2>/dev/null; then
      warn "ClawSec monitor already running (PID $existing_pid)"
      return 0
    else
      info "Stale PID file found — cleaning up"
      rm -f "$PID_FILE"
    fi
  fi

  # Check if ClawSec installed; warn but don't block
  local clawsec_log
  clawsec_log=$(find_clawsec_log)
  if [[ -z "$clawsec_log" ]]; then
    warn "ClawSec not installed — run ./install-clawsec.sh first"
    warn "Monitor will start anyway and wait for ClawSec to be installed"
  fi

  # Verify bot token is available
  local bot_token
  bot_token=$(get_bot_token)
  if [[ -z "$bot_token" ]]; then
    warn "No Telegram bot token found in ~/.openclaw/openclaw.json"
    warn "Alerts will be logged but not sent until token is available"
  fi

  # Start daemon in background
  nohup bash "$0" _daemon >> "$LOG_FILE" 2>&1 &
  local pid=$!
  echo "$pid" > "$PID_FILE"

  sleep 1
  if kill -0 "$pid" 2>/dev/null; then
    ok "ClawSec monitor started (PID $pid)"
    info "Log: $LOG_FILE"
    if [[ -z "$clawsec_log" ]]; then
      info "Waiting for ClawSec install — run ./install-clawsec.sh to enable alerts"
    fi
  else
    error "Monitor failed to start — check $LOG_FILE"
    rm -f "$PID_FILE"
    return 1
  fi
}

cmd_stop() {
  if [[ ! -f "$PID_FILE" ]]; then
    warn "No PID file found — monitor may not be running"
    return 0
  fi

  local pid
  pid=$(cat "$PID_FILE")

  if kill -0 "$pid" 2>/dev/null; then
    kill "$pid"
    sleep 1
    if kill -0 "$pid" 2>/dev/null; then
      kill -9 "$pid" 2>/dev/null || true
    fi
    rm -f "$PID_FILE"
    ok "ClawSec monitor stopped (was PID $pid)"
  else
    warn "Process $pid not running — cleaning up stale PID file"
    rm -f "$PID_FILE"
  fi
}

cmd_status() {
  log ""
  log "${BOLD}ClawSec Monitor Status${RESET}"
  log "────────────────────────"

  if [[ -f "$PID_FILE" ]]; then
    local pid
    pid=$(cat "$PID_FILE")
    if kill -0 "$pid" 2>/dev/null; then
      ok "Running (PID $pid)"
    else
      warn "PID file exists (PID $pid) but process not running"
    fi
  else
    warn "Not running"
  fi

  # ClawSec status
  local clawsec_log
  clawsec_log=$(find_clawsec_log 2>/dev/null || echo "")
  if [[ -z "$clawsec_log" ]]; then
    warn "ClawSec: not installed"
  elif [[ "$clawsec_log" == "INSTALLED_NO_LOG" ]]; then
    ok "ClawSec: installed (no log file yet)"
  else
    ok "ClawSec: installed, watching $clawsec_log"
  fi

  # Log file
  if [[ -f "$LOG_FILE" ]]; then
    local log_lines
    log_lines=$(wc -l < "$LOG_FILE")
    info "Monitor log: $LOG_FILE ($log_lines lines)"
  else
    info "Monitor log: not created yet"
  fi

  # Last seen state
  if [[ -f "$STATE_FILE" ]]; then
    local last_line
    last_line=$(cat "$STATE_FILE")
    info "Last processed line: $last_line"
  fi

  log ""
}

cmd_tail() {
  if [[ ! -f "$LOG_FILE" ]]; then
    warn "No log file yet at $LOG_FILE"
    return 0
  fi
  tail -f "$LOG_FILE"
}

# ─── Main ─────────────────────────────────────────────────────────────────────
COMMAND="${1:-help}"

case "$COMMAND" in
  start)   cmd_start ;;
  stop)    cmd_stop ;;
  status)  cmd_status ;;
  tail)    cmd_tail ;;
  _daemon) run_daemon ;;
  help|--help|-h)
    log ""
    log "${BOLD}clawsec-monitor.sh${RESET} — ClawSec alert wrapper"
    log ""
    log "Usage: ./clawsec-monitor.sh <command>"
    log ""
    log "Commands:"
    log "  start   Start the background monitor daemon"
    log "  stop    Stop the daemon"
    log "  status  Show current status"
    log "  tail    Follow the monitor log"
    log ""
    log "Alerts fire as Telegram messages with inline buttons."
    log "Requires ClawSec to be installed (./install-clawsec.sh)."
    log ""
    ;;
  *)
    error "Unknown command: $COMMAND"
    log "Usage: ./clawsec-monitor.sh start|stop|status|tail"
    exit 1
    ;;
esac
