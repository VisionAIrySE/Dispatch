import re
from typing import Optional, Tuple

# Each entry: (pattern, issue_description, suggested_alternative)
VERBOSE_PATTERNS = [
    (
        r"\bgit\s+log\b(?!.*--oneline)",
        "git log without --oneline floods context with full commit bodies",
        "git log --oneline -20",
    ),
    (
        r"\bfind\s+[./](?!.*-maxdepth)",
        "find without -maxdepth can return unbounded recursive output",
        "find . -maxdepth 2 ...",
    ),
    (
        r"\bcat\s+\S",
        "cat loads the entire file into context — use the Read tool with offset/limit",
        "Read tool with offset/limit parameters",
    ),
    (
        r"\bnpm\s+install\b(?!.*--silent)(?!.*\s-s\b)",
        "npm install floods context with package install noise",
        "npm install --silent",
    ),
    (
        r"\bls\s+-l",
        "ls -l on large directories produces verbose listing",
        "ls or ls -1",
    ),
    (
        r"\bpip\s+install\b(?!.*-q\b)(?!.*--quiet)",
        "pip install floods context with package output",
        "pip install -q ...",
    ),
]


def check_verbose_command(command: str) -> Optional[Tuple[str, str, str]]:
    """
    Returns (pattern, issue, suggestion) if the command will flood context.
    Returns None if the command is clean.
    """
    for pattern, issue, suggestion in VERBOSE_PATTERNS:
        if re.search(pattern, command, re.IGNORECASE):
            return (pattern, issue, suggestion)
    return None
