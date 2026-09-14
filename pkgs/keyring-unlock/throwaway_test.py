import os, subprocess, sys
from jeepney import DBusAddress, new_method_call, MessageType
from jeepney.io.blocking import open_dbus_connection
os.environ.setdefault("DBUS_SESSION_BUS_ADDRESS", f"unix:path=/run/user/{os.getuid()}/bus")
conn = open_dbus_connection("SESSION"); BUS="org.freedesktop.secrets"; ROOT="/org/freedesktop/secrets"
def call(path, iface, m, sig=None, body=()):
    r = conn.send_and_get_reply(new_method_call(DBusAddress(path, bus_name=BUS, interface=iface), m, sig, body))
    if r.header.message_type == MessageType.error: raise RuntimeError(f"{m}: {r.body}")
    return r.body
def locked(p): return call(p, "org.freedesktop.DBus.Properties", "Get", "ss", ("org.freedesktop.Secret.Collection","Locked"))[0][1]
_, s = call(ROOT, "org.freedesktop.Secret.Service", "OpenSession", "sv", ("plain", ("s","")))
default_before = call(ROOT, "org.freedesktop.Secret.Service", "ReadAlias", "s", ("default",))[0]
coll = call(ROOT, "org.gnome.keyring.InternalUnsupportedGuiltRiddenInterface", "CreateWithMasterPassword",
            "a{sv}(oayays)", ({"org.freedesktop.Secret.Collection.Label": ("s", "overnight-keyring-unlock-test")}, (s, b"", b"correct-horse", "text/plain")))[0]
print("created", coll, "locked:", locked(coll))
call(ROOT, "org.freedesktop.Secret.Service", "Lock", "ao", ([coll],)); print("after Lock, locked:", locked(coll))
run = lambda pw: subprocess.run([sys.executable, sys.argv[1], coll], input=pw+"\n", capture_output=True, text=True)
w = run("wrong-password"); print("wrong pw -> rc", w.returncode, (w.stdout+w.stderr).strip(), "| locked:", locked(coll))
r = run("correct-horse"); print("right pw -> rc", r.returncode, (r.stdout+r.stderr).strip(), "| locked:", locked(coll))
a = run("x"); print("again     -> rc", a.returncode, (a.stdout+a.stderr).strip())
call(coll, "org.freedesktop.Secret.Collection", "Delete"); 
cols = call(ROOT, "org.freedesktop.DBus.Properties", "Get", "ss", ("org.freedesktop.Secret.Service","Collections"))[0][1]
print("deleted; remaining collections:", cols, "| default alias unchanged:", call(ROOT, "org.freedesktop.Secret.Service", "ReadAlias", "s", ("default",))[0] == default_before)
