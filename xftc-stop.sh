#!/bin/bash
# XFTC — Stop hook
# Records session end timestamp for cache timeout detection

trap 'exit 0' ERR

HOOK_INPUT=$(cat)
PYTHONPATH="${HOME}/.claude" python3 -m xftc.xftc stop <<< "$HOOK_INPUT" 2>/dev/null || exit 0
