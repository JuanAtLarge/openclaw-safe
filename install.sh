#!/usr/bin/env bash
# install.sh — OpenClaw-Safe One-Command Installer
# Usage: curl -sSL https://raw.githubusercontent.com/JuanAtLarge/openclaw-safe/main/install.sh | bash
#
# What this does:
#   1. Clones or updates openclaw-safe to ~/.openclaw-safe/
#   2. Makes all scripts executable
#   3. Runs audit.sh immediately
#   4. Tells you what to do next

set -euo pipefail

REPO="https://github.com/JuanAtLarge/openclaw-safe.git"
INSTALL_DIR="${OPENCLAW_SAFE_DIR:-${HOME}/.openclaw-safe}"

# Colors
RED='\033[0;31m' GREEN='\033[0;32m' YELLOW='\033[1;33m'
BLUE='\033[0;34m' BOLD='\033[1m' RESET='\033[0m'

log() { echo -e "$*"; }

log ""
log "${BOLD}╔══════════════════════════════════════════════════════╗${RESET}"
log "${BOLD}║          openclaw-safe Installer 🦙🔒                ║${RESET}"
log "${BOLD}║   Community Hardening Tool for OpenClaw              ║${RESET}"
log "${BOLD}╚══════════════════════════════════════════════════════╝${RESET}"
log ""

# ─── Check git ────────────────────────────────────────────────────────────────
if ! command -v git &>/dev/null; then
  log "${RED}✗ git is required but not found${RESET}"
  log "  Install git and try again"
  exit 1
fi

# ─── Clone or update ──────────────────────────────────────────────────────────
if [[ -d "$INSTALL_DIR/.git" ]]; then
  log "${BLUE}ℹ Updating openclaw-safe...${RESET}"
  cd "$INSTALL_DIR"
  git pull --quiet
  log "${GREEN}✓ Updated to latest${RESET}"
else
  log "${BLUE}ℹ Installing openclaw-safe to $INSTALL_DIR...${RESET}"
  git clone --quiet "$REPO" "$INSTALL_DIR"
  log "${GREEN}✓ Cloned successfully${RESET}"
fi

cd "$INSTALL_DIR"

# ─── Make scripts executable ──────────────────────────────────────────────────
chmod +x audit.sh scan-skills.sh harden.sh install-clawsec.sh install.sh 2>/dev/null || true
log "${GREEN}✓ Scripts ready${RESET}"

# ─── Run audit immediately ────────────────────────────────────────────────────
log ""
log "${BOLD}Running security audit now...${RESET}"
log "$(printf '─%.0s' {1..52})"
log ""

if bash "$INSTALL_DIR/audit.sh"; then
  AUDIT_EXIT=0
else
  AUDIT_EXIT=$?
fi

log ""
log "$(printf '─%.0s' {1..52})"

# ─── Next steps ───────────────────────────────────────────────────────────────
log ""
log "${BOLD}Next steps:${RESET}"
log ""

if [[ "$AUDIT_EXIT" -ge 2 ]]; then
  log "  ${RED}Critical issues found!${RESET} Address them first:"
  log "  → Check audit-results/$(date +%Y-%m-%d).md for details"
  log ""
fi

log "  ${BOLD}From $INSTALL_DIR:${RESET}"
log ""
log "  ${GREEN}./harden.sh${RESET}             Apply safe defaults automatically"
log "  ${GREEN}./harden.sh --dry-run${RESET}   Preview changes before applying"
log "  ${GREEN}./scan-skills.sh${RESET}        Scan installed skills for suspicious patterns"
log "  ${GREEN}./install-clawsec.sh${RESET}    Install ClawSec vulnerability scanner"
log "  ${GREEN}./audit.sh${RESET}              Re-run audit anytime"
log ""
log "  ${BLUE}Report saved to:${RESET} $INSTALL_DIR/audit-results/$(date +%Y-%m-%d).md"
log ""
log "  ${BOLD}Agent-friendly one-liner to re-audit later:${RESET}"
log "  bash ~/.openclaw-safe/audit.sh"
log ""
log "${GREEN}✓ openclaw-safe installed at $INSTALL_DIR${RESET}"
log ""

exit "$AUDIT_EXIT"
