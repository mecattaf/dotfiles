"""Fixture tests for paperless-bridge (dotfiles#136).

Runs as the package's install check (default.nix). Everything is local: a
temp canonical tree shaped like the real /mnt/nas/documents/academic-papers
(catalog/papers.sqlite with the real column names, ocr-june/papers-canonical,
receipts/historical), an in-memory fake of the Paperless REST surface the
bridge uses, and a fake `utility-model` that answers from a canned reply.
Nothing here reaches a network or a model.

BRIDGE_UNDER_TEST names the bridge.py to import (the installed copy in the
Nix build); it defaults to the file beside this one.
"""

import argparse
import hashlib
import importlib.util
import io
import json
import os
import sqlite3
import sys
import tempfile
import textwrap
import unittest
from unittest import mock
from contextlib import redirect_stdout, redirect_stderr

HERE = os.path.dirname(os.path.abspath(__file__))
BRIDGE = os.environ.get("BRIDGE_UNDER_TEST", os.path.join(HERE, "bridge.py"))
TAXONOMY = os.path.join(os.path.dirname(BRIDGE), "taxonomy.json")
if not os.path.exists(TAXONOMY):
    TAXONOMY = os.path.join(HERE, "taxonomy.json")

DB_A = "00878086-f67f-4c94-b861-8f04c97ebd11"  # OCR'd, hashes agree
DB_B = "03047355-9fd0-4f92-93e9-e19b177ca2a5"  # OCR'd from a different payload
DB_C = "0559f09e-08e5-4364-afbf-2695c7bb3ed5"  # mirrored paper, no OCR yet


def sha(data):
    return hashlib.sha256(data).hexdigest()


class FakePaperless:
    """The slice of the Paperless v3 API the bridge touches."""

    def __init__(self):
        self.docs, self.tags, self.notes, self.fields = {}, {}, {}, {}
        self.calls = []

    def add_doc(self, doc_id, **kw):
        self.docs[doc_id] = {"id": doc_id, "tags": [], "content": "", "title": "", **kw}
        self.notes[doc_id] = []

    def tag_id(self, name):
        for t in self.tags.values():
            if t["name"] == name:
                return t["id"]
        tid = len(self.tags) + 1
        self.tags[tid] = {"id": tid, "name": name}
        return tid

    def api(self, method, path, body=None, params=None):
        self.calls.append((method, path, body))
        parts = [p for p in path.split("/") if p][1:]  # drop "api"
        if parts == ["documents"] and method == "GET":
            params = params or {}
            docs = sorted(self.docs.values(), key=lambda d: d["id"])
            stem = params.get("original_filename__istartswith")
            if stem is not None:
                docs = [d for d in docs if (d.get("original_file_name") or "").startswith(stem)]
            n = params.get("page_size", len(docs) or 1)
            page = params.get("page", 1)
            chunk = docs[(page - 1) * n : page * n]
            more = page * n < len(docs)
            return {"count": len(docs), "next": f"page={page + 1}" if more else None, "results": chunk}
        if parts[:1] == ["documents"] and parts[2:] == ["metadata"]:
            doc = self.docs[int(parts[1])]
            return {"original_checksum": doc["checksum"], "media_filename": doc["media_filename"]}
        if parts[:1] == ["documents"] and len(parts) == 2:
            doc = self.docs[int(parts[1])]
            if method == "PATCH":
                doc.update(body)
            return doc
        if parts[:1] == ["documents"] and parts[2:] == ["notes"]:
            if method == "POST":
                self.notes[int(parts[1])].append({"note": body["note"]})
            return list(self.notes[int(parts[1])])
        if parts == ["tags"] and method == "POST":
            tid = self.tag_id(body["name"])
            self.tags[tid].update(body)
            return self.tags[tid]
        if parts == ["custom_fields"] and method == "POST":
            fid = len(self.fields) + 1
            self.fields[fid] = {"id": fid, **body}
            return self.fields[fid]
        raise AssertionError(f"unexpected API call {method} {path}")

    def api_all(self, path, params=None):
        if path == "/api/tags/":
            return list(self.tags.values())
        if path == "/api/custom_fields/":
            return list(self.fields.values())
        if path == "/api/documents/":
            return list(self.docs.values())
        raise AssertionError(f"unexpected api_all {path}")


class BridgeCase(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        t = self.tmp.name
        self.root = os.path.join(t, "documents")
        self.academic = os.path.join(self.root, "academic-papers")
        self.state = os.path.join(t, "state")
        env = {
            "BRIDGE_CANONICAL_ROOT": self.root,
            "BRIDGE_STATE_DIR": self.state,
            "BRIDGE_SPOOL": os.path.join(self.root, ".paperless-consume"),
            "BRIDGE_VIEW_ROOT": os.path.join(self.root, ".paperless-view"),
            "BRIDGE_TAXONOMY": TAXONOMY,
            "BRIDGE_SUGGEST_MODEL": "halogen-qwen3.8-flash-next",
            "PAPERLESS_TOKEN": "fixture-token",
            "XDG_RUNTIME_DIR": t,
        }
        self._old_env = {k: os.environ.get(k) for k in env}
        os.environ.update(env)
        self.build_fixture()
        spec = importlib.util.spec_from_file_location(f"bridge_{id(self)}", BRIDGE)
        self.b = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(self.b)
        self.fake = FakePaperless()
        self.b.api = self.fake.api
        self.b.api_all = self.fake.api_all

    def tearDown(self):
        for k, v in self._old_env.items():
            if v is None:
                os.environ.pop(k, None)
            else:
                os.environ[k] = v
        self.tmp.cleanup()

    # -- fixture shaped like the 2026-09-13 probe of the real corpus

    def write(self, rel, data):
        path = os.path.join(self.root, rel)
        os.makedirs(os.path.dirname(path), exist_ok=True)
        with open(path, "wb" if isinstance(data, bytes) else "w") as f:
            f.write(data)
        return path

    def build_fixture(self):
        self.pdf_a = b"%PDF-1.4 fixture A\n%%EOF\n"
        self.pdf_b = b"%PDF-1.4 fixture B facsimile\n%%EOF\n"
        self.pdf_b_ocr_source = b"%PDF-1.4 fixture B the payload that was OCRed\n%%EOF\n"
        self.pdf_c = b"%PDF-1.4 fixture C\n%%EOF\n"
        self.rel_a = f"academic-papers/historical-originals/by-db-id/{DB_A}/Eisenhardt-1989.pdf"
        self.rel_b = f"academic-papers/historical-facsimiles/by-db-id/{DB_B}/Heckman.pdf"
        self.rel_c = "academic-papers/originals/knowledge/bocconi/syllabus.pdf"
        self.write(self.rel_a, self.pdf_a)
        self.write(self.rel_b, self.pdf_b)
        self.write(self.rel_c, self.pdf_c)
        self.write("general/manual.pdf", b"%PDF-1.4 general\n%%EOF\n")
        # Machinery trees the scan must never inventory.
        self.write(".paperless-view/Paper/2024/x.pdf", self.pdf_a)
        self.write(".paperless-consume/stale.pdf", self.pdf_c)
        self.write("historical/.Trash-1000/files/old.pdf", b"%PDF trash\n")

        recorded = "/mnt/nas/documents/academic-papers"
        for db_id, src in ((DB_A, self.pdf_a), (DB_B, self.pdf_b_ocr_source)):
            pdir = f"academic-papers/ocr-june/papers-canonical/{db_id}"
            self.write(
                f"{pdir}/canonical/paper.md",
                textwrap.dedent(
                    f"""\
                    ---
                    uuid: {db_id}
                    title: "fixture"
                    sha256: {sha(src)}
                    ---

                    <!-- page:001 -->
                    # Making Fast Strategic Decisions

                    zanzibar-only-in-paper-md {db_id[:8]}

                    <!-- page:012 -->
                    closing text
                    """
                ),
            )
            self.write(f"{pdir}/source.json", json.dumps({"db_id": db_id, "sha256": sha(src)}))
            self.write(f"{pdir}/metadata.json", json.dumps({"openalex": {"doi": "10.2307/256434"}}))
        for db_id, local, rel in ((DB_A, self.pdf_a, self.rel_a), (DB_B, self.pdf_b, self.rel_b)):
            self.write(
                f"academic-papers/receipts/historical/{db_id}.json",
                json.dumps({"db_id": db_id, "local_pdf_sha256": sha(local),
                            "local_pdf_path": rel.split("/", 1)[1]}),
            )

        os.makedirs(os.path.join(self.academic, "catalog"), exist_ok=True)
        db = sqlite3.connect(os.path.join(self.academic, "catalog", "papers.sqlite"))
        db.executescript(
            """
            CREATE TABLE paper_archive (db_id TEXT PRIMARY KEY, local_pdf_path TEXT NOT NULL UNIQUE,
              local_pdf_sha256 TEXT);
            CREATE TABLE historical_archive (db_id TEXT PRIMARY KEY, local_pdf_path TEXT UNIQUE,
              local_pdf_sha256 TEXT);
            CREATE TABLE ocr_derivatives (db_id TEXT PRIMARY KEY, source_sha256 TEXT,
              canonical_markdown_path TEXT);
            """
        )
        db.execute("INSERT INTO paper_archive VALUES (?,?,?)",
                   (DB_C, self.rel_c.split("/", 1)[1], sha(self.pdf_c)))
        db.execute("INSERT INTO historical_archive VALUES (?,?,?)",
                   (DB_A, self.rel_a.split("/", 1)[1], sha(self.pdf_a)))
        db.execute("INSERT INTO historical_archive VALUES (?,?,?)",
                   (DB_B, self.rel_b.split("/", 1)[1], sha(self.pdf_b)))
        for db_id, src in ((DB_A, self.pdf_a), (DB_B, self.pdf_b_ocr_source)):
            db.execute(
                "INSERT INTO ocr_derivatives VALUES (?,?,?)",
                (db_id, sha(src),
                 f"{recorded}/ocr-june/papers-canonical/{db_id}/canonical/paper.md"),
            )
        db.commit()
        db.close()

    def run_cmd(self, fn, **kw):
        out, err = io.StringIO(), io.StringIO()
        with redirect_stdout(out), redirect_stderr(err):
            rc = fn(argparse.Namespace(**kw))
        text = out.getvalue().strip()
        try:
            return rc, json.loads(text) if text else None
        except ValueError:
            return rc, text

    def project(self, rel, paperless_id):
        """Mark a scanned entry as relinked into Paperless (the ingest and
        root-helper halves are exercised live, not here)."""
        db = self.b.ledger()
        db.execute(
            "UPDATE entries SET state='relinked', paperless_id=?, media_path=? WHERE rel_path=?",
            (paperless_id, f"Paper/{paperless_id}.pdf", rel),
        )
        db.commit()
        self.fake.add_doc(paperless_id, content="baseline tesseract text", title=rel)


class TestScanAndCatalog(BridgeCase):
    def test_catalog_maps_both_archive_tables(self):
        ids = self.b.academic_db_ids()
        self.assertEqual(ids[self.rel_a], DB_A)
        self.assertEqual(ids[self.rel_b], DB_B)
        self.assertEqual(ids[self.rel_c], DB_C)

    def test_scan_inventories_with_db_ids_and_skips_machinery(self):
        rc, out = self.run_cmd(self.b.cmd_scan)
        self.assertEqual(rc, 0)
        self.assertEqual(out["added"], 4)
        rows = {r["rel_path"]: r for r in self.b.ledger().execute("SELECT * FROM entries")}
        self.assertEqual(set(rows), {self.rel_a, self.rel_b, self.rel_c, "general/manual.pdf"})
        self.assertEqual(rows[self.rel_a]["academic_db_id"], DB_A)
        self.assertIsNone(rows["general/manual.pdf"]["academic_db_id"])
        rc, out = self.run_cmd(self.b.cmd_scan)
        self.assertEqual(out["added"], 0)

    def test_checksum_accepts_v31_sha256_and_v30_md5(self):
        s, m = sha(self.pdf_a), hashlib.md5(self.pdf_a).hexdigest()
        self.assertTrue(self.b.checksum_matches(s, s, m))
        self.assertTrue(self.b.checksum_matches(m, s, m))
        self.assertFalse(self.b.checksum_matches(sha(b"other"), s, m))
        self.assertFalse(self.b.checksum_matches(s[:32], s, m))


class TestEnrich(BridgeCase):
    def test_resolve_rebases_catalog_path_and_collects_hash_claims(self):
        art = self.b.resolve_canonical(DB_A)
        self.assertTrue(art["md_path"].startswith(self.academic))
        self.assertEqual(set(art["source_hashes"]), {"catalog", "frontmatter", "source.json"})
        self.assertIsNone(self.b.canonical_mismatch(art, sha(self.pdf_a)))
        self.assertIsNone(self.b.resolve_canonical(DB_C))

    def test_resolve_falls_back_to_layout_without_catalog_row(self):
        os.unlink(os.path.join(self.academic, "catalog", "papers.sqlite"))
        art = self.b.resolve_canonical(DB_A)
        self.assertTrue(os.path.isfile(art["md_path"]))
        self.assertEqual(set(art["source_hashes"]), {"frontmatter", "source.json"})

    def test_page_markers_real_and_sourced_forms(self):
        md = "---\nsha256: x\n---\n<!-- page:001 -->\nA\n<!-- page:12 source:mineru -->\nB\n"
        self.assertEqual(self.b.page_marker_projection(md), "[page 1]\nA\n[page 12]\nB\n")

    def test_enrich_syncs_matching_and_refuses_mismatched_payload(self):
        self.run_cmd(self.b.cmd_scan)
        self.project(self.rel_a, 11)
        self.project(self.rel_b, 12)
        self.project(self.rel_c, 13)
        rc, out = self.run_cmd(self.b.cmd_enrich)
        self.assertEqual(rc, 0)
        self.assertEqual(out, {"synced": 1, "awaiting_receipt": 1, "source_mismatch": 1})
        a = self.fake.docs[11]
        self.assertIn("zanzibar-only-in-paper-md", a["content"])
        self.assertIn("[page 12]", a["content"])
        self.assertNotIn("sha256:", a["content"])
        vals = {self.fake.fields[f["field"]]["name"]: f["value"] for f in a["custom_fields"]}
        self.assertEqual(vals["academic-db-id"], DB_A)
        self.assertEqual(vals["doi"], "10.2307/256434")
        self.assertEqual(self.fake.docs[12]["content"], "baseline tesseract text")
        with open(os.path.join(self.state, "receipts.jsonl")) as f:
            events = [json.loads(line)["event"] for line in f]
        self.assertIn("enrich-source-mismatch", events)
        # Converged: a second run patches nothing.
        patches = sum(1 for c in self.fake.calls if c[0] == "PATCH")
        rc, out = self.run_cmd(self.b.cmd_enrich)
        self.assertEqual(out["synced"], 0)
        self.assertEqual(patches, sum(1 for c in self.fake.calls if c[0] == "PATCH"))


class TestSuggestAndTags(BridgeCase):
    def fake_utility(self, reply):
        script = os.path.join(self.tmp.name, "utility.py")
        with open(os.path.join(self.tmp.name, "reply.txt"), "w") as f:
            f.write(reply)
        with open(script, "w") as f:
            f.write(textwrap.dedent(
                f"""\
                import json, sys
                req = json.load(sys.stdin)
                open({os.path.join(self.tmp.name, 'request.json')!r}, 'w').write(json.dumps(req))
                reply = open({os.path.join(self.tmp.name, 'reply.txt')!r}).read()
                print(json.dumps({{"model": "utility",
                                  "choices": [{{"message": {{"content": reply}}}}]}}))
                """
            ))
        self.b.UTILITY_CMD = f"{sys.executable} {script}"

    def suggest(self, **kw):
        args = dict(limit=4, document_id=None, min_confidence=0.5, max_chars=12000,
                    timeout=60, force=False)
        args.update(kw)
        return self.run_cmd(self.b.cmd_suggest, **args)

    def test_parse_candidates_filters_vocabulary_and_confidence(self):
        allowed = {"kind/paper", "kind/book"}
        reply = ('<think>{"tags": [{"slug": "kind/book", "confidence": 1}]}</think> Sure: '
                 '{"tags": [{"slug": "kind/paper", "confidence": 0.9},'
                 ' {"slug": "status/reading", "confidence": 0.99},'
                 ' {"slug": "kind/book", "confidence": 0.2},'
                 ' {"slug": "kind/invented", "confidence": 0.8},'
                 ' {"slug": "kind/paper", "confidence": true}]}')
        self.assertEqual(self.b.parse_candidates(reply, allowed, 0.5), [("kind/paper", 0.9)])
        self.assertEqual(self.b.parse_candidates("no json here", allowed, 0.5), [])

    def test_suggest_writes_candidates_note_and_is_idempotent(self):
        self.fake.add_doc(21, content="An academic paper about strategy.", title="paper")
        self.fake.add_doc(22, content="Oven manual", title="manual", tags=[self.fake.tag_id("status/inbox")])
        self.fake_utility('{"tags": [{"slug": "kind/paper", "confidence": 0.82},'
                          ' {"slug": "personal/favorite", "confidence": 0.9}]}')
        rc, out = self.suggest()
        self.assertEqual(rc, 0)
        with open(os.path.join(self.tmp.name, "request.json")) as f:
            req = json.load(f)
        self.assertEqual(req["model"], "utility")
        self.assertIn("kind/paper", req["messages"][0]["content"])
        self.assertNotIn("status/inbox", req["messages"][0]["content"])
        cand = self.fake.tag_id("ai-candidate/kind/paper")
        self.assertIn(cand, self.fake.docs[21]["tags"])
        self.assertEqual(self.fake.tags[cand]["matching_algorithm"], 0)
        self.assertIn(self.fake.tag_id("status/inbox"), self.fake.docs[22]["tags"])
        self.assertFalse(any(t["name"] == "ai-candidate/personal/favorite" for t in self.fake.tags.values()))
        note = self.fake.notes[21][0]["note"]
        self.assertTrue(note.startswith("paperless-bridge suggest\n"))
        rec = json.loads(note.split("\n", 1)[1])
        self.assertEqual(rec["model"], "halogen-qwen3.8-flash-next")
        self.assertEqual(rec["taxonomy_version"], 1)
        self.assertEqual(rec["candidates"], [{"slug": "kind/paper", "confidence": 0.82}])
        rc, out = self.suggest()
        self.assertEqual(out["suggested"], [])
        self.assertEqual(out["skipped_already_suggested"], [21, 22])
        self.assertEqual(len(self.fake.notes[21]), 1)

    def test_suggest_limit_advances_through_the_corpus(self):
        for i in range(1, 61):
            self.fake.add_doc(i, content=f"doc {i}", title=f"t{i}")
        self.fake_utility('{"tags": []}')
        seen = []
        for _ in range(3):
            rc, out = self.suggest(limit=25)
            self.assertEqual(rc, 0)
            seen.append([s["document"] for s in out["suggested"]])
        self.assertEqual(seen[0], list(range(1, 26)))
        self.assertEqual(seen[1], list(range(26, 51)))
        self.assertEqual(seen[2], list(range(51, 61)))

    def test_accept_candidate_round_trip_through_sync_tags(self):
        self.run_cmd(self.b.cmd_scan)
        self.project(self.rel_a, 31)
        self.fake_utility('{"tags": [{"slug": "kind/paper", "confidence": 0.9}]}')
        self.suggest(document_id=[31])
        # Human acceptance: candidate out, owning-namespace tag in.
        doc = self.fake.docs[31]
        doc["tags"] = [t for t in doc["tags"] if t != self.fake.tag_id("ai-candidate/kind/paper")]
        doc["tags"].append(self.fake.tag_id("kind/paper"))
        rc, out = self.run_cmd(self.b.cmd_sync_tags)
        self.assertEqual(rc, 0, out)
        self.assertEqual(out["drift"], [])
        self.assertEqual(out["sidecars_updated"], 1)
        rows = {r["rel_path"]: r for r in self.b.ledger().execute("SELECT * FROM entries")}
        side = os.path.join(self.state, "accepted-tags", f"{rows[self.rel_a]['source_id']}.json")
        with open(side) as f:
            self.assertEqual(json.load(f)["tags"], ["kind/paper"])
        rc, out = self.run_cmd(self.b.cmd_sync_tags)
        self.assertEqual((out["tags_created"], out["sidecars_updated"]), (0, 0))

    def test_unknown_machine_tag_is_drift(self):
        self.fake.tag_id("ai-candidate/status/reading")
        rc, out = self.run_cmd(self.b.cmd_sync_tags)
        self.assertEqual(rc, 1)
        self.assertEqual(out["drift"], ["ai-candidate/status/reading"])


class TestIngestParking(BridgeCase):
    """Entries Paperless cannot take must leave the head of the queue."""

    def ingest(self, batch=10):
        return self.run_cmd(self.b.cmd_ingest, batch=batch, timeout=0)

    def states(self):
        return {r["rel_path"]: r["state"] for r in self.b.ledger().execute("SELECT * FROM entries")}

    def test_unreadable_is_parked_then_requeued(self):
        os.chmod(os.path.join(self.root, self.rel_a), 0o600)
        self.run_cmd(self.b.cmd_scan)
        rc, out = self.ingest()
        st = self.states()
        self.assertEqual(st[self.rel_a], "unreadable")
        # Readable entries were staged and timed out (no consumer here).
        self.assertEqual(st["general/manual.pdf"], "consume-timeout")
        self.assertFalse(os.path.exists(os.path.join(
            self.root, ".paperless-consume", "%s.pdf" % self.b.ledger().execute(
                "SELECT source_id FROM entries WHERE rel_path=?", (self.rel_a,)).fetchone()[0])))
        os.chmod(os.path.join(self.root, self.rel_a), 0o644)
        rc, out = self.ingest()
        self.assertEqual(out["requeued"], 1)
        self.assertEqual(self.states()[self.rel_a], "consume-timeout")

    def test_timeout_is_parked_keeps_spool_and_is_adopted(self):
        self.run_cmd(self.b.cmd_scan)
        rc, out = self.ingest(batch=1)
        row = self.b.ledger().execute("SELECT * FROM entries ORDER BY rel_path LIMIT 1").fetchone()
        self.assertEqual(row["state"], "consume-timeout")
        spool = os.path.join(self.root, ".paperless-consume", f"{row['source_id']}.pdf")
        self.assertTrue(os.path.exists(spool))
        # The next batch moves on instead of re-selecting the parked entry.
        rc, out = self.ingest(batch=1)
        self.assertEqual(sorted(self.states().values()).count("consume-timeout"), 2)
        # Paperless finishes late: the parked entry is adopted, spool cleared.
        src = os.path.join(self.root, row["rel_path"])
        with open(src, "rb") as f:
            data = f.read()
        self.fake.add_doc(77, original_file_name=f"{row['source_id']}.pdf",
                          checksum=sha(data), media_filename="Paper/77.pdf")
        rc, out = self.ingest(batch=0)
        self.assertEqual(out["adopted"], 1)
        got = self.b.ledger().execute("SELECT * FROM entries WHERE source_id=?", (row["source_id"],)).fetchone()
        self.assertEqual((got["state"], got["paperless_id"], got["media_path"]), ("ingested", 77, "Paper/77.pdf"))
        self.assertFalse(os.path.exists(spool))


class TestBulk(BridgeCase):
    def bulk(self, **kw):
        args = dict(batch=2, timeout=1, max_rounds=10, min_free_gb=0, max_load=1e9, require_unit=[])
        args.update(kw)
        return self.run_cmd(self.b.cmd_bulk, **args)

    def events(self):
        with open(os.path.join(self.state, "receipts.jsonl")) as f:
            return [json.loads(line) for line in f]

    def test_low_space_pauses_before_touching_anything(self):
        rc, _ = self.bulk(min_free_gb=10**9)
        self.assertEqual(rc, self.b.BULK_PAUSED)
        self.assertEqual(self.events()[-1]["event"], "bulk-paused")
        self.assertIn("low-space", self.events()[-1]["reason"])
        self.assertEqual(self.b.ledger().execute("SELECT COUNT(*) FROM entries").fetchone()[0], 0)

    def test_inactive_router_unit_pauses(self):
        class Proc:
            returncode = 3

        # Scoped: the subprocess module is process-global, shared with
        # every other test's bridge instance.
        with mock.patch.object(self.b.subprocess, "run", lambda *a, **k: Proc()):
            rc, _ = self.bulk(require_unit=["dnsmasq.service"])
        self.assertEqual(rc, self.b.BULK_PAUSED)
        self.assertEqual(self.events()[-1]["reason"], "unit-inactive: dnsmasq.service")

    def test_load_pauses(self):
        rc, _ = self.bulk(max_load=-1)
        self.assertEqual(rc, self.b.BULK_PAUSED)
        self.assertIn("load", self.events()[-1]["reason"])

    def test_rounds_progress_then_converge(self):
        def ingest(args):
            db = self.b.ledger()
            ids = [r[0] for r in db.execute(
                "SELECT source_id FROM entries WHERE state='inventoried' LIMIT ?", (args.batch,))]
            for i in ids:
                db.execute("UPDATE entries SET state='ingested' WHERE source_id=?", (i,))
            db.commit()
            return 0

        self.b.cmd_ingest = ingest
        self.b.cmd_relink = lambda args: 0
        self.b.cmd_verify = lambda args: 0
        rc, _ = self.bulk()
        self.assertEqual(rc, 0)
        kinds = [e["event"] for e in self.events()]
        self.assertEqual(kinds.count("bulk-round"), 2)
        self.assertEqual(kinds[-1], "bulk-converged")

    def test_no_progress_pauses_and_verify_failure_aborts(self):
        self.b.cmd_ingest = lambda args: 0
        self.b.cmd_relink = lambda args: 0
        self.b.cmd_verify = lambda args: 0
        rc, _ = self.bulk()
        self.assertEqual(rc, self.b.BULK_PAUSED)
        self.assertEqual(self.events()[-1]["reason"], "no progress in two rounds")
        self.b.cmd_verify = lambda args: 1
        rc, _ = self.bulk()
        self.assertEqual(rc, 1)
        self.assertEqual(self.events()[-1]["event"], "bulk-aborted")


if __name__ == "__main__":
    unittest.main()
