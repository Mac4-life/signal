# Signal — public marketplace for Claude Desktop / Cowork install

Single-plugin marketplace exposing the Signal Mailchimp-enrichment plugin for Claude Desktop / Cowork install. The actual product source lives in a private repo; this public mirror exists only to provide a `git URL` that Claude Desktop / Cowork can clone for the **Add marketplace** install path.

## Install

In Claude Desktop / Cowork:

1. **Customize → Personal plugins → Add marketplace**
2. URL: `https://github.com/Mac4-life/signal`
3. Install **signal** from the marketplace
4. Click **Install** on the Signal connector — your browser opens to the Signal consent page
5. Sign in with Mailchimp if prompted, click **Allow**, the tab closes itself

After install, run `/signal-setup` in chat to verify the round-trip. Authorization is OAuth 2.1 — there's no MCP URL to paste.

## What's in here

- `.claude-plugin/marketplace.json` — single-plugin marketplace manifest
- `apps/plugin/` — the Signal plugin itself: `.claude-plugin/plugin.json`, `.mcp.json`, `skills/`, `commands/`, `README.md`, `bundle.sh`

Plugin version: see `apps/plugin/.claude-plugin/plugin.json`. Tagged `v0.2.0` — marketplace shape (OAuth + separate `.mcp.json`); previous `v0.1.x` `userConfig.mcp_url` shape is retired.
