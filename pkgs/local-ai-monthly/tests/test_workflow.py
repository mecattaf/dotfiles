from __future__ import annotations

import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest


PACKAGE_ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(PACKAGE_ROOT))

import workflow  # noqa: E402


def command(*argv: str, cwd: Path) -> str:
    completed = subprocess.run(
        argv, cwd=cwd, text=True, capture_output=True, check=True
    )
    return completed.stdout.strip()


class StateTests(unittest.TestCase):
    def test_markdown_state_is_the_only_pin_advance(self) -> None:
        state = {
            "schema_version": 1,
            "source_pins": {"owner/repo": "b" * 40},
        }
        markdown = (
            "# Brief\n\n"
            + workflow.STATE_BEGIN
            + workflow.canonical_json(state)
            + workflow.STATE_END
        )
        self.assertEqual(workflow.parse_embedded_state(markdown), state)
        registry = {
            "sources": [
                {"slug": "owner/repo", "baseline": "a" * 40},
                {"slug": "owner/other", "baseline": "c" * 40},
            ]
        }
        self.assertEqual(
            workflow.accepted_pins(registry, state),
            {"owner/repo": "b" * 40, "owner/other": "c" * 40},
        )
        self.assertEqual(workflow.strip_embedded_state(markdown), "# Brief\n")


class PathTests(unittest.TestCase):
    def test_path_policy_is_deterministic(self) -> None:
        source = {
            "watched_paths": ["README.md", "data/**"],
            "ignore_paths": ["data/generated/**"],
            "evidence_paths": ["**/*.md", "**/*.json", "README.md"],
        }
        self.assertEqual(
            workflow.relevant_paths(
                source,
                [
                    "README.md",
                    "data/run/result.json",
                    "data/generated/result.json",
                    "data/run/blob.bin",
                    "unwatched.md",
                ],
            ),
            ["README.md", "data/run/result.json"],
        )


class ModelResolutionTests(unittest.TestCase):
    def setUp(self) -> None:
        self.catalog = {
            "deployments": {
                "fast-row": {
                    "model": "fast-model",
                    "role": "utility",
                    "status": "canonical",
                    "ramTierGb": 4,
                },
                "daily-row": {
                    "model": "daily-model",
                    "role": "general",
                    "status": "canonical",
                    "ramTierGb": 24,
                },
                "quality-row": {
                    "model": "quality-model",
                    "role": "quality",
                    "status": "canonical",
                    "ramTierGb": 128,
                },
            }
        }
        self.inference = {
            "model_class": "strongest",
            "fallback_classes": ["fast"],
            "classes": {
                "strongest": {
                    "role_order": ["quality", "general"],
                    "ram_order": "descending",
                },
                "fast": {
                    "role_order": ["utility", "general"],
                    "ram_order": "ascending",
                },
            },
        }

    def test_strongest_is_abstract_but_resolves_to_loaded_quality(self) -> None:
        self.assertEqual(
            workflow.resolve_model(
                self.catalog,
                self.inference,
                ["fast-model", "daily-model", "quality-model"],
                None,
            ),
            ("quality-model", "strongest"),
        )

    def test_missing_quality_falls_through_role_then_class(self) -> None:
        self.assertEqual(
            workflow.resolve_model(self.catalog, self.inference, ["fast-model"], None),
            ("fast-model", "fast"),
        )


class GitPreparationTests(unittest.TestCase):
    def test_local_repository_becomes_one_bounded_task(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            upstream = root / "upstream"
            upstream.mkdir()
            command("git", "init", "-b", "main", cwd=upstream)
            command("git", "config", "user.name", "Fixture", cwd=upstream)
            command(
                "git", "config", "user.email", "fixture@example.invalid", cwd=upstream
            )
            (upstream / "README.md").write_text("baseline\n", encoding="utf-8")
            command("git", "add", "README.md", cwd=upstream)
            command("git", "commit", "-m", "baseline", cwd=upstream)
            baseline = command("git", "rev-parse", "HEAD", cwd=upstream)
            (upstream / "README.md").write_text(
                "candidate https://huggingface.co/example/model\n", encoding="utf-8"
            )
            command("git", "commit", "-am", "candidate", cwd=upstream)

            source = {
                "slug": "fixture/repo",
                "url": str(upstream),
                "processor": "generic",
                "partition": "files",
                "watched_paths": ["README.md"],
            }
            registry = {
                "limits": {
                    "commit_log": 20,
                    "evidence_files": 12,
                    "excerpt_chars": 4000,
                    "total_evidence_chars": 50000,
                    "hf_inspections": 4,
                    "git_timeout_seconds": 30,
                }
            }
            result = workflow.prepare_source(
                source,
                baseline,
                root / "clones",
                registry,
                {"catalog": {"deployments": {"accepted": {}}}},
                "run",
            )
            self.assertEqual(result["status"], "prepared", result.get("error"))
            self.assertEqual(len(result["tasks"]), 1)
            bundle = result["tasks"][0]["bundle"]
            self.assertEqual(bundle["allowed_hf_repositories"], ["example/model"])
            self.assertEqual(bundle["tool_quotas"]["hf_inspections"], 1)
            self.assertEqual(bundle["scope"]["files"], ["README.md"])


class ContractTests(unittest.TestCase):
    def setUp(self) -> None:
        self.schema = json.loads(
            (PACKAGE_ROOT / "schema" / "brief.schema.json").read_text(encoding="utf-8")
        )
        self.bundle = {
            "task_id": "run:fixture:001",
            "source": {
                "slug": "fixture/repo",
                "baseline_sha": "a" * 40,
                "observed_head_sha": "b" * 40,
                "comparison_kind": "incremental-git-interval",
                "commit_count": 1,
            },
            "scope": {"partition": "README.md-01-01"},
            "evidence": [
                {
                    "id": "E001",
                    "path": "README.md",
                    "url": "https://github.com/fixture/repo/compare/a...b",
                    "content": "candidate",
                }
            ],
        }

    def brief(self) -> dict:
        return {
            "schema_version": 1,
            "task_id": self.bundle["task_id"],
            "source": dict(self.bundle["source"]),
            "scope": {
                "partition": self.bundle["scope"]["partition"],
                "inspected_evidence_ids": ["E001"],
                "omitted_evidence_ids": [],
            },
            "findings": [
                {
                    "id": "F001",
                    "kind": "claim",
                    "change_class": "new-model",
                    "summary": "A candidate appeared.",
                    "hardware_relevance": "Unknown until tested.",
                    "nix_relevance": "Would require a proposal card.",
                    "topics": ["candidate"],
                    "evidence_ids": ["E001"],
                    "derived_from": [],
                }
            ],
            "roster_proposals": [],
            "decision": {
                "action": "watch",
                "confidence": "medium",
                "unresolved_questions": [],
                "next_baseline_sha": "b" * 40,
            },
            "status": "complete",
        }

    def test_valid_atomic_submission(self) -> None:
        envelope = {"brief": self.brief(), "hf_inspections": []}
        self.assertEqual(
            workflow.validation_errors(
                envelope, self.bundle, self.schema, {"accepted"}
            ),
            [],
        )

    def test_unknown_evidence_fails_closed(self) -> None:
        brief = self.brief()
        brief["findings"][0]["evidence_ids"] = ["E999"]
        errors = workflow.validation_errors(
            {"brief": brief, "hf_inspections": []},
            self.bundle,
            self.schema,
            {"accepted"},
        )
        self.assertTrue(any("unknown evidence" in error for error in errors), errors)

    def test_unknown_hf_inspection_fails_closed(self) -> None:
        brief = self.brief()
        brief["roster_proposals"] = [
            {
                "action": "investigate",
                "relationship": "net-add",
                "stable_model_id": "new-model",
                "comparison_targets": [],
                "improvement_axes": ["quality"],
                "reason": "Covers an unfilled workload.",
                "evidence_ids": ["E001"],
                "hf_inspection_id": "HF999",
                "artifact": {
                    "hf_url": None,
                    "revision": None,
                    "files": [],
                    "runtime_repo": None,
                    "runtime_commit": None,
                    "backend": None,
                    "hosts": [],
                },
                "unresolved_fields": [
                    "hf_url",
                    "revision",
                    "runtime_repo",
                    "runtime_commit",
                    "backend",
                ],
            }
        ]
        errors = workflow.validation_errors(
            {"brief": brief, "hf_inspections": []},
            self.bundle,
            self.schema,
            {"accepted"},
        )
        self.assertTrue(
            any("unknown HF inspection" in error for error in errors), errors
        )

    def test_mechanically_verified_proposal_becomes_markdown_card(self) -> None:
        brief = self.brief()
        brief["roster_proposals"] = [
            {
                "action": "investigate",
                "relationship": "net-add",
                "stable_model_id": "new-model",
                "comparison_targets": [],
                "improvement_axes": ["quality"],
                "reason": "Covers an unfilled workload.",
                "evidence_ids": ["E001", "HF001"],
                "hf_inspection_id": "HF001",
                "artifact": {
                    "hf_url": "https://huggingface.co/example/model",
                    "revision": "c" * 40,
                    "files": [{"path": "model.gguf", "bytes": 10, "sha256": "d" * 64}],
                    "runtime_repo": None,
                    "runtime_commit": None,
                    "backend": None,
                    "hosts": [],
                },
                "unresolved_fields": ["runtime_repo", "runtime_commit", "backend"],
            }
        ]
        inspection = {
            "id": "HF001",
            "repository": "example/model",
            "hf_url": "https://huggingface.co/example/model",
            "requested_revision": "main",
            "revision": "c" * 40,
            "files": [
                {
                    "path": "model.gguf",
                    "bytes": 10,
                    "sha256": "d" * 64,
                    "nix_sri": "sha256-3d3d",
                }
            ],
            "card_data": {"license": "apache-2.0"},
            "api_url": "https://huggingface.co/api/models/example/model/revision/main",
        }
        envelope = {"brief": brief, "hf_inspections": [inspection]}
        self.assertEqual(
            workflow.validation_errors(
                envelope, self.bundle, self.schema, {"accepted"}
            ),
            [],
        )
        source = {
            "slug": "fixture/repo",
            "tasks": [{"bundle": self.bundle, "envelope": envelope}],
        }
        cards = workflow.proposal_cards("2026-08", [source], "quality-model")
        self.assertEqual(len(cards), 1)
        markdown = workflow.render_card(cards[0])
        self.assertIn("Proposal only", markdown)
        self.assertIn("model.gguf", markdown)
        self.assertIn("local-ai-model-proposal", markdown)

        conflicting = json.loads(json.dumps(source))
        conflicting["slug"] = "fixture/other"
        conflicting["tasks"][0]["envelope"]["hf_inspections"][0]["repository"] = (
            "other/model"
        )
        conflicting["tasks"][0]["envelope"]["hf_inspections"][0]["revision"] = "e" * 40
        with self.assertRaisesRegex(
            workflow.WorkflowError, "conflicting proposal cards"
        ):
            workflow.proposal_cards("2026-08", [source, conflicting], "quality-model")


if __name__ == "__main__":
    unittest.main()
