"""dictate-hold: the CLIENT half of dictation (#376, route b').

Spawned by niri's Mod+Space bind (binds.kdl, repeat=false), once per press.
It is a per-press user process that lives exactly as long as the key is held
plus the transcription, not a daemon, runner or unit. That is what keeps
it inside the thin-client rule, whose one standing exception is the Huion
sync (DECISIONS 2026-09-13).

  1. The focused niri window must be a herdr projector (app-id
     herdr-projector). Anything else: exit, nothing recorded. Delivery into
     non-herdr windows is #376's "later".
  2. Title that kitty window "REC" while held (the issue's spinner) and
     "transcribing" after.
  3. pw-record (the client's PipeWire DEFAULT source, i.e. whatever the
     Shift+F9 Audio Route picker selected) | ssh coordinator voxtype-relay.
     One ssh session per press, no ControlMaster (home/ssh.nix option (B)).
  4. Block on evdev until Space or Meta is released. niri binds have no
     on-release trigger, which is why this reads /dev/input directly (tom is
     in the `input` group). Esc while held, or `dictate-hold --cancel`
     (Mod+Shift+Space), cancels.
  5. Stop pw-record. EOF makes the relay stop the coordinator daemon and
     print the transcript. Type it into THAT projector with
     `kitten @ send-text`: literal text, never a bracketed paste (an empty
     one triggers herdr's clipboard-image bridge). --match recent:0 is the
     projector's own window, so the text lands in whichever herdr pane that
     projector has focused, and other projectors are untouched.

No model and no voxtype package live on the client: the flake asserts it.

Test hooks: DICTATE_HOLD_SECS=N holds for N seconds instead of reading evdev;
DICTATE_REMOTE / DICTATE_RELAY override the ssh target and remote command.
"""

import json
import os
import select
import signal
import subprocess
import sys
import time

import evdev
from evdev import ecodes

CLASS = "herdr-projector"
REMOTE = os.environ.get("DICTATE_REMOTE", "coordinator")
RELAY = os.environ.get("DICTATE_RELAY", "voxtype-relay")
RUNTIME = os.environ.get("XDG_RUNTIME_DIR", "/run/user/%d" % os.getuid())
PIDFILE = os.path.join(RUNTIME, "dictate-hold.pid")
MAX_HOLD_S = 300
RELAY_TIMEOUT_S = 45
# A tap is not dictation: parakeet turns a fraction of a second of silence
# into a word ("Yeah.", measured), so a hold shorter than this is a cancel.
MIN_HOLD_S = 0.3
RELEASE_KEYS = {
    ecodes.KEY_SPACE,
    ecodes.KEY_LEFTMETA,
    ecodes.KEY_RIGHTMETA,
}

cancelled = False


def log(msg):
    print("dictate-hold: " + msg, file=sys.stderr, flush=True)


def notify(msg):
    log(msg)
    try:
        subprocess.run(
            ["notify-send", "Dictation", msg],
            check=False,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            timeout=3,
        )
    except (OSError, subprocess.TimeoutExpired):
        pass


def kitten(pid, *args, check=False):
    return subprocess.run(
        ["kitten", "@", "--to", "unix:@kitty-%d" % pid, *args],
        check=check,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        timeout=5,
    )


def set_title(pid, title):
    # With no title, kitty reverts to the one the program set.
    args = ["set-window-title", "--match", "recent:0"]
    if title:
        args.append(title)
    try:
        kitten(pid, *args)
    except (OSError, subprocess.TimeoutExpired):
        pass


def focused_projector():
    try:
        out = subprocess.run(
            ["niri", "msg", "-j", "focused-window"],
            check=True,
            capture_output=True,
            text=True,
            timeout=5,
        ).stdout
        win = json.loads(out or "null")
    except (OSError, subprocess.SubprocessError, ValueError):
        return None
    if not win or win.get("app_id") != CLASS or not win.get("pid"):
        return None
    return int(win["pid"])


def keyboards():
    devs = []
    for path in evdev.list_devices():
        try:
            dev = evdev.InputDevice(path)
        except OSError:
            continue
        keys = dev.capabilities().get(ecodes.EV_KEY, [])
        if ecodes.KEY_SPACE in keys:
            devs.append(dev)
        else:
            dev.close()
    return devs


def wait_release():
    """Return True on release, False on cancel (Esc / SIGUSR1 / timeout)."""
    hold = os.environ.get("DICTATE_HOLD_SECS")
    if hold:
        end = time.monotonic() + float(hold)
        while time.monotonic() < end and not cancelled:
            time.sleep(0.05)
        return not cancelled
    devs = keyboards()
    if not devs:
        log("no readable keyboard under /dev/input (group input?)")
        return False
    try:
        # Already released before we got here (a tap): stop at once.
        if not any(set(d.active_keys()) & RELEASE_KEYS for d in devs):
            return True
        end = time.monotonic() + MAX_HOLD_S
        by_fd = {d.fd: d for d in devs}
        while not cancelled:
            left = end - time.monotonic()
            if left <= 0:
                log("held for %ds; cancelling" % MAX_HOLD_S)
                return False
            try:
                ready, _, _ = select.select(list(by_fd), [], [], min(left, 0.5))
            except InterruptedError:
                continue
            for fd in ready:
                try:
                    events = list(by_fd[fd].read())
                except OSError:
                    # unplugged mid-hold (the Duo keyboard detaches)
                    del by_fd[fd]
                    continue
                for ev in events:
                    if ev.type != ecodes.EV_KEY:
                        continue
                    if ev.code == ecodes.KEY_ESC and ev.value == 1:
                        return False
                    if ev.code in RELEASE_KEYS and ev.value == 0:
                        return True
            if not by_fd:
                return True
        return False
    finally:
        for d in devs:
            d.close()


def on_cancel(signum, frame):
    global cancelled
    cancelled = True


def cancel_running():
    try:
        with open(PIDFILE) as f:
            pid = int(f.read().strip())
        os.kill(pid, signal.SIGUSR1)
    except (OSError, ValueError):
        pass
    return 0


def main():
    if sys.argv[1:] == ["--cancel"]:
        return cancel_running()
    if sys.argv[1:]:
        log("usage: dictate-hold [--cancel]")
        return 2

    pid = focused_projector()
    if pid is None:
        log("focused window is not a herdr projector; nothing to dictate into")
        return 0

    signal.signal(signal.SIGUSR1, on_cancel)
    signal.signal(signal.SIGTERM, on_cancel)
    with open(PIDFILE, "w") as f:
        f.write(str(os.getpid()))

    rec = relay = None
    try:
        set_title(pid, "● REC")
        rec = subprocess.Popen(
            ["pw-record", "--raw", "--rate", "16000", "--channels", "1",
             "--format", "s16", "-"],
            stdout=subprocess.PIPE,
        )
        relay = subprocess.Popen(
            ["ssh", "-o", "BatchMode=yes", REMOTE, RELAY],
            stdin=rec.stdout,
            stdout=subprocess.PIPE,
        )
        rec.stdout.close()

        started = time.monotonic()
        released = wait_release()
        if released and time.monotonic() - started < MIN_HOLD_S:
            released = False
        rec.send_signal(signal.SIGINT)
        try:
            rec.wait(timeout=3)
        except subprocess.TimeoutExpired:
            rec.kill()

        if not released:
            # Discard on the daemon FIRST: a bare hang-up only reaches the
            # relay as EOF on stdin (no pty, no SIGHUP), which is exactly its
            # "stop and transcribe" signal (measured 2026-09-13).
            try:
                subprocess.run(
                    ["ssh", "-o", "BatchMode=yes", REMOTE, RELAY + " --cancel"],
                    check=False,
                    stdout=subprocess.DEVNULL,
                    timeout=10,
                )
            except (OSError, subprocess.TimeoutExpired):
                pass
            relay.terminate()
            relay.wait(timeout=5)
            log("cancelled")
            return 0

        set_title(pid, "… transcribing")
        try:
            out, _ = relay.communicate(timeout=RELAY_TIMEOUT_S)
        except subprocess.TimeoutExpired:
            relay.kill()
            notify("no transcript from %s in %ds" % (REMOTE, RELAY_TIMEOUT_S))
            return 1
        if relay.returncode != 0:
            notify("%s %s failed (exit %d)" % (REMOTE, RELAY, relay.returncode))
            return 1
        text = out.decode("utf-8", "replace")
        if not text.strip():
            log("empty transcript")
            return 0
        try:
            kitten(pid, "send-text", "--match", "recent:0", "--", text,
                   check=True)
        except (OSError, subprocess.SubprocessError):
            notify("the projector window closed before the text arrived")
            return 1
        return 0
    finally:
        set_title(pid, "")
        for p in (rec, relay):
            if p is not None and p.poll() is None:
                p.kill()
        try:
            os.unlink(PIDFILE)
        except OSError:
            pass


if __name__ == "__main__":
    sys.exit(main())
