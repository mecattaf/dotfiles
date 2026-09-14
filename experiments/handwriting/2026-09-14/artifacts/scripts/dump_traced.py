"""Run the repo's `huion_notes dump` unchanged, but log every frame sent/received.

Usage: PYTHONPATH=<repo> python3 dump_traced.py dump --mac ... --keep -o ...
"""
import logging
import sys
import time

from huion_notes import transport, cli

T0 = time.monotonic()
_send = transport.BleTransport.send
_on_value = transport.BleTransport._on_value


def _ts() -> str:
    return f"{time.monotonic() - T0:7.2f}s"


async def send(self, frame: bytes) -> None:
    print(f"{_ts()} >> {bytes(frame).hex(' ')}", file=sys.stderr, flush=True)
    return await _send(self, frame)


def on_value(self, data: bytes) -> None:
    b = bytes(data)
    print(f"{_ts()} << {b[:24].hex(' ')}{' …' if len(b) > 24 else ''} ({len(b)}B)", file=sys.stderr, flush=True)
    return _on_value(self, data)


transport.BleTransport.send = send
transport.BleTransport._on_value = on_value

if __name__ == "__main__":
    logging.basicConfig(level=logging.DEBUG, format="%(levelname)s %(name)s: %(message)s")
    sys.exit(cli.main(sys.argv[1:]))
