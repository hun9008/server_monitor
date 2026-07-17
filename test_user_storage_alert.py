#!/usr/bin/env python3
import unittest
from pathlib import Path
from tempfile import TemporaryDirectory
from unittest.mock import patch

import user_storage_alert as alert


USERS = [
    {"name": "A", "email": "a@example.com", "username": "a"},
    {"name": "B", "email": "b@example.com", "username": None},
    {"name": "C", "email": "", "username": "c"},
    {"name": "D", "email": "d@example.com", "username": "d"},
]


class UserStorageAlertTests(unittest.TestCase):
    def test_only_complete_records_count_toward_n(self):
        self.assertEqual([u["username"] for u in alert.eligible_users(USERS)], ["a", "d"])
        self.assertEqual(100 / len(alert.eligible_users(USERS)), 50)

    def test_storage_percentage(self):
        fake_pw = type("Pw", (), {"pw_dir": "/home/a"})()
        with patch.object(alert.pwd, "getpwnam", return_value=fake_pw), patch.object(
            alert.subprocess, "check_output", side_effect=["250\t/home/a\n", "Size\n1000\n"]
        ):
            self.assertEqual(alert.storage_usage("a"), ("/home/a", 250, 1000, 25.0))

    def test_test_recipient_is_fixed(self):
        self.assertEqual(alert.TEST_RECIPIENT, "younghune135@unist.ac.kr")

    def test_nine_hour_cooldown(self):
        with TemporaryDirectory() as directory, patch.dict(
            alert.os.environ,
            {"USER_STORAGE_STATE_DIR": directory, "USER_STORAGE_COOLDOWN_HOURS": "9"},
        ):
            alert.mark_sent("a", now=1000)
            self.assertTrue(alert.in_cooldown("a", now=1000 + 9 * 3600 - 1))
            self.assertFalse(alert.in_cooldown("a", now=1000 + 9 * 3600))
            self.assertEqual(Path(directory, "a.last").read_text(encoding="ascii"), "1000")


if __name__ == "__main__":
    unittest.main()
