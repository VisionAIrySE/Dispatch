from datetime import datetime, timezone, timedelta
from typing import Optional

# ET = UTC-5 (EST). Does not adjust for EDT — good enough for a nudge.
_ET_OFFSET = timedelta(hours=-5)
_PEAK_START = 8   # 8am ET
_PEAK_END = 14    # 2pm ET (exclusive)
_CACHE_TIMEOUT_SECONDS = 300  # 5 minutes


def _utcnow() -> datetime:
    """Indirection for test mocking."""
    return datetime.now(timezone.utc)


def is_peak_hours() -> bool:
    """True if current ET time is 8am–2pm on a weekday."""
    et_now = _utcnow() + _ET_OFFSET
    if et_now.weekday() >= 5:   # Saturday=5, Sunday=6
        return False
    return _PEAK_START <= et_now.hour < _PEAK_END


def check_cache_timeout(last_stop_time: Optional[str]) -> bool:
    """
    True if the gap since last session stop exceeds 5 minutes
    (meaning the CC prompt cache has expired).
    """
    if not last_stop_time:
        return False
    try:
        last_stop = datetime.fromisoformat(last_stop_time)
        if last_stop.tzinfo is None:
            last_stop = last_stop.replace(tzinfo=timezone.utc)
        gap = (_utcnow() - last_stop).total_seconds()
        return gap > _CACHE_TIMEOUT_SECONDS
    except Exception:
        return False
