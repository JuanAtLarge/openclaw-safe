#!/usr/bin/env bash
# setup-wizard.sh — OpenClaw-Safe Setup Wizard (stateful, agent-driven)
#
# This script starts the wizard by sending the first Telegram button message.
# The agent (via HEARTBEAT.md) handles each button tap and drives the rest.
#
# Usage: bash setup-wizard.sh

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SAFE_DIR="${HOME}/.openclaw-safe"
OPENCLAW_CONFIG="${HOME}/.openclaw/openclaw.json"
STATE_FILE="${SAFE_DIR}/wizard-state.json"
CHAT_ID=$(python3 -c "
import json, os
try:
    creds = json.load(open(os.path.expanduser('~/.openclaw/credentials/telegram-default-allowFrom.json')))
    print(creds['allowFrom'][0])
except:
    print('')
" 2>/dev/null || true)

if [[ -z "$CHAT_ID" ]]; then
    echo "⚠ Could not determine your Telegram chat ID."
    echo "  Make sure OpenClaw is paired with Telegram, then retry."
    exit 1
fi

mkdir -p "$SAFE_DIR"

# ─── Load bot token ──────────────────────────────────────────────────────────
BOT_TOKEN=$(python3 -c "
import json, sys
try:
    with open('${OPENCLAW_CONFIG}') as f:
        d = json.load(f)
    print(d.get('channels', {}).get('telegram', {}).get('botToken', ''))
except:
    print('')
" 2>/dev/null || true)

if [[ -z "$BOT_TOKEN" ]]; then
    echo "⚠ No Telegram bot token found in openclaw.json"
    echo "  Run the setup steps manually:"
    echo "  1. bash harden.sh"
    echo "  2. bash scan-skills.sh"
    echo "  3. bash monitor.sh start"
    echo "  4. bash install-clawsec.sh"
    exit 0
fi

# ─── Run quick audit to get current state ────────────────────────────────────
echo "🔍 Scanning your install..."
audit_output=$(bash "$SCRIPT_DIR/audit.sh" 2>&1 | sed 's/\x1b\[[0-9;]*m//g')
score=$(echo "$audit_output" | grep -oE 'Score: [0-9]+/100' | head -1 | grep -oE '[0-9]+' | head -1 || echo "?")

# ─── Save initial wizard state ───────────────────────────────────────────────
python3 -c "
import json, os
state = {
    'step': 'welcome',
    'score_before': '${score}',
    'hardened': False,
    'scanned': False,
    'monitored': False,
    'clawsec': False,
    'script_dir': '${SCRIPT_DIR}'
}
with open('${STATE_FILE}', 'w') as f:
    json.dump(state, f, indent=2)
print('State saved')
"

# ─── Send welcome message with buttons ───────────────────────────────────────
echo "📱 Sending setup wizard to Telegram..."

python3 -c "
import urllib.request, json

bot_token = '${BOT_TOKEN}'
chat_id = '${CHAT_ID}'

text = '''🦙 Welcome to openclaw-safe setup!

I'll walk you through securing your OpenClaw install. I'll explain each step and ask before doing anything.

Current security score: ${score}/100

Takes about 2 minutes. Ready?'''

payload = json.dumps({
    'chat_id': chat_id,
    'text': text,
    'reply_markup': {
        'inline_keyboard': [[
            {'text': '✅ Let\'s go', 'callback_data': 'setup:welcome:yes'},
            {'text': '❌ Not now',   'callback_data': 'setup:welcome:no'}
        ]]
    }
}).encode()

req = urllib.request.Request(
    f'https://api.telegram.org/bot{bot_token}/sendMessage',
    data=payload,
    headers={'Content-Type': 'application/json'}
)
resp = json.loads(urllib.request.urlopen(req).read())
if resp.get('ok'):
    print('✅ Setup wizard sent to Telegram — tap the buttons to continue.')
else:
    print('❌ Failed to send:', resp)
"
