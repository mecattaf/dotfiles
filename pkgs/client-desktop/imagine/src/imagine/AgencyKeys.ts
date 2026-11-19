// Stock command parsing stays in public useKeybindings. This adapter consumes
// only Agency's namespace before forwarding the remaining events unchanged.
import { useKeybindings } from "@domicile-desktop/manganese-window-management/keyboard/useKeybindings";
import type { WindowAction, WindowState } from "@domicile-desktop/manganese-window-management/window-state";
import type { Domicile } from "@domicile-desktop/sdk/desktop/desktop";
import { KeyAction, KeyActionKind } from "@domicile-desktop/sdk/key-action";
import { ownKeybindings } from "@domicile-desktop/sdk/own-keybindings";
import type { ShellKeybindings } from "@domicile-desktop/sdk/own-keybindings";
import { useEffectEvent, useMemo } from "react";

// Vertical output selection follows stock 67c29a9 screen-toward.ts (MIT,
// LICENSE): choose the nearest screen wholly beyond the current output's edge.
export const outputToward = (
  screens: WindowState["screens"],
  focused: string,
  direction: "up" | "down",
): string | undefined => {
  const here = screens.find(({ name }) => name === focused)?.box;
  if (here === undefined) return undefined;
  const x = here.x + here.width / 2;
  const y = here.y + here.height / 2;
  const distance = ({ box }: WindowState["screens"][number]) => {
    const dx = Math.min(Math.max(x, box.x), box.x + box.width) - x;
    const dy = Math.min(Math.max(y, box.y), box.y + box.height) - y;
    return dx * dx + dy * dy;
  };
  return screens.filter(({ name, box }) => name !== focused && (direction === "up"
    ? box.y + box.height <= here.y : box.y >= here.y + here.height))
    .toSorted((a, b) => distance(a) - distance(b))[0]?.name;
};

export const useAgencyKeys = ({ domicile, keybindings, mode, modal, onAction,
  onModeChanged, onAgency, chatWindow = false }: {
  domicile: Domicile;
  keybindings: ShellKeybindings;
  mode: string;
  modal: boolean;
  onAction: (action: WindowAction) => void;
  onModeChanged: (mode: string) => void;
  onAgency: (args: readonly string[]) => void;
  chatWindow?: boolean;
}) => {
  const keys = useMemo(() => ({ ...keybindings, keybindings: {
    ...keybindings.keybindings,
    "Meta+b": KeyAction.SendShell(["agency", "rail", "toggle"]),
    ...(chatWindow ? { "Alt+Return": KeyAction.SendShell(["imagine", "chat-window", "toggle"]) } : {}),
  } }), [keybindings, chatWindow]);
  const modes = useMemo(() => ownKeybindings(keys), [keys]);
  const command = useEffectEvent((args: readonly string[]) => {
    if (args[0] !== "agency" && args[0] !== "imagine") return false;
    onAgency(args.slice(1));
    return true;
  });
  const shortcut = useEffectEvent((chord: string) => {
    const action = modes.get(mode)?.get(chord);
    return action?.kind === KeyActionKind.SendShell && command(action.args);
  });
  const adapted = useMemo(() => new Proxy(domicile, {
    get(target, key) {
      if (key === "keyboard") return new Proxy(target.keyboard, {
        get(keyboard, member) {
          if (member !== "on") return Reflect.get(keyboard, member);
          const observe = keyboard.on as (name: string, handler: (event: unknown) => void) => () => void;
          return ((name: string, handler: (event: unknown) => void) =>
            observe(name, (event: unknown) => {
              if (name !== "shortcut" || !shortcut((event as { chord: string }).chord)) handler(event);
            })) as typeof keyboard.on;
        },
      });
      if (key === "shell") return new Proxy(target.shell, {
        get(shell, member) {
          if (member !== "commands") return Reflect.get(shell, member);
          return async () => (await shell.commands()).map((listening) => ({
            ...listening,
            items: listening.items.pipeThrough(new TransformStream<readonly string[], readonly string[]>({
              transform(args, controller) { if (!command(args)) controller.enqueue(args); },
            })),
          }));
        },
      });
      return Reflect.get(target, key);
    },
  }), [domicile]);
  useKeybindings({ domicile: adapted, keybindings: keys, launcherOpen: modal,
    mode, onAction, onModeChanged });
  return keys;
};
