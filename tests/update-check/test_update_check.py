from __future__ import annotations

import importlib.machinery
import importlib.util
import json
import os
import re
import subprocess
import sys
import tempfile
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
import json, os, re, subprocess, sys
from pathlib import Path
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
    tree = re.search(r'git\+file://([^"]+)', args[-1]).group(1)
    lock = json.loads((Path(tree) / "flake.lock").read_text())
    merged = {}
    for key in lock["nodes"]["root"]["inputs"].values():
        merged.update(state["versions"].get(lock["nodes"][key]["locked"]["rev"], {}))
    paths = json.loads(os.environ["UPDATE_CHECK_PATHS"])
    print(json.dumps({k: merged.get(k) for k in paths}))
    sys.exit(0)
branch = subprocess.run(["git", "rev-parse", "--abbrev-ref", "HEAD"], capture_output=True, text=True).stdout.strip()
if any(f in branch for f in state["fail"]):
    print("error: builder for %s failed" % branch)
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

    def run_check(self, *args: str) -> dict:
        p = subprocess.run([sys.executable, str(SCRIPT), "--json", *args], env=self.env,
                           capture_output=True, text=True)
        self.assertEqual(p.returncode, 0, p.stderr + p.stdout)
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
        r = self.run_check()
        self.assertFalse(r["herdr"]["gate"]["ok"])
        prs = {p["head"]: p for p in self.state()["prs"]}
        self.assertTrue(prs["update/herdr"]["isDraft"])
        self.assertIn("builder for update/herdr failed", prs["update/herdr"]["body"])
        self.assertFalse(prs["update/llm-agents"]["isDraft"])

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


if __name__ == "__main__":
    unittest.main()
