"""Read the existing fleet observation contract without starting collection."""
import argparse
import json
from pathlib import Path
import sys

from observer import refresh_rows, validate_public


MAX_BYTES = 1024 * 1024


class SnapshotError(Exception):
    def __init__(self, code, message):
        self.code, self.message = code, message


def read_snapshot(path):
    try:
        with path.open("rb") as stream:
            raw = stream.read(MAX_BYTES + 1)
    except FileNotFoundError:
        raise SnapshotError("snapshot-missing", "No observation snapshot has been collected yet.") from None
    except OSError:
        raise SnapshotError("snapshot-unreadable", "The observation snapshot could not be read.") from None
    try:
        if len(raw) > MAX_BYTES:
            raise ValueError("snapshot budget exceeded")
        value = json.loads(raw)
        schema = json.loads((Path(__file__).parent / "schema/snapshot-v1.schema.json").read_text())
        if not isinstance(value, dict) or value.get("schemaVersion") != "fleet-observations/1":
            raise ValueError("unsupported snapshot")
        if set(schema["required"]) - set(value) or set(value) - set(schema["properties"]):
            raise ValueError("unexpected snapshot fields")
        if any(not isinstance(value[key], list) for key in ("subjects", "observations", "events", "coverage")):
            raise ValueError("invalid snapshot collections")
        validate_public(value)
        # A stopped observer must not make an expired measurement look current.
        # Keep the original acquisition times and last-good values, and never
        # advance the persisted snapshot or publisher sequence from this reader.
        value["observations"] = [
            refresh_rows([row], row["lastAttemptAt"])[0]
            for row in value["observations"]
        ]
        return value
    except (ValueError, KeyError, TypeError, AttributeError, OSError):
        raise SnapshotError("snapshot-invalid", "The retained observation snapshot is invalid.") from None


def encoded(value):
    return json.dumps(value, ensure_ascii=True, allow_nan=False, sort_keys=True)


def render(value):
    lines = [f"fleet observations  {value['snapshotId']}  generated {value['generatedAt']}",
             "publisher " + encoded(value["publisher"]),
             "catalogue " + value["catalogRevision"]]
    if value.get("synthetic"):
        lines.append("SYNTHETIC FIXTURE")
    for title, key in (("Subjects", "subjects"), ("Observations", "observations"),
                       ("Events", "events"), ("Source coverage", "coverage")):
        lines.extend(["", title + " (as recorded in this snapshot)"])
        for row in value[key]:
            lines.append("  " + encoded(row))
        if not value[key]:
            lines.append("  none recorded")
    return "\n".join(lines) + "\n"


def main(argv=None):
    parser = argparse.ArgumentParser(
        prog="fleet-status observations",
        description="Read all retained fleet/account/compute observations; no collection or network calls.",
    )
    parser.add_argument("--json", action="store_true", help="emit the full fleet-observations/1 contract")
    location = parser.add_mutually_exclusive_group()
    location.add_argument("--state-dir", type=Path, help="the existing fleet-observer state directory")
    location.add_argument("--snapshot", type=Path, help="read a specific retained snapshot file")
    args = parser.parse_args(argv)
    state = args.state_dir or Path.home() / ".local/state/fleet-status"
    path = args.snapshot or state / "public/status.json"
    try:
        value = read_snapshot(path)
    except SnapshotError as exc:
        if args.json:
            print(encoded({"error": {"code": exc.code, "message": exc.message}}), file=sys.stderr)
        else:
            print(f"fleet-status observations: {exc.message} ({exc.code})", file=sys.stderr)
        return 1
    if args.json:
        print(encoded(value))
    else:
        sys.stdout.write(render(value))
    return 0


if __name__ == "__main__":
    sys.exit(main())
