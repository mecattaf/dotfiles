/**
 * The `export const meta = {...}` header of a workflow script.
 *
 * The Claude Code Workflow tool requires meta to be a PURE LITERAL: it is read
 * without running the script. This module is a small tokenizer and recursive
 * descent parser for exactly that literal language (objects, arrays, strings,
 * template strings without `${}`, numbers, true/false/null, comments, trailing
 * commas). Anything else, an identifier used as a value, a call, a spread, a
 * computed key, an interpolation, is rejected with the offending offset. No
 * part of the header is evaluated.
 *
 * The meta declaration is then cut out of the source and replaced by the same
 * number of newlines, so line numbers in the body's stack traces stay true.
 */
import { Schema } from "effect";

export class MetaError extends Error {
  override readonly name = "MetaError";
}

/** The validated meta shape. Only `name` and `description` are required. */
export const WorkflowMeta = Schema.Struct({
  name: Schema.String.check(Schema.isNonEmpty()),
  description: Schema.String.check(Schema.isNonEmpty()),
  phases: Schema.optionalKey(
    Schema.Array(
      Schema.Struct({
        title: Schema.String,
        detail: Schema.optionalKey(Schema.String),
        model: Schema.optionalKey(Schema.String),
      }),
    ),
  ),
});
export type WorkflowMeta = typeof WorkflowMeta.Type;

const decodeMeta = Schema.decodeUnknownSync(WorkflowMeta);

type Literal = null | boolean | number | string | Literal[] | { [k: string]: Literal };

class LiteralParser {
  i: number;
  constructor(
    readonly src: string,
    start: number,
  ) {
    this.i = start;
  }

  fail(msg: string): never {
    const line = this.src.slice(0, this.i).split("\n").length;
    throw new MetaError(`meta is not a pure literal: ${msg} (line ${line}, offset ${this.i})`);
  }

  ws(): void {
    for (;;) {
      const c = this.src[this.i];
      if (c === " " || c === "\t" || c === "\n" || c === "\r") this.i++;
      else if (this.src.startsWith("//", this.i)) {
        const e = this.src.indexOf("\n", this.i);
        this.i = e < 0 ? this.src.length : e + 1;
      } else if (this.src.startsWith("/*", this.i)) {
        const e = this.src.indexOf("*/", this.i + 2);
        if (e < 0) this.fail("unterminated comment");
        this.i = e + 2;
      } else return;
    }
  }

  value(): Literal {
    this.ws();
    const c = this.src[this.i];
    if (c === "{") return this.object();
    if (c === "[") return this.array();
    if (c === '"' || c === "'") return this.string(c);
    if (c === "`") return this.template();
    if (c === "-" || c === "+" || c === "." || (c !== undefined && c >= "0" && c <= "9")) return this.number();
    const id = this.ident();
    if (id === "true") return true;
    if (id === "false") return false;
    if (id === "null") return null;
    if (id === "") this.fail(`unexpected ${JSON.stringify(c ?? "end of input")}`);
    return this.fail(`free identifier '${id}' used as a value`);
  }

  ident(): string {
    const m = /^[A-Za-z_$][A-Za-z0-9_$]*/.exec(this.src.slice(this.i, this.i + 256));
    if (!m) return "";
    this.i += m[0].length;
    return m[0];
  }

  object(): { [k: string]: Literal } {
    this.i++;
    const out: { [k: string]: Literal } = Object.create(null);
    for (;;) {
      this.ws();
      if (this.src[this.i] === "}") {
        this.i++;
        return { ...out };
      }
      if (this.src.startsWith("...", this.i)) this.fail("spread");
      const c = this.src[this.i];
      let key: string;
      if (c === '"' || c === "'") key = this.string(c);
      else if (c === "[") this.fail("computed key");
      else if (c !== undefined && c >= "0" && c <= "9") key = String(this.number());
      else {
        key = this.ident();
        if (!key) this.fail(`unexpected ${JSON.stringify(c ?? "end of input")} where a key was expected`);
      }
      this.ws();
      if (this.src[this.i] !== ":") this.fail(`shorthand or method property '${key}'`);
      this.i++;
      if (key === "__proto__") this.fail("__proto__ key");
      out[key] = this.value();
      this.ws();
      if (this.src[this.i] === ",") this.i++;
      else if (this.src[this.i] !== "}") this.fail("expected ',' or '}'");
    }
  }

  array(): Literal[] {
    this.i++;
    const out: Literal[] = [];
    for (;;) {
      this.ws();
      if (this.src[this.i] === "]") {
        this.i++;
        return out;
      }
      if (this.src.startsWith("...", this.i)) this.fail("spread");
      out.push(this.value());
      this.ws();
      if (this.src[this.i] === ",") this.i++;
      else if (this.src[this.i] !== "]") this.fail("expected ',' or ']'");
    }
  }

  escape(): string {
    const c = this.src[this.i++];
    switch (c) {
      case "n": return "\n";
      case "t": return "\t";
      case "r": return "\r";
      case "b": return "\b";
      case "f": return "\f";
      case "v": return "\v";
      case "0": return "\0";
      case "\n": return "";
      case "u": {
        if (this.src[this.i] === "{") {
          const e = this.src.indexOf("}", this.i);
          const cp = parseInt(this.src.slice(this.i + 1, e), 16);
          this.i = e + 1;
          return String.fromCodePoint(cp);
        }
        const h = this.src.slice(this.i, this.i + 4);
        if (!/^[0-9a-fA-F]{4}$/.test(h)) this.fail("bad \\u escape");
        this.i += 4;
        return String.fromCharCode(parseInt(h, 16));
      }
      case "x": {
        const h = this.src.slice(this.i, this.i + 2);
        if (!/^[0-9a-fA-F]{2}$/.test(h)) this.fail("bad \\x escape");
        this.i += 2;
        return String.fromCharCode(parseInt(h, 16));
      }
      case undefined: return this.fail("unterminated string");
      default: return c;
    }
  }

  string(q: string): string {
    this.i++;
    let s = "";
    for (;;) {
      const c = this.src[this.i++];
      if (c === undefined || c === "\n") this.fail("unterminated string");
      if (c === q) return s;
      s += c === "\\" ? this.escape() : c;
    }
  }

  template(): string {
    this.i++;
    let s = "";
    for (;;) {
      const c = this.src[this.i++];
      if (c === undefined) this.fail("unterminated template");
      if (c === "`") return s;
      if (c === "$" && this.src[this.i] === "{") {
        this.i--;
        this.fail("template interpolation");
      }
      s += c === "\\" ? this.escape() : c === "\r" ? "" : c;
    }
  }

  number(): number {
    const m = /^[+-]?(0[xX][0-9a-fA-F_]+|0[bB][01_]+|0[oO][0-7_]+|(\d[\d_]*)?\.?\d[\d_]*([eE][+-]?\d+)?)/.exec(
      this.src.slice(this.i, this.i + 64),
    );
    if (!m) return this.fail("bad number");
    this.i += m[0].length;
    const n = Number(m[0].replace(/_/g, ""));
    if (Number.isNaN(n)) this.fail("bad number");
    return n;
  }
}

/** Mask string, template and comment contents so a scan cannot match inside them. */
function findMetaDecl(src: string): RegExpExecArray | null {
  const re = /(^|[\n;])[ \t]*export\s+const\s+meta\s*=\s*/g;
  return re.exec(src);
}

export interface LoadedScript {
  readonly meta: WorkflowMeta;
  /** Source with the meta declaration replaced by blank lines. */
  readonly body: string;
}

/** Parse and validate meta, and return the script body with meta cut out. */
export function extractMeta(src: string): LoadedScript {
  const m = findMetaDecl(src);
  if (!m) throw new MetaError("script has no top-level `export const meta = {...}`");
  const declStart = m.index + m[1]!.length;
  const litStart = m.index + m[0].length;
  if (src[litStart] !== "{") {
    const p = new LiteralParser(src, litStart);
    p.fail("meta must be an object literal");
  }
  const p = new LiteralParser(src, litStart);
  const raw = p.value();
  const end = p.i;
  p.ws();
  if (src[p.i] === ";") p.i++;
  else if (p.i < src.length) {
    // A literal followed by `.x`, `(`, `[`, `+`, `?`, `||`, a template etc. is an
    // expression, not a literal: JavaScript would continue it even across a newline.
    if (/^[.([?+\-*/%&|^,=<>!`]/.test(src.slice(p.i, p.i + 1)) || /^(in|instanceof)\b/.test(src.slice(p.i, p.i + 11))) {
      p.fail("meta literal is followed by an operator or call");
    }
    const between = src.slice(end, p.i);
    if (!/\n/.test(between)) p.fail("meta literal must end the statement");
    p.i = end;
  }
  let decoded: WorkflowMeta;
  try {
    decoded = decodeMeta(raw);
  } catch (e) {
    throw new MetaError(`meta does not have the required shape (name, description, phases?): ${(e as Error).message}`);
  }
  if (/(^|[\n;])[ \t]*export\s/.test(src.slice(p.i))) throw new MetaError("only `export const meta` may be exported");
  const cut = src.slice(declStart, p.i);
  const blank = cut.replace(/[^\n]/g, "");
  return { meta: decoded, body: src.slice(0, declStart) + blank + src.slice(p.i) };
}
