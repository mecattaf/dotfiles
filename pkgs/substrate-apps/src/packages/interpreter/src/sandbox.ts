/**
 * The script's realm: a fresh node:vm context with nothing from the host in it.
 *
 * The script sees only the ECMAScript intrinsics of its own realm plus the
 * workflow builtins. Every builtin is DEFINED INSIDE the realm (see PRELUDE)
 * and talks to the host through one captured `host` object that the script can
 * never name. Values cross the boundary as JSON strings, and host errors are
 * re-created as realm errors, so no host object (and so no host `Function`
 * constructor, the classic node:vm escape) is ever reachable from the script.
 *
 * `parallel` and `pipeline` are pure combinators and run entirely in the realm.
 * `Date.now()`, `Date()`, argless `new Date()` and `Math.random()` throw, as in
 * the harness: they would make a resumed run diverge from its journal.
 *
 * This is isolation of GLOBALS and of the host object graph, not a security
 * boundary against a hostile script (vm shares the process, the heap and the
 * event loop). Workflow scripts are the operator's own code.
 */
import vm from "node:vm";

/** The host half of the bridge. Every value in and out is a primitive or a JSON string. */
export interface HostBridge {
  agent(prompt: unknown, optsJson: string | undefined): Promise<string>;
  phase(title: string): void;
  log(message: string): void;
  itemNull(where: "parallel" | "pipeline", item: number, stage: number, reason: string): void;
  maxItems(): number;
  budgetTotal(): number | null;
  budgetSpent(): number;
  workflow(ref: string, argsJson: string | undefined): Promise<string>;
}

const PRELUDE = String.raw`
(function install(host) {
  "use strict";
  const RealDate = Date;
  const banned = (what) => { throw new Error(what + " is not available in a workflow script (it would break resume)"); };
  function GuardedDate(...a) {
    if (!new.target) banned("Date()");
    if (a.length === 0) banned("new Date()");
    return Reflect.construct(RealDate, a, new.target);
  }
  Object.defineProperty(GuardedDate, "prototype", { value: RealDate.prototype, writable: false });
  Object.defineProperty(RealDate.prototype, "constructor", { value: GuardedDate, writable: false, configurable: false });
  GuardedDate.now = () => banned("Date.now()");
  GuardedDate.parse = RealDate.parse;
  GuardedDate.UTC = RealDate.UTC;
  Object.freeze(GuardedDate);
  Object.defineProperty(globalThis, "Date", { value: GuardedDate, writable: false, configurable: false });
  Object.defineProperty(Math, "random", { value: () => banned("Math.random()"), writable: false, configurable: false });

  const realmError = (e) => new Error(e && typeof e.message === "string" ? e.message : String(e));
  const decode = (s) => JSON.parse(s);
  const optsJson = (o) => {
    if (o === undefined || o === null) return undefined;
    if (typeof o !== "object") throw new TypeError("agent(prompt, opts): opts must be an object");
    return JSON.stringify(o, (k, v) => (typeof v === "function" ? undefined : v));
  };

  async function agent(prompt, opts) {
    let p;
    try { p = host.agent(prompt, optsJson(opts)); } catch (e) { throw realmError(e); }
    let s;
    try { s = await p; } catch (e) { throw realmError(e); }
    return decode(s);
  }

  const checkItems = (name, n) => {
    const cap = host.maxItems();
    if (n > cap) throw new Error(name + ": " + n + " items exceeds the per-call cap of " + cap);
  };
  const why = (e) => (e && typeof e.message === "string" ? e.message : String(e));

  async function parallel(thunks) {
    if (!Array.isArray(thunks)) throw new TypeError("parallel(thunks): thunks must be an array");
    checkItems("parallel", thunks.length);
    return Promise.all(thunks.map((t, i) =>
      Promise.resolve()
        .then(() => (typeof t === "function" ? t() : t))
        .catch((e) => { host.itemNull("parallel", i, 0, why(e)); return null; })));
  }

  async function pipeline(items, ...stages) {
    if (!Array.isArray(items)) throw new TypeError("pipeline(items, ...stages): items must be an array");
    checkItems("pipeline", items.length);
    for (const s of stages) if (typeof s !== "function") throw new TypeError("pipeline: every stage must be a function");
    return Promise.all(items.map(async (item, index) => {
      let prev = item;
      for (let s = 0; s < stages.length; s++) {
        try { prev = await stages[s](prev, item, index); }
        catch (e) { host.itemNull("pipeline", index, s, why(e)); return null; }
      }
      return prev;
    }));
  }

  const phase = (title) => { host.phase(String(title)); };
  const log = (message) => { host.log(typeof message === "string" ? message : String(message)); };
  const budget = Object.freeze({
    get total() { return host.budgetTotal(); },
    spent: () => host.budgetSpent(),
    remaining: () => { const t = host.budgetTotal(); return t === null ? Infinity : Math.max(0, t - host.budgetSpent()); },
  });
  async function workflow(ref, args) {
    const name = typeof ref === "string" ? ref : ref && typeof ref.scriptPath === "string" ? ref.scriptPath : ref && typeof ref.name === "string" ? ref.name : null;
    if (name === null) throw new TypeError("workflow(nameOrRef, args): name must be a string or { scriptPath } / { name }");
    let p;
    try { p = host.workflow(name, args === undefined ? undefined : JSON.stringify(args)); } catch (e) { throw realmError(e); }
    let s;
    try { s = await p; } catch (e) { throw realmError(e); }
    return decode(s);
  }
  return Object.freeze({ agent, parallel, pipeline, phase, log, budget, workflow });
})
`;

export interface CompiledScript {
  run(argsJson: string | undefined): Promise<string>;
}

/**
 * Compile a script body (meta already cut out) into its own realm.
 * `lineOffset` keeps stack-trace line numbers equal to the file's.
 */
export function compileInRealm(body: string, filename: string, host: HostBridge): CompiledScript {
  const ctx = vm.createContext(Object.create(null), { name: filename, codeGeneration: { strings: true, wasm: false } });
  const install = new vm.Script(PRELUDE, { filename: "workflow-prelude.js" }).runInContext(ctx) as (h: HostBridge) => Record<string, unknown>;
  const builtins = install(host);
  const wrapped =
    "(async function (agent, parallel, pipeline, phase, log, budget, workflow, __argsJson) {\n" +
    '"use strict"; const args = __argsJson === undefined ? undefined : JSON.parse(__argsJson);\n' +
    body +
    "\n})";
  let fn: (...a: unknown[]) => Promise<unknown>;
  try {
    fn = new vm.Script(wrapped, { filename, lineOffset: -2 }).runInContext(ctx) as typeof fn;
  } catch (e) {
    throw new SyntaxError(`${filename}: ${(e as Error).message}`);
  }
  const toJson = new vm.Script(
    "(v) => { const s = JSON.stringify(v === undefined ? null : v); return s === undefined ? 'null' : s; }",
  ).runInContext(ctx) as (v: unknown) => string;
  return {
    async run(argsJson) {
      const v = await fn(
        builtins.agent,
        builtins.parallel,
        builtins.pipeline,
        builtins.phase,
        builtins.log,
        builtins.budget,
        builtins.workflow,
        argsJson,
      );
      return toJson(v);
    },
  };
}
