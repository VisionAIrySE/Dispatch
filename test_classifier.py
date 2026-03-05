import json
import unittest
from unittest.mock import patch, MagicMock
from classifier import classify_topic_shift, extract_recent_messages, should_skip


class TestExtractRecentMessages(unittest.TestCase):
    def test_extracts_last_3_human_messages(self):
        transcript = [
            {"role": "user", "content": "help me fix this bug"},
            {"role": "assistant", "content": "sure"},
            {"role": "user", "content": "now write a test"},
            {"role": "assistant", "content": "ok"},
            {"role": "user", "content": "deploy to Firebase"},
        ]
        result = extract_recent_messages(transcript, n=3)
        assert len(result) == 3
        assert result[-1] == "deploy to Firebase"

    def test_handles_fewer_than_n_messages(self):
        transcript = [{"role": "user", "content": "hello"}]
        result = extract_recent_messages(transcript, n=3)
        assert result == ["hello"]

    def test_handles_content_block_format(self):
        transcript = [
            {"role": "user", "content": [{"type": "text", "text": "build a Flutter widget"}]}
        ]
        result = extract_recent_messages(transcript, n=3)
        assert result == ["build a Flutter widget"]


class TestShouldSkip(unittest.TestCase):
    def test_skips_short_messages(self):
        assert should_skip("ok thanks") is True

    def test_does_not_skip_long_new_message(self):
        assert should_skip("I need to set up a new n8n workflow to process webhooks") is False

    def test_skips_very_short_message(self):
        assert should_skip("yes") is True


class TestClassifyTopicShift(unittest.TestCase):
    @patch('classifier.anthropic.Anthropic')
    def test_returns_structured_result_on_shift(self, mock_client_cls):
        mock_client = MagicMock()
        mock_client_cls.return_value = mock_client
        mock_client.messages.create.return_value = MagicMock(
            content=[MagicMock(text=json.dumps({
                "shift": True,
                "task_type": "flutter",
                "confidence": 0.92
            }))]
        )
        result = classify_topic_shift(
            messages=["fix supabase query", "now build a Flutter widget"],
            cwd="/home/visionairy/SNAP-app",
            last_task_type="supabase"
        )
        assert result["shift"] is True
        assert result["task_type"] == "flutter"
        assert result["confidence"] == 0.92

    @patch('classifier.anthropic.Anthropic')
    def test_returns_no_shift_on_continuation(self, mock_client_cls):
        mock_client = MagicMock()
        mock_client_cls.return_value = mock_client
        mock_client.messages.create.return_value = MagicMock(
            content=[MagicMock(text=json.dumps({
                "shift": False,
                "task_type": "flutter",
                "confidence": 0.95
            }))]
        )
        result = classify_topic_shift(
            messages=["add a new screen", "make the button blue"],
            cwd="/home/visionairy/SNAP-app",
            last_task_type="flutter"
        )
        assert result["shift"] is False

    @patch('classifier.anthropic.Anthropic')
    def test_handles_malformed_response_gracefully(self, mock_client_cls):
        mock_client = MagicMock()
        mock_client_cls.return_value = mock_client
        mock_client.messages.create.return_value = MagicMock(
            content=[MagicMock(text="not json")]
        )
        result = classify_topic_shift(
            messages=["something"],
            cwd="/home/visionairy",
            last_task_type=None
        )
        assert result["shift"] is False
        assert result["task_type"] == "general"
        assert result["confidence"] == 0.0


if __name__ == '__main__':
    unittest.main()
