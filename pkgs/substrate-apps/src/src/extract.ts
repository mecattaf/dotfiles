/**
 * Static prompt extraction from a Claude ultracode workflow script.
 *
 * The dialect has three properties that, taken together, stop any single
 * JavaScript goal symbol from parsing one of these files:
 *   1. it opens with `export const meta = {...}`, which is module-only;
 *   2. it closes with a top-level `return {...}`, which is function-body-only;
 *   3. it uses top-level `await`, which the function-body goal rejects.
 * On top of that, `phase()`, `agent()`, `parallel()` and `pipeline()` are
 * harness builtins and the scripts import nothing, so the file is not runnable
 * either. This module therefore never parses and never evaluates. It scans.
 *
 * The scan is lexical: one pass builds a mask of the positions that are plain
 * code (not inside a string, a template literal's text, a comment or a regular
 * expression literal), and everything else keys off that mask. The source is
 * only ever read.
 */

const CODE = 1;
const NOT_CODE = 0;

/** Tokens after which a `/` begins a regular expression rather than a division. */
const REGEX_PRECEDERS = new Set([
  "(", ",", "=", ":", "[", "!", "&", "|", "?", "{", "}", ";", "+", "-", "*", "%",
  "<", ">", "~", "^",
]);

/**
 * Mark every source position as code or not-code. The interior of a template
 * literal's `${...}` substitution is code; the literal text around it is not.
 */
export function codeMask(src: string): Uint8Array {
  const mask = new Uint8Array(src.length);
  // One entry per template literal we are inside of, holding the brace depth at
  // which it opened. That is what tells a `}` closing a `${` substitution apart
  // from any other `}`.
  const tmplStack: number[] = [];
  let braceDepth = 0;
  let i = 0;
  let lastSignificant = "";

  const inTemplateText = (): boolean =>
    tmplStack.length > 0 && braceDepth === tmplStack[tmplStack.length - 1];

  while (i < src.length) {
    const c = src[i]!;
    const c2 = src[i + 1];

    if (inTemplateText()) {
      if (c === "\\") {
        mask[i++] = NOT_CODE;
        if (i < src.length) mask[i++] = NOT_CODE;
        continue;
      }
      if (c === "`") {
        mask[i++] = NOT_CODE;
        tmplStack.pop();
        lastSignificant = "str";
        continue;
      }
      if (c === "$" && c2 === "{") {
        mask[i++] = NOT_CODE;
        mask[i++] = CODE;
        braceDepth++;
        lastSignificant = "{";
        continue;
      }
      mask[i++] = NOT_CODE;
      continue;
    }

    if (c === "/" && c2 === "/") {
      while (i < src.length && src[i] !== "\n") mask[i++] = NOT_CODE;
      continue;
    }
    if (c === "/" && c2 === "*") {
      mask[i++] = NOT_CODE;
      mask[i++] = NOT_CODE;
      while (i < src.length && !(src[i] === "*" && src[i + 1] === "/")) mask[i++] = NOT_CODE;
      if (i < src.length) { mask[i++] = NOT_CODE; mask[i++] = NOT_CODE; }
      continue;
    }
    if (c === '"' || c === "'") {
      mask[i++] = NOT_CODE;
      while (i < src.length) {
        if (src[i] === "\\") { mask[i++] = NOT_CODE; if (i < src.length) mask[i++] = NOT_CODE; continue; }
        if (src[i] === c) { mask[i++] = NOT_CODE; break; }
        mask[i++] = NOT_CODE;
      }
      lastSignificant = "str";
      continue;
    }
    if (c === "`") {
      mask[i++] = NOT_CODE;
      tmplStack.push(braceDepth);
      lastSignificant = "str";
      continue;
    }
    if (c === "/" && (REGEX_PRECEDERS.has(lastSignificant) || lastSignificant === "")) {
      const startAt = i;
      mask[i++] = NOT_CODE;
      let inClass = false;
      let closed = false;
      while (i < src.length) {
        const r = src[i]!;
        if (r === "\\") { mask[i++] = NOT_CODE; if (i < src.length) mask[i++] = NOT_CODE; continue; }
        if (r === "\n") break;
        if (r === "[") inClass = true;
        else if (r === "]") inClass = false;
        else if (r === "/" && !inClass) { mask[i++] = NOT_CODE; closed = true; break; }
        mask[i++] = NOT_CODE;
      }
      if (!closed) {
        // It was not a regular expression after all. Undo and treat as code.
        for (let k = startAt; k < i; k++) mask[k] = CODE;
        i = startAt + 1;
        mask[startAt] = CODE;
        lastSignificant = "/";
        continue;
      }
      while (i < src.length && /[a-z]/.test(src[i]!)) mask[i++] = NOT_CODE;
      lastSignificant = "re";
      continue;
    }

    mask[i] = CODE;
    if (c === "{") braceDepth++;
    else if (c === "}") braceDepth--;
    if (!/\s/.test(c)) lastSignificant = c;
    i++;
  }
  return mask;
}

export interface AgentCall {
  /** Byte offset of the `a` of `agent(`. */
  readonly at: number;
  /** Source text of the first argument, verbatim. */
  readonly promptExpr: string;
  /** Source text of the options object literal, verbatim, or undefined. */
  readonly optionsExpr: string | undefined;
  /** `label` from the options object, when it is a plain string literal. */
  readonly label: string | undefined;
  /** `effort` from the options object, when it is a plain string literal. */
  readonly effort: string | undefined;
}

function isIdentChar(c: string | undefined): boolean {
  return c !== undefined && /[A-Za-z0-9_$]/.test(c);
}

/** Walk from an opening bracket to its match, honouring the code mask. */
function matchBracket(src: string, mask: Uint8Array, open: number): { close: number; commas: number[] } {
  const openCh = src[open]!;
  const closeCh = openCh === "(" ? ")" : openCh === "{" ? "}" : "]";
  let depth = 0;
  const commas: number[] = [];
  for (let i = open; i < src.length; i++) {
    if (mask[i] !== CODE) continue;
    const c = src[i]!;
    if (c === "(" || c === "{" || c === "[") depth++;
    else if (c === ")" || c === "}" || c === "]") {
      depth--;
      if (depth === 0) {
        if (c !== closeCh) return { close: -1, commas };
        return { close: i, commas };
      }
    } else if (c === "," && depth === 1) commas.push(i);
  }
  return { close: -1, commas };
}

const HEX = /^[0-9a-fA-F]+$/;

/**
 * Decode ONE escape sequence. `at` is the index of the character that follows
 * the backslash. Returns the decoded text and the index to continue from.
 *
 * A-11 of the 2026-09-23 review. The reader decoded only `n`, `t` and `r` and
 * dropped the backslash from every other escape, so `\u0041` extracted as the
 * four plain characters `u0041` and the prompt sent to a seat differed from the
 * prompt the script would have sent. Dropping the backslash happens to be the
 * RIGHT answer for `\\`, `\"`, `\'` and `\``, which is why the six real
 * records never showed it; it is wrong for every numeric escape.
 */
function decodeEscape(src: string, at: number): { text: string; next: number } {
  const n = src[at];
  if (n === undefined) return { text: "", next: at + 1 };
  switch (n) {
    case "n": return { text: "\n", next: at + 1 };
    case "t": return { text: "\t", next: at + 1 };
    case "r": return { text: "\r", next: at + 1 };
    case "b": return { text: "\b", next: at + 1 };
    case "f": return { text: "\f", next: at + 1 };
    case "v": return { text: "\v", next: at + 1 };
    case "\r":
      // A line continuation. CRLF counts as one.
      return { text: "", next: src[at + 1] === "\n" ? at + 2 : at + 1 };
    case "\n":
      return { text: "", next: at + 1 };
    case "0":
      if (!/[0-9]/.test(src[at + 1] ?? "")) return { text: "\0", next: at + 1 };
      break;
    case "x": {
      const h = src.slice(at + 1, at + 3);
      if (h.length === 2 && HEX.test(h)) {
        return { text: String.fromCharCode(parseInt(h, 16)), next: at + 3 };
      }
      break;
    }
    case "u": {
      if (src[at + 1] === "{") {
        const close = src.indexOf("}", at + 2);
        const h = close < 0 ? "" : src.slice(at + 2, close);
        if (h.length > 0 && HEX.test(h) && parseInt(h, 16) <= 0x10ffff) {
          return { text: String.fromCodePoint(parseInt(h, 16)), next: close + 1 };
        }
        break;
      }
      const h = src.slice(at + 1, at + 5);
      if (h.length === 4 && HEX.test(h)) {
        return { text: String.fromCharCode(parseInt(h, 16)), next: at + 5 };
      }
      break;
    }
    default:
      break;
  }
  // Every other escape, and every malformed numeric one, is the character
  // itself: `\q` is `q`, `\\` is a backslash, `\"` is a quote.
  return { text: n, next: at + 1 };
}

/** Read a plain string-literal value at `start` (a quote or backtick). */
function readLiteral(
  src: string,
  start: number,
): { text: string; interpolated: boolean; escapedSubstitution: boolean; end: number } | undefined {
  const q = src[start];
  if (q !== '"' && q !== "'" && q !== "`") return undefined;
  let out = "";
  let interpolated = false;
  let escapedSubstitution = false;
  let i = start + 1;
  while (i < src.length) {
    const c = src[i]!;
    if (c === "\\") {
      // A-11. `\${NAME}` in a template evaluates to the literal characters
      // `${NAME}`, but the reader dropped the backslash and `substituteConsts`
      // then replaced what was left, so the prompt said the const's VALUE
      // where the script would have passed the expression verbatim. The two
      // are indistinguishable downstream, so the literal is FLAGGED here and
      // the prompt is refused rather than silently wrong.
      if (q === "`" && src[i + 1] === "$" && src[i + 2] === "{") {
        escapedSubstitution = true;
        out += "${";
        i += 3;
        continue;
      }
      const dec = decodeEscape(src, i + 1);
      out += dec.text;
      i = dec.next;
      continue;
    }
    if (c === q) return { text: out, interpolated, escapedSubstitution, end: i };
    if (q === "`" && c === "$" && src[i + 1] === "{") {
      interpolated = true;
      // Copy the substitution through verbatim; resolveConsts may replace it.
      let depth = 0;
      let j = i + 1;
      for (; j < src.length; j++) {
        if (src[j] === "{") depth++;
        else if (src[j] === "}") { depth--; if (depth === 0) break; }
      }
      out += src.slice(i, j + 1);
      i = j + 1;
      continue;
    }
    out += c;
    i++;
  }
  return undefined;
}

/**
 * Collect top-level `const IDENT = <string literal>` bindings, in declaration
 * order, resolving each one's own `${IDENT}` against what is already known.
 */
export function topLevelStringConsts(src: string, mask: Uint8Array): Map<string, string> {
  const consts = new Map<string, string>();
  const re = /\bconst\s+([A-Za-z_$][A-Za-z0-9_$]*)\s*=\s*/g;
  let m: RegExpExecArray | null;
  while ((m = re.exec(src)) !== null) {
    if (mask[m.index] !== CODE) continue;
    const valueAt = m.index + m[0].length;
    const lit = readLiteral(src, valueAt);
    if (lit === undefined) continue;
    // A-11: a const whose literal carries an escaped substitution is left
    // UNBOUND, so a prompt naming it is refused by the unresolved-substitution
    // check rather than silently carrying the wrong text.
    if (lit.escapedSubstitution) continue;
    consts.set(m[1]!, substituteConsts(lit.text, consts));
  }
  return consts;
}

/** Replace `${IDENT}` with a known binding. Anything else is left verbatim. */
export function substituteConsts(text: string, consts: Map<string, string>): string {
  return text.replace(/\$\{([A-Za-z_$][A-Za-z0-9_$]*)\}/g, (whole, name: string) =>
    consts.has(name) ? consts.get(name)! : whole,
  );
}

/** Find every `agent(...)` call that sits at a code position. */
export function scanAgentCalls(src: string): AgentCall[] {
  const mask = codeMask(src);
  const consts = topLevelStringConsts(src, mask);
  const calls: AgentCall[] = [];
  const re = /\bagent\s*\(/g;
  let m: RegExpExecArray | null;
  while ((m = re.exec(src)) !== null) {
    if (mask[m.index] !== CODE) continue;
    if (isIdentChar(src[m.index - 1]) || src[m.index - 1] === ".") continue;
    const open = m.index + m[0].length - 1;
    const { close, commas } = matchBracket(src, mask, open);
    if (close < 0) continue;
    const firstComma = commas.length > 0 ? commas[0]! : close;
    const promptExpr = src.slice(open + 1, firstComma).trim();
    const optionsExpr = commas.length > 0 ? src.slice(firstComma + 1, close).trim() : undefined;

    let label: string | undefined;
    let effort: string | undefined;
    if (optionsExpr !== undefined && optionsExpr.startsWith("{")) {
      const objStart = firstComma + 1 + (src.slice(firstComma + 1).length - src.slice(firstComma + 1).trimStart().length);
      label = readOptionString(src, mask, objStart, "label");
      effort = readOptionString(src, mask, objStart, "effort");
    }
    calls.push({ at: m.index, promptExpr, optionsExpr, label, effort });
  }
  return calls.map((c) => ({ ...c, promptExpr: c.promptExpr }));
}

/** Read `key: '<literal>'` at depth 1 of the object literal opening at objStart. */
function readOptionString(src: string, mask: Uint8Array, objStart: number, key: string): string | undefined {
  if (src[objStart] !== "{") return undefined;
  const { close } = matchBracket(src, mask, objStart);
  if (close < 0) return undefined;
  let depth = 0;
  for (let i = objStart; i < close; i++) {
    if (mask[i] !== CODE) continue;
    const c = src[i]!;
    if (c === "{" || c === "(" || c === "[") { depth++; continue; }
    if (c === "}" || c === ")" || c === "]") { depth--; continue; }
    if (depth !== 1) continue;
    if (!src.startsWith(key, i)) continue;
    if (isIdentChar(src[i - 1])) continue;
    let j = i + key.length;
    while (j < close && /\s/.test(src[j]!)) j++;
    if (src[j] !== ":") continue;
    j++;
    while (j < close && /\s/.test(src[j]!)) j++;
    const lit = readLiteral(src, j);
    if (lit === undefined || lit.interpolated) return undefined;
    return lit.text;
  }
  return undefined;
}

export type PromptResolution =
  | { readonly ok: true; readonly prompt: string }
  | { readonly ok: false; readonly reason: string };

/**
 * Exactly the pattern `substituteConsts` substitutes. Matching the two makes the
 * check below say precisely one thing: a substitution this scanner would have
 * replaced, had the binding been known, is still sitting in the text.
 */
const SUBSTITUTION = /\$\{[A-Za-z_$][A-Za-z0-9_$]*\}/;

/**
 * CR-01 of the 2026-09-23 evals. `SUBSTITUTION` matches a bare identifier only,
 * so `${a.b}`, `${f(x)}` and `${JSON.stringify(x, null, 2)}` survived the guard
 * and 82 real prompts were marked resolved while still carrying expression
 * text. After the script's own consts are applied, ANY surviving `${` is a
 * substitution this scanner did not evaluate, and the prompt is refused.
 */
const ANY_SUBSTITUTION = /\$\{/;

/**
 * Substitute, then decide whether what came out is a PROMPT.
 *
 * A-06 and A-09 of the 2026-09-23 review. `promptResolved` is the bit the
 * admission pass filters on, so it has to mean "usable", not "a literal was
 * found". Two things were being called resolved and were not:
 *
 *  - a prompt in which a `${...}` substitution SURVIVED, which on the six real
 *    records was 5 of the 11 resolved prompts. A seat would have been spent
 *    sending a model the characters `${AREAS}`.
 *  - a prompt that is empty or whitespace only, which spends a seat on nothing.
 *
 * Refusing both is what the rest of the pipeline already promises: an
 * unresolved item is recorded with its reason, admitted nowhere, and counted.
 */
function finishPrompt(
  text: string,
  consts: Map<string, string>,
  escapedSubstitution = false,
): PromptResolution {
  if (escapedSubstitution) {
    return {
      ok: false,
      reason:
        "the literal carries an escaped substitution (\\${...}), whose verbatim text this extractor cannot tell from a real substitution after decoding",
    };
  }
  const prompt = substituteConsts(text, consts);
  const left = SUBSTITUTION.exec(prompt);
  if (left !== null) {
    return {
      ok: false,
      reason: `the prompt still carries the unresolved substitution ${left[0]} after the script's own top-level consts were applied`,
    };
  }
  const anyLeft = ANY_SUBSTITUTION.exec(prompt);
  if (anyLeft !== null) {
    const tail = prompt.slice(anyLeft.index, anyLeft.index + 40);
    return {
      ok: false,
      reason: `the prompt still carries an unevaluated substitution ${JSON.stringify(tail)} (a member, call or other expression this scanner never evaluates)`,
    };
  }
  if (prompt.trim() === "") {
    return { ok: false, reason: "the prompt is empty or whitespace only" };
  }
  return { ok: true, prompt };
}

/**
 * Resolve one label to one prompt. Matching is by label, never by position.
 * Zero matches and more than one match are both refusals, and the caller must
 * admit nothing for the item. `promptPreview` is truncated and is never used.
 */
export function resolvePromptForLabel(src: string, label: string): PromptResolution {
  const mask = codeMask(src);
  const consts = topLevelStringConsts(src, mask);
  const calls = scanAgentCalls(src).filter((c) => c.label === label);
  if (calls.length === 0) {
    return { ok: false, reason: `no agent() call carries label ${JSON.stringify(label)}` };
  }
  if (calls.length > 1) {
    return { ok: false, reason: `${calls.length} agent() calls carry label ${JSON.stringify(label)}` };
  }
  const call = calls[0]!;
  const whole = wholeLiteralArgument(src, call);
  if (!whole.ok) return whole;
  return finishPrompt(whole.lit.text, consts, whole.lit.escapedSubstitution);
}

/**
 * Read the first argument as ONE whole literal, or say why not.
 *
 * CR-02 of the 2026-09-23 evals. `readLiteral` reads the first literal and
 * stops at its closing quote, so `agent(\`head\` + draft, ...)` resolved to
 * `head` alone and the upstream draft was dropped without a word
 * (wf_acfbcc7c-8c5 verify-write: 1197 of 38695 chars). The literal must END
 * where the argument ends; anything after it (`+ expr`, `.trim()`, a ternary)
 * is an expression this scanner does not evaluate.
 */
function wholeLiteralArgument(
  src: string,
  call: AgentCall,
): { ok: true; lit: NonNullable<ReturnType<typeof readLiteral>> } | { ok: false; reason: string } {
  const start = indexOfFirstLiteral(src, call);
  const lit = readLiteral(src, start);
  if (lit === undefined) {
    return { ok: false, reason: "the first argument of the matching agent() call is not a string literal" };
  }
  const literalLength = lit.end - start + 1;
  if (literalLength !== call.promptExpr.length) {
    const rest = call.promptExpr.slice(Math.max(0, literalLength)).trim().slice(0, 40);
    return {
      ok: false,
      reason: `the first argument is a literal followed by an expression (${JSON.stringify(rest)}); only a whole literal argument resolves`,
    };
  }
  return { ok: true, lit };
}

/** Offset of the first argument's opening quote, or -1. */
function indexOfFirstLiteral(src: string, call: AgentCall): number {
  const open = src.indexOf("(", call.at);
  let i = open + 1;
  while (i < src.length && /\s/.test(src[i]!)) i++;
  return i;
}

/** The effort option of the single agent() call carrying this label, if any. */
export function resolveEffortForLabel(src: string, label: string): string | undefined {
  const calls = scanAgentCalls(src).filter((c) => c.label === label);
  return calls.length === 1 ? calls[0]!.effort : undefined;
}

export interface LabelIndex {
  readonly consts: Map<string, string>;
  readonly byLabel: Map<string, AgentCall[]>;
  readonly src: string;
}

/** Scan a script once and index its agent() calls by label. */
export function buildLabelIndex(src: string): LabelIndex {
  const mask = codeMask(src);
  const consts = topLevelStringConsts(src, mask);
  const byLabel = new Map<string, AgentCall[]>();
  for (const call of scanAgentCalls(src)) {
    if (call.label === undefined) continue;
    const bucket = byLabel.get(call.label);
    if (bucket === undefined) byLabel.set(call.label, [call]);
    else bucket.push(call);
  }
  return { consts, byLabel, src };
}

/** Resolve one label against a prebuilt index. Same rules as resolvePromptForLabel. */
export function resolveFromIndex(idx: LabelIndex, label: string): PromptResolution & { effort?: string } {
  const calls = idx.byLabel.get(label) ?? [];
  if (calls.length === 0) {
    return { ok: false, reason: `no agent() call carries label ${JSON.stringify(label)}` };
  }
  if (calls.length > 1) {
    return { ok: false, reason: `${calls.length} agent() calls carry label ${JSON.stringify(label)}` };
  }
  const call = calls[0]!;
  const whole = wholeLiteralArgument(idx.src, call);
  if (!whole.ok) return whole;
  const finished = finishPrompt(whole.lit.text, idx.consts, whole.lit.escapedSubstitution);
  if (!finished.ok) return finished;
  const out: PromptResolution & { effort?: string } = { ok: true, prompt: finished.prompt };
  if (call.effort !== undefined) out.effort = call.effort;
  return out;
}
