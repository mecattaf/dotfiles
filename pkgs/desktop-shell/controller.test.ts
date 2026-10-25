import { test, expect } from "bun:test";
import { EventEmitter } from "node:events";
import {
  DesktopController,
  parseSnapshot,
  socketPath,
  type Run,
} from "./controller";
import { parseDesktop, searchScore } from "./applications";
import { parseTheme } from "./theme";
const fixture = {
  clients: [
    {
      address: "0x123",
      title: "Editor, draft",
      class: "kitty",
      workspace: { id: 2, name: "work" },
      grouped: ["0x123", "0x456"],
      floating: false,
      fullscreen: 0,
    },
  ],
  workspaces: [{ id: 2, name: "work", windows: 1, monitor: "eDP-1" }],
  monitors: [
    {
      id: 0,
      name: "eDP-1",
      focused: true,
      activeWorkspace: { id: 2, name: "work" },
      scale: 1.25,
    },
  ],
  activewindow: { address: "0x123" },
};
function harness(execute?: Run) {
  const sockets: EventEmitter[] = [];
  const calls: string[][] = [];
  const controller = new DesktopController(
    () => {},
    execute ??
      (async (c, args) => {
        calls.push([c, ...args]);
        return args[0] === "dispatch"
          ? "ok"
          : JSON.stringify(fixture[args[1] as keyof typeof fixture]);
      }),
    ((_: string) => {
      const socket = new EventEmitter();
      Object.assign(socket, { destroy: () => socket.emit("close") });
      sockets.push(socket);
      return socket;
    }) as never,
  );
  controller.start("/private/test.sock");
  return { controller, sockets, calls };
}
test("snapshot preserves comma titles, group membership and focused workspace", () => {
  const state = parseSnapshot(
    Object.values(fixture).map((value) => JSON.stringify(value)),
  );
  expect(state.clients[0]?.title).toBe("Editor, draft");
  expect(state.clients[0]?.grouped).toHaveLength(2);
  expect(state.monitors[0]?.activeWorkspace.id).toBe(2);
});
test("invalid compositor snapshots and unsafe socket identifiers are rejected", () => {
  expect(() => parseSnapshot(["{}", "[]", "[]", "{}"])).toThrow();
  expect(() => socketPath("/run/user/1", "../../other")).toThrow();
});
test("window actions pass exact argv, reject bad IDs and retain targeted window", async () => {
  const h = harness();
  try {
    h.sockets[0]!.emit("connect");
    await h.controller.refresh();
    await h.controller.focus("0x123");
    await h.controller.move("0x123", 3);
    expect(h.calls).toContainEqual([
      "hyprctl",
      "dispatch",
      "focuswindow",
      "address:0x123",
    ]);
    expect(h.calls).toContainEqual([
      "hyprctl",
      "dispatch",
      "movetoworkspacesilent",
      "3,address:0x123",
    ]);
    await expect(h.controller.focus("0x123;exec nope")).rejects.toThrow();
    await expect(h.controller.workspace(-1)).rejects.toThrow();
  } finally {
    h.controller.stop();
  }
});
test("partial event lines wait for newline and burst refreshes coalesce", async () => {
  const h = harness();
  try {
    h.sockets[0]!.emit("connect");
    await h.controller.refresh();
    h.calls.length = 0;
    h.sockets[0]!.emit("data", Buffer.from("activewindow>>kitty,Ed"));
    await Bun.sleep(60);
    expect(h.calls).toHaveLength(0);
    h.sockets[0]!.emit("data", Buffer.from("itor\nwindowtitle>>0x123\n"));
    await Bun.sleep(70);
    expect(h.calls).toHaveLength(4);
  } finally {
    h.controller.stop();
  }
});
test("disconnect marks stale state unusable and reconnect refreshes", async () => {
  const h = harness();
  try {
    h.sockets[0]!.emit("connect");
    await h.controller.refresh();
    h.sockets[0]!.emit("close");
    expect(h.controller.state.connected).toBe(false);
    await expect(h.controller.workspace(1)).rejects.toThrow();
    await Bun.sleep(290);
    expect(h.sockets).toHaveLength(2);
    h.sockets[1]!.emit("connect");
    await h.controller.refresh();
    expect(h.controller.state.connected).toBe(true);
  } finally {
    h.controller.stop();
  }
});
test("an in-flight snapshot cannot resurrect a closed compositor connection", async () => {
  let release!: () => void;
  const wait = new Promise<void>((r) => (release = r));
  const h = harness(async (_, args) => {
    await wait;
    return JSON.stringify(fixture[args[1] as keyof typeof fixture]);
  });
  try {
    h.sockets[0]!.emit("connect");
    h.sockets[0]!.emit("close");
    release();
    await h.controller.refresh();
    expect(h.controller.state.connected).toBe(false);
  } finally {
    h.controller.stop();
  }
});
test("desktop-entry visibility follows overrides and the current desktop", () => {
  expect(parseDesktop("[Desktop Entry]\nHidden=true", "a", "a", [])).toBeNull();
  expect(
    parseDesktop(
      "[Desktop Entry]\nType=Application\nName=Other\nExec=other\nOnlyShowIn=GNOME;",
      "a",
      "a",
      ["Hyprland"],
    ),
  ).toBeUndefined();
  const app = parseDesktop(
    "[Desktop Entry]\nType=Application\nName=Mail\nExec=mail %U\n[Desktop Action New]\nName=Wrong",
    "a",
    "a",
    ["Hyprland"],
  );
  expect(app?.name).toBe("Mail");
});
test("search requires all terms and prefers a name prefix", () => {
  expect(searchScore("mail calendar", "Mail", "email")).toBe(-1);
  expect(searchScore("mail", "Mail")).toBeGreaterThan(
    searchScore("mail", "Gmail"),
  );
});
test("theme reader accepts only palette values and falls back for missing fields", () => {
  const theme = parseTheme(
    "background #123456\nforeground #abcdef\ncolor1 $(nope)",
  );
  expect(theme.background).toBe("#123456");
  expect(theme.foreground).toBe("#abcdef");
  expect(theme.error).toBe("#F47B85");
});
