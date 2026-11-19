import { expect, test } from "bun:test";
import { connectedDevices, connectionDelta } from "./AirPodsPolicy";
const device = (connected = true) => ({ address: "aa:bb:cc:11:22:33", connected, paired: true });
test("a fresh connection enables one automatic route", () => {
  const first = connectionDelta(new Set(), [device()]);
  expect(first.connected).toEqual(["AA:BB:CC:11:22:33"]);
  expect(connectionDelta(first.current, [device()]).connected).toEqual([]);
});
test("unrelated updates preserve a manual mode until reconnect", () => {
  const first = connectionDelta(undefined, [device()]);
  const unchanged = connectionDelta(first.current, [{ ...device(), battery: 75 }]);
  expect(unchanged.initial).toBe(false);
  expect(unchanged.connected).toEqual([]);
  expect(unchanged.disconnected).toEqual([]);
});
test("disconnect and reconnect are distinct edges", () => {
  const first = connectionDelta(undefined, [device()]);
  const gone = connectionDelta(first.current, [device(false)]);
  expect(gone.disconnected).toEqual(["AA:BB:CC:11:22:33"]);
  expect(connectionDelta(gone.current, [device()]).connected).toEqual(["AA:BB:CC:11:22:33"]);
});

test("BlueZ device variants preserve connection and pairing facts", () => {
  expect(connectedDevices([{ "/device": { "org.bluez.Device1": {
    Address: { value: "AA:BB:CC:DD:EE:FF" }, Connected: { value: true }, Paired: { value: true },
  } }, "/adapter": { "org.bluez.Adapter1": {} } }])).toEqual([
    { address: "AA:BB:CC:DD:EE:FF", connected: true, paired: true },
  ]);
  expect(connectedDevices([])).toEqual([]);
});
