export {};
const modes = ["bar", "launcher", "controls", "windows", "notifications", "toasts"];
const arg = process.argv[2] ?? "bar";
if (arg === "--help") {
  console.log(
    "Usage: desktop-shell [bar|launcher|controls|windows|notifications|toasts|daemon]\nA native Solid/GPUIX shell for Hyprland. Repeating a popup command closes it.\nnotifications-clear dismisses all; notifications-dnd on|off controls quiet mode.\nEscape closes popups; launcher: Up/Down then Enter.\n--check-native loads the native addon without opening a window.\n--version prints the application version.",
  );
  process.exit(0);
}
if (arg === "--version") {
  console.log("desktop-shell 0.1.0 (GPUIX 0.10.0, Solid 1)");
  process.exit(0);
}
if (arg === "--check-native") {
  const native = await import("@gpuix/native");
  if (typeof native.GpuixRenderer !== "function")
    throw new Error("Missing native GPUIX renderer");
  console.log(
    "GPUIX native addon loaded; layer-shell is exposed by the pinned 0.10.0 API.",
  );
  process.exit(0);
}
if (arg === "daemon") {
  const { serveNotifications } = await import("./notifications-daemon");
  await serveNotifications();
} else if (arg === "notifications-clear" || arg === "notifications-dnd" || arg === "notifications-dismiss") {
  const { notificationCommand } = await import("./notifications-client");
  if(arg === "notifications-clear") await notificationCommand({type:'clear'});
  else if(arg === "notifications-dismiss") await notificationCommand({type:'dismiss-latest'});
  else { const setting=process.argv[3];if(setting!=='on'&&setting!=='off')throw new Error('Use notifications-dnd on|off');await notificationCommand({type:'dnd',enabled:setting==='on'}); }
  process.exit(0);
} else if (!modes.includes(arg)) {
  console.error(`Unknown mode: ${arg}`);
  process.exit(2);
}
if(arg !== "daemon") {
const { singleton } = await import("./singleton");
let closing = false;
let release: (() => Promise<void>) | undefined;
async function close() {
  if (closing) return;
  closing = true;
  await release?.();
  process.exit(0);
}
release = await singleton(arg, () => void close());
process.once("SIGINT", () => void close());
process.once("SIGTERM", () => void close());
try {
  const { start } = await import("./ui");
  const provider = process.argv[3] === '--provider' ? process.argv[4] : 'all';
  if(!provider || !['all','windows','applications','commands','clipboard','files'].includes(provider))throw new Error('Unknown launcher provider');
  await start(arg as "bar" | "launcher" | "controls" | "windows" | "notifications" | "toasts", close, provider);
} catch (error) {
  console.error(error);
  await release();
  process.exit(1);
}
}
