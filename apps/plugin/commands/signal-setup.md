---
description: Verify Signal is connected and walk the user through any setup steps they're missing. Calls whoami() to confirm the MCP URL is reaching the worker, reminds the user about Mailchimp + Gmail OAuth being separate connections, and lists the demo flows once everything is connected.
---

# /signal-setup

Verifies the Signal plugin is connected end-to-end. Authorization is OAuth 2.1 — the user clicked **Allow** on the consent screen at install time, and the worker minted a token bound to their Mailchimp identity. This command confirms the round-trip works and reminds the user of any remaining setup steps.

## What to do when the user invokes this command

### Step 1 — verify the MCP round-trip

Call the `whoami` tool.

- **Success (returns a `uid`):** print `Connected as <uid>. Signal MCP is reachable.` and continue to step 2.
- **`not_connected` / 401 / connection refused:** the OAuth grant has expired, was revoked, or never completed. Print:

  > Signal can't reach your MCP endpoint. The most likely cause is that your OAuth grant has lapsed.
  >
  > 1. Re-authorize: **Customize → Personal plugins → Signal → Manage → re-authorize**, or click **Install** on the Signal connector again.
  > 2. If that doesn't help, confirm the Signal worker is running.
  >
  > After re-authorizing, run `/signal-setup` again.

  Stop here.

### Step 2 — verify Mailchimp + Gmail OAuth

Call `list_audiences` to test Mailchimp connectivity.

- **Returns audiences:** Mailchimp is connected.
- **`not_connected`:** Mailchimp OAuth hasn't been completed (or has been revoked). Print:
  > Mailchimp isn't connected yet. Open your Signal dashboard and click **Connect Mailchimp** to complete OAuth. Then run `/signal-setup` again.

For Gmail, there's no equivalent test tool (Gmail is read by the overnight cron, not by chat tools). Print a reminder either way:

> **Gmail status:** Gmail is read by the overnight cron pipeline. If you haven't connected Gmail yet, open your Signal dashboard and click **Connect Gmail**. Without Gmail, `/morning-brief` won't have content to surface.

### Step 3 — print the demo flows

Print this verbatim:

> **What you can do now:**
>
> - **Mode 1 — preview pending proposals:** "What proposals are pending for my Acme contacts?"
> - **Mode 2 — paste-in enrichment:** "Sarah Chen moved to Google" + paste a LinkedIn screenshot or email.
> - **Mode 3 — overnight brief:** `/morning-brief` (lands the morning after Gmail is connected and at least one cron has run).
>
> **OAuth note:** Mailchimp and Gmail are separate connections behind your Signal dashboard. If any tool call later returns `not_connected`, that's the reconnect path.

## Failure modes to handle gracefully

- User runs `/signal-setup` immediately after install but skipped the OAuth consent → `whoami` fails. Step 1's error path covers this — point them at the connector's Install / re-authorize action.
- User has Mailchimp connected but not Gmail → `list_audiences` succeeds but `/morning-brief` later returns `null`. Step 2's Gmail reminder covers this.
- User revoked the plugin grant from the Signal dashboard → token starts 401-ing. Step 1's re-authorize copy is the path.
