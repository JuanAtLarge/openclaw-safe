#!/usr/bin/env bash
# quarantine.sh — Manage quarantined OpenClaw skills
# Part of openclaw-safe: https://github.com/JuanAtLarge/openclaw-safe
#
# Usage:
#   ./quarantine.sh list                # show all quarantined skills
#   ./quarantine.sh restore <name>      # move a skill back to user skills dir (with warning)
#   ./quarantine.sh purge <name>        # permanently delete a quarantined skill

set -euo pipefail

# ─── Colors ──────────────────────────────────────────────────────────────────
if [[ "${NO_COLOR:-}" == "1" ]]; then
  RED="" GREEN="" YELLOW="" BLUE="" BOLD="" RESET=""
else
  RED='\033[0;31m' GREEN='\033[0;32m' YELLOW='\033[1;33m'
  BLUE='\033[0;34m' BOLD='\033[1m' RESET='\033[0m'
fi

QUARANTINE_BASE="${HOME}/.openclaw-safe/quarantine"
USER_SKILLS="${HOME}/.agents/skills"

log() { echo -e "$*"; }

usage() {
  log ""
  log "${BOLD}quarantine.sh — Manage quarantined OpenClaw skills${RESET}"
  log ""
  log "Usage:"
  log "  ${BOLD}./quarantine.sh list${RESET}               Show all quarantined skills"
  log "  ${BOLD}./quarantine.sh restore <name>${RESET}     Move a skill back to user skills dir"
  log "  ${BOLD}./quarantine.sh purge <name>${RESET}       Permanently delete a quarantined skill"
  log ""
}

cmd_list() {
  log ""
  log "${BOLD}╔══════════════════════════════════════════════════╗${RESET}"
  log "${BOLD}║     Quarantined Skills 🔒                        ║${RESET}"
  log "${BOLD}╚══════════════════════════════════════════════════╝${RESET}"
  log ""

  if [[ ! -d "$QUARANTINE_BASE" ]]; then
    log "  ${GREEN}✓${RESET} No quarantine directory found — nothing quarantined."
    log ""
    return 0
  fi

  # Find all quarantined skills (date/skill-name pattern)
  local found=0
  while IFS= read -r -d '' manifest; do
    local quarantine_dir
    quarantine_dir=$(dirname "$manifest")
    local skill_name
    skill_name=$(basename "$quarantine_dir")
    local date_dir
    date_dir=$(basename "$(dirname "$quarantine_dir")")

    found=$((found+1))
    log "  ${RED}🔒${RESET} ${BOLD}${skill_name}${RESET}"
    log "     Quarantined: ${date_dir}"
    log "     Location:    ${quarantine_dir}"

    # Show reason from manifest
    local reason
    reason=$(grep -m1 "\*\*Reason:\*\*" "$manifest" 2>/dev/null | sed 's/.*\*\*Reason:\*\* //' | sed 's/^- //' || echo "Unknown")
    [[ -z "$reason" ]] && reason="Unknown"
    log "     Reason:      ${reason}"
    log ""
  done < <(find "$QUARANTINE_BASE" -name "QUARANTINE.md" -print0 2>/dev/null | sort -z)

  if [[ "$found" -eq 0 ]]; then
    log "  ${GREEN}✓${RESET} No quarantined skills found."
    log ""
  else
    log "  Total quarantined: ${found}"
    log ""
    log "  To restore: ${BOLD}./quarantine.sh restore <skill-name>${RESET}"
    log "  To delete:  ${BOLD}./quarantine.sh purge <skill-name>${RESET}"
    log ""
  fi
}

cmd_restore() {
  local skill_name="${1:-}"
  if [[ -z "$skill_name" ]]; then
    log "${RED}Error:${RESET} Please provide a skill name."
    log "Usage: ./quarantine.sh restore <skill-name>"
    exit 1
  fi

  # Find the quarantine entry
  local skill_dir=""
  while IFS= read -r -d '' manifest; do
    local qdir
    qdir=$(dirname "$manifest")
    if [[ "$(basename "$qdir")" == "$skill_name" ]]; then
      skill_dir="${qdir}/${skill_name}"
      break
    fi
  done < <(find "$QUARANTINE_BASE" -name "QUARANTINE.md" -print0 2>/dev/null)

  if [[ -z "$skill_dir" ]] || [[ ! -d "$skill_dir" ]]; then
    log "${RED}Error:${RESET} Quarantined skill '${skill_name}' not found."
    log "Run ${BOLD}./quarantine.sh list${RESET} to see quarantined skills."
    exit 1
  fi

  log ""
  log "${YELLOW}⚠️  WARNING: Restoring a quarantined skill${RESET}"
  log ""
  log "  Skill:   ${skill_name}"
  log "  From:    ${skill_dir}"
  log "  To:      ${USER_SKILLS}/${skill_name}"
  log ""
  log "  ${YELLOW}This skill was quarantined because it was flagged as CRITICAL.${RESET}"
  log "  ${YELLOW}Only restore it if you have manually reviewed it and confirmed it is safe.${RESET}"
  log ""

  if [[ ! -t 0 ]]; then
    log "${RED}Error:${RESET} Restore requires interactive confirmation. Run in a terminal."
    exit 1
  fi

  echo -ne "  I have reviewed this skill and confirm it is safe. Restore? [y/N]: "
  read -r response
  if [[ ! "$response" =~ ^[Yy]$ ]]; then
    log "  Restore cancelled."
    exit 0
  fi

  # Ensure user skills dir exists
  mkdir -p "$USER_SKILLS"

  if [[ -d "${USER_SKILLS}/${skill_name}" ]]; then
    log "${RED}Error:${RESET} ${USER_SKILLS}/${skill_name} already exists. Remove or rename it first."
    exit 1
  fi

  if ! mv "$skill_dir" "$USER_SKILLS/" 2>/dev/null; then
    log "${RED}Error:${RESET} Cannot move skill back to ${USER_SKILLS}/. Check permissions."
    exit 1
  fi

  # Clean up the quarantine entry (remove manifest + now-empty dir)
  local qentry_dir
  qentry_dir=$(dirname "$skill_dir")
  rm -f "${qentry_dir}/QUARANTINE.md" 2>/dev/null || true
  rmdir "$qentry_dir" 2>/dev/null || true

  log ""
  log "  ${GREEN}✅ ${skill_name} restored to ${USER_SKILLS}/${skill_name}${RESET}"
  log "  ${YELLOW}Run ${BOLD}bash scan-skills.sh${RESET}${YELLOW} to re-verify before using.${RESET}"
  log ""
}

cmd_purge() {
  local skill_name="${1:-}"
  if [[ -z "$skill_name" ]]; then
    log "${RED}Error:${RESET} Please provide a skill name."
    log "Usage: ./quarantine.sh purge <skill-name>"
    exit 1
  fi

  # Find the quarantine entry
  local qentry_dir=""
  while IFS= read -r -d '' manifest; do
    local qdir
    qdir=$(dirname "$manifest")
    if [[ "$(basename "$qdir")" == "$skill_name" ]]; then
      qentry_dir="$qdir"
      break
    fi
  done < <(find "$QUARANTINE_BASE" -name "QUARANTINE.md" -print0 2>/dev/null)

  if [[ -z "$qentry_dir" ]]; then
    log "${RED}Error:${RESET} Quarantined skill '${skill_name}' not found."
    log "Run ${BOLD}./quarantine.sh list${RESET} to see quarantined skills."
    exit 1
  fi

  log ""
  log "${RED}⚠️  PERMANENT DELETION WARNING${RESET}"
  log ""
  log "  This will PERMANENTLY DELETE the quarantined skill:"
  log "  ${BOLD}${qentry_dir}${RESET}"
  log ""
  log "  ${RED}This cannot be undone.${RESET}"
  log ""

  if [[ ! -t 0 ]]; then
    log "${RED}Error:${RESET} Purge requires interactive confirmation. Run in a terminal."
    exit 1
  fi

  echo -ne "  Permanently delete '${skill_name}'? Type 'DELETE' to confirm: "
  read -r response
  if [[ "$response" != "DELETE" ]]; then
    log "  Purge cancelled."
    exit 0
  fi

  if ! rm -rf "$qentry_dir" 2>/dev/null; then
    log "${RED}Error:${RESET} Cannot delete ${qentry_dir}. Check permissions."
    exit 1
  fi

  log ""
  log "  ${GREEN}✅ ${skill_name} permanently deleted.${RESET}"
  log ""
}

# ─── Main ─────────────────────────────────────────────────────────────────────
COMMAND="${1:-}"

case "$COMMAND" in
  list)
    cmd_list
    ;;
  restore)
    cmd_restore "${2:-}"
    ;;
  purge)
    cmd_purge "${2:-}"
    ;;
  ""|--help|-h)
    usage
    ;;
  *)
    log "${RED}Error:${RESET} Unknown command '${COMMAND}'"
    usage
    exit 1
    ;;
esac
