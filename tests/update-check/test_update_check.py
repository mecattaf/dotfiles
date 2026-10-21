from __future__ import annotations

import argparse
import contextlib
import datetime as dt
import io
from unittest.mock import patch, Mock
import importlib.machinery
import importlib.util
import json
import os
import re
import subprocess
import sys
import tempfile
import time
import unittest
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[2]
SCRIPT = Path(os.environ.get("UPDATE_CHECK_SCRIPT", REPO_ROOT / "home/dot_local/bin/update-check"))
WATCH = Path(os.environ.get("UPDATE_WATCH", REPO_ROOT / "lib/update-watch.json"))
FLAKE_LOCK = Path(os.environ.get("UPDATE_FLAKE_LOCK", REPO_ROOT / "flake.lock"))


def load_module():
    loader = importlib.machinery.SourceFileLoader("update_check", str(SCRIPT))
    spec = importlib.util.spec_from_loader("update_check", loader)
    module = importlib.util.module_from_spec(spec)
    loader.exec_module(module)
    return module


uc = load_module()


# Fake nix: `flake update` moves the lock (to the head in fake.json for a
# branch input, to the commit flake.nix now pins for a pinned one), `eval`
# answers the versions fake.json records for the revs locked in the evaluated
# tree, and fmt/flake check/build fail on a branch named in fake.json "fail".
FAKE_NIX = r'''
import json, os, re, subprocess, sys, time
from pathlib import Path
time.sleep(float(os.environ.get("FAKE_NIX_DELAY", "0")))
state_path = Path(os.environ["FAKE_STATE"])
state = json.loads(state_path.read_text())
args = sys.argv[1:]
state["calls"].append(["nix"] + args)
state_path.write_text(json.dumps(state))
if args[:2] == ["flake", "update"]:
    name = args[2]
    lock = json.loads(Path("flake.lock").read_text())
    node = lock["nodes"][lock["nodes"]["root"]["inputs"][name]]
    o = node["original"]
    if "rev" in o:
        m = re.search(r'github:%s/%s/(\w+)' % (o["owner"], o["repo"]), Path("flake.nix").read_text())
        o["rev"] = m.group(1)
        node["locked"]["rev"] = m.group(1)
    else:
        node["locked"]["rev"] = state["heads"]["%s/%s" % (o["owner"], o["repo"])]
    node["locked"]["lastModified"] += 1
    Path("flake.lock").write_text(json.dumps(lock, indent=2) + "\n")
    sys.exit(0)
if args[0] == "eval":
    tree = re.search(r'git\+file://([^"]+)', args[-1]).group(1).split("?")[0]
    lock = json.loads((Path(tree) / "flake.lock").read_text())
    merged = {}
    for key in lock["nodes"]["root"]["inputs"].values():
        merged.update(state["versions"].get(lock["nodes"][key]["locked"]["rev"], {}))
    paths = json.loads(os.environ["UPDATE_CHECK_PATHS"])
    print(json.dumps({k: merged.get(k) for k in paths}))
    sys.exit(0)
branch = subprocess.run(["git", "rev-parse", "--abbrev-ref", "HEAD"], capture_output=True, text=True).stdout.strip()
if any(f in branch or f.replace("update/", "update-check-") in str(Path.cwd()) for f in state["fail"]):
    print("error: builder for %s failed" % state["fail"][0])
    sys.exit(1)
print("ok")
'''

# Fake gh: GitHub reads from fake.json, PRs kept in fake.json.
FAKE_GH = r'''
import json, os, subprocess, sys
from pathlib import Path
state_path = Path(os.environ["FAKE_STATE"])
state = json.loads(state_path.read_text())
args = sys.argv[1:]
state["calls"].append(["gh"] + args)
def flag(name):
    return args[args.index(name) + 1] if name in args else None
def done(out=None):
    state_path.write_text(json.dumps(state))
    if out is not None:
        print(out if isinstance(out, str) else json.dumps(out))
    sys.exit(0)
if args[0] == "api":
    for i, needle in enumerate(state.get("api_fail", [])):
        if needle in args[1]:
            if state.get("api_fail_once"):
                state["api_fail"].pop(i)
            state_path.write_text(json.dumps(state))
            print("gh: HTTP 504", file=sys.stderr)
            sys.exit(1)
    path = args[1].split("?")[0].split("/")
    repo = "/".join(path[1:3])
    if len(path) == 3:
        done({"default_branch": "main"})
    if path[3] == "commits":
        ref = "/".join(path[4:])
        for t in state["tags"].get(repo, []):
            if t["name"] == ref:
                done({"sha": t["commit"]["sha"], "commit": {"committer": {"date": "2026-10-13T00:00:00Z"}}})
        done({"sha": state["heads"][repo], "commit": {"committer": {"date": "2026-10-14T00:00:00Z"}}})
    if path[3] == "releases":
        done(state["releases"].get(repo, []))
    if path[3] == "tags":
        done(state["tags"].get(repo, []))
if args[:2] == ["pr", "list"]:
    head = flag("--head")
    done([p for p in state["prs"] if p["state"] == "open" and p["head"] == head])
if args[:2] == ["pr", "create"]:
    n = len(state["prs"]) + 1
    url = "https://github.com/%s/pull/%d" % (flag("-R"), n)
    state["prs"].append({"number": n, "url": url, "head": flag("--head"), "title": flag("--title"),
                         "body": Path(flag("--body-file")).read_text(), "isDraft": "--draft" in args,
                         "state": "open", "mergeable": "MERGEABLE", "headRefOid": ""})
    done(url)
pr = next(p for p in state["prs"] if p["number"] == int(args[2]))
if args[1] == "edit":
    pr["title"] = flag("--title")
    pr["body"] = Path(flag("--body-file")).read_text()
elif args[1] == "ready":
    pr["isDraft"] = "--undo" in args
elif args[1] == "close":
    pr["state"] = "closed"
    subprocess.run(["git", "--git-dir", os.environ["FAKE_ORIGIN"], "branch", "-D", pr["head"]], check=True,
                   capture_output=True)
done()
'''

FLAKE_NIX = """{
  inputs = {
    llm-agents.url = "github:numtide/llm-agents.nix";
    herdr = {
      url = "github:herdrdev/herdr/%s"; # v0.9.3, wire 22
    };
  };
  outputs = _: { };
}
"""

H0, H1 = "a" * 40, "b" * 40
A0, A1, A2 = "1" * 40, "2" * 40, "3" * 40


def lock_json(llm_rev: str, herdr_rev: str) -> str:
    return json.dumps({
        "nodes": {
            "root": {"inputs": {"llm-agents": "llm-agents", "herdr": "herdr"}},
            "llm-agents": {
                "locked": {"type": "github", "owner": "numtide", "repo": "llm-agents.nix",
                           "rev": llm_rev, "lastModified": 1000},
                "original": {"type": "github", "owner": "numtide", "repo": "llm-agents.nix"},
            },
            "herdr": {
                "locked": {"type": "github", "owner": "herdrdev", "repo": "herdr",
                           "rev": herdr_rev, "lastModified": 1000},
                "original": {"type": "github", "owner": "herdrdev", "repo": "herdr", "rev": herdr_rev},
            },
        },
        "root": "root",
        "version": 7,
    }, indent=2) + "\n"


WATCH_FIXTURE = {
    "inputs": [
        {"name": "llm-agents", "follow": "branch", "hosts": ["strix"],
         "versions": {"claude-code": "x.claude-code"},
         "notes": {"claude-code": {"repo": "anthropics/claude-code", "tagPrefix": "v"}},
         "switch": "Nothing restarts."},
        {"name": "herdr", "follow": "release", "hosts": ["strix"],
         "versions": {"herdr": "x.herdr"},
         "notes": {"herdr": {"repo": "herdrdev/herdr", "tagPrefix": "v"}},
         "switch": "keep-old."},
    ]
}


def release(tag: str, published: str, body: str, prerelease: bool = False) -> dict:
    return {"tag_name": tag, "published_at": published, "body": body,
            "prerelease": prerelease, "draft": False}


class PureHelpers(unittest.TestCase):
    def test_parse_version(self) -> None:
        self.assertEqual(uc.parse_version("2.1.296"), (2, 1, 296))
        self.assertEqual(uc.parse_version("rust-v0.162.1", "rust-v"), (0, 162, 1))
        self.assertIsNone(uc.parse_version("rust-v0.163.0-alpha.10", "rust-v"))
        self.assertIsNone(uc.parse_version("0-unstable-ae26ca4"))
        self.assertIsNone(uc.parse_version("0.9.4", "v"))
        self.assertIsNone(uc.parse_version(None))

    def test_select_releases_by_version(self) -> None:
        rels = [
            release("v2.1.296", "2026-10-13", "c"),
            release("v2.1.290", "2026-10-08", "b"),
            release("v2.1.287", "2026-10-02", "a"),
            release("v2.1.297-rc1", "2026-10-14", "rc"),
            release("v2.1.299", "2026-10-15", "pre", prerelease=True),
        ]
        picked = uc.select_releases(rels, "v", (2, 1, 287), (2, 1, 296))
        self.assertEqual([r["tag_name"] for r in picked], ["v2.1.290", "v2.1.296"])

    def test_select_releases_by_date_for_a_snapshot_pin(self) -> None:
        rels = [
            release("v0.15.0", "2026-10-13T21:53:32Z", "new"),
            release("v0.14.0", "2026-10-13T12:45:53Z", "older than the pin"),
        ]
        picked = uc.select_releases(rels, "v", None, (0, 15, 0), "2026-10-13T16:44:35Z",
                                    "2026-10-13T21:53:32Z")
        self.assertEqual([r["tag_name"] for r in picked], ["v0.15.0"])

    def test_rewrite_pin_moves_the_commit_and_the_release_on_its_line(self) -> None:
        text = FLAKE_NIX % H0
        out = uc.rewrite_pin(text, f"github:herdrdev/herdr/{H0}", f"github:herdrdev/herdr/{H1}",
                             "v0.9.3", "v0.9.4")
        self.assertIn(f'"github:herdrdev/herdr/{H1}"; # v0.9.4, wire 22', out)
        self.assertEqual(out.count(H0), 0)

    def test_rewrite_pin_moves_a_tag(self) -> None:
        text = 'vicinae.url = "github:vicinaehq/vicinae/v0.29.1";\n'
        out = uc.rewrite_pin(text, "github:vicinaehq/vicinae/v0.29.1",
                             "github:vicinaehq/vicinae/v0.30.0", "v0.29.1", "v0.30.0")
        self.assertEqual(out, 'vicinae.url = "github:vicinaehq/vicinae/v0.30.0";\n')

    def test_rewrite_pin_refuses_an_ambiguous_pin(self) -> None:
        text = '"github:o/r/x"\n"github:o/r/x"\n'
        with self.assertRaises(uc.CheckError):
            uc.rewrite_pin(text, "github:o/r/x", "github:o/r/y")

    def test_a_snapshot_version_is_titled_by_its_release(self) -> None:
        self.assertEqual(uc.pr_title("gufo", {"gufo": ("0-unstable-ae26ca4", "0-unstable-89d6185")},
                                     "v0.15.0"), "update: gufo (gufo v0.15.0)")
        self.assertEqual(uc.pr_title("herdr", {"herdr": ("0.9.3", "0.9.4")}, "v0.9.4"),
                         "update: herdr (herdr 0.9.4)")

    def test_body_marker_round_trips_and_the_body_fits(self) -> None:
        report = {
            "input": "llm-agents", "to_rev": A1, "from_rev": A0, "base": "f" * 40,
            "from_date": 1000, "to_date": "2026-10-14T00:00:00Z", "tag": None,
            "run": "2026-10-14T02:00:00Z",
            "changed": {"claude-code": ("2.1.287", "2.1.296")},
            "gate": {"ok": True, "steps": [{"step": "flake check", "ok": True, "seconds": 3}]},
        }
        notes = [{"package": "claude-code", "repo": "anthropics/claude-code", "from": "2.1.287",
                  "to": "2.1.296",
                  "releases": [release(f"v2.1.{n}", "2026-10-13", "x" * 5000) for n in range(288, 297)]}]
        body = uc.build_body(report, {"switch": "Nothing restarts."}, notes, limit=20000)
        self.assertLessEqual(len(body), 20000)
        self.assertIn("(cut for length; full notes: "
                      "https://github.com/anthropics/claude-code/releases/tag/v2.1.296)", body)
        self.assertIn("| claude-code | 2.1.287 | 2.1.296 |", body)
        self.assertLess(body.index("### v2.1.296"), body.index("### v2.1.288"))  # newest first
        marker = uc.read_marker(body)
        self.assertEqual(marker["to_rev"], A1)
        self.assertEqual(marker["versions"], {"claude-code": ["2.1.287", "2.1.296"]})
        self.assertNotIn(chr(0x2014), body)  # no em-dash in what Tom reads

    def test_every_program_gets_a_share_of_the_notes(self) -> None:
        report = {
            "input": "llm-agents", "to_rev": A1, "from_rev": A0, "base": "f" * 40,
            "from_date": 1000, "to_date": "2026-10-14T00:00:00Z", "tag": None,
            "run": "2026-10-14T02:00:00Z",
            "changed": {"claude-code": ("1", "2"), "codex": ("1", "2"), "pi": ("1", "2")},
            "gate": {"ok": True, "steps": []},
        }
        notes = [
            {"package": "claude-code", "repo": "a/cc", "from": "1", "to": "2",
             "releases": [release(f"v2.{n}", "2026-10-13", "c" * 4000) for n in range(20)]},
            {"package": "codex", "repo": "a/codex", "from": "1", "to": "2",
             "releases": [release(f"v3.{n}", "2026-10-13", "x" * 4000) for n in range(5)]},
            {"package": "pi", "repo": "a/pi", "from": "1", "to": "2",
             "releases": [release("v1.1", "2026-10-13", "## What's changed\n\npi notes")]},
        ]
        body = uc.build_body(report, {"switch": "-"}, notes, limit=30000)
        self.assertLessEqual(len(body), 30000)
        self.assertIn("pi notes", body)
        self.assertNotIn("What's changed", body)
        for tag in ["v2.%d" % n for n in range(20)] + ["v3.%d" % n for n in range(5)]:
            self.assertIn(f"### {tag} ", body)  # every release keeps its heading
        self.assertIn("x" * 1500, body)  # and a real share of its notes


class WatchFile(unittest.TestCase):
    """lib/update-watch.json agrees with the flake.lock it is read beside."""

    def test_every_entry_is_a_bumpable_root_input(self) -> None:
        watch = json.loads(WATCH.read_text())
        lock = json.loads(FLAKE_LOCK.read_text())
        names = [e["name"] for e in watch["inputs"]]
        self.assertEqual(len(names), len(set(names)))
        for e in watch["inputs"]:
            with self.subTest(e["name"]):
                node = uc.lock_node(lock, e["name"])
                self.assertIn(e["follow"], ("branch", "release"))
                if e["follow"] == "release":
                    self.assertTrue(node["original"].get("rev") or node["original"].get("ref"))
                else:
                    self.assertNotIn("rev", node["original"])
                self.assertTrue(e["hosts"])
                self.assertTrue(set(e["hosts"]) <= set(uc.HOSTS))
                self.assertTrue(e["versions"])
                self.assertTrue(set(e.get("notes", {})) <= set(e["versions"]))
                for src in e.get("notes", {}).values():
                    self.assertRegex(src["repo"], r"^[\w.-]+/[\w.-]+$")
                self.assertTrue(e.get("switch"))
                for out in e.get("build", []):
                    self.assertRegex(out, r"^\.#[\w.-]+$")


class Run(unittest.TestCase):
    def setUp(self) -> None:
        self.tmp = tempfile.TemporaryDirectory()
        t = Path(self.tmp.name)
        self.t = t
        self.env = {
            **os.environ,
            "HOME": str(t / "home"),
            "GIT_AUTHOR_NAME": "test", "GIT_AUTHOR_EMAIL": "test@example.invalid",
            "GIT_COMMITTER_NAME": "test", "GIT_COMMITTER_EMAIL": "test@example.invalid",
            "GIT_CONFIG_NOSYSTEM": "1",
        }
        (t / "home").mkdir()
        self.origin = t / "origin.git"
        self.git("init", "-q", "--bare", "-b", "main", str(self.origin))
        seed = t / "seed"
        self.git("init", "-q", "-b", "main", str(seed))
        (seed / "lib").mkdir()
        (seed / "lib/update-watch.json").write_text(json.dumps(WATCH_FIXTURE, indent=2))
        (seed / "flake.nix").write_text(FLAKE_NIX % H0)
        (seed / "flake.lock").write_text(lock_json(A0, H0))
        self.git("-C", str(seed), "add", "-A")
        self.git("-C", str(seed), "commit", "-q", "-m", "seed")
        self.git("-C", str(seed), "push", "-q", str(self.origin), "main")
        self.seed = seed
        self.repo = t / "repo"
        self.git("clone", "-q", str(self.origin), str(self.repo))

        bin_ = t / "bin"
        bin_.mkdir()
        for name, src in (("nix", FAKE_NIX), ("gh", FAKE_GH)):
            p = bin_ / name
            p.write_text(f"#!{sys.executable}\n{src}")
            p.chmod(0o755)
        self.state_path = t / "fake.json"
        self.write_state({
            "heads": {"numtide/llm-agents.nix": A1},
            "tags": {"herdrdev/herdr": [{"name": "v0.9.3", "commit": {"sha": H0}},
                                        {"name": "v0.9.4", "commit": {"sha": H1}}]},
            "releases": {
                "herdrdev/herdr": [
                    release("v0.9.4", "2026-10-13T15:41:22Z", "herdr 0.9.4 notes"),
                    release("preview-2026-10-12", "2026-10-12T13:48:36Z", "preview notes", True),
                    release("v0.9.3", "2026-09-29T19:29:23Z", "herdr 0.9.3 notes"),
                ],
                "anthropics/claude-code": [
                    release("v2.1.296", "2026-10-13T00:00:00Z", "cc 296 notes"),
                    release("v2.1.287", "2026-10-02T00:00:00Z", "cc 287 notes"),
                ],
            },
            "versions": {
                A0: {"claude-code": "2.1.287"}, A1: {"claude-code": "2.1.296"},
                A2: {"claude-code": "2.1.297"},
                H0: {"herdr": "0.9.3"}, H1: {"herdr": "0.9.4"},
            },
            "fail": [], "prs": [], "calls": [],
        })
        self.env.update({
            "PATH": f"{bin_}:{os.environ['PATH']}",
            "FAKE_STATE": str(self.state_path),
            "FAKE_ORIGIN": str(self.origin),
            "UPDATE_CHECK_REPO": str(self.repo),
            "UPDATE_CHECK_WORKTREES": str(t / "wt"),
            "UPDATE_CHECK_STATE": str(t / "state"),
            "UPDATE_CHECK_GH_REPO": "mecattaf/dotfiles",
            "UPDATE_CHECK_RETRY_SECONDS": "0",
        })

    def tearDown(self) -> None:
        self.tmp.cleanup()

    def git(self, *args: str) -> str:
        return subprocess.run(["git", *args], env=self.env, check=True, capture_output=True,
                              text=True).stdout.strip()

    def state(self) -> dict:
        return json.loads(self.state_path.read_text())

    def write_state(self, state: dict) -> None:
        self.state_path.write_text(json.dumps(state))

    def edit_state(self, **changes) -> None:
        s = self.state()
        s.update(changes)
        self.write_state(s)

    def run_check(self, *args: str, expected_exit: int = 0) -> dict:
        p = subprocess.run([sys.executable, str(SCRIPT), "--json", *args], env=self.env,
                           capture_output=True, text=True)
        self.assertEqual(p.returncode, expected_exit, p.stderr + p.stdout)
        return {r["input"]: r for r in json.loads(p.stdout)["inputs"]}

    def origin_file(self, branch: str, path: str) -> str:
        return self.git("--git-dir", str(self.origin), "show", f"{branch}:{path}")

    def origin_branches(self) -> list[str]:
        out = self.git("--git-dir", str(self.origin), "for-each-ref", "--format=%(refname:short)",
                       "refs/heads")
        return sorted(out.split())

    def assert_tidy(self) -> None:
        self.assertEqual(len(self.git("-C", str(self.repo), "worktree", "list").splitlines()), 1)
        self.assertEqual(self.git("-C", str(self.repo), "branch", "--list", "update/*"), "")
        self.assertEqual(self.git("-C", str(self.repo), "status", "--porcelain"), "")

    def test_first_run_opens_one_pr_per_moved_input(self) -> None:
        r = self.run_check()
        self.assertEqual(r["llm-agents"]["status"], "opened")
        self.assertEqual(r["herdr"]["status"], "opened")
        self.assertEqual(self.origin_branches(), ["main", "update/herdr", "update/llm-agents"])

        lock = json.loads(self.origin_file("update/llm-agents", "flake.lock"))
        self.assertEqual(lock["nodes"]["llm-agents"]["locked"]["rev"], A1)
        msg = self.git("--git-dir", str(self.origin), "log", "-1", "--format=%B", "update/llm-agents")
        self.assertIn("claude-code 2.1.287 -> 2.1.296", msg)
        self.assertIn(uc.TRAILER, msg)

        flake = self.origin_file("update/herdr", "flake.nix")
        self.assertIn(f'"github:herdrdev/herdr/{H1}"; # v0.9.4, wire 22', flake)

        prs = {p["head"]: p for p in self.state()["prs"]}
        self.assertFalse(prs["update/llm-agents"]["isDraft"])
        self.assertIn("cc 296 notes", prs["update/llm-agents"]["body"])
        self.assertNotIn("cc 287 notes", prs["update/llm-agents"]["body"])
        self.assertIn("herdr 0.9.4 notes", prs["update/herdr"]["body"])
        self.assertNotIn("preview notes", prs["update/herdr"]["body"])
        self.assertEqual(prs["update/herdr"]["title"], "update: herdr (herdr 0.9.4)")
        self.assert_tidy()

        calls = [c for c in self.state()["calls"] if c[0] == "nix" and c[1] == "fmt"]
        self.assertEqual(len(calls), 1)  # only the pin rewrite touches flake.nix

    def test_a_failed_gate_opens_a_draft_with_the_log_tail(self) -> None:
        self.edit_state(fail=["update/herdr"])
        r = self.run_check(expected_exit=1)
        self.assertFalse(r["herdr"]["gate"]["ok"])
        prs = {p["head"]: p for p in self.state()["prs"]}
        self.assertTrue(prs["update/herdr"]["isDraft"])
        self.assertIn("builder for update/herdr failed", prs["update/herdr"]["body"])
        self.assertFalse(prs["update/llm-agents"]["isDraft"])

        # An unchanged failed draft stays visibly failed on later checks.
        r = self.run_check("--only", "herdr", expected_exit=1)
        self.assertFalse(r["herdr"]["gate"]["ok"])
        self.edit_state(fail=[])
        r = self.run_check("--force", "--only", "herdr")
        self.assertEqual(r["herdr"]["status"], "refreshed")
        self.assertFalse({p["head"]: p for p in self.state()["prs"]}["update/herdr"]["isDraft"])

    def test_a_second_night_with_nothing_new_changes_nothing(self) -> None:
        self.run_check()
        pushed = self.git("--git-dir", str(self.origin), "rev-parse", "update/llm-agents")
        r = self.run_check()
        self.assertEqual(r["llm-agents"]["status"], "unchanged")
        self.assertEqual(r["herdr"]["status"], "unchanged")
        self.assertEqual(len(self.state()["prs"]), 2)
        self.assertEqual(self.git("--git-dir", str(self.origin), "rev-parse", "update/llm-agents"),
                         pushed)

    def test_a_moved_upstream_rebuilds_the_bump_and_carries_review_commits(self) -> None:
        self.run_check(("--only"), "llm-agents")
        review = self.t / "review"
        self.git("clone", "-q", "-b", "update/llm-agents", str(self.origin), str(review))
        (review / "ADOPT.md").write_text("adopt a new setting\n")
        self.git("-C", str(review), "add", "ADOPT.md")
        self.git("-C", str(review), "commit", "-q", "-m", "claude-code: take the new setting")
        self.git("-C", str(review), "push", "-q", "origin", "update/llm-agents")

        self.edit_state(heads={"numtide/llm-agents.nix": A2})
        r = self.run_check("--only", "llm-agents")
        self.assertEqual(r["llm-agents"]["status"], "refreshed")
        self.assertEqual(len(r["llm-agents"]["carried"]), 1)
        self.assertEqual(self.origin_file("update/llm-agents", "ADOPT.md"), "adopt a new setting")
        lock = json.loads(self.origin_file("update/llm-agents", "flake.lock"))
        self.assertEqual(lock["nodes"]["llm-agents"]["locked"]["rev"], A2)
        log = self.git("--git-dir", str(self.origin), "log", "--format=%s", "main..update/llm-agents")
        self.assertEqual(log.splitlines(), ["claude-code: take the new setting",
                                            f"llm-agents: bump to {A2[:8]} (1970-01-01)"])
        pr = self.state()["prs"][0]
        self.assertIn("| claude-code | 2.1.287 | 2.1.297 |", pr["body"])
        self.assertIn("Carried from the previous round", pr["body"])
        self.assertEqual(len(self.state()["prs"]), 1)
        self.assert_tidy()

    def test_an_upstream_move_that_changes_no_watched_version_is_skipped(self) -> None:
        s = self.state()
        s["versions"][A1] = {"claude-code": "2.1.287"}
        self.write_state(s)
        r = self.run_check("--only", "llm-agents")
        self.assertEqual(r["llm-agents"]["status"], "no-version-change")
        self.assertEqual(self.state()["prs"], [])
        self.assertEqual(self.origin_branches(), ["main"])
        self.assert_tidy()

    def test_main_catching_up_closes_the_pr_and_its_branch(self) -> None:
        self.run_check("--only", "llm-agents")
        (self.seed / "flake.lock").write_text(lock_json(A1, H0))
        self.git("-C", str(self.seed), "commit", "-q", "-am", "llm-agents by hand")
        self.git("-C", str(self.seed), "push", "-q", str(self.origin), "main")
        r = self.run_check("--only", "llm-agents")
        self.assertEqual(r["llm-agents"]["status"], "closed")
        self.assertEqual(self.state()["prs"][0]["state"], "closed")
        self.assertEqual(self.origin_branches(), ["main"])

    def test_main_catching_up_keeps_unmerged_review_commits(self) -> None:
        self.run_check("--only", "llm-agents")
        review = self.t / "review"
        self.git("clone", "-q", "-b", "update/llm-agents", str(self.origin), str(review))
        (review / "ADOPT.md").write_text("pending reviewed change")
        self.git("-C", str(review), "add", "ADOPT.md")
        self.git("-C", str(review), "commit", "-qam", "reviewed adoption")
        self.git("-C", str(review), "push", "-q", "origin", "update/llm-agents")
        (self.seed / "flake.lock").write_text(lock_json(A1, H0))
        self.git("-C", str(self.seed), "commit", "-qam", "input bumped separately")
        self.git("-C", str(self.seed), "push", "-q", str(self.origin), "main")
        result = self.run_check("--only", "llm-agents")["llm-agents"]
        self.assertEqual(result["status"], "review-pending")
        self.assertEqual(len(result["pending_commits"]), 1)
        self.assertEqual(self.state()["prs"][0]["state"], "open")
        self.assertIn("update/llm-agents", self.origin_branches())

    def test_a_flaky_github_read_is_retried(self) -> None:
        self.edit_state(api_fail=["anthropics/claude-code/releases"], api_fail_once=True)
        r = self.run_check("--only", "llm-agents")
        self.assertEqual(r["llm-agents"]["status"], "opened")
        self.assertIn("cc 296 notes", self.state()["prs"][0]["body"])

    def test_unreadable_release_notes_still_open_the_pr(self) -> None:
        self.edit_state(api_fail=["anthropics/claude-code/releases"])
        r = self.run_check("--only", "llm-agents")
        self.assertEqual(r["llm-agents"]["status"], "opened")
        self.assertIn("the release notes could not be read this run", self.state()["prs"][0]["body"])
        self.assert_tidy()

    def test_dry_run_changes_nothing(self) -> None:
        r = self.run_check("--dry-run")
        self.assertEqual(r["llm-agents"]["status"], "would-open")
        self.assertEqual(r["herdr"]["status"], "would-open")
        self.assertEqual(self.origin_branches(), ["main"])
        self.assertEqual(self.state()["prs"], [])
        self.assertFalse((self.t / "wt").exists())

    def test_missing_version_probe_is_an_error_not_a_quiet_night(self) -> None:
        state = self.state()
        state["versions"][A0] = {}
        self.write_state(state)
        results = self.run_check("--only", "llm-agents", expected_exit=1)
        self.assertIn("version probe missing", results["llm-agents"]["error"])
        self.assertEqual(self.origin_branches(), ["main"])
        self.assert_tidy()

    def test_review_worktree_is_never_deleted(self) -> None:
        self.run_check("--only", "llm-agents")
        self.git("-C", str(self.repo), "fetch", "origin")
        review = self.t / "wt" / "update-llm-agents"
        self.git("-C", str(self.repo), "worktree", "add", "-b", "update/llm-agents",
                 str(review), "origin/update/llm-agents")
        (review / "uncommitted.txt").write_text("live review")
        self.edit_state(heads={"numtide/llm-agents.nix": A2})
        self.run_check("--only", "llm-agents")
        self.assertEqual((review / "uncommitted.txt").read_text(), "live review")
        self.assertTrue(self.git("-C", str(self.repo), "branch", "--list", "update/llm-agents"))

    def test_review_conflict_preserves_remote_tip(self) -> None:
        self.run_check("--only", "llm-agents")
        review = self.t / "review"
        self.git("clone", "-q", "-b", "update/llm-agents", str(self.origin), str(review))
        (review / "flake.nix").write_text("reviewer edits the declaration\n")
        self.git("-C", str(review), "commit", "-qam", "reviewed adoption")
        self.git("-C", str(review), "push", "-q", "origin", "update/llm-agents")
        old_tip = self.git("--git-dir", str(self.origin), "rev-parse", "update/llm-agents")
        (self.seed / "flake.nix").write_text("main edits the declaration differently\n")
        self.git("-C", str(self.seed), "commit", "-qam", "new main")
        self.git("-C", str(self.seed), "push", "-q", str(self.origin), "main")
        self.edit_state(heads={"numtide/llm-agents.nix": A2})
        results = self.run_check("--only", "llm-agents", expected_exit=1)
        self.assertIn("existing PR preserved", results["llm-agents"]["error"])
        self.assertEqual(self.git("--git-dir", str(self.origin), "rev-parse", "update/llm-agents"), old_tip)
        self.assert_tidy()

    def test_changed_main_refreshes_unchanged_upstream(self) -> None:
        self.run_check("--only", "llm-agents")
        (self.seed / "unrelated.txt").write_text("main changed")
        self.git("-C", str(self.seed), "add", "unrelated.txt")
        self.git("-C", str(self.seed), "commit", "-qam", "new main")
        self.git("-C", str(self.seed), "push", "-q", str(self.origin), "main")
        results = self.run_check("--only", "llm-agents")
        self.assertEqual(results["llm-agents"]["status"], "refreshed")
        self.assertEqual(self.origin_file("update/llm-agents", "unrelated.txt"), "main changed")

    def test_background_worker_outlives_parent_and_holds_lock_until_result(self):
        self.env["FAKE_NIX_DELAY"] = "0.25"
        launched = subprocess.run([sys.executable, str(SCRIPT), "--background", "--json", "--only", "herdr"],
                                  env=self.env, capture_output=True, text=True, timeout=10)
        self.assertEqual(launched.returncode, 0, launched.stderr)
        receipt = json.loads(launched.stdout)
        self.assertEqual(receipt["status"], "launched")
        self.assertEqual(os.getsid(receipt["pid"]), receipt["pid"])
        # The launching process has exited. A second invocation cannot acquire
        # the lock still held by the worker in its separate process session.
        duplicate = subprocess.run([sys.executable, str(SCRIPT), "--background", "--json"],
                                   env=self.env, capture_output=True, text=True, timeout=10)
        self.assertEqual(duplicate.returncode, 75)
        self.assertEqual(json.loads(duplicate.stdout)["active_job"]["pid"], receipt["pid"])
        deadline = time.monotonic() + 20
        while time.monotonic() < deadline:
            result = json.loads(Path(receipt["job"]).read_text())
            if result["status"] == "completed":
                break
            time.sleep(0.05)
        self.assertEqual(result["status"], "completed", result)
        self.assertTrue(result["ok"])
        self.assertTrue(Path(receipt["log"]).exists())
        self.assertEqual(result["inputs"][0]["status"], "opened")
        self.assert_tidy()

    def test_background_gate_failure_is_durable(self):
        self.edit_state(fail=["update/herdr"])
        launched = subprocess.run([sys.executable, str(SCRIPT), "--background", "--json", "--only", "herdr"],
                                  env=self.env, capture_output=True, text=True, timeout=10)
        self.assertEqual(launched.returncode, 0)
        receipt = json.loads(launched.stdout)
        deadline = time.monotonic() + 20
        while time.monotonic() < deadline:
            result = json.loads(Path(receipt["job"]).read_text())
            if result["status"] == "completed":
                break
            time.sleep(0.05)
        self.assertEqual(result["status"], "completed", result)
        self.assertFalse(result["ok"])
        self.assertFalse(result["inputs"][0]["gate"]["ok"])

    def test_interrupted_background_job_is_reported_before_launching_more(self):
        state = self.t / "state"
        jobs = state / "jobs"
        jobs.mkdir(parents=True)
        job = jobs / "previous.json"
        receipt = {"status": "running", "pid": 999999999, "job": str(job), "run": "previous"}
        job.write_text(json.dumps(receipt))
        (state / "last-launch.json").write_text(json.dumps(receipt))
        result = subprocess.run([sys.executable, str(SCRIPT), "--background", "--json"],
                                env=self.env, capture_output=True, text=True, timeout=10)
        self.assertEqual(result.returncode, 1)
        self.assertEqual(json.loads(result.stdout)["previous"]["status"], "interrupted")
        self.assertEqual(self.state()["prs"], [])


class Nightly(unittest.TestCase):
    def test_paris_date_crosses_utc_midnight_and_dst(self):
        self.assertEqual(uc.night_key(dt.datetime(2026, 10, 21, 23, tzinfo=dt.timezone.utc)), "2026-10-21")
        self.assertEqual(uc.night_key(dt.datetime(2026, 10, 26, 23, 30, tzinfo=dt.timezone.utc)), "2026-10-26")

    def invoke(self, *flags):
        output = io.StringIO()
        with contextlib.redirect_stdout(output):
            code = uc.main(["--if-idle", "--json", *flags])
        return code, json.loads(output.getvalue())

    def test_busy_defers_without_fetch_or_stamp(self):
        with tempfile.TemporaryDirectory() as directory, patch.object(uc, "STATE", Path(directory)), \
                patch.object(uc, "busy_reasons", return_value=["working Herdr pane"]), \
                patch.object(uc, "Run") as run:
            code, report = self.invoke()
            self.assertEqual((code, report["status"]), (0, "deferred"))
            run.assert_not_called()
            self.assertFalse((Path(directory) / "last-night.json").exists())
            self.assertEqual(len(list((Path(directory) / "runs").glob("*.json"))), 1)

    def test_completed_failure_is_visible_and_not_rebuilt_hourly(self):
        run = Mock(main="abc", watch={"inputs": [{"name": "herdr"}]})
        run.check.return_value = {"input": "herdr", "status": "opened", "gate": {"ok": False}, "draft": True}
        with tempfile.TemporaryDirectory() as directory, patch.object(uc, "STATE", Path(directory)), \
                patch.object(uc, "busy_reasons", return_value=[]), patch.object(uc, "Run", return_value=run):
            code, report = self.invoke()
            self.assertEqual((code, report["status"], report["ok"]), (1, "completed", False))
            code, report = self.invoke()
            self.assertEqual((code, report["status"]), (1, "already-checked"))
            self.assertFalse(report["previous"]["ok"])
            self.assertEqual(run.check.call_count, 1)
            self.assertFalse(json.loads((Path(directory) / "last-night.json").read_text())["ok"])

    def test_dry_run_does_not_consume_night(self):
        run = Mock(main="abc", watch={"inputs": []})
        with tempfile.TemporaryDirectory() as directory, patch.object(uc, "STATE", Path(directory)), \
                patch.object(uc, "busy_reasons", return_value=[]), patch.object(uc, "Run", return_value=run):
            self.invoke("--dry-run")
            self.assertFalse((Path(directory) / "last-night.json").exists())

    def test_unknown_idle_state_errors_without_running(self):
        with tempfile.TemporaryDirectory() as directory, patch.object(uc, "STATE", Path(directory)), \
                patch.object(uc, "busy_reasons", side_effect=uc.CheckError("Herdr unavailable")), \
                patch.object(uc, "Run") as run:
            code, report = self.invoke()
            self.assertEqual((code, report["status"]), (1, "error"))
            run.assert_not_called()

    def test_busy_between_inputs_defers_remaining_work(self):
        run = Mock(main="abc", watch={"inputs": [{"name": "a"}, {"name": "b"}]})
        run.check.return_value = {"input": "a", "status": "current"}
        with tempfile.TemporaryDirectory() as directory, patch.object(uc, "STATE", Path(directory)), \
                patch.object(uc, "busy_reasons", side_effect=[[], [], ["new interactive work"]]), \
                patch.object(uc, "Run", return_value=run):
            code, report = self.invoke()
            self.assertEqual((code, report["status"]), (0, "deferred"))
            self.assertEqual(run.check.call_count, 1)
            self.assertFalse((Path(directory) / "last-night.json").exists())

    def test_herdr_probe_is_conservative_and_read_only(self):
        panes = [{"agent": "codex", "agent_status": "working", "pane_id": "p1"},
                 {"agent": "claude", "agent_status": "idle", "pane_id": "p2"},
                 {"agent_status": "unknown", "pane_id": "shell"}]
        with patch.object(uc.os, "getloadavg", return_value=(0, 0, 0)), \
                patch.object(uc.Path, "glob", return_value=[]), \
                patch.object(uc, "sh", return_value=json.dumps({"result": {"panes": panes}})) as sh:
            self.assertEqual(uc.busy_reasons(), ["Herdr pane p1 is working"])
            sh.assert_called_once_with(["herdr", "pane", "list"], timeout=15)


class IssueWatch(unittest.TestCase):
    def make_run(self, directory):
        run = uc.Run.__new__(uc.Run)
        run.args = argparse.Namespace(dry_run=False)
        run.main = "main-commit"
        run.logs = Path(directory)
        run.eval_versions = Mock(return_value={"strix": "7.2.12", "nas": "7.2.10"})
        return run

    def test_kernel_series_ignores_patch_and_rc_and_keeps_closed_issue(self):
        entry = {"name": "linux", "source": "kernel.org", "seriesOnly": True,
                 "versions": {"strix": "x", "nas": "y"}, "reason": "Review before reboot."}
        for available, expected in [("7.2.99", "current"), ("7.3", "issue-exists")]:
            with self.subTest(available), tempfile.TemporaryDirectory() as directory:
                run = self.make_run(directory)
                response = io.StringIO(json.dumps({"releases": [{"version": available}, {"version": "7.4-rc1"}]}))
                with patch.object(uc.urllib.request, "urlopen", return_value=response), \
                        patch.object(uc, "gh_json", return_value=[{"title": "update: linux 7.3 available", "url": "issue-url", "state": "CLOSED"}]), \
                        patch.object(uc, "sh") as sh:
                    result = run.check_issue(entry)
                    self.assertEqual(result["status"], expected)
                    sh.assert_not_called()
                    if expected == "issue-exists":
                        self.assertEqual(result["issue_state"], "CLOSED")

    def test_new_series_opens_issue_without_nix_update(self):
        entry = {"name": "linux", "source": "kernel.org", "seriesOnly": True,
                 "versions": {"strix": "x", "nas": "y"}, "reason": "Review before reboot."}
        with tempfile.TemporaryDirectory() as directory:
            run = self.make_run(directory)
            response = io.StringIO(json.dumps({"releases": [{"version": "7.3.2", "gitweb": "https://kernel.org/"}]}))
            with patch.object(uc.urllib.request, "urlopen", return_value=response), \
                    patch.object(uc, "gh_json", return_value=[]), \
                    patch.object(uc, "sh", return_value="https://github.com/example/issues/1") as sh:
                result = run.check_issue(entry)
                self.assertEqual((result["status"], result["available"]), ("issue-opened", "7.3"))
                self.assertEqual(sh.call_args.args[0][:3], ["gh", "issue", "create"])
                self.assertIn("7.2.12", (Path(directory) / "linux.issue.md").read_text())
                run.eval_versions.assert_called_once_with(uc.REPO, entry["versions"], "main-commit")

    def test_github_watch_uses_latest_stable_release(self):
        entry = {"name": "fish", "source": "github", "repo": "fish-shell/fish-shell",
                 "tagPrefix": "", "versions": {"fish": "x"}, "reason": "Review shell."}
        with tempfile.TemporaryDirectory() as directory:
            run = self.make_run(directory)
            run.eval_versions.return_value = {"fish": "4.8.1"}
            run.args.dry_run = True
            run.releases = Mock(return_value=[release("4.9.3", "today", "stable"), release("5.0.0", "today", "preview", True)])
            with patch.object(uc, "gh_json", return_value=[]), patch.object(uc, "sh") as sh:
                result = run.check_issue(entry)
                self.assertEqual((result["status"], result["available"]), ("would-open-issue", "4.9.3"))
                sh.assert_not_called()


if __name__ == "__main__":
    unittest.main()
