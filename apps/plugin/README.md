# Signal — Claude Desktop / Cowork plugin

Mailchimp contact enrichment as a native Claude capability. Drop a paste-in or run `/morning-brief` — Claude proposes the right updates and previews them before any Mailchimp write.

## What's in here

- `.claude-plugin/plugin.json` — manifest (per Anthropic's plugin spec; manifest must live in `.claude-plugin/`, not at archive root).
- `skills/enrich-contacts/SKILL.md` — model-invokable skill that teaches Claude the enrichment workflow.
- `commands/signal-setup.md` — slash command that verifies the MCP round-trip + reminds about Mailchimp / Gmail OAuth.
- `commands/morning-brief.md` — slash command that reads the overnight brief and orchestrates the apply flow.
- `bundle.sh` — packages the plugin into `apps/plugin/dist/signal.plugin` for local testing / archive distribution.

The MCP server config is declared inline in `plugin.json.mcpServers.signal`. There is no `connectors/` directory — that was the wrong shape for Anthropic's plugin schema.

## Install

### 1. Sign in and grab your MCP URL

Open <https://signal-lilac-six.vercel.app/> and:

1. Click **Sign in with Mailchimp** → complete OAuth → land on the dashboard.
2. (Optional, recommended) Click **Connect Gmail** — required for `/morning-brief`.
3. On the dashboard, **reveal and copy** your MCP URL. It looks like:

```
https://<worker-host>/mcp/<bearer-token>
```

Treat it like a credential — the bearer token in the path is your per-user authentication.

### 2. Add the Signal marketplace in Claude Desktop / Cowork

1. Open **Customize → Personal plugins → Add marketplace**.
2. Paste: `https://github.com/Mac4-life/signal`
3. The Signal marketplace appears — click **Install** on the Signal plugin.

> The marketplace URL is the same for everyone. Your MCP URL (from step 1) is unique per user.

### 3. Provide your MCP URL

When the install dialog prompts for `mcp_url`, paste the URL you copied from your dashboard. It's stored sensitively in your system keychain, not in plain config. To update it later: **Customize → Personal plugins → Signal → Settings**.

### 4. Verify

Run `/signal-setup` in chat. Expected output: `Connected as <uid>. Signal MCP is reachable.`

## Prereqs

- A Signal worker deployed (Cloudflare Workers) — see the repo root README.
- A Signal web app running (Next.js / Vercel) — same.
- A Mailchimp account with at least one audience.
- A Gmail account (for the overnight brief).

## Usage

**Mode 1 — find / preview proposals:**

> "What proposals are pending for Acme contacts?"

**Mode 2 — paste-in enrichment:**

> "Sarah Chen moved to Google" + paste a LinkedIn screenshot or email.

**Mode 3 — overnight brief:**

> `/morning-brief`

## Troubleshooting

- **`/signal-setup` says "Signal can't reach your MCP endpoint"** — the `mcp_url` config is wrong, the bearer was rotated, or the worker is down. Update via **Customize → Personal plugins → Signal → Settings**, or reinstall.
- **Mailchimp tool calls return `not_connected`** — Mailchimp OAuth expired or was revoked. Reconnect at your Signal dashboard.
- **`/morning-brief` says "no brief yet"** — the cron pipeline runs at your scheduled delivery hour. The first brief lands the morning after Gmail is connected and at least one cron has run.
- **"Add marketplace" doesn't show the Signal plugin** — confirm the URL is exactly `https://github.com/Mac4-life/signal` and that the repo loads in a browser. The marketplace manifest is `.claude-plugin/marketplace.json` at the repo root; if it's missing, the marketplace fails silently.

## Links

- Master spec: `signal-spec.md` at repo root.
- App state: `APP_STATE.md` at repo root.
- Source: `apps/mcp-worker/` (Worker + cron) and `apps/web/` (Next.js + OAuth + dashboard).
