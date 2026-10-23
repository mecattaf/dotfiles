// Nix owns releases and systemd owns the process. Omit the app's mutable
// updater, Herdr binary updater, public Portal and anonymous telemetry.
import { createServer } from "./index.ts";
import { readHerdrProfiles } from "./herdr-profiles.ts";

const server = createServer({ registerBridge: true, herdrProfiles: readHerdrProfiles });
let stopping = false;
const stop = () => {
  if (stopping) return;
  stopping = true;
  server.stop();
  // Allow terminal sidecars to release their attach slots without touching
  // the independently managed Herdr server or its panes.
  void Bun.sleep(2000).then(() => process.exit(0));
};
process.on("SIGTERM", stop);
process.on("SIGINT", stop);
console.log(`herdr-web-ui listening on http://${server.hostname}:${server.port}`);
