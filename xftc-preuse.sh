#!/bin/bash
# XFTC — PreToolUse hook
# Enforcement: Agent model (Opus block, Sonnet warn), verbose Bash commands

trap 'exit 0' ERR

HOOK_INPUT=$(cat)

# Fast exit for tools XFTC doesn't care about
TOOL_NAME=$(python3 -c "
import json, sys
d = json.loads(sys.argv[1]) if sys.argv[1].strip() else {}
print(d.get('tool_name', ''))
" "$HOOK_INPUT" 2>/dev/null || echo "")

echo "$TOOL_NAME" | grep -qE '^(Agent|Bash)$' || exit 0

PYTHONPATH="${HOME}/.claude" python3 -m xftc.xftc preuse <<< "$HOOK_INPUT" 2>/dev/null
EXIT_CODE=$?
exit $EXIT_CODE
