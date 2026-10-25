import { execFile } from "node:child_process";
import { createConnection, type Socket } from "node:net";
import { join } from "node:path";

export interface Client {
  address: string;
  title: string;
  class: string;
  workspace: { id: number; name: string };
  grouped: string[];
  floating: boolean;
  fullscreen: number;
  focusHistoryID?: number;
}
export interface Workspace {
  id: number;
  name: string;
  windows: number;
  monitor: string;
}
export interface Monitor {
  id: number;
  name: string;
  focused: boolean;
  activeWorkspace: { id: number; name: string };
  scale: number;
}
export interface DesktopState {
  connected: boolean;
  error: string;
  clients: Client[];
  workspaces: Workspace[];
  monitors: Monitor[];
  activeAddress: string;
}
export const emptyState = (): DesktopState => ({
  connected: false,
  error: "Connecting to Hyprland…",
  clients: [],
  workspaces: [],
  monitors: [],
  activeAddress: "",
});
export type Run = (command: string, args: string[]) => Promise<string>;
export const run: Run = (command, args) =>
  new Promise((resolve, reject) => {
    execFile(
      command,
      args,
      { timeout: 5000, maxBuffer: 4 * 1024 * 1024 },
      (error, stdout, stderr) =>
        error
          ? reject(new Error(stderr.trim() || error.message))
          : resolve(stdout),
    );
  });
export function socketPath(
  runtime: string | undefined,
  signature: string | undefined,
): string {
  if (!runtime || !signature || !/^[a-zA-Z0-9_.-]+$/.test(signature))
    throw new Error("Start desktop-shell inside a Hyprland session.");
  return join(runtime, "hypr", signature, ".socket2.sock");
}
export function parseSnapshot(
  parts: string[],
): Omit<DesktopState, "connected" | "error"> {
  const [clients, workspaces, monitors, active] = parts.map((x) =>
    JSON.parse(x),
  );
  if (
    !Array.isArray(clients) ||
    !Array.isArray(workspaces) ||
    !Array.isArray(monitors)
  )
    throw new Error("Invalid Hyprland snapshot");
  for (const c of clients)
    if (
      typeof c.address !== "string" ||
      typeof c.title !== "string" ||
      typeof c.class !== "string" ||
      typeof c.workspace?.id !== "number"
    )
      throw new Error("Invalid Hyprland client");
  return {
    clients: clients.map((c) => ({
      ...c,
      grouped: Array.isArray(c.grouped) ? c.grouped : [],
    })),
    workspaces,
    monitors,
    activeAddress: typeof active?.address === "string" ? active.address : "",
  };
}
export class DesktopController {
  state = emptyState();
  private socket?: Socket;
  private stopped = true;
  private retry?: ReturnType<typeof setTimeout>;
  private debounce?: ReturnType<typeof setTimeout>;
  private delay = 250;
  private running?: Promise<void>;
  private dirty = false;
  private buffer = "";
  private epoch = 0;
  private socketReady = false;
  private refreshRetry?: ReturnType<typeof setTimeout>;
  constructor(
    private changed: (state: DesktopState) => void,
    private execute: Run = run,
    private connect = createConnection,
  ) {}
  private publish(patch: Partial<DesktopState>) {
    this.state = { ...this.state, ...patch };
    this.changed(this.state);
  }
  start(
    path = socketPath(
      process.env.XDG_RUNTIME_DIR,
      process.env.HYPRLAND_INSTANCE_SIGNATURE,
    ),
  ) {
    this.stopped = false;
    this.attach(path);
  }
  stop() {
    this.stopped = true;
    this.epoch++;
    clearTimeout(this.retry);
    clearTimeout(this.debounce);
    clearTimeout(this.refreshRetry);
    this.socket?.destroy();
  }
  private attach(path: string) {
    if (this.stopped) return;
    this.buffer = "";
    this.epoch++;
    const socket = this.connect(path);
    this.socket = socket;
    socket.on("connect", () => {
      this.socketReady = true;
      this.delay = 250;
      void this.refresh();
    });
    socket.on("data", (data: Buffer) => {
      this.buffer += data.toString();
      if (this.buffer.length > 1024 * 1024) {
        socket.destroy(new Error("Hyprland event buffer exceeded limit"));
        return;
      }
      const lines = this.buffer.split("\n");
      this.buffer = lines.pop()!;
      if (
        lines.some((line) =>
          /^(workspace|focusedmon|activewindow|openwindow|closewindow|movewindow|windowtitle|monitor|createworkspace|destroyworkspace|changegroup|togglegroup|fullscreen|changefloatingmode)/.test(
            line,
          ),
        )
      )
        this.schedule();
    });
    socket.on("error", (error: Error) =>
      this.publish({ connected: false, error: error.message }),
    );
    socket.on("close", () => {
      this.epoch++;
      this.socketReady = false;
      clearTimeout(this.refreshRetry);
      if (this.stopped) return;
      this.publish({
        connected: false,
        error: "Hyprland disconnected. Reconnecting…",
      });
      this.retry = setTimeout(() => this.attach(path), this.delay);
      this.delay = Math.min(this.delay * 2, 10000);
    });
  }
  private schedule() {
    clearTimeout(this.debounce);
    this.debounce = setTimeout(() => void this.refresh(), 40);
  }
  refresh(): Promise<void> {
    if (this.running) {
      this.dirty = true;
      return this.running;
    }
    this.running = (async () => {
      do {
        this.dirty = false;
        const epoch = this.epoch;
        try {
          const parts = await Promise.all(
            ["clients", "workspaces", "monitors", "activewindow"].map((q) =>
              this.execute("hyprctl", ["-j", q]),
            ),
          );
          if (!this.stopped && this.socketReady && epoch === this.epoch)
            this.publish({
              ...parseSnapshot(parts),
              connected: true,
              error: "",
            });
        } catch (error) {
          if (!this.stopped && epoch === this.epoch) {
            this.publish({ connected: false, error: String(error) });
            clearTimeout(this.refreshRetry);
            this.refreshRetry = setTimeout(() => void this.refresh(), 2000);
          }
        }
      } while (this.dirty && !this.stopped);
    })().finally(() => {
      this.running = undefined;
    });
    return this.running;
  }
  async dispatch(action: string, ...args: string[]) {
    if (!this.state.connected) throw new Error("Hyprland is disconnected.");
    const output = await this.execute("hyprctl", ["dispatch", action, ...args]);
    if (output.trim() !== "ok")
      throw new Error(output.trim() || "Hyprland returned no acknowledgement");
    await this.refresh();
  }
  focus(address: string) {
    if (!/^0x[0-9a-f]+$/i.test(address))
      return Promise.reject(new Error("Invalid window address"));
    return this.dispatch("focuswindow", `address:${address}`);
  }
  workspace(id: number) {
    if (!Number.isSafeInteger(id) || id < 1)
      return Promise.reject(new Error("Invalid workspace"));
    return this.dispatch("workspace", String(id));
  }
  async move(address: string, id: number) {
    if (!/^0x[0-9a-f]+$/i.test(address) || !Number.isSafeInteger(id) || id < 1)
      throw new Error("Invalid window or workspace");
    return this.dispatch("movetoworkspacesilent", `${id},address:${address}`);
  }
}
