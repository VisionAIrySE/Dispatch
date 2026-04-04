"""
XFTC — Xpansion Factor Token Control
Module 3 of Dispatch.
Entry point for all three hooks: submit, preuse, stop.
"""
import json
import os
import sys
from datetime import datetime, timezone, date

# Allow running as __main__ from hook scripts
_DIR = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.dirname(_DIR))

from xftc.state import (
    get_tier, get_session, update_session,
    get_project, update_project, get_dir_hash, load_state, save_state,
)
from xftc.colors import xftc_prefix

# Pending notices file — written by submit hook, read by Claude at response start
_PENDING_FILE = os.path.expanduser("~/.claude/dispatch/xftc_pending.json")
_pending: list = []


def _notify(line: str) -> None:
    """Queue a notice for user-visible surfacing AND print for Claude context."""
    print(line)
    _pending.append(line)


def _flush_pending() -> None:
    """Write all queued notices to pending file for Claude to surface in response."""
    if not _pending:
        return
    try:
        existing: list = []
        if os.path.exists(_PENDING_FILE):
            with open(_PENDING_FILE) as f:
                data = json.load(f)
                existing = data if isinstance(data, list) else []
        existing.extend(_pending)
        os.makedirs(os.path.dirname(_PENDING_FILE), exist_ok=True)
        with open(_PENDING_FILE, "w") as f:
            json.dump(existing, f)
    except Exception:
        pass


# ── Public API ──────────────────────────────────────────────────────────────

def run_submit_hook(data: dict) -> int:
    session_id = data.get("session_id", "unknown")
    cwd = data.get("cwd", os.getcwd())
    transcript_path = data.get("transcript_path")
    dir_hash = get_dir_hash(cwd)
    tier = get_tier()
    is_pro = (tier == "pro")

    session = get_session(session_id)
    project = get_project(dir_hash)
    message_count = session.get("message_count", 0) + 1

    update_session(session_id, {
        "message_count": message_count,
        "session_start": session.get(
            "session_start",
            datetime.now(timezone.utc).isoformat()
        ),
    })

    # Skills check — every session, all tiers
    if not session.get("skills_warned"):
        from xftc.checks.skills_check import check_skills
        skills_result = check_skills()
        if skills_result:
            count = skills_result["count"]
            total_kb = skills_result["total_kb"]
            top = ", ".join(f"{n} ({kb}KB)" for n, kb in skills_result["top_heavy"][:3])
            if is_pro:
                _notify(
                    f"{xftc_prefix()}  {count} skills installed ({total_kb}KB) — "
                    f"every SKILL.md reloads on every message"
                )
                _notify(
                    f"         Largest: {top}"
                )
                _notify(
                    "         Run /dispatch prune-skills to review and remove unused ones"
                )
            else:
                _notify(
                    f"{xftc_prefix()}  {count} skills installed ({total_kb}KB) — "
                    f"skills burn context on every message"
                )
                _notify(
                    "         Review with: ls ~/.claude/skills/ — "
                    "or upgrade for full token analysis: dispatch.visionairy.biz/pro"
                )
            update_session(session_id, {"skills_warned": True})

    # CLAUDE.md check — every session, all tiers (token hog, not Pro-exclusive)
    if not session.get("claude_md_warned"):
        from xftc.checks.claude_md_check import check_claude_md
        result = check_claude_md(cwd)
        if result:
            p_lines, g_lines = result
            total = p_lines + g_lines
            if is_pro:
                _notify(
                    f"{xftc_prefix()}  Your CLAUDE.md is {total} lines — "
                    f"every line reloads on every message"
                )
                _notify(
                    "         Run /dispatch-compact-md to move reference sections "
                    "to ~/.claude/ref/ files Claude reads on demand"
                )
            else:
                _notify(
                    f"{xftc_prefix()}  Your CLAUDE.md is {total} lines — "
                    f"every line burns context on every message"
                )
                _notify(
                    "         Run /dispatch-compact-md to compact it — "
                    "or upgrade for full token hog detection: dispatch.visionairy.biz/pro"
                )
            update_session(session_id, {"claude_md_warned": True})

    if is_pro:
        _run_pro_submit(session, session_id, project, dir_hash, cwd, message_count,
                        transcript_path)
    elif not session.get("ghost_fired"):
        _maybe_fire_submit_ghost(session_id, cwd, message_count)

    _flush_pending()
    return 0


def run_preuse_hook(data: dict) -> int:
    # Surface any pending XFTC notices — block this tool call once, clear, retry succeeds
    if os.path.exists(_PENDING_FILE):
        try:
            with open(_PENDING_FILE) as f:
                notices = json.load(f)
            if notices:
                with open(_PENDING_FILE, "w") as f:
                    json.dump([], f)
                print("\n".join(notices))
                return 1
        except Exception:
            pass

    tool_name = data.get("tool_name", "")
    tool_input = data.get("tool_input", {})
    session_id = data.get("session_id", "unknown")
    tier = get_tier()
    is_pro = (tier == "pro")

    if tool_name == "Agent":
        return _check_agent(tool_input, session_id, is_pro)
    if tool_name == "Bash":
        return _check_bash(tool_input, session_id, is_pro)
    return 0


def run_stop_hook(data: dict) -> int:
    session_id = data.get("session_id", "unknown")
    update_session(session_id, {
        "last_stop_time": datetime.now(timezone.utc).isoformat()
    })
    return 0


# ── Pro submit checks ───────────────────────────────────────────────────────

def _run_pro_submit(session, session_id, project, dir_hash, cwd, message_count,
                    transcript_path=None):
    from xftc.checks.mcp_check import check_mcp_overhead
    from xftc.checks.context_check import should_compact
    from xftc.checks.timing_check import is_peak_hours, check_cache_timeout
    from xftc.checks.version_check import check_version

    today = str(date.today())
    is_monday = date.today().weekday() == 0

    # MCP overhead — once per session
    if not session.get("mcp_warned"):
        result = check_mcp_overhead(cwd)
        if result:
            count, tokens = result
            _notify(
                f"{xftc_prefix()}  {count} MCP server{'s' if count != 1 else ''} "
                f"active (~{tokens:,} tokens/message overhead)"
            )
            _notify("         Disconnect unused servers with /mcp to reduce baseline cost")
            update_session(session_id, {"mcp_warned": True})

    # Peak hours — once per session
    if not session.get("peak_warned") and is_peak_hours():
        _notify(f"{xftc_prefix()}  Peak hours (8am\u20132pm ET weekdays) \u2014 session budgets drain faster")
        _notify("         Consider deferring large refactors or multi-agent runs to off-peak")
        update_session(session_id, {"peak_warned": True})

    # 60% compact reminder — once per session
    if not session.get("compact_warned"):
        fill = should_compact(message_count, cwd, transcript_path)
        if fill:
            pct = int(fill * 100)
            _notify(f"{xftc_prefix()}  Context estimated ~{pct}% full \u2014 autocompact triggers near 99%.")
            _notify("         Options: /compact (preserve context)  /clear (fresh start)  /warm-start (snapshot + clear)")
            update_session(session_id, {"compact_warned": True})

    # Cache timeout — weekly cap, needs substantial prior context
    last_stop = _get_prev_stop(session_id)
    if last_stop and is_monday and project.get("last_cache_reminder") != today:
        prior_msgs = session.get("message_count", 0)
        if prior_msgs > 10 and check_cache_timeout(last_stop):
            _notify(f"{xftc_prefix()}  Stepped away? Prompt cache expired \u2014 full context reprocessed from scratch")
            _notify("         Use /compact before breaks to preserve cache and reduce cost on return")
            update_project(dir_hash, {"last_cache_reminder": today})

    # Memory audit — once per project per day
    if project.get("memory_audit_last") != today:
        from xftc.checks.memory_audit_check import check_memory_audit
        result = check_memory_audit(cwd)
        if result:
            count = result["count"]
            bloated = result.get("bloated", False)
            line_count = result.get("line_count", 0)
            issues = []
            if count:
                noun = "link" if count == 1 else "links"
                issues.append(f"{count} broken {noun}")
            if bloated:
                issues.append(f"{line_count} lines — over 180-line limit")
            _notify(f"{xftc_prefix()}  MEMORY.md: {', '.join(issues)}")
            _notify("         Say '/warm-start' to audit and fix (creates .bak backup first)")
        update_project(dir_hash, {"memory_audit_last": today})

    # Version check — Mondays only
    if is_monday:
        state = load_state()
        installed = state.get("installed_version", "1.0.0")
        last_notified = state.get("last_notified_version", "1.0.0")
        last_check = state.get("last_version_check_date", "")
        result = check_version(installed, last_notified, last_check)
        if result:
            version, changelog = result
            _notify(f"{xftc_prefix()}  v{version} available \u2014 new in this release:")
            if changelog:
                _notify(changelog)
            _notify(
                "  Run: bash <(curl -s "
                "https://raw.githubusercontent.com/VisionAIrySE/Dispatch/main/install.sh"
                ") --update"
            )
            state["last_notified_version"] = version
            state["last_version_check_date"] = today
            save_state(state)


# ── Ghost notification ──────────────────────────────────────────────────────

def _maybe_fire_submit_ghost(session_id, cwd, message_count):
    from xftc.checks.mcp_check import check_mcp_overhead
    from xftc.checks.timing_check import is_peak_hours

    if check_mcp_overhead(cwd):
        _notify(f"{xftc_prefix()}  Pro would have flagged an MCP overhead issue here \u2014 dispatch.visionairy.biz/pro")
        update_session(session_id, {"ghost_fired": True})
    elif is_peak_hours():
        _notify(f"{xftc_prefix()}  Pro would have flagged peak hour usage here \u2014 dispatch.visionairy.biz/pro")
        update_session(session_id, {"ghost_fired": True})
    elif message_count >= 8:
        _notify(f"{xftc_prefix()}  Pro would have flagged context usage here \u2014 dispatch.visionairy.biz/pro")
        update_session(session_id, {"ghost_fired": True})


# ── PreToolUse handlers ─────────────────────────────────────────────────────

def _check_agent(tool_input, session_id, is_pro):
    from xftc.checks.model_check import check_subagent_model
    result = check_subagent_model(tool_input)
    if not result:
        return 0

    model, action = result

    if not is_pro:
        session = get_session(session_id)
        if not session.get("ghost_fired"):
            print(f"{xftc_prefix()}  Pro would have flagged sub-agent model usage here \u2014 dispatch.visionairy.biz/pro")
            update_session(session_id, {"ghost_fired": True})
        return 0

    if action == "block":
        print(f"{xftc_prefix()}  Sub-agent using {model} \u2014 Haiku recommended for this task type")
        print(f"         Approve to proceed with {model}, or cancel and switch model")
        print("         Say 'proceed' to continue")
        return 2

    if action == "warn":
        print(f"{xftc_prefix()}  Sub-agent using {model} on what looks like a lightweight task")
        print("         Consider claude-haiku-4-5-20251001 to reduce token cost")
        print("         Say 'proceed' to continue")
        return 2

    # nudge — unspecified model, informational only
    print(f"{xftc_prefix()}  Sub-agent model unspecified \u2014 set model: 'haiku' for lightweight tasks")
    return 0


def _check_bash(tool_input, session_id, is_pro):
    from xftc.checks.command_check import check_verbose_command
    command = tool_input.get("command", "")
    result = check_verbose_command(command)
    if not result:
        return 0

    _, issue, suggestion = result

    if not is_pro:
        session = get_session(session_id)
        if not session.get("ghost_fired"):
            print(f"{xftc_prefix()}  Pro would have flagged a verbose command here \u2014 dispatch.visionairy.biz/pro")
            update_session(session_id, {"ghost_fired": True})
        return 0

    print(f"{xftc_prefix()}  {issue}")
    print(f"         Suggested: {suggestion}")
    print("         Say 'proceed' to run original command anyway")
    return 2


# ── Helpers ─────────────────────────────────────────────────────────────────

def _get_prev_stop(current_session_id: str):
    """Return the most recent last_stop_time from any session other than current."""
    state = load_state()
    stops = [
        d.get("last_stop_time")
        for sid, d in state.get("sessions", {}).items()
        if sid != current_session_id and d.get("last_stop_time")
    ]
    return max(stops) if stops else None


# ── CLI entry point (called from hook scripts) ──────────────────────────────

if __name__ == "__main__":
    if len(sys.argv) < 2:
        sys.exit(0)

    hook_type = sys.argv[1]
    try:
        raw = sys.stdin.read()
        data = json.loads(raw) if raw.strip() else {}
    except Exception:
        data = {}

    try:
        if hook_type == "submit":
            sys.exit(run_submit_hook(data))
        elif hook_type == "preuse":
            sys.exit(run_preuse_hook(data))
        elif hook_type == "stop":
            sys.exit(run_stop_hook(data))
    except Exception:
        pass

    sys.exit(0)
