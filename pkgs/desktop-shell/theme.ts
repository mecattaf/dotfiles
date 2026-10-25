import { readFile } from "node:fs/promises";
import { watch } from "node:fs";
import { join } from "node:path";

// Native projection of the accepted design/claude-primer role mapping.
// Palette values originate in home/themes; no browser or Primer DOM is loaded.
export interface Theme {
  name: string;
  light: boolean;
  background: string;
  surface: string;
  subtle: string;
  foreground: string;
  secondary: string;
  muted: string;
  border: string;
  selection: string;
  selectionText: string;
  error: string;
  accent: string;
  brand: string;
  primary: string;
  primaryText: string;
  hover: string;
}
export const fonts = {
  sans: "Anthropic Sans",
  mono: "Anthropic Mono",
  serif: "Anthropic Serif",
};
export const fallback: Theme = {
  name: "noir",
  light: false,
  background: "#000000",
  surface: "#000000",
  subtle: "#000000",
  foreground: "#EAECF0",
  secondary: "#D3D7DE",
  muted: "#818898",
  border: "#373735",
  selection: "#264F78",
  selectionText: "#EAECF0",
  error: "#F47B85",
  accent: "#70B8FF",
  brand: "#D97757",
  primary: "#D97757",
  primaryText: "#131313",
  hover: "#37373555",
};
const color = (value: unknown, otherwise: string) =>
  typeof value === "string" && /^#[a-f\d]{6}$/i.test(value) ? value : otherwise;
export function parsePalette(value: unknown): Theme {
  if (!value || typeof value !== "object")
    throw new Error("Invalid shell palette");
  const p = value as Record<string, any>;
  if (
    !p.ground ||
    !p.border ||
    !p.selection ||
    !["claude-light", "claude-dark", "noir"].includes(p.name)
  )
    throw new Error("Incomplete shell palette");
  const light = p.name === "claude-light";
  const background = color(
    light ? p.ground.base : p.ground.desktop,
    fallback.background,
  );
  const subtle = color(p.ground.dim, fallback.subtle);
  const border = color(p.border.inactive, fallback.border);
  return {
    name: p.name,
    light,
    background,
    surface: color(p.ground.raised, fallback.surface),
    subtle,
    foreground: color(p.fg, fallback.foreground),
    secondary: color(p.fgDim, fallback.secondary),
    muted: color(light ? p.fgDim : p.comment, fallback.muted),
    border,
    selection: color(p.selection.bg, fallback.selection),
    selectionText: color(p.selection.fg, fallback.selectionText),
    error: color(p.red, fallback.error),
    accent: color(p.accent, fallback.accent),
    brand: color(p.brand, fallback.brand),
    primary: light ? "#A74B2F" : color(p.brand, fallback.brand),
    primaryText: light ? "#FFFFFF" : "#131313",
    hover: p.name === "noir" ? border + "55" : subtle,
  };
}
// Compatibility with generations predating the complete JSON theme fragment.
export function parseTheme(text: string): Theme {
  const p: Record<string, string> = {};
  for (const line of text.split("\n")) {
    const m = line.match(/^([a-z_0-9]+)\s+(#[a-fA-F0-9]{6})\s*$/);
    if (m) p[m[1]!] = m[2]!;
  }
  return {
    ...fallback,
    background: p.background ?? fallback.background,
    surface: p.background ?? fallback.surface,
    foreground: p.foreground ?? fallback.foreground,
    secondary: p.color7 ?? fallback.secondary,
    muted: p.color8 ?? fallback.muted,
    border: p.inactive_border_color ?? fallback.border,
    selection: p.selection_background ?? fallback.selection,
    selectionText: p.selection_foreground ?? fallback.selectionText,
    error: p.color1 ?? fallback.error,
    accent: p.url_color ?? fallback.accent,
  };
}
export function followTheme(update: (theme: Theme) => void) {
  const dir =
    process.env.XDG_CONFIG_HOME ?? join(process.env.HOME ?? "", ".config");
  let timer: ReturnType<typeof setTimeout> | undefined;
  let revision = 0;
  const reload = async () => {
    const current = ++revision;
    let next: Theme;
    try {
      next = parsePalette(
        JSON.parse(
          await readFile(join(dir, "theme", "desktop-shell.json"), "utf8"),
        ),
      );
    } catch {
      next = await readFile(join(dir, "theme", "kitty.conf"), "utf8")
        .then(parseTheme)
        .catch(() => fallback);
    }
    if (current === revision) update(next);
  };
  let watcher: ReturnType<typeof watch> | undefined;
  try {
    watcher = watch(dir, (_, file) => {
      if (file?.toString() === "theme") {
        clearTimeout(timer);
        timer = setTimeout(() => void reload(), 50);
      }
    });
  } catch {}
  process.on("SIGUSR1", reload);
  void reload();
  return () => {
    revision++;
    clearTimeout(timer);
    watcher?.close();
    process.off("SIGUSR1", reload);
  };
}
