#!/usr/bin/env bash
# scan-skills.sh — OpenClaw Skill Security Scanner
# Part of openclaw-safe: https://github.com/JuanAtLarge/openclaw-safe
#
# Usage: ./scan-skills.sh [--all] [--no-color]
#   --all: also scan built-in skills (default: user-installed only)
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
for arg in "$@"; do [[ "$arg" == "--all" ]] && SCAN_ALL=1; done

TOTAL=0
PASS=0
WARN=0
FAIL=0
BUILTIN_SCANNED=0
USER_SCANNED=0

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

log() { echo -e "$*"; }
section() { log ""; log "${BOLD}${BLUE}── $* ──────────────────────────────────────────${RESET}"; }

# ─── Suspicious pattern definitions ──────────────────────────────────────────
# Format: "Label|regex"  (regex matched against file content line by line)
# Only flag code files (.sh .js .ts .py) not docs (.md) for most patterns
declare -a CODE_PATTERNS=(
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
  local hits=()
  local content
  content=$(cat "$file" 2>/dev/null || echo "")

  for pattern_entry in "${CODE_PATTERNS[@]}"; do
    local label regex
    label="${pattern_entry%%|*}"
    regex="${pattern_entry##*|}"
    if echo "$content" | grep -qiE "$regex" 2>/dev/null; then
      hits+=("$label")
    fi
  done

  printf '%s\n' "${hits[@]:-}"
}

scan_skill() {
  local skill_dir="$1"
  local label="${2:-}"   # optional label e.g. "[built-in]"
  local skill_name
  skill_name=$(basename "$skill_dir")
  local -a skill_issues=()
  local file_count=0

  # Scan code files
  while IFS= read -r -d '' file; do
    file_count=$((file_count+1))
    local basename_file
    basename_file=$(basename "$file")
    while IFS= read -r hit; do
      [[ -z "$hit" ]] && continue
      skill_issues+=("$hit (in $basename_file)")
    done < <(scan_code_file "$file")
  done < <(find "$skill_dir" -type f \( -name "*.sh" -o -name "*.js" -o -name "*.ts" -o -name "*.py" \) -print0 2>/dev/null)

  TOTAL=$((TOTAL+1))

  local label_suffix=""
  [[ -n "$label" ]] && label_suffix=" ${BLUE}${label}${RESET}"

  if [[ ${#skill_issues[@]} -eq 0 ]]; then
    log "  ${GREEN}✓ PASS${RESET}  $skill_name${label_suffix} (${file_count} code file(s) scanned)"
    PASS=$((PASS+1))
  else
    log "  ${YELLOW}⚠ WARN${RESET}  $skill_name${label_suffix}"
    # Deduplicate and show top 5
    local seen=()
    local count=0
    for issue in "${skill_issues[@]}"; do
      # Check if already seen
      local already=0
      for s in "${seen[@]:-}"; do [[ "$s" == "$issue" ]] && already=1 && break; done
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

# ─── Scan user-installed skills ───────────────────────────────────────────────
section "User-Installed Skills"
if [[ -d "$USER_SKILLS" ]]; then
  USER_SKILL_COUNT=$(ls -1 "$USER_SKILLS" 2>/dev/null | wc -l | tr -d ' ')
  if [[ "$USER_SKILL_COUNT" -gt 0 ]]; then
    for skill_dir in "$USER_SKILLS"/*/; do
      if [[ -d "$skill_dir" ]]; then
        scan_skill "$skill_dir" ""
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
        scan_skill "$skill_dir" "[built-in]"
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
if [[ "$SCAN_ALL" == "1" ]]; then
  log ""
  log "  ${BLUE}ℹ${RESET} $BUILTIN_SCANNED built-in skills scanned, $USER_SCANNED user skills scanned"
fi
log ""

if [[ "$FAIL" -gt 0 ]]; then
  exit 2
elif [[ "$WARN" -gt 0 ]]; then
  exit 1
else
  exit 0
fi
