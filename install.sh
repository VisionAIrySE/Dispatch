#!/bin/bash
# =============================================================================
# Dispatch — Install Script
# Runtime skill router for Claude Code
# =============================================================================

set -euo pipefail

DISPATCH_DIR="$HOME/.claude/skill-router"
HOOKS_DIR="$HOME/.claude/hooks"
SETTINGS="$HOME/.claude/settings.json"

echo "Installing Dispatch..."

# ── Check dependencies ─────────────────────────────────────────────────────
if ! python3 -c "import anthropic" 2>/dev/null; then
    echo "Installing anthropic Python package..."
    pip3 install anthropic --quiet
fi

if ! command -v npx &>/dev/null; then
    echo "ERROR: npx not found. Install Node.js first: https://nodejs.org"
    exit 1
fi

# ── Create directories ─────────────────────────────────────────────────────
mkdir -p "$DISPATCH_DIR" "$HOOKS_DIR"

# ── Copy Python modules ────────────────────────────────────────────────────
cp classifier.py "$DISPATCH_DIR/"
cp evaluator.py "$DISPATCH_DIR/"

# ── Seed state files ───────────────────────────────────────────────────────
[ -f "$DISPATCH_DIR/state.json" ] || echo '{"last_task_type":null,"last_updated":null}' > "$DISPATCH_DIR/state.json"
[ -f "$DISPATCH_DIR/registry.json" ] || echo '{"last_built":null,"plugins":{}}' > "$DISPATCH_DIR/registry.json"

# ── Install hook script ────────────────────────────────────────────────────
sed "s|/home/visionairy|$HOME|g" dispatch.sh > "$HOOKS_DIR/skill-router.sh"
chmod +x "$HOOKS_DIR/skill-router.sh"

# ── Register hook in settings.json ────────────────────────────────────────
if [ ! -f "$SETTINGS" ]; then
    echo '{"hooks":{}}' > "$SETTINGS"
fi

python3 - <<PYEOF
import json, sys

settings_path = "$SETTINGS"
hook_cmd = "bash $HOOKS_DIR/skill-router.sh"

with open(settings_path) as f:
    settings = json.load(f)

hooks = settings.setdefault("hooks", {})

for entry in hooks.get("UserPromptSubmit", []):
    for h in entry.get("hooks", []):
        if h.get("command") == hook_cmd:
            print("Dispatch already registered — skipping.")
            sys.exit(0)

hooks.setdefault("UserPromptSubmit", []).append({
    "hooks": [{
        "type": "command",
        "command": hook_cmd,
        "timeout_ms": 10000
    }]
})

with open(settings_path, "w") as f:
    json.dump(settings, f, indent=2)

print("Registered UserPromptSubmit hook in settings.json")
PYEOF

echo ""
echo "✓ Dispatch installed."
echo ""
echo "Next steps:"
echo "  1. Set your Anthropic API key: export ANTHROPIC_API_KEY=sk-ant-..."
echo "  2. Start a new Claude Code session"
echo "  3. Type a task — Dispatch fires automatically on topic shifts"
echo ""
