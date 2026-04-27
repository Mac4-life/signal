# Signal — Claude Desktop / Cowork plugin

Mailchimp contact enrichment as a native Claude capability. Drop a paste-in or run `/morning-brief` — Claude proposes the right updates and previews them before any Mailchimp write.

## What's in here

- `.claude-plugin/plugin.json` — manifest (per Anthropic's plugin spec; manifest must live in `.claude-plugin/`, not at archive root).
- `.mcp.json` — MCP server declaration (header-Bearer transport against the Signal worker; auth is OAuth 2.1 + DCR, completed at install time).
- `skills/enrich-contacts/SKILL.md` — model-invokable skill that teaches Claude the enrichment workflow.
- `commands/signal-setup.md` — slash command that verifies the MCP round-trip + reminds about Mailchimp / Gmail OAuth.
- `commands/morning-brief.md` — slash command that reads the overnight brief and orchestrates the apply flow.
- `bundle.sh` — packages the plugin into `apps/plugin/dist/signal.plugin` for local testing.

The MCP server config lives in `.mcp.json` (separate file, not inline in `plugin.json`) — Cowork's marketplace runtime shadows inline `mcpServers` to avoid SDK double-load. Authorization is delegated to the worker's OAuth provider; there is no `userConfig.mcp_url` and no per-user URL to copy.

## Install

1. **Add the marketplace** — in Claude Desktop / Cowork, open **Customize → Personal plugins → Add marketplace** and paste:

   ```
   https://github.com/Mac4-life/signal
   ```

2. **Install Signal** — the Signal entry appears in the marketplace; click **Install**.

3. **Connect the connector** — click **Install** on the Signal connector. Your browser opens to the Signal consent page.

4. **Sign in with Mailchimp** if prompted, then click **Allow**. The browser tab closes itself; you're back in Cowork.

5. **Verify** — run `/signal-setup` in chat. Expected output: `Connected as <uid>. Signal MCP is reachable.`

> The marketplace URL is the same for everyone. Authorization happens via OAuth at install time — the worker mints a per-user token bound to your Mailchimp identity. There is no MCP URL to copy.

## After install

Your dashboard lives at **https://signal-lilac-six.vercel.app/dashboard**. From there you can:

- **Connect Mailchimp** (required) — completes the OAuth that gives Signal read + staged-write access to your audience.
- **Connect Gmail** (optional, but required for `/morning-brief`) — Signal reads the last 24 hours of inbox during the overnight cron and stages proposals.
- **Pick the audience the cron should run against** + your local delivery hour.
- **Revoke the plugin** — kills the OAuth grant; the plugin in Cowork starts returning `not_connected` until you re-authorize.
- **See recent briefs** — last ten dates with proposal + non-member counts.

You'll bounce here once during install (Step 4 above redirects through it). Bookmark it for managing connections later.

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

- **`/signal-setup` says "Signal can't reach your MCP endpoint"** — the OAuth grant has expired, was revoked, or never completed. Re-authorize via **Customize → Personal plugins → Signal → Manage → re-authorize**, or click **Install** on the Signal connector again.
- **Mailchimp tool calls return `not_connected`** — Mailchimp OAuth expired or was revoked. Reconnect at your Signal dashboard.
- **`/morning-brief` says "no brief yet"** — the cron pipeline runs at your scheduled delivery hour. The first brief lands the morning after Gmail is connected and at least one cron has run.
- **"Add marketplace" doesn't show the Signal plugin** — confirm the URL is exactly `https://github.com/Mac4-life/signal` and that the repo loads in a browser. The marketplace manifest is `.claude-plugin/marketplace.json` at the repo root; if it's missing, the marketplace fails silently.

## Links

- Master spec: `signal-spec.md` at repo root.
- App state: `APP_STATE.md` at repo root.
- Source: `apps/mcp-worker/` (Worker + cron) and `apps/web/` (Next.js + OAuth + dashboard).
