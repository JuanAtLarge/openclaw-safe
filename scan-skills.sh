#!/usr/bin/env bash
# scan-skills.sh — OpenClaw Skill Security Scanner
# Part of openclaw-safe: https://github.com/JuanAtLarge/openclaw-safe
#
# Usage: ./scan-skills.sh [--all] [--no-color] [--quarantine]
#   --all:        also scan built-in skills (default: user-installed only)
#   --quarantine: auto-quarantine CRITICAL skills without prompting (agent mode)
# Exit codes: 0=all pass, 1=warnings, 2=critical issues

set -euo pipefail

# ─── Colors ──────────────────────────────────────────────────────────────────
if [[ "${NO_COLOR:-}" == "1" ]] || [[ "${1:-}" == "--no-color" ]]; then
  RED="" GREEN="" YELLOW="" BLUE="" BOLD="" RESET=""
else
  RED='\033[0;31m' GREEN='\033[0;32m' YELLOW='\033[1;33m'
  BLUE='\033[0;34m' BOLD='\033[1m' RESET='\033[0m'
fi

SCAN_ALL=0
AUTO_QUARANTINE=0
for arg in "$@"; do
  [[ "$arg" == "--all" ]] && SCAN_ALL=1
  [[ "$arg" == "--quarantine" ]] && AUTO_QUARANTINE=1
done

TOTAL=0
PASS=0
WARN=0
FAIL=0
BUILTIN_SCANNED=0
USER_SCANNED=0
GHOST_FILES_CHECKED=0

# Built-in skills paths: macOS (npm-global) or Linux (/usr/local)
if [[ -d "${HOME}/.npm-global/lib/node_modules/openclaw/skills" ]]; then
  BUILTIN_SKILLS="${HOME}/.npm-global/lib/node_modules/openclaw/skills"
elif [[ -d "/usr/local/lib/node_modules/openclaw/skills" ]]; then
  BUILTIN_SKILLS="/usr/local/lib/node_modules/openclaw/skills"
else
  BUILTIN_SKILLS=""
fi
USER_SKILLS="${HOME}/.agents/skills"
VT_KEY="${VIRUSTOTAL_API_KEY:-}"
QUARANTINE_BASE="${HOME}/.openclaw-safe/quarantine"
TODAY=$(date +%Y-%m-%d)

# Track CRITICAL skills for quarantine (as parallel arrays, bash 3.2 compat)
# CRITICAL_SKILL_DIRS[i] and CRITICAL_SKILL_REASONS[i] are aligned
CRITICAL_SKILL_DIRS=()
CRITICAL_SKILL_REASONS=()

log() { echo -e "$*"; }
section() { log ""; log "${BOLD}${BLUE}── $* ──────────────────────────────────────────${RESET}"; }

# ─── Suspicious pattern definitions ──────────────────────────────────────────
# Format: "Label|regex"  (regex matched against file content line by line)
# Only flag code files (.sh .js .ts .py) not docs (.md) for most patterns
CODE_PATTERNS=(
  "curl to external URL|^\s*curl\s+['\"]?https?://"
  "wget to external URL|^\s*wget\s+['\"]?https?://"
  "eval() in code|^\s*eval\s*[\(\"]"
  "exec() with shell variable|^\s*exec\s*\(\s*\$"
  "base64 decode piped to shell|base64\s+-d\s*[^|]*\|\s*(ba)?sh"
  "hardcoded 40+ char token|=\s*['\"][a-zA-Z0-9_/+=-]{40,}['\"]"
  "AWS credential key|AWS_SECRET_ACCESS_KEY|AWS_ACCESS_KEY_ID"
  "reading ~/.ssh directory|['\"]?~?/\.ssh/"
  "discord/slack webhook POST|hooks\.slack\.com|discord\.com/api/webhooks"
  "node child_process spawn|child_process['\"]?\).*spawn|require.*child_process.*spawn"
  "process substitution exec|<\(curl |<\(wget "
  "suspicious long base64 blob|[A-Za-z0-9+/]{120,}={0,2}"
)

scan_code_file() {
  local file="$1"
  local content
  content=$(cat "$file" 2>/dev/null || echo "")

  for pattern_entry in "${CODE_PATTERNS[@]}"; do
    local label regex
    label="${pattern_entry%%|*}"
    regex="${pattern_entry##*|}"
    if echo "$content" | grep -qiE "$regex" 2>/dev/null; then
      echo "$label"
    fi
  done
}

scan_skill() {
  local skill_dir="$1"
  local is_builtin="${2:-0}"   # 1 = built-in skill
  local label="${3:-}"         # optional label e.g. "[built-in]"
  local skill_name
  skill_name=$(basename "$skill_dir")
  local skill_issues
  skill_issues=()
  local critical_issues
  critical_issues=()
  local file_count=0

  # Scan code files for suspicious patterns
  while IFS= read -r -d '' file; do
    file_count=$((file_count+1))
    local basename_file
    basename_file=$(basename "$file")
    while IFS= read -r hit; do
      [[ -z "$hit" ]] && continue
      skill_issues+=("$hit (in $basename_file)")
    done < <(scan_code_file "$file")
  done < <(find "$skill_dir" -type f \( -name "*.sh" -o -name "*.js" -o -name "*.ts" -o -name "*.py" \) -print0 2>/dev/null)

  # ─── ghost-scan: run on skill directory (detects invisible Unicode in JS/TS) ──
  # ghost-scan scans directories, finding all JS/TS/MJS files within
  local js_ts_count
  js_ts_count=$(find "$skill_dir" -type f \( -name "*.js" -o -name "*.ts" -o -name "*.mjs" \) 2>/dev/null | wc -l | tr -d ' ')
  if [[ "$js_ts_count" -gt 0 ]]; then
    if command -v npx &>/dev/null; then
      local ghost_output ghost_exit
      ghost_exit=0
      ghost_output=$(npx --yes ghost-scan "$skill_dir" 2>&1) || ghost_exit=$?
      # Extract how many files were scanned from ghost-scan output
      local ghost_scanned
      ghost_scanned=$(echo "$ghost_output" | grep -oE 'Scanned [0-9]+ files?' | grep -oE '[0-9]+' || echo "0")
      GHOST_FILES_CHECKED=$((GHOST_FILES_CHECKED+ghost_scanned))
      if [[ "$ghost_exit" -ne 0 ]]; then
        # Non-zero exit means findings — extract flagged file names from output
        local flagged_files
        flagged_files=$(echo "$ghost_output" | grep -E "^⚠️  WARNING " | sed 's|^⚠️  WARNING ||' | while read -r fpath; do basename "$fpath"; done | tr '\n' ',' | sed 's/,$//')
        if [[ -z "$flagged_files" ]]; then
          flagged_files="$skill_name"
        fi
        critical_issues+=("Hidden Unicode payload detected — possible code injection attack (in ${flagged_files})")
      fi
    else
      log "  ${YELLOW}ℹ${RESET}  ghost-scan skipped (npx not found)"
    fi
  fi

  TOTAL=$((TOTAL+1))

  local label_suffix=""
  [[ -n "$label" ]] && label_suffix=" ${BLUE}${label}${RESET}"

  if [[ ${#critical_issues[@]} -gt 0 ]]; then
    # CRITICAL: hidden Unicode or other critical issue detected
    log "  ${RED}✗ CRITICAL${RESET}  $skill_name${label_suffix}"
    for issue in "${critical_issues[@]}"; do
      log "          ${RED}→ CRITICAL:${RESET} $issue"
    done
    # Also show any pattern-based warnings
    local seen
    seen=()
    local count=0
    for issue in "${skill_issues[@]+"${skill_issues[@]}"}"; do
      local already=0
      local s
      for s in "${seen[@]+"${seen[@]}"}"; do [[ "$s" == "$issue" ]] && already=1 && break; done
      if [[ "$already" == "0" ]] && [[ "$count" -lt 5 ]]; then
        log "          ${YELLOW}→${RESET} $issue"
        seen+=("$issue")
        count=$((count+1))
      fi
    done
    FAIL=$((FAIL+1))
    # Track for quarantine — only user-installed skills can be quarantined
    if [[ "$is_builtin" == "0" ]]; then
      CRITICAL_SKILL_DIRS+=("$skill_dir")
      CRITICAL_SKILL_REASONS+=("${critical_issues[0]}")
    fi
  elif [[ ${#skill_issues[@]} -eq 0 ]]; then
    log "  ${GREEN}✓ PASS${RESET}  $skill_name${label_suffix} (${file_count} code file(s) scanned)"
    PASS=$((PASS+1))
  else
    log "  ${YELLOW}⚠ WARN${RESET}  $skill_name${label_suffix}"
    # Deduplicate and show top 5
    local seen
    seen=()
    local count=0
    for issue in "${skill_issues[@]+"${skill_issues[@]}"}"; do
      local already=0
      local s
      for s in "${seen[@]+"${seen[@]}"}"; do [[ "$s" == "$issue" ]] && already=1 && break; done
      if [[ "$already" == "0" ]] && [[ "$count" -lt 5 ]]; then
        log "          ${YELLOW}→${RESET} $issue"
        seen+=("$issue")
        count=$((count+1))
      fi
    done
    WARN=$((WARN+1))
  fi

  # VirusTotal scan if API key available
  if [[ -n "$VT_KEY" ]]; then
    local combined_hash
    combined_hash=$(find "$skill_dir" -type f | sort | xargs cat 2>/dev/null | shasum -a 256 | cut -d' ' -f1)
    local vt_result
    vt_result=$(curl -sf --request GET \
      --url "https://www.virustotal.com/api/v3/files/${combined_hash}" \
      --header "x-apikey: ${VT_KEY}" 2>/dev/null || echo "")
    if [[ -n "$vt_result" ]]; then
      local mal_count
      mal_count=$(echo "$vt_result" | python3 -c "
import json,sys
d=json.load(sys.stdin)
print(d.get('data',{}).get('attributes',{}).get('last_analysis_stats',{}).get('malicious',0))
" 2>/dev/null || echo "0")
      if [[ "$mal_count" != "0" ]]; then
        log "    ${RED}✗ VT${RESET}     $skill_name — $mal_count VirusTotal engine(s) flagged!"
        FAIL=$((FAIL+1))
        WARN=$((WARN-1))
      fi
    fi
  fi
}

# ─── Quarantine a skill ───────────────────────────────────────────────────────
quarantine_skill() {
  local skill_dir="$1"
  local reason="${2:-Unknown critical issue detected}"
  local skill_name
  skill_name=$(basename "$skill_dir")
  local dest="${QUARANTINE_BASE}/${TODAY}/${skill_name}"

  # Create quarantine container directory
  if ! mkdir -p "$dest" 2>/dev/null; then
    log "  ${RED}✗ ERROR:${RESET} Cannot create quarantine directory: $dest"
    return 1
  fi

  # Move skill directory into quarantine container
  if ! mv "$skill_dir" "$dest/" 2>/dev/null; then
    log "  ${RED}✗ ERROR:${RESET} Cannot move $skill_dir — check permissions"
    rmdir "$dest" 2>/dev/null || true
    return 1
  fi

  # List moved files for manifest
  local moved_files
  moved_files=$(find "${dest}/${skill_name}" -type f 2>/dev/null | sed "s|${dest}/${skill_name}/|  - |" || echo "  (unable to list files)")

  # Create QUARANTINE.md manifest
  cat > "${dest}/QUARANTINE.md" <<MANIFEST
# QUARANTINE MANIFEST

## Skill: ${skill_name}

- **Quarantined:** $(date '+%Y-%m-%d %H:%M:%S %Z')
- **Reason:** ${reason}
- **Original location:** ${skill_dir}
- **Moved to:** ${dest}/${skill_name}/

## Files Moved

${moved_files}

## What To Do Next

1. Inspect the files in \`${dest}/${skill_name}/\` manually
2. If the skill is safe, restore it: \`./quarantine.sh restore ${skill_name}\`
3. If it's malicious, purge it: \`./quarantine.sh purge ${skill_name}\`
4. Report malicious skills at: https://github.com/JuanAtLarge/openclaw-safe/issues

## DO NOT restore this skill until you have manually reviewed it.
MANIFEST

  log "  ${GREEN}✅${RESET} ${skill_name} quarantined — moved to ~/.openclaw-safe/quarantine/"

  # Try to disable via openclaw CLI if available
  if command -v openclaw &>/dev/null; then
    if openclaw skills disable --help &>/dev/null 2>&1; then
      openclaw skills disable "$skill_name" 2>/dev/null && \
        log "  ${GREEN}✅${RESET} Skill disabled via openclaw CLI" || \
        log "  ${YELLOW}ℹ${RESET}  openclaw skills disable failed (may already be disabled)"
    fi
  fi

  # ─── Telegram interactive notification ────────────────────────────────────
  # Map reason codes/text to plain English explanations
  local plain_reason
  local reason_lower
  reason_lower=$(echo "$reason" | tr '[:upper:]' '[:lower:]')
  if echo "$reason_lower" | grep -qE "hidden-unicode|hidden unicode|invisible unicode|unicode payload|ghost-scan"; then
    plain_reason="Hidden invisible characters found in the skill's code — a common technique to hide malicious instructions that look normal to the human eye."
  elif echo "$reason_lower" | grep -qE "eval.*external|eval.*url|downloads.*runs"; then
    plain_reason="The skill's code downloads and runs code from the internet, which could be used to execute malicious commands on your machine."
  elif echo "$reason_lower" | grep -qE "base64.*pipe|base64.*shell|base64 decode|decode.*shell"; then
    plain_reason="The skill decodes hidden data and runs it as a shell command — a technique often used to disguise malicious code."
  elif echo "$reason_lower" | grep -qE "credential|\.ssh|aws_secret|secret file"; then
    plain_reason="The skill attempts to read credential or secret files on your machine."
  elif echo "$reason_lower" | grep -qE "curl|wget|suspicious.*network|suspicious.*request|discord.*webhook|slack.*webhook"; then
    plain_reason="The skill makes suspicious network requests that could be sending your data to an external server."
  else
    plain_reason="Suspicious code pattern detected that could pose a security risk."
  fi

  local alert_msg
  alert_msg="🚨 openclaw-safe: Skill Quarantined

Skill: ${skill_name}
Reason: ${plain_reason}

What would you like to do?"

  local buttons
  buttons='[[{"text":"🗑️ Remove Permanently","callback_data":"quarantine:purge:'"${skill_name}"'"},{"text":"🔒 Keep Quarantined","callback_data":"quarantine:keep:'"${skill_name}"'"},{"text":"↩️ Restore","callback_data":"quarantine:restore:'"${skill_name}"'"}]]'

  if command -v openclaw &>/dev/null; then
    # Try to send with buttons first
    if openclaw message send --channel telegram \
        --message "$alert_msg" \
        --buttons "$buttons" 2>/dev/null; then
      log "  ${GREEN}✅${RESET} Telegram interactive alert sent (with buttons)"
    else
      # Fall back to plain text
      local plain_msg="🚨 openclaw-safe: Skill Quarantined — ${skill_name}. ${plain_reason} Run: ./quarantine.sh purge ${skill_name} (or restore/list)"
      if openclaw message send --channel telegram \
          --message "$plain_msg" 2>/dev/null; then
        log "  ${GREEN}✅${RESET} Telegram notification sent (plain text fallback)"
      else
        log "  ${YELLOW}ℹ${RESET}  Telegram notification failed — alert logged below"
        log ""
        log "  ${RED}🚨 ALERT:${RESET} $plain_msg"
      fi
    fi
  else
    log ""
    log "  ${RED}🚨 ALERT:${RESET} Malicious skill quarantined — ${skill_name}. Check ~/.openclaw-safe/quarantine/"
  fi
}

# ─── Header ───────────────────────────────────────────────────────────────────
log ""
log "${BOLD}╔══════════════════════════════════════════════════╗${RESET}"
log "${BOLD}║        OpenClaw Skill Scanner 🦙🔍               ║${RESET}"
log "${BOLD}╚══════════════════════════════════════════════════╝${RESET}"

if [[ -n "$VT_KEY" ]]; then
  log "  ${GREEN}VirusTotal API key detected — VT scanning enabled${RESET}"
else
  log "  ${BLUE}ℹ${RESET} Set VIRUSTOTAL_API_KEY env var to enable VT scanning"
fi

# Check ghost-scan (npx) availability
if command -v npx &>/dev/null; then
  log "  ${GREEN}✓${RESET} ghost-scan enabled (npx available)"
else
  log "  ${YELLOW}⚠${RESET} ghost-scan disabled (npx not found)"
fi

# ─── Scan user-installed skills ───────────────────────────────────────────────
section "User-Installed Skills"
if [[ -d "$USER_SKILLS" ]]; then
  USER_SKILL_COUNT=$(ls -1 "$USER_SKILLS" 2>/dev/null | wc -l | tr -d ' ')
  if [[ "$USER_SKILL_COUNT" -gt 0 ]]; then
    for skill_dir in "$USER_SKILLS"/*/; do
      if [[ -d "$skill_dir" ]]; then
        scan_skill "$skill_dir" "0" ""
        USER_SCANNED=$((USER_SCANNED+1))
      fi
    done
  else
    log "  ${BLUE}ℹ${RESET} No user-installed skills found"
  fi
else
  log "  ${BLUE}ℹ${RESET} No user skills directory found ($USER_SKILLS)"
fi

# ─── Optionally scan built-in skills ─────────────────────────────────────────
if [[ "$SCAN_ALL" == "1" ]]; then
  section "Built-in OpenClaw Skills (--all)"
  if [[ -n "$BUILTIN_SKILLS" && -d "$BUILTIN_SKILLS" ]]; then
    log "  ${BLUE}ℹ${RESET} Scanning: $BUILTIN_SKILLS"
    for skill_dir in "$BUILTIN_SKILLS"/*/; do
      if [[ -d "$skill_dir" ]]; then
        scan_skill "$skill_dir" "1" "[built-in]"
        BUILTIN_SCANNED=$((BUILTIN_SCANNED+1))
      fi
    done
  else
    log "  ${BLUE}ℹ${RESET} Built-in skills directory not found (tried: ~/.npm-global/lib/node_modules/openclaw/skills and /usr/local/lib/node_modules/openclaw/skills)"
  fi
else
  log ""
  log "  ${BLUE}ℹ${RESET} Run with --all to also scan built-in OpenClaw skills"
  [[ -n "$BUILTIN_SKILLS" ]] && log "  ${BLUE}ℹ${RESET} Built-in skills path: ${BUILTIN_SKILLS}"
fi

# ─── Summary ─────────────────────────────────────────────────────────────────
log ""
log "${BOLD}${BLUE}═══════════════════════════════════════════════════${RESET}"
log "${BOLD} Skill Scan Summary${RESET}"
log "${BOLD}${BLUE}═══════════════════════════════════════════════════${RESET}"
log "  Total scanned:  $TOTAL"
log "  ${GREEN}✓ Pass:${RESET}         $PASS"
log "  ${YELLOW}⚠ Warnings:${RESET}     $WARN"
log "  ${RED}✗ Critical:${RESET}     $FAIL"
log "  ghost-scan:     ${GHOST_FILES_CHECKED} file(s) checked"
if [[ "$SCAN_ALL" == "1" ]]; then
  log ""
  log "  ${BLUE}ℹ${RESET} $BUILTIN_SCANNED built-in skills scanned, $USER_SCANNED user skills scanned"
fi
log ""

# ─── Quarantine prompt ────────────────────────────────────────────────────────
if [[ ${#CRITICAL_SKILL_DIRS[@]} -gt 0 ]]; then
  log ""
  log "${BOLD}${RED}╔══════════════════════════════════════════════════╗${RESET}"
  log "${BOLD}${RED}║  ⚠️  CRITICAL SKILLS DETECTED                    ║${RESET}"
  log "${BOLD}${RED}╚══════════════════════════════════════════════════╝${RESET}"
  log ""
  log "  The following user-installed skills have CRITICAL issues:"
  _qi=0
  for _qdir in "${CRITICAL_SKILL_DIRS[@]}"; do
    _qname=$(basename "$_qdir")
    log "    ${RED}•${RESET} ${_qname}: ${CRITICAL_SKILL_REASONS[$_qi]}"
    _qi=$((_qi+1))
  done
  log ""

  _do_quarantine=0

  if [[ "$AUTO_QUARANTINE" == "1" ]]; then
    log "  ${YELLOW}--quarantine flag set — auto-quarantining without prompt${RESET}"
    _do_quarantine=1
  elif [[ ! -t 0 ]]; then
    # Non-interactive (piped) — skip quarantine gracefully
    log "  ${BLUE}ℹ${RESET} Non-interactive mode — skipping quarantine prompt"
    log "  ${BLUE}ℹ${RESET} Run with --quarantine to auto-quarantine, or run interactively to be prompted"
    _do_quarantine=0
  else
    echo -ne "  Quarantine flagged skills? [y/N]: "
    read -r _qresponse
    [[ "$_qresponse" =~ ^[Yy]$ ]] && _do_quarantine=1
  fi

  if [[ "$_do_quarantine" == "1" ]]; then
    section "Quarantining Critical Skills"
    _qi=0
    for _qdir in "${CRITICAL_SKILL_DIRS[@]}"; do
      quarantine_skill "$_qdir" "${CRITICAL_SKILL_REASONS[$_qi]}"
      _qi=$((_qi+1))
    done
  fi
fi

if [[ "$FAIL" -gt 0 ]]; then
  exit 2
elif [[ "$WARN" -gt 0 ]]; then
  exit 1
else
  exit 0
fi
