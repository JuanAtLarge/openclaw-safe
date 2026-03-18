# Honest Gaps — What We Can't Fix Yet 🕳️

This is the uncomfortable part. Here's what's genuinely hard or impossible to fully solve right now for personal OpenClaw users.

---

## Gap 1: Prompt Injection in External Content Is Basically Unsolvable (Right Now)

**The problem:** Your agent reads a webpage, Reddit post, or email. An attacker embeds invisible or cleverly hidden instructions in that content. The LLM follows them.

**What you can do:** Narrow the scope of what crons are allowed to do. A cron that can only post a summary to Telegram has a much smaller blast radius than one that can send emails, modify files, and run scripts.

**What you can't do:** Reliably detect injection attacks. LLMs are trained to follow instructions. They don't have a reliable "this instruction came from untrusted content" filter. OpenClaw has no semantic sandbox at this layer.

**Honest assessment:** If you're running crons that fetch external content AND take high-stakes actions (sending emails, modifying important files, making purchases), you're accepting meaningful risk. The mitigation is scope limitation, not elimination.

---

## Gap 2: No Cryptographic Agent-to-Agent Auth

**The problem:** When the main agent spawns a subagent, there's no cryptographic handshake. The subagent can't prove it's the legitimate OpenClaw subagent runtime, and the main agent can't verify the instructions it's following actually came from you.

**What OpenClaw does:** Uses session-level token auth at the gateway layer. That's better than nothing, but it's not mutual auth.

**What you can't do:** Verify the full chain of trust from your original instruction → main agent → subagent → tool call.

**Honest assessment:** For personal/SMB use, this is mostly theoretical risk. The more concrete risk is a malicious skill that impersonates a legitimate one. Keep skills minimal and from trusted sources.

---

## Gap 3: Memory Is Flat and Shared

**The problem:** All crons and agents that run in the same session context share the same memory system. There's no per-cron memory isolation.

**Example attack path:**
1. Reddit cron fetches a malicious post with injected instructions
2. Injected instructions tell the agent to write a fake "memory" about the user's credentials
3. The next agent session loads that memory and acts on it

**What you can do:**
- Use `sessionTarget: "isolated"` for crons that read external content (well-configured crons already do this ✅)
- Review memory files periodically
- Keep state files separate from the workspace memory directory

**What you can't do:** Fully sandbox cron memory from main session memory. Isolated sessions still share the underlying vector store.

---

## Gap 4: ClawHub Skill Verification Is Voluntary

**The stat:** 824 malicious skills out of 10,700. That's 7.7%.

**The problem:** ClawHub doesn't have mandatory security scanning before publish. ClawSec scanning is a tool you have to run yourself. There's no "verified safe" badge with any enforcement behind it.

**What you can do:**
- Scan with ClawSec before installing anything from ClawHub
- Read the SKILL.md before installing — does it need more permissions than it should?
- Prefer bundled skills (they're audited by the OpenClaw team)
- Check the skill's GitHub repo and issue history if it has one

**What you can't do:** Know for certain a skill is safe. Even "clean" skills can receive malicious updates.

---

## Gap 5: Browser Sessions Are Not Isolated Per Cron

**The problem:** Multiple crons can use the same browser profile (e.g., `profile=openclaw`). If one cron gets compromised and does something in the browser, another cron with the same profile has access to those same cookies and sessions.

**What you can do:** Accept this as a known limitation for now. Keep browser-using crons to a minimum.

**What you can't do:** Easily run per-cron isolated browser profiles without significant manual setup.

---

## Gap 6: No Outbound Traffic Monitoring

**The problem:** If an agent is exfiltrating data (sending an email, making an API call to an unknown endpoint), there's no built-in way to catch it.

**What you can do:** 
- Use Cisco scanner for network-level monitoring
- Review Telegram message logs periodically (what did the agent send?)
- Check `openclaw logs --follow` occasionally to spot unexpected tool calls

**What you can't do:** Get automatic alerts when an agent does something suspicious without a third-party tool.

---

## The Bottom Line

You can meaningfully reduce your risk with the steps in CHECKLIST.md. You cannot eliminate it. 

The most important thing is keeping cron scope narrow: an agent that can only post to Twitter can only hurt you via Twitter. An agent that can read your emails, modify files, and make API calls can hurt you a lot more ways.
