# Signal — Claude Desktop / Cowork plugin

Mailchimp contact enrichment as a native Claude capability. Drop a paste-in or run `/morning-brief` — Claude proposes the right updates and previews them before any Mailchimp write.

## What's in here

- `.claude-plugin/plugin.json` — manifest (per Anthropic's plugin spec; manifest must live in `.claude-plugin/`, not at archive root).
- `skills/enrich-contacts/SKILL.md` — model-invokable skill that teaches Claude the enrichment workflow.
- `commands/signal-setup.md` — slash command that verifies the MCP round-trip + reminds about Mailchimp / Gmail OAuth.
- `commands/morning-brief.md` — slash command that reads the overnight brief and orchestrates the apply flow.
- `bundle.sh` — packages the plugin into `apps/plugin/dist/signal.plugin` for upload.

The MCP server config is declared inline in `plugin.json.mcpServers.signal`. There is no `connectors/` directory — that was the wrong shape for Anthropic's plugin schema.

## Install

### 1. Pre-install setup (in your browser)

Open your **Signal dashboard**, complete:
- **Connect Mailchimp** — OAuth round-trip
- **Connect Gmail** — OAuth round-trip (required for `/morning-brief`)

Then copy your **MCP URL** from the dashboard. It looks like:

```
https://<worker-host>/mcp/<bearer-token>
```

Treat it like a credential — the bearer token in the path is your per-user authentication.

### 2. Build the bundle

```bash
bash apps/plugin/bundle.sh
```

Output: `apps/plugin/dist/signal.plugin`

### 3. Install in Claude Desktop

1. Open **Customize → Personal plugins → + → Upload plugin**
2. Select `apps/plugin/dist/signal.plugin`
3. When prompted for `mcp_url`, paste the MCP URL you copied above. (It's stored sensitively in your system keychain, not in plain config.)
4. Confirm install.

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
- **Plugin upload says "Plugin validation failed"** — usually a manifest schema mismatch. Confirm the bundle was built fresh (`bash apps/plugin/bundle.sh`) and the archive contains `.claude-plugin/plugin.json`.

## Links

- Master spec: `signal-spec.md` at repo root.
- App state: `APP_STATE.md` at repo root.
- Source: `apps/mcp-worker/` (Worker + cron) and `apps/web/` (Next.js + OAuth + dashboard).
