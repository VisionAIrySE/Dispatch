from datetime import datetime, timezone, timedelta
from unittest.mock import patch
import pytest


class TestTimingCheck:
    def test_weekday_peak_hour_returns_true(self):
        from xftc.checks.timing_check import is_peak_hours
        # Monday 10am ET = Monday 15:00 UTC (EST)
        mock_time = datetime(2026, 4, 6, 15, 0, 0, tzinfo=timezone.utc)  # Monday
        with patch("xftc.checks.timing_check._utcnow", return_value=mock_time):
            assert is_peak_hours() is True

    def test_weekday_off_peak_returns_false(self):
        from xftc.checks.timing_check import is_peak_hours
        # Monday 6pm ET = Monday 23:00 UTC (EST)
        mock_time = datetime(2026, 4, 6, 23, 0, 0, tzinfo=timezone.utc)  # Monday
        with patch("xftc.checks.timing_check._utcnow", return_value=mock_time):
            assert is_peak_hours() is False

    def test_weekend_peak_hour_returns_false(self):
        from xftc.checks.timing_check import is_peak_hours
        # Saturday 10am ET
        mock_time = datetime(2026, 4, 4, 15, 0, 0, tzinfo=timezone.utc)  # Saturday
        with patch("xftc.checks.timing_check._utcnow", return_value=mock_time):
            assert is_peak_hours() is False

    def test_cache_timeout_recent_stop_returns_false(self):
        from xftc.checks.timing_check import check_cache_timeout
        recent = (datetime.now(timezone.utc) - timedelta(minutes=2)).isoformat()
        assert check_cache_timeout(recent) is False

    def test_cache_timeout_old_stop_returns_true(self):
        from xftc.checks.timing_check import check_cache_timeout
        old = (datetime.now(timezone.utc) - timedelta(minutes=10)).isoformat()
        assert check_cache_timeout(old) is True

    def test_cache_timeout_none_returns_false(self):
        from xftc.checks.timing_check import check_cache_timeout
        assert check_cache_timeout(None) is False

    def test_cache_timeout_malformed_returns_false(self):
        from xftc.checks.timing_check import check_cache_timeout
        assert check_cache_timeout("not-a-date") is False

    def test_peak_hour_boundary_8am_is_peak(self):
        from xftc.checks.timing_check import is_peak_hours
        # Monday 8am ET = Monday 13:00 UTC (EST)
        mock_time = datetime(2026, 4, 6, 13, 0, 0, tzinfo=timezone.utc)
        with patch("xftc.checks.timing_check._utcnow", return_value=mock_time):
            assert is_peak_hours() is True

    def test_peak_hour_boundary_2pm_is_off_peak(self):
        from xftc.checks.timing_check import is_peak_hours
        # Monday 2pm ET = Monday 19:00 UTC (EST)
        mock_time = datetime(2026, 4, 6, 19, 0, 0, tzinfo=timezone.utc)
        with patch("xftc.checks.timing_check._utcnow", return_value=mock_time):
            assert is_peak_hours() is False
