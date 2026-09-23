#!/usr/bin/env node
// Entry point: registers tsx's ESM loader, then runs src/main.ts.
import { register } from "tsx/esm/api";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";

register();
const here = dirname(fileURLToPath(import.meta.url));
const { main } = await import(join(here, "..", "src", "main.ts"));
process.exitCode = await main(process.env);
