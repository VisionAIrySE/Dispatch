#!/bin/bash
# =============================================================================
# Pre-Edit System Impact Audit Hook
#
# Fires before Edit or Write on source files. Injects the 6-question
# System Impact Audit as a reminder. Fires ONCE per project per day to
# avoid per-edit noise.
#
# Applies globally to all Visionairy projects.
# =============================================================================

trap 'exit 0' ERR

HOOK_INPUT=$(cat)

# ── Extract the file path being edited ────────────────────────────────────
FILE_PATH=$(python3 -c "
import sys, json
d = json.loads(sys.stdin.read())
ti = d.get('tool_input', {})
print(ti.get('file_path', ''))
" <<< "$HOOK_INPUT" 2>/dev/null || echo "")

# ── Only fire for source files ─────────────────────────────────────────────
echo "$FILE_PATH" | grep -qE '\.(ts|tsx|js|jsx|py|sql|sh|dart)$' || exit 0

# ── Once per project per day ───────────────────────────────────────────────
DIR_HASH=$(pwd | md5sum | cut -c1-8 2>/dev/null || echo "default")
DATE=$(date +%Y%m%d)
FLAG="/tmp/claude-audit-reminded-${DIR_HASH}-${DATE}"

[ -f "$FLAG" ] && exit 0  # Already reminded today — allow edit

touch "$FLAG"

# ── Inject audit reminder ──────────────────────────────────────────────────
python3 - <<'PYEOF'
import json

msg = (
    "📋 SYSTEM IMPACT AUDIT — required before code changes\n\n"
    "Answer these 6 questions before proceeding:\n\n"
    "  1. DATA FLOW      — What data enters/exits? What if the format changes?\n"
    "  2. CALLERS        — Who calls this? What do they expect?\n"
    "  3. CALLEES        — What does this call? What does it need?\n"
    "  4. SIDE EFFECTS   — DB writes? API calls? State mutations?\n"
    "  5. STATE          — Race conditions? Caches? Locks?\n"
    "  6. ERROR PATH     — When this fails, what breaks downstream?\n\n"
    "─────────────────────────────────────────────────────────────────────\n"
    "This reminder fires once per project per day. Proceed with your edit\n"
    "after confirming you've considered the above."
)

print(json.dumps({"decision": "block", "reason": msg}))
PYEOF
