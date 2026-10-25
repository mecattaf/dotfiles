import { createConnection, createServer } from "node:net";
import { mkdir, unlink, chmod, stat } from "node:fs/promises";
import { join } from "node:path";
export async function singleton(
  mode: string,
  close: () => void,
): Promise<() => Promise<void>> {
  const runtime = process.env.XDG_RUNTIME_DIR,
    signature = process.env.HYPRLAND_INSTANCE_SIGNATURE;
  if (!runtime || !signature || !/^[a-zA-Z0-9_.-]+$/.test(signature))
    throw new Error("A Hyprland session and XDG_RUNTIME_DIR are required.");
  const dir = join(runtime, "desktop-shell");
  await mkdir(dir, { recursive: true, mode: 0o700 });
  const path = join(dir, `${signature.slice(-32)}-${mode}.sock`);
  const contact = () =>
    new Promise<boolean>((resolve) => {
      const client = createConnection(path);
      client.setTimeout(1000);
      client.once("connect", () => {
        client.end(mode === "bar" || mode === "toasts" ? "present" : "close");
        resolve(true);
      });
      client.once("error", () => resolve(false));
      client.once("timeout", () => {
        client.destroy();
        resolve(false);
      });
    });
  const server = createServer((client) => {
    client.setTimeout(1000, () => client.destroy());
    client.once("data", (data) => {
      if (data.toString() === "close") close();
      client.end();
    });
  });
  const listen = () =>
    new Promise<void>((resolve, reject) => {
      const failed = (error: Error) => reject(error);
      server.once("error", failed);
      server.listen(path, () => {
        server.off("error", failed);
        resolve();
      });
    });
  try {
    await listen();
  } catch (error) {
    if ((error as NodeJS.ErrnoException).code !== "EADDRINUSE") throw error;
    if (await contact()) process.exit(0);
    const stale = await stat(path).catch(() => undefined);
    // A freshly-bound peer may still be starting. Never unlink that endpoint.
    if (stale && Date.now() - stale.mtimeMs < 2000) {
      await new Promise((resolve) => setTimeout(resolve, 100));
      if (await contact()) process.exit(0);
      throw new Error("Desktop shell is still starting. Try again shortly.");
    }
    // Only our own stale per-instance endpoint, never compositor/user sockets.
    await unlink(path).catch((error) => {
      if (error.code !== "ENOENT") throw error;
    });
    try {
      await listen();
    } catch (retryError) {
      if (await contact()) process.exit(0);
      throw retryError;
    }
  }
  await chmod(path, 0o600);
  return async () => {
    server.close();
    await unlink(path).catch(() => {});
  };
}
