#!/usr/bin/env node
// Entry point: registers tsx's ESM loader, then runs src/cli.ts.
import { register } from "tsx/esm/api";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";

register();
const here = dirname(fileURLToPath(import.meta.url));
const { main } = await import(join(here, "..", "src", "cli.ts"));
const { code, out } = await main(process.argv.slice(2));
(code === 0 ? process.stdout : process.stderr).write(out + "\n");
process.exitCode = code;
