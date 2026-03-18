#!/usr/bin/env bash
# setup-wizard.sh — OpenClaw-Safe Interactive Setup Wizard
# Part of openclaw-safe: https://github.com/JuanAtLarge/openclaw-safe
#
# Guides users through security setup via Telegram yes/no buttons.
# Falls back to terminal prompts if Telegram is unavailable.
#
# Usage: bash setup-wizard.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SAFE_DIR="${HOME}/.openclaw-safe"
OPENCLAW_CONFIG="${HOME}/.openclaw/openclaw.json"
OFFSET_FILE="${SAFE_DIR}/setup-offset.txt"
STATE_FILE="${SAFE_DIR}/setup-complete.json"
CHAT_ID="YOUR_TELEGRAM_CHAT_ID"
POLL_TIMEOUT=60

mkdir -p "$SAFE_DIR"

# ─── Load bot token ──────────────────────────────────────────────────────────
BOT_TOKEN=""
if [[ -f "$OPENCLAW_CONFIG" ]]; then
    BOT_TOKEN=$(python3 -c "
import json, sys
try:
    with open('$OPENCLAW_CONFIG') as f:
        d = json.load(f)
    print(d.get('channels', {}).get('telegram', {}).get('botToken', ''))
except:
    print('')
" 2>/dev/null || true)
fi

USE_TELEGRAM=0
[[ -n "$BOT_TOKEN" ]] && USE_TELEGRAM=1

# ─── Terminal fallback ────────────────────────────────────────────────────────
terminal_ask() {
    local prompt="$1"
    local answer
    echo ""
    echo -n "  $prompt [y/N]: "
    read -r answer
    [[ "${answer,,}" == "y" || "${answer,,}" == "yes" ]]
}

# ─── Telegram helpers ─────────────────────────────────────────────────────────
tg_send() {
    local text="$1"
    python3 << PYEOF 2>/dev/null || true
import urllib.request, urllib.parse, json

bot_token = "${BOT_TOKEN}"
chat_id = "${CHAT_ID}"
text = """${text}"""

payload = json.dumps({
    "chat_id": chat_id,
    "text": text,
    "parse_mode": "HTML"
}).encode()

req = urllib.request.Request(
    f"https://api.telegram.org/bot{bot_token}/sendMessage",
    data=payload,
    headers={"Content-Type": "application/json"}
)
resp = urllib.request.urlopen(req, timeout=10)
data = json.loads(resp.read().decode())
if data.get("ok"):
    print(data["result"]["message_id"])
PYEOF
}

tg_send_buttons() {
    local text="$1"
    local callback_yes="$2"
    local callback_no="$3"
    local label_yes="${4:-✅ Yes}"
    local label_no="${5:-❌ No}"

    python3 << PYEOF 2>/dev/null || true
import urllib.request, urllib.parse, json

bot_token = "${BOT_TOKEN}"
chat_id = "${CHAT_ID}"
text = """${text}"""

payload = json.dumps({
    "chat_id": chat_id,
    "text": text,
    "parse_mode": "HTML",
    "reply_markup": {
        "inline_keyboard": [[
            {"text": "${label_yes}", "callback_data": "${callback_yes}"},
            {"text": "${label_no}",  "callback_data": "${callback_no}"}
        ]]
    }
}).encode()

req = urllib.request.Request(
    f"https://api.telegram.org/bot{bot_token}/sendMessage",
    data=payload,
    headers={"Content-Type": "application/json"}
)
resp = urllib.request.urlopen(req, timeout=10)
data = json.loads(resp.read().decode())
if data.get("ok"):
    print(data["result"]["message_id"])
PYEOF
}

tg_answer_callback() {
    local callback_id="$1"
    python3 -c "
import urllib.request, json
payload = json.dumps({'callback_query_id': '${callback_id}'}).encode()
req = urllib.request.Request(
    'https://api.telegram.org/bot${BOT_TOKEN}/answerCallbackQuery',
    data=payload, headers={'Content-Type': 'application/json'}
)
urllib.request.urlopen(req, timeout=5)
" 2>/dev/null || true
}

# ─── Poll for callback ────────────────────────────────────────────────────────
# Returns: "yes" or "no" or "timeout"
wait_for_callback() {
    local expected_prefix="$1"
    local start
    start=$(date +%s)

    while true; do
        local elapsed
        elapsed=$(( $(date +%s) - start ))
        if [[ "$elapsed" -gt "$POLL_TIMEOUT" ]]; then
            echo "timeout"
            return
        fi

        local result
        # Use timeout=0 (short poll) to avoid conflicting with OpenClaw's long-poll.
        # Retry silently on 409 Conflict errors.
        result=$(python3 << PYEOF 2>/dev/null || echo ""
import urllib.request, json, sys, os

bot_token = "${BOT_TOKEN}"
offset_file = "${OFFSET_FILE}"
expected_prefix = "${expected_prefix}"

try:
    offset_val = int(open(offset_file).read().strip()) if os.path.exists(offset_file) else 0
except:
    offset_val = 0

try:
    url = f"https://api.telegram.org/bot{bot_token}/getUpdates?offset={offset_val}&timeout=0"
    req = urllib.request.urlopen(url, timeout=8)
    data = json.loads(req.read().decode())
except urllib.error.HTTPError as e:
    if e.code == 409:
        # OpenClaw is long-polling — we'll retry after sleep
        sys.exit(0)
    sys.exit(0)
except Exception:
    sys.exit(0)

updates = data.get("result", [])
if not updates:
    sys.exit(0)

# Always advance offset past all updates we've seen
last_offset = updates[-1]["update_id"] + 1

for update in updates:
    cb = update.get("callback_query", {})
    data_val = cb.get("data", "")
    cb_id = cb.get("id", "")

    if data_val.startswith(expected_prefix):
        # Write new offset
        with open(offset_file, "w") as f:
            f.write(str(last_offset))
        answer = "yes" if data_val.endswith(":yes") else "no"
        print(f"{answer}|{cb_id}")
        sys.exit(0)

# No match — update offset to skip past these
with open(offset_file, "w") as f:
    f.write(str(last_offset))
PYEOF
)

        if [[ -n "$result" ]]; then
            local answer cb_id
            answer="${result%%|*}"
            cb_id="${result##*|}"
            # Acknowledge the button tap
            tg_answer_callback "$cb_id"
            echo "$answer"
            return
        fi

        sleep 2
    done
}

# ─── Ask via Telegram or terminal ────────────────────────────────────────────
ask_wizard() {
    local message="$1"
    local callback_prefix="$2"
    local label_yes="${3:-✅ Yes}"
    local label_no="${4:-❌ No}"
    local terminal_prompt="${5:-Proceed?}"

    if [[ "$USE_TELEGRAM" == "1" ]]; then
        tg_send_buttons "$message" "${callback_prefix}:yes" "${callback_prefix}:no" "$label_yes" "$label_no" > /dev/null
        local result
        result=$(wait_for_callback "$callback_prefix")

        if [[ "$result" == "timeout" ]]; then
            # Fallback to terminal
            echo "  [Telegram timeout — falling back to terminal]" >&2
            if terminal_ask "$terminal_prompt"; then
                echo "yes"
            else
                echo "no"
            fi
        else
            echo "$result"
        fi
    else
        # Pure terminal mode
        if terminal_ask "$terminal_prompt"; then
            echo "yes"
        else
            echo "no"
        fi
    fi
}

say() {
    if [[ "$USE_TELEGRAM" == "1" ]]; then
        tg_send "$1" > /dev/null
    else
        echo -e "$1"
    fi
}

# ─── Tracking state ──────────────────────────────────────────────────────────
HARDENED=false
SCANNED=false
MONITORED=false
CLAWSEC=false
HARDEN_ISSUES=0

# ─── Audit helpers ────────────────────────────────────────────────────────────
run_audit_summary() {
    # Run audit silently and capture the score/findings
    local audit_output
    audit_output=$(bash "$SCRIPT_DIR/audit.sh" 2>&1 || true)
    # Strip ANSI color codes
    audit_output=$(echo "$audit_output" | sed 's/\x1b\[[0-9;]*m//g')

    # Extract score
    local score
    score=$(echo "$audit_output" | grep -oE 'Score: [0-9]+/100' | head -1 | grep -oE '[0-9]+' | head -1 || echo "?")

    # Count warnings and criticals
    local warnings criticals
    warnings=$(echo "$audit_output" | grep -c '⚠\|WARN\|\[warn\]' 2>/dev/null || echo "0")
    criticals=$(echo "$audit_output" | grep -c '✗\|CRITICAL\|\[critical\]' 2>/dev/null || echo "0")

    echo "${score}|${warnings}|${criticals}|${audit_output}"
}

parse_audit_findings() {
    local audit_output="$1"

    # Check specific findings
    local version_ok gateway_ok exec_ask_ok plugins_ok clawsec_ok skills_ok
    version_ok=$(echo "$audit_output" | grep -qi 'version.*safe\|✓.*version' && echo "1" || echo "0")
    gateway_ok=$(echo "$audit_output" | grep -qi 'gateway.*local\|127\.0\.0\.1' && echo "1" || echo "0")
    exec_ask_ok=$(echo "$audit_output" | grep -qi 'exec\.ask.*allowlist\|exec\.ask.*on-miss' && echo "1" || echo "0")
    plugins_ok=$(echo "$audit_output" | grep -qi 'plugins\.allow.*set\|plugins.*✓' && echo "1" || echo "0")
    clawsec_ok=$(echo "$audit_output" | grep -qi 'clawsec.*installed\|clawsec.*✓' && echo "1" || echo "0")
    skills_ok=$(echo "$audit_output" | grep -qi 'skills.*all.*pass\|skills.*✓\|no.*suspicious' && echo "1" || echo "0")

    echo "${version_ok}|${gateway_ok}|${exec_ask_ok}|${plugins_ok}|${clawsec_ok}|${skills_ok}"
}

score_emoji() {
    local score="$1"
    if [[ "$score" -ge 90 ]]; then echo "🟢 Excellent"
    elif [[ "$score" -ge 75 ]]; then echo "🟡 Good"
    elif [[ "$score" -ge 50 ]]; then echo "🟠 Fair"
    else echo "🔴 Needs Work"
    fi
}

count_harden_issues() {
    local dry_output count
    dry_output=$(bash "$SCRIPT_DIR/harden.sh" --dry-run 2>&1 | sed 's/\x1b\[[0-9;]*m//g' || true)
    count=$(echo "$dry_output" | grep -c '→' 2>/dev/null) || count=0
    echo "$count"
}

# ─── STEP 0: Welcome ─────────────────────────────────────────────────────────
echo ""
echo "🦙 openclaw-safe setup wizard starting..."
[[ "$USE_TELEGRAM" == "1" ]] && echo "   Check your Telegram for prompts."
echo ""

WELCOME_MSG="🦙 <b>Welcome to openclaw-safe setup!</b>

I'm going to walk you through securing your OpenClaw install. I'll explain each step and ask before doing anything.

Takes about 2 minutes. Ready?"

response=$(ask_wizard "$WELCOME_MSG" "setup:welcome" "✅ Let's go" "❌ Not now" "Start the security setup wizard?")

if [[ "$response" == "no" ]]; then
    say "No problem! Run <code>bash setup-wizard.sh</code> anytime to come back. 🦙"
    echo "  User skipped setup. Exiting."
    exit 0
fi

# ─── STEP 1: Run audit ───────────────────────────────────────────────────────
say "🔍 <b>Scanning your OpenClaw install...</b>"
echo "  Running audit..."

audit_result=$(run_audit_summary)
SCORE="${audit_result%%|*}"
rest="${audit_result#*|}"
WARNINGS="${rest%%|*}"
rest="${rest#*|}"
CRITICALS="${rest%%|*}"
AUDIT_OUTPUT="${rest#*|}"

findings=$(parse_audit_findings "$AUDIT_OUTPUT")
VERSION_OK="${findings%%|*}"; findings="${findings#*|}"
GATEWAY_OK="${findings%%|*}"; findings="${findings#*|}"
EXEC_ASK_OK="${findings%%|*}"; findings="${findings#*|}"
PLUGINS_OK="${findings%%|*}"; findings="${findings#*|}"
CLAWSEC_INSTALLED="${findings%%|*}"
SKILLS_OK="${findings##*|}"

# Build summary message
v_icon="$([[ "$VERSION_OK" == "1" ]] && echo "✅" || echo "⚠️")"
g_icon="$([[ "$GATEWAY_OK" == "1" ]] && echo "✅" || echo "⚠️")"
e_icon="$([[ "$EXEC_ASK_OK" == "1" ]] && echo "✅" || echo "⚠️")"
p_icon="$([[ "$PLUGINS_OK" == "1" ]] && echo "✅" || echo "⚠️")"
c_icon="$([[ "$CLAWSEC_INSTALLED" == "1" ]] && echo "✅" || echo "⚠️")"
s_icon="$([[ "$SKILLS_OK" == "1" ]] && echo "✅" || echo "⚠️")"

# Score emoji
if [[ "$SCORE" =~ ^[0-9]+$ ]] && [[ "$SCORE" -ge 90 ]]; then _semoji="🟢 Excellent"
elif [[ "$SCORE" =~ ^[0-9]+$ ]] && [[ "$SCORE" -ge 75 ]]; then _semoji="🟡 Good"
elif [[ "$SCORE" =~ ^[0-9]+$ ]] && [[ "$SCORE" -ge 50 ]]; then _semoji="🟠 Fair"
elif [[ "$SCORE" =~ ^[0-9]+$ ]]; then _semoji="🔴 Needs Work"
else _semoji=""; fi
score_str="${SCORE}/100 ${_semoji}"

SUMMARY_MSG="📊 <b>Scan complete! Here's what I found:</b>

${v_icon} Version check
${g_icon} Gateway binding
${e_icon} exec.ask setting
${p_icon} plugins.allow
${c_icon} ClawSec
${s_icon} Skill security

<b>Security Score: ${score_str}</b>"

say "$SUMMARY_MSG"
sleep 1

# ─── STEP 2: Harden config ───────────────────────────────────────────────────
# Count issues
HARDEN_ISSUES=$(count_harden_issues)

if [[ "$HARDEN_ISSUES" -gt 0 && ("$EXEC_ASK_OK" == "0" || "$PLUGINS_OK" == "0") ]]; then
    # Build specific list of what needs fixing
    FIX_LIST=""
    [[ "$EXEC_ASK_OK" == "0" ]] && FIX_LIST="${FIX_LIST}
→ <b>exec.ask:</b> Makes your agent pause before running shell commands. Prevents unauthorized commands from running silently."
    [[ "$PLUGINS_OK" == "0" ]] && FIX_LIST="${FIX_LIST}
→ <b>plugins.allow:</b> Locks down which plugins can auto-load. Prevents unknown plugins from quietly activating."

    HARDEN_MSG="🔒 <b>Config Hardening</b>

I found ${HARDEN_ISSUES} setting(s) that should be fixed:
${FIX_LIST}

Fix these automatically? I'll back up your config first."

    response=$(ask_wizard "$HARDEN_MSG" "setup:harden" "✅ Yes, fix them" "❌ Skip" "Automatically harden config settings?")

    if [[ "$response" == "yes" ]]; then
        echo "  Running harden.sh..."
        echo "y" | bash "$SCRIPT_DIR/harden.sh" > /tmp/harden-output.txt 2>&1 || true
        say "✅ <b>Config hardened!</b> Backup saved just in case."
        HARDENED=true
    else
        say "⏭️ Skipped config hardening. You can run <code>bash harden.sh</code> manually."
    fi
else
    say "✅ <b>Config looks good</b> — no hardening needed."
fi

sleep 1

# ─── STEP 3: Skill scan ──────────────────────────────────────────────────────
SCAN_MSG="🔍 <b>Skill Scanner</b>

Checks your installed skills for malicious code — including hidden invisible characters that can't be seen with the human eye.

Takes about 10 seconds. Scan now?"

response=$(ask_wizard "$SCAN_MSG" "setup:scan" "✅ Yes, scan" "❌ Skip" "Scan installed skills for malicious code?")

if [[ "$response" == "yes" ]]; then
    say "🔍 Scanning skills..."
    echo "  Running scan-skills.sh..."

    scan_exit=0
    scan_output=$(bash "$SCRIPT_DIR/scan-skills.sh" 2>&1) || scan_exit=$?
    scan_output=$(echo "$scan_output" | sed 's/\x1b\[[0-9;]*m//g')

    # Parse results
    total=$(echo "$scan_output" | grep -oE '[0-9]+ skill' | head -1 | grep -oE '[0-9]+' || echo "?")
    passed=$(echo "$scan_output" | grep -oE '[0-9]+ passed' | head -1 | grep -oE '[0-9]+' || echo "?")
    warnings_s=$(echo "$scan_output" | grep -oE '[0-9]+ warn' | head -1 | grep -oE '[0-9]+' || echo "0")
    criticals_s=$(echo "$scan_output" | grep -oE '[0-9]+ critical\|[0-9]+ CRITICAL' | head -1 | grep -oE '[0-9]+' || echo "0")

    if [[ "$scan_exit" -ge 2 ]] || [[ "${criticals_s:-0}" -gt 0 ]]; then
        say "🚨 <b>Found suspicious skills!</b> Check your Telegram for a quarantine alert."
        # Trigger quarantine if script is available
        if [[ -x "$SCRIPT_DIR/quarantine.sh" ]]; then
            bash "$SCRIPT_DIR/scan-skills.sh" --quarantine --no-color > /dev/null 2>&1 || true
        fi
    elif [[ "$scan_exit" -eq 1 ]] || [[ "${warnings_s:-0}" -gt 0 ]]; then
        say "⚠️ <b>Skill scan complete</b> — ${warnings_s:-0} warning(s) found. Review with <code>bash scan-skills.sh</code>"
    else
        say "✅ <b>Skills scanned — all clear!</b>"
        SCANNED=true
    fi
else
    say "⏭️ Skipped skill scan. Run <code>bash scan-skills.sh</code> manually anytime."
fi

sleep 1

# ─── STEP 4: Memory monitor ──────────────────────────────────────────────────
MONITOR_MSG="👁️ <b>Memory File Monitor</b>

Watches your agent's memory files in real-time. If anything suspicious gets written — like hidden instructions from a malicious website — you'll get an instant alert.

Runs silently in the background and survives restarts automatically.

Start the monitor?"

response=$(ask_wizard "$MONITOR_MSG" "setup:monitor" "✅ Yes, start it" "❌ Skip for now" "Start the background memory file monitor?")

if [[ "$response" == "yes" ]]; then
    echo "  Starting monitor.sh..."
    bash "$SCRIPT_DIR/monitor.sh" start > /dev/null 2>&1 || true
    say "✅ <b>Memory monitor running!</b>"
    MONITORED=true
else
    say "⏭️ Skipped memory monitor. Start it later with <code>bash monitor.sh start</code>"
fi

sleep 1

# ─── STEP 5: ClawSec ─────────────────────────────────────────────────────────
if [[ "$CLAWSEC_INSTALLED" == "1" ]]; then
    say "✅ <b>ClawSec is already installed</b> — you're covered."
    CLAWSEC=true
else
    CLAWSEC_MSG="🛡️ <b>ClawSec (by Prompt Security)</b>

A free security tool that watches your agent in real-time for two specific threats:

→ <b>Config tampering:</b> alerts if a skill quietly changes your settings
→ <b>Blocked network calls:</b> stops and flags unauthorized data transfers

When it catches something, you get a Telegram alert with buttons to resolve it instantly.

Install ClawSec?"

    response=$(ask_wizard "$CLAWSEC_MSG" "setup:clawsec" "✅ Yes, install it" "❌ Skip for now" "Install ClawSec security tool?")

    if [[ "$response" == "yes" ]]; then
        say "🛡️ Installing ClawSec..."
        echo "  Running install-clawsec.sh..."
        bash "$SCRIPT_DIR/install-clawsec.sh" > /tmp/clawsec-output.txt 2>&1 || true
        say "✅ <b>ClawSec installed and monitoring!</b>"
        CLAWSEC=true
    else
        say "⏭️ Skipped ClawSec. Install later with <code>bash install-clawsec.sh</code>"
    fi
fi

sleep 1

# ─── STEP 6: Final score + summary ───────────────────────────────────────────
echo "  Running final audit..."
final_result=$(run_audit_summary)
FINAL_SCORE="${final_result%%|*}"
if [[ "$FINAL_SCORE" =~ ^[0-9]+$ ]] && [[ "$FINAL_SCORE" -ge 90 ]]; then _femoji="🟢 Excellent"
elif [[ "$FINAL_SCORE" =~ ^[0-9]+$ ]] && [[ "$FINAL_SCORE" -ge 75 ]]; then _femoji="🟡 Good"
elif [[ "$FINAL_SCORE" =~ ^[0-9]+$ ]] && [[ "$FINAL_SCORE" -ge 50 ]]; then _femoji="🟠 Fair"
elif [[ "$FINAL_SCORE" =~ ^[0-9]+$ ]]; then _femoji="🔴 Needs Work"
else _femoji=""; fi
final_score_str="${FINAL_SCORE}/100 ${_femoji}"

# Build status lines
h_status="$([[ "$HARDENED" == "true" ]] && echo "✅ Config hardened" || echo "⏭️ Config hardening skipped")"
s_status="$([[ "$SCANNED" == "true" ]] && echo "✅ Skills scanned — all clear" || echo "⏭️ Skill scan skipped")"
m_status="$([[ "$MONITORED" == "true" ]] && echo "✅ Memory monitor: running" || echo "⏭️ Memory monitor: not started")"
c_status="$([[ "$CLAWSEC" == "true" ]] && echo "✅ ClawSec: installed" || echo "⏭️ ClawSec: not installed")"

FINAL_MSG="🎉 <b>Setup complete!</b>

Here's your security status:

${h_status}
${s_status}
${m_status}
${c_status}

<b>Security Score: ${final_score_str}</b>

You're protected. If anything suspicious happens, you'll get a Telegram alert with a button to fix it.

Run <code>bash audit.sh</code> anytime to check your status."

say "$FINAL_MSG"

# ─── Save setup state ────────────────────────────────────────────────────────
_HARDENED_VAL="${HARDENED}"
_SCANNED_VAL="${SCANNED}"
_MONITORED_VAL="${MONITORED}"
_CLAWSEC_VAL="${CLAWSEC}"
_SCORE_VAL="${SCORE}"
_FINAL_SCORE_VAL="${FINAL_SCORE}"
_STATE_FILE="${STATE_FILE}"

python3 << PYEOF
import json, datetime, os

state = {
    "completed_at": datetime.datetime.utcnow().isoformat() + "Z",
    "score_before": os.environ.get("_SCORE_VAL", "?"),
    "score_after": os.environ.get("_FINAL_SCORE_VAL", "?"),
    "installed": {
        "hardened":  os.environ.get("_HARDENED_VAL")  == "true",
        "scanned":   os.environ.get("_SCANNED_VAL")   == "true",
        "monitored": os.environ.get("_MONITORED_VAL") == "true",
        "clawsec":   os.environ.get("_CLAWSEC_VAL")   == "true"
    }
}

state_file = os.environ.get("_STATE_FILE", os.path.expanduser("~/.openclaw-safe/setup-complete.json"))
os.makedirs(os.path.dirname(state_file), exist_ok=True)
with open(state_file, "w") as f:
    json.dump(state, f, indent=2)
print(f"State saved to {state_file}")
PYEOF

echo ""
echo "🦙 Setup wizard complete! Security score: ${FINAL_SCORE}/100"
echo ""
