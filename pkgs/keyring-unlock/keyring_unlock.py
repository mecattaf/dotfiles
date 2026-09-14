"""keyring-unlock [COLLECTION] -- unlock a gnome-keyring collection without a GUI prompt.

The coordinator boots headless: no login unlocks the keyring. Run this over
ssh from the client (`ssh -t coordinator keyring-unlock`) and type the keyring
password once. The password is read from the terminal (or stdin when not a
tty), never from argv, and handed to gnome-keyring's own
UnlockWithMasterPassword over the session bus. Exit 0 only when the collection
reports Locked=false afterwards; 1 on a wrong password; 2 on any other error.
"""
import getpass, os, sys
from jeepney import DBusAddress, new_method_call, MessageType
from jeepney.io.blocking import open_dbus_connection

BUS = "org.freedesktop.secrets"
ROOT = "/org/freedesktop/secrets"


def main() -> int:
    os.environ.setdefault("DBUS_SESSION_BUS_ADDRESS", f"unix:path=/run/user/{os.getuid()}/bus")
    try:
        conn = open_dbus_connection("SESSION")
    except Exception as exc:
        print(f"keyring-unlock: no session bus: {exc}", file=sys.stderr); return 2

    def call(path, iface, method, sig=None, body=()):
        reply = conn.send_and_get_reply(new_method_call(DBusAddress(path, bus_name=BUS, interface=iface), method, sig, body))
        if reply.header.message_type == MessageType.error:
            raise RuntimeError(f"{method}: {reply.header.fields.get(4, '')} {reply.body}")
        return reply.body

    def locked(path):
        return call(path, "org.freedesktop.DBus.Properties", "Get", "ss", ("org.freedesktop.Secret.Collection", "Locked"))[0][1]

    try:
        _, session = call(ROOT, "org.freedesktop.Secret.Service", "OpenSession", "sv", ("plain", ("s", "")))
        collection = sys.argv[1] if len(sys.argv) > 1 else call(ROOT, "org.freedesktop.Secret.Service", "ReadAlias", "s", ("default",))[0]
        if collection == "/":
            print("keyring-unlock: no default keyring", file=sys.stderr); return 2
        if not locked(collection):
            print(f"keyring-unlock: {collection} is already unlocked"); return 0
        password = getpass.getpass("keyring password: ") if sys.stdin.isatty() else sys.stdin.readline().rstrip("\n")
        try:
            call(ROOT, "org.gnome.keyring.InternalUnsupportedGuiltRiddenInterface", "UnlockWithMasterPassword",
                 "o(oayays)", (collection, (session, b"", password.encode(), "text/plain")))
        except RuntimeError:
            if locked(collection):
                print(f"keyring-unlock: wrong password, {collection} is still locked", file=sys.stderr); return 1
            raise
        if locked(collection):
            print(f"keyring-unlock: wrong password, {collection} is still locked", file=sys.stderr); return 1
        print(f"keyring-unlock: {collection} unlocked"); return 0
    except Exception as exc:
        print(f"keyring-unlock: {exc}", file=sys.stderr); return 2


if __name__ == "__main__":
    sys.exit(main())
