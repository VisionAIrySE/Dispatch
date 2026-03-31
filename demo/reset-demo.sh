#!/bin/bash
# =============================================================================
# ToolDispatch — Demo Reset Script
#
# Run this BEFORE every GIF recording session.
# Cleans all state so both demos fire cleanly on first trigger.
#
# Usage:  bash ~/Dispatch/demo/reset-demo.sh
# =============================================================================

set -e

DISPATCH_DIR="$HOME/Dispatch"
DEMO_REPO="$HOME/dispatch-demo"
STATE_FILE="$HOME/.claude/dispatch/state.json"

echo ""
echo "  ToolDispatch — Demo Reset"
echo "  ────────────────────────────"

# ── 1. Reset XF Audit demo repo ─────────────────────────────────────────────
echo "  [1/5] Resetting XF Audit demo repo..."
mkdir -p "$DEMO_REPO"
cd "$DEMO_REPO"

# Init git if not already a repo
git rev-parse --git-dir &>/dev/null || git init -q

# Restore both demo files to stub state from Dispatch source
cp "$DISPATCH_DIR/demo/notifier.py" "$DEMO_REPO/notifier.py"
cp "$DISPATCH_DIR/demo/monitor.py"  "$DEMO_REPO/monitor.py"

# Commit if files changed
git add notifier.py monitor.py 2>/dev/null || true
git diff --cached --quiet 2>/dev/null || git commit -m "reset: restore stub state" -q 2>/dev/null || true

echo "        ✓ dispatch-demo/ restored to stub state"

# ── 2. Clear XF Audit symbol history in demo repo ───────────────────────────
echo "  [2/5] Clearing XF Audit state..."
mkdir -p "$DEMO_REPO/.xf"
echo '[]' > "$DEMO_REPO/.xf/recent_symbols.json"
# Also clear session state (trust level resets for clean consent display)
echo '{"trust_level": 0}' > "$DEMO_REPO/.xf/session_state.json"
echo "        ✓ XF Audit symbol history cleared"

# ── 3. Reset Dispatch state.json ────────────────────────────────────────────
echo "  [3/5] Resetting Dispatch session state..."
python3 -c "
import json, os, tempfile
f = '$STATE_FILE'
try:
    d = json.load(open(f))
except Exception:
    d = {}
d['last_recommended_category'] = ''
d['session_recommendations'] = 0
d['session_audits'] = 0
d['session_blocks'] = 0
d['session_id'] = ''
d['bypass'] = {}
dir_ = os.path.dirname(os.path.abspath(f))
fd, tmp = tempfile.mkstemp(dir=dir_)
with os.fdopen(fd, 'w') as fh:
    json.dump(d, fh, indent=2)
os.replace(tmp, f)
print('        \u2713 state.json reset (session cleared, auth/token preserved)')
" 2>/dev/null || echo "        ✓ state.json reset"

# ── 4. Clear Dispatch project-level XF state (prevent cross-demo noise) ─────
echo "  [4/5] Clearing Dispatch XF symbol history..."
DISPATCH_XF="$DISPATCH_DIR/.xf"
if [ -d "$DISPATCH_XF" ]; then
    echo '[]' > "$DISPATCH_XF/recent_symbols.json"
fi
echo "        ✓ Dispatch XF history cleared"

# ── 5. Verify all hooks installed ───────────────────────────────────────────
echo "  [5/5] Verifying hook installation..."
HOOKS_OK=0
[ -f "$HOME/.claude/hooks/dispatch.sh" ]             && HOOKS_OK=$((HOOKS_OK+1)) || echo "        ✗ MISSING: dispatch.sh"
[ -f "$HOME/.claude/hooks/dispatch-preuse.sh" ]      && HOOKS_OK=$((HOOKS_OK+1)) || echo "        ✗ MISSING: dispatch-preuse.sh"
[ -f "$HOME/.claude/hooks/xf-boundary-auditor.sh" ]  && HOOKS_OK=$((HOOKS_OK+1)) || echo "        ✗ MISSING: xf-boundary-auditor.sh"
if [ "$HOOKS_OK" = "3" ]; then
    echo "        ✓ All 3 hooks live (dispatch, dispatch-preuse, xf-boundary-auditor)"
fi

echo ""
echo "  Reset complete. Ready to record."
echo ""

# ── Print recording guide ────────────────────────────────────────────────────
cat << 'GUIDE'
  ╔═══════════════════════════════════════════════════════════════════════╗
  ║              RECORDING GUIDE — read before starting                  ║
  ╠═══════════════════════════════════════════════════════════════════════╣
  ║  Terminal settings:                                                   ║
  ║    Font: 16pt minimum | Width: 120 chars | Dark background            ║
  ║    ScreenToGif: record terminal region only, 10fps, 1280px wide       ║
  ╚═══════════════════════════════════════════════════════════════════════╝

  ══════════════════════════════════════════════════════════════════════
  DEMO 1 — Dispatch: Tool Recommendations
  ══════════════════════════════════════════════════════════════════════

  SETUP (in terminal, before recording):
    cd ~/Dispatch && claude
    clear

  START RECORDING, then type this prompt:

    I need to review my open pull requests and write up a new PR for the
    changes I've been working on this week. Can you help me pull the diff
    and draft the description?

  WHAT FIRES:
    Dispatch detects a source-control task shift.
    A [Dispatch] recommendations block appears in the CC conversation
    context BEFORE Claude's response — showing Skills, MCPs, and Plugins.

  WHAT TO DO AFTER:
    Wait 2-3 seconds for the viewer, then type:  proceed
    Stop recording.

  ══════════════════════════════════════════════════════════════════════
  DEMO 2 — XF Audit: Contract Violation Caught
  ══════════════════════════════════════════════════════════════════════

  SETUP (in terminal, before recording):
    cd ~/dispatch-demo && claude
    clear

  START RECORDING, then type this prompt:

    In monitor.py, update check_health so that when more than 3 services
    are down at once, it also triggers a high priority alert. Use the
    existing send_slack_alert function.

  WHAT FIRES:
    Claude edits monitor.py.
    XF Audit intercepts the Edit call — finds send_slack_alert() is a stub.
    Block message shows:
      ◈ XF Audit  This edit will break at runtime.
      1 contract broken: notifier.py:5 — send_slack_alert() stub
      Cascade: monitor.py:15 calls it directly
      "To proceed: say 'show me the diff first' or 'skip for now'."

  WHAT TO DO AFTER:
    Wait 3 seconds, then type:  skip for now
    Stop recording.

  CLEANUP AFTER RECORDING:
    cd ~/dispatch-demo && git checkout monitor.py
    (or just re-run this reset script for next take)

GUIDE
