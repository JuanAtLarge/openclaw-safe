# Safe Config Defaults

This is a template for a hardened `~/.openclaw/openclaw.json` for personal/SMB use. **Don't blindly copy this** — use it as a reference and adjust to your setup.

---

## Annotated Safe Config

```json
{
  "meta": {
    "lastTouchedVersion": "2026.3.13"
  },

  "plugins": {
    // IMPORTANT: List every plugin you trust here.
    // If this is empty, non-bundled plugins can auto-load without your knowledge.
    "allow": ["telegram"],
    
    "entries": {
      "telegram": {
        "enabled": true
      }
    }
  },

  "gateway": {
    "mode": "local",
    "auth": {
      "mode": "token"
      // token is auto-generated — don't hardcode one here
    }
    // If you use a reverse proxy, add:
    // "trustedProxies": ["127.0.0.1"]
  },

  "channels": {
    "telegram": {
      "enabled": true,
      "dmPolicy": "pairing",    // GOOD: only paired accounts can DM
      "groupPolicy": "allowlist", // GOOD: only listed groups can interact
      // Add your user ID(s) here:
      "groupAllowFrom": [],      // fill this in if using groupPolicy: allowlist
      "streaming": "partial"
    }
  },

  "agents": {
    "defaults": {
      "model": {
        "primary": "anthropic/claude-sonnet-4-6"
      },
      "workspace": "/Users/YOURUSERNAME/.openclaw/workspace",
      
      // Context pruning helps prevent memory bloat
      "contextPruning": {
        "mode": "cache-ttl",
        "ttl": "1h"
      },
      
      // Compaction safeguard mode is safer than aggressive
      "compaction": {
        "mode": "safeguard"
      }
    }
  }
}
```

---

## What Each Setting Does (Plain English)

### `plugins.allow`
Controls which plugins can load. Empty means "anything can load." Fill this in with only the plugins you actually use. Restart the gateway after changing.

### `gateway.mode: "local"`
Keeps the Control UI on loopback only (127.0.0.1). Nobody outside your machine can reach it. Don't change to "remote" unless you know exactly what you're doing and have auth set up properly.

### `channels.telegram.dmPolicy: "pairing"`
Only Telegram users who have paired with your OpenClaw can DM the bot. Anyone else is ignored. This is the right setting for personal use.

### `channels.telegram.groupPolicy: "allowlist"`
Only Telegram groups you've explicitly listed can interact with the bot. If your bot is in a group you don't control, this prevents people in that group from sending it commands.

### `compaction.mode: "safeguard"`
When session context gets long, OpenClaw needs to compress it. Safeguard mode is more conservative — it won't throw away important context to save tokens. Better for personal use where every session has context that matters.

---

## Settings That Are NOT in the Default Config (But Maybe Should Be)

These may not exist yet or may require upcoming versions — check OpenClaw docs:

- `security.promptInjectionGuard` — if/when this exists, turn it on
- `cron.execApproval` — requiring approval for cron tool calls before they run
- `memory.writePolicy` — restricting which sessions can write to shared memory

Watch for these in release notes.
