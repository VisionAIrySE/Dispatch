import json
import re
import urllib.request
from datetime import date
from typing import Optional, Tuple

_GITHUB_REPO = "VisionAIrySE/Dispatch"
_RELEASES_URL = f"https://api.github.com/repos/{_GITHUB_REPO}/releases/latest"
_CHANGELOG_URL = f"https://raw.githubusercontent.com/{_GITHUB_REPO}/main/CHANGELOG.md"
_INSTALL_CMD = f"bash <(curl -s https://raw.githubusercontent.com/{_GITHUB_REPO}/main/install.sh) --update"
_TIMEOUT = 5  # seconds


def _today() -> date:
    """Indirection for test mocking."""
    return date.today()


def fetch_latest_version() -> Optional[str]:
    """Fetch latest release tag from GitHub. Returns None on any failure."""
    try:
        req = urllib.request.Request(
            _RELEASES_URL,
            headers={"User-Agent": "XFTC-version-check/1.0"},
        )
        with urllib.request.urlopen(req, timeout=_TIMEOUT) as resp:
            data = json.loads(resp.read())
        return data.get("tag_name", "").lstrip("v") or None
    except Exception:
        return None


def fetch_changelog_for_version(version: str) -> str:
    """Fetch CHANGELOG.md and extract bullet points for the given version."""
    try:
        req = urllib.request.Request(
            _CHANGELOG_URL,
            headers={"User-Agent": "XFTC-version-check/1.0"},
        )
        with urllib.request.urlopen(req, timeout=_TIMEOUT) as resp:
            content = resp.read().decode("utf-8")
        pattern = rf"## \[?v?{re.escape(version)}\]?.*?\n(.*?)(?=\n## |\Z)"
        match = re.search(pattern, content, re.DOTALL)
        if not match:
            return ""
        lines = match.group(1).strip().split("\n")
        bullets = [l for l in lines if l.strip().startswith(("-", "+", "*"))][:5]
        return "\n".join(f"  {b.strip()}" for b in bullets)
    except Exception:
        return ""


def check_version(
    installed_version: str,
    last_notified_version: str,
    last_check_date: str,
) -> Optional[Tuple[str, str]]:
    """
    Returns (latest_version, changelog_text) if a new version notification
    should fire. Returns None otherwise.

    Fires only on Mondays, once per new version.
    """
    today = _today()
    today_str = str(today)

    if today.weekday() != 0:  # 0 = Monday
        return None

    if last_check_date == today_str:
        return None

    latest = fetch_latest_version()
    if not latest:
        return None

    if latest == last_notified_version:
        return None

    changelog = fetch_changelog_for_version(latest)
    return (latest, changelog)
