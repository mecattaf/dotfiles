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
 * the harness: they would make a resumed run diverge from its journal. So does
 * `Intl.DateTimeFormat` format() or formatToParts() with no date (D17), which
 * the spec defaults to the current time; Intl and the Date
 * `toLocale*String` methods default to the UTC zone, not the host's; the Date
 * local-time accessors (`getHours`, `setHours`, `getTimezoneOffset`,
 * `toString`) and the multi-field constructor answer in UTC too.
 *
 * This is isolation of GLOBALS and of the host object graph, not a security
 * boundary against a hostile script (vm shares the process, the heap and the
 * event loop). Workflow scripts are the operator's own code.
 */
import vm from "node:vm";

/** The host half of the bridge. Every value in and out is a primitive or a JSON string. */
export interface HostBridge {
  /** `lane`: the realm-side lane path of the call (D06), or undefined outside any combinator lane. */
  agent(prompt: unknown, optsJson: string | undefined, lane?: string): Promise<string>;
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
    // D17: the multi-field form reads its fields as UTC, not in the host zone.
    if (a.length >= 2) return Reflect.construct(RealDate, [RealDate.UTC(...a)], new.target);
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
  // D17: an Intl date format with no date reads the clock (the spec defaults it to Date.now()).
  const DTFP = Intl.DateTimeFormat.prototype;
  const fmtGet = Object.getOwnPropertyDescriptor(DTFP, "format").get;
  // One wrapper per formatter, as the spec caches one bound format (f.format === f.format).
  const fmtCache = new WeakMap();
  Object.defineProperty(DTFP, "format", { get() {
    const f = fmtGet.call(this);
    let w = fmtCache.get(this);
    if (w === undefined) { w = (d) => (d === undefined ? banned("Intl.DateTimeFormat format() with no date") : f(d)); fmtCache.set(this, w); }
    return w;
  }, configurable: false });
  const fmtParts = DTFP.formatToParts;
  Object.defineProperty(DTFP, "formatToParts", { value: function formatToParts(d) { return d === undefined ? banned("Intl.DateTimeFormat formatToParts() with no date") : fmtParts.call(this, d); }, writable: false, configurable: false });

  // D17: Intl reads the clock (an argless format()) and the host time zone (the default timeZone). Pin the
  // default zone to UTC and refuse a format with no date, so a resumed run on another host cannot diverge.
  const RealDTF = Intl.DateTimeFormat;
  const pinUtc = (o) => { const x = Object.assign({}, o); if (x.timeZone === undefined) x.timeZone = "UTC"; return x; };
  const needDate = (what, d) => { if (d === undefined) banned("Intl.DateTimeFormat " + what + "() with no date"); return d; };
  function GuardedDTF(locales, options) {
    const inner = new RealDTF(locales, pinUtc(options));
    const self = Object.create(GuardedDTF.prototype);
    Object.defineProperties(self, {
      format: { value: (d) => inner.format(needDate("format", d)) },
      formatToParts: { value: (d) => inner.formatToParts(needDate("formatToParts", d)) },
      formatRange: { value: (a, b) => inner.formatRange(a, b) },
      formatRangeToParts: { value: (a, b) => inner.formatRangeToParts(a, b) },
      resolvedOptions: { value: () => inner.resolvedOptions() },
    });
    return Object.freeze(self);
  }
  GuardedDTF.supportedLocalesOf = RealDTF.supportedLocalesOf;
  Object.freeze(GuardedDTF.prototype);
  Object.freeze(GuardedDTF);
  Object.defineProperty(Intl, "DateTimeFormat", { value: GuardedDTF, writable: false, configurable: false });
  // The local-time accessors answer in UTC, so the host zone never reaches the script through Date either.
  const DP = RealDate.prototype;
  for (const f of ["FullYear", "Month", "Date", "Day", "Hours", "Minutes", "Seconds", "Milliseconds"]) {
    Object.defineProperty(DP, "get" + f, { value: DP["getUTC" + f], writable: false, configurable: false });
    if (f !== "Day") Object.defineProperty(DP, "set" + f, { value: DP["setUTC" + f], writable: false, configurable: false });
  }
  Object.defineProperty(DP, "getTimezoneOffset", { value: function () { return 0; }, writable: false, configurable: false });
  const realToUTCString = DP.toUTCString;
  Object.defineProperty(DP, "toString", { value: function () { return realToUTCString.call(this); }, writable: false, configurable: false });
  Object.defineProperty(DP, "toDateString", { value: function () { return realToUTCString.call(this).slice(0, 16); }, writable: false, configurable: false });
  Object.defineProperty(DP, "toTimeString", { value: function () { return realToUTCString.call(this).slice(17); }, writable: false, configurable: false });
  for (const m of ["toLocaleString", "toLocaleDateString", "toLocaleTimeString"]) {
    const real = RealDate.prototype[m];
    Object.defineProperty(RealDate.prototype, m, { value: function (locales, options) { return real.call(this, locales, pinUtc(options)); }, writable: false, configurable: false });
  }

  const realmError = (e) => new Error(e && typeof e.message === "string" ? e.message : String(e));
  const decode = (s) => JSON.parse(s);
  const optsJson = (o) => {
    if (o === undefined || o === null) return undefined;
    if (typeof o !== "object") throw new TypeError("agent(prompt, opts): opts must be an object");
    return JSON.stringify(o, (k, v) => (typeof v === "function" ? undefined : v));
  };

  // D06 lanes. "lane" is non-empty only while a combinator synchronously runs
  // a thunk or a stage for one item; every continuation after an await sees
  // "" (or the enclosing lane), so only a call made synchronously in a lane is
  // tagged, and an untagged call keeps the conservative lineage rule.
  let lane = "";
  let combinators = 0;
  const inLane = (path, f) => { const saved = lane; lane = path; try { return f(); } finally { lane = saved; } };

  async function agent(prompt, opts) {
    const myLane = lane;
    let p;
    try { p = host.agent(prompt, optsJson(opts), myLane === "" ? undefined : myLane); } catch (e) { throw realmError(e); }
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
    const base = lane + "/" + (++combinators);
    return Promise.all(thunks.map((t, i) =>
      Promise.resolve()
        .then(() => (typeof t === "function" ? inLane(base + ":" + i, t) : t))
        .catch((e) => { host.itemNull("parallel", i, 0, why(e)); return null; })));
  }

  async function pipeline(items, ...stages) {
    if (!Array.isArray(items)) throw new TypeError("pipeline(items, ...stages): items must be an array");
    checkItems("pipeline", items.length);
    for (const s of stages) if (typeof s !== "function") throw new TypeError("pipeline: every stage must be a function");
    const base = lane + "/" + (++combinators);
    return Promise.all(items.map(async (item, index) => {
      let prev = item;
      for (let s = 0; s < stages.length; s++) {
        try { const v = prev; prev = await inLane(base + ":" + index, () => stages[s](v, item, index)); }
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
