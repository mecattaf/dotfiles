import { readdir, readFile } from "node:fs/promises";
import { join } from "node:path";
export interface Application {
  id: string;
  name: string;
  comment: string;
  keywords: string;
  path: string;
  terminal: boolean;
}
export function parseDesktop(
  contents: string,
  path: string,
  id: string,
  desktops: string[],
): Application | null | undefined {
  let inEntry = false;
  const values: Record<string, string> = {};
  for (const line of contents.split(/\r?\n/)) {
    if (line.startsWith("[")) {
      inEntry = line === "[Desktop Entry]";
      continue;
    }
    if (!inEntry || line.startsWith("#")) continue;
    const at = line.indexOf("=");
    if (at > 0)
      values[line.slice(0, at)] = line
        .slice(at + 1)
        .replace(/\\s/g, " ")
        .replace(/\\n/g, " ");
  }
  if (values.Hidden === "true") return null;
  if (
    values.Type !== "Application" ||
    values.NoDisplay === "true" ||
    !values.Name ||
    (!values.Exec && values.DBusActivatable !== "true")
  )
    return undefined;
  if (
    values.OnlyShowIn &&
    !values.OnlyShowIn.split(";").some((x) => desktops.includes(x))
  )
    return undefined;
  if (values.NotShowIn?.split(";").some((x) => desktops.includes(x)))
    return undefined;
  return {
    id,
    name: values.Name,
    comment: values.Comment ?? "",
    keywords: values.Keywords ?? "",
    path,
    terminal: values.Terminal === "true",
  };
}
export async function applications(env = process.env): Promise<Application[]> {
  const roots = [
    env.XDG_DATA_HOME ?? join(env.HOME ?? "", "/.local/share"),
    ...(env.XDG_DATA_DIRS ?? "/usr/local/share:/usr/share").split(":"),
  ];
  const found = new Map<string, Application | null | undefined>();
  const desktops = (env.XDG_CURRENT_DESKTOP ?? "Hyprland").split(":");
  async function scan(dir: string, prefix = "") {
    let entries;
    try {
      entries = await readdir(dir, { withFileTypes: true });
    } catch {
      return;
    }
    for (const entry of entries) {
      const path = join(dir, entry.name),
        id = prefix + entry.name;
      if (entry.isDirectory()) {
        await scan(path, id + "-");
        continue;
      }
      if (!entry.name.endsWith(".desktop") || found.has(id)) continue;
      try {
        found.set(
          id,
          parseDesktop(await readFile(path, "utf8"), path, id, desktops),
        );
      } catch {
        /* Broken desktop entries are skipped, never executed as shell text. */
      }
    }
  }
  for (const root of roots) await scan(join(root, "applications"));
  return [...found.values()]
    .filter((x): x is Application => Boolean(x))
    .sort((a, b) => a.name.localeCompare(b.name));
}
export function searchScore(query: string, ...values: string[]): number {
  const terms = query.toLocaleLowerCase().trim().split(/\s+/).filter(Boolean),
    text = values.join(" ").toLocaleLowerCase();
  if (!terms.every((term) => text.includes(term))) return -1;
  return terms.reduce(
    (score, term) =>
      score + (values[0]?.toLocaleLowerCase().startsWith(term) ? 10 : 1),
    0,
  );
}
