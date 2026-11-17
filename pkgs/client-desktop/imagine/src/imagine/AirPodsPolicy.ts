/** Connection edges only: profile/volume/battery updates never reselect audio. */
export function connectionDelta(previous: ReadonlySet<string> | undefined,
  devices: readonly { address: string; connected: boolean; paired: boolean }[]) {
  const current = new Set(devices.filter(device => device.connected && device.paired)
    .map(device => device.address.toUpperCase()));
  return { current, initial: previous === undefined,
    connected: [...current].filter(address => !previous?.has(address)),
    disconnected: [...(previous ?? [])].filter(address => !current.has(address)) };
}

/** BlueZ variants from the SDK's existing system-bus transport. */
export function connectedDevices(body: readonly unknown[]) {
  const objects = body[0];
  if (!objects || typeof objects !== "object") return [];
  return Object.values(objects).flatMap(interfaces => {
    const device = interfaces?.["org.bluez.Device1"];
    const address = device?.Address?.value;
    if (typeof address !== "string") return [];
    return [{ address, paired: device.Paired?.value === true, connected: device.Connected?.value === true }];
  });
}
