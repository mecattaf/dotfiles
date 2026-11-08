// Adapted from Manganese 67c29a9906905bd5e1679803232c2f510b3fed9e,
// shell-manganese/src/theme. Copyright 2026 Connor Prussin; MIT (LICENSE).
import type { ThemeSource } from "@domicile-desktop/component-library/theme-source";
import { watchHost } from "@domicile-desktop/manganese-host/watch-host";
import type { Domicile } from "@domicile-desktop/sdk/desktop/desktop";
import { themeSchema } from "@domicile-desktop/sdk/theme";

const KEY = "theme:v2";
export const rememberedTheme = () =>
  themeSchema.safeParse(globalThis.localStorage?.getItem(KEY)).data;

export const hostTheme = ({ theme }: Pick<Domicile, "theme">): ThemeSource => {
  const turning: (() => void)[] = [];
  theme.on("windowschange", () => {
    for (const settle of turning.splice(0)) setTimeout(settle, 300);
  });
  return {
    get theme() { return theme.current ?? rememberedTheme(); },
    onTheme: (handler) => watchHost(
      (heard) => theme.on("change", heard), () => theme.current,
      (current) => {
        globalThis.localStorage?.setItem(KEY, current);
        handler(current);
      },
    ),
    setTheme: (next) => { theme.set(next); },
    turnWindows: (next) => new Promise((resolve) => {
      turning.push(resolve);
      theme.captured(next);
    }),
  };
};
