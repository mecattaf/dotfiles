#!/usr/bin/env python3
"""Publish one committed public snapshot through the narrowly scoped writer.

The observer owns acquisition and sequence generation. This client owns one
conditional HTTPS write and reconciles an uncertain response before another
attempt. Credentials stay in a private NAS file, outside argv and environment.
"""
import argparse
import datetime as dt
import fcntl
import json
import os
from pathlib import Path
import socket
import stat
import tempfile
import urllib.error
import urllib.parse
import urllib.request

MAX_BYTES = 1024 * 1024


class PublishError(Exception):
    """A safe error code, never a URL, credential or upstream response body."""


def utcnow():
    return dt.datetime.now(dt.timezone.utc).isoformat().replace("+00:00", "Z")


def atomic_json(path, value):
    fd, name = tempfile.mkstemp(prefix=".publisher-", dir=path.parent)
    try:
        with os.fdopen(fd, "w") as stream:
            json.dump(value, stream, separators=(",", ":"))
            stream.write("\n")
            stream.flush()
            os.fsync(stream.fileno())
        os.replace(name, path)
        directory = os.open(path.parent, os.O_RDONLY | os.O_DIRECTORY)
        try:
            os.fsync(directory)
        finally:
            os.close(directory)
    finally:
        if os.path.exists(name):
            os.unlink(name)


def secret(path):
    try:
        fd = os.open(path, os.O_RDONLY | os.O_NOFOLLOW)
        with os.fdopen(fd, "rb") as stream:
            info = os.fstat(stream.fileno())
            if not stat.S_ISREG(info.st_mode) or info.st_uid != os.getuid() or info.st_mode & 0o077:
                raise PublishError("publisher-credential-permissions")
            value = stream.read(4097).strip()
        if not 32 <= len(value) <= 4096 or any(chr(c).isspace() for c in value):
            raise PublishError("publisher-credential-invalid")
        return value.decode("ascii")
    except (OSError, UnicodeError) as error:
        raise PublishError("publisher-credential-unavailable") from error


def snapshot(path):
    try:
        with open(path, "rb") as stream:
            body = stream.read(MAX_BYTES + 1)
        value = json.loads(body)
        sequence = value["publisher"]["sequence"]
        identity = value["snapshotId"]
        if (len(body) > MAX_BYTES or value.get("schemaVersion") != "fleet-observations/1"
                or value.get("synthetic") is not False or type(sequence) is not int
                or not 0 <= sequence <= 2**53 - 1 or not isinstance(identity, str)
                or not 1 <= len(identity) <= 128 or "\n" in identity):
            raise ValueError("invalid snapshot")
        return body, sequence, identity
    except (OSError, ValueError, KeyError, TypeError) as error:
        raise PublishError("publisher-snapshot-invalid") from error


class Client:
    def __init__(self, base_url, token, timeout=8, *, allow_http=False):
        url = urllib.parse.urlsplit(base_url)
        if (url.scheme not in (("https", "http") if allow_http else ("https",))
                or not url.hostname or url.username or url.password or url.query or url.fragment
                or url.path not in ("", "/")):
            raise PublishError("publisher-url-invalid")
        self.url = base_url.rstrip("/") + "/v1/status.json"
        self.token = token
        self.timeout = timeout
        # Publication never forwards its bearer credential through a redirect.
        class NoRedirect(urllib.request.HTTPRedirectHandler):
            def redirect_request(self, request, file, code, message, headers, newurl):
                return None
        self.opener = urllib.request.build_opener(NoRedirect())

    def request(self, method, data=None, headers=None):
        request = urllib.request.Request(self.url, data=data, method=method, headers={
            "Authorization": "Bearer " + self.token,
            "Content-Type": "application/json",
            "User-Agent": "fleet-status-observer/1",
            **(headers or {}),
        })
        try:
            with self.opener.open(request, timeout=self.timeout) as response:
                return response.status, dict(response.headers)
        except urllib.error.HTTPError as error:
            code, response_headers = error.code, dict(error.headers)
            error.close()
            return code, response_headers
        except (OSError, urllib.error.URLError, socket.timeout) as error:
            raise PublishError("publisher-network-error") from error

    def head(self):
        code, headers = self.request("HEAD")
        if code == 404:
            return {"sequence": -1, "snapshotId": None, "etag": None}
        if code in (401, 403):
            raise PublishError("publisher-auth-failed")
        if code != 200:
            raise PublishError("publisher-storage-unavailable")
        headers = {name.lower(): value for name, value in headers.items()}
        try:
            sequence = int(headers["x-sequence"])
            identity, etag = headers["x-snapshot-id"], headers["etag"]
            if sequence < 0 or sequence > 2**53 - 1 or not identity or not etag:
                raise ValueError()
        except (KeyError, ValueError):
            raise PublishError("publisher-response-invalid") from None
        return {"sequence": sequence, "snapshotId": identity, "etag": etag}


def publish_file(snapshot_path, state_dir, base_url, token_file, *, allow_http=False):
    state_dir = Path(state_dir)
    state_dir.mkdir(mode=0o700, parents=True, exist_ok=True)
    if state_dir.is_symlink():
        raise PublishError("publisher-state-invalid")
    os.chmod(state_dir, 0o700)
    lock_fd = os.open(state_dir / "publisher.lock", os.O_CREAT | os.O_RDWR | os.O_NOFOLLOW, 0o600)
    with os.fdopen(lock_fd, "a") as lock:
        try:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError:
            return {"status": "pending", "errorCode": "publisher-already-running"}
        state_path = state_dir / "publisher.json"
        if state_path.is_symlink():
            raise PublishError("publisher-state-invalid")
        try:
            state = json.loads(state_path.read_text())
            if not isinstance(state, dict) or type(state.get("remoteSequence", -1)) is not int:
                raise ValueError()
        except FileNotFoundError:
            state = {}
        except (ValueError, OSError):
            raise PublishError("publisher-state-invalid") from None
        state["lastAttemptAt"] = utcnow()
        sequence = identity = None
        try:
            body, sequence, identity = snapshot(snapshot_path)
            client = Client(base_url, secret(token_file), allow_http=allow_http)
            remote = client.head()
            state["remoteSequence"] = max(state.get("remoteSequence", -1), remote["sequence"])

            def succeeded(reconciled=False):
                state.update(remoteSequence=sequence, lastSuccessAt=utcnow(), lastSnapshotId=identity, errorCode=None)
                return {"status": "published", "committedSequence": sequence, "reconciled": reconciled}

            if remote["sequence"] == sequence and remote["snapshotId"] == identity:
                result = succeeded(True)
            elif remote["sequence"] >= sequence:
                raise PublishError("publisher-sequence-conflict")
            else:
                condition = {"If-Match": remote["etag"]} if remote["etag"] else {"If-None-Match": "*"}
                uncertain = False
                try:
                    code, _ = client.request("PUT", body, condition)
                    if code in (200, 201):
                        result = succeeded()
                    elif code in (401, 403):
                        raise PublishError("publisher-auth-failed")
                    elif code in (409, 412):
                        uncertain = True
                    elif code in (400, 413, 422, 428):
                        raise PublishError("publisher-snapshot-refused")
                    else:
                        uncertain = True
                except PublishError as error:
                    if str(error) != "publisher-network-error":
                        raise
                    uncertain = True
                if uncertain:
                    remote = client.head()
                    state["remoteSequence"] = max(state["remoteSequence"], remote["sequence"])
                    if remote["sequence"] == sequence and remote["snapshotId"] == identity:
                        result = succeeded(True)
                    else:
                        raise PublishError("publisher-publication-uncertain")
        except PublishError as error:
            state["errorCode"] = str(error)
            result = {"status": "failed", "errorCode": str(error)}
        atomic_json(state_path, state)
        return result


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--snapshot", required=True)
    parser.add_argument("--state-dir", required=True)
    parser.add_argument("--url", required=True)
    parser.add_argument("--token-file", required=True)
    args = parser.parse_args(argv)
    try:
        result = publish_file(args.snapshot, args.state_dir, args.url, args.token_file)
    except (PublishError, OSError) as error:
        result = {"status": "failed", "errorCode": str(error) if isinstance(error, PublishError) else "publisher-local-error"}
    print(json.dumps(result, separators=(",", ":")))
    return 0 if result["status"] == "published" else 75


if __name__ == "__main__":
    raise SystemExit(main())
