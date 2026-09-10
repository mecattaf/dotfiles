from __future__ import annotations

import datetime as dt
import json
import os
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[2]
SCRIPT = Path(
    os.environ.get(
        "CLAUDE_SESSIONS_SCRIPT",
        REPO_ROOT / "home/dot_local/bin/claude-sessions",
    )
)


class ClaudeSessionsTests(unittest.TestCase):
    def setUp(self) -> None:
        self.tmp = tempfile.TemporaryDirectory()
        self.home = Path(self.tmp.name)

    def tearDown(self) -> None:
        self.tmp.cleanup()

    def write_session(
        self, seat_root: str, session_id: str, modified: str, slug: str
    ) -> Path:
        path = self.home / seat_root / "project" / f"{session_id}.jsonl"
        path.parent.mkdir(parents=True, exist_ok=True)
        records = [
            {"bad": "metadata-free"},
            {
                "type": "user",
                "sessionId": session_id,
                "cwd": f"/work/{slug}",
                "slug": slug,
                "message": {"role": "user", "content": f"continue {slug}"},
            },
        ]
        path.write_text("not-json\n" + "\n".join(map(json.dumps, records)) + "\n")
        stamp = dt.datetime.fromisoformat(modified).timestamp()
        os.utime(path, (stamp, stamp))
        return path

    def run_script(self, *args: str):
        env = os.environ.copy()
        env["CLAUDE_SESSIONS_HOME"] = str(self.home)
        result = subprocess.run(
            [sys.executable, str(SCRIPT), *args],
            text=True,
            capture_output=True,
            env=env,
            check=True,
        )
        return json.loads(result.stdout) if "--json" in args else result.stdout

    def test_fans_out_over_all_three_seats_and_sorts_newest_first(self) -> None:
        self.write_session(".claude/projects", "one", "2026-09-08T16:49:41+02:00", "alpha")
        self.write_session(".claude-work/projects", "two", "2026-09-08T16:49:43+02:00", "beta")
        self.write_session(".claude-3/projects", "three", "2026-09-08T16:49:42+02:00", "gamma")

        rows = self.run_script("--json", "--limit", "0")

        self.assertEqual([row["seat"] for row in rows], ["cc2", "cc3", "cc"])
        self.assertEqual([row["session_id"] for row in rows], ["two", "three", "one"])
        self.assertEqual(rows[0]["last_prompt"], "continue beta")

    def test_around_filters_by_transcript_mtime(self) -> None:
        self.write_session(".claude/projects", "inside", "2026-09-08T16:49:43+02:00", "inside")
        self.write_session(".claude-work/projects", "outside", "2026-09-08T16:50:30+02:00", "outside")

        rows = self.run_script(
            "--around",
            "2026-09-08 16:49:43+02:00",
            "--window-seconds",
            "5",
            "--json",
            "--limit",
            "0",
        )

        self.assertEqual([row["session_id"] for row in rows], ["inside"])

    def test_text_output_can_include_last_prompt(self) -> None:
        self.write_session(".claude-3/projects", "three", "2026-09-08T16:49:42+02:00", "gamma")

        output = self.run_script("--show-prompt")

        self.assertIn("SEAT", output)
        self.assertIn("cc3", output)
        self.assertIn("continue gamma", output)


if __name__ == "__main__":
    unittest.main()
