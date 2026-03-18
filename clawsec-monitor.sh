#!/usr/bin/env bash
# clawsec-monitor.sh — ClawSec Alert Wrapper (v7 — Auto-Resolve)
# Part of openclaw-safe: https://github.com/JuanAtLarge/openclaw-safe
#
# Watches ClawSec logs and auto-investigates, auto-quarantines, then sends
# plain-English Telegram alerts with one-tap resolution buttons.
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
ALERTS_FILE="${DAEMON_DIR}/alerts.json"
QUARANTINE_DIR="${DAEMON_DIR}/quarantine"
POLL_INTERVAL=30
CHAT_ID=$(python3 -c "
import json, os
try:
    creds = json.load(open(os.path.expanduser('~/.openclaw/credentials/telegram-default-allowFrom.json')))
    print(creds['allowFrom'][0])
except:
    print('')
" 2>/dev/null || true)

# ClawSec log search paths (in priority order)
CLAWSEC_LOG_CANDIDATES=(
  "${HOME}/.clawsec/clawsec.log"
  "${HOME}/.clawsec/logs/clawsec.log"
  "${HOME}/.clawsec/logs/events.log"
  "/var/log/clawsec/clawsec.log"
  "/var/log/clawsec.log"
)

# Skill directories to search
SKILL_DIRS=(
  "${HOME}/.agents/skills"
  "${HOME}/.openclaw/workspace/skills"
  "${HOME}/.npm-global/lib/node_modules/openclaw/skills"
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
  if ! command -v clawsec &>/dev/null && [[ ! -d "${HOME}/.clawsec" ]]; then
    echo ""
    return
  fi

  if command -v clawsec &>/dev/null; then
    local status_log
    status_log=$(clawsec status 2>/dev/null | grep -i "log" | grep -oE '[^ ]+\.log' | head -1 || true)
    if [[ -n "$status_log" && -f "$status_log" ]]; then
      echo "$status_log"
      return
    fi
  fi

  for candidate in "${CLAWSEC_LOG_CANDIDATES[@]}"; do
    if [[ -f "$candidate" ]]; then
      echo "$candidate"
      return
    fi
  done

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

# ─── Alert State Tracking ─────────────────────────────────────────────────────

# Generate a unique alert ID
make_alert_id() {
  echo "alert-$(date '+%Y%m%d-%H%M%S')"
}

# Append a new alert to alerts.json (append-only — never delete)
log_alert() {
  local id="$1"
  local type="$2"        # config-tamper | blocked-network-call
  local description="$3"
  local skill="${4:-}"
  local detected_at
  detected_at=$(date -u '+%Y-%m-%dT%H:%M:%SZ')

  mkdir -p "$DAEMON_DIR"

  python3 -c "
import json, os, sys

alerts_file = '${ALERTS_FILE}'
new_alert = {
    'id': '${id}',
    'type': '${type}',
    'detectedAt': '${detected_at}',
    'description': '''${description}''',
    'status': 'open',
    'resolvedAt': None,
    'resolution': None,
    'skill': '''${skill}''' if '''${skill}''' else None
}

# Load existing (handle malformed gracefully)
alerts = []
if os.path.exists(alerts_file):
    try:
        with open(alerts_file) as f:
            content = f.read().strip()
            if content:
                alerts = json.loads(content)
        if not isinstance(alerts, list):
            alerts = []
    except (json.JSONDecodeError, Exception) as e:
        print(f'Warning: alerts.json malformed, starting fresh: {e}', file=sys.stderr)
        alerts = []

alerts.append(new_alert)

with open(alerts_file, 'w') as f:
    json.dump(alerts, f, indent=2)
" 2>> "$LOG_FILE" || daemon_log "WARNING: Failed to write alert to alerts.json"
}

# Update an alert's status (by matching open alerts of given type)
update_alert_status() {
  local alert_id="$1"
  local new_status="$2"
  local resolution="${3:-}"

  if [[ ! -f "$ALERTS_FILE" ]]; then
    return
  fi

  python3 -c "
import json, os, sys
from datetime import datetime, timezone

alerts_file = '${ALERTS_FILE}'
alert_id = '${alert_id}'
new_status = '${new_status}'
resolution = '${resolution}' or None
resolved_at = datetime.now(timezone.utc).strftime('%Y-%m-%dT%H:%M:%SZ') if new_status in ('resolved', 'acknowledged') else None

alerts = []
try:
    with open(alerts_file) as f:
        alerts = json.load(f)
    if not isinstance(alerts, list):
        alerts = []
except Exception as e:
    print(f'Error reading alerts.json: {e}', file=sys.stderr)
    sys.exit(0)

updated = False
for alert in alerts:
    if alert.get('id') == alert_id:
        alert['status'] = new_status
        if resolved_at:
            alert['resolvedAt'] = resolved_at
        if resolution:
            alert['resolution'] = resolution
        updated = True

with open(alerts_file, 'w') as f:
    json.dump(alerts, f, indent=2)

if updated:
    print(f'Alert {alert_id} updated to {new_status}')
else:
    print(f'Alert {alert_id} not found')
" 2>> "$LOG_FILE" || true
}

# Get most recently open alert of a given type
get_open_alert_id() {
  local type="$1"
  if [[ ! -f "$ALERTS_FILE" ]]; then
    echo ""
    return
  fi
  python3 -c "
import json, sys
try:
    with open('${ALERTS_FILE}') as f:
        alerts = json.load(f)
    if not isinstance(alerts, list):
        sys.exit(0)
    # Find most recent open alert of given type
    matches = [a for a in alerts if a.get('type') == '${type}' and a.get('status') == 'open']
    if matches:
        print(matches[-1]['id'])
except:
    pass
" 2>/dev/null || echo ""
}

# ─── Config Diff Logic ────────────────────────────────────────────────────────

# Find the most recent backup file
find_latest_backup() {
  local config_dir="${HOME}/.openclaw"
  local latest=""
  local latest_time=0

  for f in "${config_dir}"/openclaw.json.backup.*; do
    [[ -f "$f" ]] || continue
    local mtime
    mtime=$(stat -f "%m" "$f" 2>/dev/null || stat -c "%Y" "$f" 2>/dev/null || echo "0")
    if [[ "$mtime" -gt "$latest_time" ]]; then
      latest_time="$mtime"
      latest="$f"
    fi
  done

  echo "$latest"
}

# Parse JSON diff into plain English
diff_configs_plain_english() {
  local current="$1"
  local backup="$2"

  python3 -c "
import json, sys

def load_json(path):
    try:
        with open(path) as f:
            return json.load(f)
    except Exception as e:
        return None

def flatten(obj, prefix=''):
    items = {}
    if isinstance(obj, dict):
        for k, v in obj.items():
            new_key = f'{prefix}.{k}' if prefix else k
            if isinstance(v, (dict, list)):
                items.update(flatten(v, new_key))
            else:
                items[new_key] = v
    elif isinstance(obj, list):
        items[prefix] = json.dumps(obj)
    else:
        items[prefix] = obj
    return items

current = load_json('${current}')
backup = load_json('${backup}')

if not current or not backup:
    print('→ Could not parse config files for diff')
    sys.exit(0)

curr_flat = flatten(current)
back_flat = flatten(backup)

changes = []

# Fields removed (in backup but not current)
for key in back_flat:
    if key not in curr_flat:
        changes.append(f'→ {key} was removed (was: {back_flat[key]})')

# Fields added (in current but not backup)
for key in curr_flat:
    if key not in back_flat:
        changes.append(f'→ {key} was added (value: {curr_flat[key]})')

# Fields changed
for key in curr_flat:
    if key in back_flat and str(curr_flat[key]) != str(back_flat[key]):
        changes.append(f'→ {key} changed from {back_flat[key]} to {curr_flat[key]}')

if changes:
    print('\n'.join(changes[:10]))  # Cap at 10 changes
    if len(changes) > 10:
        print(f'→ ... and {len(changes) - 10} more changes')
else:
    print('→ Files appear identical (timing-based false positive?)')
" 2>/dev/null || echo "→ Could not diff config files"
}

# ─── Alert Senders ────────────────────────────────────────────────────────────

send_config_tamper_alert() {
  local alert_time="$1"

  daemon_log "Auto-investigating config tamper..."

  # Find backup
  local backup
  backup=$(find_latest_backup)

  local changes_text
  local backup_ts=""

  if [[ -z "$backup" ]]; then
    changes_text="→ No backup found to compare against"
    daemon_log "No backup file found for diff"
  else
    # Extract timestamp from backup filename
    backup_ts=$(basename "$backup" | sed 's/openclaw\.json\.backup\.//')
    daemon_log "Diffing against backup: $backup"
    changes_text=$(diff_configs_plain_english "${HOME}/.openclaw/openclaw.json" "$backup")
    daemon_log "Diff result: $changes_text"
  fi

  # Log alert
  local alert_id
  alert_id=$(make_alert_id)
  local short_desc
  short_desc=$(echo "$changes_text" | head -3 | tr '\n' ' ' | cut -c1-120)
  log_alert "$alert_id" "config-tamper" "$short_desc" ""
  daemon_log "Alert logged: $alert_id"

  # Build message text
  local msg_text
  if [[ -n "$backup_ts" ]]; then
    msg_text="🚨 Your OpenClaw config was modified unexpectedly.

Here's what changed:
${changes_text}

This could mean a skill changed your security settings.

Alert ID: ${alert_id}"
  else
    msg_text="🚨 Your OpenClaw config was modified unexpectedly at ${alert_time}.

${changes_text}

This could mean a skill changed your security settings.

Alert ID: ${alert_id}"
  fi

  local payload
  payload=$(python3 -c "
import json, sys

text = '''${msg_text}'''
buttons = {'inline_keyboard': [[
  {'text': '🔄 Restore Original', 'callback_data': 'clawsec:restore-config'},
  {'text': '✅ Keep These Changes', 'callback_data': 'clawsec:keep-config'}
]]}
print(json.dumps({
  'chat_id': '${CHAT_ID}',
  'text': text,
  'reply_markup': json.dumps(buttons)
}))
" 2>/dev/null)

  if [[ -n "$payload" ]]; then
    send_telegram "$payload"
    daemon_log "Config tamper alert sent (alert_id=$alert_id)"
  else
    daemon_log "ERROR: Failed to build config tamper payload"
  fi
}

# Search all installed skills for a URL or domain reference
find_skill_for_url() {
  local url="$1"
  # Extract domain from URL
  local domain
  domain=$(python3 -c "
from urllib.parse import urlparse
import sys
try:
    parsed = urlparse('${url}')
    print(parsed.netloc or parsed.path.split('/')[0])
except:
    print('${url}')
" 2>/dev/null || echo "$url")

  daemon_log "Searching skills for references to: $url (domain: $domain)"

  for skill_dir in "${SKILL_DIRS[@]}"; do
    [[ -d "$skill_dir" ]] || continue
    # Search all files in skill directories
    local match
    match=$(grep -rl --include="*.sh" --include="*.md" --include="*.js" --include="*.ts" --include="*.json" \
      -e "$domain" -e "$url" "$skill_dir" 2>/dev/null | head -1 || true)

    if [[ -n "$match" ]]; then
      # Extract skill name (first component under skill_dir)
      local rel_path="${match#$skill_dir/}"
      local skill_name="${rel_path%%/*}"
      daemon_log "Found skill: $skill_name in $skill_dir (file: $match)"
      echo "$skill_name:$skill_dir"
      return
    fi
  done

  echo ""
}

# Quarantine a skill immediately (no prompt — unauthorized network calls are serious)
auto_quarantine_skill() {
  local skill_name="$1"
  local skill_dir="$2"
  local full_path="${skill_dir}/${skill_name}"

  if [[ ! -d "$full_path" && ! -f "$full_path" ]]; then
    daemon_log "WARNING: Cannot quarantine $skill_name — path not found: $full_path"
    return 1
  fi

  mkdir -p "$QUARANTINE_DIR"

  local ts
  ts=$(date '+%Y%m%d-%H%M%S')
  local quarantine_dest="${QUARANTINE_DIR}/${skill_name}.quarantined.${ts}"

  # Record origin for restore
  local metadata_file="${QUARANTINE_DIR}/${skill_name}.quarantined.${ts}.meta"

  daemon_log "Auto-quarantining $skill_name from $full_path → $quarantine_dest"

  mv "$full_path" "$quarantine_dest" 2>> "$LOG_FILE" || {
    daemon_log "ERROR: Failed to move $full_path to quarantine"
    return 1
  }

  # Write metadata for restore
  cat > "$metadata_file" << EOF
skill_name=${skill_name}
original_path=${full_path}
quarantine_path=${quarantine_dest}
quarantined_at=$(date -u '+%Y-%m-%dT%H:%M:%SZ')
reason=auto-quarantine-blocked-network-call
EOF

  daemon_log "Quarantined $skill_name successfully (metadata: $metadata_file)"
  echo "$quarantine_dest"
}

send_network_block_alert() {
  local blocked_url="$1"
  local alert_time="$2"

  daemon_log "Auto-investigating blocked network call: $blocked_url"

  # Search for offending skill
  local skill_result
  skill_result=$(find_skill_for_url "$blocked_url")

  local alert_id
  alert_id=$(make_alert_id)

  local payload

  if [[ -n "$skill_result" ]]; then
    local skill_name="${skill_result%%:*}"
    local skill_dir="${skill_result#*:}"

    # Auto-quarantine immediately — no prompt
    local quarantine_path
    quarantine_path=$(auto_quarantine_skill "$skill_name" "$skill_dir" || echo "")

    if [[ -n "$quarantine_path" ]]; then
      log_alert "$alert_id" "blocked-network-call" \
        "Blocked call to $blocked_url — skill $skill_name quarantined automatically" \
        "$skill_name"

      daemon_log "Alert logged: $alert_id (skill quarantined: $skill_name)"

      payload=$(python3 -c "
import json

text = '''🚨 Blocked Network Call

ClawSec blocked a request to: ${blocked_url}

I investigated and found the source:
→ Skill: ${skill_name} made this call

I've quarantined it automatically to protect you.

Alert ID: ${alert_id}'''

buttons = {'inline_keyboard': [[
  {'text': '🗑️ Remove Permanently', 'callback_data': 'clawsec:purge-skill:${skill_name}'},
  {'text': '↩️ Restore if False Positive', 'callback_data': 'clawsec:restore-skill:${skill_name}'},
  {'text': '📋 View Details', 'callback_data': 'clawsec:view-log'}
]]}

print(json.dumps({
  'chat_id': '${CHAT_ID}',
  'text': text,
  'reply_markup': json.dumps(buttons)
}))
" 2>/dev/null)

    else
      # Quarantine failed — still alert
      log_alert "$alert_id" "blocked-network-call" \
        "Blocked call to $blocked_url — skill $skill_name found but quarantine failed" \
        "$skill_name"

      payload=$(python3 -c "
import json

text = '''🚨 Blocked Network Call

ClawSec blocked a request to: ${blocked_url}

I found the source skill (${skill_name}) but could not quarantine it automatically.
You should remove it manually.

Alert ID: ${alert_id}'''

buttons = {'inline_keyboard': [[
  {'text': '🔍 Show Installed Skills', 'callback_data': 'clawsec:show-skills'},
  {'text': '📋 View ClawSec Log', 'callback_data': 'clawsec:view-log'}
]]}

print(json.dumps({
  'chat_id': '${CHAT_ID}',
  'text': text,
  'reply_markup': json.dumps(buttons)
}))
" 2>/dev/null)
    fi

  else
    # No skill found
    log_alert "$alert_id" "blocked-network-call" \
      "Blocked call to $blocked_url — source skill not identified" \
      ""

    daemon_log "Alert logged: $alert_id (skill not found)"

    payload=$(python3 -c "
import json

text = '''🚨 Blocked Network Call

ClawSec blocked a request to: ${blocked_url}

I couldn't identify which skill made this call. The call was blocked so you're safe, but you may want to review recently installed skills.

Alert ID: ${alert_id}'''

buttons = {'inline_keyboard': [[
  {'text': '🔍 Show Installed Skills', 'callback_data': 'clawsec:show-skills'},
  {'text': '📋 View ClawSec Log', 'callback_data': 'clawsec:view-log'}
]]}

print(json.dumps({
  'chat_id': '${CHAT_ID}',
  'text': text,
  'reply_markup': json.dumps(buttons)
}))
" 2>/dev/null)
  fi

  if [[ -n "$payload" ]]; then
    send_telegram "$payload"
    daemon_log "Network block alert sent (alert_id=$alert_id)"
  else
    daemon_log "ERROR: Failed to build network block payload"
  fi
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

  local new_content
  new_content=$(tail -n "+$((last_line + 1))" "$log_file" 2>/dev/null || true)

  if [[ -z "$new_content" ]]; then
    echo "$current_lines"
    return
  fi

  daemon_log "Processing $((current_lines - last_line)) new log lines"

  # Detect config tampering
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
      local blocked_url
      blocked_url=$(echo "$matched_line" | grep -oE 'https?://[^ ]+' | head -1 || echo "unknown-url")
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
  daemon_log "=== ClawSec monitor v7 started (PID $$) ==="

  local clawsec_log
  clawsec_log=$(find_clawsec_log)

  if [[ -z "$clawsec_log" ]]; then
    daemon_log "ClawSec not installed — monitor will wait and retry every ${POLL_INTERVAL}s"
  elif [[ "$clawsec_log" == "INSTALLED_NO_LOG" ]]; then
    daemon_log "ClawSec installed but no log file found yet — will keep checking"
  else
    daemon_log "Watching ClawSec log: $clawsec_log"
  fi

  local last_line=0
  if [[ -f "$STATE_FILE" ]]; then
    last_line=$(cat "$STATE_FILE" 2>/dev/null || echo "0")
  fi

  while true; do
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

  local clawsec_log
  clawsec_log=$(find_clawsec_log)
  if [[ -z "$clawsec_log" ]]; then
    warn "ClawSec not installed — run ./install-clawsec.sh first"
    warn "Monitor will start anyway and wait for ClawSec to be installed"
  fi

  local bot_token
  bot_token=$(get_bot_token)
  if [[ -z "$bot_token" ]]; then
    warn "No Telegram bot token found in ~/.openclaw/openclaw.json"
    warn "Alerts will be logged but not sent until token is available"
  fi

  nohup bash "$0" _daemon >> "$LOG_FILE" 2>&1 &
  local pid=$!
  echo "$pid" > "$PID_FILE"

  sleep 1
  if kill -0 "$pid" 2>/dev/null; then
    ok "ClawSec monitor v7 started (PID $pid)"
    info "Log: $LOG_FILE"
    info "Alerts: $ALERTS_FILE"
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

  local clawsec_log
  clawsec_log=$(find_clawsec_log 2>/dev/null || echo "")
  if [[ -z "$clawsec_log" ]]; then
    warn "ClawSec: not installed"
  elif [[ "$clawsec_log" == "INSTALLED_NO_LOG" ]]; then
    ok "ClawSec: installed (no log file yet)"
  else
    ok "ClawSec: installed, watching $clawsec_log"
  fi

  if [[ -f "$LOG_FILE" ]]; then
    local log_lines
    log_lines=$(wc -l < "$LOG_FILE")
    info "Monitor log: $LOG_FILE ($log_lines lines)"
  else
    info "Monitor log: not created yet"
  fi

  if [[ -f "$STATE_FILE" ]]; then
    local last_line
    last_line=$(cat "$STATE_FILE")
    info "Last processed line: $last_line"
  fi

  # Show alert summary
  if [[ -f "$ALERTS_FILE" ]]; then
    local open_count
    open_count=$(python3 -c "
import json
try:
    with open('${ALERTS_FILE}') as f:
        alerts = json.load(f)
    print(len([a for a in alerts if a.get('status') == 'open']))
except:
    print(0)
" 2>/dev/null || echo "0")
    info "Open alerts: $open_count"
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
    log "${BOLD}clawsec-monitor.sh v7${RESET} — ClawSec auto-resolve wrapper"
    log ""
    log "Usage: ./clawsec-monitor.sh <command>"
    log ""
    log "Commands:"
    log "  start   Start the background monitor daemon"
    log "  stop    Stop the daemon"
    log "  status  Show current status + open alert count"
    log "  tail    Follow the monitor log"
    log ""
    log "v7 features:"
    log "  • Auto-diffs config files — shows exactly what changed"
    log "  • Auto-investigates blocked calls — finds the offending skill"
    log "  • Auto-quarantines unauthorized skills — no prompt needed"
    log "  • Tracks all alerts in ~/.openclaw-safe/alerts.json"
    log "  • One-tap Telegram buttons to resolve everything"
    log ""
    ;;
  *)
    error "Unknown command: $COMMAND"
    log "Usage: ./clawsec-monitor.sh start|stop|status|tail"
    exit 1
    ;;
esac
