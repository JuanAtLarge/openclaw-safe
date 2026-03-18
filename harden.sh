#!/usr/bin/env bash
# harden.sh — OpenClaw One-Shot Hardener
# Part of openclaw-safe: https://github.com/JuanAtLarge/openclaw-safe
#
# Usage: ./harden.sh [--dry-run] [--no-color]
#   --dry-run: show what would change without applying
# Exit codes: 0=success, 1=partial, 2=error

set -euo pipefail

# ─── Colors ──────────────────────────────────────────────────────────────────
if [[ "${NO_COLOR:-}" == "1" ]] || [[ "${1:-}" == "--no-color" ]]; then
  RED="" GREEN="" YELLOW="" BLUE="" BOLD="" RESET=""
else
  RED='\033[0;31m' GREEN='\033[0;32m' YELLOW='\033[1;33m'
  BLUE='\033[0;34m' BOLD='\033[1m' RESET='\033[0m'
fi

DRY_RUN=0
for arg in "$@"; do [[ "$arg" == "--dry-run" ]] && DRY_RUN=1; done

CHANGED=0
SKIPPED=0
ERRORS=0

OPENCLAW_CONFIG="${HOME}/.openclaw/openclaw.json"
BACKUP_FILE="${OPENCLAW_CONFIG}.backup.$(date +%Y%m%d-%H%M%S)"

log() { echo -e "$*"; }
changed() { log "  ${GREEN}✓ CHANGED${RESET} $*"; CHANGED=$((CHANGED+1)); }
skipped() { log "  ${BLUE}→ SKIP${RESET}    $*"; SKIPPED=$((SKIPPED+1)); }
suggest() { log "  ${YELLOW}⚠ SUGGEST${RESET} $*"; }
err() { log "  ${RED}✗ ERROR${RESET}   $*"; ERRORS=$((ERRORS+1)); }

# ─── Header ───────────────────────────────────────────────────────────────────
log ""
log "${BOLD}╔══════════════════════════════════════════════════╗${RESET}"
log "${BOLD}║         OpenClaw Hardener 🦙🛡️                    ║${RESET}"
log "${BOLD}╚══════════════════════════════════════════════════╝${RESET}"
[[ "$DRY_RUN" == "1" ]] && log "${YELLOW}  DRY RUN MODE — no changes will be applied${RESET}"
log ""

# ─── Prereqs ──────────────────────────────────────────────────────────────────
if [[ ! -f "$OPENCLAW_CONFIG" ]]; then
  err "openclaw.json not found at $OPENCLAW_CONFIG"
  exit 2
fi

if ! command -v python3 &>/dev/null; then
  err "python3 required for config editing"
  exit 2
fi

# ─── Backup ───────────────────────────────────────────────────────────────────
log "${BOLD}Step 1: Backup${RESET}"
if [[ "$DRY_RUN" == "0" ]]; then
  cp "$OPENCLAW_CONFIG" "$BACKUP_FILE"
  log "  Backup saved: $BACKUP_FILE"
else
  log "  ${BLUE}[dry-run]${RESET} Would backup to: $BACKUP_FILE"
fi

# ─── Parse current config ─────────────────────────────────────────────────────
CURRENT_CONFIG=$(cat "$OPENCLAW_CONFIG")

# Helper: check if jq available, otherwise use python3
json_get() {
  if command -v jq &>/dev/null; then
    echo "$CURRENT_CONFIG" | jq -r "$1" 2>/dev/null
  else
    python3 -c "
import json, sys
d = json.loads('''$CURRENT_CONFIG''')
# Basic path resolver
try:
    keys = '$1'.lstrip('.').split('.')
    v = d
    for k in keys:
        v = v.get(k) if isinstance(v, dict) else None
        if v is None: break
    print(v if v is not None else 'null')
except: print('null')
" 2>/dev/null
  fi
}

# ─── Harden: plugins.allow ────────────────────────────────────────────────────
log ""
log "${BOLD}Step 2: Plugin Allow-List${RESET}"

PLUGINS_ALLOW=$(python3 -c "
import json
with open('$OPENCLAW_CONFIG') as f: d = json.load(f)
allow = d.get('plugins', {}).get('allow', [])
print(json.dumps(allow))
" 2>/dev/null || echo "[]")

LOADED_PLUGINS=$(python3 -c "
import json
with open('$OPENCLAW_CONFIG') as f: d = json.load(f)
entries = list(d.get('plugins', {}).get('entries', {}).keys())
installs = list(d.get('plugins', {}).get('installs', {}).keys())
all_plugins = list(set(entries + installs))
print(json.dumps(all_plugins))
" 2>/dev/null || echo "[]")

if [[ "$PLUGINS_ALLOW" == "[]" || "$PLUGINS_ALLOW" == "null" ]]; then
  if [[ "$LOADED_PLUGINS" != "[]" && "$LOADED_PLUGINS" != "null" ]]; then
    log "  plugins.allow is empty — setting to currently installed plugins: $LOADED_PLUGINS"
    if [[ "$DRY_RUN" == "0" ]]; then
      python3 << PYEOF
import json
with open('$OPENCLAW_CONFIG') as f: d = json.load(f)
loaded = $LOADED_PLUGINS
if 'plugins' not in d: d['plugins'] = {}
d['plugins']['allow'] = loaded
with open('$OPENCLAW_CONFIG', 'w') as f: json.dump(d, f, indent=4)
print("  Applied.")
PYEOF
      changed "Set plugins.allow to: $LOADED_PLUGINS"
    else
      log "  ${BLUE}[dry-run]${RESET} Would set plugins.allow = $LOADED_PLUGINS"
      CHANGED=$((CHANGED+1))
    fi
  else
    suggest "plugins.allow is empty and no plugins detected — add plugins manually after installing them"
  fi
else
  skipped "plugins.allow already set: $PLUGINS_ALLOW"
fi

# ─── Harden: File permissions ──────────────────────────────────────────────────
log ""
log "${BOLD}Step 3: Config File Permissions${RESET}"

CONFIG_PERMS=$(stat -f "%A" "$OPENCLAW_CONFIG" 2>/dev/null || stat -c "%a" "$OPENCLAW_CONFIG" 2>/dev/null || echo "unknown")

if [[ "$CONFIG_PERMS" == "unknown" ]]; then
  suggest "Could not check file permissions — manually verify: ls -la $OPENCLAW_CONFIG"
elif [[ "$CONFIG_PERMS" == "600" ]]; then
  skipped "openclaw.json already has secure permissions (600)"
else
  if [[ "$DRY_RUN" == "0" ]]; then
    chmod 600 "$OPENCLAW_CONFIG"
    changed "Set openclaw.json permissions to 600 (was: $CONFIG_PERMS)"
  else
    log "  ${BLUE}[dry-run]${RESET} Would chmod 600 $OPENCLAW_CONFIG (currently: $CONFIG_PERMS)"
    CHANGED=$((CHANGED+1))
  fi
fi

# ─── Check: exec approval settings ────────────────────────────────────────────
log ""
log "${BOLD}Step 4: Exec Approval Settings${RESET}"

EXEC_ASK=$(python3 -c "
import json
with open('$OPENCLAW_CONFIG') as f: d = json.load(f)
v = d.get('tools', {}).get('exec', {}).get('ask') or d.get('exec', {}).get('ask')
print(v if v else 'null')
" 2>/dev/null || echo "null")

if [[ "$EXEC_ASK" == "null" ]]; then
  suggest "exec.ask not set — recommended: set tools.exec.ask = 'allowlist' in openclaw.json"
  suggest "This prevents agents from running unapproved shell commands"
  suggest "Add to openclaw.json:"
  suggest '  "tools": { "exec": { "ask": "allowlist" } }'
  log ""
  log "  ${YELLOW}Note:${RESET} Cannot safely auto-apply exec settings without knowing your current workflow."
  log "  Add the above manually after reviewing which exec commands you need to allow."
elif [[ "$EXEC_ASK" == "off" ]]; then
  suggest "exec.ask = off — this is unsafe! Change to 'allowlist' or 'always'"
  skipped "Not auto-changing exec settings — review manually"
else
  skipped "exec.ask = $EXEC_ASK (review if this matches your intent)"
fi

# ─── Check: Gateway ────────────────────────────────────────────────────────────
log ""
log "${BOLD}Step 5: Gateway Security${RESET}"

GATEWAY_MODE=$(python3 -c "
import json
with open('$OPENCLAW_CONFIG') as f: d = json.load(f)
print(d.get('gateway', {}).get('mode', 'null'))
" 2>/dev/null || echo "null")

GATEWAY_BIND=$(python3 -c "
import json
with open('$OPENCLAW_CONFIG') as f: d = json.load(f)
print(d.get('gateway', {}).get('bind', 'null'))
" 2>/dev/null || echo "null")

if [[ "$GATEWAY_BIND" == "0.0.0.0" ]]; then
  if [[ "$DRY_RUN" == "0" ]]; then
    python3 << PYEOF
import json
with open('$OPENCLAW_CONFIG') as f: d = json.load(f)
d.setdefault('gateway', {})['bind'] = '127.0.0.1'
with open('$OPENCLAW_CONFIG', 'w') as f: json.dump(d, f, indent=4)
PYEOF
    changed "Set gateway.bind from 0.0.0.0 to 127.0.0.1"
  else
    log "  ${BLUE}[dry-run]${RESET} Would set gateway.bind = 127.0.0.1 (currently: 0.0.0.0)"
    CHANGED=$((CHANGED+1))
  fi
else
  skipped "Gateway bind = ${GATEWAY_BIND} (OK)"
fi

# ─── Summary ──────────────────────────────────────────────────────────────────
log ""
log "${BOLD}${BLUE}═══════════════════════════════════════════════════${RESET}"
log "${BOLD} Hardening Summary${RESET}"
log "${BOLD}${BLUE}═══════════════════════════════════════════════════${RESET}"
if [[ "$DRY_RUN" == "1" ]]; then
  log "  ${BLUE}[DRY RUN]${RESET} $CHANGED change(s) would be applied"
else
  log "  ${GREEN}✓${RESET} $CHANGED change(s) applied"
  [[ "$CHANGED" -gt 0 ]] && log "  Backup saved at: $BACKUP_FILE"
fi
log "  ${BLUE}→${RESET} $SKIPPED already-OK setting(s) skipped"
[[ "$ERRORS" -gt 0 ]] && log "  ${RED}✗${RESET} $ERRORS error(s)"
log ""
log "  ${YELLOW}Next steps:${RESET}"
log "  1. Run ./audit.sh to verify the hardening applied"
log "  2. Restart OpenClaw if any config changes were made"
log "  3. Review manual suggestions above"
log ""

[[ "$ERRORS" -gt 0 ]] && exit 2
exit 0
