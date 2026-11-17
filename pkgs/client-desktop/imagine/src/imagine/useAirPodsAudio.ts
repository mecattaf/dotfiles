import type { Domicile } from "@domicile-desktop/sdk/desktop/desktop";
import type { DbusSignal, Listened, Listening } from "@domicile-desktop/sdk/system";
import { Bus, ListenedKind } from "@domicile-desktop/sdk/system";
import { useEffect, useEffectEvent, useState } from "react";
import { connectedDevices, connectionDelta } from "./AirPodsPolicy";
import { runHelperRequest } from "./HelperRequest";

/** One signal subscription on Domicile's existing D-Bus connection. No timer,
 * subprocess watcher, radio scan, service or connection polling. */
export function useAirPodsAudio(domicile: Domicile,
  announce: (label: string, value: string, detail?: string) => void) {
  const [revision, setRevision] = useState(0);
  const notice = useEffectEvent(announce);
  useEffect(() => {
    let stopped = false;
    let subscription: Listening<Listened<DbusSignal>> | undefined;
    let previous: ReadonlySet<string> | undefined;
    const update = async () => {
      const result = await domicile.dbus.call({ bus: Bus.System, destination: "org.bluez",
        interface: "org.freedesktop.DBus.ObjectManager", member: "GetManagedObjects", path: "/" });
      const body = result.match({ Ok: reply => reply.body, Err: () => undefined });
      if (stopped || body === undefined) return;
      const delta = connectionDelta(previous, connectedDevices(body));
      previous = delta.current;
      if (!delta.initial && delta.connected.length === 0 && delta.disconnected.length === 0) return;
      const reply = await runHelperRequest(domicile, ["imagine-audio-control"], { action: "audio-auto",
        initial: delta.initial, connected: delta.connected, disconnected: delta.disconnected }, 20000);
      if (stopped) return;
      if (!reply.ok) { console.error("Imagine automatic audio route", reply.message); return; }
      if (reply.changed) setRevision(value => value + 1);
      if (reply.notice) notice("AirPods", "Connected", reply.message);
    };
    const refresh = () => update().catch((error: unknown) => console.error("Imagine automatic audio route", error));
    const follow = async () => {
      const result = await domicile.dbus.match({ bus: Bus.System, sender: "org.bluez" });
      subscription = result.match({ Ok: value => value, Err: () => undefined });
      if (!subscription) throw Error("Unable to watch Bluetooth connections");
      if (stopped) { subscription.stop(); return; }
      const reader = subscription.items.getReader();
      try {
        await refresh();
        for (let next = await reader.read(); !next.done; next = await reader.read()) {
          const event = next.value;
          if (event.kind === ListenedKind.Missed) { await refresh(); continue; }
          const signal = event.item;
          if (signal.member === "InterfacesAdded" || signal.member === "InterfacesRemoved") await refresh();
          else if (signal.member === "PropertiesChanged" && signal.body[0] === "org.bluez.Device1") {
            const changed = signal.body[1];
            if (changed && typeof changed === "object" && ("Connected" in changed || "Paired" in changed)) await refresh();
          }
        }
        const ended = await subscription.ended;
        ended.match({ Ok: () => undefined, Err: error => console.error("Imagine Bluetooth subscription", error) });
      } finally { reader.releaseLock(); }
    };
    void follow().catch((error: unknown) => console.error("Imagine automatic audio route", error));
    return () => { stopped = true; subscription?.stop(); };
  }, [domicile]);
  return revision;
}
