#!/bin/bash
# XFTC — UserPromptSubmit hook
# Checks: MCP overhead, peak hours, 60% compact, CLAUDE.md length,
#         cache timeout reminder, version notification (Pro)
# Ghost notification on first trigger for Free/BYOK

trap 'exit 0' ERR

HOOK_INPUT=$(cat)

# Inject cwd into the data passed to Python
CWD=$(pwd)
AUGMENTED=$(python3 -c "
import json, sys
d = json.loads(sys.argv[1]) if sys.argv[1].strip() else {}
d['cwd'] = sys.argv[2]
print(json.dumps(d))
" "$HOOK_INPUT" "$CWD" 2>/dev/null || echo "{\"cwd\":\"$CWD\"}")

PYTHONPATH="${HOME}/.claude" python3 -m xftc.xftc submit <<< "$AUGMENTED" 2>/dev/null || exit 0
