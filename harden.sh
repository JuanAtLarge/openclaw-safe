#!/usr/bin/env bash
# harden.sh — OpenClaw One-Shot Hardener v2
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

# Check if we're in an interactive terminal (for prompts)
# HARDEN_YES=1 env var forces all prompts to auto-accept (wizard/non-interactive mode)
IS_INTERACTIVE=0
[[ -t 0 && -t 1 ]] && IS_INTERACTIVE=1
[[ "${HARDEN_YES:-}" == "1" ]] && IS_INTERACTIVE=2  # special: force-yes mode

CHANGED=0
SKIPPED=0
ERRORS=0
CONFIG_CHANGED=0

OPENCLAW_CONFIG="${OPENCLAW_CONFIG:-${HOME}/.openclaw/openclaw.json}"
BACKUP_FILE="${OPENCLAW_CONFIG}.backup.$(date +%Y%m%d-%H%M%S)"

log()     { echo -e "$*"; }
ok()      { log "  ${GREEN}✓${RESET} $*"; }
changed() { log "  ${GREEN}✓ CHANGED${RESET} $*"; CHANGED=$((CHANGED+1)); CONFIG_CHANGED=$((CONFIG_CHANGED+1)); }
skipped() { log "  ${BLUE}→ SKIP${RESET}    $*"; SKIPPED=$((SKIPPED+1)); }
warn()    { log "  ${YELLOW}⚠${RESET} $*"; }
err()     { log "  ${RED}✗ ERROR${RESET}   $*"; ERRORS=$((ERRORS+1)); }

# ─── Prompt helper ────────────────────────────────────────────────────────────
# Returns 0 (yes) or 1 (no). Auto-skips (returns 1) in non-interactive mode.
ask_yes_no() {
  local prompt="$1"
  if [[ "$IS_INTERACTIVE" == "0" ]]; then
    log "  ${BLUE}[non-interactive]${RESET} Skipping prompt: $prompt"
    return 1
  fi
  if [[ "$IS_INTERACTIVE" == "2" ]]; then
    log "  ${GREEN}[auto-yes]${RESET} $prompt → yes"
    return 0
  fi
  local answer
  read -rp "$(echo -e "  ${YELLOW}?${RESET} ${prompt} [y/N]: ")" answer
  [[ "${answer,,}" == "y" || "${answer,,}" == "yes" ]]
}

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

# ─── Phase 1: SCAN ────────────────────────────────────────────────────────────
# Collect issues without applying. We'll confirm and apply after showing summary.

log "${BOLD}Scanning your OpenClaw install...${RESET}"
log ""

# Track pending fixes as parallel arrays (bash 3 compat, no associative arrays)
FIX_NAMES=()
FIX_DESCS=()

# ─── Scan: plugins.allow ──────────────────────────────────────────────────────
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
    FIX_NAMES+=("plugins_allow")
    FIX_DESCS+=("Set plugins.allow to currently installed plugins: $LOADED_PLUGINS")
  fi
fi

# ─── Scan: file permissions ────────────────────────────────────────────────────
CONFIG_PERMS=$(stat -f "%OLp" "$OPENCLAW_CONFIG" 2>/dev/null || stat -c "%a" "$OPENCLAW_CONFIG" 2>/dev/null || echo "unknown")

if [[ "$CONFIG_PERMS" != "unknown" && "$CONFIG_PERMS" != "600" ]]; then
  FIX_NAMES+=("file_perms")
  FIX_DESCS+=("Set openclaw.json permissions to 600 (currently: $CONFIG_PERMS)")
fi

# ─── Scan: exec.ask ───────────────────────────────────────────────────────────
EXEC_ASK=$(python3 -c "
import json
with open('$OPENCLAW_CONFIG') as f: d = json.load(f)
v = d.get('tools', {}).get('exec', {}).get('ask') or d.get('exec', {}).get('ask')
print(v if v else 'null')
" 2>/dev/null || echo "null")

EXEC_ASK_NEEDS_FIX=0
if [[ "$EXEC_ASK" == "null" ]]; then
  EXEC_ASK_NEEDS_FIX=1
  FIX_NAMES+=("exec_ask")
  FIX_DESCS+=("Set tools.exec.ask = 'allowlist' (currently not configured — agents can run any shell command!)")
elif [[ "$EXEC_ASK" == "off" ]]; then
  EXEC_ASK_NEEDS_FIX=1
  FIX_NAMES+=("exec_ask")
  FIX_DESCS+=("Change tools.exec.ask from 'off' to 'allowlist' (off = zero shell approval!)")
fi

# ─── Scan: gateway binding ────────────────────────────────────────────────────
GATEWAY_BIND=$(python3 -c "
import json
with open('$OPENCLAW_CONFIG') as f: d = json.load(f)
print(d.get('gateway', {}).get('bind', 'null'))
" 2>/dev/null || echo "null")

if [[ "$GATEWAY_BIND" == "0.0.0.0" ]]; then
  FIX_NAMES+=("gateway_bind")
  FIX_DESCS+=("Set gateway.bind to 127.0.0.1 (currently exposed on ALL network interfaces!)")
fi

# ─── Phase 2: SHOW FINDINGS ───────────────────────────────────────────────────

NUM_FIXES=${#FIX_NAMES[@]}

if [[ "$NUM_FIXES" -eq 0 ]]; then
  log "${GREEN}${BOLD}✓ Nothing to fix — your config looks good!${RESET}"
  log ""
  log "  Run ${BOLD}./audit.sh${RESET} for a full security report."
  log ""
  exit 0
fi

# Show exec.ask warning prominently if present
if [[ "$EXEC_ASK_NEEDS_FIX" == "1" ]]; then
  log "${YELLOW}⚠ exec.ask not configured — this lets agents run shell commands without approval${RESET}"
  log ""
fi

log "${BOLD}Found $NUM_FIXES thing(s) to fix:${RESET}"
log ""
for i in "${!FIX_NAMES[@]}"; do
  log "  ${YELLOW}[$((i+1))]${RESET} ${FIX_DESCS[$i]}"
done
log ""

# ─── Dry-run mode: show and exit ──────────────────────────────────────────────
if [[ "$DRY_RUN" == "1" ]]; then
  log "${BOLD}${BLUE}═══════════════════════════════════════════════════${RESET}"
  log "${BOLD} Dry Run Summary${RESET}"
  log "${BOLD}${BLUE}═══════════════════════════════════════════════════${RESET}"
  log ""
  log "  ${BLUE}[dry-run]${RESET} $NUM_FIXES change(s) would be applied:"
  for desc in "${FIX_DESCS[@]}"; do
    log "    ${BLUE}→${RESET} $desc"
  done
  log ""
  # Show exec.ask specifically
  if [[ "$EXEC_ASK_NEEDS_FIX" == "1" ]]; then
    log "  ${BLUE}[dry-run]${RESET} Would add to openclaw.json:"
    log '    "tools": { "exec": { "ask": "allowlist" } }'
    log ""
  fi
  log "  Run ${BOLD}./harden.sh${RESET} (without --dry-run) to apply."
  log ""
  exit 0
fi

# ─── Phase 3: CONFIRM ─────────────────────────────────────────────────────────
if ! ask_yes_no "Apply all fixes?"; then
  log ""
  log "${BOLD}No changes applied. Here's what to do manually:${RESET}"
  log ""
  for desc in "${FIX_DESCS[@]}"; do
    log "  ${YELLOW}→${RESET} $desc"
  done
  log ""
  log "  Or just run ${BOLD}./harden.sh${RESET} again when you're ready."
  log ""
  exit 0
fi

log ""

# ─── Phase 4: BACKUP ──────────────────────────────────────────────────────────
log "${BOLD}Backing up config...${RESET}"
cp "$OPENCLAW_CONFIG" "$BACKUP_FILE"
ok "Backup saved: $BACKUP_FILE"
log ""

# ─── Phase 5: APPLY ───────────────────────────────────────────────────────────
log "${BOLD}Applying fixes...${RESET}"
log ""

for fix_name in "${FIX_NAMES[@]}"; do

  case "$fix_name" in

    plugins_allow)
      log "  ${BLUE}[1/1]${RESET} Setting plugins.allow..."
      python3 << PYEOF
import json
with open('$OPENCLAW_CONFIG') as f: d = json.load(f)
loaded = $LOADED_PLUGINS
if 'plugins' not in d: d['plugins'] = {}
d['plugins']['allow'] = loaded
with open('$OPENCLAW_CONFIG', 'w') as f: json.dump(d, f, indent=4)
PYEOF
      changed "plugins.allow set to: $LOADED_PLUGINS"
      ;;

    file_perms)
      chmod 600 "$OPENCLAW_CONFIG"
      changed "openclaw.json permissions set to 600 (was: $CONFIG_PERMS)"
      ;;

    exec_ask)
      log "  Setting tools.exec.ask..."
      python3 << PYEOF
import json
with open('$OPENCLAW_CONFIG') as f: d = json.load(f)
if 'tools' not in d: d['tools'] = {}
if 'exec' not in d['tools']: d['tools']['exec'] = {}
d['tools']['exec']['ask'] = 'allowlist'
with open('$OPENCLAW_CONFIG', 'w') as f: json.dump(d, f, indent=4)
PYEOF
      ok "✅ exec.ask set to allowlist"
      CHANGED=$((CHANGED+1))
      CONFIG_CHANGED=$((CONFIG_CHANGED+1))
      ;;

    gateway_bind)
      python3 << PYEOF
import json
with open('$OPENCLAW_CONFIG') as f: d = json.load(f)
d.setdefault('gateway', {})['bind'] = '127.0.0.1'
with open('$OPENCLAW_CONFIG', 'w') as f: json.dump(d, f, indent=4)
PYEOF
      changed "gateway.bind set to 127.0.0.1 (was: 0.0.0.0)"
      ;;

  esac
done

# ─── Phase 6: SUMMARY ─────────────────────────────────────────────────────────
log ""
log "${BOLD}${BLUE}═══════════════════════════════════════════════════${RESET}"
log "${BOLD} Hardening Complete${RESET}"
log "${BOLD}${BLUE}═══════════════════════════════════════════════════${RESET}"
log ""
log "  ${GREEN}✓${RESET} $CHANGED fix(es) applied"
log "  ${BLUE}→${RESET} $SKIPPED setting(s) already OK"
[[ "$ERRORS" -gt 0 ]] && log "  ${RED}✗${RESET} $ERRORS error(s)"
[[ "$CHANGED" -gt 0 ]] && log "  Backup saved at: $BACKUP_FILE"
log ""

# ─── Phase 7: RESTART PROMPT ──────────────────────────────────────────────────
if [[ "$CONFIG_CHANGED" -gt 0 ]]; then
  log "  Config updated."
  if ask_yes_no "Restart OpenClaw to apply changes?"; then
    log ""
    log "  Restarting OpenClaw..."
    if openclaw gateway restart; then
      ok "OpenClaw restarted successfully"
    else
      warn "Restart command failed — try: openclaw gateway restart"
    fi
  else
    log ""
    log "  ${YELLOW}Remember to restart OpenClaw manually:${RESET}"
    log "    openclaw gateway restart"
  fi
fi

log ""
log "  Run ${BOLD}./audit.sh${RESET} to verify everything looks good."
log ""

[[ "$ERRORS" -gt 0 ]] && exit 2
exit 0
