#!/usr/bin/env bash
# install-clawsec.sh — ClawSec Installer
# Part of openclaw-safe: https://github.com/JuanAtLarge/openclaw-safe
#
# Usage: ./install-clawsec.sh [--no-color]
# Exit codes: 0=installed, 1=already installed, 2=failed

set -euo pipefail

# ─── Colors ──────────────────────────────────────────────────────────────────
if [[ "${NO_COLOR:-}" == "1" ]] || [[ "${1:-}" == "--no-color" ]]; then
  RED="" GREEN="" YELLOW="" BLUE="" BOLD="" RESET=""
else
  RED='\033[0;31m' GREEN='\033[0;32m' YELLOW='\033[1;33m'
  BLUE='\033[0;34m' BOLD='\033[1m' RESET='\033[0m'
fi

CLAWSEC_REPO="https://github.com/prompt-security/clawsec"
INSTALL_DIR="${HOME}/.clawsec"

log() { echo -e "$*"; }

log ""
log "${BOLD}╔══════════════════════════════════════════════════╗${RESET}"
log "${BOLD}║        ClawSec Installer 🦙🔐                    ║${RESET}"
log "${BOLD}╚══════════════════════════════════════════════════╝${RESET}"
log ""

# ─── Check if already installed ──────────────────────────────────────────────
if command -v clawsec &>/dev/null; then
  CURRENT_VERSION=$(clawsec --version 2>/dev/null || echo "unknown")
  log "${GREEN}✓ ClawSec is already installed${RESET} (version: $CURRENT_VERSION)"
  log "  Location: $(which clawsec)"
  log ""
  log "  To update: cd $INSTALL_DIR && git pull && npm install"
  log "  To scan:   clawsec scan"
  exit 1
fi

if [[ -d "$INSTALL_DIR" ]]; then
  log "${YELLOW}⚠ ClawSec directory exists at $INSTALL_DIR but binary not in PATH${RESET}"
  log "  Attempting reinstall..."
fi

# ─── Check prereqs ─────────────────────────────────────────────────────────────
log "${BLUE}ℹ Checking prerequisites...${RESET}"

if ! command -v git &>/dev/null; then
  log "${RED}✗ git not found — required for install${RESET}"
  exit 2
fi
log "  ${GREEN}✓${RESET} git available"

if ! command -v node &>/dev/null; then
  log "${RED}✗ node not found — required for ClawSec${RESET}"
  exit 2
fi
log "  ${GREEN}✓${RESET} node $(node --version) available"

if ! command -v npm &>/dev/null; then
  log "${RED}✗ npm not found — required for ClawSec${RESET}"
  exit 2
fi
log "  ${GREEN}✓${RESET} npm $(npm --version) available"

# ─── Clone / update ───────────────────────────────────────────────────────────
log ""
log "${BLUE}ℹ Installing ClawSec from $CLAWSEC_REPO...${RESET}"

if [[ -d "$INSTALL_DIR/.git" ]]; then
  log "  Updating existing clone..."
  cd "$INSTALL_DIR"
  git pull --quiet
else
  log "  Cloning repository..."
  if ! git clone --quiet "$CLAWSEC_REPO" "$INSTALL_DIR" 2>&1; then
    log "${RED}✗ Failed to clone $CLAWSEC_REPO${RESET}"
    log "  Note: The repository may not exist yet or may be private."
    log "  Check: $CLAWSEC_REPO"
    log ""
    log "  ${YELLOW}Alternative:${RESET} Use VirusTotal integration in scan-skills.sh"
    log "  Set VIRUSTOTAL_API_KEY env var and run: ./scan-skills.sh"
    exit 2
  fi
fi

# ─── Install dependencies ──────────────────────────────────────────────────────
log ""
log "${BLUE}ℹ Installing dependencies...${RESET}"
cd "$INSTALL_DIR"

if [[ -f "package.json" ]]; then
  npm install --quiet 2>&1 | tail -5
else
  log "${YELLOW}⚠ No package.json found — ClawSec may use a different install method${RESET}"
fi

# ─── Verify install ────────────────────────────────────────────────────────────
log ""
log "${BLUE}ℹ Verifying install...${RESET}"

# Try common binary locations
CLAWSEC_BIN=""
for candidate in \
  "$INSTALL_DIR/bin/clawsec" \
  "$INSTALL_DIR/clawsec" \
  "$INSTALL_DIR/node_modules/.bin/clawsec"; do
  if [[ -f "$candidate" ]]; then
    CLAWSEC_BIN="$candidate"
    break
  fi
done

if [[ -z "$CLAWSEC_BIN" ]]; then
  log "${RED}✗ ClawSec binary not found after install${RESET}"
  log "  Check $INSTALL_DIR for the installed files"
  exit 2
fi

# Make executable
chmod +x "$CLAWSEC_BIN"

# Add to PATH suggestion
log "${GREEN}✓ ClawSec installed at: $CLAWSEC_BIN${RESET}"
log ""
log "${YELLOW}Add to PATH:${RESET}"
log "  echo 'export PATH=\"$INSTALL_DIR/bin:\$PATH\"' >> ~/.zshrc"
log "  source ~/.zshrc"
log ""
log "${GREEN}✓ Install complete!${RESET}"
log ""
log "  Usage:"
log "    clawsec scan              # Scan installed skills"
log "    clawsec scan --deep       # Full deep scan"
log "    clawsec report            # View last report"
log ""

exit 0
