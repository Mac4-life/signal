#!/usr/bin/env bash
# Build the Signal Cowork / Claude Desktop plugin bundle.
#
# Layout per Anthropic's plugin spec (code.claude.com/docs/en/plugins-reference):
# the manifest lives at `.claude-plugin/plugin.json`; `skills/`, `commands/`,
# and any other top-level dirs sit alongside `.claude-plugin/`, NOT inside it.
#
# Output: apps/plugin/dist/signal.plugin (zip archive).
# Run from repo root: bash apps/plugin/bundle.sh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
PLUGIN_DIR="$ROOT/apps/plugin"
DIST_DIR="$PLUGIN_DIR/dist"
BUNDLE_NAME="signal.plugin"
BUNDLE_PATH="$DIST_DIR/$BUNDLE_NAME"

# Sanity-check required artifacts.
for f in .claude-plugin/plugin.json skills/enrich-contacts/SKILL.md commands/signal-setup.md commands/morning-brief.md README.md; do
  if [ ! -f "$PLUGIN_DIR/$f" ]; then
    echo "✗ Missing required artifact: $PLUGIN_DIR/$f"
    exit 1
  fi
done

# Validate manifest JSON parses.
python3 -m json.tool "$PLUGIN_DIR/.claude-plugin/plugin.json" > /dev/null

mkdir -p "$DIST_DIR"
rm -f "$BUNDLE_PATH"

# Bundle. Zip the directory CONTENTS (Anthropic's plugin loader expects the
# `.claude-plugin/` directory + sibling content dirs at archive root, not
# nested under a `plugin/` folder). `package.json` is workspace-only metadata
# and is excluded.
(
  cd "$PLUGIN_DIR" && zip -rq "$BUNDLE_PATH" \
    .claude-plugin \
    skills \
    commands \
    README.md \
    -x "*.DS_Store"
)

echo ""
echo "✓ Built: $BUNDLE_PATH"
echo "  Size: $(du -h "$BUNDLE_PATH" | cut -f1)"
echo "  Contents:"
unzip -l "$BUNDLE_PATH" | sed 's/^/    /'
echo ""
echo "Install via Claude Desktop: Customize → Personal plugins → + → Upload plugin."
