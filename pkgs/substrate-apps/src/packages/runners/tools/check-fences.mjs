#!/usr/bin/env node
// Fences for @substrate/runners. Each fence is a rule the house or a ruling
// states, checked mechanically over the package's own files. Exit 1 on any hit.
import { readdirSync, readFileSync, statSync } from "node:fs";
import { dirname, join, relative } from "node:path";
import { fileURLToPath } from "node:url";

const root = join(dirname(fileURLToPath(import.meta.url)), "..");
const walk = (d) =>
  readdirSync(d).flatMap((f) => {
    const p = join(d, f);
    if (f === "node_modules") return [];
    return statSync(p).isDirectory() ? walk(p) : [p];
  });
const files = ["src", "test", "bin", "tools", "scripts"]
  .flatMap((d) => { try { return walk(join(root, d)); } catch { return []; } })
  .concat([join(root, "README.md"), join(root, "runtimes.example.toml")].filter((p) => { try { return statSync(p).isFile(); } catch { return false; } }));

const SRC = (f) => /\/(src|bin)\//.test(f);
const fences = [
  { id: "no-tally-dependency", why: "R44: tally and tally-ts-sdk are prior art, never a dependency", only: SRC, re: /from\s+["'][^"']*tally/ },
  { id: "no-systemctl-exec", why: "house rule: no systemctl from code", only: SRC, re: /\[\s*["'](?:systemctl|nixos-rebuild)["']|["']nix["']\s*,\s*["']profile["']/ },
  { id: "no-herdr-server-control", why: "never restart or stop herdr", only: SRC, re: /server\.(?:stop|restart|shutdown)|["']server["']\s*,\s*["'](?:stop|restart)["']/ },
  { id: "no-runtime-dir", why: "never touch /run/user; runsc state lives under ~/.local/state", only: SRC, re: /XDG_RUNTIME_DIR/ },
  { id: "model-pinned", why: "OI-6: model ids by full id; the allowlist (src/models.ts) is the one place a model or alias is named", only: (f) => SRC(f) && !/\/src\/models\.ts$/.test(f), re: /["'](?:opus|best|claude-fable[^"']*|[^"']*sonnet[^"']*)["']/ },
  { id: "no-credential-read", why: "credentials are mounted, never read or copied", only: SRC, re: /\.credentials\.json(?!.*fence-ok: bound by path, never read)|readFileSync\([^)]*(?:cred|claude)/i },
  { id: "no-dotenv", why: "never read a .env", only: SRC, re: /readFileSync\([^)]*\.env\b/ },
  { id: "no-push-or-deploy", why: "no push, no deploy from code", only: SRC, re: /["']git["']\s*,\s*["']push["']|wrangler\s+deploy/ },
  { id: "no-em-dash", why: "Tom: no em-dashes in anything written for him", only: () => true, re: new RegExp(String.fromCharCode(0x2014)), comments: true },
];

let hits = 0;
for (const f of files) {
  const lines = readFileSync(f, "utf8").split("\n");
  for (const fence of fences) {
    if (!fence.only(f)) continue;
    lines.forEach((l, i) => {
      const comment = /^\s*(\*|\/\/|\/\*)/.test(l);
      if (comment && !fence.comments) return;
      if (fence.re.test(l)) {
        hits++;
        console.log(`${fence.id}: ${relative(root, f)}:${i + 1}: ${l.trim().slice(0, 160)}  (${fence.why})`);
      }
    });
  }
}
console.log(`fences: ${fences.length} rules over ${files.length} files, ${hits} hit(s)`);
process.exit(hits ? 1 : 0);
