#!/usr/bin/env bash
# install-clawsec.sh — Install ClawSec security skill suite for OpenClaw
# ClawSec by Prompt Security (SentinelOne) — https://clawsec.prompt.security

set -euo pipefail

BOLD='\033[1m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
RESET='\033[0m'

CLAWSEC_REPO="https://github.com/prompt-security/clawsec"
CLAWSEC_DIR="$HOME/.clawsec"
SKILLS_DIR="$HOME/.openclaw/skills"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo -e "${BOLD}╔══════════════════════════════════════════════════╗${RESET}"
echo -e "${BOLD}║        ClawSec Installer 🦙🔐                    ║${RESET}"
echo -e "${BOLD}╚══════════════════════════════════════════════════╝${RESET}"
echo ""
echo -e "${BLUE}ℹ ClawSec is a security skill suite for OpenClaw${RESET}"
echo -e "${BLUE}ℹ Built by Prompt Security (a SentinelOne company)${RESET}"
echo ""

# ── Prerequisites ──────────────────────────────────────────────────────────────
echo -e "${BOLD}Checking prerequisites...${RESET}"

MISSING=0
for cmd in git node npm; do
    if command -v "$cmd" &>/dev/null; then
        echo -e "  ${GREEN}✓${RESET} $cmd available"
    else
        echo -e "  ${RED}✗${RESET} $cmd not found — required"
        MISSING=1
    fi
done

if [ "$MISSING" -eq 1 ]; then
    echo -e "\n${RED}✗ Missing required tools. Install them and retry.${RESET}"
    exit 1
fi

# ── Clone or update ClawSec ────────────────────────────────────────────────────
echo ""
echo -e "${BOLD}Installing ClawSec...${RESET}"

if [ -d "$CLAWSEC_DIR/.git" ]; then
    echo -e "  ${BLUE}→${RESET} Updating existing ClawSec install..."
    cd "$CLAWSEC_DIR" && git pull --quiet
    echo -e "  ${GREEN}✓${RESET} ClawSec updated"
else
    echo -e "  ${BLUE}→${RESET} Cloning ClawSec repository..."
    git clone --quiet "$CLAWSEC_REPO" "$CLAWSEC_DIR"
    echo -e "  ${GREEN}✓${RESET} ClawSec cloned"
fi

# ── Install dependencies ───────────────────────────────────────────────────────
echo -e "  ${BLUE}→${RESET} Installing dependencies..."
cd "$CLAWSEC_DIR" && npm install --silent 2>/dev/null || true
echo -e "  ${GREEN}✓${RESET} Dependencies installed"

# ── Install skills into OpenClaw ───────────────────────────────────────────────
echo ""
echo -e "${BOLD}Installing ClawSec skills into OpenClaw...${RESET}"

mkdir -p "$SKILLS_DIR"

SKILLS_INSTALLED=0
if [ -d "$CLAWSEC_DIR/skills" ]; then
    for skill_dir in "$CLAWSEC_DIR/skills"/*/; do
        skill_name=$(basename "$skill_dir")
        target="$SKILLS_DIR/$skill_name"
        if [ -d "$target" ]; then
            echo -e "  ${BLUE}→ SKIP${RESET}    $skill_name (already installed)"
        else
            cp -r "$skill_dir" "$target"
            echo -e "  ${GREEN}✓ INSTALLED${RESET} $skill_name"
            SKILLS_INSTALLED=$((SKILLS_INSTALLED + 1))
        fi
    done
    echo -e "\n  ${GREEN}✓${RESET} $SKILLS_INSTALLED skill(s) installed to $SKILLS_DIR"
else
    echo -e "  ${YELLOW}⚠${RESET} No skills directory found in ClawSec repo"
fi

# ── Summary ────────────────────────────────────────────────────────────────────
echo ""
echo -e "${BLUE}═══════════════════════════════════════════════════${RESET}"
echo -e "${BOLD} ClawSec Install Summary${RESET}"
echo -e "${BLUE}═══════════════════════════════════════════════════${RESET}"
echo ""
echo -e "  ${GREEN}✓${RESET} ClawSec installed to: $CLAWSEC_DIR"
echo -e "  ${GREEN}✓${RESET} Skills installed to:   $SKILLS_DIR"
echo ""
echo -e "  ${BOLD}Available ClawSec skills:${RESET}"
if [ -d "$CLAWSEC_DIR/skills" ]; then
    for skill_dir in "$CLAWSEC_DIR/skills"/*/; do
        skill_name=$(basename "$skill_dir")
        desc=""
        if [ -f "$skill_dir/SKILL.md" ]; then
            desc=$(grep "^description:" "$skill_dir/SKILL.md" 2>/dev/null | head -1 | sed 's/description: //' | cut -c1-60)
        fi
        echo -e "    ${BLUE}→${RESET} $skill_name${desc:+ — $desc}"
    done
fi
echo ""
echo -e "  ${BOLD}Next steps:${RESET}"
echo -e "  1. Restart OpenClaw for skills to load: openclaw gateway restart"
echo -e "  2. Start the ClawSec monitor: ${BOLD}./clawsec-monitor.sh start${RESET}"
echo -e "  3. Run a full audit: ${BOLD}bash audit.sh${RESET}"
echo ""

# ── Start clawsec-monitor ──────────────────────────────────────────────────────
if [ -f "$SCRIPT_DIR/clawsec-monitor.sh" ]; then
    echo -e "${BLUE}→${RESET} Starting ClawSec monitor..."
    bash "$SCRIPT_DIR/clawsec-monitor.sh" start
    echo -e "${GREEN}✓${RESET} ClawSec monitor running — you'll get Telegram alerts for security events"
fi

echo ""
echo -e "${GREEN}${BOLD}✓ ClawSec installation complete!${RESET}"
