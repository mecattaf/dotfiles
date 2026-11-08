import { describe, expect, test } from "bun:test";
import type { BrowserWindow } from "@domicile-desktop/sdk/desktop/browser";
import { WindowAction as A, closedIdsOf, workspaceHolding } from "@domicile-desktop/manganese-window-management/window-state";
import type { WindowState } from "@domicile-desktop/manganese-window-management/window-state";
import { agencyReducer, initialAgencyState } from "./policy";
import { AMBIENT_CHAT_APPS, AMBIENT_CHAT_APP_ID, ambientChatConfig, ambientTarget,
  createAmbientChat, observeAmbient, planAmbient, reduceAmbient } from "./AmbientChat";
import type { AmbientTransition } from "./AmbientChat";

const config = ambientChatConfig({ launcher: "agency-chat-ambient" })!;
const screens = [
  { name: "upper", box: { x: 0, y: 0, width: 1440, height: 900 } },
  { name: "lower", box: { x: 0, y: 900, width: 1440, height: 900 } },
];
const browser = (id: string, appId = AMBIENT_CHAT_APP_ID): BrowserWindow => ({
  id, appId, url: "http://127.0.0.1:17319/", title: "Agency", width: 0, height: 0,
  isApp: true, isCaptured: false, isPrivate: false, partition: "", popupWindow: undefined,
});
const settle = async () => { for (let n = 0; n < 8; n++) await Promise.resolve(); };

/** Dispatch deliberately queues, as React does, rather than updating read() synchronously. */
const fixture = () => {
  let state = agencyReducer(initialAgencyState(), A.ScreensDescribed(screens));
  let browsers: readonly BrowserWindow[] | undefined = [];
  let blocked = false;
  const queued: AmbientTransition[] = [];
  const launches: readonly string[][] = [];
  const mutableLaunches = launches as string[][];
  const completions: { resolve: () => void; reject: (error: unknown) => void }[] = [];
  const deadlines = new Set<() => void>();
  const errors: string[] = [];
  const control = createAmbientChat(config, {
    read: () => ({ state, browsers, blocked }),
    transition: (action) => queued.push(action),
    launch: (argv) => new Promise<void>((resolve, reject) => {
      mutableLaunches.push([...argv]); completions.push({ resolve, reject });
    }),
    report: (message) => errors.push(message),
    schedule: (callback) => { deadlines.add(callback); return () => { deadlines.delete(callback); }; },
  });
  const flush = () => {
    for (const action of queued.splice(0)) state = reduceAmbient(state, action, agencyReducer);
    control.reconcile();
  };
  const list = (now: readonly BrowserWindow[], background = AMBIENT_CHAT_APPS) => {
    browsers = now; state = agencyReducer(state, A.BrowserWindowsListed(now, background)); control.reconcile();
  };
  return { control, queued, launches, completions, deadlines, errors, flush, list,
    get state() { return state; },
    get browsers() { return browsers; },
    act: (action: A) => { state = agencyReducer(state, action); control.reconcile(); },
    unlist: () => { browsers = undefined; },
    block: (value: boolean) => { blocked = value; control.reconcile(); },
  };
};

describe("optional ambient viewer configuration", () => {
  test("is disabled by default and accepts only a fixed executable, not bootstrap arguments", () => {
    expect(ambientChatConfig(undefined)).toBeUndefined();
    for (const launcher of ["", "sh -c bad", "http://127.0.0.1:17319/?token=x", "helper?token=x", "helper\n--open"]) {
      expect(() => ambientChatConfig({ launcher })).toThrow();
    }
    expect(ambientChatConfig({ launcher: "/nix/store/fixture/bin/agency-chat-ambient" })?.width).toBe(640);
    for (const width of [NaN, Infinity, 0, 9000]) expect(() => ambientChatConfig({ launcher: "ambient", width })).toThrow();
  });
});

describe("actual public reducer retention", () => {
  test("exact background viewer shows floating, hides without closing, and preserves the full viewer and scratchpad", () => {
    const f = fixture();
    f.act(A.AppAppeared("terminal", "terminal"));
    f.act(A.WindowSentToScratchpad());
    f.list([browser("full", "agency-web"), browser("ambient")]);
    const before = f.state.windows;
    const full = workspaceHolding(f.state, "browser:full");
    const scratchpad = f.state.scratchpad;
    expect(observeAmbient(f.state, f.browsers)).toMatchObject({ kind: "window", shown: false });
    f.control.command(["ambient-chat", "show"]); f.flush();
    expect(f.state.workspaces[0]?.floats[0]).toMatchObject({ width: 640, height: 480, x: 400, y: 396 });
    expect(workspaceHolding(f.state, "browser:ambient")?.name).toBe("1");
    f.control.command(["ambient-chat", "hide"]); f.flush();
    expect(workspaceHolding(f.state, "browser:ambient")).toBeUndefined();
    expect(f.state.windows).toBe(before);
    expect(closedIdsOf(f.state, ["browser:ambient"])).toEqual([]);
    expect(workspaceHolding(f.state, "browser:full")?.tiling).toEqual(full?.tiling);
    expect(f.state.scratchpad).toBe(scratchpad);
    expect(f.launches).toEqual([]);
  });
  test("rapid show/hide/show before paint cannot retile the viewer or lose the final intent", () => {
    const f = fixture(); f.list([browser("a")]);
    f.control.command(["ambient-chat", "show"]);
    f.control.command(["ambient-chat", "toggle"]);
    f.control.command(["ambient-chat", "toggle"]);
    expect(f.queued.map(({ visible }) => visible)).toEqual([true, false, true]);
    f.flush();
    expect(f.state.workspaces[0]?.floats).toHaveLength(1);
    expect(f.state.workspaces[0]?.tiling.root).toBeUndefined();
    f.control.command(["ambient-chat", "toggle"]); f.flush();
    expect(workspaceHolding(f.state, "browser:a")).toBeUndefined();
  });
  test("repeated explicit show preserves an already resized float", () => {
    const f = fixture(); f.list([browser("a")]);
    f.control.command(["ambient-chat", "show"]); f.flush();
    f.act(A.WindowResized("browser:a", { width: 700, height: 500, x: 100, y: 80 }));
    f.control.command(["ambient-chat", "show"]); f.flush();
    expect(f.state.workspaces[0]?.floats[0]).toMatchObject({ width: 700, height: 500, x: 100, y: 80 });
  });
  test("summon moves only the ambient viewer to the current lower output", () => {
    const f = fixture(); f.list([browser("full", "agency-web"), browser("a")]);
    f.control.command(["ambient-chat", "show"]); f.flush();
    f.act(A.ScreenHovered("lower"));
    f.control.command(["ambient-chat", "show"]); f.flush();
    expect(workspaceHolding(f.state, "browser:a")?.name).toBe("10");
    expect(workspaceHolding(f.state, "browser:full")?.name).toBe("1");
    expect(f.state.focused).toBe("lower");
    expect(f.state.workspaces.find(({ name }) => name === "10")?.floats[0]).toMatchObject({ x: 400, y: 396 });
  });
  test("impossible native minimum fit is refused visibly without exposing or closing the page", () => {
    const f = fixture(); f.act(A.ScreensDescribed([{ name: "small", box: { width: 200, height: 160, x: 4000, y: 3000 } }]));
    f.list([browser("a")]); f.control.command(["ambient-chat", "show"]); f.flush();
    expect(workspaceHolding(f.state, "browser:a")).toBeUndefined();
    expect(f.state.windows).toHaveLength(1);
    expect(f.queued).toEqual([]);
    expect(f.errors.at(-1)).toContain("cannot contain the native floating minimum");
  });
  test("the planner reports and centres the actual public reducer minimum", () => {
    const f = fixture(); f.list([browser("a")]);
    const plan = planAmbient(f.state, { ambient: true, id: "browser:a", visible: true,
      target: ambientTarget(f.state)!, size: { width: 120, height: 120 } }, agencyReducer);
    expect(plan.geometry).toEqual({ width: 240, height: 120, x: 600, y: 756 });
    expect(plan.error).toBeUndefined();
  });
  test("atomic membership guard refuses a stale update after browser removal or normal-window adoption", () => {
    const f = fixture(); f.list([browser("a")]); f.control.command(["ambient-chat", "show"]);
    const update = f.queued[0]!;
    f.list([]); const removed = f.state;
    expect(reduceAmbient(removed, update, agencyReducer)).toBe(removed);
    f.flush(); f.control.command(["ambient-chat", "toggle"]);
    expect(f.launches).toHaveLength(1); // A closed viewer cannot leave a stale shown intent.
    f.control.dispose();
    const g = fixture(); g.list([browser("a")], []);
    expect(reduceAmbient(g.state, update, agencyReducer)).toBe(g.state);
  });
  test("an output/workspace navigation queued ahead of show makes that stale show a no-op", () => {
    const f = fixture(); f.list([browser("a")]); f.control.command(["ambient-chat", "show"]);
    f.act(A.ScreenHovered("lower")); f.flush();
    expect(workspaceHolding(f.state, "browser:a")).toBeUndefined();
  });
});

describe("launch and refresh races", () => {
  test("undefined browser list, duplicate IDs and missing membership do not allocate or mutate", () => {
    const f = fixture(); f.unlist(); f.control.command(["ambient-chat", "show"]);
    expect(f.launches).toEqual([]);
    f.list([browser("a"), browser("b")]); f.control.command(["ambient-chat", "show"]);
    expect(f.queued).toEqual([]); expect(f.errors.at(-1)).toContain("duplicate");
    const g = fixture(); g.list([browser("a")], []); g.control.command(["ambient-chat", "hide"]);
    expect(g.queued).toEqual([]); expect(g.errors.at(-1)).toContain("not retained");
  });
  test("SDK list ahead of reducer publication waits instead of taking over an ordinary window", () => {
    expect(observeAmbient(initialAgencyState(), [browser("a")])).toEqual({ kind: "unlisted" });
  });
  test("one bootstrap is coalesced, and hide during bootstrap retains the new page hidden", async () => {
    const f = fixture(); f.control.command(["ambient-chat", "show"]); f.control.command(["ambient-chat", "show"]);
    f.control.command(["ambient-chat", "toggle"]);
    expect(f.launches).toEqual([["agency-chat-ambient"]]);
    f.completions[0]!.resolve(); await settle();
    expect(f.deadlines.size).toBe(1); // Native ack is not browser-list evidence.
    f.list([browser("a")]); f.flush();
    expect(workspaceHolding(f.state, "browser:a")).toBeUndefined();
    expect(f.state.windows).toHaveLength(1); expect(f.deadlines.size).toBe(0);
  });
  test("late bootstrap after lock/modal or user navigation does not steal focus", async () => {
    for (const block of [true, false]) {
      const f = fixture(); f.control.command(["ambient-chat", "show"]);
      if (block) f.block(true); else f.act(A.ScreenHovered("lower"));
      f.list([browser("a")]); f.completions[0]!.resolve(); await settle(); f.flush();
      expect(workspaceHolding(f.state, "browser:a")).toBeUndefined();
      expect(f.queued).toEqual([]);
    }
  });
  test("disposed mount ignores completion without killing or closing the late guest", async () => {
    const f = fixture(); f.control.command(["ambient-chat", "show"]); f.control.dispose();
    f.list([browser("a")]); f.completions[0]!.resolve(); await settle(); f.flush();
    expect(f.state.windows).toHaveLength(1); expect(workspaceHolding(f.state, "browser:a")).toBeUndefined();
    expect(f.queued).toEqual([]); expect(f.deadlines.size).toBe(0);
  });
  test("launcher failure is bounded and never echoes captured credentials", async () => {
    const f = fixture(); f.control.command(["ambient-chat", "show"]);
    f.completions[0]!.reject(Error("secret-token-fixture must not be displayed")); await settle();
    expect(f.errors.at(-1)).toContain("launcher failed");
    expect(JSON.stringify(f.errors)).not.toContain("secret-token-fixture");
    expect(f.launches).toHaveLength(1); expect(f.deadlines.size).toBe(0);
  });
  test("a timed-out still-running helper is not duplicated, including after a window briefly arrived", async () => {
    const f = fixture(); f.control.command(["ambient-chat", "show"]);
    f.list([browser("a")]); f.flush(); f.list([]);
    for (const deadline of [...f.deadlines]) deadline();
    f.control.command(["ambient-chat", "show"]);
    expect(f.launches).toHaveLength(1);
    f.completions[0]!.resolve(); await settle();
    // A deliberate later command may retry after the owned call has ended.
    f.control.command(["ambient-chat", "show"]); expect(f.launches).toHaveLength(2);
    f.control.dispose();
  });
  test("new shell reconstructs exact identity and opens no duplicate on refresh", () => {
    const f = fixture(); f.list([browser("retained")]);
    expect(f.launches).toEqual([]); expect(f.queued).toEqual([]);
    expect(f.control.consumesFocusRequest("browser:retained")).toBe(true);
    expect(f.control.consumesFocusRequest("browser:full")).toBe(false);
    f.control.command(["ambient-chat", "show"]); f.flush();
    expect(workspaceHolding(f.state, "browser:retained")?.name).toBe("1");
    expect(f.launches).toEqual([]);
  });
  test("lock/modal commands and unrelated command namespaces never launch or change state", () => {
    const f = fixture(); f.block(true);
    expect(f.control.command(["chrome", "hide"])).toBe(false);
    expect(f.control.command(["ambient-chat", "show"])).toBe(true);
    expect(f.launches).toEqual([]); expect(f.queued).toEqual([]);
    f.block(false); f.control.command(["ambient-chat", "show", "unexpected"]);
    expect(f.launches).toEqual([]); expect(f.errors.at(-1)).toContain("usage");
  });
});
