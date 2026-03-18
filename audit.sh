#!/usr/bin/env bash
# audit.sh — OpenClaw Security Audit
# Part of openclaw-safe: https://github.com/JuanAtLarge/openclaw-safe
#
# Usage: ./audit.sh [--quiet] [--no-color]
# Exit codes: 0=all good, 1=warnings, 2=critical issues
#
# Tested against: OpenClaw 2026.3.13 on macOS (arm64)

# ─── Colors ──────────────────────────────────────────────────────────────────
if [[ "${NO_COLOR:-}" == "1" ]] || [[ "${1:-}" == "--no-color" ]]; then
  RED="" GREEN="" YELLOW="" BLUE="" BOLD="" RESET=""
else
  RED='\033[0;31m' GREEN='\033[0;32m' YELLOW='\033[1;33m'
  BLUE='\033[0;34m' BOLD='\033[1m' RESET='\033[0m'
fi

QUIET="${QUIET:-0}"
[[ "${1:-}" == "--quiet" ]] && QUIET=1

# ─── State ────────────────────────────────────────────────────────────────────
WARNINGS=0
CRITICALS=0
TIMESTAMP=$(date +"%Y-%m-%d %H:%M:%S")
DATE=$(date +"%Y-%m-%d")
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RESULTS_DIR="${SCRIPT_DIR}/audit-results"
REPORT_FILE="${RESULTS_DIR}/${DATE}.md"
REPORT_TMP=$(mktemp)

# ─── Helpers ─────────────────────────────────────────────────────────────────
log()     { [[ "$QUIET" == "0" ]] && echo -e "$*" || true; }
pass()    { log "  ${GREEN}✓${RESET} $*"; echo "- ✅ $*" >> "$REPORT_TMP"; }
warn()    { log "  ${YELLOW}⚠${RESET} $*"; echo "- ⚠️  $*" >> "$REPORT_TMP"; WARNINGS=$((WARNINGS+1)); }
crit()    { log "  ${RED}✗${RESET} $*"; echo "- 🚨 $*" >> "$REPORT_TMP"; CRITICALS=$((CRITICALS+1)); }
info()    { log "  ${BLUE}ℹ${RESET} $*"; echo "- ℹ️  $*" >> "$REPORT_TMP"; }
section() {
  log ""
  log "${BOLD}${BLUE}── $* ──────────────────────────────────────────${RESET}"
  echo "" >> "$REPORT_TMP"
  echo "## $*" >> "$REPORT_TMP"
}

# ─── Config paths ─────────────────────────────────────────────────────────────
OPENCLAW_CONFIG="${HOME}/.openclaw/openclaw.json"
OPENCLAW_SKILLS_DIR="${HOME}/.npm-global/lib/node_modules/openclaw/skills"
USER_SKILLS_DIR="${HOME}/.agents/skills"

# ─── Header ───────────────────────────────────────────────────────────────────
log ""
log "${BOLD}╔══════════════════════════════════════════════════╗${RESET}"
log "${BOLD}║         OpenClaw Security Audit 🦙🔒              ║${RESET}"
log "${BOLD}╚══════════════════════════════════════════════════╝${RESET}"
log "  Timestamp: $TIMESTAMP"
log "  Host: $(hostname)"
log "  Config: $OPENCLAW_CONFIG"

{
  echo "# OpenClaw Security Audit"
  echo "**Date:** $TIMESTAMP  "
  echo "**Host:** $(hostname)  "
  echo "**Tool:** openclaw-safe/audit.sh  "
} >> "$REPORT_TMP"

# ─── Check: OpenClaw Config exists ────────────────────────────────────────────
section "Config File"
if [[ ! -f "$OPENCLAW_CONFIG" ]]; then
  crit "openclaw.json not found at $OPENCLAW_CONFIG"
  log ""
  log "${RED}Cannot continue without config file.${RESET}"
  rm -f "$REPORT_TMP"
  exit 2
fi
pass "Config found: $OPENCLAW_CONFIG"

# ─── Check: OpenClaw Version ──────────────────────────────────────────────────
section "OpenClaw Version"
VERSION_RAW=$(openclaw --version 2>/dev/null || echo "unknown")
VERSION=$(echo "$VERSION_RAW" | grep -oE '[0-9]{4}\.[0-9]+\.[0-9]+' | head -1 || true)

if [[ -z "$VERSION" ]]; then
  warn "Could not determine OpenClaw version (got: $VERSION_RAW)"
else
  info "Installed version: $VERSION"
  MIN_VERSION="2026.2.25"
  # Convert YYYY.MM.DD to comparable: YYYY*10000 + MM*100 + DD
  ver_to_int() {
    echo "$1" | awk -F. '{printf "%d%04d%04d", $1, $2, $3}'
  }
  INSTALLED_INT=$(ver_to_int "$VERSION")
  MIN_INT=$(ver_to_int "$MIN_VERSION")
  if (( INSTALLED_INT < MIN_INT )); then
    crit "Version $VERSION is below minimum safe version $MIN_VERSION (vulnerable to ClawJacked)"
    crit "Run: npm update -g openclaw"
  else
    pass "Version $VERSION >= $MIN_VERSION (ClawJacked patch applied)"
  fi
fi

# ─── Check: plugins.allow ─────────────────────────────────────────────────────
section "Plugin Allow-List"
PLUGINS_ALLOW_COUNT=$(python3 -c "
import json
with open('$OPENCLAW_CONFIG') as f: d = json.load(f)
allow = d.get('plugins', {}).get('allow', [])
print(len(allow) if isinstance(allow, list) else 0)
" 2>/dev/null || echo "0")

PLUGINS_ALLOW_LIST=$(python3 -c "
import json
with open('$OPENCLAW_CONFIG') as f: d = json.load(f)
allow = d.get('plugins', {}).get('allow', [])
print(', '.join(allow) if isinstance(allow, list) else '')
" 2>/dev/null || echo "")

if [[ "$PLUGINS_ALLOW_COUNT" == "0" ]]; then
  crit "plugins.allow is empty — all plugins are permitted by default"
  crit "Set plugins.allow in openclaw.json to restrict which plugins can load"
else
  pass "plugins.allow is set: [$PLUGINS_ALLOW_LIST]"
fi

# ─── Check: Exec Approval Settings ───────────────────────────────────────────
section "Exec Approval Settings"
EXEC_ASK=$(python3 -c "
import json
with open('$OPENCLAW_CONFIG') as f: d = json.load(f)
v = d.get('tools', {}).get('exec', {}).get('ask') or d.get('exec', {}).get('ask')
print(v if v else 'null')
" 2>/dev/null || echo "null")

if [[ "$EXEC_ASK" == "null" ]]; then
  warn "exec.ask not explicitly configured (defaults may allow unapproved shell commands)"
  warn "Consider: tools.exec.ask = 'allowlist' or 'always'"
else
  case "$EXEC_ASK" in
    deny)      pass "exec.ask = deny (most restrictive — shell exec blocked)" ;;
    allowlist) pass "exec.ask = allowlist (approved commands only)" ;;
    always)    pass "exec.ask = always (prompts for every exec)" ;;
    on-miss)   warn "exec.ask = on-miss (only prompts for unapproved commands)" ;;
    off)       crit "exec.ask = off (no approval required for shell execution!)" ;;
    *)         warn "exec.ask = $EXEC_ASK (unknown value — review manually)" ;;
  esac
fi

# ─── Check: Gateway Exposure ─────────────────────────────────────────────────
section "Gateway Exposure"
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

GATEWAY_URL=$(python3 -c "
import json
with open('$OPENCLAW_CONFIG') as f: d = json.load(f)
g = d.get('gateway', {})
v = g.get('remote', {}).get('url') or g.get('url', 'null')
print(v)
" 2>/dev/null || echo "null")

GATEWAY_AUTH=$(python3 -c "
import json
with open('$OPENCLAW_CONFIG') as f: d = json.load(f)
print(d.get('gateway', {}).get('auth', {}).get('mode', 'null'))
" 2>/dev/null || echo "null")

info "Gateway mode: $GATEWAY_MODE"

if [[ "$GATEWAY_BIND" == "0.0.0.0"* ]]; then
  crit "Gateway is bound to 0.0.0.0 — exposed on ALL network interfaces!"
  crit "Change gateway.bind to '127.0.0.1' unless external access is needed"
elif [[ "$GATEWAY_BIND" == "127.0.0.1"* ]]; then
  pass "Gateway bound to localhost — not externally exposed"
elif [[ "$GATEWAY_BIND" == "null" ]]; then
  if [[ "$GATEWAY_MODE" == "local" ]]; then
    pass "Gateway in local mode — assumed localhost only"
  else
    warn "Gateway bind not specified and mode is '$GATEWAY_MODE' — verify network exposure"
  fi
else
  warn "Gateway bind = $GATEWAY_BIND — verify this is intentional"
fi

if [[ "$GATEWAY_URL" != "null" && -n "$GATEWAY_URL" ]]; then
  warn "Remote URL configured: $GATEWAY_URL — ensure this endpoint is secured"
fi

if [[ "$GATEWAY_AUTH" == "token" ]]; then
  pass "Gateway auth: token-based authentication enabled"
elif [[ "$GATEWAY_AUTH" == "null" ]]; then
  warn "Gateway auth mode not configured — verify authentication is required"
else
  info "Gateway auth mode: $GATEWAY_AUTH"
fi

# ─── Check: Crons for Unsafe External Content ─────────────────────────────────
section "Cron Safety (External Content Isolation)"

CRON_RESULT=$(python3 << 'PYEOF' 2>/dev/null || echo "ERROR"
import json, os, sys

config_file = os.path.expanduser('~/.openclaw/openclaw.json')
cron_files = [
    config_file,
    os.path.expanduser('~/.openclaw/crons.json'),
    os.path.expanduser('~/.openclaw/cron.json'),
]

EXTERNAL_TRIGGERS = ['email', 'web', 'reddit', 'twitter', 'rss', 'news', 'fetch', 'http', 'url']

found_any = False
cron_warnings = 0
lines = []

for cf in cron_files:
    if not os.path.exists(cf):
        continue
    with open(cf) as f:
        data = json.load(f)
    crons = data.get('crons', data.get('cron', {}))
    if isinstance(crons, dict):
        entries = list(crons.items())
    elif isinstance(crons, list):
        entries = [(str(i), c) for i, c in enumerate(crons)]
    else:
        continue

    for name, cron in entries:
        if not isinstance(cron, dict):
            continue
        found_any = True
        prompt = str(cron.get('prompt', cron.get('task', ''))).lower()
        session_target = cron.get('sessionTarget', cron.get('session_target', ''))

        reads_external = any(t in prompt for t in EXTERNAL_TRIGGERS)
        is_isolated = session_target == 'isolated'

        if reads_external and not is_isolated:
            lines.append(f"CRIT:Cron '{name}' reads external content without sessionTarget=isolated (injection risk!)")
            cron_warnings += 1
        elif reads_external and is_isolated:
            lines.append(f"PASS:Cron '{name}' reads external content in isolated session")
        elif not session_target:
            lines.append(f"WARN:Cron '{name}' has no sessionTarget set — consider 'isolated'")
            cron_warnings += 1
        else:
            lines.append(f"PASS:Cron '{name}' sessionTarget={session_target}")

if not found_any:
    lines.append("PASS:No cron jobs configured")

# Print warnings count as first line so shell can read it
print(cron_warnings)
for l in lines:
    print(l)
PYEOF
)

if [[ "$CRON_RESULT" == "ERROR" || -z "$CRON_RESULT" ]]; then
  warn "Could not parse cron configuration"
else
  CRON_WARN_COUNT=$(echo "$CRON_RESULT" | head -1)
  while IFS= read -r line; do
    [[ -z "$line" ]] && continue
    prefix="${line%%:*}"
    msg="${line#*:}"
    case "$prefix" in
      PASS) pass "$msg" ;;
      WARN) warn "$msg" ;;
      CRIT) crit "$msg" ;;
      *)    info "$line" ;;
    esac
  done < <(echo "$CRON_RESULT" | tail -n +2)
fi

# ─── Check: Hardcoded Credentials in Config ──────────────────────────────────
section "Credential Exposure"

CRED_RESULT=$(python3 << 'PYEOF' 2>/dev/null || echo "ERROR"
import json, os, re

config_file = os.path.expanduser('~/.openclaw/openclaw.json')

SENSITIVE_KEYS = re.compile(
    r'(token|secret|password|passwd|apikey|api_key|credential|auth_key|private_key|access_key)',
    re.IGNORECASE
)

found = []

def scan_and_collect(d, path=""):
    if isinstance(d, dict):
        items = d.items()
    elif isinstance(d, list):
        items = enumerate(d)
    else:
        return
    for k, v in items:
        full_path = f"{path}.{k}" if path else str(k)
        if isinstance(v, (dict, list)):
            scan_and_collect(v, full_path)
        elif isinstance(v, str) and len(v) > 8:
            if SENSITIVE_KEYS.search(str(k)):
                display = v[:4] + '****' + v[-4:] if len(v) > 12 else '****'
                found.append(f"{full_path}={display}")

with open(config_file) as f:
    data = json.load(f)

scan_and_collect(data)

if found:
    print(len(found))
    for item in found:
        print(item)
else:
    print(0)
PYEOF
)

if [[ "$CRED_RESULT" == "ERROR" || -z "$CRED_RESULT" ]]; then
  warn "Could not scan credentials in config"
else
  CRED_COUNT=$(echo "$CRED_RESULT" | head -1)
  if [[ "$CRED_COUNT" == "0" ]]; then
    pass "No obvious credentials found in config"
  else
    warn "Hardcoded credentials found in openclaw.json ($CRED_COUNT field(s)):"
    while IFS= read -r line; do
      [[ -z "$line" ]] && continue
      info "  → $line"
    done < <(echo "$CRED_RESULT" | tail -n +2)
    warn "Consider using environment variables instead of hardcoded tokens"
  fi
fi

# ─── Check: Installed Skills ──────────────────────────────────────────────────
section "Installed Skills"

if [[ -d "$OPENCLAW_SKILLS_DIR" ]]; then
  BUILTIN_COUNT=$(ls -1 "$OPENCLAW_SKILLS_DIR" 2>/dev/null | wc -l | tr -d ' ')
  info "Built-in skills: $BUILTIN_COUNT"
fi

if [[ -d "$USER_SKILLS_DIR" ]]; then
  USER_COUNT=$(ls -1 "$USER_SKILLS_DIR" 2>/dev/null | wc -l | tr -d ' ')
  if [[ "$USER_COUNT" -gt 0 ]]; then
    USER_SKILLS_LIST=$(ls -1 "$USER_SKILLS_DIR" 2>/dev/null | tr '\n' ', ' | sed 's/,$//')
    info "User-installed skills ($USER_COUNT): $USER_SKILLS_LIST"
    warn "User-installed skills not auto-vetted — run: ./scan-skills.sh"
  else
    pass "No user-installed skills"
  fi
else
  pass "No user skills directory found"
fi

if command -v clawsec &>/dev/null; then
  pass "ClawSec installed — run: clawsec scan"
else
  warn "ClawSec not installed — run: ./install-clawsec.sh"
fi

# ─── Check: surreal-mem-mcp ───────────────────────────────────────────────────
section "surreal-mem-mcp"
if command -v surreal-mem-mcp &>/dev/null 2>&1; then
  SMCP_VERSION=$(surreal-mem-mcp --version 2>/dev/null || echo "unknown")
  warn "surreal-mem-mcp installed (v$SMCP_VERSION) — ensure memory is not shared with untrusted agents"
else
  SMCP_NPM=$(npm list -g surreal-mem-mcp 2>/dev/null | grep surreal-mem-mcp || true)
  if [[ -n "$SMCP_NPM" ]]; then
    warn "surreal-mem-mcp found via npm ($SMCP_NPM) — verify it's current"
  else
    pass "surreal-mem-mcp not installed (no memory MCP exposure)"
  fi
fi

# ─── Check: File Permissions ──────────────────────────────────────────────────
section "File Permissions"
# macOS uses -f, Linux uses -c
CONFIG_PERMS=$(stat -f "%OLp" "$OPENCLAW_CONFIG" 2>/dev/null || stat -c "%a" "$OPENCLAW_CONFIG" 2>/dev/null || echo "unknown")

if [[ "$CONFIG_PERMS" == "unknown" ]]; then
  warn "Could not check config file permissions"
elif [[ "$CONFIG_PERMS" == "600" ]]; then
  pass "openclaw.json permissions: 600 (owner read/write only)"
elif [[ "$CONFIG_PERMS" == "644" ]]; then
  warn "openclaw.json is world-readable (perms: $CONFIG_PERMS) — run: chmod 600 ~/.openclaw/openclaw.json"
else
  warn "openclaw.json permissions: $CONFIG_PERMS — consider: chmod 600 ~/.openclaw/openclaw.json"
fi

# ─── Summary ──────────────────────────────────────────────────────────────────
log ""
log "${BOLD}${BLUE}═══════════════════════════════════════════════════${RESET}"
log "${BOLD} Audit Summary${RESET}"
log "${BOLD}${BLUE}═══════════════════════════════════════════════════${RESET}"

if [[ "$CRITICALS" -gt 0 ]]; then
  log "  ${RED}${BOLD}✗ $CRITICALS critical issue(s) found${RESET}"
fi
if [[ "$WARNINGS" -gt 0 ]]; then
  log "  ${YELLOW}⚠ $WARNINGS warning(s) found${RESET}"
fi
if [[ "$CRITICALS" -eq 0 && "$WARNINGS" -eq 0 ]]; then
  log "  ${GREEN}${BOLD}✓ All checks passed — looking good!${RESET}"
fi
log ""

# ─── Write Report ─────────────────────────────────────────────────────────────
mkdir -p "$RESULTS_DIR"

{
  cat "$REPORT_TMP"
  echo ""
  echo "---"
  echo "## Summary"
  echo "- **Criticals:** $CRITICALS"
  echo "- **Warnings:** $WARNINGS"
  echo "- **Version:** ${VERSION:-unknown}"
  echo ""
  echo "*Generated by [openclaw-safe](https://github.com/JuanAtLarge/openclaw-safe)*"
} > "$REPORT_FILE"

rm -f "$REPORT_TMP"

log "  Report: $REPORT_FILE"
log ""

# Exit code
if [[ "$CRITICALS" -gt 0 ]]; then
  exit 2
elif [[ "$WARNINGS" -gt 0 ]]; then
  exit 1
else
  exit 0
fi
