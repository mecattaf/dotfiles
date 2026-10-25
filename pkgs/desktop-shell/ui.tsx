import { createSignal, createMemo, For, Show, type JSX } from "solid-js";
import {
  render,
  createRenderer,
  type NativeRenderer,
  type EventPayload,
  type StyleDesc,
} from "@gpuix/solid";
import { spawn } from "node:child_process";
import { readFile, readdir } from "node:fs/promises";
import { DesktopController, emptyState, run, type Client } from "./controller";
import { applications, searchScore, type Application } from "./applications";
import { fallback, followTheme, fonts } from "./theme";
import {
  providerItems,
  listThemes,
  clipboardItems,
  fileItems,
  activateProvider,
  type ProviderItem,
} from "./providers";
import {
  followNotifications,
  notificationCommand,
  type NotificationSnapshot,
  type ShellNotification,
} from "./notifications-client";

export async function start(
  mode:
    | "bar"
    | "launcher"
    | "controls"
    | "windows"
    | "notifications"
    | "toasts",
  close: () => Promise<void>,
  initialProvider = "all",
) {
  const [theme, setTheme] = createSignal(fallback),
    [state, setState] = createSignal(emptyState()),
    [error, setError] = createSignal("");
  const [provider, setProvider] = createSignal(initialProvider);
  const [query, setQuery] = createSignal(""),
    [selected, setSelected] = createSignal(0),
    [apps, setApps] = createSignal<Application[]>([]);
  const [clock, setClock] = createSignal(new Date()),
    [volume, setVolume] = createSignal(""),
    [battery, setBattery] = createSignal(""),
    [busy, setBusy] = createSignal(false);
  const [animations, setAnimations] = createSignal<boolean | null>(null),
    [blur, setBlur] = createSignal<boolean | null>(null);
  const notificationsMode = mode === "notifications" || mode === "toasts";
  const [notifications, setNotifications] = createSignal<NotificationSnapshot>({
    connected: false,
    error: "Connecting to notifications…",
    dnd: false,
    items: [],
    history: [],
  });
  let toastCount = 0;
  let firstSnapshot: (() => void) | undefined;
  const ready =
    mode === "toasts"
      ? new Promise<void>((resolve) => {
          firstSnapshot = resolve;
        })
      : Promise.resolve();
  if (mode === "bar" || notificationsMode)
    followNotifications((snapshot) => {
      setNotifications(snapshot);
      if (snapshot.connected) firstSnapshot?.();
      if (mode === "toasts" && !snapshot.connected && toastCount > 0)
        void close();
      if (
        mode === "toasts" &&
        snapshot.connected &&
        toastCount > 0 &&
        Math.min(4, snapshot.items.length) !== toastCount
      )
        void close();
      if (
        mode === "toasts" &&
        snapshot.connected &&
        (snapshot.items.length === 0 || snapshot.dnd)
      )
        void close();
    });
  const [themeNames, setThemeNames] = createSignal<string[]>([]);
  const [extraItems, setExtraItems] = createSignal<ProviderItem[]>([]);
  const [providerLoading, setProviderLoading] = createSignal(false);
  const [providerError, setProviderError] = createSignal("");
  let providerRevision = 0,
    providerTimer: ReturnType<typeof setTimeout> | undefined;
  function refreshProvider() {
    const revision = ++providerRevision,
      kind = provider(),
      term = query();
    clearTimeout(providerTimer);
    setExtraItems([]);
    setProviderError("");
    if (
      (kind !== "clipboard" && kind !== "files") ||
      (kind === "files" && term.trim().length < 2)
    ) {
      setProviderLoading(false);
      return;
    }
    setProviderLoading(true);
    providerTimer = setTimeout(async () => {
      try {
        const items = await (kind === "clipboard"
          ? clipboardItems(term)
          : fileItems(term));
        if (revision === providerRevision) setExtraItems(items);
      } catch (e) {
        if (revision === providerRevision)
          setProviderError(e instanceof Error ? e.message : String(e));
      } finally {
        if (revision === providerRevision) setProviderLoading(false);
      }
    }, 120);
  }
  const controller = new DesktopController(setState);
  if (!notificationsMode) controller.start();
  followTheme(setTheme);
  const act = async (action: () => Promise<unknown>, dismiss = false) => {
    if (busy()) return;
    setBusy(true);
    setError("");
    try {
      await action();
      if (dismiss) await close();
    } catch (e) {
      setError(e instanceof Error ? e.message : String(e));
    } finally {
      setBusy(false);
    }
  };
  const helper = (name: string, args: string[] = [], dismiss = false) =>
    void act(() => run(name, args), dismiss);
  const launch = (command: string, args: string[] = []) => {
    setError("");
    const child = spawn(command, args, { stdio: "ignore", detached: true });
    child.once("error", (e) => setError(e.message));
    child.once("spawn", () => {
      child.unref();
      void close();
    });
  };
  const open = (view: string) => {
    const child = spawn(
      process.env.DESKTOP_SHELL_EXECUTABLE ?? "desktop-shell",
      [view],
      { stdio: "ignore", detached: true },
    );
    child.once("error", (e) => setError(e.message));
    child.unref();
  };
  async function status() {
    const results = await Promise.allSettled([
      run("wpctl", ["get-volume", "@DEFAULT_AUDIO_SINK@"]),
      readdir("/sys/class/power_supply").then(async (names) => {
        for (const name of names) {
          const root = "/sys/class/power_supply/" + name;
          if (
            (await readFile(root + "/type", "utf8").catch(() => "")).trim() ===
            "Battery"
          ) {
            const [capacity, state] = await Promise.all([
              readFile(root + "/capacity", "utf8"),
              readFile(root + "/status", "utf8"),
            ]);
            return `${capacity.trim()}% ${state.trim() === "Charging" ? "↑" : ""}`;
          }
        }
        return "";
      }),
    ]);
    setVolume(
      results[0].status === "fulfilled"
        ? results[0].value.trim().replace("Volume: ", "")
        : "Audio unavailable",
    );
    setBattery(results[1].status === "fulfilled" ? results[1].value : "");
  }
  if (mode === "bar" || mode === "controls") {
    void status();
    setInterval(() => {
      setClock(new Date());
      void status();
    }, 15000);
  }
  if (mode === "launcher")
    void listThemes()
      .then(setThemeNames)
      .catch((e) => setError(String(e)));
  if (mode === "launcher")
    void applications()
      .then(setApps)
      .catch((e) => setError(String(e)));
  if (mode === "controls")
    void Promise.all(
      ["animations:enabled", "decoration:blur:enabled"].map((k) =>
        run("hyprctl", ["-j", "getoption", k]),
      ),
    )
      .then(([a, b]) => {
        setAnimations(Boolean(JSON.parse(a!).int));
        setBlur(Boolean(JSON.parse(b!).int));
      })
      .catch((e) => setError(String(e)));
  if (mode === "launcher") refreshProvider();
  const spaces = createMemo(() =>
    state()
      .workspaces.filter((w) => w.id > 0)
      .sort((a, b) => a.id - b.id),
  );
  const focusedSpace = createMemo(
    () => state().monitors.find((m) => m.focused)?.activeWorkspace.id,
  );
  const active = createMemo(() =>
    state().clients.find((c) => c.address === state().activeAddress),
  );
  const hits = createMemo(() =>
    [
      ...state().clients.map((c) => ({
        id: c.address,
        kind: "windows",
        label: c.title || c.class,
        detail: `${c.class} · ${c.workspace.name}`,
        score: searchScore(query(), c.title, c.class, c.workspace.name),
        go: () => controller.focus(c.address),
      })),
      ...apps().map((a) => ({
        id: a.id,
        kind: "applications",
        label: a.name,
        detail: a.comment || "Application",
        score: searchScore(query(), a.name, a.comment, a.keywords),
        go: () => run("gio", ["launch", a.path]),
      })),
      ...[
        {
          label: "Desktop controls",
          detail: "Audio, display and appearance",
          go: async () => open("controls"),
        },
        {
          label: "Browse windows",
          detail: "Workspaces and grouped windows",
          go: async () => open("windows"),
        },
        {
          label: "New terminal",
          detail: "Herdr projector",
          go: async () => launch("herdr-projector"),
        },
        {
          label: "Open Chrome",
          detail: "Browser",
          go: async () => launch("google-chrome-stable"),
        },
        {
          label: "Notifications",
          detail: "Notification history and do not disturb",
          go: async () => open("notifications"),
        },
      ].map((command) => ({
        ...command,
        id: command.label,
        kind: "commands",
        score: searchScore(query(), command.label, command.detail),
      })),
      ...providerItems(query(), { themeNames: themeNames() }).map((item) => ({
        id: item.id,
        kind: "commands",
        label: item.title,
        detail: item.subtitle,
        score:
          item.id === "calculator"
            ? 10000
            : searchScore(query(), item.title, item.subtitle, item.keywords),
        go: () => activateProvider(item.action),
      })),
      ...extraItems().map((item) => ({
        id: item.id,
        kind: provider(),
        label: item.title,
        detail: item.subtitle,
        score: 1,
        go: () => activateProvider(item.action),
      })),
    ]
      .filter(
        (x) => x.score >= 0 && (provider() === "all" || provider() === x.kind),
      )
      .sort((a, b) => b.score - a.score)
      .slice(0, 60),
  );
  const visibleHits = createMemo(() =>
    hits()
      .map((hit, index) => ({ hit, index }))
      .slice(Math.max(0, selected() - 7), Math.max(0, selected() - 7) + 8),
  );
  const text = (muted = false): StyleDesc => ({
    fontFamily: fonts.sans,
    fontSize: 13,
    color: muted ? theme().muted : theme().foreground,
  });
  const row: StyleDesc = {
    display: "flex",
    flexDirection: "row",
    alignItems: "center",
    gap: 8,
  };
  const mono = (): StyleDesc => ({
    ...text(true),
    fontFamily: fonts.mono,
    fontSize: 11,
  });
  function Button(p: {
    label: string;
    action: () => void;
    selected?: boolean;
    small?: boolean;
    quiet?: boolean;
    primary?: boolean;
  }) {
    const [focused, setFocused] = createSignal(false);
    const invoke = () => {
      if (!busy()) p.action();
    };
    return (
      <div
        role="button"
        aria-label={p.label}
        aria-selected={p.selected}
        tabIndex={0}
        onClick={invoke}
        onFocus={() => setFocused(true)}
        onBlur={() => setFocused(false)}
        onKeyDown={(e) => {
          if (e.key === "enter" || e.key === "space") invoke();
        }}
        style={{
          display: "flex",
          alignItems: "center",
          height: p.small ? 26 : 32,
          paddingLeft: p.small ? 8 : 10,
          paddingRight: p.small ? 8 : 10,
          borderRadius: 6,
          borderWidth: p.small || p.quiet ? 0 : 1,
          borderColor: focused()
            ? theme().accent
            : p.selected
              ? theme().foreground
              : theme().border,
          backgroundColor: p.primary
            ? theme().primary
            : p.selected
              ? theme().hover
              : p.small || p.quiet
                ? undefined
                : theme().surface,
          hover: { backgroundColor: p.primary ? theme().brand : theme().hover },
          cursor: "pointer",
          flexShrink: 0,
        }}
      >
        <text
          style={{
            ...text(),
            fontWeight: p.selected ? 600 : 400,
            color: p.primary ? theme().primaryText : theme().foreground,
            whiteSpace: "nowrap",
            textOverflow: "ellipsis",
          }}
        >
          {p.label}
        </text>
      </div>
    );
  }
  function Tab(p: { label: string; selected: boolean; action: () => void }) {
    return (
      <div
        role="tab"
        aria-label={p.label}
        aria-selected={p.selected}
        tabIndex={0}
        onClick={p.action}
        onKeyDown={(e) => {
          if (e.key === "enter" || e.key === "space") p.action();
        }}
        style={{
          height: 34,
          display: "flex",
          alignItems: "center",
          paddingLeft: 2,
          paddingRight: 2,
          marginRight: 18,
          borderBottomWidth: 2,
          borderColor: p.selected ? theme().foreground : "#00000000",
          cursor: "pointer",
        }}
      >
        <text
          style={{ ...text(!p.selected), fontWeight: p.selected ? 600 : 400 }}
        >
          {p.label}
        </text>
      </div>
    );
  }
  function Section(p: {
    title: string;
    detail?: string;
    children: JSX.Element;
  }) {
    return (
      <div
        style={{
          display: "flex",
          flexDirection: "column",
          gap: 10,
          paddingTop: 14,
          paddingBottom: 16,
          borderBottomWidth: 1,
          borderColor: theme().border,
        }}
      >
        <div style={{ ...row, justifyContent: "space-between" }}>
          <text style={{ ...text(), fontWeight: 600 }}>{p.title}</text>
          <Show when={p.detail}>
            <text style={mono()}>{p.detail}</text>
          </Show>
        </div>
        {p.children}
      </div>
    );
  }
  function Status() {
    return (
      <>
        <Show when={!notificationsMode && !state().connected}>
          <text style={{ ...text(), color: theme().error }}>
            {state().error}
          </text>
        </Show>
        <Show when={notificationsMode && !notifications().connected}>
          <text style={{ ...text(), color: theme().error }}>
            {notifications().error}
          </text>
        </Show>
        <Show when={error()}>
          <text style={{ ...text(), color: theme().error }}>{error()}</text>
        </Show>
      </>
    );
  }
  function WindowRow(p: { client: Client }) {
    const c = p.client;
    return (
      <div
        style={{
          display: "flex",
          flexDirection: "column",
          padding: 8,
          borderBottomWidth: 1,
          borderColor: theme().border,
          gap: 4,
        }}
      >
        <Button
          label={c.title || c.class}
          selected={c.address === state().activeAddress}
          action={() => void act(() => controller.focus(c.address), true)}
        />
        <text style={text(true)}>
          {c.class}
          {c.grouped.length > 1 ? ` · group of ${c.grouped.length}` : ""}
          {c.floating ? " · floating" : ""}
        </text>
        <div style={row}>
          <text style={text(true)}>Move to</text>
          <For each={spaces()}>
            {(w) => (
              <Button
                small
                label={w.name}
                selected={w.id === c.workspace.id}
                action={() => void act(() => controller.move(c.address, w.id))}
              />
            )}
          </For>
          <Button
            small
            label="Group / ungroup"
            action={() =>
              void act(async () => {
                await controller.focus(c.address);
                await controller.dispatch("togglegroup");
              })
            }
          />
        </div>
      </div>
    );
  }
  function Bar() {
    return (
      <div
        style={{
          ...row,
          height: "100%",
          width: "100%",
          paddingLeft: 8,
          paddingRight: 8,
          gap: 12,
          backgroundColor: theme().background + "d9",
          borderBottomWidth: 1,
          borderColor: theme().border + "b3",
        }}
      >
        <Button small label="Go to" action={() => open("launcher")} />
        <div
          style={{
            ...row,
            gap: 4,
            borderLeftWidth: 1,
            borderColor: theme().border,
            paddingLeft: 8,
          }}
        >
          <For each={spaces()}>
            {(w) => (
              <div
                style={{
                  borderBottomWidth: 2,
                  borderColor:
                    w.id === focusedSpace() ? theme().brand : "#00000000",
                }}
              >
                <Button
                  small
                  label={w.name}
                  action={() => void act(() => controller.workspace(w.id))}
                />
              </div>
            )}
          </For>
        </div>
        <div
          role="button"
          aria-label="Browse windows"
          onClick={() => open("windows")}
          style={{
            flexGrow: 1,
            minWidth: 0,
            paddingLeft: 8,
            cursor: "pointer",
          }}
        >
          <text
            style={{
              ...text(true),
              whiteSpace: "nowrap",
              textOverflow: "ellipsis",
            }}
          >
            {!state().connected
              ? "Reconnecting…"
              : active()?.title || "Desktop"}
          </text>
        </div>
        <Show when={error()}>
          <text style={{ ...text(), color: theme().error }}>{error()}</text>
        </Show>
        <Show when={battery()}>
          <text style={mono()}>{battery()}</text>
        </Show>
        <Button
          small
          label={clock().toLocaleTimeString([], {
            hour: "2-digit",
            minute: "2-digit",
          })}
          action={() => open("controls")}
        />
        <Button
          small
          label={
            !notifications().connected
              ? "Notifications · offline"
              : notifications().dnd
                ? "Do not disturb"
                : `Notifications${notifications().items.length ? ` · ${notifications().items.length}` : ""}`
          }
          action={() => open("notifications")}
        />
        <Button small label="Controls" action={() => open("controls")} />
      </div>
    );
  }
  function Launcher() {
    return (
      <>
        <input
          autoFocus
          role="searchbox"
          aria-label="Search desktop"
          placeholder="Search windows, applications and commands…"
          value={query()}
          onSubmit={() => {
            const hit = hits()[selected()];
            if (hit) void act(hit.go, true);
          }}
          onChange={(e) => {
            setQuery(e.value ?? "");
            setSelected(0);
            refreshProvider();
          }}
          style={{
            ...text(),
            fontSize: 15,
            height: 42,
            padding: 10,
            backgroundColor: theme().surface,
            borderWidth: 1,
            borderColor: theme().border,
            borderRadius: 6,
          }}
        />
        <div
          role="tablist"
          aria-label="Search providers"
          style={{
            ...row,
            gap: 0,
            borderBottomWidth: 1,
            borderColor: theme().border,
          }}
        >
          <For
            each={[
              ["all", "All"],
              ["windows", "Windows"],
              ["applications", "Applications"],
              ["commands", "Commands"],
              ["clipboard", "Clipboard"],
              ["files", "Files"],
            ]}
          >
            {(item) => (
              <Tab
                label={item[1]!}
                selected={provider() === item[0]}
                action={() => {
                  setProvider(item[0]!);
                  setSelected(0);
                  refreshProvider();
                }}
              />
            )}
          </For>
        </div>
        <div
          style={{
            display: "flex",
            flexDirection: "column",
            flexGrow: 1,
            overflowY: "scroll",
            paddingTop: 4,
          }}
        >
          <For each={visibleHits()}>
            {({ hit, index }) => (
              <div
                role="button"
                aria-label={hit.label}
                aria-selected={index === selected()}
                onClick={() => void act(hit.go, true)}
                style={{
                  ...row,
                  paddingLeft: 12,
                  paddingRight: 12,
                  height: 48,
                  borderRadius: 4,
                  gap: 12,
                  backgroundColor:
                    index === selected() ? theme().hover : undefined,
                  hover: { backgroundColor: theme().hover },
                  cursor: "pointer",
                }}
              >
                <div
                  style={{
                    width: 3,
                    height: 22,
                    backgroundColor:
                      index === selected() ? theme().brand : "#00000000",
                    borderRadius: 1,
                  }}
                />
                <div
                  style={{
                    display: "flex",
                    flexDirection: "column",
                    gap: 3,
                    flexGrow: 1,
                    minWidth: 0,
                  }}
                >
                  <text
                    style={{
                      ...text(),
                      whiteSpace: "nowrap",
                      textOverflow: "ellipsis",
                    }}
                  >
                    {hit.label}
                  </text>
                  <text
                    style={{
                      ...text(true),
                      fontSize: 11,
                      whiteSpace: "nowrap",
                      textOverflow: "ellipsis",
                    }}
                  >
                    {hit.detail}
                  </text>
                </div>
                <text style={mono()}>
                  {hit.kind === "windows"
                    ? "Window"
                    : hit.kind === "applications"
                      ? "App"
                      : hit.kind === "clipboard"
                        ? "Clipboard"
                        : hit.kind === "files"
                          ? "File"
                          : "Command"}
                </text>
              </div>
            )}
          </For>
          <Show when={hits().length === 0}>
            <text style={{ ...text(true), padding: 16 }}>
              {providerError() ||
                (providerLoading()
                  ? "Searching…"
                  : provider() === "files" && query().trim().length < 2
                    ? "Type at least two characters to search Documents and Downloads."
                    : "No results for this search.")}
            </text>
          </Show>
        </div>
        <div
          style={{
            ...row,
            justifyContent: "space-between",
            paddingTop: 8,
            borderTopWidth: 1,
            borderColor: theme().border,
          }}
        >
          <text style={mono()}>
            {provider() === "files"
              ? "Documents & Downloads · "
              : provider() === "clipboard"
                ? "Clipboard history · "
                : ""}
            {hits().length} results
          </text>
          <text style={mono()}>↑ ↓ select ↵ open Esc close</text>
        </div>
      </>
    );
  }
  function Controls() {
    return (
      <div
        style={{
          display: "flex",
          flexDirection: "column",
          overflowY: "scroll",
          flexGrow: 1,
          paddingRight: 4,
        }}
      >
        <div
          style={{ ...row, justifyContent: "space-between", paddingBottom: 8 }}
        >
          <text style={text(true)}>
            {clock().toLocaleDateString([], {
              weekday: "long",
              day: "numeric",
              month: "long",
            })}
          </text>
          <Show when={battery()}>
            <text style={mono()}>Battery {battery()}</text>
          </Show>
        </div>
        <Section title="Sound" detail={volume()}>
          <div style={row}>
            <Button label="Quieter" action={() => helper("volume", ["down"])} />
            <Button label="Mute" action={() => helper("volume", ["mute"])} />
            <Button label="Louder" action={() => helper("volume", ["up"])} />
          </div>
          <div style={{ ...row, justifyContent: "space-between" }}>
            <text style={text(true)}>Output</text>
            <div style={row}>
              <For
                each={[
                  ["internal", "Internal"],
                  ["speaker", "Speaker"],
                  ["inzone", "INZONE"],
                ]}
              >
                {(item) => (
                  <Button
                    quiet
                    label={item[1]!}
                    action={() => helper("audio-route", [item[0]!])}
                  />
                )}
              </For>
            </div>
          </div>
        </Section>
        <Section title="Display">
          <div style={{ ...row, justifyContent: "space-between" }}>
            <text style={text(true)}>Brightness</text>
            <div style={row}>
              <Button
                label="Dimmer"
                action={() => helper("brightness", ["down"])}
              />
              <Button
                label="Brighter"
                action={() => helper("brightness", ["up"])}
              />
            </div>
          </div>
          <div style={{ ...row, justifyContent: "space-between" }}>
            <text style={text(true)}>Effects</text>
            <div style={row}>
              <Button
                selected={animations() === true}
                label={`Animations ${animations() === null ? "…" : animations() ? "on" : "off"}`}
                action={() =>
                  void act(async () => {
                    await run("hyprctl", [
                      "keyword",
                      "animations:enabled",
                      animations() ? "false" : "true",
                    ]);
                    setAnimations(!animations());
                  })
                }
              />
              <Button
                selected={blur() === true}
                label={`Blur ${blur() === null ? "…" : blur() ? "on" : "off"}`}
                action={() =>
                  void act(async () => {
                    await run("hyprctl", [
                      "keyword",
                      "decoration:blur:enabled",
                      blur() ? "false" : "true",
                    ]);
                    setBlur(!blur());
                  })
                }
              />
            </div>
          </div>
        </Section>
        <Section title="Appearance">
          <div style={row}>
            <For
              each={[
                ["claude-light", "Claude Light"],
                ["claude-dark", "Claude Dark"],
                ["noir", "Noir"],
              ]}
            >
              {(item) => (
                <Button
                  label={item[1]!}
                  selected={theme().name === item[0]}
                  action={() => helper("theme", [item[0]!])}
                />
              )}
            </For>
          </div>
        </Section>
        <Section title="Media">
          <div style={row}>
            <Button label="Previous" action={() => helper("media", ["prev"])} />
            <Button
              label="Play / pause"
              action={() => helper("media", ["play"])}
            />
            <Button label="Next" action={() => helper("media", ["next"])} />
          </div>
        </Section>
        <Section title="Connections">
          <div style={row}>
            <Button
              label="Network"
              action={() => launch("kitty", ["--", "nmtui"])}
            />
            <Button
              label="Bluetooth"
              action={() => launch("blueman-manager")}
            />
          </div>
        </Section>
        <div style={{ ...row, paddingTop: 16, paddingBottom: 8 }}>
          <Button label="Terminal" action={() => launch("herdr-projector")} />
          <Button
            label="Chrome"
            action={() => launch("google-chrome-stable")}
          />
          <Button
            label="Capture area"
            action={() => launch("screenshot", ["area"])}
          />
        </div>
      </div>
    );
  }
  function Windows() {
    return (
      <div style={{ flexGrow: 1, overflowY: "scroll" }}>
        <div style={row}>
          <Button
            label="New workspace"
            action={() => helper("desktop-workspace", ["new"])}
          />
          <Button
            label="Rename"
            action={() => launch("desktop-workspace", ["rename"])}
          />
          <Button
            label="Detach"
            action={() => helper("desktop-workspace", ["detach"])}
          />
          <Button
            label="Park workspace"
            action={() => helper("desktop-workspace", ["close"])}
          />
          <Button
            label="Restore"
            action={() => helper("desktop-workspace", ["restore"])}
          />
        </div>
        <For each={spaces()}>
          {(w) => (
            <div>
              <div style={row}>
                <Button
                  label={w.name}
                  selected={w.id === focusedSpace()}
                  action={() =>
                    void act(() => controller.workspace(w.id), true)
                  }
                />
                <text style={text(true)}>
                  {w.monitor} · {w.windows} windows
                </text>
              </div>
              <For
                each={state().clients.filter((c) => c.workspace.id === w.id)}
              >
                {(c) => <WindowRow client={c} />}
              </For>
            </div>
          )}
        </For>
        <Show when={state().clients.length === 0 && state().connected}>
          <text style={text(true)}>No open windows.</text>
        </Show>
      </div>
    );
  }
  const activeNotificationIds = createMemo(
    () => new Set(notifications().items.map((n) => n.id)),
  );
  const notificationRows = createMemo(() => {
    const rows = [
      ...notifications().items,
      ...notifications().history.filter(
        (n) => !activeNotificationIds().has(n.id),
      ),
    ];
    return rows.sort((a, b) => b.createdAt - a.createdAt);
  });
  const toastRows = createMemo(() =>
    [...notifications().items]
      .sort((a, b) => b.urgency - a.urgency || b.createdAt - a.createdAt)
      .slice(0, 4),
  );
  function NotificationRow(p: { item: ShellNotification; toast?: boolean }) {
    const active = () => activeNotificationIds().has(p.item.id);
    return (
      <div
        style={{
          display: "flex",
          flexDirection: "column",
          gap: p.toast ? 6 : 8,
          padding: p.toast ? 10 : 12,
          flexShrink: 0,
          height: p.toast ? 140 : undefined,
          backgroundColor: p.toast ? theme().background + "e6" : undefined,
          borderWidth: p.toast ? 1 : 0,
          borderBottomWidth: 1,
          borderColor: theme().border,
          borderRadius: p.toast ? 8 : 0,
        }}
      >
        <div style={{ ...row, justifyContent: "space-between" }}>
          <text
            style={{
              ...mono(),
              flexGrow: 1,
              minWidth: 0,
              whiteSpace: "nowrap",
              textOverflow: "ellipsis",
              color: p.item.urgency === 2 ? theme().brand : theme().muted,
            }}
          >
            {p.item.app || "Notification"}
            {p.item.urgency === 2 ? " · urgent" : ""}
          </text>
          <Show when={!p.toast}>
            <text style={mono()}>
              {new Date(p.item.createdAt).toLocaleTimeString([], {
                hour: "2-digit",
                minute: "2-digit",
              })}
            </text>
          </Show>
          <Show when={active()}>
            <Button
              small
              quiet
              label="Dismiss"
              action={() =>
                void act(() =>
                  notificationCommand({ type: "dismiss", id: p.item.id }),
                )
              }
            />
          </Show>
        </div>
        <text
          style={{
            ...text(),
            fontWeight: 600,
            whiteSpace: "nowrap",
            textOverflow: "ellipsis",
          }}
        >
          {p.item.summary}
        </text>
        <Show when={p.item.body}>
          <div style={{ maxHeight: p.toast ? 28 : 100, overflow: "hidden" }}>
            <text
              style={{ ...text(true), color: theme().secondary, fontSize: 12 }}
            >
              {p.item.body}
            </text>
          </div>
        </Show>
        <Show when={active() && p.item.actions.length > 0}>
          <div style={{ ...row, marginTop: 0, overflowX: "scroll" }}>
            <For each={p.item.actions}>
              {(action) => (
                <Button
                  small
                  label={action.label}
                  action={() =>
                    void act(() =>
                      notificationCommand({
                        type: "action",
                        id: p.item.id,
                        key: action.key,
                      }),
                    )
                  }
                />
              )}
            </For>
          </div>
        </Show>
      </div>
    );
  }
  function Notifications() {
    return (
      <>
        <div
          style={{
            ...row,
            justifyContent: "space-between",
            paddingBottom: 10,
            borderBottomWidth: 1,
            borderColor: theme().border,
          }}
        >
          <Button
            label={`Do not disturb ${notifications().dnd ? "on" : "off"}`}
            selected={notifications().dnd}
            action={() =>
              void act(() =>
                notificationCommand({
                  type: "dnd",
                  enabled: !notifications().dnd,
                }),
              )
            }
          />
          <Button
            quiet
            label="Clear all"
            action={() =>
              void act(() => notificationCommand({ type: "clear" }))
            }
          />
        </div>
        <div
          style={{
            display: "flex",
            flexDirection: "column",
            flexGrow: 1,
            overflowY: "scroll",
          }}
        >
          <For each={notificationRows()}>
            {(item) => <NotificationRow item={item} />}
          </For>
          <Show
            when={notifications().connected && notificationRows().length === 0}
          >
            <text style={{ ...text(true), padding: 16 }}>
              No notifications.
            </text>
          </Show>
        </div>
        <text style={mono()}>
          {notifications().items.length} active ·{" "}
          {notifications().history.length} in history
        </text>
      </>
    );
  }
  function Toasts() {
    return (
      <div
        style={{
          display: "flex",
          flexDirection: "column",
          gap: 8,
          width: "100%",
          height: "100%",
        }}
      >
        <For each={toastRows()}>
          {(item) => <NotificationRow item={item} toast />}
        </For>
        <Show when={error() || !notifications().connected}>
          <div
            style={{
              padding: 12,
              backgroundColor: theme().background + "e6",
              borderRadius: 8,
            }}
          >
            <Status />
            <Button small label="Close" action={() => void close()} />
          </div>
        </Show>
      </div>
    );
  }
  function App() {
    return mode === "bar" ? (
      <Bar />
    ) : mode === "toasts" ? (
      <Toasts />
    ) : (
      <div
        style={{
          display: "flex",
          flexDirection: "column",
          width: "100%",
          height: "100%",
          backgroundColor: theme().background + "e6",
          padding: 16,
          gap: 12,
          borderWidth: 1,
          borderColor: theme().border,
          borderRadius: 8,
        }}
      >
        <div style={{ ...row, justifyContent: "space-between" }}>
          <text style={{ ...text(), fontSize: 17, fontWeight: 600 }}>
            {mode === "launcher"
              ? "Go to"
              : mode === "controls"
                ? "Controls"
                : mode === "notifications"
                  ? "Notifications"
                  : "Windows"}
          </text>
          <Button small label="Close" action={() => void close()} />
        </div>
        <Status />
        {mode === "launcher" ? (
          <Launcher />
        ) : mode === "controls" ? (
          <Controls />
        ) : mode === "notifications" ? (
          <Notifications />
        ) : (
          <Windows />
        )}
        <Show when={busy()}>
          <text style={text(true)}>Working…</text>
        </Show>
      </div>
    );
  }
  // GPUIX 0.10 exposes no layer surface resize/input-region setter. Size the
  // toast surface to actual rows; daemon supervises clean exits when count
  // changes. This avoids a transparent rectangle swallowing desktop clicks.
  if (mode === "toasts") {
    await new Promise<void>((resolve, reject) => {
      const timeout = setTimeout(
        () =>
          reject(new Error("Notification service did not provide a snapshot")),
        3000,
      );
      void ready.then(() => {
        clearTimeout(timeout);
        resolve();
      });
    });
    toastCount = Math.min(4, notifications().items.length);
    if (!toastCount || notifications().dnd) {
      await close();
      return;
    }
  }
  const options = {
    title: "Desktop shell",
    appId: `desktop-shell-${mode}`,
    width:
      mode === "bar"
        ? 1
        : mode === "toasts"
          ? 390
          : mode === "notifications"
            ? 500
            : mode === "controls"
              ? 560
              : 700,
    height:
      mode === "bar"
        ? 32
        : mode === "toasts"
          ? toastCount * 148 - 8
          : mode === "notifications"
            ? 650
            : mode === "controls"
              ? 710
              : 580,
    transparent: true,
    layerShell: {
      namespace: `desktop-shell-${mode}`,
      layer: mode === "bar" ? "top" : "overlay",
      anchor:
        mode === "bar"
          ? ["top", "left", "right"]
          : mode === "toasts"
            ? ["top"]
            : ["top", "right"],
      exclusiveZone: mode === "bar" ? 32 : -1,
      keyboardInteractivity:
        mode === "bar" || mode === "toasts" ? "none" : "exclusive",
      margin:
        mode === "bar"
          ? [0, 0, 0, 0]
          : mode === "toasts"
            ? [40, 0, 0, 0]
            : [40, 12, 0, 0],
    },
    onKeyDown: (e: EventPayload, renderer: NativeRenderer) => {
      if (e.key === "tab") {
        if (e.modifiers?.shift) renderer.focusPrevious?.();
        else renderer.focusNext?.();
        return true;
      }
      if (e.key === "escape" && mode !== "bar") {
        void close();
        return true;
      }
      if (mode === "launcher") {
        if (e.key === "down") {
          setSelected((s) => Math.max(0, Math.min(s + 1, hits().length - 1)));
          return true;
        }
        if (e.key === "up") {
          setSelected((s) => Math.max(0, s - 1));
          return true;
        }
        if (e.key === "enter") {
          const hit = hits()[selected()];
          if (hit) void act(hit.go, true);
          return true;
        }
      }
      return false;
    },
  };
  // Linux GPUI owns its UI thread; avoid the stock 8ms JS tick loop.
  const native = createRenderer();
  native.init(options);
  render(() => <App />, { ...options, renderer: native });
  setInterval(() => {
    if (!native.tick()) void close();
  }, 500);
}
