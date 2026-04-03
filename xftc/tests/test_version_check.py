from datetime import date
from unittest.mock import patch, MagicMock
import pytest


class TestVersionCheck:
    def test_check_skips_on_non_monday(self):
        from xftc.checks.version_check import check_version
        # 2026-04-03 is a Friday
        with patch("xftc.checks.version_check._today", return_value=date(2026, 4, 3)):
            result = check_version("1.0.0", "1.0.0", "")
            assert result is None

    def test_check_skips_if_already_checked_today(self):
        from xftc.checks.version_check import check_version
        today = date(2026, 4, 6)  # Monday
        with patch("xftc.checks.version_check._today", return_value=today):
            result = check_version("1.0.0", "1.0.0", "2026-04-06")
            assert result is None

    def test_check_skips_if_already_notified(self):
        from xftc.checks.version_check import check_version
        today = date(2026, 4, 6)  # Monday
        with patch("xftc.checks.version_check._today", return_value=today):
            with patch("xftc.checks.version_check.fetch_latest_version", return_value="1.1.0"):
                # Already notified about 1.1.0
                result = check_version("1.0.0", "1.1.0", "2026-03-30")
                assert result is None

    def test_check_returns_version_on_monday_with_new_version(self):
        from xftc.checks.version_check import check_version
        today = date(2026, 4, 6)  # Monday
        with patch("xftc.checks.version_check._today", return_value=today):
            with patch("xftc.checks.version_check.fetch_latest_version", return_value="1.2.0"):
                with patch("xftc.checks.version_check.fetch_changelog_for_version", return_value="+ new feature"):
                    result = check_version("1.0.0", "1.0.0", "2026-03-30")
                    assert result is not None
                    version, changelog = result
                    assert version == "1.2.0"
                    assert "new feature" in changelog

    def test_fetch_latest_version_returns_none_on_network_error(self):
        from xftc.checks.version_check import fetch_latest_version
        with patch("urllib.request.urlopen", side_effect=Exception("network error")):
            result = fetch_latest_version()
            assert result is None

    def test_fetch_changelog_returns_empty_on_error(self):
        from xftc.checks.version_check import fetch_changelog_for_version
        with patch("urllib.request.urlopen", side_effect=Exception("network error")):
            result = fetch_changelog_for_version("1.2.0")
            assert result == ""
