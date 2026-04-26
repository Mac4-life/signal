# Signal — public marketplace for Claude Desktop install testing

Single-plugin marketplace exposing the Signal Mailchimp-enrichment plugin for Claude Desktop install. The actual product source is at the private Intuit repo; this public mirror exists only to provide a `git URL` Claude Desktop can clone for the **Add marketplace** install path.

## Install

In Claude Desktop:

1. **Customize → Personal plugins → + → Add marketplace**
2. URL: `Mac4-life/signal-plugin` (or the full git URL)
3. Sync, then install **signal** from the marketplace
4. When prompted for `mcp_url`, paste your Signal MCP URL from your dashboard

## What's in here

- `.claude-plugin/marketplace.json` — single-plugin marketplace manifest
- `apps/plugin/` — the Signal plugin (manifest, skill, slash commands, README, bundle script)
