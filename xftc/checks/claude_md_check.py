import os
from typing import Optional, Tuple

CLAUDE_MD_LINE_LIMIT = 200


def count_claude_md_lines(cwd: str) -> Tuple[int, int]:
    """Returns (project_lines, global_lines)."""
    project_lines = 0
    global_lines = 0

    project_md = os.path.join(cwd, "CLAUDE.md")
    if os.path.exists(project_md):
        try:
            with open(project_md) as f:
                project_lines = sum(1 for _ in f)
        except Exception:
            pass

    global_md = os.path.expanduser("~/.claude/CLAUDE.md")
    if os.path.exists(global_md):
        try:
            with open(global_md) as f:
                global_lines = sum(1 for _ in f)
        except Exception:
            pass

    return (project_lines, global_lines)


def check_claude_md(cwd: str) -> Optional[Tuple[int, int]]:
    """
    Returns (project_lines, global_lines) if the total exceeds the limit.
    Returns None if within limits.
    """
    project_lines, global_lines = count_claude_md_lines(cwd)
    if project_lines + global_lines > CLAUDE_MD_LINE_LIMIT:
        return (project_lines, global_lines)
    return None
